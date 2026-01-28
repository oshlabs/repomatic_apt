import Config

config :repomatic_apt,
  repo_root: "/var/lib/repomatic_apt/repo",
  port: 4080,
  distributions: [
    %{
      suite: "stable",
      codename: "stable",
      architectures: ["amd64"],
      components: ["main"],
      origin: "RepomaticApt",
      label: "RepomaticApt"
    }
  ]

import_config "#{config_env()}.exs"
