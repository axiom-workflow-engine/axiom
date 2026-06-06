# Cloud-specific infrastructure examples

This directory holds **reference** Infrastructure-as-Code modules
that provision the cluster and supporting infrastructure for
running Axiom on a specific cloud.

## What these are for

The Helm chart under [`../helm/axiom-engine/`](../helm/axiom-engine/)
is the canonical deployment path and works on any conformant
Kubernetes cluster. These modules are **optional convenience
wrappers** for users who want Axiom to ship with its own cluster.

## What these are NOT

- They are not on the upgrade-critical path. Engine upgrades
  happen via `helm upgrade`, not via re-applying Terraform.
- They are not exhaustive. You are expected to read the modules,
  understand what they provision, and customize for your VPC
  layout, compliance boundary, and cost profile.
- They are not a substitute for production hardening. Treat them
  as starting points — review IAM scopes, encryption-at-rest,
  network policy, logging, and backup policies before pointing
  them at a real account.

## Conventions

Every provider module under this directory should follow these
conventions:

1. **Module name is the provider name.** Directory layout is
   `examples/<provider>/<module>.tf`.
2. **Inputs use snake_case.** Module variable names match what the
   Helm chart accepts (e.g. `cluster_name`, `namespace`).
3. **Outputs include `kubeconfig_command`.** Every module must
   emit a `null_resource` (or equivalent) that prints the
   `aws eks update-kubeconfig` / `gcloud container clusters
   get-credentials` / `az aks get-credentials` command needed
   to access the cluster it just provisioned.
4. **State backend is configurable.** The S3 / GCS / AzureRM
   backend block is parameterized via `backend.hcl` so users can
   point at their own state store.
5. **No real secrets in `.tfvars`.** Use a `.tfvars.example` file
   with placeholder values and add it to `.gitignore`.
6. **Provider versions are pinned.** Use the `required_providers`
   block with a `version` constraint, and use `required_version`
   for Terraform itself.

## Available modules

| Module                                       | Status        | Notes                              |
| -------------------------------------------- | ------------- | ---------------------------------- |
| [`aws/`](./aws/)                             | Reference     | VPC + EKS + supporting AWS infra   |
| `gcp/`                                       | Not provided  | Use [`gke`](https://cloud.google.com/kubernetes-engine/docs/terraform-quickstart) or write one |
| `azure/`                                     | Not provided  | Use [`azurerm` AKS](https://learn.microsoft.com/azure/aks/terraform-deploy-k8s) or write one |
| [`externalsecret/`](./externalsecret/)       | Reference     | AWS Secrets Manager via ESO         |

## Local development cluster

If you just need a cluster to test against — without paying for a
real cloud — use one of these instead of the modules here:

```bash
# kind
kind create cluster --config - <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
  - role: worker
  - role: worker
EOF

# k3d
k3d cluster create axiom --agents 3

# minikube
minikube start --nodes 3
```

Then point Helm at the local context and install:

```bash
helm install axiom ../helm/axiom-engine \
  --set replicaCount=1 \
  --set persistence.enabled=false \
  --set externalSecret.enabled=false
```
