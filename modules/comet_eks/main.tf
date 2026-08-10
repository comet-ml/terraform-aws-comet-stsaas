locals {
  volume_type                  = "gp3"
  volume_encrypted             = false
  volume_delete_on_termination = true

  # Under Auto Mode, pin schedulable add-ons onto the built-in `system` node
  # pool. That pool is labeled karpenter.sh/nodepool=system and tainted
  # CriticalAddonsOnly=true:NoSchedule, so pinning needs BOTH a nodeSelector for
  # the label and a toleration for the taint. DaemonSets (vpc-cni, kube-proxy)
  # are intentionally NOT pinned — they must run on every node.
  #
  # The nodeSelector/toleration below feed both native-addon configuration_values
  # (via auto_mode_pin, merged into each addon's HA config) and the Helm
  # controller `values` (auto_mode_addon_values). All are empty/no-op when Auto
  # Mode is off, so nothing changes for MNG/Karpenter deployments.
  auto_mode_addon_node_selector = { "karpenter.sh/nodepool" = "system" }
  auto_mode_addon_tolerations = [{
    key      = "CriticalAddonsOnly"
    operator = "Exists"
    effect   = "NoSchedule"
  }]

  # Auto Mode pinning fragment (nodeSelector + toleration), merged into each
  # addon's config below. Empty map when Auto Mode is off so it adds nothing.
  # Built via merge so the "off" case is {} without tripping Terraform's
  # conditional-result-type check (a bare ? {...} : {} has mismatched types).
  auto_mode_pin = merge(
    var.enable_auto_mode ? { nodeSelector = local.auto_mode_addon_node_selector } : {},
    var.enable_auto_mode ? { tolerations = local.auto_mode_addon_tolerations } : {},
  )

  # HA settings for schedulable control-plane addons. coredns and the EBS CSI
  # controller already ship a PDB + anti-affinity by default; metrics-server
  # ships a single replica with none. We set these explicitly on all three so
  # HA is visible in code rather than implicit (and overrides the addon's own
  # PDB rather than creating a conflicting second one).
  #
  # Spreading uses topologySpreadConstraints with whenUnsatisfiable=ScheduleAnyway
  # (soft) so pods still schedule on a single-node pool (e.g. a 1-node Auto Mode
  # `system` pool) instead of going Pending — HA when nodes exist, no deadlock
  # when they don't.
  addon_ha_replicas = 2
  addon_ha_pdb      = { maxUnavailable = 1 }
  addon_ha_topology_spread = [{
    maxSkew           = 1
    topologyKey       = "kubernetes.io/hostname"
    whenUnsatisfiable = "ScheduleAnyway"
  }]

  # coredns/metrics-server accept HA + pinning at the top level. metrics-server
  # uses `replicas`; coredns uses `replicaCount`. Both accept podDisruptionBudget
  # and topologySpreadConstraints.
  coredns_config = jsonencode(merge(local.auto_mode_pin, {
    replicaCount              = local.addon_ha_replicas
    podDisruptionBudget       = local.addon_ha_pdb
    topologySpreadConstraints = local.addon_ha_topology_spread
  }))
  metrics_server_config = jsonencode(merge(local.auto_mode_pin, {
    replicas                  = local.addon_ha_replicas
    podDisruptionBudget       = local.addon_ha_pdb
    topologySpreadConstraints = local.addon_ha_topology_spread
  }))

  # EBS CSI nests everything under `controller` (the controller Deployment; the
  # node DaemonSet is unaffected).
  auto_mode_ebs_csi_config = jsonencode({
    controller = merge(local.auto_mode_pin, {
      replicaCount              = local.addon_ha_replicas
      podDisruptionBudget       = local.addon_ha_pdb
      topologySpreadConstraints = local.addon_ha_topology_spread
    })
  })

  # Helm controllers take a YAML values doc with top-level nodeSelector/tolerations.
  auto_mode_addon_values = var.enable_auto_mode ? [yamlencode({
    nodeSelector = local.auto_mode_addon_node_selector
    tolerations  = local.auto_mode_addon_tolerations
  })] : []

  # Check if additional S3 bucket ARNs are provided
  has_additional_s3_buckets = var.additional_s3_bucket_arns != null && length(var.additional_s3_bucket_arns) > 0

  # Build the IAM policies map for node groups
  # Combines the comet S3 policy (if enabled) with additional S3 policy (if buckets provided)
  node_group_iam_policies = merge(
    var.s3_enabled ? { comet_s3_access = var.comet_ec2_s3_iam_policy } : {},
    local.has_additional_s3_buckets ? { additional_s3_access = aws_iam_policy.additional_s3_bucket_policy[0].arn } : {}
  )

  # Auto-generate security group rules for private access CIDRs
  private_access_sg_rules = var.eks_cluster_endpoint_private_access && length(var.eks_private_access_cidrs) > 0 ? {
    for idx, cidr in var.eks_private_access_cidrs : "private_access_${idx}" => {
      description = "Allow private access from ${cidr}"
      protocol    = "-1" # All protocols
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      cidr_blocks = [cidr]
    }
  } : {}

  # Merge auto-generated rules with any additional custom rules
  cluster_security_group_rules = merge(
    local.private_access_sg_rules,
    var.eks_cluster_security_group_additional_rules
  )

  # Tags the Cluster Autoscaler uses for auto-discovery of ASGs. Merged into
  # local.eks_managed_node_group_defaults.tags so every managed nodegroup
  # inherits them automatically. When CA is disabled this is empty and the
  # tags are not applied.
  cluster_autoscaler_asg_tags = var.eks_enable_cluster_autoscaler ? {
    "k8s.io/cluster-autoscaler/enabled"                 = "true"
    "k8s.io/cluster-autoscaler/${var.eks_cluster_name}" = "owned"
  } : {}

  # Defaults applied to every entry in eks_managed_node_groups. v21 of the
  # upstream module dropped the top-level eks_managed_node_group_defaults
  # variable, so we merge these into each entry below.
  eks_managed_node_group_defaults = merge(
    {
      ami_type                   = var.eks_mng_ami_type
      enable_bootstrap_user_data = true
      enable_monitoring          = true
      force_update_version       = var.eks_mng_force_update_version
      # When false, the node group keeps its current AMI release (release_version
      # is left AWS-managed) instead of bumping to the latest on every apply —
      # lets AMI rolls be scheduled separately from other terraform changes.
      use_latest_ami_release_version = var.eks_mng_use_latest_ami_release_version
      # Node groups always point at the launch template's numeric default_version,
      # NOT the "$Latest"/"$Default" aliases. Passing an alias makes terraform
      # store the literal string in config while AWS resolves it to a number, so
      # every plan shows a spurious `version = "N" -> "$Latest"` diff that never
      # converges. Pointing at default_version (a concrete number) keeps plans
      # clean. Set here once in the shared defaults so every node group inherits
      # it (rather than repeating it per entry).
      launch_template_version = null
      # This knob only controls whether default_version auto-advances: when
      # pinned, new LT versions are NOT promoted to default, so node groups don't
      # roll on benign LT changes (e.g. tag-only bumps); deliberate rolls bump the
      # default.
      update_launch_template_default_version = !var.eks_mng_pin_launch_template_version
      # Set platform based on AMI type - AL2023 uses nodeadm, AL2 uses bootstrap.sh
      platform = startswith(var.eks_mng_ami_type, "AL2023") ? "al2023" : "linux"
      # Preserve v20 IMDS hop limit of 2. v21 default is 1 — flipping it would
      # break any sidecar/proxy pattern that reaches IMDS through an extra hop.
      metadata_options = {
        http_endpoint               = "enabled"
        http_tokens                 = "required"
        http_put_response_hop_limit = 2
        instance_metadata_tags      = "disabled"
      }
      # common_tags on the nodegroup propagate to instances; CA discovery
      # tags must be on the ASG so the autoscaler can match them.
      tags = merge(var.common_tags, local.cluster_autoscaler_asg_tags)
    },
    var.eks_mng_ami_id != null ? {
      ami_id = var.eks_mng_ami_id
    } : {}
  )

  # Build access entries for admin roles
  admin_access_entries = {
    for arn in var.eks_admin_role_arns : arn => {
      principal_arn = arn
      type          = "STANDARD"
      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }
}

# IAM policy for additional S3 bucket access (only created if additional_s3_bucket_arns is provided)
resource "aws_iam_policy" "additional_s3_bucket_policy" {
  count = local.has_additional_s3_buckets ? 1 : 0

  name        = "additional-s3-access-policy-${var.eks_cluster_name}"
  description = "Policy for access to additional S3 buckets from EKS cluster ${var.eks_cluster_name}"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:ListBucket*",
          "s3:PutBucket*",
          "s3:GetBucket*",
          "s3:AbortMultipartUpload",
          "s3:ListMultipartUploadParts",
          "s3:ListBucketMultipartUploads"
        ],
        Resource = flatten([
          for arn in var.additional_s3_bucket_arns : [
            arn,
            "${arn}/*"
          ]
        ])
      }
    ]
  })

  tags = merge(
    var.common_tags,
    {
      Name = "additional-s3-access-policy-${var.eks_cluster_name}"
    }
  )
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.24.0"

  name                    = var.eks_cluster_name
  kubernetes_version      = var.eks_cluster_version
  endpoint_public_access  = var.eks_cluster_endpoint_public_access
  endpoint_private_access = var.eks_cluster_endpoint_private_access
  deletion_protection     = var.eks_cluster_deletion_protection

  security_group_additional_rules = local.cluster_security_group_rules

  authentication_mode                      = var.eks_authentication_mode
  enable_cluster_creator_admin_permissions = var.eks_enable_cluster_creator_admin_permissions

  access_entries = local.admin_access_entries

  # KMS key access control for cluster encryption
  kms_key_administrators = var.kms_key_administrators
  kms_key_users          = var.kms_key_users

  vpc_id     = var.vpc_id
  subnet_ids = var.eks_private_subnets

  # EKS Auto Mode. When enabled, the control plane provisions nodes via the
  # built-in node pools and the upstream module auto-creates/wires the Auto Mode
  # node IAM role (so node_role_arn is intentionally omitted). The block is
  # always sent — enabled = false explicitly disables Auto Mode so a cluster that
  # previously had it on can be turned back off (a bare null would omit the
  # argument and leave the last-applied config in place).
  compute_config = {
    enabled    = var.enable_auto_mode
    node_pools = var.enable_auto_mode ? var.auto_mode_node_pools : []
  }

  # Bake the Karpenter discovery tag directly into the node SG so it is never
  # dropped when Terraform modifies the security group during subsequent applies.
  node_security_group_tags = var.enable_karpenter ? {
    "karpenter.sh/discovery" = var.eks_cluster_name
  } : {}

  # Native EKS managed addons. These are plain aws_eks_addon passthroughs, so
  # they live on the eks module directly rather than in a separate addons wrapper.
  # aws-ebs-csi-driver is intentionally NOT here — it needs the IRSA role, which
  # depends on this module's OIDC output, so it is a standalone aws_eks_addon
  # below to avoid an eks -> irsa -> eks dependency cycle.
  addons = merge(
    {
      # vpc-cni and kube-proxy are DaemonSets — not pinned to the system pool.
      # vpc-cni must be ready before nodes join, so provision it before compute.
      # DND-1082: when eks_enable_network_policy is set, turn on the CNI's
      # Kubernetes NetworkPolicy enforcement (enableNetworkPolicy=true runs the
      # aws-eks-nodeagent). NetworkPolicy objects are created-but-ignored until
      # this is on. Off leaves the addon at AWS defaults (enforcement disabled).
      vpc-cni = merge(
        { before_compute = true },
        var.eks_enable_network_policy ? {
          configuration_values = jsonencode({ enableNetworkPolicy = "true" })
        } : {}
      )
      kube-proxy = {}
      # coredns is a schedulable Deployment — HA (2 replicas + PDB + soft
      # topology spread) plus system-pool pinning under Auto Mode. See the
      # coredns_config local.
      coredns = {
        configuration_values = local.coredns_config
      }
    },
    # metrics-server is required for HPA and `kubectl top`. It runs in
    # kube-system and listens on port 10251; node SG rule above lets the
    # kube-apiserver reach it. Schedulable Deployment — HA + pinned under Auto
    # Mode (metrics_server_config local).
    var.eks_enable_metrics_server ? {
      metrics-server = merge(
        var.eks_metrics_server_addon_version != null ? {
          addon_version = var.eks_metrics_server_addon_version
        } : {},
        {
          configuration_values = local.metrics_server_config
        }
      )
    } : {},
    # cert-manager as a native EKS managed add-on (no IAM required). Replaces the
    # eks_blueprints_addons helm release; installs via the EKS control-plane API
    # (works on private clusters with no data-plane access). Schedulable
    # Deployment — HA (2 replicas + PDB + soft spread) + Auto Mode pinning, same
    # shape as coredns (both use replicaCount). See coredns_config local.
    var.eks_cert_manager ? {
      cert-manager = merge(
        var.eks_cert_manager_addon_version != null ? {
          addon_version = var.eks_cert_manager_addon_version
        } : {},
        {
          configuration_values = local.coredns_config
        }
      )
    } : {},
    # external-dns as a native EKS managed add-on. Uses EKS Pod Identity (not
    # IRSA) for Route53 access — see the external_dns IAM role above and the
    # pod-identity-agent add-on below. Replaces the eks_blueprints_addons helm
    # release. external-dns is single-replica by design (leader election) — its
    # addon schema exposes no replicaCount/PDB — so it takes system-pool pinning
    # only (auto_mode_pin), not the full HA config.
    var.eks_external_dns ? {
      external-dns = merge(
        {
          pod_identity_association = [{
            role_arn        = aws_iam_role.external_dns[0].arn
            service_account = "external-dns"
          }]
        },
        var.eks_external_dns_addon_version != null ? {
          addon_version = var.eks_external_dns_addon_version
        } : {},
        length(local.auto_mode_pin) > 0 ? {
          configuration_values = jsonencode(local.auto_mode_pin)
        } : {}
      )
    } : {},
    # Pod Identity agent — required for any add-on/workload using EKS Pod Identity
    # (currently external-dns). Enabled whenever external-dns is on.
    var.eks_external_dns ? {
      eks-pod-identity-agent = {}
    } : {},
    # Observability add-ons (native EKS managed add-ons, no IAM required).
    # kube-state-metrics is a schedulable Deployment — HA (replicas + PDB +
    # spread) + pinning, same shape as metrics-server (both use `replicas`).
    var.eks_enable_kube_state_metrics ? {
      kube-state-metrics = merge(
        var.eks_kube_state_metrics_addon_version != null ? {
          addon_version = var.eks_kube_state_metrics_addon_version
        } : {},
        {
          configuration_values = local.metrics_server_config
        }
      )
    } : {},
    var.eks_enable_prometheus_node_exporter ? {
      # DaemonSet — runs on every node, so not pinned to the system pool.
      prometheus-node-exporter = var.eks_prometheus_node_exporter_addon_version != null ? {
        addon_version = var.eks_prometheus_node_exporter_addon_version
      } : {}
    } : {},
    var.eks_enable_node_monitoring_agent ? {
      # DaemonSet — runs on every node, so not pinned to the system pool.
      eks-node-monitoring-agent = var.eks_node_monitoring_agent_addon_version != null ? {
        addon_version = var.eks_node_monitoring_agent_addon_version
      } : {}
    } : {}
  )

  eks_managed_node_groups = merge(
    # Karpenter Node Group — created when Karpenter is enabled.
    # Dedicated to the Karpenter controller only; tainted so no other pods schedule here.
    # All other node groups are suppressed when Karpenter is enabled (Karpenter provisions them).
    var.enable_karpenter ? {
      karpenter = merge(local.eks_managed_node_group_defaults, {
        name           = "karpenter"
        instance_types = var.eks_karpenter_node_instance_types
        min_size       = var.eks_karpenter_node_min_size
        max_size       = var.eks_karpenter_node_max_size
        desired_size   = var.eks_karpenter_node_desired_size
        block_device_mappings = {
          xvda = {
            device_name = "/dev/xvda"
            ebs = {
              volume_size           = var.eks_karpenter_node_disk_size
              volume_type           = local.volume_type
              encrypted             = local.volume_encrypted
              delete_on_termination = local.volume_delete_on_termination
            }
          }
        }
        labels = {
          nodegroup_name = "karpenter"
        }
        taints = {
          dedicated = {
            key    = "dedicated"
            value  = "karpenter"
            effect = "NO_SCHEDULE"
          }
        }
        tags_propagate_at_launch     = true
        iam_role_additional_policies = local.node_group_iam_policies
      })
    } : {},
    # Admin Node Group — always created when enabled. Required for system workloads (cert-manager, LBC,
    # external-secrets, etc.) before Karpenter bootstraps, and for infra isolation in production.
    # When Karpenter is enabled, uses smaller instance types since these nodes only run system pods.
    var.enable_admin_node_group ? {
      admin = merge(local.eks_managed_node_group_defaults, {
        name           = var.eks_admin_name
        instance_types = var.enable_karpenter ? var.eks_admin_karpenter_instance_types : var.eks_admin_instance_types
        capacity_type  = var.eks_admin_capacity_type
        min_size       = var.eks_admin_min_size
        max_size       = var.eks_admin_max_size
        desired_size   = var.eks_admin_desired_size
        block_device_mappings = {
          xvda = {
            device_name = "/dev/xvda"
            ebs = {
              volume_size           = var.eks_mng_disk_size
              volume_type           = local.volume_type
              encrypted             = local.volume_encrypted
              delete_on_termination = local.volume_delete_on_termination
            }
          }
        }
        labels = {
          nodegroup_name = "admin"
        }
        tags_propagate_at_launch     = true
        iam_role_additional_policies = local.node_group_iam_policies
        },
        var.eks_admin_ami_type != null ? { ami_type = var.eks_admin_ami_type } : {},
      var.eks_admin_subnet_ids != null ? { subnet_ids = var.eks_admin_subnet_ids } : {})
    } : {},
    # Comet Node Group — disabled when Karpenter is enabled (Karpenter provisions comet nodes)
    (var.enable_comet_node_group && !var.enable_karpenter) ? {
      comet = merge(local.eks_managed_node_group_defaults, {
        name            = var.eks_comet_name
        use_name_prefix = var.eks_comet_use_name_prefix
        iam_role_name   = var.eks_comet_iam_role_name
        instance_types  = var.eks_comet_instance_types
        capacity_type   = var.eks_comet_capacity_type
        min_size        = var.eks_comet_min_size
        max_size        = var.eks_comet_max_size
        desired_size    = var.eks_comet_desired_size
        block_device_mappings = {
          xvda = {
            device_name = "/dev/xvda"
            ebs = {
              volume_size           = var.eks_mng_disk_size
              volume_type           = local.volume_type
              encrypted             = local.volume_encrypted
              delete_on_termination = local.volume_delete_on_termination
            }
          }
        }
        labels = {
          nodegroup_name = "comet"
        }
        tags_propagate_at_launch     = true
        iam_role_additional_policies = local.node_group_iam_policies
        },
        var.eks_comet_ami_type != null ? { ami_type = var.eks_comet_ami_type } : {},
      var.eks_comet_subnet_ids != null ? { subnet_ids = var.eks_comet_subnet_ids } : {})
    } : {},
    # Druid Node Group — disabled when Karpenter is enabled
    (var.enable_druid_node_group && var.enable_mpm_infra && !var.enable_karpenter) ? {
      druid = merge(local.eks_managed_node_group_defaults, {
        name           = var.eks_druid_name
        instance_types = var.eks_druid_instance_types
        min_size       = var.eks_druid_min_size
        max_size       = var.eks_druid_max_size
        desired_size   = var.eks_druid_desired_size
        block_device_mappings = {
          xvda = {
            device_name = "/dev/xvda"
            ebs = {
              volume_size           = var.eks_mng_disk_size
              volume_type           = local.volume_type
              encrypted             = local.volume_encrypted
              delete_on_termination = local.volume_delete_on_termination
            }
          }
        }
        labels = {
          nodegroup_name = "druid"
        }
        tags_propagate_at_launch     = true
        iam_role_additional_policies = local.node_group_iam_policies
        },
      var.eks_druid_subnet_ids != null ? { subnet_ids = var.eks_druid_subnet_ids } : {})
    } : {},
    # Airflow Node Group — disabled when Karpenter is enabled
    (var.enable_airflow_node_group && var.enable_mpm_infra && !var.enable_karpenter) ? {
      airflow = merge(local.eks_managed_node_group_defaults, {
        name           = var.eks_airflow_name
        instance_types = var.eks_airflow_instance_types
        min_size       = var.eks_airflow_min_size
        max_size       = var.eks_airflow_max_size
        desired_size   = var.eks_airflow_desired_size
        block_device_mappings = {
          xvda = {
            device_name = "/dev/xvda"
            ebs = {
              volume_size           = var.eks_mng_disk_size
              volume_type           = local.volume_type
              encrypted             = local.volume_encrypted
              delete_on_termination = local.volume_delete_on_termination
            }
          }
        }
        labels = {
          nodegroup_name = "airflow"
        }
        tags_propagate_at_launch     = true
        iam_role_additional_policies = local.node_group_iam_policies
        },
      var.eks_airflow_subnet_ids != null ? { subnet_ids = var.eks_airflow_subnet_ids } : {})
    } : {},
    # ClickHouse Node Group — requires explicit opt-in AND Karpenter must be disabled
    (var.enable_clickhouse_node_group && !var.enable_karpenter) ? {
      clickhouse = merge(local.eks_managed_node_group_defaults, {
        name            = var.eks_clickhouse_name
        use_name_prefix = var.eks_clickhouse_use_name_prefix
        iam_role_name   = var.eks_clickhouse_iam_role_name
        instance_types  = var.eks_clickhouse_instance_types
        capacity_type   = var.eks_clickhouse_capacity_type
        min_size        = var.eks_clickhouse_min_size
        max_size        = var.eks_clickhouse_max_size
        desired_size    = var.eks_clickhouse_desired_size
        block_device_mappings = {
          xvda = {
            device_name = "/dev/xvda"
            ebs = {
              volume_size           = var.eks_clickhouse_volume_size
              volume_type           = var.eks_clickhouse_volume_type
              encrypted             = var.eks_clickhouse_volume_encrypted
              delete_on_termination = var.eks_clickhouse_delete_on_termination
            }
          }
        }
        labels = {
          nodegroup_name = "clickhouse"
        }
        taints                       = var.eks_clickhouse_taints
        tags_propagate_at_launch     = true
        iam_role_additional_policies = local.node_group_iam_policies
        },
        var.eks_clickhouse_ami_type != null ? { ami_type = var.eks_clickhouse_ami_type } : {},
      var.eks_clickhouse_subnet_ids != null ? { subnet_ids = var.eks_clickhouse_subnet_ids } : {})
    } : {},
    # Additional custom node groups
    {
      for k, v in var.additional_node_groups : k => merge(
        local.eks_managed_node_group_defaults,
        v,
        {
          tags             = merge(local.eks_managed_node_group_defaults.tags, lookup(v, "tags", {}))
          metadata_options = merge(local.eks_managed_node_group_defaults.metadata_options, lookup(v, "metadata_options", {}))
        }
      )
    }
  )
}


