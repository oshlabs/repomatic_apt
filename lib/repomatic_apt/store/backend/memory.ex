defmodule RepomaticApt.Store.Backend.Memory do
  @moduledoc """
  In-memory storage backend backed by an Agent.

  Useful for testing (no temp dirs, no cleanup) and embedded/ephemeral use.
  Does not implement `file_path/2` — there is no filesystem.
  """

  @behaviour RepomaticApt.Store.Backend

  defstruct [:pid]

  @type t :: %__MODULE__{pid: pid()}

  @spec new() :: t()
  def new do
    {:ok, pid} = Agent.start_link(fn -> %{} end)
    %__MODULE__{pid: pid}
  end

  @impl true
  def put(%__MODULE__{pid: pid}, path, content) do
    Agent.update(pid, &Map.put(&1, path, IO.iodata_to_binary(content)))
    :ok
  end

  @impl true
  def get(%__MODULE__{pid: pid}, path) do
    case Agent.get(pid, &Map.fetch(&1, path)) do
      {:ok, _data} = ok -> ok
      :error -> {:error, :enoent}
    end
  end

  @impl true
  def delete(%__MODULE__{pid: pid}, path) do
    Agent.update(pid, &Map.delete(&1, path))
    :ok
  end

  @impl true
  def exists?(%__MODULE__{pid: pid}, path) do
    Agent.get(pid, &Map.has_key?(&1, path))
  end

  @impl true
  def list(%__MODULE__{pid: pid}, prefix) do
    entries =
      Agent.get(pid, fn store ->
        normalized = if prefix == "", do: "", else: prefix <> "/"

        store
        |> Map.keys()
        |> Enum.filter(&String.starts_with?(&1, normalized))
        |> Enum.map(&String.replace_leading(&1, normalized, ""))
        |> Enum.map(fn rel -> rel |> String.split("/") |> hd() end)
        |> Enum.uniq()
      end)

    {:ok, entries}
  end
end
