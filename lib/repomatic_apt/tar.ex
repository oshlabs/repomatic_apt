defmodule RepomaticApt.Tar do
  @moduledoc """
  Low-level POSIX/ustar tar archive builder.

  Builds tar entries and archives directly from binaries, without
  touching the filesystem.
  """

  @doc """
  Builds a single POSIX/ustar tar entry (512-byte header + data padded to 512 bytes).

  `typeflag` is the ASCII character for the entry type:
  - `?0` — regular file
  - `?5` — directory
  """
  @spec entry(String.t(), binary(), char()) :: binary()
  def entry(name, data, typeflag) do
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

  @doc """
  Builds raw tar data from a list of `{path, content}` file entries.

  Automatically creates directory entries for all ancestor directories.

  ## Options

    * `:end_marker` — append two 512-byte zero blocks (standard end-of-archive
      marker). Default `false`.
  """
  @spec build_data([{String.t(), binary()}], keyword()) :: binary()
  def build_data(files, opts \\ []) do
    end_marker = Keyword.get(opts, :end_marker, false)

    dirs =
      files
      |> Enum.flat_map(fn {path, _} ->
        parts = Path.split(path)

        for i <- 1..(length(parts) - 1) do
          Path.join(Enum.take(parts, i)) <> "/"
        end
      end)
      |> Enum.uniq()
      |> Enum.sort()

    tar_data =
      Enum.reduce(dirs, <<>>, fn dir, acc ->
        acc <> entry(dir, <<>>, ?5)
      end)

    tar_data =
      Enum.reduce(files, tar_data, fn {path, content}, acc ->
        acc <> entry(path, content, ?0)
      end)

    if end_marker do
      tar_data <> :binary.copy(<<0>>, 1024)
    else
      tar_data
    end
  end
end
