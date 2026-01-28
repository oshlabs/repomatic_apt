defmodule RepomaticApt.Deb.Control do
  @moduledoc """
  Parse RFC 822-style control stanzas.
  """

  @doc """
  Parse a control file string into a map of field name to value.
  """
  @spec parse(String.t()) :: %{String.t() => String.t()}
  def parse(string) do
    string
    |> String.split("\n")
    |> parse_lines(nil, nil, %{})
  end

  defp parse_lines([], key, value, acc) do
    finalize(key, value, acc)
  end

  defp parse_lines(["" | rest], key, value, acc) do
    parse_lines(rest, key, value, acc)
  end

  defp parse_lines([<<" ", continuation::binary>> | rest], key, value, acc) when key != nil do
    parse_lines(rest, key, value <> "\n" <> continuation, acc)
  end

  defp parse_lines([<<"\t", continuation::binary>> | rest], key, value, acc) when key != nil do
    parse_lines(rest, key, value <> "\n" <> continuation, acc)
  end

  defp parse_lines([line | rest], key, value, acc) do
    acc = finalize(key, value, acc)

    case String.split(line, ":", parts: 2) do
      [new_key, new_value] ->
        parse_lines(rest, String.trim(new_key), String.trim(new_value), acc)

      _ ->
        parse_lines(rest, key, value, acc)
    end
  end

  defp finalize(nil, _value, acc), do: acc
  defp finalize(key, value, acc), do: Map.put(acc, key, value)
end
