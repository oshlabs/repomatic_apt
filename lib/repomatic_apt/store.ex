defmodule RepomaticApt.Store do
  @moduledoc """
  File storage with pool layout, by-hash support, and pluggable backends.

  Path utility functions (`pool_path/3`, `pool_prefix/1`, `deb_filename/3`)
  are pure and take no backend argument.

  I/O functions delegate to a `{module, state}` backend tuple.
  """

  @type backend :: {module(), term()}

  @doc """
  Compute the pool path for a package.

  Packages starting with "lib" use `lib<first-char>` prefix,
  others use just the first character.

      iex> RepomaticApt.Store.pool_path("main", "nginx", "nginx_1.0_amd64.deb")
      "pool/main/n/nginx/nginx_1.0_amd64.deb"

      iex> RepomaticApt.Store.pool_path("main", "libxml2", "libxml2_2.9_amd64.deb")
      "pool/main/libx/libxml2/libxml2_2.9_amd64.deb"
  """
  @spec pool_path(String.t(), String.t(), String.t()) :: String.t()
  def pool_path(component, name, filename) do
    prefix = pool_prefix(name)
    Path.join(["pool", component, prefix, name, filename])
  end

  @doc """
  Compute the pool prefix for a package name.
  """
  @spec pool_prefix(String.t()) :: String.t()
  def pool_prefix("lib" <> <<c::utf8, _rest::binary>>), do: "lib" <> <<c::utf8>>
  def pool_prefix(<<c::utf8, _rest::binary>>), do: <<c::utf8>>

  @doc """
  Build the deb filename from package metadata.
  """
  @spec deb_filename(String.t(), String.t(), String.t()) :: String.t()
  def deb_filename(name, version, architecture) do
    "#{name}_#{version}_#{architecture}.deb"
  end

  @doc """
  Store a file at the given relative path via the backend.
  """
  @spec write_file(backend(), String.t(), iodata()) :: :ok
  def write_file({mod, state}, relative_path, content) do
    mod.put(state, relative_path, content)
  end

  @doc """
  Write a file and its by-hash copy via the backend.

  Returns the SHA256 hex hash of the content.
  """
  @spec write_with_by_hash(backend(), String.t(), iodata()) :: String.t()
  def write_with_by_hash({mod, state} = _backend, relative_path, content) do
    hash = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
    dir = Path.dirname(relative_path)
    by_hash_relative = Path.join([dir, "by-hash", "SHA256", hash])

    mod.put(state, relative_path, content)
    mod.put(state, by_hash_relative, content)

    hash
  end

  @doc """
  Clean up old by-hash entries, keeping only hashes present in `current_hashes`.
  """
  @spec cleanup_by_hash(backend(), String.t(), [String.t()]) :: :ok
  def cleanup_by_hash({mod, state}, by_hash_dir, current_hashes) do
    sha_dir = Path.join([by_hash_dir, "by-hash", "SHA256"])

    case mod.list(state, sha_dir) do
      {:ok, entries} ->
        current_set = MapSet.new(current_hashes)

        entries
        |> Enum.reject(&MapSet.member?(current_set, &1))
        |> Enum.each(fn old_hash ->
          mod.delete(state, Path.join(sha_dir, old_hash))
        end)

      {:error, _} ->
        :ok
    end

    :ok
  end
end