module "irsa-ebs-csi" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.39"

  role_name             = "AmazonEKSTFEBSCSIRole-${module.eks.cluster_name}"
  attach_ebs_csi_policy = true

  oidc_providers = {
    ex = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}

# State migration: native addons moved out of the eks_blueprints_addons module.
# coredns/kube-proxy/metrics-server now live on module.eks.addons (aws_eks_addon.this),
# vpc-cni is provisioned before_compute (aws_eks_addon.before_compute), and
# aws-ebs-csi-driver is the standalone resource below. Because these stay the
# same resource TYPE (aws_eks_addon), the moved blocks make the transition a
# no-op on existing clusters instead of destroy/recreate.
#
# NOTE: cert-manager and external-dns are NOT covered by moved blocks. On
# brownfield clusters they were installed as Helm releases by
# eks_blueprints_addons; here they become aws_eks_addon (module.eks.addons).
# That is a resource-TYPE change (helm_release -> aws_eks_addon), which a moved
# block cannot express. So for a cluster that already runs them via Helm, the
# first apply will DESTROY the Helm release and CREATE the native add-on — not
# a no-op. Sequence per environment before applying:
#   1. `terraform plan` and confirm the only cert-manager/external-dns change is
#      helm_release destroy + aws_eks_addon create (no other collateral).
#   2. Optionally `terraform state rm` the old helm_release and
#      `terraform import` the add-on to avoid a brief in-cluster gap; otherwise
#      accept the short recreate window (cert issuance / DNS reconcile pauses).
moved {
  from = module.eks_blueprints_addons.aws_eks_addon.this["coredns"]
  to   = module.eks.aws_eks_addon.this["coredns"]
}

