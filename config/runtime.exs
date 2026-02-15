import Config

if config_env() == :prod do
  config :repomatic_apt,
    start_server: true

  if repo_root = System.get_env("REPOMATIC_REPO_ROOT") do
    config :repomatic_apt, repo_root: repo_root
  end

  if port = System.get_env("REPOMATIC_PORT") do
    config :repomatic_apt, port: String.to_integer(port)
  end

  if ip_str = System.get_env("REPOMATIC_IP") do
    {:ok, ip} = :inet.parse_address(String.to_charlist(ip_str))
    config :repomatic_apt, ip: ip
  end

  if token = System.get_env("REPOMATIC_API_TOKEN") do
    config :repomatic_apt, api_token: token
  end

  if max_upload = System.get_env("REPOMATIC_MAX_UPLOAD_SIZE") do
    config :repomatic_apt, max_upload_size: String.to_integer(max_upload)
  end

  if dists_json = System.get_env("REPOMATIC_DISTRIBUTIONS") do
    distributions =
      dists_json
      |> Jason.decode!()
      |> Enum.map(fn dist ->
        Map.new(dist, fn {k, v} -> {String.to_existing_atom(k), v} end)
      end)

    config :repomatic_apt, distributions: distributions
  end

  if key_path = System.get_env("REPOMATIC_SIGNING_KEY_PATH") do
    key = key_path |> File.read!() |> RepomaticApt.Gpg.Key.import_etf!()
    config :repomatic_apt, signing_key: key
  end

  if uid = System.get_env("REPOMATIC_SIGNING_KEY_UID") do
    config :repomatic_apt, signing_key_uid: uid
  end
end
