defmodule RepomaticApt do
  @moduledoc """
  RepomaticApt — an Elixir APT repository server.

  Can run standalone or be embedded in a parent supervision tree:

      # Standalone (Application callback starts it automatically)
      # config :repomatic_apt, repo_root: "/data/apt", ...

      # Embedded
      children = [
        {RepomaticApt, [
          repo_root: "/data/apt",
          distributions: [...],
          start_server: false
        ]}
      ]
  """

  use Supervisor

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    children =
      [
        {RepomaticApt.Config, opts},
        RepomaticApt.MetadataStore,
        RepomaticApt.Repo
      ] ++ maybe_bandit(opts)

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp maybe_bandit(opts) do
    start_server =
      Keyword.get(opts, :start_server) ||
        Application.get_env(:repomatic_apt, :start_server, false)

    if start_server do
      port =
        Keyword.get(opts, :port) ||
          Application.get_env(:repomatic_apt, :port, 4080)

      ip =
        Keyword.get(opts, :ip) ||
          Application.get_env(:repomatic_apt, :ip, {0, 0, 0, 0})

      [{Bandit, plug: RepomaticApt.Web.Router, port: port, ip: ip}]
    else
      []
    end
  end
end