moved {
  from = module.eks_blueprints_addons.aws_eks_addon.this["kube-proxy"]
  to   = module.eks.aws_eks_addon.this["kube-proxy"]
}

moved {
  from = module.eks_blueprints_addons.aws_eks_addon.this["vpc-cni"]
  to   = module.eks.aws_eks_addon.before_compute["vpc-cni"]
}

moved {
  from = module.eks_blueprints_addons.aws_eks_addon.this["metrics-server"]
  to   = module.eks.aws_eks_addon.this["metrics-server"]
}

moved {
  from = module.eks_blueprints_addons.aws_eks_addon.this["aws-ebs-csi-driver"]
  to   = aws_eks_addon.ebs_csi
}

# aws-ebs-csi-driver managed addon. Standalone (not in module.eks.addons)
# because its IRSA role depends on the eks module's OIDC output — putting it
# inside the module would create an eks -> irsa-ebs-csi -> eks cycle.
resource "aws_eks_addon" "ebs_csi" {
  cluster_name             = module.eks.cluster_name
  addon_name               = "aws-ebs-csi-driver"
  service_account_role_arn = module.irsa-ebs-csi.iam_role_arn

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  # Pin the controller Deployment to the system pool under Auto Mode. The node
  # DaemonSet (ebs-csi-node) is unaffected — it must run on every node.
  configuration_values = local.auto_mode_ebs_csi_config

  tags = var.common_tags
}

