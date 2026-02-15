# RepomaticApt

An Elixir APT repository server. Accepts `.deb` package uploads via a REST API, generates signed index files, and serves the repository over HTTP. Includes a web UI for browsing packages and setup instructions.

## Features

- **REST API** for uploading, listing, and deleting packages
- **OpenPGP signing** with pure-Erlang RSA key generation and v4 packet encoding (no GPG binary required)
- **Debian-compliant indices** — generates `Packages`, `Packages.gz`, `Release`, `Release.gpg`, and `InRelease`
- **Acquire-By-Hash** support for atomic client-side updates
- **Web UI** for browsing distributions, packages, and setup instructions
- **Embeddable** — runs standalone with Bandit or mounts as a Plug inside a Phoenix app
- **Zero external dependencies** for crypto — uses Erlang's `:crypto` and `:zlib` modules
- **Atomic index writes** — temp file + rename to prevent partial reads
- **Optional API authentication** via bearer token
- **Configurable upload size limits**
- **Health check endpoint** at `/healthz`

## Quick Start

### 1. Clone and install dependencies

```sh
git clone https://github.com/oshlabs/repomatic_apt.git
cd repomatic_apt
mix deps.get
```

### 2. Generate a signing key

Open an IEx session and generate a key:

```sh
iex -S mix
```

```elixir
key = RepomaticApt.Gpg.Key.generate(
  bits: 4096,
  uid: "My Repository <repo@example.com>"
)

# Export the private key to a file (keep this safe!)
File.write!("signing_key.asc", RepomaticApt.Gpg.Key.export_secret(key))

# Export the public key for distribution
File.write!("public_key.asc", RepomaticApt.Gpg.Key.export_public(key))
```

### 3. Configure

Edit `config/config.exs` (or use environment-specific config files):

```elixir
import Config

config :repomatic_apt,
  repo_root: "/var/lib/repomatic_apt/repo",
  port: 4080,
  distributions: [
    %{
      suite: "bookworm",
      codename: "bookworm",
      architectures: ["amd64", "arm64"],
      components: ["main"],
      origin: "My Repository",
      label: "My Repository"
    }
  ]
```

To load the signing key at startup, add to `config/runtime.exs`:

```elixir
import Config

if File.exists?("signing_key.asc") do
  # For now, generate and persist the key; loading from file is a future feature
end
```

Or set the key programmatically before the app starts:

```elixir
key = RepomaticApt.Gpg.Key.generate(bits: 4096, uid: "Repo <repo@example.com>")
Application.put_env(:repomatic_apt, :signing_key, key)
```

### 4. Run

```sh
mix run --no-halt
```

The server starts on port 4080 by default. Visit `http://localhost:4080/ui` for the web interface.

## Configuration Reference

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `repo_root` | `String` | `"/var/lib/repomatic_apt/repo"` | Directory where repository files are stored |
| `port` | `integer` | `4080` | HTTP server port |
| `distributions` | `[map]` | `[%{suite: "stable", ...}]` | List of distribution configurations |
| `signing_key` | `%RepomaticApt.Gpg.Key{}` | `nil` | Signing key struct (nil disables signing) |
| `api_token` | `String` | `nil` | Bearer token for API auth (nil disables auth) |
| `max_upload_size` | `integer` | `104_857_600` | Maximum upload size in bytes (100 MB) |
| `start_server` | `boolean` | `true` | Whether to start the built-in HTTP server |

### Distribution configuration

Each distribution map supports:

| Key | Example | Description |
|-----|---------|-------------|
| `suite` | `"bookworm"` | Suite name used in APT sources |
| `codename` | `"bookworm"` | Distribution codename |
| `architectures` | `["amd64", "arm64"]` | Supported architectures |
| `components` | `["main", "contrib"]` | Repository components |
| `origin` | `"My Repository"` | Origin field in Release file |
| `label` | `"My Repository"` | Label field in Release file |

## REST API

### Upload a package

```sh
curl -X PUT \
  --data-binary @mypackage_1.0-1_amd64.deb \
  http://localhost:4080/api/packages/bookworm/main
```

Response (201):

```json
{
  "package": "mypackage",
  "version": "1.0-1",
  "architecture": "amd64",
  "filename": "pool/main/m/mypackage/mypackage_1.0-1_amd64.deb",
  "sha256": "abcdef1234567890..."
}
```

### Upload with authentication

When `api_token` is configured:

```sh
curl -X PUT \
  -H "Authorization: Bearer your-secret-token" \
  --data-binary @mypackage_1.0-1_amd64.deb \
  http://localhost:4080/api/packages/bookworm/main
```

### List packages

```sh
# All packages in a component
curl http://localhost:4080/api/packages/bookworm/main

# Filter by architecture
curl http://localhost:4080/api/packages/bookworm/main?arch=amd64
```

Response (200):

```json
{
  "packages": [
    {"name": "mypackage", "version": "1.0-1", "architecture": "amd64"}
  ]
}
```

### Delete a package

```sh
curl -X DELETE \
  http://localhost:4080/api/packages/bookworm/main/mypackage/1.0-1/amd64
```

Response (200):

```json
{"deleted": true}
```

### Health check

```sh
curl http://localhost:4080/healthz
```

