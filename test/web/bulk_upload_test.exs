defmodule RepomaticApt.Web.BulkUploadTest do
  use ExUnit.Case

  alias RepomaticApt.MetadataStore
  alias RepomaticApt.Test.DebHelper

  setup do
    MetadataStore.clear()

    tmp =
      Path.join(
        System.tmp_dir!(),
        "repomatic_apt_bulk_test_#{:erlang.unique_integer([:positive])}"
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
      Application.put_env(:repomatic_apt, :max_upload_size, 100 * 1024 * 1024)
      File.rm_rf!(tmp)
    end)

    %{repo_root: tmp}
  end

  defp call(conn) do
    RepomaticApt.Web.Router.call(conn, RepomaticApt.Web.Router.init([]))
  end

  defp make_tar_gz(files) do
    tmp =
      Path.join(
        System.tmp_dir!(),
        "repomatic_apt_bulk_test_tar_#{:erlang.unique_integer([:positive])}.tar"
      )

    entries = Enum.map(files, fn {name, content} -> {~c"#{name}", content} end)
    :ok = :erl_tar.create(~c"#{tmp}", entries)
    tar_data = File.read!(tmp)
    File.rm!(tmp)
    :zlib.gzip(tar_data)
  end

  defp make_zip(files) do
    entries = Enum.map(files, fn {name, content} -> {~c"#{name}", content} end)
    {:ok, {_name, zip_data}} = :zip.create(~c"archive.zip", entries, [:memory])
    zip_data
  end

  test "bulk upload tar.gz with multiple valid debs returns 201" do
    deb1 = DebHelper.build_deb("bulk-a", "1.0", "amd64")
    deb2 = DebHelper.build_deb("bulk-b", "2.0", "amd64")

    archive =
      make_tar_gz([{"bulk-a_1.0_amd64.deb", deb1}, {"bulk-b_2.0_amd64.deb", deb2}])

    conn =
      Plug.Test.conn(:put, "/api/packages/stable/main/bulk", archive)
      |> Plug.Conn.put_req_header("content-type", "application/octet-stream")
      |> call()

    assert conn.status == 201
    body = Jason.decode!(conn.resp_body)
    assert body["count"] == 2

    packages = body["packages"]
    names = Enum.map(packages, & &1["package"]) |> Enum.sort()
    assert names == ["bulk-a", "bulk-b"]

    Enum.each(packages, fn pkg ->
      assert pkg["version"] != nil
      assert pkg["architecture"] == "amd64"
      assert pkg["filename"] =~ "pool/main/"
      assert pkg["sha256"] != nil
    end)
  end

  test "bulk upload zip with valid debs returns 201" do
    deb = DebHelper.build_deb("zip-pkg", "1.0", "amd64")
    archive = make_zip([{"zip-pkg_1.0_amd64.deb", deb}])

    conn =
      Plug.Test.conn(:put, "/api/packages/stable/main/bulk", archive)
      |> Plug.Conn.put_req_header("content-type", "application/octet-stream")
      |> call()

    assert conn.status == 201
    body = Jason.decode!(conn.resp_body)
    assert body["count"] == 1
    assert hd(body["packages"])["package"] == "zip-pkg"
  end

  test "atomicity: archive with valid and invalid debs returns 400 and adds nothing" do
    valid_deb = DebHelper.build_deb("good-pkg", "1.0", "amd64")
    invalid_deb = "not a valid deb file"

    archive =
      make_tar_gz([
        {"good-pkg_1.0_amd64.deb", valid_deb},
        {"bad-pkg_1.0_amd64.deb", invalid_deb}
      ])

    conn =
      Plug.Test.conn(:put, "/api/packages/stable/main/bulk", archive)
      |> Plug.Conn.put_req_header("content-type", "application/octet-stream")
      |> call()

    assert conn.status == 400
    body = Jason.decode!(conn.resp_body)
    assert body["error"] =~ "failed validation"
    assert is_list(body["failures"])
    assert length(body["failures"]) == 1
    assert hd(body["failures"])["file"] == "bad-pkg_1.0_amd64.deb"

    # Verify nothing was added
    packages = RepomaticApt.Repo.list_packages("stable", "main", "amd64")
    assert packages == []
  end

  test "empty archive (no .deb files) returns 400" do
    archive = make_tar_gz([{"readme.txt", "hello"}, {"notes.md", "notes"}])

    conn =
      Plug.Test.conn(:put, "/api/packages/stable/main/bulk", archive)
      |> Plug.Conn.put_req_header("content-type", "application/octet-stream")
      |> call()

    assert conn.status == 400
    body = Jason.decode!(conn.resp_body)
    assert body["error"] =~ "no .deb files"
  end

  test "unsupported archive format returns 400" do
    conn =
      Plug.Test.conn(:put, "/api/packages/stable/main/bulk", "not an archive format")
      |> Plug.Conn.put_req_header("content-type", "application/octet-stream")
      |> call()

    assert conn.status == 400
    body = Jason.decode!(conn.resp_body)
    assert body["error"] =~ "Unsupported archive format"
  end

  test "bulk upload exceeding size limit returns 413" do
    Application.put_env(:repomatic_apt, :max_upload_size, 10)

    deb = DebHelper.build_deb("big", "1.0", "amd64")
    archive = make_tar_gz([{"big_1.0_amd64.deb", deb}])

    conn =
      Plug.Test.conn(:put, "/api/packages/stable/main/bulk", archive)
      |> Plug.Conn.put_req_header("content-type", "application/octet-stream")
      |> call()

    assert conn.status == 413
    assert Jason.decode!(conn.resp_body)["error"] =~ "exceeds maximum size"
  end

  test "bulk upload requires auth when token configured" do
    Application.put_env(:repomatic_apt, :api_token, "secret123")

    deb = DebHelper.build_deb("auth-pkg", "1.0", "amd64")
    archive = make_tar_gz([{"auth-pkg_1.0_amd64.deb", deb}])

    # Without token
    conn =
      Plug.Test.conn(:put, "/api/packages/stable/main/bulk", archive)
      |> Plug.Conn.put_req_header("content-type", "application/octet-stream")
      |> call()

    assert conn.status == 401

    # With correct token
    conn =
      Plug.Test.conn(:put, "/api/packages/stable/main/bulk", archive)
      |> Plug.Conn.put_req_header("content-type", "application/octet-stream")
      |> Plug.Conn.put_req_header("authorization", "Bearer secret123")
      |> call()

    assert conn.status == 201
  end

  test "bulk upload packages appear in repository indices", %{repo_root: root} do
    deb1 = DebHelper.build_deb("idx-bulk-a", "1.0", "amd64")
    deb2 = DebHelper.build_deb("idx-bulk-b", "2.0", "amd64")

    archive =
      make_tar_gz([{"idx-bulk-a_1.0_amd64.deb", deb1}, {"idx-bulk-b_2.0_amd64.deb", deb2}])

    Plug.Test.conn(:put, "/api/packages/stable/main/bulk", archive)
    |> Plug.Conn.put_req_header("content-type", "application/octet-stream")
    |> call()

    packages_path = Path.join(root, "dists/stable/main/binary-amd64/Packages")
    content = File.read!(packages_path)
    assert content =~ "Package: idx-bulk-a"
    assert content =~ "Package: idx-bulk-b"
  end
end
