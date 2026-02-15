defmodule RepomaticAptTest do
  use ExUnit.Case

  describe "TLS configuration" do
    setup do
      old_certfile = Application.get_env(:repomatic_apt, :certfile)
      old_keyfile = Application.get_env(:repomatic_apt, :keyfile)

      on_exit(fn ->
        if old_certfile,
          do: Application.put_env(:repomatic_apt, :certfile, old_certfile),
          else: Application.delete_env(:repomatic_apt, :certfile)

        if old_keyfile,
          do: Application.put_env(:repomatic_apt, :keyfile, old_keyfile),
          else: Application.delete_env(:repomatic_apt, :keyfile)
      end)

      Application.delete_env(:repomatic_apt, :certfile)
      Application.delete_env(:repomatic_apt, :keyfile)
      :ok
    end

    defp bandit_opts(init_opts) do
      {:ok, {_sup_flags, children}} = RepomaticApt.init(init_opts)

      Enum.find_value(children, fn
        %{start: {Bandit, :start_link, [opts]}} -> opts
        _ -> nil
      end)
    end

    test "plain HTTP when no TLS opts" do
      opts = bandit_opts(start_server: true)
      assert opts[:plug] == RepomaticApt.Web.Router
      refute opts[:scheme]
      refute opts[:certfile]
      refute opts[:keyfile]
    end

    test "HTTPS when certfile and keyfile passed as opts" do
      opts = bandit_opts(start_server: true, certfile: "/certs/cert.pem", keyfile: "/certs/key.pem")
      assert opts[:scheme] == :https
      assert opts[:certfile] == "/certs/cert.pem"
      assert opts[:keyfile] == "/certs/key.pem"
    end

    test "HTTPS when certfile and keyfile set in app env" do
      Application.put_env(:repomatic_apt, :certfile, "/certs/cert.pem")
      Application.put_env(:repomatic_apt, :keyfile, "/certs/key.pem")

      opts = bandit_opts(start_server: true)
      assert opts[:scheme] == :https
      assert opts[:certfile] == "/certs/cert.pem"
      assert opts[:keyfile] == "/certs/key.pem"
    end

    test "plain HTTP when only certfile is set" do
      opts = bandit_opts(start_server: true, certfile: "/certs/cert.pem")
      refute opts[:scheme]
      refute opts[:certfile]
      refute opts[:keyfile]
    end

    test "plain HTTP when only keyfile is set" do
      opts = bandit_opts(start_server: true, keyfile: "/certs/key.pem")
      refute opts[:scheme]
      refute opts[:certfile]
      refute opts[:keyfile]
    end

    test "no Bandit child when start_server is false" do
      assert bandit_opts(start_server: false) == nil
    end
  end
end
