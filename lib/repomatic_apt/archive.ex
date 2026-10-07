defmodule RepomaticApt.Archive do
  @moduledoc """
  Extracts `.deb` entries from an archive file on disk into a directory.

  Supports `.tar.gz` and `.zip` archives, detected by magic bytes rather
  than file extension. Everything streams from and to disk so that peak
  memory is bounded by the largest single archive entry, not by the size
  of the whole archive.
  """

  require Record

  alias RepomaticApt.Config

  Record.defrecordp(:zip_file, Record.extract(:zip_file, from_lib: "stdlib/include/zip.hrl"))

  @tmp_dir_prefix "repomatic_apt_upload_"

  @typedoc "A `.deb` entry: `{basename, absolute path of the extracted file}`."
  @type deb_entry :: {String.t(), Path.t()}

  @doc """
  Extract the `.deb` entries of `archive_path` into `dest_dir`.

  `dest_dir` is created if needed. Only entries whose basename ends in
  `.deb` and does not start with a dot are extracted; directory structure
  inside the archive is ignored and every entry lands directly in `dest_dir`
  under its basename.

  Returns `{:ok, entries}` or `{:error, :unsupported_archive_format}` /
  `{:error, {:extract_failed, reason}}`.
  """
  @spec extract_debs(Path.t(), Path.t()) :: {:ok, [deb_entry()]} | {:error, term()}
  def extract_debs(archive_path, dest_dir) do
    File.mkdir_p!(dest_dir)

    case magic(archive_path) do
      {:ok, <<0x1F, 0x8B>>} -> extract_tar_gz(archive_path, dest_dir)
      {:ok, <<"PK">>} -> extract_zip(archive_path, dest_dir)
      {:ok, _} -> {:error, :unsupported_archive_format}
      {:error, reason} -> {:error, {:extract_failed, reason}}
    end
  end

  @doc """
  Create a fresh scratch directory under the configured upload temp dir,
  run `fun` with its path, and remove the directory afterwards — including
  when `fun` raises or throws.
  """
  @spec with_tmp_dir((Path.t() -> result)) :: result when result: term()
  def with_tmp_dir(fun) do
    dir =
      Path.join(
        Config.upload_tmp_dir(),
        "#{@tmp_dir_prefix}#{System.unique_integer([:positive])}_#{:erlang.phash2(make_ref())}"
      )

    File.mkdir_p!(dir)

    try do
      fun.(dir)
    after
      File.rm_rf(dir)
    end
  end

  defp magic(path) do
    File.open(path, [:read, :binary], fn io ->
      case IO.binread(io, 2) do
        data when is_binary(data) -> data
        :eof -> <<>>
        {:error, reason} -> throw({:magic_error, reason})
      end
    end)
  catch
    {:magic_error, reason} -> {:error, reason}
  end

  # tar.gz: erl_tar inflates the stream itself (`:compressed`), so we list
  # the table first, pick the .deb entries, and extract only those. erl_tar
  # refuses entries that would escape `cwd`, so traversal is not a concern.
  defp extract_tar_gz(archive_path, dest_dir) do
    tar = to_charlist(archive_path)
    extract_dir = Path.join(dest_dir, "tar")
    File.mkdir_p!(extract_dir)

    with {:ok, names} <- :erl_tar.table(tar, [:compressed]),
         wanted = Enum.filter(names, &deb_name?(to_string(&1))),
         :ok <- extract_tar_entries(tar, extract_dir, wanted) do
      entries =
        wanted
        |> Enum.map(fn name ->
          src = Path.join(extract_dir, to_string(name))
          {Path.basename(src), src}
        end)
        |> Enum.filter(fn {_base, src} -> regular_file?(src) end)
        |> Enum.map(fn {base, src} -> {base, move_to_flat(src, dest_dir, base)} end)

      {:ok, entries}
    else
      {:error, reason} -> {:error, {:extract_failed, reason}}
    end
  end

  defp extract_tar_entries(_tar, _dir, []), do: :ok

  defp extract_tar_entries(tar, dir, wanted) do
    :erl_tar.extract(tar, [:compressed, {:cwd, to_charlist(dir)}, {:files, wanted}])
  end

  # Extracted tar entries keep their internal directory layout; move each
  # one up to `dest_dir/<basename>` so callers see a flat list.
  defp move_to_flat(src, dest_dir, base) do
    dest = Path.join(dest_dir, base)
    File.rename!(src, dest)
    dest
  end

  # zip: open the archive once, then fetch only the wanted entries one at a
  # time so memory is bounded by the largest entry. We write under the
  # basename only, which also neutralises any `../` in entry names (OTP
  # sanitises those itself and logs an "Illegal path" warning).
  defp extract_zip(archive_path, dest_dir) do
    with {:ok, handle} <- :zip.zip_open(to_charlist(archive_path), [:memory]) do
      try do
        with {:ok, listing} <- :zip.zip_list_dir(handle) do
          names = for zip_file(name: name) <- listing, deb_name?(to_string(name)), do: name
          extract_zip_entries(handle, dest_dir, names, [])
        end
      after
        :zip.zip_close(handle)
      end
    end
    |> case do
      {:ok, entries} -> {:ok, entries}
      {:error, reason} -> {:error, {:extract_failed, reason}}
    end
  end

  defp extract_zip_entries(_handle, _dest_dir, [], acc), do: {:ok, Enum.reverse(acc)}

  defp extract_zip_entries(handle, dest_dir, [name | rest], acc) do
    case :zip.zip_get(name, handle) do
      {:ok, {_name, data}} ->
        base = name |> to_string() |> Path.basename()
        dest = Path.join(dest_dir, base)
        File.write!(dest, data)
        extract_zip_entries(handle, dest_dir, rest, [{base, dest} | acc])

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp deb_name?(name) do
    base = Path.basename(name)
    String.ends_with?(base, ".deb") and not String.starts_with?(base, ".")
  end

  defp regular_file?(path) do
    case File.lstat(path) do
      {:ok, %File.Stat{type: :regular}} -> true
      _ -> false
    end
  end
end
