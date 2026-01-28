defmodule RepomaticApt.Gpg.ArmorTest do
  use ExUnit.Case, async: true

  alias RepomaticApt.Gpg.Armor

  test "encodes with correct header and footer" do
    result = Armor.encode("test", "PGP PUBLIC KEY BLOCK")
    assert result =~ "-----BEGIN PGP PUBLIC KEY BLOCK-----"
    assert result =~ "-----END PGP PUBLIC KEY BLOCK-----"
  end

  test "includes blank line after header" do
    result = Armor.encode("data", "PGP SIGNATURE")
    lines = String.split(result, "\n")
    header_idx = Enum.find_index(lines, &(&1 =~ "BEGIN"))
    assert Enum.at(lines, header_idx + 1) == ""
  end

  test "base64 body is decodable" do
    original = :crypto.strong_rand_bytes(256)
    result = Armor.encode(original, "PGP MESSAGE")

    lines = String.split(result, "\n")
    # Lines between blank line and CRC line
    blank_idx = Enum.find_index(lines, &(&1 == "")) + 1
    crc_idx = Enum.find_index(lines, &String.starts_with?(&1, "="))
    b64_lines = Enum.slice(lines, blank_idx..(crc_idx - 1))
    decoded = b64_lines |> Enum.join() |> Base.decode64!()
    assert decoded == original
  end

  test "CRC line starts with =" do
    result = Armor.encode("test", "PGP SIGNATURE")
    lines = String.split(result, "\n")
    crc_line = Enum.find(lines, &String.starts_with?(&1, "="))
    assert crc_line != nil
    # CRC is 3 bytes = 4 base64 chars
    assert String.length(crc_line) == 5
  end

  test "base64 lines are max 76 chars" do
    data = :crypto.strong_rand_bytes(1024)
    result = Armor.encode(data, "PGP MESSAGE")

    lines = String.split(result, "\n")

    b64_lines =
      lines
      |> Enum.filter(&(&1 != ""))
      |> Enum.reject(&String.starts_with?(&1, "-"))
      |> Enum.reject(&String.starts_with?(&1, "="))

    Enum.each(b64_lines, fn line ->
      assert String.length(line) <= 76
    end)
  end
end
