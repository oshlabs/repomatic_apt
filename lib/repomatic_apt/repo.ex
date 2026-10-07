defmodule RepomaticApt.Repo do
  @moduledoc """
  High-level repository operations. Serializes index rebuilds via GenServer.
  """

  use GenServer

  require Logger

  alias RepomaticApt.{Config, MetadataStore, Store}
  alias RepomaticApt.Deb.Package
  alias RepomaticApt.Gpg.Key
  alias RepomaticApt.Index.{Packages, Release, Compress}
  alias RepomaticApt.Gpg.Sign

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec rescan_pool() :: {:ok, non_neg_integer()}
  def rescan_pool do
    GenServer.call(__MODULE__, :rescan_pool, 300_000)
  end

  @impl true
  def init(_opts) do
    resolve_signing_key()
    load_from_indices()
    {:ok, %{}}
  end

  defp resolve_signing_key do
    case Config.signing_key() do
      %Key{} ->
        Logger.info("Using signing key from configuration")
        :ok

      nil ->
        key_path = Path.join(Config.repo_root(), "signing_key.etf")

        case File.read(key_path) do
          {:ok, data} ->
            key = Key.import_etf!(data)
            Config.put(:signing_key, key)
            Logger.info("Loaded signing key from #{key_path}")

          {:error, _} ->
            uid =
              Application.get_env(:repomatic_apt, :signing_key_uid) ||
                "RepomaticApt <repomatic_apt@localhost>"

            key = Key.generate(uid: uid)

            with :ok <- File.mkdir_p(Path.dirname(key_path)),
                 :ok <- File.write(key_path, Key.export_etf(key)) do
              Logger.info("Generated new signing key, saved to #{key_path}")
            else
              {:error, reason} ->
                Logger.warning(
                  "Generated signing key but could not save to #{key_path}: #{inspect(reason)}"
                )
            end

            Config.put(:signing_key, key)
        end
    end
  end

  defp load_from_indices do
    backend = Config.backend()
    distributions = Config.distributions()

    count =
      Enum.reduce(distributions, 0, fn dist, acc ->
        suite = dist[:suite] || dist[:codename]
        components = dist[:components] || ["main"]
        architectures = dist[:architectures] || ["amd64"]

        Enum.reduce(components, acc, fn component, acc2 ->
          Enum.reduce(architectures, acc2, fn arch, acc3 ->
            path = "dists/#{suite}/#{component}/binary-#{arch}/Packages"

            case Store.read_file(backend, path) do
              {:ok, content} ->
                packages = Packages.parse(content)

                Enum.each(packages, fn pkg ->
                  MetadataStore.put(suite, component, pkg)
                end)

                acc3 + length(packages)

              {:error, _} ->
                acc3
            end
          end)
        end)
      end)

    if count > 0 do
      Logger.info("Loaded #{count} package(s) from existing indices")
    end
  end

  @spec add_package(String.t(), String.t(), binary()) :: {:ok, Package.t()} | {:error, term()}
  def add_package(distribution, component, deb_binary) do
    GenServer.call(__MODULE__, {:add_package, distribution, component, deb_binary}, 30_000)
  end

  @doc """
  Add several packages atomically. `deb_entries` are `{basename, path}` pairs
  pointing at `.deb` files on disk (see `RepomaticApt.Archive.extract_debs/2`).

  Every file is validated before any is committed; on failure nothing is
  added and the failing files are returned. Files are read one at a time so
  memory use is bounded by the largest package, not the whole batch.
  """
  @spec add_packages_bulk(String.t(), String.t(), [RepomaticApt.Archive.deb_entry()]) ::
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
    # Phase 1: validate all. Only the parsed metadata is kept; the file
    # contents are dropped again after each extract.
    results =
      Enum.map(deb_entries, fn {filename, path} ->
        with {:ok, binary} <- File.read(path),
             {:ok, pkg} <- Package.extract(binary) do
          {:ok, filename, path, pkg}
        else
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
        Enum.map(results, fn {:ok, _filename, path, pkg} ->
          filename = Store.deb_filename(pkg.name, pkg.version, pkg.architecture)
          pool_path = Store.pool_path(component, pkg.name, filename)
          Store.write_file(backend, pool_path, File.read!(path))

          pkg = %{pkg | filename: pool_path}
          MetadataStore.put(distribution, component, pkg)

          Logger.info(
            "Package added (bulk): #{pkg.name} #{pkg.version} #{pkg.architecture} to #{distribution}/#{component}"
          )

          pkg
        end)

      rebuild_indices(distribution)

      # Release the per-package binaries promptly rather than waiting for
      # the next natural GC of this long-lived process.
      :erlang.garbage_collect()

      {:reply, {:ok, packages}, state}
    end
  end

  def handle_call(:rescan_pool, _from, state) do
    MetadataStore.clear()
    backend = Config.backend()
    distributions = Config.distributions()

    count =
      Enum.reduce(distributions, 0, fn dist, acc ->
        suite = dist[:suite] || dist[:codename]
        components = dist[:components] || ["main"]

        Enum.reduce(components, acc, fn component, comp_acc ->
          pool_dir = "pool/#{component}"

          deb_paths =
            case Store.list_recursive(backend, pool_dir) do
              {:ok, paths} -> Enum.filter(paths, &String.ends_with?(&1, ".deb"))
              {:error, _} -> []
            end

          Enum.reduce(deb_paths, comp_acc, fn deb_path, path_acc ->
            case Store.read_file(backend, deb_path) do
              {:ok, deb_binary} ->
                case Package.extract(deb_binary) do
                  {:ok, pkg} ->
                    pkg = %{pkg | filename: deb_path}
                    MetadataStore.put(suite, component, pkg)
                    path_acc + 1

                  {:error, reason} ->
                    Logger.warning("Rescan: failed to extract #{deb_path}: #{inspect(reason)}")
                    path_acc
                end

              {:error, reason} ->
                Logger.warning("Rescan: failed to read #{deb_path}: #{inspect(reason)}")
                path_acc
            end
          end)
        end)
      end)

    Enum.each(distributions, fn dist ->
      suite = dist[:suite] || dist[:codename]
      rebuild_indices(suite)
    end)

    Logger.info("Rescan complete: #{count} package(s) loaded from pool")
    {:reply, {:ok, count}, state}
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
