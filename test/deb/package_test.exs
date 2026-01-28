defmodule RepomaticApt.Deb.PackageTest do
  use ExUnit.Case, async: true

  alias RepomaticApt.Deb.Package

  defp make_ar(members) do
    body =
      Enum.reduce(members, <<>>, fn {name, data}, acc ->
        padded_name = String.pad_trailing(name <> "/", 16)
        size_str = String.pad_trailing(Integer.to_string(byte_size(data)), 10)
        filler = String.pad_trailing("", 32)
        header = padded_name <> filler <> size_str <> "`\n"
        padding = if rem(byte_size(data), 2) == 1, do: "\n", else: ""
        acc <> header <> data <> padding
      end)

    "!<arch>\n" <> body
  end

  defp make_control_tar_gz(control_content) do
    tmp =
      Path.join(
        System.tmp_dir!(),
        "repomatic_apt_test_control_#{:erlang.unique_integer([:positive])}.tar"
      )

    :ok = :erl_tar.create(~c"#{tmp}", [{~c"./control", control_content}])
    tar_data = File.read!(tmp)
    File.rm!(tmp)
    :zlib.gzip(tar_data)
  end

  defp build_deb(control_content) do
    control_tar_gz = make_control_tar_gz(control_content)
    make_ar([{"debian-binary", "2.0\n"}, {"control.tar.gz", control_tar_gz}, {"data.tar.gz", ""}])
  end

  test "extracts metadata from a minimal .deb" do
    control = """
    Package: hello
    Version: 1.0-1
    Architecture: amd64
    Maintainer: Test <test@example.com>
    Description: A test package
    """

    deb = build_deb(control)
    assert {:ok, pkg} = Package.extract(deb)
    assert pkg.name == "hello"
    assert pkg.version == "1.0-1"
    assert pkg.architecture == "amd64"
    assert pkg.maintainer == "Test <test@example.com>"
    assert pkg.description == "A test package"
    assert pkg.size == byte_size(deb)
  end

  test "computes sha256" do
    deb = build_deb("Package: test\nVersion: 1.0\n")
    {:ok, pkg} = Package.extract(deb)
    expected = :crypto.hash(:sha256, deb) |> Base.encode16(case: :lower)
    assert pkg.sha256 == expected
  end

  test "returns error for invalid archive" do
    assert {:error, :invalid_magic} = Package.extract("not a deb")
  end
end
