defmodule RepomaticApt.Deb.ControlTest do
  use ExUnit.Case, async: true

  alias RepomaticApt.Deb.Control

  test "simple fields" do
    input = """
    Package: hello
    Version: 1.0
    Architecture: amd64
    """

    result = Control.parse(input)
    assert result["Package"] == "hello"
    assert result["Version"] == "1.0"
    assert result["Architecture"] == "amd64"
  end

  test "multiline Description" do
    input = """
    Package: test
    Description: short desc
     Long description line 1.
     Long description line 2.
    """

    result = Control.parse(input)

    assert result["Description"] ==
             "short desc\nLong description line 1.\nLong description line 2."
  end

  test "continuation lines with tab" do
    input = "Key: value\n\tmore value\n"
    result = Control.parse(input)
    assert result["Key"] == "value\nmore value"
  end
end