# EKS Auto Mode + managed node group coexistence.
#
# Auto Mode nodes attach the EKS-managed cluster primary security group, while
# managed node groups use this module's node security group. Neither SG allows
# the other by default, so cross-node-type pod traffic is dropped — e.g. a pod
# on a managed node cannot reach coredns running on an Auto Mode node, breaking
# DNS for the whole managed-node fleet. Allow all traffic both ways between the
# two SGs. Only created while Auto Mode is enabled (i.e. during coexistence).
resource "aws_vpc_security_group_ingress_rule" "auto_mode_cluster_from_node" {
  count                        = var.enable_auto_mode ? 1 : 0
  security_group_id            = module.eks.cluster_primary_security_group_id
  referenced_security_group_id = module.eks.node_security_group_id
  ip_protocol                  = "-1"
  description                  = "auto-mode and managed node coexistence"
}

resource "aws_vpc_security_group_ingress_rule" "auto_mode_node_from_cluster" {
  count                        = var.enable_auto_mode ? 1 : 0
  security_group_id            = module.eks.node_security_group_id
  referenced_security_group_id = module.eks.cluster_primary_security_group_id
  ip_protocol                  = "-1"
  description                  = "auto-mode and managed node coexistence"
}

# external-dns Pod Identity role. The external-dns EKS add-on authenticates via
# Pod Identity (not IRSA), so it needs a role trusted by pods.eks.amazonaws.com
# with Route53 permissions scoped to the configured hosted zones.
data "aws_iam_policy_document" "external_dns_assume" {
  count = var.eks_external_dns ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "external_dns" {
  count = var.eks_external_dns ? 1 : 0

  # Change records only on the specific hosted zones external-dns manages.
  statement {
    effect    = "Allow"
    actions   = ["route53:ChangeResourceRecordSets"]
    resources = var.eks_external_dns_r53_zones
  }

  # Discovery of zones/records is list/read and not zone-scopable.
  statement {
    effect    = "Allow"
    actions   = ["route53:ListHostedZones", "route53:ListResourceRecordSets", "route53:ListTagsForResource"]
    resources = ["*"]
  }
}

resource "aws_iam_role" "external_dns" {
  count = var.eks_external_dns ? 1 : 0

  name               = "${var.environment}-external-dns"
  assume_role_policy = data.aws_iam_policy_document.external_dns_assume[0].json

  tags = merge(var.common_tags, {
    Name        = "${var.environment}-external-dns"
    Description = "Pod Identity role for the external-dns EKS add-on - Route53"
  })
}

resource "aws_iam_role_policy" "external_dns" {
  count = var.eks_external_dns ? 1 : 0

  name   = "route53-access"
  role   = aws_iam_role.external_dns[0].id
  policy = data.aws_iam_policy_document.external_dns[0].json
}

# StorageClasses (gp3 default + comet-generic) moved to the comet-infra umbrella
# chart (ArgoCD-owned) — see comet-devops-helm/charts/comet-infra. The former
# wait_for_alb_webhook settle delay went with them; ordering for ALB-webhook
# dependents is enforced ArgoCD-side (sync waves), not in Terraform. This module
# no longer touches the Kubernetes API for storage classes.

#########################################
#### Cluster Autoscaler IRSA Role ####
#########################################
# Allows the cluster-autoscaler service account (deployed out-of-band by
# ArgoCD) to describe and modify EKS-managed ASGs. ASG auto-discovery is
# driven by the `k8s.io/cluster-autoscaler/*` tags applied via
# `eks_managed_node_group_defaults.tags` above.
module "cluster_autoscaler_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.39"

  count = var.eks_enable_cluster_autoscaler ? 1 : 0

  role_name                        = "${var.environment}-cluster-autoscaler"
  attach_cluster_autoscaler_policy = true
  cluster_autoscaler_cluster_names = [var.eks_cluster_name]

  oidc_providers = {
    ex = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:cluster-autoscaler"]
    }
  }

  tags = merge(
    var.common_tags,
    {
      Name        = "${var.environment}-cluster-autoscaler"
      Description = "IRSA role for Cluster Autoscaler to manage EKS-managed ASGs"
    }
  )
}

