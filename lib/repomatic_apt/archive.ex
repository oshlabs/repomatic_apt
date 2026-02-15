defmodule RepomaticApt.Archive do
  @moduledoc """
  Extracts `.deb` entries from tar.gz or zip archives.
  Delegates to `RepomaticCommon.Archive`.
  """

  @spec extract_debs(binary()) :: {:ok, [{String.t(), binary()}]} | {:error, term()}
  def extract_debs(data), do: RepomaticCommon.Archive.extract(data, ".deb")
end
