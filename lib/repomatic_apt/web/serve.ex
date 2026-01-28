defmodule RepomaticApt.Web.Serve do
  @moduledoc """
  File serving utility with path traversal protection.
  """

  import Plug.Conn

  @spec send_repo_file(Plug.Conn.t(), String.t()) :: Plug.Conn.t()
  def send_repo_file(conn, relative_path) do
    # Reject path traversal
    if String.contains?(relative_path, "..") do
      send_resp(conn, 400, "Invalid path")
    else
      full_path = Path.join(RepomaticApt.Config.repo_root(), relative_path)

      if File.exists?(full_path) do
        conn
        |> put_resp_content_type(content_type(relative_path))
        |> send_file(200, full_path)
      else
        send_resp(conn, 404, "Not found")
      end
    end
  end

  defp content_type(path) do
    case Path.extname(path) do
      ".gz" -> "application/gzip"
      ".deb" -> "application/vnd.debian.binary-package"
      ".gpg" -> "application/pgp-signature"
      _ -> "text/plain"
    end
  end
end
