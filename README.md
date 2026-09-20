# searchd

A sharded search service. It serves customer queries synchronously over HTTP and
takes a continuous stream of new documents from the crawl pipeline.

This repository is a trimmed-down version of the real thing: the chart, the
Terraform for its node pool, the deploy pipeline, and the dashboards we watch.

## What it does

Each replica holds one shard of the index in memory and on a local SSD. A query
fans out to all shards and merges results. Ingest writes new documents into the
live segment on the same replicas.

| Endpoint | Purpose |
| --- | --- |
| `GET /search?q=` | Customer query path |
| `POST /ingest` | Crawl pipeline writes |
| `GET /healthz` | Process health |
| `GET /metrics` | Index state, doc count, ingest buffer depth |

## What it's held to

- **p99 latency: 300 ms.** Customers call `/search` synchronously from their own
  request paths, so our tail latency lands inside theirs.
- **No maintenance windows.** There is no hour of the day when this can be down.
- **Index load takes about 14 minutes per replica.** A replica that starts cold
  has to pull its shard from object storage before it can answer properly.
- **Ingest runs continuously**, roughly 2–3 TB of new documents a day.

## Current shape

- 3 replicas in the chart (production runs 6 shards × 3 replicas)
- `n2-standard-16` nodes, local SSD, single node pool
- Deploys on merge to `main` via GitHub Actions
- Replication factor 3; a shard needs 2 of 3 replicas to answer correctly

## Running it locally

### Prerequisites

The local flow needs `docker`, `kind`, `kubectl`, `helm`, `make`, and `curl`.
Terraform is **not** required — the `terraform/` directory is here to read, and
its state backend points at a private GCS bucket, so don't run `apply` against it.

Give Docker at least 4 CPUs and 8 GB of memory; the kind cluster runs four
nodes (1 control plane + 3 workers) as containers.

#### macOS

Install [Homebrew](https://brew.sh) if you don't have it:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Then:

```bash
xcode-select --install                # make (skip if already installed)
brew install --cask docker            # Docker Desktop
brew install kind kubectl helm
open -a Docker                        # start Docker Desktop before continuing
```

(Colima or another Docker runtime works too, as long as `docker ps` succeeds.)

#### Linux (Debian/Ubuntu)

```bash
# make and curl
sudo apt-get update && sudo apt-get install -y make curl

# Docker Engine
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker "$USER"   # then log out/in, or run: newgrp docker

# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/$(dpkg --print-architecture)/kubectl"
sudo install -m 0755 kubectl /usr/local/bin/kubectl && rm kubectl

# kind
curl -Lo kind "https://github.com/kubernetes-sigs/kind/releases/latest/download/kind-linux-$(dpkg --print-architecture)"
sudo install -m 0755 kind /usr/local/bin/kind && rm kind

# helm
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

On Fedora/RHEL, swap the `apt-get` line for `sudo dnf install -y make curl` and
use `uname -m` in place of `dpkg --print-architecture` (`x86_64` → download the
`amd64` binaries, `aarch64` → `arm64`).

#### Verify

```bash
docker ps          # daemon reachable, no permission errors
kind version
kubectl version --client
helm version
```

### Bring it up

```bash
make kind-up        # creates the kind cluster (1 control plane + 3 workers)
make deploy-local   # builds the image, loads it, installs the chart
make smoke          # fires some queries and an ingest batch
```

### Issuing requests

The chart exposes the pods through two ClusterIP services, `searchd-query` and
`searchd-ingest` (plus a headless `searchd` for the StatefulSet), all on
port 8080. To reach them from your machine, port-forward one of them:

```bash
kubectl -n search port-forward svc/searchd-query 8080:8080
```

Then, from another terminal:

```bash
# Search. Returns {"hits": [], "cold": true} until the index load finishes
# (~90 s locally after pod start), then real hits with scores.
curl 'localhost:8080/search?q=test'

# Ingest a batch — the body is a JSON array of documents. Replies 202.
curl -XPOST localhost:8080/ingest -d '[{"doc":"a"},{"doc":"b"}]'
# {"accepted": 2}

# Process health.
curl localhost:8080/healthz
# {"status": "ok", "pod": "searchd-0", "shard": "0"}

# Index state, doc count, ingest buffer depth.
curl localhost:8080/metrics
# {"index_loaded": true, "docs": 4200000, "uptime_seconds": 120, "ingest_buffer": 2}
```

Ctrl-C the port-forward when you're done.

### Tear it down

```bash
make kind-down      # deletes the kind cluster
```

Locally the index load is shortened to 90 seconds via `env.indexLoadSeconds`.

## Layout

```
app/                  the service itself
helm/                 chart, values, templates
terraform/            node pool and cluster
.github/workflows/    build and deploy
dashboards/           what we currently graph
```

## Known context

- Two engineers are on call, rotating weekly.
- The fleet is sized by hand; there is no autoscaling on it today.
- Traffic is about 4,000 queries/sec steady, peaking near 9,000.
