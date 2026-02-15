defmodule RepomaticApt.Integration.DockerTest do
  use ExUnit.Case

  @moduletag :docker
  @moduletag timeout: 120_000

  alias RepomaticApt.{Config, MetadataStore, Repo}
  alias RepomaticApt.Test.DebHelper
  alias RepomaticApt.Store.Backend.Memory

  setup do
    {_, exit_code} = System.cmd("docker", ["info"], stderr_to_stdout: true)

    if exit_code != 0 do
      flunk("Docker is not available")
    end

    # Save current Config state and set up Memory backend
    old_state = Agent.get(Config, & &1)
    mem = Memory.new()

    Agent.update(Config, fn _ ->
      Map.merge(old_state, %{
        backend: {Memory, mem},
        distributions: [
          %{
            suite: "stable",
            codename: "stable",
            architectures: ["amd64"],
            components: ["main"],
            origin: "Repomatic",
            label: "Repomatic"
          }
        ]
      })
    end)

    MetadataStore.clear()

    # Start Bandit on a random port
    {:ok, bandit_pid} =
      Bandit.start_link(
        plug: RepomaticApt.Web.Router,
        port: 0,
        startup_log: false
      )

    {:ok, {_, port}} = ThousandIsland.listener_info(bandit_pid)

    on_exit(fn ->
      try do
        Supervisor.stop(bandit_pid, :normal, 5_000)
      catch
        :exit, _ -> :ok
      end

      Agent.update(Config, fn _ -> old_state end)
      MetadataStore.clear()
    end)

    %{port: port}
  end

  test "apt-get installs package from repomatic_apt repo", %{port: port} do
    # Build an installable .deb with a real file
    file_content = "hello from repomatic\n"

    deb =
      DebHelper.build_installable_deb("repomatic-test", "1.0-1", "amd64", [
        {"./usr/share/repomatic-test/hello.txt", file_content}
      ])

    # Upload to the repo
    {:ok, _pkg} = Repo.add_package("stable", "main", deb)

    # Export public key to a temp file
    pubkey = Repo.get_public_key()

    key_path =
      Path.join(
        System.tmp_dir!(),
        "repomatic_docker_test_#{System.unique_integer([:positive])}.asc"
      )

    File.write!(key_path, pubkey)

    try do
      # Run Debian container that installs the package and verifies the file
      {output, exit_code} =
        System.cmd(
          "docker",
          [
            "run",
            "--rm",
            "--network",
            "host",
            "-v",
            "#{key_path}:/etc/apt/keyrings/repomatic.asc:ro",
            "debian:trixie",
            "bash",
            "-c",
            """
            set -e
            echo 'deb [signed-by=/etc/apt/keyrings/repomatic.asc] http://localhost:#{port} stable main' \
              > /etc/apt/sources.list.d/repomatic.list
            apt-get update -o Acquire::AllowInsecureRepositories=false
            apt-get install -y repomatic-test
            cat /usr/share/repomatic-test/hello.txt
            """
          ],
          stderr_to_stdout: true
        )

      assert exit_code == 0,
             "Docker apt-get install failed (exit #{exit_code}):\n#{output}"

      assert output =~ "hello from repomatic"
    after
      File.rm(key_path)
    end
  end

  test "apt-get installs package with ro_token authentication", %{port: port} do
    ro_token = "test-read-token-#{System.unique_integer([:positive])}"
    Config.put(:ro_token, ro_token)

    file_content = "hello from authenticated repomatic\n"

    deb =
      DebHelper.build_installable_deb("repomatic-auth-test", "1.0-1", "amd64", [
        {"./usr/share/repomatic-auth-test/hello.txt", file_content}
      ])

    {:ok, _pkg} = Repo.add_package("stable", "main", deb)

    pubkey = Repo.get_public_key()

    key_path =
      Path.join(
        System.tmp_dir!(),
        "repomatic_docker_auth_test_#{System.unique_integer([:positive])}.asc"
      )

    File.write!(key_path, pubkey)

    try do
      {output, exit_code} =
        System.cmd(
          "docker",
          [
            "run",
            "--rm",
            "--network",
            "host",
            "-v",
            "#{key_path}:/etc/apt/keyrings/repomatic.asc:ro",
            "debian:trixie",
            "bash",
            "-c",
            """
            set -e
            mkdir -p /etc/apt/auth.conf.d
            echo 'machine localhost login apt password #{ro_token}' \
              > /etc/apt/auth.conf.d/repomatic.conf
            chmod 600 /etc/apt/auth.conf.d/repomatic.conf
            echo 'deb [signed-by=/etc/apt/keyrings/repomatic.asc] http://localhost:#{port} stable main' \
              > /etc/apt/sources.list.d/repomatic.list
            apt-get update -o Acquire::AllowInsecureRepositories=false
            apt-get install -y repomatic-auth-test
            cat /usr/share/repomatic-auth-test/hello.txt
            """
          ],
          stderr_to_stdout: true
        )

      assert exit_code == 0,
             "Docker apt-get install with ro_token failed (exit #{exit_code}):\n#{output}"

      assert output =~ "hello from authenticated repomatic"
    after
      Config.put(:ro_token, nil)
      File.rm(key_path)
    end
  end
end
