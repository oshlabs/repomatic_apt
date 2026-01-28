defmodule RepomaticApt.Store do
  @moduledoc """
  File storage with pool layout, by-hash support, and atomic writes.
  """

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
  Store a file at the given path under repo_root, creating directories as needed.
  """
  @spec write_file(String.t(), String.t(), iodata()) :: String.t()
  def write_file(repo_root, relative_path, content) do
    full_path = Path.join(repo_root, relative_path)
    full_path |> Path.dirname() |> File.mkdir_p!()
    File.write!(full_path, content)
    full_path
  end

  @doc """
  Atomically write a file by writing to a temp file then renaming.
  """
  @spec write_file_atomic(String.t(), String.t(), iodata()) :: String.t()
  def write_file_atomic(repo_root, relative_path, content) do
    full_path = Path.join(repo_root, relative_path)
    full_path |> Path.dirname() |> File.mkdir_p!()
    tmp_path = full_path <> ".tmp.#{:erlang.unique_integer([:positive])}"
    File.write!(tmp_path, content)
    File.rename!(tmp_path, full_path)
    full_path
  end

  @doc """
  Write a file atomically and also store it under by-hash.

  Returns `{full_path, by_hash_path}`.
  """
  @spec write_with_by_hash(String.t(), String.t(), iodata()) :: {String.t(), String.t()}
  def write_with_by_hash(repo_root, relative_path, content) do
    full_path = write_file_atomic(repo_root, relative_path, content)

    hash = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
    dir = Path.dirname(relative_path)
    by_hash_relative = Path.join([dir, "by-hash", "SHA256", hash])
    by_hash_full = write_file(repo_root, by_hash_relative, content)

    {full_path, by_hash_full}
  end

  @doc """
  Clean up old by-hash entries, keeping only hashes present in `current_hashes`.
  """
  @spec cleanup_by_hash(String.t(), String.t(), [String.t()]) :: :ok
  def cleanup_by_hash(repo_root, by_hash_dir, current_hashes) do
    full_dir = Path.join([repo_root, by_hash_dir, "by-hash", "SHA256"])

    if File.dir?(full_dir) do
      current_set = MapSet.new(current_hashes)

      full_dir
      |> File.ls!()
      |> Enum.reject(&MapSet.member?(current_set, &1))
      |> Enum.each(fn old_hash ->
        File.rm(Path.join(full_dir, old_hash))
      end)
    end

    :ok
  end
end
