defmodule RepomaticApt.Config do
  @moduledoc """
  Configuration for RepomaticApt.

  Stores opts passed at startup in an Agent. Each accessor checks the
  Agent state first, then falls back to `Application.get_env/3`.
  """

  use Agent

  alias RepomaticApt.Gpg.Key
  alias RepomaticApt.Store.Backend.Local

  @spec start_link(keyword()) :: Agent.on_start()
  def start_link(opts \\ []) do
    Agent.start_link(fn -> build_config(opts) end, name: __MODULE__)
  end

  defp build_config(opts) do
    Map.new(opts)
  end

  @spec repo_root() :: String.t()
  def repo_root, do: get(:repo_root, "/var/lib/repomatic_apt/repo")

  @spec port() :: non_neg_integer()
  def port, do: get(:port, 4080)

  @spec distributions() :: [map()]
  def distributions, do: get(:distributions, [])

  @spec find_distribution(String.t()) :: map()
  def find_distribution(name) do
    distributions()
    |> Enum.find(%{}, fn d -> d[:suite] == name || d[:codename] == name end)
  end

  @spec ip() :: :inet.socket_address()
  def ip, do: get(:ip, {0, 0, 0, 0})

  @spec signing_key() :: Key.t() | nil
  def signing_key, do: get(:signing_key)

  @doc "Maximum upload size in bytes (default 100 MB)."
  @spec max_upload_size() :: non_neg_integer()
  def max_upload_size, do: get(:max_upload_size, 100 * 1024 * 1024)

  @doc """
  Directory for spooling uploads and extracting bulk archives (default: the
  system temp dir). Needs room for roughly twice the largest upload.
  """
  @spec upload_tmp_dir() :: Path.t()
  def upload_tmp_dir, do: get(:upload_tmp_dir, System.tmp_dir!())

  @doc "API bearer token for authentication. nil means no auth required."
  @spec api_token() :: String.t() | nil
  def api_token, do: get(:api_token)

  @doc "Read-only token for repository access. nil means read paths are open."
  @spec ro_token() :: String.t() | nil
  def ro_token, do: get(:ro_token)

  @doc "Returns the storage backend as a `{module, state}` tuple."
  @spec backend() :: {module(), term()}
  def backend do
    Agent.get(__MODULE__, fn state ->
      if Map.has_key?(state, :backend) do
        Map.get(state, :backend)
      else
        root =
          if Map.has_key?(state, :repo_root) do
            Map.get(state, :repo_root)
          else
            Application.get_env(:repomatic_apt, :repo_root, "/var/lib/repomatic_apt/repo")
          end

        {Local, Local.new(root)}
      end
    end)
  end

  @doc "Set a config value at runtime."
  @spec put(atom(), term()) :: :ok
  def put(key, value) do
    Agent.update(__MODULE__, fn state -> Map.put(state, key, value) end)
  end

  defp get(key, default \\ nil) do
    Agent.get(__MODULE__, fn state ->
      if Map.has_key?(state, key) do
        Map.get(state, key)
      else
        Application.get_env(:repomatic_apt, key, default)
      end
    end)
  end
end
