import Config

config :repomatic_apt,
  repo_root: "/var/lib/repomatic_apt/repo",
  port: 4080,
  ip: {0, 0, 0, 0},
  start_server: true,
  api_token: nil,
  ro_token: nil,
  max_upload_size: 104_857_600,
  signing_key: nil,
  signing_key_uid: nil,
  # certfile: "/path/to/cert.pem",
  # keyfile: "/path/to/key.pem",
  distributions: [
    %{
      suite: "bookworm",         # Debian release target (used in APT sources line)
      codename: "bookworm",      # release codename (often same as suite)
      architectures: ["amd64"],  # supported CPU architectures
      components: ["main"],      # repo sections (main, contrib, non-free, ...)
      origin: "RepomaticApt",    # metadata project or team providing the repo
      label: "RepomaticApt"      # metadata label shown to APT users
    }
  ]
