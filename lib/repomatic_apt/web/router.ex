defmodule RepomaticApt.Web.Router do
  use Plug.Router

  alias RepomaticApt.Config

  plug(:match)
  plug(:authorize_read)
  plug(:dispatch)

  forward("/api", to: RepomaticApt.Web.Api)
  forward("/ui", to: RepomaticApt.Web.Ui)

  get "/healthz" do
    send_resp(conn, 200, Jason.encode!(%{status: "ok"}))
  end

  get "/dists/*path" do
    RepomaticApt.Web.Serve.send_repo_file(conn, Path.join(["dists" | path]))
  end

  get "/pool/*path" do
    RepomaticApt.Web.Serve.send_repo_file(conn, Path.join(["pool" | path]))
  end

  get "/key.gpg" do
    case RepomaticApt.Repo.get_public_key() do
      nil ->
        send_resp(conn, 404, "No signing key configured")

      pubkey ->
        conn
        |> put_resp_content_type("application/pgp-keys")
        |> send_resp(200, pubkey)
    end
  end

  get "/" do
    conn
    |> put_resp_header("location", "/ui")
    |> send_resp(302, "")
  end

  match _ do
    send_resp(conn, 404, "Not found")
  end

  defp authorize_read(conn, _opts) do
    token = Config.ro_token()

    cond do
      is_nil(token) ->
        conn

      match?(["healthz"], conn.path_info) ->
        conn

      match?(["api" | _], conn.path_info) ->
        conn

      true ->
        case Plug.BasicAuth.parse_basic_auth(conn) do
          {_user, ^token} ->
            conn

          _ ->
            conn
            |> put_resp_header("www-authenticate", ~s(Basic realm="RepomaticApt"))
            |> send_resp(401, "Unauthorized")
            |> halt()
        end
    end
  end
end
