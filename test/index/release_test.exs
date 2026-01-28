defmodule RepomaticApt.Index.ReleaseTest do
  use ExUnit.Case, async: true

  alias RepomaticApt.Index.Release

  test "generates header fields" do
    result =
      Release.generate(
        suite: "jammy",
        codename: "jammy",
        architectures: ["amd64", "arm64"],
        components: ["main"],
        origin: "RepomaticApt",
        label: "RepomaticApt",
        date: ~U[2025-01-15 12:00:00Z]
      )

    assert result =~ "Origin: RepomaticApt"
    assert result =~ "Label: RepomaticApt"
    assert result =~ "Suite: jammy"
    assert result =~ "Codename: jammy"
    assert result =~ "Architectures: amd64 arm64"
    assert result =~ "Components: main"
    assert result =~ "Date: Wed, 15 Jan 2025 12:00:00 UTC"
  end

  test "includes SHA256 entries for files" do
    content_a = "Package: hello\nVersion: 1.0\n"
    content_b = "compressed data here"

    result =
      Release.generate(
        suite: "jammy",
        files: [
          {"main/binary-amd64/Packages", content_a},
          {"main/binary-amd64/Packages.gz", content_b}
        ]
      )

    assert result =~ "SHA256:"

    hash_a = :crypto.hash(:sha256, content_a) |> Base.encode16(case: :lower)
    hash_b = :crypto.hash(:sha256, content_b) |> Base.encode16(case: :lower)

    assert result =~ hash_a
    assert result =~ hash_b
    assert result =~ "main/binary-amd64/Packages"
    assert result =~ "main/binary-amd64/Packages.gz"
  end

  test "omits nil fields" do
    result = Release.generate(suite: "test", date: ~U[2025-01-15 12:00:00Z])
    refute result =~ "Origin:"
    refute result =~ "Label:"
    assert result =~ "Suite: test"
  end

  test "SHA256 entries include correct sizes" do
    content = "hello world"

    result =
      Release.generate(
        suite: "test",
        files: [{"test/Packages", content}],
        date: ~U[2025-01-15 12:00:00Z]
      )

    assert result =~ " #{byte_size(content)} "
  end
end
