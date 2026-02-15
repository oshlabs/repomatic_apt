defmodule RepomaticApt.Application do
  use Application

  def start(_type, _args) do
    if Application.get_env(:repomatic_apt, :autostart, true) do
      RepomaticApt.start_link([])
    else
      # Embedded: parent starts {RepomaticApt, opts} in its own supervision tree
      Supervisor.start_link([], strategy: :one_for_one, name: RepomaticApt.AppSupervisor)
    end
  end
end
