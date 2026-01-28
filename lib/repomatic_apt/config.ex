defmodule RepomaticApt.Config do
  @moduledoc """
  Configuration accessors for the RepomaticApt application.
  """

  alias RepomaticApt.Gpg.Key

  @spec repo_root() :: String.t()
  def repo_root, do: Application.get_env(:repomatic_apt, :repo_root, "/var/lib/repomatic_apt/repo")

  @spec port() :: non_neg_integer()
  def port, do: Application.get_env(:repomatic_apt, :port, 4080)

  @spec distributions() :: [map()]
  def distributions, do: Application.get_env(:repomatic_apt, :distributions, [])

  @spec find_distribution(String.t()) :: map()
  def find_distribution(name) do
    distributions()
    |> Enum.find(%{}, fn d -> d[:suite] == name || d[:codename] == name end)
  end

  @spec signing_key() :: Key.t() | nil
  def signing_key, do: Application.get_env(:repomatic_apt, :signing_key)

  @doc "Maximum upload size in bytes (default 100 MB)."
  @spec max_upload_size() :: non_neg_integer()
  def max_upload_size, do: Application.get_env(:repomatic_apt, :max_upload_size, 100 * 1024 * 1024)

  @doc "API bearer token for authentication. nil means no auth required."
  @spec api_token() :: String.t() | nil
  def api_token, do: Application.get_env(:repomatic_apt, :api_token)
end
