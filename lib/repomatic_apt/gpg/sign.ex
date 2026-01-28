defmodule RepomaticApt.Gpg.Sign do
  @moduledoc """
  OpenPGP detached and clearsign operations.
  """

  alias RepomaticApt.Gpg.{Key, Packet, Armor}

  @doc """
  Produce an ASCII-armored detached signature (binary document, type 0x00).
  """
  @spec detached(Key.t(), binary(), keyword()) :: String.t()
  def detached(%Key{} = key, data, opts \\ []) do
    sig_body =
      Key.make_signature_body(
        key,
        0x00,
        fn sig_header, trailer ->
          data <> sig_header <> trailer
        end,
        opts
      )

    sig_packet = Packet.encode_old_packet(2, sig_body)
    Armor.encode(sig_packet, "PGP SIGNATURE")
  end

  @doc """
  Produce a clearsigned message (canonical text, type 0x01).
  """
  @spec clearsign(Key.t(), String.t(), keyword()) :: String.t()
  def clearsign(%Key{} = key, text, opts \\ []) do
    normalized = normalize_text(text)

    sig_body =
      Key.make_signature_body(
        key,
        0x01,
        fn sig_header, trailer ->
          normalized <> sig_header <> trailer
        end,
        opts
      )

    sig_packet = Packet.encode_old_packet(2, sig_body)
    sig_armor = Armor.encode(sig_packet, "PGP SIGNATURE")

    escaped = dash_escape(String.trim_trailing(text, "\n"))

    "-----BEGIN PGP SIGNED MESSAGE-----\nHash: SHA256\n\n" <>
      escaped <> "\n" <> sig_armor
  end

  defp normalize_text(text) do
    text
    |> String.trim_trailing("\n")
    |> String.split("\n")
    |> Enum.map(&String.trim_trailing/1)
    |> Enum.join("\r\n")
  end

  defp dash_escape(text) do
    text
    |> String.split("\n")
    |> Enum.map(fn
      "-" <> _ = line -> "- " <> line
      line -> line
    end)
    |> Enum.join("\n")
  end
end
