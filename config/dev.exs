import Config

config :repomatic_apt,
  repo_root: "/var/lib/repomatic_apt/repo",
  port: 4080,
  ip: {0, 0, 0, 0},
  start_server: false,
  api_token: nil,
  max_upload_size: 104_857_600,
  signing_key: nil,
  signing_key_uid: nil,
  # certfile: "/path/to/cert.pem",
  # keyfile: "/path/to/key.pem",
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
