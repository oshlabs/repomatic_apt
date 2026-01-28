defmodule RepomaticApt.Version do
  @moduledoc """
  Debian version parsing and comparison.
  """

  @type t :: %__MODULE__{
          epoch: non_neg_integer(),
          upstream: String.t(),
          revision: String.t()
        }

  defstruct epoch: 0, upstream: "", revision: ""

  @doc """
  Parse a Debian version string into a `%Version{}`.

  Format: `[epoch:]upstream[-revision]`
  """
  @spec parse(String.t()) :: t()
  def parse(string) when is_binary(string) do
    {epoch, rest} =
      case String.split(string, ":", parts: 2) do
        [epoch_str, rest] -> {String.to_integer(epoch_str), rest}
        [rest] -> {0, rest}
      end

    {upstream, revision} =
      case :binary.match(rest, "-") do
        :nomatch ->
          {rest, ""}

        _ ->
          # Split on the *last* hyphen
          parts = String.split(rest, "-")
          revision = List.last(parts)
          upstream = parts |> Enum.drop(-1) |> Enum.join("-")
          {upstream, revision}
      end

    %__MODULE__{epoch: epoch, upstream: upstream, revision: revision}
  end

  @doc """
  Compare two versions. Returns `:lt`, `:eq`, or `:gt`.
  """
  @spec compare(t(), t()) :: :lt | :eq | :gt
  def compare(%__MODULE__{} = a, %__MODULE__{} = b) do
    case int_cmp(a.epoch, b.epoch) do
      :eq ->
        case compare_strings(a.upstream, b.upstream) do
          :eq -> compare_strings(a.revision, b.revision)
          result -> result
        end

      result ->
        result
    end
  end

  defp int_cmp(a, b) when a < b, do: :lt
  defp int_cmp(a, b) when a > b, do: :gt
  defp int_cmp(_, _), do: :eq

  @doc false
  @spec compare_strings(String.t(), String.t()) :: :lt | :eq | :gt
  def compare_strings(a, b) do
    a_parts = split_version_string(a)
    b_parts = split_version_string(b)
    compare_parts(a_parts, b_parts)
  end

  # Split a version string into alternating non-digit and digit segments.
  defp split_version_string(""), do: []

  defp split_version_string(s) do
    {non_digit, rest} = take_while(s, &(!digit?(&1)))
    {digit, rest2} = take_while(rest, &digit?/1)
    [{non_digit, digit_to_int(digit)} | split_version_string(rest2)]
  end

  defp digit_to_int(""), do: 0
  defp digit_to_int(s), do: String.to_integer(s)

  defp digit?(c), do: c >= ?0 and c <= ?9

  defp take_while(<<>>, _fun), do: {"", ""}

  defp take_while(<<c::utf8, rest::binary>>, fun) do
    if fun.(c) do
      {taken, remaining} = take_while(rest, fun)
      {<<c::utf8, taken::binary>>, remaining}
    else
      {"", <<c::utf8, rest::binary>>}
    end
  end

  defp compare_parts([], []), do: :eq

  defp compare_parts([], [{non_digit, num} | rest]),
    do: compare_parts([{"", 0}], [{non_digit, num} | rest])

  defp compare_parts([{non_digit, num} | rest], []),
    do: compare_parts([{non_digit, num} | rest], [{"", 0}])

  defp compare_parts([{nd_a, num_a} | rest_a], [{nd_b, num_b} | rest_b]) do
    case compare_lexical(nd_a, nd_b) do
      :eq ->
        case int_cmp(num_a, num_b) do
          :eq -> compare_parts(rest_a, rest_b)
          result -> result
        end

      result ->
        result
    end
  end

  # Debian lexical comparison: letters sort before non-letters,
  # tilde sorts before everything (including empty).
  defp compare_lexical(a, b) do
    a_chars = String.to_charlist(a)
    b_chars = String.to_charlist(b)
    compare_chars(a_chars, b_chars)
  end

  defp compare_chars([], []), do: :eq
  defp compare_chars([], [?~ | _]), do: :gt
  defp compare_chars([?~ | _], []), do: :lt
  defp compare_chars([], _), do: :lt
  defp compare_chars(_, []), do: :gt

  defp compare_chars([a | rest_a], [b | rest_b]) do
    case int_cmp(char_order(a), char_order(b)) do
      :eq -> compare_chars(rest_a, rest_b)
      result -> result
    end
  end

  # Tilde sorts before everything (including empty string, handled above).
  # Letters sort before non-letters (except tilde).
  defp char_order(?~), do: -1

  defp char_order(c) when c in ?A..?Z or c in ?a..?z, do: c

  # Non-letter, non-tilde characters sort after letters.
  # ASCII letters are 65-90, 97-122. We put others after by adding 256.
  defp char_order(c), do: c + 256
end
