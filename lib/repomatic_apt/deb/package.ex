defmodule RepomaticApt.Deb.Package do
  @moduledoc """
  Extract metadata from a `.deb` binary.
  """

  alias RepomaticApt.Deb.{Ar, Control}

  @type t :: %__MODULE__{
          name: String.t() | nil,
          version: String.t() | nil,
          architecture: String.t() | nil,
          maintainer: String.t() | nil,
          installed_size: String.t() | nil,
          depends: String.t() | nil,
          section: String.t() | nil,
          priority: String.t() | nil,
          description: String.t() | nil,
          filename: String.t() | nil,
          size: non_neg_integer() | nil,
          sha256: String.t() | nil,
          extra_fields: %{String.t() => String.t()}
        }

  defstruct [
    :name,
    :version,
    :architecture,
    :maintainer,
    :installed_size,
    :depends,
    :section,
    :priority,
    :description,
    :filename,
    :size,
    :sha256,
    extra_fields: %{}
  ]

  @known_fields ~w(Package Version Architecture Maintainer Installed-Size Depends Section Priority Description)

  @doc """
  Extract package metadata from a `.deb` binary.
  """
  @spec extract(binary()) :: {:ok, t()} | {:error, term()}
  def extract(deb_binary) when is_binary(deb_binary) do
    with {:ok, members} <- Ar.parse(deb_binary),
         {:ok, control_tar} <- find_control_tar(members),
         {:ok, control_data} <- extract_control(control_tar) do
      fields = Control.parse(control_data)

      extra = Map.drop(fields, @known_fields)

      package = %__MODULE__{
        name: fields["Package"],
        version: fields["Version"],
        architecture: fields["Architecture"],
        maintainer: fields["Maintainer"],
        installed_size: fields["Installed-Size"],
        depends: fields["Depends"],
        section: fields["Section"],
        priority: fields["Priority"],
        description: fields["Description"],
        size: byte_size(deb_binary),
        sha256: :crypto.hash(:sha256, deb_binary) |> Base.encode16(case: :lower),
        extra_fields: extra
      }

      {:ok, package}
    end
  end

  defp find_control_tar(members) do
    case Enum.find(members, fn m -> m.name in ["control.tar.gz", "control.tar"] end) do
      nil -> {:error, :no_control_tar}
      member -> {:ok, member}
    end
  end

  defp extract_control(%{name: "control.tar.gz", data: data}) do
    decompressed = :zlib.gunzip(data)
    extract_control_from_tar(decompressed)
  end

  defp extract_control(%{name: "control.tar", data: data}) do
    extract_control_from_tar(data)
  end

  defp extract_control_from_tar(tar_data) do
    case :erl_tar.extract({:binary, tar_data}, [:memory]) do
      {:ok, files} ->
        case List.keyfind(files, ~c"./control", 0) || List.keyfind(files, ~c"control", 0) do
          {_, content} -> {:ok, to_string(content)}
          nil -> {:error, :no_control_file}
        end

      {:error, reason} ->
        {:error, {:tar_extract, reason}}
    end
  end
end
