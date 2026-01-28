defmodule RepomaticApt.Web.Router do
  use Plug.Router

  plug(:match)
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

  match _ do
    send_resp(conn, 404, "Not found")
  end
end
