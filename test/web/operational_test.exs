defmodule RepomaticApt.Web.OperationalTest do
  use ExUnit.Case

  alias RepomaticApt.MetadataStore
  alias RepomaticApt.Test.DebHelper

  setup do
    MetadataStore.clear()

    tmp =
      Path.join(
        System.tmp_dir!(),
        "repomatic_apt_ops_test_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp)
    Application.put_env(:repomatic_apt, :repo_root, tmp)
    Application.put_env(:repomatic_apt, :api_token, nil)
    Application.put_env(:repomatic_apt, :max_upload_size, 100 * 1024 * 1024)

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

    on_exit(fn ->
      Application.put_env(:repomatic_apt, :api_token, nil)
      Application.put_env(:repomatic_apt, :ro_token, nil)
      Application.put_env(:repomatic_apt, :max_upload_size, 100 * 1024 * 1024)
      File.rm_rf!(tmp)
    end)

    %{repo_root: tmp}
  end

  defp call(conn) do
    RepomaticApt.Web.Router.call(conn, RepomaticApt.Web.Router.init([]))
  end

  # Health check

  test "GET /healthz returns ok" do
    conn = Plug.Test.conn(:get, "/healthz") |> call()
    assert conn.status == 200
    assert Jason.decode!(conn.resp_body) == %{"status" => "ok"}
  end

  # API authentication

  test "API requests pass when no token configured" do
    Application.put_env(:repomatic_apt, :api_token, nil)

    conn =
      Plug.Test.conn(:get, "/api/stable/main")
      |> call()

    assert conn.status == 200
  end

  test "API rejects requests without token when configured" do
    Application.put_env(:repomatic_apt, :api_token, "secret123")

    conn =
      Plug.Test.conn(:get, "/api/stable/main")
      |> call()

    assert conn.status == 401
    assert Jason.decode!(conn.resp_body)["error"] == "Unauthorized"
  end

  test "API accepts requests with correct Bearer token" do
    Application.put_env(:repomatic_apt, :api_token, "secret123")

    conn =
      Plug.Test.conn(:get, "/api/stable/main")
      |> Plug.Conn.put_req_header("authorization", "Bearer secret123")
      |> call()

    assert conn.status == 200
  end

  test "API rejects requests with wrong token" do
    Application.put_env(:repomatic_apt, :api_token, "secret123")

    conn =
      Plug.Test.conn(:get, "/api/stable/main")
      |> Plug.Conn.put_req_header("authorization", "Bearer wrong")
      |> call()

    assert conn.status == 401
  end

  # Read-only token (ro_token)

  test "read paths open when ro_token is nil" do
    Application.put_env(:repomatic_apt, :ro_token, nil)

    for path <- ["/dists/stable/Release", "/pool/main/test", "/key.gpg", "/ui"] do
      conn = Plug.Test.conn(:get, path) |> call()
      assert conn.status != 401, "Expected #{path} to not return 401, got #{conn.status}"
    end
  end

  test "/dists returns 401 when ro_token set and no auth" do
    Application.put_env(:repomatic_apt, :ro_token, "readpass")
    conn = Plug.Test.conn(:get, "/dists/stable/Release") |> call()
    assert conn.status == 401
    assert Plug.Conn.get_resp_header(conn, "www-authenticate") == [~s(Basic realm="RepomaticApt")]
  end

  test "/pool returns 401 when ro_token set and no auth" do
    Application.put_env(:repomatic_apt, :ro_token, "readpass")
    conn = Plug.Test.conn(:get, "/pool/main/test") |> call()
    assert conn.status == 401
  end

  test "/key.gpg returns 401 when ro_token set and no auth" do
    Application.put_env(:repomatic_apt, :ro_token, "readpass")
    conn = Plug.Test.conn(:get, "/key.gpg") |> call()
    assert conn.status == 401
  end

  test "/ui returns 401 when ro_token set and no auth" do
    Application.put_env(:repomatic_apt, :ro_token, "readpass")
    conn = Plug.Test.conn(:get, "/ui") |> call()
    assert conn.status == 401
  end

  test "read paths succeed with correct Basic auth password" do
    Application.put_env(:repomatic_apt, :ro_token, "readpass")

    for path <- ["/dists/stable/Release", "/key.gpg", "/ui"] do
      conn =
        Plug.Test.conn(:get, path)
        |> Plug.Conn.put_req_header("authorization", basic_auth("anything", "readpass"))
        |> call()

      assert conn.status != 401, "Expected #{path} to not return 401 with correct auth"
    end
  end

  test "read paths return 401 with wrong Basic auth password" do
    Application.put_env(:repomatic_apt, :ro_token, "readpass")

    conn =
      Plug.Test.conn(:get, "/ui")
      |> Plug.Conn.put_req_header("authorization", basic_auth("user", "wrong"))
      |> call()

    assert conn.status == 401
  end

  test "/healthz always open regardless of ro_token" do
    Application.put_env(:repomatic_apt, :ro_token, "readpass")
    conn = Plug.Test.conn(:get, "/healthz") |> call()
    assert conn.status == 200
  end

  test "/api unaffected by ro_token" do
    Application.put_env(:repomatic_apt, :ro_token, "readpass")
    Application.put_env(:repomatic_apt, :api_token, nil)

    conn = Plug.Test.conn(:get, "/api/stable/main") |> call()
    assert conn.status == 200
  end

  defp basic_auth(user, pass) do
    "Basic " <> Base.encode64("#{user}:#{pass}")
  end

  # Upload size limit

  test "upload within size limit succeeds" do
    Application.put_env(:repomatic_apt, :max_upload_size, 1_000_000)
    deb = DebHelper.build_deb("small", "1.0", "amd64")

    conn =
      Plug.Test.conn(:put, "/api/stable/main", deb)
      |> Plug.Conn.put_req_header("content-type", "application/octet-stream")
      |> call()

    assert conn.status == 201
  end

  test "upload exceeding size limit returns 413" do
    Application.put_env(:repomatic_apt, :max_upload_size, 10)
    deb = DebHelper.build_deb("big", "1.0", "amd64")

    conn =
      Plug.Test.conn(:put, "/api/stable/main", deb)
      |> Plug.Conn.put_req_header("content-type", "application/octet-stream")
      |> call()

    assert conn.status == 413
    assert Jason.decode!(conn.resp_body)["error"] =~ "exceeds maximum size"
  end

  # Atomic writes

  test "index files are written atomically (no temp files left behind)", %{repo_root: root} do
    deb = DebHelper.build_deb("atomic-test", "1.0", "amd64")

    Plug.Test.conn(:put, "/api/stable/main", deb)
    |> Plug.Conn.put_req_header("content-type", "application/octet-stream")
    |> call()

    dists_dir = Path.join(root, "dists/stable")

    tmp_files =
      dists_dir
      |> Path.join("**/*.tmp.*")
      |> Path.wildcard()

    assert tmp_files == []
  end

  # By-hash cleanup

  test "old by-hash entries are cleaned up after update", %{repo_root: root} do
    deb1 = DebHelper.build_deb("cleanup-test", "1.0", "amd64")

    Plug.Test.conn(:put, "/api/stable/main", deb1)
    |> Plug.Conn.put_req_header("content-type", "application/octet-stream")
    |> call()

    by_hash_dir = Path.join(root, "dists/stable/main/binary-amd64/by-hash/SHA256")
    old_hashes = File.ls!(by_hash_dir) |> MapSet.new()

    # Upload a different package to change the Packages file content
    deb2 = DebHelper.build_deb("cleanup-test2", "2.0", "amd64")

    Plug.Test.conn(:put, "/api/stable/main", deb2)
    |> Plug.Conn.put_req_header("content-type", "application/octet-stream")
    |> call()

    new_hashes = File.ls!(by_hash_dir) |> MapSet.new()

    # Old hashes that aren't current should be removed
    stale = MapSet.difference(old_hashes, new_hashes)
    # At least some old hashes should have been cleaned up
    # (the Packages content changed, so old hashes differ)
    assert MapSet.size(stale) > 0
  end
end
