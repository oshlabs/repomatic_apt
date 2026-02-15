defmodule RepomaticApt.Store.Backend.Local do
  @moduledoc """
  Local filesystem storage backend.

  Writes are atomic (temp file + rename) to prevent partial reads.
  """

  @behaviour RepomaticApt.Store.Backend

  defstruct [:repo_root]

  @type t :: %__MODULE__{repo_root: String.t()}

  @spec new(String.t()) :: t()
  def new(repo_root) do
    %__MODULE__{repo_root: repo_root}
  end

  @impl true
  def put(%__MODULE__{repo_root: root}, path, content) do
    full_path = Path.join(root, path)
    full_path |> Path.dirname() |> File.mkdir_p!()
    tmp_path = full_path <> ".tmp.#{:erlang.unique_integer([:positive])}"
    File.write!(tmp_path, content)
    File.rename!(tmp_path, full_path)
    :ok
  end

  @impl true
  def get(%__MODULE__{repo_root: root}, path) do
    File.read(Path.join(root, path))
  end

  @impl true
  def delete(%__MODULE__{repo_root: root}, path) do
    case File.rm(Path.join(root, path)) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, _} = err -> err
    end
  end

  @impl true
  def exists?(%__MODULE__{repo_root: root}, path) do
    File.exists?(Path.join(root, path))
  end

  @impl true
  def list(%__MODULE__{repo_root: root}, path) do
    case File.ls(Path.join(root, path)) do
      {:ok, entries} -> {:ok, entries}
      {:error, :enoent} -> {:ok, []}
      {:error, _} = err -> err
    end
  end

  @impl true
  def file_path(%__MODULE__{repo_root: root}, path) do
    Path.join(root, path)
  end
end
