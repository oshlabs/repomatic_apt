defmodule RepomaticApt.Archive do
  @moduledoc """
  Detects archive format via magic bytes and extracts `.deb` entries.
  Supports `.tar.gz` and `.zip` archives.
  """

  @spec extract_debs(binary()) :: {:ok, [{String.t(), binary()}]} | {:error, term()}
  def extract_debs(<<0x1F, 0x8B, _::binary>> = data) do
    extract_tar_gz(data)
  end

  def extract_debs(<<"PK", _::binary>> = data) do
    extract_zip(data)
  end

  def extract_debs(_data) do
    {:error, :unsupported_archive_format}
  end

  defp extract_tar_gz(data) do
    with {:ok, decompressed} <- safe_gunzip(data),
         {:ok, entries} <- safe_tar_extract(decompressed) do
      {:ok, filter_debs(entries)}
    end
  end

  defp extract_zip(data) do
    case :zip.extract(data, [:memory]) do
      {:ok, entries} ->
        mapped =
          Enum.map(entries, fn {name, binary} ->
            {to_string(name), binary}
          end)

        {:ok, filter_debs(mapped)}

      {:error, reason} ->
        {:error, {:extract_failed, reason}}
    end
  end

  defp safe_gunzip(data) do
    {:ok, :zlib.gunzip(data)}
  rescue
    e -> {:error, {:extract_failed, Exception.message(e)}}
  end

  defp safe_tar_extract(tar_data) do
    case :erl_tar.extract({:binary, tar_data}, [:memory]) do
      {:ok, entries} ->
        mapped =
          Enum.map(entries, fn {name, binary} ->
            {to_string(name), binary}
          end)

        {:ok, mapped}

      {:error, reason} ->
        {:error, {:extract_failed, reason}}
    end
  end

  defp filter_debs(entries) do
    entries
    |> Enum.filter(fn {name, _binary} ->
      basename = Path.basename(name)
      String.ends_with?(basename, ".deb") and not String.starts_with?(basename, ".")
    end)
    |> Enum.map(fn {name, binary} ->
      {Path.basename(name), binary}
    end)
  end
end
