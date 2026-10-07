# RepomaticApt

An Elixir APT repository server. Accepts `.deb` package uploads via a REST API, generates signed index files, and serves the repository over HTTP. Includes a web UI for browsing packages and setup instructions.

## Features

- **REST API** for uploading, listing, and deleting packages (single and bulk)
- **Bulk upload** — upload a `.tar.gz` or `.zip` of `.deb` files with atomic validation (all-or-nothing)
- **OpenPGP signing** with pure-Erlang RSA key generation and v4 packet encoding (no GPG binary required)
- **Debian-compliant indices** — generates `Packages`, `Packages.gz`, `Release`, `Release.gpg`, and `InRelease`
- **Acquire-By-Hash** support for atomic client-side updates
- **Web UI** for browsing distributions, packages, and setup instructions
- **TLS/SSL** — optional HTTPS with configurable certificate and key files
- **Embeddable** — runs standalone with Bandit or mounts as a Plug inside a Phoenix app
- **Pluggable storage backends** — local filesystem (default) or in-memory; implement the `Store.Backend` behaviour for custom backends
- **Zero external dependencies** for crypto — uses Erlang's `:crypto` and `:zlib` modules
- **No external dependencies** beyond Plug, Bandit, and Jason — everything else is built-in
- **Atomic index writes** — temp file + rename to prevent partial reads
- **Optional API authentication** via bearer token
- **Configurable upload size limits**
- **Metadata persistence** — on startup, rebuilds in-memory metadata from existing `Packages` index files so the UI and API resume without re-uploading
- **Rescan Pool** — admin action to re-read every `.deb` from the pool and rebuild all metadata and indices from scratch
- **Health check endpoint** at `/healthz`

## Quick Start

### 1. Clone and install dependencies

```sh
git clone https://github.com/oshlabs/repomatic_apt.git
cd repomatic_apt
mix deps.get
```

### 2. Generate a signing key

```sh
mix repomatic_apt.gen_key --uid "My Repository <repo@example.com>"
```

This writes `signing_key.etf` (private, keep safe) and `signing_key.asc` (public, for distribution).

For Kubernetes, generate a Secret YAML directly:

```sh
mix repomatic_apt.gen_key --k8s --uid "My Repository <repo@example.com>"
```

### 3. Configure

Edit `config/dev.exs` (or use environment-specific config files):

```elixir
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
      suite: "bookworm",
      codename: "bookworm",
      architectures: ["amd64", "arm64"],
      components: ["main"],
      origin: "My Repository",
      label: "My Repository"
    }
  ]
```

Or pass the signing key via environment variable (recommended for containers/Kubernetes):

```sh
# Pass the key inline (in-memory only, never written to disk)
REPOMATIC_SIGNING_KEY="$(cat signing_key.etf)" mix run --no-halt

# Or point to a file
REPOMATIC_SIGNING_KEY_PATH=signing_key.etf mix run --no-halt
```

If no key is provided, the server auto-generates one on startup and saves it to `<repo_root>/signing_key.etf`.

### 4. Run

```sh
mix run --no-halt
```

The server starts on port 4080 by default. Visit `http://localhost:4080/ui` for the web interface.

## Configuration Reference

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `repo_root` | `String` | `"/var/lib/repomatic_apt/repo"` | Directory where repository files are stored |
| `port` | `integer` | `4080` | HTTP/HTTPS server port |
| `ip` | `tuple` | `{0, 0, 0, 0}` | Bind address |
| `distributions` | `[map]` | `[%{suite: "stable", ...}]` | List of distribution configurations |
| `signing_key` | `%RepomaticApt.Gpg.Key{}` | `nil` | Signing key struct (nil disables signing) |
| `signing_key_uid` | `String` | `nil` | UID for auto-generated signing key |
| `api_token` | `String` | `nil` | Bearer token for API auth (nil disables auth) |
| `ro_token` | `String` | `nil` | Read-only token for repo access via HTTP Basic auth (nil means open) |
| `max_upload_size` | `integer` | `104_857_600` | Maximum upload size in bytes (100 MB) |
| `upload_tmp_dir` | `String` | system temp dir | Scratch directory for spooling uploads and extracting bulk archives; needs roughly 2x the largest upload free |
| `certfile` | `String` | `nil` | Path to PEM certificate file (enables TLS when both cert and key are set) |
| `keyfile` | `String` | `nil` | Path to PEM private key file (enables TLS when both cert and key are set) |
| `start_server` | `boolean` | `false` | Whether to start the built-in HTTP server |

