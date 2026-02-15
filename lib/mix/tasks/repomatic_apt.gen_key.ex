defmodule Mix.Tasks.RepomaticApt.GenKey do
  @moduledoc """
  Generates a signing key for RepomaticApt.

      mix repomatic_apt.gen_key [--output FILE] [--uid UID] [--bits BITS]

  ## Options

    * `--output` — output file path (default: `signing_key.etf`)
    * `--uid` — key UID (default: `RepomaticApt <repomatic_apt@localhost>`)
    * `--bits` — RSA key size (default: 4096)

  Writes the ETF key file and a companion `.asc` public key file.
  """

  use Mix.Task

  @shortdoc "Generate a signing key for RepomaticApt"

  @impl true
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args, strict: [output: :string, uid: :string, bits: :integer])

    output = opts[:output] || "signing_key.etf"
    uid = opts[:uid] || "RepomaticApt <repomatic_apt@localhost>"
    bits = opts[:bits] || 4096

    Mix.shell().info("Generating #{bits}-bit RSA key with UID: #{uid}")

    key = RepomaticApt.Gpg.Key.generate(bits: bits, uid: uid)

    File.write!(output, RepomaticApt.Gpg.Key.export_etf(key))
    Mix.shell().info("Wrote #{output}")

    asc_path = Path.rootname(output) <> ".asc"
    File.write!(asc_path, RepomaticApt.Gpg.Key.export_public(key))
    Mix.shell().info("Wrote #{asc_path}")
  end
end
