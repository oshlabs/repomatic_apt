defmodule RepomaticApt.MetadataStore do
  @moduledoc """
  In-memory store for package metadata, backed by an Agent.
  """

  use Agent

  alias RepomaticApt.Deb.Package

  @spec start_link(keyword()) :: Agent.on_start()
  def start_link(_opts \\ []) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  @spec put(String.t(), String.t(), Package.t()) :: :ok
  def put(distribution, component, package) do
    key = {distribution, component, package.architecture, package.name, package.version}
    Agent.update(__MODULE__, &Map.put(&1, key, package))
  end

  @spec delete(String.t(), String.t(), String.t(), String.t(), String.t()) :: :ok
  def delete(distribution, component, name, version, arch) do
    key = {distribution, component, arch, name, version}
    Agent.update(__MODULE__, &Map.delete(&1, key))
  end

  @spec list(String.t(), String.t(), String.t()) :: [Package.t()]
  def list(distribution, component, arch) do
    Agent.get(__MODULE__, fn store ->
      store
      |> Enum.filter(fn {{d, c, a, _n, _v}, _pkg} ->
        d == distribution && c == component && a == arch
      end)
      |> Enum.map(fn {_key, pkg} -> pkg end)
    end)
  end

  @spec list_all(String.t(), String.t()) :: [Package.t()]
  def list_all(distribution, component) do
    Agent.get(__MODULE__, fn store ->
      store
      |> Enum.filter(fn {{d, c, _a, _n, _v}, _pkg} ->
        d == distribution && c == component
      end)
      |> Enum.map(fn {_key, pkg} -> pkg end)
    end)
  end

  @spec clear() :: :ok
  def clear do
    Agent.update(__MODULE__, fn _ -> %{} end)
  end
end
