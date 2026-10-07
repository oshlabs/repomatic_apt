defmodule RepomaticApt.BuildTest do
  use ExUnit.Case, async: true

  alias RepomaticApt.Build

  describe "version/0" do
    test "matches the version in mix.exs" do
      assert Build.version() == Mix.Project.config()[:version]
      assert Build.version() =~ ~r/^\d+\.\d+\.\d+/
    end
  end

  describe "git_rev/0" do
    test "is nil or a short hex revision with optional -dirty suffix" do
      case Build.git_rev() do
        nil -> :ok
        rev -> assert rev =~ ~r/^[0-9a-f]{7,}(-dirty)?$/
      end
    end
  end

  describe "display/0" do
    test "is v<version> plus the revision in parentheses when known" do
      case Build.git_rev() do
        nil -> assert Build.display() == "v#{Build.version()}"
        rev -> assert Build.display() == "v#{Build.version()} (#{rev})"
      end
    end
  end
end
