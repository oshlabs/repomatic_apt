# Docker / Kubernetes Deployment

## Quick Start

```bash
docker build -t repomatic_apt .
docker run -d \
  -p 4080:4080 \
  -v repomatic_data:/var/lib/repomatic_apt/repo \
  -e REPOMATIC_API_TOKEN=secret \
  repomatic_apt
```

The server will auto-generate a signing key on first start and persist it in the data volume.

## Environment Variables

| Variable | Default | Description |
|---|---|---|
| `REPOMATIC_REPO_ROOT` | `/var/lib/repomatic_apt/repo` | Data directory |
| `REPOMATIC_LISTEN_PORT` | `4080` | HTTP port |
| `REPOMATIC_LISTEN_IP` | `0.0.0.0` | Bind address |
| `REPOMATIC_API_TOKEN` | *(none — no auth)* | Bearer token for API auth |
| `REPOMATIC_RO_TOKEN` | *(none — open read)* | Read-only token for repo access (HTTP Basic auth) |
| `REPOMATIC_MAX_UPLOAD_SIZE` | `104857600` (100 MB) | Max upload bytes |
| `REPOMATIC_DISTRIBUTIONS` | See dev.exs | JSON array of distribution objects |
| `REPOMATIC_SIGNING_KEY` | *(none)* | Signing key as base64-encoded ETF string (in-memory only, no disk write) |
| `REPOMATIC_SIGNING_KEY_PATH` | *(none)* | Path to ETF key file |
| `REPOMATIC_SIGNING_KEY_UID` | `RepomaticApt <repomatic_apt@localhost>` | UID for auto-generated key |
| `REPOMATIC_TLS_CERTFILE` | *(none)* | Path to PEM certificate file |
| `REPOMATIC_TLS_KEYFILE` | *(none)* | Path to PEM private key file |

## TLS/SSL

To enable HTTPS, set both `REPOMATIC_TLS_CERTFILE` and `REPOMATIC_TLS_KEYFILE`. When both are set, the server starts with `scheme: :https`. When neither is set, plain HTTP is used (default).

```bash
docker run -d \
  -p 4443:4443 \
  -v /path/to/certs:/certs:ro \
  -v repomatic_data:/var/lib/repomatic_apt/repo \
  -e REPOMATIC_LISTEN_PORT=4443 \
  -e REPOMATIC_TLS_CERTFILE=/certs/cert.pem \
  -e REPOMATIC_TLS_KEYFILE=/certs/key.pem \
  -e REPOMATIC_API_TOKEN=secret \
  repomatic_apt
```

### Docker Compose with TLS

```yaml
services:
  repomatic:
    build: .
    ports:
      - "4443:4443"
    volumes:
      - repomatic_data:/var/lib/repomatic_apt/repo
      - ./certs:/certs:ro
    environment:
      REPOMATIC_LISTEN_PORT: "4443"
      REPOMATIC_TLS_CERTFILE: /certs/cert.pem
      REPOMATIC_TLS_KEYFILE: /certs/key.pem
      REPOMATIC_API_TOKEN: "${REPOMATIC_API_TOKEN}"
    restart: unless-stopped

volumes:
  repomatic_data:
```

### Kubernetes

In Kubernetes, TLS is typically terminated at the Ingress controller. However, if you need end-to-end encryption, mount the certificate and key via a Secret and set the environment variables:

```yaml
volumes:
  - name: tls-certs
    secret:
      secretName: repomatic-tls
containers:
  - name: repomatic
    volumeMounts:
      - name: tls-certs
        mountPath: /certs
        readOnly: true
    env:
      - name: REPOMATIC_LISTEN_PORT
        value: "4443"
      - name: REPOMATIC_TLS_CERTFILE
        value: /certs/tls.crt
      - name: REPOMATIC_TLS_KEYFILE
        value: /certs/tls.key
```

## Signing Key Management

The signing key is used to sign `Release.gpg` and `InRelease` files and is served to clients via `/key.gpg`. There are three ways to provide a signing key, checked in this order:

| Method | Env var | Disk write | Best for |
|--------|---------|------------|----------|
| Inline via env var | `REPOMATIC_SIGNING_KEY` | No (in-memory only) | Kubernetes, containers |
| File path | `REPOMATIC_SIGNING_KEY_PATH` | No | Docker with mounted secrets |
| Auto-generated | *(none)* | Yes (`<repo_root>/signing_key.etf`) | Local dev, simple Docker setups |

If `REPOMATIC_SIGNING_KEY` is set, `REPOMATIC_SIGNING_KEY_PATH` is ignored.

### Passing the key via environment variable (recommended for Kubernetes)

The key stays in memory only — nothing is written to disk. Generate the key and pass it as an env var:

```bash
# Generate the key
mix repomatic_apt.gen_key --uid "My Repo <repo@example.com>"

# Pass it inline
docker run -d \
  -e "REPOMATIC_SIGNING_KEY=$(cat signing_key.etf)" \
  -e REPOMATIC_API_TOKEN=secret \
  -p 4080:4080 \
  repomatic_apt
```

### Passing the key via file path

Mount the ETF file into the container and point to it:

```bash
docker run -d \
  -v /path/to/signing_key.etf:/keys/signing_key.etf:ro \
  -e REPOMATIC_SIGNING_KEY_PATH=/keys/signing_key.etf \
  -e REPOMATIC_API_TOKEN=secret \
  -p 4080:4080 \
  repomatic_apt
```

