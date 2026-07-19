# bot-detector-k8s
copy paste the application.yaml in argoCD

## Repo layout

Each workload lives in its own directory at the repo root, containing
a `deployment.yaml` (or `cronjob.yaml` / `job.yaml`) and, if it needs
secrets, a `*.sops.yaml` file:

```
<workload-name>/
  deployment.yaml
  secret.sops.yaml     # optional, encrypted
jobs/
  <job-name>.yaml      # CronJobs and one-shot Jobs
```

## Secrets

Workloads consume a `DATABASE_URL` (and a few service-specific keys) from
Kubernetes Secrets. Secrets can be created two ways:

- **Opaque** — applied directly to the cluster, never committed. Use for
  local clusters or one-off bootstrapping.
- **SOPS** — encrypted-with-`age` manifests committed to Git and reconciled
  by ArgoCD (via KSOPS). Use for anything tracked in this repo.

The MySQL service is `mysql.database.svc:3306` (Service `mysql` in namespace
`database`). The connection string format is:

```
mysql+asyncmy://<db-user>:<db-password>@mysql.database.svc:3306/playerdata
```

Throughout this guide, replace:

| Placeholder | Meaning |
| --- | --- |
| `<workload-name>` | k8s Deployment/Job/CronJob name, e.g. `ban-migration-worker`, `job-prune-reports` |
| `<db-user>` | MySQL user, e.g. `ban-migration`, `job-prune-reports` |
| `<db-password>` | That user's password |
| `<namespace>` | k8s namespace, almost always `bd-prd` |
| `<secret-dir>` | Directory holding the workload's manifests, e.g. `worker-ban-migration`, `jobs` |

### Prerequisites

| Tool | Why | Install |
| --- | --- | --- |
| `kubectl` | Talk to the cluster | <https://kubernetes.io/releases/download/> |
| Cluster context | Must point at the target cluster, with write on the target namespace | `kubectl config use-context <name>` |
| MySQL user | The DB user referenced in `DATABASE_URL` must exist and have the right grants on `playerdata` | created by `bot_detector/_infra/_mysql/docker-entrypoint-initdb.d/00_init.sql` or manually |
| `sops` | Only for the SOPS path | <https://github.com/getsops/sops/releases> |
| `age` key | Only for the SOPS path — the repo's `.sops.yaml` pins one `age` recipient; you need the matching private key to encrypt/decrypt | <https://github.com/FiloSottile/age> |
| KSOPS / ArgoCD KSOPS plugin | Only if you want ArgoCD to reconcile SOPS files automatically | <https://github.com/viaduct-ai/kustomize-sops> |

Verify before you start:

```bash
kubectl config current-context
kubectl get ns <namespace> database
kubectl -n database get svc mysql
sops --version           # only needed for the SOPS path
```

### Option 1 — Opaque secret (direct, not committed)

Creates the secret live in the cluster. Nothing is written to Git.

```bash
# Set in your shell to avoid leaking the URL into shell history files
DB_URL='mysql+asyncmy://<db-user>:<db-password>@mysql.database.svc:3306/playerdata'

kubectl create secret generic <workload-name> \
  --namespace=<namespace> \
  --from-literal=DATABASE_URL="$DB_URL"
```

Verify:

```bash
kubectl -n <namespace> get secret <workload-name>
kubectl -n <namespace> get secret <workload-name> -o jsonpath='{.data.DATABASE_URL}' | base64 -d && echo
```

Update an existing opaque secret in place:

```bash
kubectl -n <namespace> create secret generic <workload-name> \
  --from-literal=DATABASE_URL="$DB_URL" --dry-run=client -o yaml | kubectl apply -f -
```

### Option 2 — SOPS-encrypted secret (committed, ArgoCD-reconciled)

Produces an encrypted manifest checked into this repo alongside the
workload's other manifests. The repo's `.sops.yaml` rule encrypts everything
except `apiVersion`, `metadata`, `kind`, and `type`, using the project
`age` recipient.

#### Step 1 — generate the plaintext manifest with `kubectl --dry-run`

```bash
DB_URL='mysql+asyncmy://<db-user>:<db-password>@mysql.database.svc:3306/playerdata'

kubectl create secret generic <workload-name> \
  --namespace=<namespace> \
  --type=Opaque \
  --from-literal=DATABASE_URL="$DB_URL" \
  --dry-run=client -o yaml > <secret-dir>/secret.sops.yaml
```

#### Step 2 — encrypt in place with SOPS

```bash
sops --encrypt --in-place <secret-dir>/secret.sops.yaml
```

After this step the file contains `ENC[AES256_GCM,...]` values and a `sops:`
block listing the `age` recipient — safe to commit. Verify quickly:

```bash
grep -L 'sops:' <secret-dir>/secret.sops.yaml
# (no output = file is encrypted)
```

#### Step 3 — apply to the cluster

Pick one depending on how the cluster is bootstrapped:

```bash
# Manual one-off: decrypts in memory, never writes plaintext to disk
sops --decrypt <secret-dir>/secret.sops.yaml | kubectl apply -f -

# ArgoCD + KSOPS: commit the .sops.yaml file and let ArgoCD reconcile.
# Make sure the target Application manifest includes the kustomize plugin.
```

#### Editing an encrypted secret later

```bash
# Opens the file in $EDITOR with values decrypted in memory only
sops <secret-dir>/secret.sops.yaml

# Or rotate a single value non-interactively
sops --set '["DATABASE_URL"] "mysql+asyncmy://<db-user>:NEW_PW@mysql.database.svc:3306/playerdata"' \
  <secret-dir>/secret.sops.yaml
```

### Conventions

- Secret name matches the workload name (e.g. Deployment `ban-migration-worker`
  reads secret `ban-migration-worker`).
- Key is `DATABASE_URL`, matching the `secretKeyRef` in the workload manifest.
- SOPS-encrypted files use the `.sops.yaml` suffix to distinguish them from
  plain manifests.
- Never commit plaintext secrets. The `.sops.yaml` rule has no path filter, so
  any YAML piped through `sops --encrypt` will be encrypted — but it is your
  responsibility to run encryption before `git add`.

## MySQL grants

Every workload runs as a dedicated MySQL user with the minimum grants its
code path needs. Users and grants are defined upstream in the application
repo:

- `bot_detector/_infra/_mysql/docker-entrypoint-initdb.d/00_init.sql` — `CREATE USER`
- `bot_detector/_infra/_mysql/docker-entrypoint-initdb.d/02_grants.sql` — `GRANT` statements, one block per user

To add a new workload's DB user, append to both files mirroring an existing
block. Verify live grants:

```bash
kubectl -n database exec -it <mysql-pod> -- mysql -u root -p -e \
  "SHOW GRANTS FOR '<db-user>'@'%';"
```
