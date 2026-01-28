defmodule RepomaticApt.StoreTest do
  use ExUnit.Case, async: true

  alias RepomaticApt.Store

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
    test "creates directories and writes file", %{tmp_dir: tmp} do
      path = Store.write_file(tmp, "a/b/c.txt", "hello")
      assert File.read!(path) == "hello"
      assert path == Path.join(tmp, "a/b/c.txt")
    end
  end

  describe "write_with_by_hash/3" do
    @tag :tmp_dir
    test "writes file and by-hash copy", %{tmp_dir: tmp} do
      content = "test content"

      {path, by_hash_path} =
        Store.write_with_by_hash(tmp, "dists/jammy/main/binary-amd64/Packages", content)

      assert File.read!(path) == content
      assert File.read!(by_hash_path) == content

      hash = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)

      assert by_hash_path ==
               Path.join(tmp, "dists/jammy/main/binary-amd64/by-hash/SHA256/#{hash}")
    end
  end
end