#########################################
#### AWS Load Balancer Controller IRSA Role ####
#########################################
# IAM only. The AWS Load Balancer Controller Helm chart itself is deployed
# out-of-band per stsaas customer via ArgoCD (comet-gitops) — there is no native
# EKS add-on for it. This role is exposed via the aws_load_balancer_controller_role_arn
# output; the ArgoCD Application annotates the controller ServiceAccount
# (kube-system:aws-load-balancer-controller) with it.
module "aws_load_balancer_controller_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.39"

  count = var.eks_aws_load_balancer_controller ? 1 : 0

  role_name                              = "${var.environment}-aws-load-balancer-controller"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    ex = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }

  tags = merge(
    var.common_tags,
    {
      Name        = "${var.environment}-aws-load-balancer-controller"
      Description = "IRSA role for the AWS Load Balancer Controller - deployed via ArgoCD"
    }
  )
}

#########################################
#### External Secrets IRSA Role ####
#########################################
# This role allows the external-secrets service account to access AWS Secrets Manager
module "external_secrets_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.39"

  count = var.enable_external_secrets ? 1 : 0

  # Role name defaults to {environment}-external-secrets; override to adopt an
  # existing differently-named role (e.g. legacy hand-rolled "zoox-external-secrets")
  # without recreating it (which would break the SA's IRSA annotation).
  role_name = coalesce(var.external_secrets_iam_role_name_override, "${var.environment}-external-secrets")

  # Attach the external secrets policy that allows Secrets Manager access
  attach_external_secrets_policy = true

  # Limit access to secrets matching the environment's path pattern
  # Uses coalesce() to match how secrets are created in the comet_secretsmanager module:
  # - If secretsmanager_environment is set, use it (e.g., "mercedesamgf1")
  # - Otherwise, fall back to environment (e.g., "mercedesamgf1-euw2")
  external_secrets_secrets_manager_arns = [
    "arn:aws:secretsmanager:*:*:secret:cometml/${coalesce(var.secretsmanager_environment, var.environment)}/*"
  ]

  # Configure OIDC provider for IRSA
  # This allows the Kubernetes service account to assume this IAM role
  oidc_providers = {
    ex = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = var.external_secrets_namespace_service_accounts
    }
  }

  tags = merge(
    var.common_tags,
    {
      Name        = "${var.environment}-external-secrets"
      Description = "IRSA role for External Secrets Operator to access AWS Secrets Manager"
    }
  )
}

#########################################
#### Loki IRSA Role and IAM Policy ####
#########################################
data "aws_iam_policy_document" "loki" {
  count = var.enable_loki ? 1 : 0

  statement {
    actions = [
      "s3:ListBucket",
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject",
    ]
    resources = [
      var.loki_s3_bucket_arn,
      "${var.loki_s3_bucket_arn}/*"
    ]
  }
}

resource "aws_iam_policy" "loki" {
  count = var.enable_loki ? 1 : 0

  name_prefix = "${var.environment}-loki-"
  description = "Provides permissions for Loki on ${var.environment} cluster"
  policy      = data.aws_iam_policy_document.loki[0].json

  tags = merge(
    var.common_tags,
    {
      Name = "${var.environment}-loki"
    }
  )
}

module "loki_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.39"

  count = var.enable_loki ? 1 : 0

  role_name = coalesce(var.loki_iam_role_name_override, "${var.environment}-loki")

  role_policy_arns = {
    loki = aws_iam_policy.loki[0].arn
  }

  oidc_providers = {
    ex = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["monitoring:monitoring-loki"]
    }
  }

  depends_on = [
    module.eks,
    aws_iam_policy.loki
  ]

  tags = merge(
    var.common_tags,
    {
      Name        = "${var.environment}-loki"
      Description = "IRSA role for Loki to access S3 bucket for log storage"
    }
  )
}

