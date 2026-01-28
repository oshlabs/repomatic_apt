defmodule RepomaticApt.Gpg.Packet do
  @moduledoc """
  OpenPGP packet encoding: old-format packets, MPIs, and subpackets.
  """

  import Bitwise

  @doc """
  Encode a binary as an OpenPGP Multi-Precision Integer.
  """
  @spec encode_mpi(binary()) :: binary()
  def encode_mpi(<<>>), do: <<0::16>>

  def encode_mpi(bin) when is_binary(bin) do
    bin = strip_leading_zeros(bin)

    case bin do
      <<>> -> <<0::16>>
      _ -> <<mpi_bit_length(bin)::16, bin::binary>>
    end
  end

  @doc """
  Wrap a body in an old-format OpenPGP packet with the given tag.
  """
  @spec encode_old_packet(non_neg_integer(), binary()) :: binary()
  def encode_old_packet(tag, body) when is_integer(tag) and is_binary(body) do
    size = byte_size(body)

    {lt, len_bytes} =
      cond do
        size < 256 -> {0, <<size::8>>}
        size < 65536 -> {1, <<size::16>>}
        true -> {2, <<size::32>>}
      end

    tag_byte = 0x80 ||| bsl(tag, 2) ||| lt
    <<tag_byte, len_bytes::binary, body::binary>>
  end

  @doc """
  Encode a signature subpacket: length + type + data.
  """
  @spec encode_subpacket(non_neg_integer(), binary()) :: binary()
  def encode_subpacket(type, data) when is_integer(type) and is_binary(data) do
    len = byte_size(data) + 1

    if len < 192 do
      <<len::8, type::8, data::binary>>
    else
      adjusted = len - 192
      <<div(adjusted, 256) + 192::8, rem(adjusted, 256)::8, type::8, data::binary>>
    end
  end

  defp strip_leading_zeros(<<0, rest::binary>>) when byte_size(rest) > 0,
    do: strip_leading_zeros(rest)

  defp strip_leading_zeros(bin), do: bin

  defp mpi_bit_length(<<first, _rest::binary>> = bin) do
    (byte_size(bin) - 1) * 8 + significant_bits(first)
  end

  defp significant_bits(0), do: 0
  defp significant_bits(n), do: 1 + significant_bits(bsr(n, 1))
end
