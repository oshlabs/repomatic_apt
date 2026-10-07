defmodule RepomaticApt.Web.Api do
  use Plug.Router

  require Logger

  plug(:match)
  plug(:authorize)
  plug(:dispatch)

  get "/key/public" do
    case RepomaticApt.Repo.get_public_key() do
      nil ->
        json(conn, 404, %{error: "No signing key configured"})

      pubkey ->
        conn
        |> put_resp_content_type("application/pgp-keys")
        |> send_resp(200, pubkey)
    end
  end

  get "/key/private" do
    case RepomaticApt.Config.signing_key() do
      nil ->
        json(conn, 404, %{error: "No signing key configured"})

      key ->
        conn
        |> put_resp_content_type("application/octet-stream")
        |> put_resp_header("content-disposition", "attachment; filename=\"signing_key.etf\"")
        |> send_resp(200, RepomaticApt.Gpg.Key.export_etf(key))
    end
  end

  put "/:distribution/:component/bulk" do
    max_size = RepomaticApt.Config.max_upload_size()

    RepomaticApt.Archive.with_tmp_dir(fn tmp_dir ->
      archive_path = Path.join(tmp_dir, "upload.archive")

      case spool_body(conn, max_size, archive_path) do
        {:ok, size, conn} ->
          Logger.info("Bulk upload received: #{size} bytes for #{distribution}/#{component}")
          bulk_add(conn, distribution, component, archive_path, Path.join(tmp_dir, "debs"))

        {:error, :too_large, conn} ->
          json(conn, 413, %{error: "Upload exceeds maximum size of #{max_size} bytes"})
      end
    end)
  end

  defp bulk_add(conn, distribution, component, archive_path, extract_dir) do
    case RepomaticApt.Archive.extract_debs(archive_path, extract_dir) do
      {:error, :unsupported_archive_format} ->
        json(conn, 400, %{
          error: "Unsupported archive format. Supported: .tar.gz, .zip"
        })

      {:error, {:extract_failed, reason}} ->
        json(conn, 400, %{error: "Failed to extract archive: #{inspect(reason)}"})

      {:ok, []} ->
        json(conn, 400, %{error: "Archive contains no .deb files"})

      {:ok, deb_entries} ->
        case RepomaticApt.Repo.add_packages_bulk(distribution, component, deb_entries) do
          {:ok, packages} ->
            json(conn, 201, %{
              count: length(packages),
              packages:
                Enum.map(packages, fn pkg ->
                  %{
                    package: pkg.name,
                    version: pkg.version,
                    architecture: pkg.architecture,
                    filename: pkg.filename,
                    sha256: pkg.sha256
                  }
                end)
            })

          {:error, failures} ->
            json(conn, 400, %{
              error: "Some packages failed validation",
              failures:
                Enum.map(failures, fn {file, reason} ->
                  %{file: file, reason: to_string(reason)}
                end)
            })
        end
    end
  end

  put "/:distribution/:component" do
    max_size = RepomaticApt.Config.max_upload_size()

    case read_full_body(conn, max_size) do
      {:ok, body, conn} ->
        Logger.info("Upload received: #{byte_size(body)} bytes for #{distribution}/#{component}")

        case RepomaticApt.Repo.add_package(distribution, component, body) do
          {:ok, pkg} ->
            json(conn, 201, %{
              package: pkg.name,
              version: pkg.version,
              architecture: pkg.architecture,
              filename: pkg.filename,
              sha256: pkg.sha256
            })

          {:error, reason} ->
            json(conn, 400, %{error: to_string(reason)})
        end

      {:error, :too_large} ->
        json(conn, 413, %{error: "Upload exceeds maximum size of #{max_size} bytes"})
    end
  end

  delete "/:distribution/:component/:name/:version/:arch" do
    case RepomaticApt.Repo.remove_package(distribution, component, name, version, arch) do
      :ok -> json(conn, 200, %{deleted: true})
      {:error, :not_found} -> json(conn, 404, %{error: "Package not found"})
    end
  end

  get "/:distribution/:component" do
    conn = Plug.Conn.fetch_query_params(conn)
    arch = conn.query_params["arch"]
    packages = RepomaticApt.Repo.list_packages(distribution, component, arch)

    json(conn, 200, %{
      packages:
        Enum.map(packages, fn pkg ->
          %{name: pkg.name, version: pkg.version, architecture: pkg.architecture}
        end)
    })
  end

  match _ do
    send_resp(conn, 404, "Not found")
  end

  defp authorize(conn, _opts) do
    case RepomaticApt.Config.api_token() do
      nil ->
        conn

      expected_token ->
        case Plug.Conn.get_req_header(conn, "authorization") do
          ["Bearer " <> token] when token == expected_token ->
            conn

          _ ->
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(401, Jason.encode!(%{error: "Unauthorized"}))
            |> halt()
        end
    end
  end

  defp json(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end

  # Stream the request body to `path` in 1 MB chunks, never holding more than
  # one chunk in memory. Stops reading as soon as `max_size` is exceeded.
  defp spool_body(conn, max_size, path) do
    File.open!(path, [:write, :binary, :raw], fn io ->
      spool_chunks(conn, max_size, io, 0)
    end)
  end

  defp spool_chunks(conn, max_size, io, written) do
    {status, chunk, conn} = Plug.Conn.read_body(conn, length: 1_000_000)
    written = written + byte_size(chunk)

    cond do
      written > max_size ->
        {:error, :too_large, conn}

      status == :ok ->
        :ok = IO.binwrite(io, chunk)
        {:ok, written, conn}

      true ->
        :ok = IO.binwrite(io, chunk)
        spool_chunks(conn, max_size, io, written)
    end
  end

  defp read_full_body(conn, max_size, acc \\ <<>>) do
    case Plug.Conn.read_body(conn, length: 10_000_000) do
      {:ok, body, conn} ->
        total = acc <> body

        if byte_size(total) > max_size do
          {:error, :too_large}
        else
          {:ok, total, conn}
        end

      {:more, partial, conn} ->
        total = acc <> partial

        if byte_size(total) > max_size do
          {:error, :too_large}
        else
          read_full_body(conn, max_size, total)
        end
    end
  end
end