################################################################
#### BYO-S3 IRSA Roles (customer-supplied bucket) - DND-1423 ###
################################################################
# One IRSA role + scoped customer-managed policy per byo_s3_irsa_roles entry.
# Generalizes the out-of-band ZooxS3Access pattern: a set of ServiceAccounts
# gets scoped access to a customer's own S3 bucket. The upstream IRSA module
# builds the OIDC web-identity trust (:sub/:aud) from namespace_service_accounts.
locals {
  # Default action set matches the live ClickHouse-backup S3 usage.
  byo_s3_default_actions = [
    "s3:GetObject",
    "s3:PutObject",
    "s3:DeleteObject",
    "s3:ListBucket",
    "s3:AbortMultipartUpload",
    "s3:ListMultipartUploadParts",
    "s3:ListBucketMultipartUploads",
  ]
}

data "aws_iam_policy_document" "byo_s3" {
  for_each = var.byo_s3_irsa_roles

  statement {
    effect  = "Allow"
    actions = coalesce(each.value.actions, local.byo_s3_default_actions)
    # Scoped to the supplied bucket(s) - bucket ARN (for ListBucket) + objects.
    resources = flatten([
      for arn in each.value.bucket_arns : [arn, "${arn}/*"]
    ])
  }
}

resource "aws_iam_policy" "byo_s3" {
  for_each = var.byo_s3_irsa_roles

  # name when adopting an existing policy in place; name_prefix otherwise.
  name        = each.value.policy_name_override
  name_prefix = each.value.policy_name_override == null ? "${var.environment}-byo-s3-${each.key}-" : null
  description = "BYO-S3 access for ${each.key} on ${var.environment} cluster (DND-1423)"
  policy      = data.aws_iam_policy_document.byo_s3[each.key].json

  tags = merge(
    var.common_tags,
    {
      Name = coalesce(each.value.policy_name_override, "${var.environment}-byo-s3-${each.key}")
    }
  )
}

module "byo_s3_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.39"

  for_each = var.byo_s3_irsa_roles

  role_name = coalesce(each.value.role_name_override, "${var.environment}-byo-s3-${each.key}")

  role_policy_arns = {
    byo_s3 = aws_iam_policy.byo_s3[each.key].arn
  }

  oidc_providers = {
    ex = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = each.value.namespace_service_accounts
    }
  }

  depends_on = [
    module.eks,
    aws_iam_policy.byo_s3
  ]

  tags = merge(
    var.common_tags,
    {
      Name        = coalesce(each.value.role_name_override, "${var.environment}-byo-s3-${each.key}")
      Description = "IRSA role granting listed ServiceAccounts scoped access to a customer-supplied S3 bucket"
    }
  )
}

##################################################
#### CloudWatch Exporter IRSA Role and Policy ####
##################################################
data "aws_iam_policy_document" "cloudwatch_exporter" {
  count = var.enable_cloudwatch_exporter ? 1 : 0

  statement {
    actions = [
      "cloudwatch:Describe*",
      "cloudwatch:Get*",
      "cloudwatch:List*",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "cloudwatch_exporter" {
  count = var.enable_cloudwatch_exporter ? 1 : 0

  name_prefix = "${var.environment}-cloudwatch-exporter-"
  description = "Provides CloudWatch read access for prometheus-cloudwatch-exporter on ${var.environment} cluster"
  policy      = data.aws_iam_policy_document.cloudwatch_exporter[0].json

  tags = merge(
    var.common_tags,
    {
      Name = "${var.environment}-cloudwatch-exporter"
    }
  )
}

module "cloudwatch_exporter_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.39"

  count = var.enable_cloudwatch_exporter ? 1 : 0

  role_name = coalesce(var.cloudwatch_exporter_iam_role_name_override, "${var.environment}-cloudwatch-exporter")

  role_policy_arns = {
    cloudwatch_exporter = aws_iam_policy.cloudwatch_exporter[0].arn
  }

  oidc_providers = {
    ex = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["monitoring:monitoring-prometheus-cloudwatch-exporter"]
    }
  }

  depends_on = [
    module.eks,
    aws_iam_policy.cloudwatch_exporter
  ]

  tags = merge(
    var.common_tags,
    {
      Name        = "${var.environment}-cloudwatch-exporter"
      Description = "IRSA role for prometheus-cloudwatch-exporter to scrape CloudWatch metrics"
    }
  )
}

#########################################
#### Monitoring Namespace and Secrets ####
#########################################
# The monitoring namespace moved to the comet-infra umbrella chart (ArgoCD-owned).
# The monitoring Secret is owned by External Secrets Operator (ExternalSecret with
# creationPolicy: Owner) — Terraform no longer creates it. Both are out of this
# module so it never touches the Kubernetes API for monitoring bootstrap.

#########################################
#### Karpenter Prerequisites ####
#########################################

data "aws_caller_identity" "current" {}

# Region consistency guard.
#
# This module no longer declares its own provider "aws" (the caller owns it), so
# the provider's region comes from the wrapper. Several resources below still key
# off var.region as a string — the Karpenter controller IAM policy scopes EC2 ARNs
# to arn:aws:ec2:${var.region}:... and pins an aws:RequestedRegion == var.region
# condition. If the caller's provider region diverges from var.region, Karpenter's
# grants would target the wrong region and deny actions. Fail fast at plan time
# instead. (.region is the aws provider v6 attribute; .name is deprecated.)
data "aws_region" "current" {}

resource "terraform_data" "region_consistency" {
  lifecycle {
    precondition {
      condition     = data.aws_region.current.region == var.region
      error_message = "The AWS provider region (${data.aws_region.current.region}) must match var.region (${var.region}). This module inherits the caller's provider — set the wrapper's provider \"aws\" { region = ... } to the same region you pass as region/eks region, or the Karpenter IAM ARNs and aws:RequestedRegion condition will target the wrong region."
    }
  }
}

# Tag private subnets for Karpenter node discovery
resource "aws_ec2_tag" "karpenter_subnet" {
  for_each    = var.enable_karpenter ? toset(var.eks_private_subnets) : toset([])
  resource_id = each.value
  key         = "karpenter.sh/discovery"
  value       = var.eks_cluster_name
}

# NOTE: the kubernetes.io/cluster/<cluster>=shared PRIVATE-subnet tag is set by the
# comet_vpc module via its authoritative private_subnet_tags map (eks_cluster_name),
# NOT here — a separate aws_ec2_tag fought the VPC module's tag map (tag flap +
# perpetual diff). For an EXTERNAL VPC (enable_vpc=false) the caller must ensure that
# tag exists on the passed-in subnets.

# Tag the node shared security group for Karpenter discovery
resource "aws_ec2_tag" "karpenter_sg" {
  count       = var.enable_karpenter ? 1 : 0
  resource_id = module.eks.node_security_group_id
  key         = "karpenter.sh/discovery"
  value       = var.eks_cluster_name

  depends_on = [module.eks]
}

# SQS queue for spot interruption / rebalance event handling
resource "aws_sqs_queue" "karpenter_interruption" {
  count                     = var.enable_karpenter ? 1 : 0
  name                      = "karpenter-${var.eks_cluster_name}"
  message_retention_seconds = 300
  sqs_managed_sse_enabled   = true

  tags = merge(
    var.common_tags,
    { Name = "karpenter-${var.eks_cluster_name}" }
  )
}

resource "aws_sqs_queue_policy" "karpenter_interruption" {
  count     = var.enable_karpenter ? 1 : 0
  queue_url = aws_sqs_queue.karpenter_interruption[0].url

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = ["events.amazonaws.com", "sqs.amazonaws.com"] }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.karpenter_interruption[0].arn
    }]
  })
}

