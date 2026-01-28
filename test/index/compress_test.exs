defmodule RepomaticApt.Index.CompressTest do
  use ExUnit.Case, async: true

  alias RepomaticApt.Index.Compress

  test "gzip roundtrip" do
    data = "Hello, this is test data for compression!"
    compressed = Compress.gzip(data)
    assert compressed != data
    assert Compress.gunzip(compressed) == data
  end

  test "gzip produces valid gzip header" do
    compressed = Compress.gzip("test")
    # Gzip magic number
    assert <<0x1F, 0x8B, _rest::binary>> = compressed
  end

  test "default compression level 9" do
    data = String.duplicate("abcdefgh", 1000)
    compressed = Compress.gzip(data)
    assert byte_size(compressed) < byte_size(data)
  end
end
