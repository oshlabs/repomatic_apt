defmodule RepomaticApt.Deb.Ar do
  @moduledoc """
  Parse ar archives.
  """

  @type member :: %{name: String.t(), data: binary()}

  @magic "!<arch>\n"
  @header_size 60

  @doc """
  Parse an ar archive binary into a list of members.
  """
  @spec parse(binary()) :: {:ok, [member()]} | {:error, term()}
  def parse(<<@magic, rest::binary>>) do
    parse_members(rest, [])
  end

  def parse(_), do: {:error, :invalid_magic}

  defp parse_members(<<>>, acc), do: {:ok, Enum.reverse(acc)}

  defp parse_members(data, _acc) when byte_size(data) < @header_size do
    {:error, :truncated_header}
  end

  defp parse_members(<<header::binary-size(@header_size), rest::binary>>, acc) do
    <<name_raw::binary-size(16), _mtime::binary-size(12), _owner::binary-size(6),
      _group::binary-size(6), _mode::binary-size(8), size_raw::binary-size(10), "`\n">> = header

    name = name_raw |> String.trim_trailing() |> String.trim_trailing("/")
    size = size_raw |> String.trim() |> String.to_integer()

    if byte_size(rest) < size do
      {:error, :truncated_data}
    else
      <<data::binary-size(size), rest2::binary>> = rest

      # Ar pads odd-size members with a newline byte
      rest2 =
        if rem(size, 2) == 1 do
          case rest2 do
            <<"\n", r::binary>> -> r
            r -> r
          end
        else
          rest2
        end

      parse_members(rest2, [%{name: name, data: data} | acc])
    end
  end

  defp parse_members(_, _acc), do: {:error, :invalid_header}
end
