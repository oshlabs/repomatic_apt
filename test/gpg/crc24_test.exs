defmodule RepomaticApt.Gpg.Crc24Test do
  use ExUnit.Case, async: true

  alias RepomaticApt.Gpg.Crc24

  test "empty data returns init value" do
    assert Crc24.compute(<<>>) == 0xB704CE
  end

  test "computes deterministic results" do
    a = Crc24.compute("Hello, World!")
    b = Crc24.compute("Hello, World!")
    assert a == b
  end

  test "different data produces different CRC" do
    refute Crc24.compute("abc") == Crc24.compute("def")
  end

  test "result is 24 bits" do
    result = Crc24.compute("test data for crc24 computation")
    assert result >= 0
    assert result <= 0xFFFFFF
  end
end
