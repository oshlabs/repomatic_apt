defmodule Mix.Tasks.RepomaticApt.GenKey do
  @moduledoc """
  Generates a signing key for RepomaticApt.

      mix repomatic_apt.gen_key [--output FILE] [--uid UID] [--bits BITS] [--k8s]

  ## Options

    * `--output` — output file path (default: `signing_key.etf`)
    * `--uid` — key UID (default: `RepomaticApt <repomatic_apt@localhost>`)
    * `--bits` — RSA key size (default: 4096)
    * `--k8s` — print a Kubernetes Secret YAML to stdout instead of writing files

  Without `--k8s`, writes the ETF key file and a companion `.asc` public key file.

  With `--k8s`, prints a Secret YAML you can pipe to `kubectl apply -f -` or
  paste into your manifests. The signing key is stored in `stringData` and
  can be referenced via the `REPOMATIC_SIGNING_KEY` env var.
  """

  use Mix.Task

  @shortdoc "Generate a signing key for RepomaticApt"

  @impl true
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args, strict: [output: :string, uid: :string, bits: :integer, k8s: :boolean])

    uid = opts[:uid] || "RepomaticApt <repomatic_apt@localhost>"
    bits = opts[:bits] || 4096

    Mix.shell().info("Generating #{bits}-bit RSA key with UID: #{uid}")

    key = RepomaticApt.Gpg.Key.generate(bits: bits, uid: uid)

    if opts[:k8s] do
      etf = RepomaticApt.Gpg.Key.export_etf(key)
      yaml = k8s_secret_yaml(etf)
      IO.puts(yaml)
    else
      output = opts[:output] || "signing_key.etf"

      File.write!(output, RepomaticApt.Gpg.Key.export_etf(key))
      Mix.shell().info("Wrote #{output}")

      asc_path = Path.rootname(output) <> ".asc"
      File.write!(asc_path, RepomaticApt.Gpg.Key.export_public(key))
      Mix.shell().info("Wrote #{asc_path}")
    end
  end

  defp k8s_secret_yaml(etf_data) do
    """
    apiVersion: v1
    kind: Secret
    metadata:
      name: repomatic-signing-key
    type: Opaque
    stringData:
      signing-key: "#{etf_data}"\
    """
  end
end
