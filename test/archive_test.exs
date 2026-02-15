defmodule RepomaticApt.ArchiveTest do
  use ExUnit.Case

  alias RepomaticApt.Archive
  alias RepomaticApt.Test.DebHelper

  defp make_tar_gz(files) do
    tmp =
      Path.join(
        System.tmp_dir!(),
        "repomatic_apt_archive_test_#{:erlang.unique_integer([:positive])}.tar"
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

  test "extracts .deb files from a tar.gz archive" do
    deb1 = DebHelper.build_deb("pkg-one", "1.0", "amd64")
    deb2 = DebHelper.build_deb("pkg-two", "2.0", "amd64")

    archive = make_tar_gz([{"pkg-one_1.0_amd64.deb", deb1}, {"pkg-two_2.0_amd64.deb", deb2}])

    assert {:ok, entries} = Archive.extract_debs(archive)
    assert length(entries) == 2
    filenames = Enum.map(entries, fn {name, _} -> name end) |> Enum.sort()
    assert filenames == ["pkg-one_1.0_amd64.deb", "pkg-two_2.0_amd64.deb"]
  end

  test "extracts .deb files from a zip archive" do
    deb = DebHelper.build_deb("zipped", "1.0", "amd64")

    archive = make_zip([{"zipped_1.0_amd64.deb", deb}])

    assert {:ok, entries} = Archive.extract_debs(archive)
    assert length(entries) == 1
    assert {name, binary} = hd(entries)
    assert name == "zipped_1.0_amd64.deb"
    assert binary == deb
  end

  test "ignores non-.deb files in archive" do
    deb = DebHelper.build_deb("real", "1.0", "amd64")

    archive =
      make_tar_gz([
        {"real_1.0_amd64.deb", deb},
        {"README.md", "readme"},
        {"checksums.txt", "abc123"}
      ])

    assert {:ok, entries} = Archive.extract_debs(archive)
    assert length(entries) == 1
    assert {name, _} = hd(entries)
    assert name == "real_1.0_amd64.deb"
  end

  test "handles nested directories using basename" do
    deb = DebHelper.build_deb("nested", "1.0", "amd64")

    archive = make_tar_gz([{"some/deep/path/nested_1.0_amd64.deb", deb}])

    assert {:ok, entries} = Archive.extract_debs(archive)
    assert length(entries) == 1
    assert {"nested_1.0_amd64.deb", _binary} = hd(entries)
  end

  test "returns error for unsupported archive format" do
    assert {:error, :unsupported_archive_format} = Archive.extract_debs("not an archive")
  end

  test "returns empty list for archives with no .deb files" do
    archive = make_tar_gz([{"readme.txt", "hello"}, {"data.csv", "a,b,c"}])

    assert {:ok, []} = Archive.extract_debs(archive)
  end

  test "skips dotfiles ending in .deb" do
    deb = DebHelper.build_deb("hidden", "1.0", "amd64")

    archive = make_tar_gz([{".hidden.deb", deb}, {"visible_1.0_amd64.deb", deb}])

    assert {:ok, entries} = Archive.extract_debs(archive)
    assert length(entries) == 1
    assert {"visible_1.0_amd64.deb", _} = hd(entries)
  end
end
