defmodule RepomaticApt.Web.UiTest do
  use ExUnit.Case

  alias RepomaticApt.MetadataStore
  alias RepomaticApt.Test.DebHelper

  setup do
    MetadataStore.clear()

    tmp =
      Path.join(System.tmp_dir!(), "repomatic_apt_ui_test_#{:erlang.unique_integer([:positive])}")

    File.mkdir_p!(tmp)
    Application.put_env(:repomatic_apt, :repo_root, tmp)

    Application.put_env(:repomatic_apt, :distributions, [
      %{
        suite: "stable",
        codename: "stable",
        architectures: ["amd64"],
        components: ["main"],
        origin: "RepomaticApt",
        label: "RepomaticApt"
      }
    ])

    on_exit(fn -> File.rm_rf!(tmp) end)
    :ok
  end

  defp call(conn) do
    RepomaticApt.Web.Router.call(conn, RepomaticApt.Web.Router.init([]))
  end

  test "GET /ui shows distributions overview" do
    conn = Plug.Test.conn(:get, "/ui") |> call()
    assert conn.status == 200
    assert conn.resp_body =~ "Distributions"
    assert conn.resp_body =~ "stable"
    assert conn.resp_body =~ "RepomaticApt"
    assert conn.resp_body =~ "Setup Instructions"
  end

  test "GET /ui/setup shows setup instructions" do
    conn = Plug.Test.conn(:get, "/ui/setup") |> call()
    assert conn.status == 200
    assert conn.resp_body =~ "Setup Instructions"
    assert conn.resp_body =~ "key.gpg"
    assert conn.resp_body =~ "sources.list"
    assert conn.resp_body =~ "apt update"
  end

  test "GET /ui/:distribution shows components and architectures" do
    conn = Plug.Test.conn(:get, "/ui/stable") |> call()
    assert conn.status == 200
    assert conn.resp_body =~ "stable"
    assert conn.resp_body =~ "main"
    assert conn.resp_body =~ "amd64"
  end

  test "GET /ui/:dist/:comp/:arch shows package list" do
    deb = DebHelper.build_deb("ui-test", "1.0", "amd64")

    Plug.Test.conn(:put, "/api/packages/stable/main", deb)
    |> Plug.Conn.put_req_header("content-type", "application/octet-stream")
    |> call()

    conn = Plug.Test.conn(:get, "/ui/stable/main/amd64") |> call()
    assert conn.status == 200
    assert conn.resp_body =~ "ui-test"
    assert conn.resp_body =~ "1.0"
  end

  test "GET /ui/:dist/:comp/:arch/:name/:version shows package detail" do
    deb = DebHelper.build_deb("detail-test", "2.0", "amd64")

    Plug.Test.conn(:put, "/api/packages/stable/main", deb)
    |> Plug.Conn.put_req_header("content-type", "application/octet-stream")
    |> call()

    conn = Plug.Test.conn(:get, "/ui/stable/main/amd64/detail-test/2.0") |> call()
    assert conn.status == 200
    assert conn.resp_body =~ "detail-test"
    assert conn.resp_body =~ "2.0"
    assert conn.resp_body =~ "SHA256"
    assert conn.resp_body =~ "Download .deb"
  end

  test "package detail for nonexistent package shows not found" do
    conn = Plug.Test.conn(:get, "/ui/stable/main/amd64/nope/1.0") |> call()
    assert conn.status == 200
    assert conn.resp_body =~ "Package not found"
  end

  test "HTML responses have correct content type" do
    conn = Plug.Test.conn(:get, "/ui") |> call()
    {_, content_type} = List.keyfind(conn.resp_headers, "content-type", 0)
    assert content_type =~ "text/html"
  end

  test "HTML escapes user-provided content" do
    deb =
      DebHelper.build_deb([
        {"Package", "xss-test"},
        {"Version", "1.0"},
        {"Architecture", "amd64"},
        {"Maintainer", "<script>alert(1)</script>"},
        {"Description", "safe"}
      ])

    Plug.Test.conn(:put, "/api/packages/stable/main", deb)
    |> Plug.Conn.put_req_header("content-type", "application/octet-stream")
    |> call()

    conn = Plug.Test.conn(:get, "/ui/stable/main/amd64/xss-test/1.0") |> call()
    refute conn.resp_body =~ "<script>"
    assert conn.resp_body =~ "&lt;script&gt;"
  end
end
