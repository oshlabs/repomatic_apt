defmodule RepomaticApt.Test.DebHelper do
  @moduledoc false

  def build_deb(fields) when is_list(fields) do
    control = Enum.map_join(fields, "\n", fn {k, v} -> "#{k}: #{v}" end) <> "\n"
    control_tar_gz = make_control_tar_gz(control)
    make_ar([{"debian-binary", "2.0\n"}, {"control.tar.gz", control_tar_gz}, {"data.tar.gz", ""}])
  end

  def build_deb(name, version, arch) do
    build_deb([
      {"Package", name},
      {"Version", version},
      {"Architecture", arch},
      {"Maintainer", "Test <test@example.com>"},
      {"Description", "Test package #{name}"}
    ])
  end

  @doc """
  Build an installable `.deb` with real files in `data.tar.gz`.

  `files` is a list of `{path, content}` tuples where paths should start with `./`,
  e.g. `[{"./usr/share/myapp/hello.txt", "hello\\n"}]`.
  """
  def build_installable_deb(name, version, arch, files) do
    installed_size =
      files
      |> Enum.reduce(0, fn {_path, content}, acc -> acc + byte_size(content) end)
      |> div(1024)
      |> max(1)

    control_content =
      Enum.map_join(
        [
          {"Package", name},
          {"Version", version},
          {"Architecture", arch},
          {"Maintainer", "Test <test@example.com>"},
          {"Description", "Test package #{name}"},
          {"Installed-Size", to_string(installed_size)}
        ],
        "\n",
        fn {k, v} -> "#{k}: #{v}" end
      ) <> "\n"

    control_tar_gz = make_control_tar_gz(control_content)
    data_tar_gz = make_data_tar_gz(files)

    make_ar([
      {"debian-binary", "2.0\n"},
      {"control.tar.gz", control_tar_gz},
      {"data.tar.gz", data_tar_gz}
    ])
  end

  defp make_control_tar_gz(control_content) do
    tmp =
      Path.join(
        System.tmp_dir!(),
        "repomatic_apt_deb_helper_#{:erlang.unique_integer([:positive])}.tar"
      )

    :ok = :erl_tar.create(~c"#{tmp}", [{~c"./control", control_content}])
    tar_data = File.read!(tmp)
    File.rm!(tmp)
    :zlib.gzip(tar_data)
  end

  defp make_data_tar_gz(files) do
    # Collect unique ancestor directories from all file paths
    dirs =
      files
      |> Enum.flat_map(fn {path, _} ->
        parts = path |> String.replace_prefix("./", "") |> Path.split()

        for i <- 1..(length(parts) - 1) do
          "./" <> Path.join(Enum.take(parts, i)) <> "/"
        end
      end)
      |> Enum.uniq()
      |> Enum.sort()

    # Build tar binary: directory entries + file entries + end-of-archive marker
    tar_data =
      Enum.reduce(dirs, <<>>, fn dir, acc ->
        acc <> tar_entry(dir, <<>>, ?5)
      end)

    tar_data =
      Enum.reduce(files, tar_data, fn {path, content}, acc ->
        acc <> tar_entry(path, content, ?0)
      end)

    # End-of-archive: two 512-byte zero blocks
    tar_data = tar_data <> :binary.copy(<<0>>, 1024)

    :zlib.gzip(tar_data)
  end

  # Build a single POSIX/ustar tar entry (header + data padded to 512 bytes).
  defp tar_entry(name, data, typeflag) do
    name_bin = String.pad_trailing(name, 100, <<0>>)
    mode = if typeflag == ?5, do: "0040755", else: "0100644"
    mode_bin = String.pad_trailing(mode, 8, <<0>>)
    uid_bin = String.pad_trailing("0000000", 8, <<0>>)
    gid_bin = String.pad_trailing("0000000", 8, <<0>>)
    size_oct = :io_lib.format(~c"~11.8.0b", [byte_size(data)]) |> IO.iodata_to_binary()
    size_bin = size_oct <> <<0>>
    mtime_bin = String.pad_trailing("00000000000", 12, <<0>>)
    # Placeholder checksum (8 spaces) for calculation
    chksum_placeholder = "        "
    type_bin = <<typeflag>>
    linkname_bin = :binary.copy(<<0>>, 100)
    magic = "ustar\0"
    version = "00"
    uname = String.pad_trailing("root", 32, <<0>>)
    gname = String.pad_trailing("root", 32, <<0>>)
    devmajor = String.pad_trailing("0000000", 8, <<0>>)
    devminor = String.pad_trailing("0000000", 8, <<0>>)
    prefix = :binary.copy(<<0>>, 155)
    pad_to_512 = :binary.copy(<<0>>, 12)

    header_no_chk =
      name_bin <>
        mode_bin <>
        uid_bin <>
        gid_bin <>
        size_bin <>
        mtime_bin <>
        chksum_placeholder <>
        type_bin <>
        linkname_bin <>
        magic <>
        version <>
        uname <>
        gname <>
        devmajor <>
        devminor <>
        prefix <>
        pad_to_512

    # Compute checksum: sum of all unsigned bytes in the header
    chksum = for(<<b <- header_no_chk>>, reduce: 0, do: (acc -> acc + b))
    chksum_str = :io_lib.format(~c"~6.8.0b", [chksum]) |> IO.iodata_to_binary()
    chksum_bin = chksum_str <> <<0, 32>>

    header =
      name_bin <>
        mode_bin <>
        uid_bin <>
        gid_bin <>
        size_bin <>
        mtime_bin <>
        chksum_bin <>
        type_bin <>
        linkname_bin <>
        magic <>
        version <>
        uname <>
        gname <>
        devmajor <>
        devminor <>
        prefix <>
        pad_to_512

    # Data blocks padded to 512 bytes
    data_padding_size = rem(512 - rem(byte_size(data), 512), 512)
    header <> data <> :binary.copy(<<0>>, data_padding_size)
  end

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
end
