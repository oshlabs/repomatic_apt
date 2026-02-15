defmodule RepomaticApt.Web.Serve do
  @moduledoc """
  File serving for APT repository files.
  Delegates to `RepomaticCommon.Web.Serve`.
  """

  @content_types %{
    ".deb" => "application/vnd.debian.binary-package",
    ".gpg" => "application/pgp-signature"
  }

  @spec send_repo_file(Plug.Conn.t(), String.t()) :: Plug.Conn.t()
  def send_repo_file(conn, relative_path) do
    backend = RepomaticApt.Config.backend()
    RepomaticCommon.Web.Serve.send_repo_file(conn, relative_path, backend, @content_types)
  end
end
