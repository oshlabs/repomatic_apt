defmodule RepomaticApt.Index.Compress do
  @moduledoc """
  Compression for index files. Currently supports gzip only.
  """

  @doc """
  Compress data with gzip at the given level (default 9).
  """
  @spec gzip(iodata(), 0..9) :: binary()
  def gzip(data, level \\ 9) do
    z = :zlib.open()

    try do
      :zlib.deflateInit(z, level, :deflated, 16 + 15, 8, :default)
      compressed = :zlib.deflate(z, data, :finish)
      :zlib.deflateEnd(z)
      IO.iodata_to_binary(compressed)
    after
      :zlib.close(z)
    end
  end

  @doc """
  Decompress gzip data.
  """
  @spec gunzip(binary()) :: binary()
  def gunzip(data) do
    :zlib.gunzip(data)
  end
end
