defmodule RepomaticApt.Repo do
  @moduledoc """
  High-level repository operations. Serializes index rebuilds via GenServer.
  """

  use GenServer

  require Logger

  alias RepomaticApt.{Config, MetadataStore, Store}
  alias RepomaticApt.Deb.Package
  alias RepomaticApt.Index.{Packages, Release, Compress}
  alias RepomaticApt.Gpg.Sign

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    {:ok, %{}}
  end

  @spec add_package(String.t(), String.t(), binary()) :: {:ok, Package.t()} | {:error, term()}
  def add_package(distribution, component, deb_binary) do
    GenServer.call(__MODULE__, {:add_package, distribution, component, deb_binary}, 30_000)
  end

  @spec add_packages_bulk(String.t(), String.t(), [{String.t(), binary()}]) ::
          {:ok, [Package.t()]} | {:error, [{String.t(), term()}]}
  def add_packages_bulk(distribution, component, deb_entries) do
    timeout = min(30_000 + length(deb_entries) * 10_000, 300_000)

    GenServer.call(
      __MODULE__,
      {:add_packages_bulk, distribution, component, deb_entries},
      timeout
    )
  end

  @spec remove_package(String.t(), String.t(), String.t(), String.t(), String.t()) :: :ok
  def remove_package(distribution, component, name, version, arch) do
    GenServer.call(__MODULE__, {:remove_package, distribution, component, name, version, arch})
  end

  @spec list_packages(String.t(), String.t(), String.t() | nil) :: [Package.t()]
  def list_packages(distribution, component, arch \\ nil) do
    if arch do
      MetadataStore.list(distribution, component, arch)
    else
      MetadataStore.list_all(distribution, component)
    end
  end

  @spec get_public_key() :: String.t() | nil
  def get_public_key do
    case Config.signing_key() do
      nil -> nil
      key -> RepomaticApt.Gpg.Key.export_public(key)
    end
  end

  @impl true
  def handle_call({:add_package, distribution, component, deb_binary}, _from, state) do
    case Package.extract(deb_binary) do
      {:ok, pkg} ->
        backend = Config.backend()
        filename = Store.deb_filename(pkg.name, pkg.version, pkg.architecture)
        pool_path = Store.pool_path(component, pkg.name, filename)
        Store.write_file(backend, pool_path, deb_binary)

        pkg = %{pkg | filename: pool_path}
        MetadataStore.put(distribution, component, pkg)

        Logger.info(
          "Package added: #{pkg.name} #{pkg.version} #{pkg.architecture} to #{distribution}/#{component}"
        )

        rebuild_indices(distribution)

        {:reply, {:ok, pkg}, state}

      {:error, reason} = err ->
        Logger.warning("Failed to extract package: #{inspect(reason)}")
        {:reply, err, state}
    end
  end

  def handle_call({:add_packages_bulk, distribution, component, deb_entries}, _from, state) do
    # Phase 1: validate all
    results =
      Enum.map(deb_entries, fn {filename, binary} ->
        case Package.extract(binary) do
          {:ok, pkg} -> {:ok, filename, binary, pkg}
          {:error, reason} -> {:error, filename, reason}
        end
      end)

    failures =
      Enum.flat_map(results, fn
        {:error, filename, reason} -> [{filename, reason}]
        _ -> []
      end)

    if failures != [] do
      {:reply, {:error, failures}, state}
    else
      # Phase 2: commit all
      backend = Config.backend()

      packages =
        Enum.map(results, fn {:ok, _filename, binary, pkg} ->
          filename = Store.deb_filename(pkg.name, pkg.version, pkg.architecture)
          pool_path = Store.pool_path(component, pkg.name, filename)
          Store.write_file(backend, pool_path, binary)

          pkg = %{pkg | filename: pool_path}
          MetadataStore.put(distribution, component, pkg)

          Logger.info(
            "Package added (bulk): #{pkg.name} #{pkg.version} #{pkg.architecture} to #{distribution}/#{component}"
          )

          pkg
        end)

      rebuild_indices(distribution)

      {:reply, {:ok, packages}, state}
    end
  end

  def handle_call({:remove_package, distribution, component, name, version, arch}, _from, state) do
    MetadataStore.delete(distribution, component, name, version, arch)

    Logger.info("Package removed: #{name} #{version} #{arch} from #{distribution}/#{component}")

    rebuild_indices(distribution)
    {:reply, :ok, state}
  end

  defp rebuild_indices(distribution) do
    dist_config = Config.find_distribution(distribution)
    components = dist_config[:components] || ["main"]
    architectures = dist_config[:architectures] || ["amd64"]
    backend = Config.backend()

    all_files =
      for component <- components, arch <- architectures do
        packages = MetadataStore.list(distribution, component, arch)
        content = Packages.generate(packages)
        gz_content = Compress.gzip(content)

        rel_dir = "dists/#{distribution}/#{component}/binary-#{arch}"

        packages_hash =
          Store.write_with_by_hash(backend, Path.join(rel_dir, "Packages"), content)

        gz_hash =
          Store.write_with_by_hash(backend, Path.join(rel_dir, "Packages.gz"), gz_content)

        Store.cleanup_by_hash(backend, rel_dir, [packages_hash, gz_hash])

        [
          {"#{component}/binary-#{arch}/Packages", content},
          {"#{component}/binary-#{arch}/Packages.gz", gz_content}
        ]
      end
      |> List.flatten()

    release_content =
      Release.generate(
        suite: dist_config[:suite] || distribution,
        codename: dist_config[:codename] || distribution,
        architectures: architectures,
        components: components,
        origin: dist_config[:origin],
        label: dist_config[:label],
        files: all_files
      )

    Store.write_file(backend, "dists/#{distribution}/Release", release_content)

    key = Config.signing_key()

    if key do
      release_gpg = Sign.detached(key, release_content)
      inrelease = Sign.clearsign(key, release_content)
      Store.write_file(backend, "dists/#{distribution}/Release.gpg", release_gpg)
      Store.write_file(backend, "dists/#{distribution}/InRelease", inrelease)
      Logger.debug("Signed Release for #{distribution}")
    end

    Logger.debug("Rebuilt indices for #{distribution}")
  end
end
