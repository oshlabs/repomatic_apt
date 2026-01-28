defmodule RepomaticApt.Index.PackagesTest do
  use ExUnit.Case, async: true

  alias RepomaticApt.Deb.Package
  alias RepomaticApt.Index.Packages

  test "generates empty string for empty list" do
    assert Packages.generate([]) == ""
  end

  test "generates single package stanza" do
    pkg = %Package{
      name: "hello",
      version: "1.0-1",
      architecture: "amd64",
      maintainer: "Test <test@example.com>",
      installed_size: "1024",
      section: "utils",
      priority: "optional",
      filename: "pool/main/h/hello/hello_1.0-1_amd64.deb",
      size: 2048,
      sha256: "abcdef1234567890",
      description: "A test package"
    }

    result = Packages.generate([pkg])

    assert result =~ "Package: hello"
    assert result =~ "Version: 1.0-1"
    assert result =~ "Architecture: amd64"
    assert result =~ "Filename: pool/main/h/hello/hello_1.0-1_amd64.deb"
    assert result =~ "Size: 2048"
    assert result =~ "SHA256: abcdef1234567890"
    assert result =~ "Description: A test package"
  end

  test "omits nil fields" do
    pkg = %Package{
      name: "minimal",
      version: "1.0",
      architecture: "all"
    }

    result = Packages.generate([pkg])

    assert result =~ "Package: minimal"
    refute result =~ "Depends:"
    refute result =~ "Section:"
  end

  test "sorts packages by name then version" do
    pkgs = [
      %Package{name: "beta", version: "2.0", architecture: "amd64"},
      %Package{name: "alpha", version: "1.0", architecture: "amd64"},
      %Package{name: "alpha", version: "0.9", architecture: "amd64"}
    ]

    result = Packages.generate(pkgs)
    lines = String.split(result, "\n")
    package_lines = Enum.filter(lines, &String.starts_with?(&1, "Package:"))

    assert package_lines == ["Package: alpha", "Package: alpha", "Package: beta"]
  end

  test "multiple packages separated by blank line" do
    pkgs = [
      %Package{name: "a", version: "1.0", architecture: "amd64"},
      %Package{name: "b", version: "1.0", architecture: "amd64"}
    ]

    result = Packages.generate(pkgs)
    # Two stanzas separated by a blank line
    assert result =~ ~r/\n\nPackage: b/
  end

  test "multiline description is formatted with continuation lines" do
    pkg = %Package{
      name: "test",
      version: "1.0",
      architecture: "all",
      description: "short desc\nLong line 1\nLong line 2"
    }

    result = Packages.generate([pkg])
    assert result =~ "Description: short desc\n Long line 1\n Long line 2"
  end
end
