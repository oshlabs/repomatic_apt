defmodule RepomaticApt.Web.Ui do
  use Plug.Router

  alias RepomaticApt.{Config, Repo}

  plug(:match)
  plug(:dispatch)

  get "/" do
    distributions = Config.distributions()

    rows =
      Enum.map_join(distributions, "\n", fn dist ->
        components = Enum.join(dist[:components] || [], ", ")
        architectures = Enum.join(dist[:architectures] || [], ", ")
        suite = dist[:suite] || "unknown"

        """
        <tr>
          <td><a href="/ui/#{suite}">#{suite}</a></td>
          <td>#{dist[:codename] || ""}</td>
          <td>#{components}</td>
          <td>#{architectures}</td>
          <td>#{dist[:origin] || ""}</td>
        </tr>
        """
      end)

    html(conn, "Distributions", """
    <h2>Distributions</h2>
    <table>
      <thead><tr><th>Suite</th><th>Codename</th><th>Components</th><th>Architectures</th><th>Origin</th></tr></thead>
      <tbody>#{rows}</tbody>
    </table>
    <p><a href="/ui/setup">Setup Instructions</a></p>
    """)
  end

  get "/setup" do
    host = conn.host || "localhost"
    port = Config.port()
    base_url = "http://#{host}:#{port}"

    html(conn, "Setup Instructions", """
    <h2>Setup Instructions</h2>
    <h3>1. Import the signing key</h3>
    <pre><code>curl -fsSL #{base_url}/key.gpg | sudo gpg --dearmor -o /usr/share/keyrings/repomatic_apt.gpg</code></pre>
    <h3>2. Add the repository</h3>
    <pre><code>echo "deb [signed-by=/usr/share/keyrings/repomatic_apt.gpg] #{base_url} stable main" | sudo tee /etc/apt/sources.list.d/repomatic_apt.list</code></pre>
    <h3>3. Update package lists</h3>
    <pre><code>sudo apt update</code></pre>
    <p><a href="/ui">&larr; Back</a></p>
    """)
  end

  get "/:distribution" do
    dist_config = Config.find_distribution(distribution)
    components = dist_config[:components] || ["main"]
    architectures = dist_config[:architectures] || ["amd64"]

    rows =
      for component <- components, arch <- architectures do
        packages = Repo.list_packages(distribution, component, arch)
        count = length(packages)

        """
        <tr>
          <td><a href="/ui/#{distribution}/#{component}/#{arch}">#{component}</a></td>
          <td>#{arch}</td>
          <td>#{count}</td>
        </tr>
        """
      end

    html(conn, distribution, """
    <h2>#{distribution}</h2>
    <p>Origin: #{dist_config[:origin] || "N/A"} | Label: #{dist_config[:label] || "N/A"}</p>
    <table>
      <thead><tr><th>Component</th><th>Architecture</th><th>Packages</th></tr></thead>
      <tbody>#{rows}</tbody>
    </table>
    <p><a href="/ui">&larr; Back</a></p>
    """)
  end

  get "/:distribution/:component/:arch" do
    packages =
      Repo.list_packages(distribution, component, arch)
      |> Enum.sort_by(& &1.name)

    rows =
      Enum.map_join(packages, "\n", fn pkg ->
        """
        <tr>
          <td><a href="/ui/#{distribution}/#{component}/#{arch}/#{pkg.name}/#{pkg.version}">#{pkg.name}</a></td>
          <td>#{pkg.version}</td>
          <td>#{(pkg.description || "") |> String.split("\n") |> hd()}</td>
        </tr>
        """
      end)

    html(conn, "#{distribution}/#{component}/#{arch}", """
    <h2>#{distribution} / #{component} / #{arch}</h2>
    <table>
      <thead><tr><th>Package</th><th>Version</th><th>Description</th></tr></thead>
      <tbody>#{rows}</tbody>
    </table>
    <p><a href="/ui/#{distribution}">&larr; Back</a></p>
    """)
  end

  get "/:distribution/:component/:arch/:name/:version" do
    packages = Repo.list_packages(distribution, component, arch)

    case Enum.find(packages, &(&1.name == name && &1.version == version)) do
      nil ->
        html(conn, "Not Found", "<p>Package not found.</p><p><a href=\"/ui\">&larr; Back</a></p>")

      pkg ->
        deps = pkg.depends || "None"
        desc = (pkg.description || "") |> String.replace("\n", "<br>")

        html(conn, "#{pkg.name} #{pkg.version}", """
        <h2>#{pkg.name} #{pkg.version}</h2>
        <table>
          <tr><td><strong>Architecture</strong></td><td>#{pkg.architecture}</td></tr>
          <tr><td><strong>Maintainer</strong></td><td>#{escape(pkg.maintainer || "N/A")}</td></tr>
          <tr><td><strong>Section</strong></td><td>#{pkg.section || "N/A"}</td></tr>
          <tr><td><strong>Priority</strong></td><td>#{pkg.priority || "N/A"}</td></tr>
          <tr><td><strong>Installed-Size</strong></td><td>#{pkg.installed_size || "N/A"}</td></tr>
          <tr><td><strong>Depends</strong></td><td>#{escape(deps)}</td></tr>
          <tr><td><strong>Size</strong></td><td>#{pkg.size} bytes</td></tr>
          <tr><td><strong>SHA256</strong></td><td><code>#{pkg.sha256}</code></td></tr>
          <tr><td><strong>Description</strong></td><td>#{desc}</td></tr>
        </table>
        <p><a href="/#{pkg.filename}">Download .deb</a></p>
        <p><a href="/ui/#{distribution}/#{component}/#{arch}">&larr; Back</a></p>
        """)
    end
  end

  match _ do
    send_resp(conn, 404, "Not found")
  end

  defp html(conn, title, body) do
    page = """
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>#{title} - RepomaticApt</title>
      <style>
        body { font-family: system-ui, sans-serif; max-width: 900px; margin: 2em auto; padding: 0 1em; color: #333; }
        h1 a { color: inherit; text-decoration: none; }
        table { border-collapse: collapse; width: 100%; margin: 1em 0; }
        th, td { border: 1px solid #ddd; padding: 0.5em 0.75em; text-align: left; }
        th { background: #f5f5f5; }
        tr:hover { background: #fafafa; }
        a { color: #0366d6; }
        pre { background: #f5f5f5; padding: 1em; overflow-x: auto; border-radius: 4px; }
        code { font-size: 0.9em; }
      </style>
    </head>
    <body>
      <h1><a href="/ui">RepomaticApt</a></h1>
      #{body}
    </body>
    </html>
    """

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, page)
  end

  defp escape(nil), do: ""

  defp escape(str) do
    str
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end
end