# EventBridge rules — forward interruption events to the SQS queue
resource "aws_cloudwatch_event_rule" "karpenter_spot_interruption" {
  count       = var.enable_karpenter ? 1 : 0
  name        = "karpenter-spot-interruption-${var.eks_cluster_name}"
  description = "Karpenter spot interruption warning for ${var.eks_cluster_name}"
  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Spot Instance Interruption Warning"]
  })
  tags = merge(var.common_tags, { Name = "karpenter-spot-interruption-${var.eks_cluster_name}" })
}

resource "aws_cloudwatch_event_target" "karpenter_spot_interruption" {
  count = var.enable_karpenter ? 1 : 0
  rule  = aws_cloudwatch_event_rule.karpenter_spot_interruption[0].name
  arn   = aws_sqs_queue.karpenter_interruption[0].arn
}

resource "aws_cloudwatch_event_rule" "karpenter_rebalance" {
  count       = var.enable_karpenter ? 1 : 0
  name        = "karpenter-rebalance-${var.eks_cluster_name}"
  description = "Karpenter rebalance recommendation for ${var.eks_cluster_name}"
  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Instance Rebalance Recommendation"]
  })
  tags = merge(var.common_tags, { Name = "karpenter-rebalance-${var.eks_cluster_name}" })
}

resource "aws_cloudwatch_event_target" "karpenter_rebalance" {
  count = var.enable_karpenter ? 1 : 0
  rule  = aws_cloudwatch_event_rule.karpenter_rebalance[0].name
  arn   = aws_sqs_queue.karpenter_interruption[0].arn
}

resource "aws_cloudwatch_event_rule" "karpenter_instance_state" {
  count       = var.enable_karpenter ? 1 : 0
  name        = "karpenter-instance-state-${var.eks_cluster_name}"
  description = "Karpenter instance state-change notification for ${var.eks_cluster_name}"
  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Instance State-change Notification"]
  })
  tags = merge(var.common_tags, { Name = "karpenter-instance-state-${var.eks_cluster_name}" })
}

resource "aws_cloudwatch_event_target" "karpenter_instance_state" {
  count = var.enable_karpenter ? 1 : 0
  rule  = aws_cloudwatch_event_rule.karpenter_instance_state[0].name
  arn   = aws_sqs_queue.karpenter_interruption[0].arn
}

resource "aws_cloudwatch_event_rule" "karpenter_health_event" {
  count       = var.enable_karpenter ? 1 : 0
  name        = "karpenter-health-${var.eks_cluster_name}"
  description = "Karpenter AWS health event for ${var.eks_cluster_name}"
  event_pattern = jsonencode({
    source      = ["aws.health"]
    detail-type = ["AWS Health Event"]
  })
  tags = merge(var.common_tags, { Name = "karpenter-health-${var.eks_cluster_name}" })
}

resource "aws_cloudwatch_event_target" "karpenter_health_event" {
  count = var.enable_karpenter ? 1 : 0
  rule  = aws_cloudwatch_event_rule.karpenter_health_event[0].name
  arn   = aws_sqs_queue.karpenter_interruption[0].arn
}

# IAM role for nodes provisioned by Karpenter (separate from managed node group role)
resource "aws_iam_role" "karpenter_node" {
  count = var.enable_karpenter ? 1 : 0
  name  = "karpenter-node-${var.eks_cluster_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(var.common_tags, { Name = "karpenter-node-${var.eks_cluster_name}" })
}

