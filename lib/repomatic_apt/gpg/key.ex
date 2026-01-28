defmodule RepomaticApt.Gpg.Key do
  @moduledoc """
  RSA key generation and OpenPGP v4 key packet construction.
  """

  alias RepomaticApt.Gpg.{Packet, Armor}
  import Bitwise

  @type t :: %__MODULE__{
          erlang_priv: list(),
          n: binary(),
          e: binary(),
          d: binary(),
          p: binary(),
          q: binary(),
          u: binary(),
          creation_time: non_neg_integer(),
          uid: String.t()
        }

  defstruct [:erlang_priv, :n, :e, :d, :p, :q, :u, :creation_time, :uid]

  @doc """
  Generate an RSA keypair.

  Options:
  - `:bits` — key size (default 4096)
  - `:uid` — user ID string (default "RepomaticApt <repomatic_apt@localhost>")
  - `:creation_time` — unix timestamp (default now)
  """
  @spec generate(keyword()) :: t()
  def generate(opts \\ []) do
    bits = opts[:bits] || 4096
    uid = opts[:uid] || "RepomaticApt <repomatic_apt@localhost>"
    creation_time = opts[:creation_time] || System.os_time(:second)

    {[_e_pub, _n_pub], [e_bin, n_bin, d_bin, p1_bin, p2_bin, _e1, _e2, _c] = priv} =
      :crypto.generate_key(:rsa, {bits, 65537})

    # OpenPGP requires p < q
    p_int = :binary.decode_unsigned(p1_bin)
    q_int = :binary.decode_unsigned(p2_bin)

    {p_bin, q_bin, q_for_inv} =
      if p_int < q_int,
        do: {p1_bin, p2_bin, q_int},
        else: {p2_bin, p1_bin, p_int}

    u_bin = :crypto.mod_pow(p_bin, q_for_inv - 2, q_bin)

    %__MODULE__{
      erlang_priv: priv,
      n: n_bin,
      e: e_bin,
      d: d_bin,
      p: p_bin,
      q: q_bin,
      u: u_bin,
      creation_time: creation_time,
      uid: uid
    }
  end

  @doc "Build the v4 public key packet body."
  @spec public_key_packet_body(t()) :: binary()
  def public_key_packet_body(%__MODULE__{} = key) do
    <<4::8, key.creation_time::32, 1::8>> <>
      Packet.encode_mpi(key.n) <>
      Packet.encode_mpi(key.e)
  end

  @doc "Compute the v4 fingerprint (SHA-1 of 0x99 + length + pubkey body)."
  @spec fingerprint(t()) :: binary()
  def fingerprint(%__MODULE__{} = key) do
    body = public_key_packet_body(key)
    :crypto.hash(:sha, <<0x99, byte_size(body)::16, body::binary>>)
  end

  @doc "Key ID: last 8 bytes of fingerprint."
  @spec key_id(t()) :: binary()
  def key_id(%__MODULE__{} = key) do
    fp = fingerprint(key)
    binary_part(fp, byte_size(fp) - 8, 8)
  end

  @doc "Build the v4 secret key packet body (unprotected)."
  @spec secret_key_packet_body(t()) :: binary()
  def secret_key_packet_body(%__MODULE__{} = key) do
    pub_part = public_key_packet_body(key)

    secret_mpis =
      Packet.encode_mpi(key.d) <>
        Packet.encode_mpi(key.p) <>
        Packet.encode_mpi(key.q) <>
        Packet.encode_mpi(key.u)

    checksum =
      secret_mpis
      |> :binary.bin_to_list()
      |> Enum.sum()
      |> band(0xFFFF)

    pub_part <> <<0::8>> <> secret_mpis <> <<checksum::16>>
  end

  @doc "Build a v4 positive certification self-signature packet body."
  @spec self_signature(t()) :: binary()
  def self_signature(%__MODULE__{} = key) do
    make_signature_body(
      key,
      0x13,
      fn sig_header, trailer ->
        pub_body = public_key_packet_body(key)

        <<0x99, byte_size(pub_body)::16, pub_body::binary>> <>
          <<0xB4, byte_size(key.uid)::32>> <>
          key.uid <>
          sig_header <> trailer
      end,
      hashed_subpackets: [
        # creation time
        Packet.encode_subpacket(2, <<key.creation_time::32>>),
        # key flags: sign + certify
        Packet.encode_subpacket(27, <<0x03>>),
        # preferred hash: SHA-256
        Packet.encode_subpacket(21, <<8>>)
      ]
    )
  end

  @doc "Export armored public key (pub packet + UID + self-sig)."
  @spec export_public(t()) :: String.t()
  def export_public(%__MODULE__{} = key) do
    data =
      Packet.encode_old_packet(6, public_key_packet_body(key)) <>
        Packet.encode_old_packet(13, key.uid) <>
        Packet.encode_old_packet(2, self_signature(key))

    Armor.encode(data, "PGP PUBLIC KEY BLOCK")
  end

  @doc "Export armored secret key (secret packet + UID + self-sig)."
  @spec export_secret(t()) :: String.t()
  def export_secret(%__MODULE__{} = key) do
    data =
      Packet.encode_old_packet(5, secret_key_packet_body(key)) <>
        Packet.encode_old_packet(13, key.uid) <>
        Packet.encode_old_packet(2, self_signature(key))

    Armor.encode(data, "PGP PRIVATE KEY BLOCK")
  end

  @doc false
  @spec make_signature_body(t(), non_neg_integer(), (binary(), binary() -> binary()), keyword()) ::
          binary()
  def make_signature_body(%__MODULE__{} = key, sig_type, hash_data_fn, opts \\ []) do
    creation_time = opts[:creation_time] || key.creation_time

    hashed_subpackets =
      opts[:hashed_subpackets] ||
        [Packet.encode_subpacket(2, <<creation_time::32>>)]

    hashed_sp_data = IO.iodata_to_binary(hashed_subpackets)

    issuer_sp = Packet.encode_subpacket(16, key_id(key))
    unhashed_sp_data = issuer_sp

    sig_header =
      <<4::8, sig_type::8, 1::8, 8::8, byte_size(hashed_sp_data)::16>> <> hashed_sp_data

    trailer = <<4::8, 0xFF::8, byte_size(sig_header)::32>>

    hash_input = hash_data_fn.(sig_header, trailer)
    hash = :crypto.hash(:sha256, hash_input)
    <<left16::binary-2, _::binary>> = hash

    signature = :crypto.sign(:rsa, :sha256, hash_input, key.erlang_priv)

    sig_header <>
      <<byte_size(unhashed_sp_data)::16>> <>
      unhashed_sp_data <>
      left16 <>
      Packet.encode_mpi(signature)
  end
end
