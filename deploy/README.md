# Axiom Deployment

This directory contains the canonical, **cloud-agnostic** deployment
artifacts for the Axiom Workflow Engine.

## Recommended path: Helm chart

The Helm chart under [`helm/axiom-engine/`](./helm/axiom-engine/) is
the **single canonical deployment path** and works on any conformant
Kubernetes cluster (EKS, GKE, AKS, on-prem, kind, k3d, etc.).

```bash
# Production install with External Secrets Operator + ServiceMonitor
helm repo add axiom https://axiom-workflow-engine.github.io/helm
helm install axiom axiom/axiom-engine \
  --namespace axiom --create-namespace \
  --values values.prod.yaml
```

A minimal local install for development:

```bash
helm install axiom ./helm/axiom-engine \
  --namespace axiom --create-namespace \
  --set replicaCount=1 \
  --set persistence.enabled=false \
  --set externalSecret.enabled=false \
  --set podDisruptionBudget.enabled=false
```

See the chart's [`values.yaml`](./helm/axiom-engine/values.yaml) for
the full list of knobs. Key groups:

| Group                   | What it controls                                |
| ----------------------- | ----------------------------------------------- |
| `replicaCount`          | StatefulSet replicas (default 3)                |
| `podDisruptionBudget`   | `minAvailable` / `maxUnavailable` for the PDB   |
| `rbac`                  | `Role`/`RoleBinding` for k8s API read access     |
| `serviceAccount`        | IRSA annotation for cloud IAM (AWS)             |
| `externalSecret`        | External Secrets Operator wiring                |
| `metrics.serviceMonitor`| Prometheus ServiceMonitor creation              |
| `networkPolicy`         | Default-deny + intra-namespace allow            |
| `persistence`           | WAL volume claim template                       |
| `ingress`               | Hostname + cert-manager TLS                     |

### Secrets

Three mutually exclusive paths exist for engine secrets
(`erlang-cookie`, `secret-key-base`, `jwt-secret`):

1. **Auto-generated (dev/test only)** — default. The chart creates a
   Secret with random values. **Not for production.**
2. **Bring your own Secret** — set `secrets.existingSecret=<name>`
   and pre-create the Secret in the target namespace.
3. **External Secrets Operator (recommended for production)** — set
   `externalSecret.enabled=true` and `externalSecret.secretStoreName=<store>`.
   The chart suppresses the auto-generated Secret and creates an
   `ExternalSecret` that materializes a k8s `Secret` from your
   cloud's secret store. See
   [`examples/externalsecret/`](./examples/externalsecret/) for a
   complete AWS Secrets Manager example.

## Plain manifests: `k8s/`

The [`k8s/`](./k8s/) directory contains rendered, raw Kubernetes
manifests for those who don't want to use Helm. These are kept in
sync with the chart's `default` values and are useful as a
reference or as a starting point for kustomize overlays.

```bash
kubectl apply -f k8s/namespace.yaml
kubectl create -f k8s/secrets.example.yaml  # edit first!
kubectl apply -f k8s/
```

**Do not** apply `secrets.example.yaml` as-is. The values are
placeholders — generate real 64-byte random secrets first (see the
comment in the file).

## Cloud-specific reference modules: `examples/`

Reference Infrastructure-as-Code modules for provisioning the
cluster and supporting infrastructure live under
[`examples/`](./examples/). These are **not** required — Helm works
against any cluster — but they are useful when you want Axiom to
come with its own cluster.

| Path                              | Provider | Notes                         |
| --------------------------------- | -------- | ----------------------------- |
| [`examples/aws/`](./examples/aws/)| AWS      | VPC, EKS, S3, IAM, CloudWatch |

See [`examples/README.md`](./examples/README.md) for the convention
governing the modules in that directory.

## Why Helm and not the Terraform modules as the canonical path?

- **Portability.** The chart runs on any conformant Kubernetes
  distribution. The Terraform modules are inherently cloud-specific.
- **Upgradability.** `helm upgrade` does the right thing. Terraform
  modules for Kubernetes resources are notoriously hard to keep
  idempotent against the live API.
- **Operational symmetry.** SRE tooling (Argo CD, Flux, Helmfile,
  etc.) speaks Helm natively. A separate Terraform path doubles the
  operational surface.

The Terraform modules under `examples/aws/` are still maintained as
a convenience for users who want the engine cluster provisioned
alongside the engine itself. They are not required and are not on
the upgrade-critical path.

## Smoke testing a deploy

```bash
# Wait for the StatefulSet to be ready
kubectl -n axiom rollout status statefulset/axiom-engine

# Port-forward and verify
kubectl -n axiom port-forward svc/axiom-engine 4000:4000 &
curl -fs http://localhost:4000/health
curl -fs http://localhost:4000/ready
curl -fs http://localhost:4000/api/v1/openapi.yaml | head -3
```

## Upgrading

Always use `helm upgrade` (not raw `kubectl apply` after the
initial install) so the chart-managed labels and annotations stay
in sync. Read the [CHANGELOG](../../CHANGELOG.md) before
bumping versions.
