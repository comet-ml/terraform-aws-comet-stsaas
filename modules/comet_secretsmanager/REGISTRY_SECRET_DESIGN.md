# Per-cluster registry pull-secret — Terraform design

Goal: when the stsaas module provisions a cluster, create `cometml/<cluster>/registry`
in the **cluster's (spoke) account**, with the value **copied from a canonical secret**
`cometml/shared/registry` in the **prod (hub) account 094792403439**. Each cluster's ESO
then syncs its own copy into k8s as `comet-ml-registry` (see the comet-infra
ClusterExternalSecret). Rotating the canonical + re-applying updates every cluster.

## Account topology (confirmed)
- **Hub / prod = `094792403439`** — Atlantis runs here; holds the canonical
  `cometml/shared/registry` (already created, valid: docker.comet.com / user `cometml`).
- **Spoke / cluster = `947208553405`** (stsaasuat) — the atlantis workflow assumes
  `947:role/atlantis` and exports those creds, so at TF time **ambient identity = spoke**.
- A spoke session **cannot** read the prod SM secret directly (ResourceNotFound cross-account).

## Module side — DONE (this branch)
`modules/comet_secretsmanager/`:
- `variables.tf`: `enable_registry_secret` (bool, default false) + `registry_dockerconfigjson`
  (string, sensitive, default null).
- `main.tf`: `aws_secretsmanager_secret.registry` (name `cometml/${var.environment}/registry`)
  + `aws_secretsmanager_secret_version.registry` (value = `var.registry_dockerconfigjson`),
  both gated by `count = var.enable_registry_secret ? 1 : 0`.
- Validated (`terraform validate` passes).
- ESO IAM already covers it: the External-Secrets IRSA policy grants
  `secret:cometml/${environment}/*` (`modules/comet_eks/main.tf:820-821`) — no IAM change.

## Root wrapper side — TODO (needs a prod IAM role first)
`comet-devops/terraform/stsaas/stsaasuat/`:

1. **Prerequisite — prod IAM role (account 094):** a role, e.g. `stsaas-canonical-reader`,
   with:
   - Trust policy allowing the spoke atlantis session (`arn:aws:iam::947208553405:role/atlantis`)
     to `sts:AssumeRole` (the ambient identity at TF time).
   - Permission: `secretsmanager:GetSecretValue` on
     `arn:aws:secretsmanager:us-east-1:094792403439:secret:cometml/shared/registry-*`.
   (Existing prod roles seen: `atlantis`, `allow-atlantis`, `registry-manager`,
   `SM-registry-integration-*` — check whether one already fits before creating a new one.)

2. **providers.tf — hub provider alias:**
   ```hcl
   provider "aws" {
     alias  = "hub"
     region = var.resource_region
     assume_role {
       role_arn = var.canonical_secret_reader_role_arn  # 094:role/stsaas-canonical-reader
     }
   }
   ```
   (No default_tags needed — read-only.)

3. **data source + wiring (main.tf):**
   ```hcl
   data "aws_secretsmanager_secret_version" "registry_canonical" {
     count    = var.enable_registry_secret ? 1 : 0
     provider = aws.hub
     secret_id = "cometml/shared/registry"
   }
   # inside module "comet_secretsmanager":
   enable_registry_secret    = var.enable_registry_secret
   registry_dockerconfigjson = try(data.aws_secretsmanager_secret_version.registry_canonical[0].secret_string, null)
   ```

4. **variables:** `enable_registry_secret` (default false) + `canonical_secret_reader_role_arn`.

## Rollout
- stsaasuat already has `cometml/stsaasuat/registry` (created manually 2026-08-12) — so
  enabling this for stsaasuat will **adopt/overwrite** it. Import or let TF take it over;
  value is identical so it's a no-op content-wise.
- New clusters: set `enable_registry_secret = true` in their tfvars → the secret is created
  + ESO CES (comet-infra values) + `cometImages.pullSecret.create=false` (comet-ml values)
  complete the chain. This closes the cold-start ordering gap (secret exists before comet-ml
  first-syncs its PreSync hooks). See the registry-pull-secret memory.

## Why not simpler
- A no-assume-role hub provider would still be the SPOKE (ambient creds are spoke), so it
  can't read prod — hence the explicit prod-role assumption.
- Passing the value via an Atlantis pre-step tfvar was the considered alternative (no new
  IAM role) but the hub-provider approach was chosen for a self-contained, in-TF copy.
