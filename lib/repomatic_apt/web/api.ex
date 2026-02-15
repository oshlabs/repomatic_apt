defmodule RepomaticApt.Web.Api do
  use Plug.Router

  require Logger

  import RepomaticCommon.Web.ApiHelpers, only: [read_full_body: 2, json: 3]

  plug(:match)
  plug(:authorize)
  plug(:dispatch)

  put "/packages/:distribution/:component/bulk" do
    max_size = RepomaticApt.Config.max_upload_size()

    case read_full_body(conn, max_size) do
      {:ok, body, conn} ->
        Logger.info(
          "Bulk upload received: #{byte_size(body)} bytes for #{distribution}/#{component}"
        )

        case RepomaticApt.Archive.extract_debs(body) do
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

      {:error, :too_large} ->
        json(conn, 413, %{error: "Upload exceeds maximum size of #{max_size} bytes"})
    end
  end

  put "/packages/:distribution/:component" do
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

  delete "/packages/:distribution/:component/:name/:version/:arch" do
    :ok = RepomaticApt.Repo.remove_package(distribution, component, name, version, arch)
    json(conn, 200, %{deleted: true})
  end

  get "/packages/:distribution/:component" do
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
    RepomaticCommon.Web.ApiHelpers.authorize(conn, RepomaticApt.Config.api_token())
  end
end
