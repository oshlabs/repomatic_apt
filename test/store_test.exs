defmodule RepomaticApt.StoreTest do
  use ExUnit.Case, async: true

  alias RepomaticApt.Store
  alias RepomaticApt.Store.Backend.Local

  doctest RepomaticApt.Store

  describe "pool_prefix/1" do
    test "single char prefix for normal packages" do
      assert Store.pool_prefix("nginx") == "n"
      assert Store.pool_prefix("zsh") == "z"
    end

    test "lib prefix for lib packages" do
      assert Store.pool_prefix("libxml2") == "libx"
      assert Store.pool_prefix("libc6") == "libc"
      assert Store.pool_prefix("libstdc++6") == "libs"
    end
  end

  describe "pool_path/3" do
    test "normal package" do
      assert Store.pool_path("main", "nginx", "nginx_1.0-1_amd64.deb") ==
               "pool/main/n/nginx/nginx_1.0-1_amd64.deb"
    end

    test "lib package" do
      assert Store.pool_path("main", "libxml2", "libxml2_2.9_amd64.deb") ==
               "pool/main/libx/libxml2/libxml2_2.9_amd64.deb"
    end
  end

  describe "deb_filename/3" do
    test "builds correct filename" do
      assert Store.deb_filename("nginx", "1.0-1", "amd64") == "nginx_1.0-1_amd64.deb"
    end
  end

  describe "write_file/3" do
    @tag :tmp_dir
    test "creates directories and writes file via backend", %{tmp_dir: tmp} do
      backend = {Local, Local.new(tmp)}
      assert :ok = Store.write_file(backend, "a/b/c.txt", "hello")
      assert File.read!(Path.join(tmp, "a/b/c.txt")) == "hello"
    end
  end

  describe "read_file/2" do
    @tag :tmp_dir
    test "reads an existing file", %{tmp_dir: tmp} do
      backend = {Local, Local.new(tmp)}
      Store.write_file(backend, "a/b.txt", "content")
      assert {:ok, "content"} = Store.read_file(backend, "a/b.txt")
    end

    @tag :tmp_dir
    test "returns error for missing file", %{tmp_dir: tmp} do
      backend = {Local, Local.new(tmp)}
      assert {:error, :enoent} = Store.read_file(backend, "nope.txt")
    end
  end

  describe "list_recursive/2" do
    @tag :tmp_dir
    test "finds files in nested directories", %{tmp_dir: tmp} do
      backend = {Local, Local.new(tmp)}
      Store.write_file(backend, "pool/main/h/hello/hello_1.0_amd64.deb", "deb1")
      Store.write_file(backend, "pool/main/libn/libnss/libnss_1.0_amd64.deb", "deb2")
      Store.write_file(backend, "pool/main/h/hello/hello_2.0_amd64.deb", "deb3")

      {:ok, paths} = Store.list_recursive(backend, "pool/main")
      debs = Enum.filter(paths, &String.ends_with?(&1, ".deb")) |> Enum.sort()

      assert debs == [
               "pool/main/h/hello/hello_1.0_amd64.deb",
               "pool/main/h/hello/hello_2.0_amd64.deb",
               "pool/main/libn/libnss/libnss_1.0_amd64.deb"
             ]
    end

    @tag :tmp_dir
    test "returns empty list for missing directory", %{tmp_dir: tmp} do
      backend = {Local, Local.new(tmp)}
      assert {:ok, []} = Store.list_recursive(backend, "nonexistent")
    end
  end

  describe "write_with_by_hash/3" do
    @tag :tmp_dir
    test "writes file and by-hash copy, returns hash", %{tmp_dir: tmp} do
      backend = {Local, Local.new(tmp)}
      content = "test content"

      hash = Store.write_with_by_hash(backend, "dists/jammy/main/binary-amd64/Packages", content)

      assert File.read!(Path.join(tmp, "dists/jammy/main/binary-amd64/Packages")) == content

      expected_hash = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
      assert hash == expected_hash

      by_hash_path =
        Path.join(tmp, "dists/jammy/main/binary-amd64/by-hash/SHA256/#{hash}")

      assert File.read!(by_hash_path) == content
    end
  end

  describe "cleanup_by_hash/3" do
    @tag :tmp_dir
    test "removes stale hashes and keeps current ones", %{tmp_dir: tmp} do
      backend = {Local, Local.new(tmp)}

      # Write two files via by-hash
      hash1 = Store.write_with_by_hash(backend, "dists/d/main/binary-amd64/Packages", "v1")
      hash2 = Store.write_with_by_hash(backend, "dists/d/main/binary-amd64/Packages", "v2")

      # Both by-hash entries exist
      sha_dir = Path.join(tmp, "dists/d/main/binary-amd64/by-hash/SHA256")
      assert File.exists?(Path.join(sha_dir, hash1))
      assert File.exists?(Path.join(sha_dir, hash2))

      # Cleanup keeping only hash2
      Store.cleanup_by_hash(backend, "dists/d/main/binary-amd64", [hash2])

      refute File.exists?(Path.join(sha_dir, hash1))
      assert File.exists?(Path.join(sha_dir, hash2))
    end
  end
end
