defmodule RepomaticApt.Gpg.KeyTest do
  use ExUnit.Case

  alias RepomaticApt.Gpg.Key

  # Use 2048 bits for faster tests
  @key_opts [bits: 2048, uid: "Test <test@example.com>", creation_time: 1_700_000_000]

  setup_all do
    key = Key.generate(@key_opts)
    %{key: key}
  end

  test "generate returns a Key struct", %{key: key} do
    assert %Key{} = key
    assert key.uid == "Test <test@example.com>"
    assert key.creation_time == 1_700_000_000
  end

  test "fingerprint is 20 bytes", %{key: key} do
    fp = Key.fingerprint(key)
    assert byte_size(fp) == 20
  end

  test "key_id is 8 bytes", %{key: key} do
    kid = Key.key_id(key)
    assert byte_size(kid) == 8
  end

  test "key_id is last 8 bytes of fingerprint", %{key: key} do
    fp = Key.fingerprint(key)
    kid = Key.key_id(key)
    assert kid == binary_part(fp, 12, 8)
  end

  test "export_public produces valid armor", %{key: key} do
    pub = Key.export_public(key)
    assert pub =~ "-----BEGIN PGP PUBLIC KEY BLOCK-----"
    assert pub =~ "-----END PGP PUBLIC KEY BLOCK-----"
  end

  test "export_secret produces valid armor", %{key: key} do
    sec = Key.export_secret(key)
    assert sec =~ "-----BEGIN PGP PRIVATE KEY BLOCK-----"
    assert sec =~ "-----END PGP PRIVATE KEY BLOCK-----"
  end

  test "public key packet body starts with version 4", %{key: key} do
    body = Key.public_key_packet_body(key)
    assert <<4, _rest::binary>> = body
  end

  test "p < q in generated key", %{key: key} do
    p = :binary.decode_unsigned(key.p)
    q = :binary.decode_unsigned(key.q)
    assert p < q
  end

  @tag :gpg
  test "gpg can import the public key", %{key: key} do
    gpg_available?() || skip_gpg()

    tmp = System.tmp_dir!()
    gnupg_home = Path.join(tmp, "repomatic_apt_gpg_test_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(gnupg_home)

    try do
      pub = Key.export_public(key)
      pub_file = Path.join(gnupg_home, "test.pub")
      File.write!(pub_file, pub)

      {output, exit_code} =
        System.cmd("gpg", ["--homedir", gnupg_home, "--batch", "--import", pub_file],
          stderr_to_stdout: true
        )

      assert exit_code == 0, "gpg import failed: #{output}"
    after
      File.rm_rf!(gnupg_home)
    end
  end

  defp gpg_available? do
    case System.cmd("which", ["gpg"], stderr_to_stdout: true) do
      {_, 0} -> true
      _ -> false
    end
  end

  defp skip_gpg, do: raise(ExUnit.DocTest.Error, "gpg not available")
end
