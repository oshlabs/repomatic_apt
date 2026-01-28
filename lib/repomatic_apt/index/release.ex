defmodule RepomaticApt.Index.Release do
  @moduledoc """
  Generate Release index files.
  """

  @doc """
  Generate a Release file string.

  Options:
  - `:suite` - suite name (e.g. "jammy")
  - `:codename` - codename (e.g. "jammy")
  - `:architectures` - list of architectures
  - `:components` - list of components
  - `:origin` - origin string
  - `:label` - label string
  - `:date` - DateTime for the Date field (defaults to now)
  - `:files` - list of `{relative_path, content}` tuples for SHA256 entries
  """
  @spec generate(keyword()) :: String.t()
  def generate(opts) do
    date = opts[:date] || DateTime.utc_now()

    header_fields =
      [
        {"Origin", opts[:origin]},
        {"Label", opts[:label]},
        {"Suite", opts[:suite]},
        {"Codename", opts[:codename]},
        {"Date", format_date(date)},
        {"Architectures", opts[:architectures] && Enum.join(opts[:architectures], " ")},
        {"Components", opts[:components] && Enum.join(opts[:components], " ")}
      ]
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Enum.map(fn {k, v} -> "#{k}: #{v}" end)
      |> Enum.join("\n")

    files = opts[:files] || []

    sha256_section =
      if files != [] do
        entries =
          files
          |> Enum.map(fn {path, content} ->
            hash = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
            size = byte_size(content)
            " #{hash} #{pad_size(size)} #{path}"
          end)
          |> Enum.join("\n")

        "\nSHA256:\n" <> entries
      else
        ""
      end

    header_fields <> sha256_section <> "\n"
  end

  defp pad_size(size) do
    size |> Integer.to_string() |> String.pad_leading(8)
  end

  defp format_date(%DateTime{} = dt) do
    Calendar.strftime(dt, "%a, %d %b %Y %H:%M:%S UTC")
  end
end
