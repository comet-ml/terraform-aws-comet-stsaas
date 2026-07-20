# Migrating in-module Helm releases to ArgoCD (Tier A)

Runbook for moving this module's **in-module `helm_release` resources** to
ArgoCD (`comet-ml/comet-gitops`), while keeping the AWS-side IAM in Terraform.

Scope: **external-secrets** (CRDs + operator) and **karpenter**. The
`eks_blueprints_addons` controllers (ALB controller, cert-manager, external-dns,
cloudwatch-metrics) are **out of scope** — they have no hand-off toggle and are
coupled to the EKS Auto Mode decision; migrate them separately.

## Why this is low-risk

The module was built for this. Both toggles default to `false` (ArgoCD-owned),
and the **IRSA role is created either way** so an external deployment can wire
its ServiceAccount to it. Terraform keeps the IAM; ArgoCD owns the chart.

| Release | Toggle (root var) | Default | IAM kept in TF |
|---------|-------------------|---------|----------------|
| `helm_release.external_secrets_crds` + `.external_secrets` | `external_secrets_via_helm_release` | `false` | `module.external_secrets_irsa_role` |
| `helm_release.karpenter_stsaas` | `eks_karpenter_via_helm_release` | `false` | `module.karpenter_irsa` + SQS/EventBridge/instance-profile |

The `kubectl_manifest.cluster_secret_store` is gated by the same
external-secrets toggle and also moves to ArgoCD (as a manifest in the app).

## The one hazard

If the `helm_release` is **currently in Terraform state**, flipping the toggle
`true → false` makes the next `apply` run **`helm uninstall`** — deleting the
live workload. You must **adopt the release into ArgoCD first** (or
`terraform state rm` it) so Terraform has nothing to uninstall.

---

## Facts to reproduce each release in ArgoCD

**external-secrets** (two TF releases → one ArgoCD app; install CRDs + operator
together, or keep the CRDs-first split):
- repo: `https://charts.external-secrets.io`, chart `external-secrets`
- version: `external_secrets_chart_version` (default **2.2.0** — must match the
  comet-gitops umbrella pin; older leaves stale CRDs that block sync)
- namespace: `external-secrets`
- ServiceAccount `external-secrets:external-secrets`, annotated
  `eks.amazonaws.com/role-arn = <module.external_secrets_irsa_role ARN>`
- operator values in TF: `replicaCount=1`, `serviceAccount.create/automount=true`,
  `webhook.create=true` (`replicaCount=1`), `certController.create=true`
  (`replicaCount=1`), `installCRDs=false` on the operator release
- Plus the `ClusterSecretStore` named `cluster-secret-store`
  (`spec.provider.aws.service=SecretsManager`, region, `auth.jwt.serviceAccountRef`
  → `external-secrets/external-secrets`)

**karpenter**:
- repo: `https://helm.comet.com/` (private — needs `karpenter_helm_username` /
  `karpenter_helm_password`; configure the repo creds in ArgoCD), chart
  `comet-stsaas-karpenter`
- version: `karpenter_chart_version` (default **0.1.0**)
- namespace: `kube-system`
- ServiceAccount `kube-system:karpenter`, annotated
  `eks.amazonaws.com/role-arn = <module.karpenter_irsa ARN>`
- values in TF: `clusterName`, `nodeInstanceProfile`, `karpenter.settings.clusterName`,
  `karpenter.settings.interruptionQueue` (the SQS queue name), plus
  `tags = merge(common_tags, karpenter_extra_tags)`

> Get the exact ARNs/values from the running config:
> `terraform output` or
> `terraform state show module.comet.module.comet_eks[0].module.external_secrets_irsa_role[0].aws_iam_role.this[0]`

---

## Per-release migration sequence

Do this **one release at a time**, per environment.

### 1. Create the ArgoCD Application in comet-gitops
Point it at the same chart + version + values (above). Sync it, but expect it to
find existing resources — the adoption step makes ArgoCD take ownership without a
destructive re-create.

### 2. Adopt the existing release (pick ONE)

**Option A — annotate/label (keeps the workload running, zero downtime):**
Make Helm's uninstall a no-op by handing the release metadata to ArgoCD. For each
existing resource in the release's namespace:
```bash
# example for external-secrets; repeat namespace/release as needed
kubectl -n external-secrets annotate <kind>/<name> \
  meta.helm.sh/release-name- meta.helm.sh/release-namespace- --overwrite
kubectl -n external-secrets label <kind>/<name> \
  app.kubernetes.io/managed-by=Helm- --overwrite
kubectl -n external-secrets label <kind>/<name> \
  argocd.argoproj.io/instance=<argocd-app-name> --overwrite
```
Then let ArgoCD sync/adopt. (Adjust to your ArgoCD resource-tracking method —
label vs annotation.)

**Option B — `terraform state rm` (simpler; ArgoCD then re-owns):**
```bash
terraform state rm 'module.comet.module.comet_eks[0].helm_release.external_secrets[0]'
terraform state rm 'module.comet.module.comet_eks[0].helm_release.external_secrets_crds[0]'
terraform state rm 'module.comet.module.comet_eks[0].kubectl_manifest.cluster_secret_store[0]'
# karpenter:
terraform state rm 'module.comet.module.comet_eks[0].helm_release.karpenter_stsaas[0]'
```
State-rm leaves the live K8s resources untouched; Terraform simply forgets them,
and ArgoCD adopts on next sync.

### 3. Flip the toggle and apply
In the consuming root (comet-gitops/comet-devops), set the root var to `false`:
```hcl
external_secrets_via_helm_release = false   # and/or
eks_karpenter_via_helm_release    = false
```
`terraform plan` should now show **no `helm uninstall`** for that release — only
that the `helm_release` (+ `kubectl_manifest` for external-secrets) leaves state.
The IRSA role and AWS prereqs stay. Apply.

### 4. Verify
- `helm list -n <namespace>` — the release is either gone from Helm (Option B) or
  now shows ArgoCD as manager (Option A); ArgoCD app is **Synced/Healthy**.
- external-secrets: a test `ExternalSecret` still resolves from Secrets Manager
  (confirms IRSA annotation → role still works).
- karpenter: create a pending pod; a node is provisioned (confirms the controller
  runs and can reach the interruption queue). **Do karpenter carefully** — a gap
  where no controller runs means no new nodes spawn for pending pods.

---

## Ordering & rollout
- Migrate **external-secrets first** (less blast radius), **karpenter last**
  (autoscaling-critical).
- Roll per environment: **dev/CI → staging → prod**.
- Per the module docs, `stsaasuat` external-secrets is already orphaned/broken in
  Helm terms, so flipping the toggle there is safe with no adoption dance.

## What stays in Terraform (do NOT remove)
- `module.external_secrets_irsa_role`, `module.karpenter_irsa`
- Karpenter AWS prereqs: SQS interruption queue, EventBridge rules, node IAM role,
  instance profile, EKS access entry, subnet/SG discovery tags
- The `gp3` StorageClass and other `kubernetes_*` resources (unaffected)
