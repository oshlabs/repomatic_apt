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
| `REPOMATIC_PORT` | `4080` | HTTP port |
| `REPOMATIC_IP` | `0.0.0.0` | Bind address |
| `REPOMATIC_API_TOKEN` | *(none — no auth)* | Bearer token for API auth |
| `REPOMATIC_MAX_UPLOAD_SIZE` | `104857600` (100 MB) | Max upload bytes |
| `REPOMATIC_DISTRIBUTIONS` | See config.exs | JSON array of distribution objects |
| `REPOMATIC_SIGNING_KEY_PATH` | *(none)* | Path to ETF key file |
| `REPOMATIC_SIGNING_KEY_UID` | `RepomaticApt <repomatic_apt@localhost>` | UID for auto-generated key |

## Signing Key Management

### Auto-generated key (default)

On first start, if no signing key is configured, the server generates a 4096-bit RSA key and saves it to `<repo_root>/signing_key.etf`. As long as your data volume persists, the key persists.

### Export key via API

```bash
# Public key (armored PGP)
curl -H "Authorization: Bearer $TOKEN" http://localhost:4080/api/key/public -o repo.asc

# Private key (ETF format — for backup or migrating to another instance)
curl -H "Authorization: Bearer $TOKEN" http://localhost:4080/api/key/private -o signing_key.etf
```

### Import key on new instance

Set `REPOMATIC_SIGNING_KEY_PATH` to the ETF file path (must be accessible inside the container):

```bash
docker run -d \
  -v /path/to/signing_key.etf:/keys/signing_key.etf:ro \
  -e REPOMATIC_SIGNING_KEY_PATH=/keys/signing_key.etf \
  -e REPOMATIC_API_TOKEN=secret \
  -p 4080:4080 \
  repomatic_apt
```

### Pre-generate key with Mix task

```bash
mix repomatic_apt.gen_key --output signing_key.etf --uid "My Repo <repo@example.com>" --bits 4096
```

This writes `signing_key.etf` and `signing_key.asc` (public key).

## Custom Distributions

```bash
docker run -d \
  -e REPOMATIC_API_TOKEN=secret \
  -e 'REPOMATIC_DISTRIBUTIONS=[{"suite":"jammy","codename":"jammy","architectures":["amd64","arm64"],"components":["main","contrib"],"origin":"MyRepo","label":"MyRepo"}]' \
  -p 4080:4080 \
  repomatic_apt
```

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

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: repomatic-secret
type: Opaque
stringData:
  api-token: "your-secret-token"
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
