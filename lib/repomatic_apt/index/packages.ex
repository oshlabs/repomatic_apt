defmodule RepomaticApt.Index.Packages do
  @moduledoc """
  Generate Packages index files from package metadata.
  """

  alias RepomaticApt.Deb.Control
  alias RepomaticApt.Deb.Package

  @known_fields ~w(Package Version Architecture Maintainer Installed-Size Depends Section Priority Description Filename Size SHA256)

  @doc """
  Parse a Packages index file string back into a list of `%Package{}` structs.
  """
  @spec parse(String.t()) :: [Package.t()]
  def parse(content) when is_binary(content) do
    content
    |> String.split("\n\n")
    |> Enum.reject(&(String.trim(&1) == ""))
    |> Enum.map(&parse_stanza/1)
  end

  defp parse_stanza(stanza) do
    fields = Control.parse(stanza)
    extra = Map.drop(fields, @known_fields)

    size =
      case fields["Size"] do
        nil -> nil
        s -> String.to_integer(s)
      end

    %Package{
      name: fields["Package"],
      version: fields["Version"],
      architecture: fields["Architecture"],
      maintainer: fields["Maintainer"],
      installed_size: fields["Installed-Size"],
      depends: fields["Depends"],
      section: fields["Section"],
      priority: fields["Priority"],
      description: fields["Description"],
      filename: fields["Filename"],
      size: size,
      sha256: fields["SHA256"],
      extra_fields: extra
    }
  end

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
