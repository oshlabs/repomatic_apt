defmodule RepomaticApt.Gpg.SignTest do
  use ExUnit.Case

  alias RepomaticApt.Gpg.{Key, Sign}

  @key_opts [bits: 2048, uid: "Test <test@example.com>", creation_time: 1_700_000_000]

  setup_all do
    key = Key.generate(@key_opts)
    %{key: key}
  end

  test "detached signature produces valid armor", %{key: key} do
    sig = Sign.detached(key, "test data")
    assert sig =~ "-----BEGIN PGP SIGNATURE-----"
    assert sig =~ "-----END PGP SIGNATURE-----"
  end

  test "clearsign produces correct format", %{key: key} do
    text = "Hello World\nThis is a test.\n"
    result = Sign.clearsign(key, text)

    assert result =~ "-----BEGIN PGP SIGNED MESSAGE-----"
    assert result =~ "Hash: SHA256"
    assert result =~ "Hello World"
    assert result =~ "-----BEGIN PGP SIGNATURE-----"
    assert result =~ "-----END PGP SIGNATURE-----"
  end

  test "clearsign dash-escapes lines starting with dash", %{key: key} do
    text = "Normal line\n- Dashed line\n--Also dashed\n"
    result = Sign.clearsign(key, text)
    assert result =~ "- - Dashed line"
    assert result =~ "- --Also dashed"
  end

  @tag :gpg
  test "gpg can verify detached signature", %{key: key} do
    gpg_available?() || skip_gpg()

    gnupg_home = make_gpg_home(key)

    try do
      data = "Release file content\nSHA256: abc123\n"
      sig = Sign.detached(key, data)

      data_file = Path.join(gnupg_home, "Release")
      sig_file = Path.join(gnupg_home, "Release.gpg")
      File.write!(data_file, data)
      File.write!(sig_file, sig)

      {output, exit_code} =
        System.cmd(
          "gpg",
          ["--homedir", gnupg_home, "--batch", "--verify", sig_file, data_file],
          stderr_to_stdout: true
        )

      assert exit_code == 0, "gpg verify failed: #{output}"
    after
      File.rm_rf!(gnupg_home)
    end
  end

  @tag :gpg
  test "gpg can verify clearsigned message", %{key: key} do
    gpg_available?() || skip_gpg()

    gnupg_home = make_gpg_home(key)

    try do
      text = "Origin: RepomaticApt\nSuite: jammy\n"
      signed = Sign.clearsign(key, text)

      inrelease_file = Path.join(gnupg_home, "InRelease")
      File.write!(inrelease_file, signed)

      {output, exit_code} =
        System.cmd(
          "gpg",
          ["--homedir", gnupg_home, "--batch", "--verify", inrelease_file],
          stderr_to_stdout: true
        )

      assert exit_code == 0, "gpg verify failed: #{output}"
    after
      File.rm_rf!(gnupg_home)
    end
  end

  defp make_gpg_home(key) do
    tmp = System.tmp_dir!()
    gnupg_home = Path.join(tmp, "repomatic_apt_gpg_test_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(gnupg_home)

    pub_file = Path.join(gnupg_home, "test.pub")
    File.write!(pub_file, Key.export_public(key))

    {_, 0} =
      System.cmd("gpg", ["--homedir", gnupg_home, "--batch", "--import", pub_file],
        stderr_to_stdout: true
      )

    gnupg_home
  end

  defp gpg_available? do
    case System.cmd("which", ["gpg"], stderr_to_stdout: true) do
      {_, 0} -> true
      _ -> false
    end
  end

  defp skip_gpg, do: raise(ExUnit.DocTest.Error, "gpg not available")
end