### Distribution configuration

Each distribution map supports:

| Key | Example | Description |
|-----|---------|-------------|
| `suite` | `"bookworm"` | Debian release target, used in the APT sources line |
| `codename` | `"bookworm"` | Release codename (often same as suite) |
| `architectures` | `["amd64", "arm64"]` | Supported CPU architectures |
| `components` | `["main", "voice"]` | Logical groupings within the distribution (like Debian's `main`, `contrib`, `non-free`) |
| `origin` | `"MyOrg"` | Metadata in the Release file — who provides the repo |
| `label` | `"MyOrg"` | Metadata in the Release file — label shown to APT users |

A **suite** defines a separate repository tree (`dists/<suite>/`). **Components** are logical groupings within that tree — use them to separate packages by team, purpose, or policy. The `origin` and `label` fields are purely metadata written to the `Release` file; they don't affect repository structure.

#### Example: multiple teams, multiple releases

Two teams (systems and voice) each publishing packages for bookworm and trixie:

```elixir
distributions: [
  %{
    suite: "bookworm",
    codename: "bookworm",
    architectures: ["amd64"],
    components: ["systems", "voice"],
    origin: "MyOrg",
    label: "MyOrg"
  },
  %{
    suite: "trixie",
    codename: "trixie",
    architectures: ["amd64"],
    components: ["systems", "voice"],
    origin: "MyOrg",
    label: "MyOrg"
  }
]
```

Each team uploads to their own component:

```sh
# Systems team
curl -X PUT --data-binary @pkg.deb http://repo:4080/api/bookworm/systems

# Voice team
curl -X PUT --data-binary @pkg.deb http://repo:4080/api/bookworm/voice
```

Clients subscribe to the components they need:

```sh
# Just voice packages
deb http://repo:4080 bookworm voice

# Just systems packages
deb http://repo:4080 bookworm systems

# Both
deb http://repo:4080 bookworm systems voice
```

## Authentication

RepomaticApt supports two independent authentication mechanisms:

### API authentication (`api_token`)

- **`api_token` set** — all `/api/*` endpoints require an `Authorization: Bearer <token>` header. Requests without a valid token receive a `401 Unauthorized` response.
- **`api_token` nil (default)** — all `/api/*` endpoints are open, no authentication required.

### Read-only authentication (`ro_token`)

- **`ro_token` set** — read paths (`/dists/*`, `/pool/*`, `/key.gpg`) and the web UI (`/ui/*`) require HTTP Basic auth where the password matches `ro_token` (username is ignored). APT natively supports this via `/etc/apt/auth.conf`.
- **`ro_token` nil (default)** — all read paths are publicly accessible, any APT client can fetch packages without credentials.

The `/healthz` endpoint is always open regardless of either token setting. The two tokens are independent — `api_token` controls API write access, `ro_token` controls repository read access.

#### Configuring APT clients for `ro_token`

When `ro_token` is set, APT clients need credentials in `/etc/apt/auth.conf.d/`:

```sh
# Create auth config
echo "machine http://your-server:4080 login apt password your-ro-token" \
  | sudo tee /etc/apt/auth.conf.d/repomatic.conf
sudo chmod 600 /etc/apt/auth.conf.d/repomatic.conf

# Import signing key (with auth)
curl -fsSL -u apt:your-ro-token http://your-server:4080/key.gpg \
  | sudo gpg --dearmor -o /usr/share/keyrings/repomatic_apt.gpg
```

The `machine` entry must include the protocol (`http://` or `https://`) — modern APT (Debian trixie / Ubuntu 25.04+) silently withholds credentials over plain HTTP otherwise. The sources.list line remains the same — APT picks up credentials from auth.conf automatically.

## REST API

### Upload a package

```sh
curl -X PUT \
  --data-binary @mypackage_1.0-1_amd64.deb \
  http://localhost:4080/api/bookworm/main
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
  http://localhost:4080/api/bookworm/main
```

### Bulk upload packages

Upload multiple `.deb` files at once by wrapping them in a `.tar.gz` or `.zip` archive. All packages are validated before any are added — if any `.deb` is invalid, the entire upload is rejected and the repository is unchanged.

```sh
# Create an archive of .deb files
tar czf packages.tar.gz *.deb

# Upload the archive
curl -X PUT \
  --data-binary @packages.tar.gz \
  http://localhost:4080/api/bookworm/main/bulk
```

Works with `.zip` archives too:

```sh
zip packages.zip *.deb
curl -X PUT \
  --data-binary @packages.zip \
  http://localhost:4080/api/bookworm/main/bulk
```

Response (201):

```json
{
  "count": 3,
  "packages": [
    {
      "package": "mypackage",
      "version": "1.0-1",
      "architecture": "amd64",
      "filename": "pool/main/m/mypackage/mypackage_1.0-1_amd64.deb",
      "sha256": "abcdef1234567890..."
    }
  ]
}
```

If any package fails validation, the response is 400 with details about which files failed:

```json
{
  "error": "Some packages failed validation",
  "failures": [
    {"file": "broken.deb", "reason": "invalid_magic"}
  ]
}
```

The archive is subject to the same `max_upload_size` limit as single uploads. Non-`.deb` files in the archive are ignored. The repository index is rebuilt only once after all packages are added.

Bulk uploads are streamed to disk (see `upload_tmp_dir`) and unpacked one entry at a time, so server memory use is bounded by the largest single `.deb`, not by the size of the archive. The format is detected from the content, so `.tgz` and `.tar.gz` are equivalent.

Packages are only published once every file in the archive has been written to the pool and the indices have been regenerated, so an upload interrupted by a crash leaves the published repository unchanged. On startup the server removes any scratch directories and `*.tmp.*` files such a crash left behind; for that reason `upload_tmp_dir` must not be shared between running instances.

### List packages

```sh
# All packages in a component
curl http://localhost:4080/api/bookworm/main

# Filter by architecture
curl http://localhost:4080/api/bookworm/main?arch=amd64
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
  http://localhost:4080/api/bookworm/main/mypackage/1.0-1/amd64
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

# 2. Add the repository (use your actual suite and components)
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
# config/config.exs (or environment-specific config)
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

This mounts RepomaticApt at `/repo`, so the API becomes `/repo/api/...`, the web UI is at `/repo/ui`, and repository files are served from `/repo/dists/...` and `/repo/pool/...`.

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
  archive.ex            # Archive extraction (.tar.gz, .zip) for bulk uploads
  tar.ex                # Low-level POSIX/ustar tar archive builder
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
  store/
    backend.ex          # Pluggable storage backend behaviour
    backend/
      local.ex          # Filesystem backend (atomic writes via temp+rename)
      memory.ex         # In-memory backend (for testing/embedding)
  web/
    router.ex           # Main Plug router
    api.ex              # REST API (upload, bulk upload, delete, list)
    serve.ex            # Static file serving with path traversal protection
    ui.ex               # HTML web interface
```

### Key design decisions

- **Metadata recovery**: The `MetadataStore` is in-memory, but metadata survives restarts. On startup the `Repo` GenServer parses existing `Packages` index files from `dists/` to repopulate the store. The "Rescan Pool" admin action goes further — it re-reads every `.deb` from the pool, re-extracts metadata, and regenerates all indices.
- **Serialized writes**: The `Repo` GenServer serializes all add/remove operations to prevent concurrent index corruption.
- **Pure-Elixir OpenPGP**: Signing uses Erlang's `:crypto` module directly. No GPG binary needed at runtime.
- **Atomic writes**: Index files are written to a temp file then renamed, so clients never see partial content.
- **Pluggable storage**: The `Store.Backend` behaviour allows swapping storage implementations. The local backend uses atomic temp-file + rename writes; the memory backend is useful for tests and ephemeral use.

## Metadata Persistence

The `MetadataStore` is an in-memory Agent — it does not write to a database. However, metadata is recovered automatically after a restart via two mechanisms:

### Startup recovery (automatic)

When the `Repo` GenServer starts, after resolving the signing key it scans the `dists/` tree for existing `Packages` index files. For each configured distribution, component, and architecture it reads `dists/{suite}/{component}/binary-{arch}/Packages`, parses the stanzas back into `%Package{}` structs, and populates the `MetadataStore`. This is fast because it reads only the index files (small text), not the `.deb` files themselves. Missing files (new or empty repo) are silently skipped.

After startup recovery the UI, API, and package listings work exactly as they did before the restart. No re-upload is needed.

### Rescan Pool (manual, admin-only)

The "Rescan Pool" link in the web UI (visible only to admin users) triggers a full rebuild from the `.deb` files in the pool:

1. Clears the entire `MetadataStore`
2. For each configured distribution and component, recursively walks `pool/{component}/` to find all `.deb` files
3. Reads each `.deb` binary and re-extracts metadata with `Package.extract/1` (the same path used during upload)
4. Stores each package in the `MetadataStore`
5. Regenerates all index files (`Packages`, `Packages.gz`, `Release`, `Release.gpg`, `InRelease`) for every distribution

This is slower than startup recovery because it reads and parses every `.deb`, but it is the authoritative rebuild — useful if index files are corrupted, if `.deb` files were added to the pool outside of the API, or if you want to force a complete re-index.

The rescan is also available programmatically via `RepomaticApt.Repo.rescan_pool/0`, which returns `{:ok, count}`.

## Web UI

The web UI is available at `/ui` and provides:

- **Distribution overview** — list of all configured distributions
- **Package browser** — navigate by distribution, component, and architecture
- **Package detail** — version, description, dependencies, SHA256, download link
- **Upload packages** — upload `.deb` or archive files (admin only)
- **Rescan Pool** — rebuild metadata from pool `.deb` files (admin only)
- **Setup instructions** — copy-paste commands for configuring APT clients

## Testing

```sh
mix test                        # run all unit tests
mix test test/version_test.exs  # single file
mix test test/repo_test.exs:37  # single test by line number
mix test --failed               # rerun failures
```

### Test suite overview

The unit tests cover every layer of the stack without external dependencies:

- **deb/** — ar archive parsing, RFC 822 control file parsing, `.deb` metadata extraction
- **gpg/** — ASCII armor encoding, CRC-24 checksums, MPI/packet framing, RSA key generation, detached and clearsign signatures
- **index/** — Packages index generation, Release file generation, gzip compression
- **web/** — REST API (upload, list, delete), Plug router, static file serving, HTML UI
- **repo** — end-to-end add/remove/list through the GenServer, concurrent uploads, signed index generation
- **store** — file storage, pool layout, atomic writes, Acquire-By-Hash
- **version** — Debian version string parsing and comparison

A test signing key (2048-bit RSA, for speed) is generated once in `test_helper.exs` and shared across all tests.

### Docker integration test

An end-to-end integration test verifies that a real Debian system can consume the repository. It starts an in-memory APT repo, uploads an installable `.deb`, then runs a Debian 13 (trixie) Docker container that installs the package via `apt-get` and checks the installed files.

Docker tests are excluded by default and require Docker on the host (Linux with `--network host`):

```sh
mix test --include docker test/integration/docker_test.exs
```

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

# Generate a signing key (writes signing_key.etf + signing_key.asc)
mix repomatic_apt.gen_key --uid "My Repo <repo@example.com>"

# Generate a signing key as Kubernetes Secret YAML
mix repomatic_apt.gen_key --k8s --uid "My Repo <repo@example.com>"
```

## License

MIT

## Credits

Claude LLM and with that the Open Source ecosystem it's trained on
