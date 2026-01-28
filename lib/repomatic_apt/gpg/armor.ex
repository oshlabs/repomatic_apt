defmodule RepomaticApt.Gpg.Armor do
  @moduledoc """
  OpenPGP ASCII armor encoding (RFC 4880 §6.2).
  """

  alias RepomaticApt.Gpg.Crc24

  @doc """
  Encode binary data as ASCII armor with the given type label.

  Type examples: `"PGP PUBLIC KEY BLOCK"`, `"PGP SIGNATURE"`.
  """
  @spec encode(binary(), String.t()) :: String.t()
  def encode(data, type) when is_binary(data) and is_binary(type) do
    b64_lines =
      data
      |> Base.encode64()
      |> chunk_string(76)

    crc = Crc24.compute(data)
    crc_line = "=" <> Base.encode64(<<crc::24>>)

    lines =
      ["-----BEGIN #{type}-----", ""] ++
        b64_lines ++
        [crc_line, "-----END #{type}-----"]

    Enum.join(lines, "\n") <> "\n"
  end

  defp chunk_string(<<>>, _size), do: []

  defp chunk_string(string, size) do
    {chunk, rest} = String.split_at(string, size)
    [chunk | chunk_string(rest, size)]
  end
end
