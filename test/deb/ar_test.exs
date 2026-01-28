defmodule RepomaticApt.Deb.ArTest do
  use ExUnit.Case, async: true

  alias RepomaticApt.Deb.Ar

  defp make_ar(members) do
    body =
      Enum.reduce(members, <<>>, fn {name, data}, acc ->
        padded_name = String.pad_trailing(name <> "/", 16)
        size_str = String.pad_trailing(Integer.to_string(byte_size(data)), 10)
        # mtime(12) + owner(6) + group(6) + mode(8) = 32 bytes of filler
        filler = String.pad_trailing("", 32)
        header = padded_name <> filler <> size_str <> "`\n"
        padding = if rem(byte_size(data), 2) == 1, do: "\n", else: ""
        acc <> header <> data <> padding
      end)

    "!<arch>\n" <> body
  end

  test "parses single member" do
    ar = make_ar([{"hello.txt", "world"}])
    assert {:ok, [%{name: "hello.txt", data: "world"}]} = Ar.parse(ar)
  end

  test "parses multiple members" do
    ar = make_ar([{"a", "abc"}, {"b", "defg"}])
    assert {:ok, [%{name: "a", data: "abc"}, %{name: "b", data: "defg"}]} = Ar.parse(ar)
  end

  test "handles odd-size padding" do
    ar = make_ar([{"odd", "12345"}, {"even", "ab"}])
    assert {:ok, [%{name: "odd", data: "12345"}, %{name: "even", data: "ab"}]} = Ar.parse(ar)
  end

  test "rejects invalid magic" do
    assert {:error, :invalid_magic} = Ar.parse("not an archive")
  end
end
