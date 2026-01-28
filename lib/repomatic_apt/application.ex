defmodule RepomaticApt.Application do
  use Application

  def start(_type, _args) do
    children =
      [
        RepomaticApt.MetadataStore,
        RepomaticApt.Repo
      ] ++ server_children()

    Supervisor.start_link(children, strategy: :one_for_one, name: RepomaticApt.Supervisor)
  end

  defp server_children do
    if Application.get_env(:repomatic_apt, :start_server, true) do
      [{Bandit, plug: RepomaticApt.Web.Router, port: RepomaticApt.Config.port()}]
    else
      []
    end
  end
end