Response (200):

```json
{"status": "ok"}
```

### Download the public key

```sh
curl -o key.gpg http://localhost:4080/key.gpg
```

## Client Setup

On a Debian/Ubuntu machine, configure APT to use the repository:

```sh
# 1. Import the signing key
curl -fsSL http://your-server:4080/key.gpg \
  | sudo gpg --dearmor -o /usr/share/keyrings/repomatic_apt.gpg

# 2. Add the repository
echo "deb [signed-by=/usr/share/keyrings/repomatic_apt.gpg] http://your-server:4080 bookworm main" \
  | sudo tee /etc/apt/sources.list.d/repomatic_apt.list

# 3. Update and install
sudo apt update
sudo apt install mypackage
```

You can also find these instructions in the web UI at `/ui/setup`.

## Embedding in a Phoenix Application

RepomaticApt can run inside an existing Phoenix app instead of as a standalone server.

### 1. Add the dependency

```elixir
# mix.exs
def deps do
  [
    {:repomatic_apt, path: "../repomatic_apt"}
    # or from Hex: {:repomatic_apt, "~> 0.1.0"}
  ]
end
```

### 2. Disable the built-in server

```elixir
# config/config.exs
config :repomatic_apt,
  start_server: false,
  repo_root: "/var/lib/myapp/repo",
  distributions: [
    %{
      suite: "bookworm",
      codename: "bookworm",
      architectures: ["amd64"],
      components: ["main"],
      origin: "My App",
      label: "My App"
    }
  ]
```

### 3. Mount the router in your Phoenix endpoint or router

```elixir
# lib/my_app_web/router.ex
defmodule MyAppWeb.Router do
  use MyAppWeb, :router

  # ... your existing routes ...

  forward "/repo", RepomaticApt.Web.Router
end
```

This mounts RepomaticApt at `/repo`, so the API becomes `/repo/api/packages/...`, the web UI is at `/repo/ui`, and repository files are served from `/repo/dists/...` and `/repo/pool/...`.

### 4. Set the signing key at startup

In your application's `start/2` callback or a startup task:

```elixir
key = RepomaticApt.Gpg.Key.generate(
  bits: 4096,
  uid: "My App Repository <repo@myapp.com>"
)
Application.put_env(:repomatic_apt, :signing_key, key)
```

Or load a persisted key from your database or filesystem.

## Repository Layout

RepomaticApt creates the standard Debian repository structure:

```
repo_root/
  dists/
    bookworm/
      Release
      Release.gpg
      InRelease
      main/
        binary-amd64/
          Packages
          Packages.gz
          by-hash/
            SHA256/
              <hash>
  pool/
    main/
      m/
        mypackage/
          mypackage_1.0-1_amd64.deb
      libn/
        libncurses/
          libncurses_6.3_amd64.deb
```

Pool paths follow Debian conventions: packages starting with `lib` use a `lib<first-char>` prefix (e.g., `libn/libncurses`), others use the first character (e.g., `m/mypackage`).

## Architecture

```
lib/repomatic_apt/
  application.ex        # OTP supervisor (MetadataStore, Repo, Bandit)
  config.ex             # Configuration accessors
  metadata_store.ex     # In-memory package metadata (Agent)
  repo.ex               # Serialized repo operations (GenServer)
  store.ex              # File storage, pool layout, atomic writes, by-hash
  version.ex            # Debian version parsing and comparison
  deb/
    ar.ex               # ar archive parser
    control.ex          # RFC 822 control file parser
    package.ex          # .deb metadata extraction
  index/
    packages.ex         # Packages index generation
    release.ex          # Release file generation
    compress.ex         # gzip compression
  gpg/
    key.ex              # RSA key generation, OpenPGP v4 packets
    sign.ex             # Detached and clearsign operations
    packet.ex           # MPI encoding, packet framing
    armor.ex            # ASCII armor encoding
    crc24.ex            # CRC-24 checksum
  web/
    router.ex           # Main Plug router
    api.ex              # REST API (upload, delete, list)
    serve.ex            # Static file serving
    ui.ex               # HTML web interface
```

### Key design decisions

- **No .deb re-reading**: Package metadata is extracted once at upload and stored in the `MetadataStore`. Index rebuilds read from the store, never from `.deb` files on disk.
- **Serialized writes**: The `Repo` GenServer serializes all add/remove operations to prevent concurrent index corruption.
- **Pure-Elixir OpenPGP**: Signing uses Erlang's `:crypto` module directly. No GPG binary needed at runtime.
- **Atomic writes**: Index files are written to a temp file then renamed, so clients never see partial content.

## Web UI

The web UI is available at `/ui` and provides:

- **Distribution overview** — list of all configured distributions
- **Package browser** — navigate by distribution, component, and architecture
- **Package detail** — version, description, dependencies, SHA256, download link
- **Setup instructions** — copy-paste commands for configuring APT clients

## Development

```sh
# Run tests
mix test

# Run a specific test file
mix test test/version_test.exs

# Run static analysis with Dialyzer
mix dialyzer

# Check formatting
mix format --check-formatted

# Format code
mix format

# Start an interactive session
iex -S mix
```

## License

MIT

## Credits

Claude LLM and with that the Open Source ecosystem it's trained on
