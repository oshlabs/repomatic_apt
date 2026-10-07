defmodule RepomaticApt.ArchiveTest do
  use ExUnit.Case

  alias RepomaticApt.Archive
  alias RepomaticApt.Test.DebHelper

  setup do
    tmp =
      Path.join(
        System.tmp_dir!(),
        "repomatic_apt_archive_test_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)
    %{tmp: tmp, dest: Path.join(tmp, "out")}
  end

  defp write_tar_gz(tmp, files) do
    tar = Path.join(tmp, "archive.tar")
    entries = Enum.map(files, fn {name, content} -> {~c"#{name}", content} end)
    :ok = :erl_tar.create(~c"#{tar}", entries)
    path = Path.join(tmp, "archive.tgz")
    File.write!(path, :zlib.gzip(File.read!(tar)))
    path
  end

  defp write_zip(tmp, files) do
    entries = Enum.map(files, fn {name, content} -> {~c"#{name}", content} end)
    {:ok, {_name, zip_data}} = :zip.create(~c"archive.zip", entries, [:memory])
    path = Path.join(tmp, "archive.zip")
    File.write!(path, zip_data)
    path
  end

  defp names(entries), do: entries |> Enum.map(fn {name, _} -> name end) |> Enum.sort()

  describe "extract_debs/2" do
    test "extracts .deb files from a tar.gz archive", %{tmp: tmp, dest: dest} do
      deb1 = DebHelper.build_deb("pkg-one", "1.0", "amd64")
      deb2 = DebHelper.build_deb("pkg-two", "2.0", "amd64")

      archive =
        write_tar_gz(tmp, [{"pkg-one_1.0_amd64.deb", deb1}, {"pkg-two_2.0_amd64.deb", deb2}])

      assert {:ok, entries} = Archive.extract_debs(archive, dest)
      assert names(entries) == ["pkg-one_1.0_amd64.deb", "pkg-two_2.0_amd64.deb"]

      for {name, path} <- entries do
        assert Path.dirname(path) == dest
        assert Path.basename(path) == name
      end

      assert File.read!(Path.join(dest, "pkg-one_1.0_amd64.deb")) == deb1
      assert File.read!(Path.join(dest, "pkg-two_2.0_amd64.deb")) == deb2
    end

    test "extracts .deb files from a zip archive", %{tmp: tmp, dest: dest} do
      deb = DebHelper.build_deb("zipped", "1.0", "amd64")
      archive = write_zip(tmp, [{"zipped_1.0_amd64.deb", deb}])

      assert {:ok, [{"zipped_1.0_amd64.deb", path}]} = Archive.extract_debs(archive, dest)
      assert File.read!(path) == deb
    end

    test "ignores non-.deb files in archive", %{tmp: tmp, dest: dest} do
      deb = DebHelper.build_deb("real", "1.0", "amd64")

      archive =
        write_tar_gz(tmp, [
          {"real_1.0_amd64.deb", deb},
          {"README.md", "readme"},
          {"checksums.txt", "abc123"}
        ])

      assert {:ok, [{"real_1.0_amd64.deb", _}]} = Archive.extract_debs(archive, dest)
      refute File.exists?(Path.join(dest, "README.md"))
    end

    test "flattens nested directories to the basename", %{tmp: tmp, dest: dest} do
      deb = DebHelper.build_deb("nested", "1.0", "amd64")
      archive = write_tar_gz(tmp, [{"some/deep/path/nested_1.0_amd64.deb", deb}])

      assert {:ok, [{"nested_1.0_amd64.deb", path}]} = Archive.extract_debs(archive, dest)
      assert path == Path.join(dest, "nested_1.0_amd64.deb")
      assert File.read!(path) == deb
    end

    test "zip entries with traversal in the name stay inside dest", %{tmp: tmp, dest: dest} do
      deb = DebHelper.build_deb("escape", "1.0", "amd64")
      archive = write_zip(tmp, [{"../../escape_1.0_amd64.deb", deb}])

      assert {:ok, [{"escape_1.0_amd64.deb", path}]} = Archive.extract_debs(archive, dest)
      assert path == Path.join(dest, "escape_1.0_amd64.deb")
      refute File.exists?(Path.join(tmp, "escape_1.0_amd64.deb"))
    end

    test "returns error for unsupported archive format", %{tmp: tmp, dest: dest} do
      path = Path.join(tmp, "junk")
      File.write!(path, "not an archive")
      assert {:error, :unsupported_archive_format} = Archive.extract_debs(path, dest)
    end

    test "returns error for a truncated gzip stream", %{tmp: tmp, dest: dest} do
      deb = DebHelper.build_deb("trunc", "1.0", "amd64")
      archive = write_tar_gz(tmp, [{"trunc_1.0_amd64.deb", deb}])
      data = File.read!(archive)
      File.write!(archive, binary_part(data, 0, div(byte_size(data), 2)))

      assert {:error, {:extract_failed, _}} = Archive.extract_debs(archive, dest)
    end

    test "returns empty list for archives with no .deb files", %{tmp: tmp, dest: dest} do
      archive = write_tar_gz(tmp, [{"readme.txt", "hello"}, {"data.csv", "a,b,c"}])
      assert {:ok, []} = Archive.extract_debs(archive, dest)
    end

    test "skips dotfiles ending in .deb", %{tmp: tmp, dest: dest} do
      deb = DebHelper.build_deb("hidden", "1.0", "amd64")
      archive = write_tar_gz(tmp, [{".hidden.deb", deb}, {"visible_1.0_amd64.deb", deb}])

      assert {:ok, [{"visible_1.0_amd64.deb", _}]} = Archive.extract_debs(archive, dest)
    end
  end

  describe "with_tmp_dir/1" do
    test "creates a directory under upload_tmp_dir and removes it afterwards", %{tmp: tmp} do
      Application.put_env(:repomatic_apt, :upload_tmp_dir, tmp)
      on_exit(fn -> Application.delete_env(:repomatic_apt, :upload_tmp_dir) end)

      dir =
        Archive.with_tmp_dir(fn dir ->
          assert File.dir?(dir)
          assert Path.dirname(dir) == tmp
          File.write!(Path.join(dir, "scratch"), "x")
          dir
        end)

      refute File.exists?(dir)
    end

    test "removes the directory when the function raises", %{tmp: tmp} do
      Application.put_env(:repomatic_apt, :upload_tmp_dir, tmp)
      on_exit(fn -> Application.delete_env(:repomatic_apt, :upload_tmp_dir) end)

      assert_raise RuntimeError, fn ->
        Archive.with_tmp_dir(fn dir ->
          send(self(), {:dir, dir})
          raise "boom"
        end)
      end

      assert_received {:dir, dir}
      refute File.exists?(dir)
    end
  end
end
