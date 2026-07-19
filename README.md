# bot-detector-k8s
copy paste the application.yaml in argoCD

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
mysql+asyncmy://<user>:<password>@mysql.database.svc:3306/playerdata
```

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
kubectl get ns bd-prd database
kubectl -n database get svc mysql
sops --version           # only needed for the SOPS path
```

### Option 1 — Opaque secret (direct, not committed)

Creates the secret live in the cluster. Nothing is written to Git.

```bash
# Set these in your shell (avoids leaking the URL into shell history files)
DB_URL_PRUNE='mysql+asyncmy://job-prune-reports:PASSWORD@mysql.database.svc:3306/playerdata'
DB_URL_BACKFILL='mysql+asyncmy://job-backfill-banned:PASSWORD@mysql.database.svc:3306/playerdata'

kubectl create secret generic job-prune-reports \
  --namespace=bd-prd \
  --from-literal=DATABASE_URL="$DB_URL_PRUNE"

kubectl create secret generic job-backfill-banned \
  --namespace=bd-prd \
  --from-literal=DATABASE_URL="$DB_URL_BACKFILL"
```

Verify:

```bash
kubectl -n bd-prd get secret job-prune-reports job-backfill-banned
kubectl -n bd-prd get secret job-prune-reports -o jsonpath='{.data.DATABASE_URL}' | base64 -d && echo
```

Update an existing opaque secret in place:

```bash
kubectl -n bd-prd create secret generic job-prune-reports \
  --from-literal=DATABASE_URL="$DB_URL_PRUNE" --dry-run=client -o yaml | kubectl apply -f -
```

### Option 2 — SOPS-encrypted secret (committed, ArgoCD-reconciled)

Produces an encrypted manifest checked into this repo under `jobs/`. The
repo's `.sops.yaml` rule encrypts everything except `apiVersion`, `metadata`,
`kind`, and `type`, using the project `age` recipient.

#### Step 1 — generate the plaintext manifest with `kubectl --dry-run`

```bash
DB_URL_PRUNE='mysql+asyncmy://job-prune-reports:PASSWORD@mysql.database.svc:3306/playerdata'
DB_URL_BACKFILL='mysql+asyncmy://job-backfill-banned:PASSWORD@mysql.database.svc:3306/playerdata'

kubectl create secret generic job-prune-reports \
  --namespace=bd-prd \
  --type=Opaque \
  --from-literal=DATABASE_URL="$DB_URL_PRUNE" \
  --dry-run=client -o yaml > jobs/job-prune-reports.sops.yaml

kubectl create secret generic job-backfill-banned \
  --namespace=bd-prd \
  --type=Opaque \
  --from-literal=DATABASE_URL="$DB_URL_BACKFILL" \
  --dry-run=client -o yaml > jobs/job-backfill-banned.sops.yaml
```

#### Step 2 — encrypt in place with SOPS

```bash
sops --encrypt --in-place jobs/job-prune-reports.sops.yaml
sops --encrypt --in-place jobs/job-backfill-banned.sops.yaml
```

After this step the files contain `ENC[AES256_GCM,...]` values and a `sops:`
block listing the `age` recipient — safe to commit. Verify quickly:

```bash
grep -L 'sops:' jobs/job-prune-reports.sops.yaml jobs/job-backfill-banned.sops.yaml
# (no output = both files are encrypted)
```

#### Step 3 — apply to the cluster

Pick one depending on how the cluster is bootstrapped:

```bash
# Manual one-off: decrypt in memory, never writes plaintext to disk
sops --decrypt jobs/job-prune-reports.sops.yaml   | kubectl apply -f -
sops --decrypt jobs/job-backfill-banned.sops.yaml | kubectl apply -f -

# ArgoCD + KSOPS: commit the .sops.yaml files and let ArgoCD reconcile.
# Make sure the target Application manifest includes the kustomize plugin.
```

#### Editing an encrypted secret later

```bash
# Opens the file in $EDITOR with values decrypted in memory only
sops jobs/job-prune-reports.sops.yaml

# Or rotate a single value non-interactively
sops --set '["DATABASE_URL"] "mysql+asyncmy://job-prune-reports:NEW_PW@mysql.database.svc:3306/playerdata"' \
  jobs/job-prune-reports.sops.yaml
```

### Conventions

- Secret name matches the workload name (`job-prune-reports`, `job-backfill-banned`).
- Key is `DATABASE_URL`, matching the `secretKeyRef` in the Job/CronJob manifests.
- SOPS-encrypted files use the `.sops.yaml` suffix to distinguish them from
  plain manifests.
- Never commit plaintext secrets. The `.sops.yaml` rule has no path filter, so
  any YAML piped through `sops --encrypt` will be encrypted — but it is your
  responsibility to run encryption before `git add`.