### Auto-generated key (default)

On first start, if no signing key is configured, the server generates a 4096-bit RSA key and saves it to `<repo_root>/signing_key.etf`. As long as your data volume persists, the key persists.

### Pre-generate key with Mix task

```bash
# Write signing_key.etf + signing_key.asc files
mix repomatic_apt.gen_key --uid "My Repo <repo@example.com>"

# Output a Kubernetes Secret YAML (pipe to kubectl apply -f -)
mix repomatic_apt.gen_key --k8s --uid "My Repo <repo@example.com>"
```

### Export key via API

```bash
# Public key (armored PGP)
curl -H "Authorization: Bearer $TOKEN" http://localhost:4080/api/key/public -o repo.asc

# Private key (ETF format — for backup or migrating to another instance)
curl -H "Authorization: Bearer $TOKEN" http://localhost:4080/api/key/private -o signing_key.etf
```

## Custom Distributions

Distributions are configured via the `REPOMATIC_DISTRIBUTIONS` environment variable as a JSON array. Each object supports these keys:

| Key | Example | Description |
|-----|---------|-------------|
| `suite` | `"bookworm"` | Debian release target (used in the APT sources line) |
| `codename` | `"bookworm"` | Release codename (often same as suite) |
| `architectures` | `["amd64", "arm64"]` | Supported CPU architectures |
| `components` | `["main", "contrib"]` | Repo sections (main, contrib, non-free, ...) |
| `origin` | `"MyOrg"` | Metadata: project or team providing the repo |
| `label` | `"MyOrg"` | Metadata: label shown to APT users |

### Docker

```bash
docker run -d \
  -e REPOMATIC_API_TOKEN=secret \
  -e 'REPOMATIC_DISTRIBUTIONS=[{"suite":"jammy","codename":"jammy","architectures":["amd64","arm64"],"components":["main","contrib"],"origin":"MyRepo","label":"MyRepo"}]' \
  -p 4080:4080 \
  repomatic_apt
```

### Kubernetes

In a Kubernetes Deployment, set the env var on the container. For readability, use a YAML literal block:

```yaml
env:
  - name: REPOMATIC_DISTRIBUTIONS
    value: |
      [
        {
          "suite": "bookworm",
          "codename": "bookworm",
          "architectures": ["amd64"],
          "components": ["main"],
          "origin": "MyOrg",
          "label": "MyOrg"
        }
      ]
```

Multiple distributions (e.g. two teams publishing to bookworm and trixie):

```yaml
env:
  - name: REPOMATIC_DISTRIBUTIONS
    value: |
      [
        {
          "suite": "bookworm",
          "codename": "bookworm",
          "architectures": ["amd64"],
          "components": ["systems", "voice"],
          "origin": "MyOrg",
          "label": "MyOrg"
        },
        {
          "suite": "trixie",
          "codename": "trixie",
          "architectures": ["amd64"],
          "components": ["systems", "voice"],
          "origin": "MyOrg",
          "label": "MyOrg"
        }
      ]
```

Each team then uploads to their own component (`/api/bookworm/systems`, `/api/bookworm/voice`), and clients subscribe to the components they need in their sources.list.

## Docker Compose

```yaml
services:
  repomatic:
    build: .
    ports:
      - "4080:4080"
    volumes:
      - repomatic_data:/var/lib/repomatic_apt/repo
    environment:
      REPOMATIC_API_TOKEN: "${REPOMATIC_API_TOKEN}"
    restart: unless-stopped

volumes:
  repomatic_data:
```

## Kubernetes

### PersistentVolumeClaim

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: repomatic-data
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 10Gi
```

### Secret

Generate a signing key Secret directly with the Mix task:

```bash
mix repomatic_apt.gen_key --k8s --uid "My Repo <repo@example.com>" | kubectl apply -f -
```

Then create a separate Secret for the API token, or combine both in a single manifest:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: repomatic-secret
type: Opaque
stringData:
  api-token: "your-secret-token"
  signing-key: "<contents of signing_key.etf>"
```

### Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: repomatic
spec:
  replicas: 1
  selector:
    matchLabels:
      app: repomatic
  template:
    metadata:
      labels:
        app: repomatic
    spec:
      containers:
        - name: repomatic
          image: repomatic_apt:latest
          ports:
            - containerPort: 4080
          env:
            - name: REPOMATIC_API_TOKEN
              valueFrom:
                secretKeyRef:
                  name: repomatic-secret
                  key: api-token
            - name: REPOMATIC_SIGNING_KEY
              valueFrom:
                secretKeyRef:
                  name: repomatic-secret
                  key: signing-key
          volumeMounts:
            - name: data
              mountPath: /var/lib/repomatic_apt/repo
          livenessProbe:
            httpGet:
              path: /healthz
              port: 4080
            initialDelaySeconds: 10
            periodSeconds: 30
          readinessProbe:
            httpGet:
              path: /healthz
              port: 4080
            initialDelaySeconds: 5
            periodSeconds: 10
          resources:
            requests:
              memory: "128Mi"
              cpu: "100m"
            limits:
              memory: "512Mi"
              cpu: "500m"
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: repomatic-data
```

### Service

```yaml
apiVersion: v1
kind: Service
metadata:
  name: repomatic
spec:
  selector:
    app: repomatic
  ports:
    - port: 80
      targetPort: 4080
  type: ClusterIP
```
