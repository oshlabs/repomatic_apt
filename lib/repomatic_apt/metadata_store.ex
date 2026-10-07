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

  @spec get(String.t(), String.t(), String.t(), String.t(), String.t()) :: Package.t() | nil
  def get(distribution, component, name, version, arch) do
    key = {distribution, component, arch, name, version}
    Agent.get(__MODULE__, &Map.get(&1, key))
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

  @doc """
  Packages that belong in the `binary-<arch>` index: those built for `arch`
  plus the architecture-independent (`Architecture: all`) ones, which Debian
  expects to appear in every per-architecture index.
  """
  @spec list_for_arch(String.t(), String.t(), String.t()) :: [Package.t()]
  def list_for_arch(distribution, component, "all"), do: list(distribution, component, "all")

  def list_for_arch(distribution, component, arch) do
    list(distribution, component, arch) ++ list(distribution, component, "all")
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