resource "aws_iam_role_policy_attachment" "karpenter_node_eks_worker" {
  count      = var.enable_karpenter ? 1 : 0
  role       = aws_iam_role.karpenter_node[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "karpenter_node_cni" {
  count      = var.enable_karpenter ? 1 : 0
  role       = aws_iam_role.karpenter_node[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "karpenter_node_ecr" {
  count      = var.enable_karpenter ? 1 : 0
  role       = aws_iam_role.karpenter_node[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "karpenter_node_ssm" {
  count      = var.enable_karpenter ? 1 : 0
  role       = aws_iam_role.karpenter_node[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Attach the Comet S3 access policy so Karpenter-provisioned nodes can access
# the Comet S3 bucket via the EC2 instance profile (keyID/secretKey = "IAM-ROLE").
resource "aws_iam_role_policy_attachment" "karpenter_node_s3" {
  count      = var.enable_karpenter && var.s3_enabled ? 1 : 0
  role       = aws_iam_role.karpenter_node[0].name
  policy_arn = var.comet_ec2_s3_iam_policy
}

resource "aws_iam_instance_profile" "karpenter_node" {
  count = var.enable_karpenter ? 1 : 0
  name  = "karpenter-node-${var.eks_cluster_name}"
  role  = aws_iam_role.karpenter_node[0].name

  tags = merge(var.common_tags, { Name = "karpenter-node-${var.eks_cluster_name}" })
}

# EKS access entry — lets Karpenter-provisioned nodes join the cluster
resource "aws_eks_access_entry" "karpenter_node" {
  count         = var.enable_karpenter ? 1 : 0
  cluster_name  = module.eks.cluster_name
  principal_arn = aws_iam_role.karpenter_node[0].arn
  type          = "EC2_LINUX"

  tags       = merge(var.common_tags, { Name = "karpenter-node-${var.eks_cluster_name}" })
  depends_on = [module.eks]
}

# IAM policy for the Karpenter controller
data "aws_iam_policy_document" "karpenter_controller" {
  count = var.enable_karpenter ? 1 : 0

  statement {
    sid    = "AllowScopedEC2InstanceAccessActions"
    effect = "Allow"
    resources = [
      "arn:aws:ec2:${var.region}::image/*",
      "arn:aws:ec2:${var.region}::snapshot/*",
      "arn:aws:ec2:${var.region}:*:security-group/*",
      "arn:aws:ec2:${var.region}:*:subnet/*",
    ]
    actions = ["ec2:RunInstances", "ec2:CreateFleet"]
  }

  statement {
    sid       = "AllowScopedEC2LaunchTemplateAccessActions"
    effect    = "Allow"
    resources = ["arn:aws:ec2:${var.region}:*:launch-template/*"]
    actions   = ["ec2:RunInstances", "ec2:CreateFleet"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/kubernetes.io/cluster/${var.eks_cluster_name}"
      values   = ["owned"]
    }
    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/karpenter.sh/nodepool"
      values   = ["*"]
    }
  }

  statement {
    sid    = "AllowScopedEC2InstanceActionsWithTags"
    effect = "Allow"
    resources = [
      "arn:aws:ec2:${var.region}:*:fleet/*",
      "arn:aws:ec2:${var.region}:*:instance/*",
      "arn:aws:ec2:${var.region}:*:volume/*",
      "arn:aws:ec2:${var.region}:*:network-interface/*",
      "arn:aws:ec2:${var.region}:*:launch-template/*",
      "arn:aws:ec2:${var.region}:*:spot-instances-request/*",
    ]
    actions = ["ec2:RunInstances", "ec2:CreateFleet", "ec2:CreateLaunchTemplate"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/kubernetes.io/cluster/${var.eks_cluster_name}"
      values   = ["owned"]
    }
    condition {
      test     = "StringLike"
      variable = "aws:RequestTag/karpenter.sh/nodepool"
      values   = ["*"]
    }
  }

  statement {
    sid    = "AllowScopedResourceCreationTagging"
    effect = "Allow"
    resources = [
      "arn:aws:ec2:${var.region}:*:fleet/*",
      "arn:aws:ec2:${var.region}:*:instance/*",
      "arn:aws:ec2:${var.region}:*:volume/*",
      "arn:aws:ec2:${var.region}:*:network-interface/*",
      "arn:aws:ec2:${var.region}:*:launch-template/*",
      "arn:aws:ec2:${var.region}:*:spot-instances-request/*",
    ]
    actions = ["ec2:CreateTags"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/kubernetes.io/cluster/${var.eks_cluster_name}"
      values   = ["owned"]
    }
    condition {
      test     = "StringEquals"
      variable = "ec2:CreateAction"
      values   = ["RunInstances", "CreateFleet", "CreateLaunchTemplate"]
    }
    condition {
      test     = "StringLike"
      variable = "aws:RequestTag/karpenter.sh/nodepool"
      values   = ["*"]
    }
  }

  statement {
    sid    = "AllowScopedDeletion"
    effect = "Allow"
    resources = [
      "arn:aws:ec2:${var.region}:*:instance/*",
      "arn:aws:ec2:${var.region}:*:launch-template/*",
    ]
    actions = ["ec2:TerminateInstances", "ec2:DeleteLaunchTemplate"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/kubernetes.io/cluster/${var.eks_cluster_name}"
      values   = ["owned"]
    }
    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/karpenter.sh/nodepool"
      values   = ["*"]
    }
  }

  statement {
    sid       = "AllowRegionalReadActions"
    effect    = "Allow"
    resources = ["*"]
    actions = [
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeImages",
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceTypeOfferings",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeLaunchTemplates",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSpotPriceHistory",
      "ec2:DescribeSubnets",
    ]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.region]
    }
  }

  statement {
    sid       = "AllowGlobalReadActions"
    effect    = "Allow"
    resources = ["*"]
    actions = [
      "iam:GetInstanceProfile",
      "pricing:GetProducts",
      "ssm:GetParameter",
      "eks:DescribeCluster",
    ]
  }

  statement {
    sid       = "AllowInterruptionQueueActions"
    effect    = "Allow"
    resources = [aws_sqs_queue.karpenter_interruption[0].arn]
    actions = [
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl",
      "sqs:ReceiveMessage",
    ]
  }

  statement {
    sid       = "AllowPassingInstanceRole"
    effect    = "Allow"
    resources = [aws_iam_role.karpenter_node[0].arn]
    actions   = ["iam:PassRole"]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "karpenter_controller" {
  count = var.enable_karpenter ? 1 : 0

  name        = "karpenter-controller-${var.eks_cluster_name}"
  description = "Karpenter controller permissions for cluster ${var.eks_cluster_name}"
  policy      = data.aws_iam_policy_document.karpenter_controller[0].json

  tags = merge(var.common_tags, { Name = "karpenter-controller-${var.eks_cluster_name}" })
}

# IRSA role for the Karpenter controller pod
module "karpenter_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.39"

  count = var.enable_karpenter ? 1 : 0

  role_name = "${var.environment}-karpenter"

  role_policy_arns = {
    karpenter = aws_iam_policy.karpenter_controller[0].arn
  }

  oidc_providers = {
    ex = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:karpenter"]
    }
  }

  tags = merge(
    var.common_tags,
    {
      Name        = "${var.environment}-karpenter"
      Description = "IRSA role for Karpenter controller"
    }
  )
}

#########################################
#### EKS API ingress — fleet-wide CIDRs ####
#########################################
# These open the EKS cluster_security_group_id (the cluster's primary SG) on
# port 443 to fleet-wide management surfaces. Each ingress source is gated by
# its own toggle; the local map merges all enabled rules into a single
# for_each so the common attributes live in one place.

locals {
  eks_api_ingress_rules = merge(
    var.enable_argocd_management_eks_access ? {
      for cidr in distinct(var.argocd_management_cidrs) :
      "argocd-management-${replace(cidr, "/", "_")}" => {
        cidr        = cidr
        description = "Allow ArgoCD management to reach EKS API from ${cidr}"
        name        = "argocd-management-access-${replace(cidr, "/", "_")}"
      }
    } : {},
    var.enable_vpn_eks_api_access ? {
      "vpn" = {
        cidr        = var.vpn_client_cidr
        description = "Allow VPN clients to reach EKS API"
        name        = "vpn-eks-api-access"
      }
    } : {},
    var.enable_ci_runners_eks_api_access ? {
      "ci-runners" = {
        cidr        = var.ci_runners_cidr
        description = "Allow CI cluster runners to reach EKS API"
        name        = "ci-runners-eks-api-access"
      }
    } : {},
  )
}

resource "aws_vpc_security_group_ingress_rule" "eks_api" {
  for_each = local.eks_api_ingress_rules

  security_group_id = module.eks.cluster_primary_security_group_id
  description       = each.value.description
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = each.value.cidr

  tags = merge(var.common_tags, { Name = each.value.name })
}

#########################################
#### Namespace nodegroup pinning ####
#########################################
# DROPPED. The scheduler.alpha.kubernetes.io/node-selector annotations pinned
# app/admin namespaces onto legacy managed node groups (nodegroup_name=…). Under
# EKS Auto Mode, scheduling is handled by NodePools/NodeClasses (comet-infra), so
# this in-cluster patching is obsolete and has been removed.

#########################################
#### Redis Insights namespace ####
#########################################
# Moved to the agentro-role/rbac local module (comet-devops), which owns agentro's
# in-cluster objects in one place. Not created by this module anymore.
