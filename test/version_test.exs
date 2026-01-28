defmodule RepomaticApt.VersionTest do
  use ExUnit.Case, async: true

  alias RepomaticApt.Version

  describe "parse/1" do
    test "simple version" do
      v = Version.parse("1.0")
      assert v.epoch == 0
      assert v.upstream == "1.0"
      assert v.revision == ""
    end

    test "version with epoch" do
      v = Version.parse("1:2.0")
      assert v.epoch == 1
      assert v.upstream == "2.0"
      assert v.revision == ""
    end

    test "version with revision" do
      v = Version.parse("1.0-2")
      assert v.epoch == 0
      assert v.upstream == "1.0"
      assert v.revision == "2"
    end

    test "version with epoch and revision" do
      v = Version.parse("3:1.0-4")
      assert v.epoch == 3
      assert v.upstream == "1.0"
      assert v.revision == "4"
    end

    test "upstream with hyphen" do
      v = Version.parse("1.0-beta-1")
      assert v.upstream == "1.0-beta"
      assert v.revision == "1"
    end
  end

  describe "compare/2" do
    test "1.0 < 1.1" do
      assert Version.compare(Version.parse("1.0"), Version.parse("1.1")) == :lt
    end

    test "1.0~rc1 < 1.0 (tilde sorts before everything)" do
      assert Version.compare(Version.parse("1.0~rc1"), Version.parse("1.0")) == :lt
    end

    test "1:0.1 > 999.999 (epoch wins)" do
      assert Version.compare(Version.parse("1:0.1"), Version.parse("999.999")) == :gt
    end

    test "1.0-1 < 1.0-2 (revision comparison)" do
      assert Version.compare(Version.parse("1.0-1"), Version.parse("1.0-2")) == :lt
    end

    test "1.0 < 1.0+dfsg1 (plus sorts after empty)" do
      assert Version.compare(Version.parse("1.0"), Version.parse("1.0+dfsg1")) == :lt
    end

    test "equal versions" do
      assert Version.compare(Version.parse("1.0-1"), Version.parse("1.0-1")) == :eq
    end

    test "2.0 > 1.9" do
      assert Version.compare(Version.parse("2.0"), Version.parse("1.9")) == :gt
    end
  end
end
