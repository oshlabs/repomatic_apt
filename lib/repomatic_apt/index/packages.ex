defmodule RepomaticApt.Index.Packages do
  @moduledoc """
  Generate Packages index files from package metadata.
  """

  alias RepomaticApt.Deb.Package

  @doc """
  Generate a Packages file string from a list of `%Package{}` structs.

  Packages are sorted by name, then by version string (lexicographic descending).
  """
  @spec generate([Package.t()]) :: String.t()
  def generate(packages) when is_list(packages) do
    packages
    |> Enum.sort_by(&{&1.name, &1.version})
    |> Enum.map(&format_stanza/1)
    |> Enum.join("\n")
  end

  defp format_stanza(%Package{} = pkg) do
    fields =
      [
        {"Package", pkg.name},
        {"Version", pkg.version},
        {"Architecture", pkg.architecture},
        {"Maintainer", pkg.maintainer},
        {"Installed-Size", pkg.installed_size},
        {"Depends", pkg.depends},
        {"Section", pkg.section},
        {"Priority", pkg.priority},
        {"Filename", pkg.filename},
        {"Size", pkg.size},
        {"SHA256", pkg.sha256},
        {"Description", pkg.description}
      ]
      |> Enum.concat(Enum.map(pkg.extra_fields || %{}, fn {k, v} -> {k, v} end))
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Enum.map(&format_field/1)
      |> Enum.join("\n")

    fields <> "\n"
  end

  defp format_field({key, value}) when is_integer(value) do
    format_field({key, Integer.to_string(value)})
  end

  defp format_field({key, value}) do
    case String.split(to_string(value), "\n") do
      [single] ->
        "#{key}: #{single}"

      [first | rest] ->
        formatted_rest = Enum.map(rest, fn line -> " #{line}" end)
        Enum.join(["#{key}: #{first}" | formatted_rest], "\n")
    end
  end
end
