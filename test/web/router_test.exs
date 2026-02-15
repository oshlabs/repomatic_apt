defmodule RepomaticApt.Web.RouterTest do
  use ExUnit.Case

  alias RepomaticApt.MetadataStore
  alias RepomaticApt.Test.DebHelper

  setup do
    MetadataStore.clear()

    tmp =
      Path.join(
        System.tmp_dir!(),
        "repomatic_apt_web_test_#{:erlang.unique_integer([:positive])}"
      )

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
    %{repo_root: tmp}
  end

  defp call(conn) do
    RepomaticApt.Web.Router.call(conn, RepomaticApt.Web.Router.init([]))
  end

  test "PUT /api/packages uploads a deb and returns JSON" do
    deb = DebHelper.build_deb("hello", "1.0-1", "amd64")

    conn =
      Plug.Test.conn(:put, "/api/packages/stable/main", deb)
      |> Plug.Conn.put_req_header("content-type", "application/octet-stream")
      |> call()

    assert conn.status == 201
    body = Jason.decode!(conn.resp_body)
    assert body["package"] == "hello"
    assert body["version"] == "1.0-1"
    assert body["architecture"] == "amd64"
    assert body["sha256"] != nil
    assert body["filename"] =~ "pool/main/h/hello/"
  end

  test "GET /api/packages lists packages" do
    deb = DebHelper.build_deb("test-pkg", "1.0", "amd64")

    Plug.Test.conn(:put, "/api/packages/stable/main", deb)
    |> Plug.Conn.put_req_header("content-type", "application/octet-stream")
    |> call()

    conn =
      Plug.Test.conn(:get, "/api/packages/stable/main?arch=amd64")
      |> call()

    assert conn.status == 200
    body = Jason.decode!(conn.resp_body)
    assert length(body["packages"]) == 1
    assert hd(body["packages"])["name"] == "test-pkg"
  end

  test "DELETE /api/packages removes a package" do
    deb = DebHelper.build_deb("removeme", "1.0", "amd64")

    Plug.Test.conn(:put, "/api/packages/stable/main", deb)
    |> Plug.Conn.put_req_header("content-type", "application/octet-stream")
    |> call()

    conn =
      Plug.Test.conn(:delete, "/api/packages/stable/main/removeme/1.0/amd64")
      |> call()

    assert conn.status == 200
    assert Jason.decode!(conn.resp_body)["deleted"] == true

    conn =
      Plug.Test.conn(:get, "/api/packages/stable/main?arch=amd64")
      |> call()

    assert Jason.decode!(conn.resp_body)["packages"] == []
  end

  test "GET /dists/stable/Release serves Release file", %{repo_root: _root} do
    # Upload a package to trigger index generation
    deb = DebHelper.build_deb("idx-test", "1.0", "amd64")

    Plug.Test.conn(:put, "/api/packages/stable/main", deb)
    |> Plug.Conn.put_req_header("content-type", "application/octet-stream")
    |> call()

    conn = Plug.Test.conn(:get, "/dists/stable/Release") |> call()
    assert conn.status == 200
    assert conn.resp_body =~ "Suite: stable"
  end

  test "GET /dists/stable/InRelease serves signed release", %{repo_root: _root} do
    deb = DebHelper.build_deb("sig-test", "1.0", "amd64")

    Plug.Test.conn(:put, "/api/packages/stable/main", deb)
    |> Plug.Conn.put_req_header("content-type", "application/octet-stream")
    |> call()

    conn = Plug.Test.conn(:get, "/dists/stable/InRelease") |> call()
    assert conn.status == 200
    assert conn.resp_body =~ "-----BEGIN PGP SIGNED MESSAGE-----"
  end

  test "GET /dists/stable/main/binary-amd64/Packages.gz serves compressed index" do
    deb = DebHelper.build_deb("gz-test", "1.0", "amd64")

    Plug.Test.conn(:put, "/api/packages/stable/main", deb)
    |> Plug.Conn.put_req_header("content-type", "application/octet-stream")
    |> call()

    conn =
      Plug.Test.conn(:get, "/dists/stable/main/binary-amd64/Packages.gz")
      |> call()

    assert conn.status == 200
    decompressed = :zlib.gunzip(conn.resp_body)
    assert decompressed =~ "Package: gz-test"
  end

  test "GET /key.gpg serves public key" do
    conn = Plug.Test.conn(:get, "/key.gpg") |> call()
    assert conn.status == 200
    assert conn.resp_body =~ "-----BEGIN PGP PUBLIC KEY BLOCK-----"
  end

  test "GET /pool serves deb file", %{repo_root: _root} do
    deb = DebHelper.build_deb("pool-test", "1.0", "amd64")

    upload_conn =
      Plug.Test.conn(:put, "/api/packages/stable/main", deb)
      |> Plug.Conn.put_req_header("content-type", "application/octet-stream")
      |> call()

    filename = Jason.decode!(upload_conn.resp_body)["filename"]

    conn = Plug.Test.conn(:get, "/#{filename}") |> call()
    assert conn.status == 200
  end

  test "GET nonexistent path returns 404" do
    conn = Plug.Test.conn(:get, "/dists/nonexistent/Release") |> call()
    assert conn.status == 404
  end

  test "PUT invalid deb returns 400" do
    conn =
      Plug.Test.conn(:put, "/api/packages/stable/main", "not a deb")
      |> Plug.Conn.put_req_header("content-type", "application/octet-stream")
      |> call()

    assert conn.status == 400
  end
end
