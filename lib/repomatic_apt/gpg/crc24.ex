defmodule RepomaticApt.Gpg.Crc24 do
  @moduledoc """
  CRC-24 computation for OpenPGP ASCII armor checksums (RFC 4880 §6.1).
  """

  import Bitwise

  @init 0xB704CE
  @poly 0x1864CFB

  @spec compute(binary()) :: non_neg_integer()
  def compute(data) when is_binary(data) do
    data
    |> :binary.bin_to_list()
    |> Enum.reduce(@init, fn byte, crc ->
      crc = bxor(crc, bsl(byte, 16))

      Enum.reduce(0..7, crc, fn _bit, crc ->
        crc = bsl(crc, 1)

        if band(crc, 0x1000000) != 0 do
          bxor(crc, @poly)
        else
          crc
        end
      end)
    end)
    |> band(0xFFFFFF)
  end
end
