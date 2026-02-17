defmodule RepomaticApt.Web.Ui do
  use Plug.Router

  alias RepomaticApt.{Archive, Config, Repo}

  plug(:parse_multipart)
  plug(:match)
  plug(:authorize_write)
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

    upload_link =
      if conn.assigns[:ui_write],
        do: ~s(<a href="/ui/upload">Upload Packages</a> | ),
        else: ""

    {rescan_link, rescan_script} =
      if conn.assigns[:ui_write],
        do: {~s[<a href="/ui" onclick="return rescan()">Rescan Pool</a> | ], rescan_script()},
        else: {"", ""}

    {logout_link, logout_script} =
      if authenticated?(conn),
        do: {~s[ | <a href="/ui" onclick="return logout()">Logout</a>], logout_script()},
        else: {"", ""}

    html(conn, "Distributions", Enum.join([
      "<h2>Distributions</h2>",
      "<table>",
      "<thead><tr><th>Suite</th><th>Codename</th><th>Components</th><th>Architectures</th><th>Origin</th></tr></thead>",
      "<tbody>", rows, "</tbody>",
      "</table>",
      "<p>", upload_link, rescan_link, ~s(<a href="/ui/setup">Setup Instructions</a>), logout_link, "</p>",
      rescan_script,
      logout_script
    ]))
  end

  get "/setup" do
    base_url = external_base_url(conn)
    ro_token = Config.ro_token()

    auth_step =
      if ro_token do
        escaped_token = escape(ro_token)
        curl_auth = "apt" <> ":" <> escaped_token

        """
        <h3>1. Configure APT authentication</h3>
        <pre><code>echo "machine #{base_url} login apt password #{escaped_token}" | sudo tee /etc/apt/auth.conf.d/repomatic.conf
        sudo chmod 600 /etc/apt/auth.conf.d/repomatic.conf</code></pre>
        <h3>2. Import the signing key</h3>
        <pre><code>curl -fsSL -u #{curl_auth} #{base_url}/key.gpg | sudo gpg --dearmor -o /usr/share/keyrings/repomatic_apt.gpg</code></pre>
        """
      else
        """
        <h3>1. Import the signing key</h3>
        <pre><code>curl -fsSL #{base_url}/key.gpg | sudo gpg --dearmor -o /usr/share/keyrings/repomatic_apt.gpg</code></pre>
        """
      end

    next_step = if ro_token, do: "3", else: "2"
    update_step = if ro_token, do: "4", else: "3"

    distributions = Config.distributions()

    sources_lines =
      Enum.map_join(distributions, "\n", fn dist ->
        suite = dist[:suite] || "stable"
        components = Enum.join(dist[:components] || ["main"], " ")
        ~s(deb [signed-by=/usr/share/keyrings/repomatic_apt.gpg] #{base_url} #{suite} #{components})
      end)

    html(conn, "Setup Instructions", """
    <h2>Setup Instructions</h2>
    #{auth_step}
    <h3>#{next_step}. Add the repository</h3>
    <p>Add the lines that match your target distribution. Remove any you don't need.</p>
    <pre><code>echo "#{escape(sources_lines)}" | sudo tee /etc/apt/sources.list.d/repomatic_apt.list</code></pre>
    <h3>#{update_step}. Update package lists</h3>
    <pre><code>sudo apt update</code></pre>
    <p><a href="/ui">&larr; Back</a></p>
    """)
  end

  get "/upload" do
    distributions = Config.distributions()

    dist_options =
      Enum.map_join(distributions, "\n", fn dist ->
        suite = dist[:suite] || "unknown"
        "<option value=\"#{escape(suite)}\">#{escape(suite)}</option>"
      end)

    first_dist = List.first(distributions) || %{}
    components = first_dist[:components] || ["main"]

    comp_options =
      Enum.map_join(components, "\n", fn comp ->
        "<option value=\"#{escape(comp)}\">#{escape(comp)}</option>"
      end)

    html(conn, "Upload Packages", """
    <h2>Upload Packages</h2>
    <p>Upload a <code>.deb</code> file, or a <code>.tar.gz</code> / <code>.zip</code> archive containing multiple <code>.deb</code> files.</p>
    <form method="post" enctype="multipart/form-data">
      <p>
        <label>Distribution<br>
          <select name="distribution">#{dist_options}</select>
        </label>
      </p>
      <p>
        <label>Component<br>
          <select name="component">#{comp_options}</select>
        </label>
      </p>
      <p>
        <label>Package file<br>
          <input type="file" name="archive" accept=".deb,.tar.gz,.tgz,.zip">
        </label>
      </p>
      <p><button type="submit">Upload</button></p>
    </form>
    <p><a href="/ui">&larr; Back</a></p>
    """)
  end

  post "/upload" do
    upload = conn.params["archive"]
    distribution = conn.params["distribution"]
    component = conn.params["component"]

    cond do
      is_nil(upload) or not is_map(upload) ->
        html_error(conn, "No file uploaded.")

      is_nil(distribution) or distribution == "" ->
        html_error(conn, "No distribution selected.")

      is_nil(component) or component == "" ->
        html_error(conn, "No component selected.")

      true ->
        body = File.read!(upload.path)

        if deb_file?(upload.filename, body) do
          upload_single_deb(conn, body, distribution, component)
        else
          upload_archive(conn, body, distribution, component)
        end
    end
  end

  get "/rescan" do
    {:ok, count} = Repo.rescan_pool()

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(%{rescanned: count}))
  end

  get "/logout" do
    conn
    |> put_resp_header("www-authenticate", ~s(Basic realm="RepomaticApt"))
    |> send_resp(401, "")
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
        body { font-family: system-ui, sans-serif; max-width: 1800px; margin: 2em auto; padding: 0 1em; color: #333; }
        h1 a { color: inherit; text-decoration: none; }
        table { border-collapse: collapse; width: 100%; margin: 1em 0; table-layout: auto; }
        th, td { border: 1px solid #ddd; padding: 0.5em 0.75em; text-align: left; }
        td:nth-child(2) { white-space: nowrap; }
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

  defp parse_multipart(conn, _opts) do
    opts =
      Plug.Parsers.init(
        parsers: [:multipart],
        pass: ["*/*"],
        length: Config.max_upload_size()
      )

    Plug.Parsers.call(conn, opts)
  end

  defp authorize_write(%{method: "GET", path_info: ["rescan"]} = conn, _opts) do
    if conn.assigns[:ui_write] do
      conn
    else
      conn
      |> put_resp_content_type("text/html")
      |> send_resp(403, forbidden_page())
      |> halt()
    end
  end

  defp authorize_write(%{method: method, path_info: ["upload"]} = conn, _opts)
       when method in ["GET", "POST"] do
    if conn.assigns[:ui_write] do
      conn
    else
      conn
      |> put_resp_content_type("text/html")
      |> send_resp(403, forbidden_page())
      |> halt()
    end
  end

  defp authorize_write(conn, _opts), do: conn

  defp forbidden_page do
    """
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>Forbidden - RepomaticApt</title>
      <style>
        body { font-family: system-ui, sans-serif; max-width: 1400px; margin: 2em auto; padding: 0 1em; color: #333; }
        h1 a { color: inherit; text-decoration: none; }
        a { color: #0366d6; }
      </style>
    </head>
    <body>
      <h1><a href="/ui">RepomaticApt</a></h1>
      <h2>Forbidden</h2>
      <p>You have read-only access. Upload is not available.</p>
      <p><a href="/ui">&larr; Back</a></p>
    </body>
    </html>
    """
  end

  # ar archives (`.deb` files) start with "!<arch>\n"
  defp deb_file?(_filename, <<"!<arch>\n", _::binary>>), do: true
  defp deb_file?(filename, _body), do: String.ends_with?(filename || "", ".deb")

  defp upload_single_deb(conn, body, distribution, component) do
    case Repo.add_package(distribution, component, body) do
      {:ok, pkg} ->
        html(conn, "Upload Successful", """
        <h2>Upload Successful</h2>
        <p>Added package to #{escape(distribution)}/#{escape(component)}.</p>
        <table>
          <thead><tr><th>Package</th><th>Version</th><th>Architecture</th></tr></thead>
          <tbody>
            <tr>
              <td>#{escape(pkg.name)}</td>
              <td>#{escape(pkg.version)}</td>
              <td>#{escape(pkg.architecture)}</td>
            </tr>
          </tbody>
        </table>
        <p><a href="/ui/upload">Upload more</a> | <a href="/ui">&larr; Back</a></p>
        """)

      {:error, reason} ->
        html_error(conn, "Failed to add package: #{escape(to_string(reason))}")
    end
  end

  defp upload_archive(conn, body, distribution, component) do
    case Archive.extract_debs(body) do
      {:error, :unsupported_archive_format} ->
        html_error(conn, "Unsupported file format. Supported: .deb, .tar.gz, .zip")

      {:error, {:extract_failed, reason}} ->
        html_error(conn, "Failed to extract archive: #{inspect(reason)}")

      {:ok, []} ->
        html_error(conn, "Archive contains no .deb files.")

      {:ok, deb_entries} ->
        case Repo.add_packages_bulk(distribution, component, deb_entries) do
          {:ok, packages} ->
            rows =
              Enum.map_join(packages, "\n", fn pkg ->
                """
                <tr>
                  <td>#{escape(pkg.name)}</td>
                  <td>#{escape(pkg.version)}</td>
                  <td>#{escape(pkg.architecture)}</td>
                </tr>
                """
              end)

            html(conn, "Upload Successful", """
            <h2>Upload Successful</h2>
            <p>Added #{length(packages)} package(s) to #{escape(distribution)}/#{escape(component)}.</p>
            <table>
              <thead><tr><th>Package</th><th>Version</th><th>Architecture</th></tr></thead>
              <tbody>#{rows}</tbody>
            </table>
            <p><a href="/ui/upload">Upload more</a> | <a href="/ui">&larr; Back</a></p>
            """)

          {:error, failures} ->
            rows =
              Enum.map_join(failures, "\n", fn {file, reason} ->
                """
                <tr>
                  <td>#{escape(file)}</td>
                  <td>#{escape(to_string(reason))}</td>
                </tr>
                """
              end)

            html_error(conn, """
            <p>Some packages failed validation:</p>
            <table>
              <thead><tr><th>File</th><th>Reason</th></tr></thead>
              <tbody>#{rows}</tbody>
            </table>
            """)
        end
    end
  end

  defp html_error(conn, message) do
    html(conn, "Upload Error", """
    <h2>Upload Error</h2>
    #{message}
    <p><a href="/ui/upload">&larr; Try again</a></p>
    """)
  end

  defp authenticated?(conn) do
    Plug.BasicAuth.parse_basic_auth(conn) != :error
  end

  defp rescan_script do
    ~s[<script>function rescan(){if(!confirm("Re-read every package from the pool?"))return false;var x=new XMLHttpRequest();x.open("GET","/ui/rescan",true);x.onloadend=function(){window.location.href="/ui"};x.send();return false}</script>]
  end

  defp logout_script do
    ~s[<script>function logout(){var x=new XMLHttpRequest();x.open("GET","/ui/logout",true,"_","_");x.onloadend=function(){window.location.href="/ui"};x.send();return false}</script>]
  end

  defp external_base_url(conn) do
    scheme = forwarded_header(conn, "x-forwarded-proto") || request_scheme(conn)

    host = forwarded_header(conn, "x-forwarded-host") || conn.host || "localhost"

    port =
      case forwarded_header(conn, "x-forwarded-port") do
        nil -> Config.port()
        val -> String.to_integer(val)
      end

    default_port = if scheme == "https", do: 443, else: 80

    if port == default_port do
      "#{scheme}://#{host}"
    else
      "#{scheme}://#{host}:#{port}"
    end
  end

  defp forwarded_header(conn, header) do
    case Plug.Conn.get_req_header(conn, header) do
      [val | _] -> val
      [] -> nil
    end
  end

  defp request_scheme(_conn) do
    if Application.get_env(:repomatic_apt, :certfile), do: "https", else: "http"
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
