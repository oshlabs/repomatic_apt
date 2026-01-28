defmodule RepomaticApt.RepoTest do
  use ExUnit.Case

  alias RepomaticApt.{Repo, MetadataStore}
  alias RepomaticApt.Test.DebHelper

  setup do
    MetadataStore.clear()

    tmp =
      Path.join(System.tmp_dir!(), "repomatic_apt_repo_test_#{:erlang.unique_integer([:positive])}")

    File.mkdir_p!(tmp)
    Application.put_env(:repomatic_apt, :repo_root, tmp)

    Application.put_env(:repomatic_apt, :distributions, [
      %{
        suite: "stable",
        codename: "stable",
        architectures: ["amd64"],
        components: ["main"],
        origin: "RepomaticApt",
        label: "RepomaticApt"
      }
    ])

    on_exit(fn ->
      File.rm_rf!(tmp)
    end)

    %{repo_root: tmp}
  end

  test "add_package stores deb and creates indices", %{repo_root: root} do
    deb = DebHelper.build_deb("hello", "1.0-1", "amd64")
    assert {:ok, pkg} = Repo.add_package("stable", "main", deb)

    assert pkg.name == "hello"
    assert pkg.version == "1.0-1"
    assert pkg.filename =~ "pool/main/h/hello/"

    # Pool file exists
    assert File.exists?(Path.join(root, pkg.filename))

    # Packages index exists and contains the package
    packages_path = Path.join(root, "dists/stable/main/binary-amd64/Packages")
    assert File.exists?(packages_path)
    content = File.read!(packages_path)
    assert content =~ "Package: hello"
    assert content =~ "Version: 1.0-1"

    # Packages.gz exists
    assert File.exists?(Path.join(root, "dists/stable/main/binary-amd64/Packages.gz"))

    # Release file exists
    release_path = Path.join(root, "dists/stable/Release")
    assert File.exists?(release_path)
    release = File.read!(release_path)
    assert release =~ "Suite: stable"
    assert release =~ "SHA256:"

    # Signed files exist
    assert File.exists?(Path.join(root, "dists/stable/Release.gpg"))
    assert File.exists?(Path.join(root, "dists/stable/InRelease"))
  end

  test "remove_package removes from index", %{repo_root: root} do
    deb = DebHelper.build_deb("goodbye", "2.0", "amd64")
    {:ok, _pkg} = Repo.add_package("stable", "main", deb)

    packages_path = Path.join(root, "dists/stable/main/binary-amd64/Packages")
    assert File.read!(packages_path) =~ "Package: goodbye"

    :ok = Repo.remove_package("stable", "main", "goodbye", "2.0", "amd64")

    refute File.read!(packages_path) =~ "Package: goodbye"
  end

  test "list_packages returns added packages" do
    deb = DebHelper.build_deb("foo", "1.0", "amd64")
    {:ok, _} = Repo.add_package("stable", "main", deb)

    packages = Repo.list_packages("stable", "main", "amd64")
    assert length(packages) == 1
    assert hd(packages).name == "foo"
  end

  test "multiple packages in same component" do
    deb1 = DebHelper.build_deb("alpha", "1.0", "amd64")
    deb2 = DebHelper.build_deb("beta", "2.0", "amd64")

    {:ok, _} = Repo.add_package("stable", "main", deb1)
    {:ok, _} = Repo.add_package("stable", "main", deb2)

    packages = Repo.list_packages("stable", "main", "amd64")
    assert length(packages) == 2
    names = Enum.map(packages, & &1.name) |> Enum.sort()
    assert names == ["alpha", "beta"]
  end

  test "concurrent uploads don't lose packages" do
    debs =
      for i <- 1..5 do
        {"pkg#{i}", DebHelper.build_deb("pkg#{i}", "1.0", "amd64")}
      end

    tasks =
      Enum.map(debs, fn {_name, deb} ->
        Task.async(fn -> Repo.add_package("stable", "main", deb) end)
      end)

    results = Task.await_many(tasks, 30_000)
    assert Enum.all?(results, &match?({:ok, _}, &1))

    packages = Repo.list_packages("stable", "main", "amd64")
    assert length(packages) == 5
  end

  test "get_public_key returns armored key" do
    pubkey = Repo.get_public_key()
    assert pubkey =~ "-----BEGIN PGP PUBLIC KEY BLOCK-----"
  end

  test "returns error for invalid deb" do
    assert {:error, _} = Repo.add_package("stable", "main", "not a deb")
  end
end
