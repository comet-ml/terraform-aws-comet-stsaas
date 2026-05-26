## Requirements

No requirements.

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | n/a |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_vpc"></a> [vpc](#module\_vpc) | terraform-aws-modules/vpc/aws | ~> 5.0.0 |

## Resources

| Name | Type |
|------|------|
| [aws_ec2_transit_gateway_vpc_attachment.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ec2_transit_gateway_vpc_attachment) | resource |
| [aws_route.tgw](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_security_group.vpc_interface_endpoints](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_vpc_endpoint.interface](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |
| [aws_vpc_endpoint.s3](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |
| [aws_vpc_security_group_ingress_rule.vpc_interface_endpoints_https](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_availability_zones.available](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/availability_zones) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_common_tags"></a> [common\_tags](#input\_common\_tags) | A map of common tags | `map(string)` | `{}` | no |
| <a name="input_eks_enabled"></a> [eks\_enabled](#input\_eks\_enabled) | Indicates if EKS module enabled | `bool` | n/a | yes |
| <a name="input_enable_s3_endpoint"></a> [enable\_s3\_endpoint](#input\_enable\_s3\_endpoint) | Provision the S3 gateway VPC endpoint attached to all route tables | `bool` | `true` | no |
| <a name="input_enable_tgw_attachment"></a> [enable\_tgw\_attachment](#input\_enable\_tgw\_attachment) | Attach this VPC to a pre-existing Transit Gateway (whose ID must be passed via `tgw_id`). Adds routes on every private route table for the destinations in `tgw_propagated_cidrs`. | `bool` | `false` | no |
| <a name="input_enable_tgw_prep"></a> [enable\_tgw\_prep](#input\_enable\_tgw\_prep) | Tag private subnets with `tgw_connect=true` so a future TGW attachment can target them. The attachment itself is created separately. | `bool` | `false` | no |
| <a name="input_enable_vpc_flow_logs"></a> [enable\_vpc\_flow\_logs](#input\_enable\_vpc\_flow\_logs) | Enable VPC Flow Logs to CloudWatch (creates the IAM role and log group when true) | `bool` | `false` | no |
| <a name="input_enable_vpc_interface_endpoints"></a> [enable\_vpc\_interface\_endpoints](#input\_enable\_vpc\_interface\_endpoints) | Provision interface VPC endpoints for AWS-managed services so workloads can reach them without NAT/Internet egress. Required when flipping EKS API / RDS / ElastiCache endpoints private-only. | `bool` | `false` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Deployment environment, i.e. dev/stage/prod, etc | `string` | n/a | yes |
| <a name="input_private_subnet_tags"></a> [private\_subnet\_tags](#input\_private\_subnet\_tags) | A map of tags for private subnets | `map(string)` | `{}` | no |
| <a name="input_public_subnet_tags"></a> [public\_subnet\_tags](#input\_public\_subnet\_tags) | A map of tags for public subnets | `map(string)` | `{}` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region to provision resources in | `string` | n/a | yes |
| <a name="input_single_nat_gateway"></a> [single\_nat\_gateway](#input\_single\_nat\_gateway) | Controls whether single NAT gateway used for all public subnets | `bool` | n/a | yes |
| <a name="input_tgw_attachment_appliance_mode_support"></a> [tgw\_attachment\_appliance\_mode\_support](#input\_tgw\_attachment\_appliance\_mode\_support) | Whether the TGW attachment maintains traffic-flow affinity through stateful appliances. Accepts 'enable' or 'disable'. | `string` | `"disable"` | no |
| <a name="input_tgw_attachment_default_route_table_association"></a> [tgw\_attachment\_default\_route\_table\_association](#input\_tgw\_attachment\_default\_route\_table\_association) | Associate the attachment with the TGW's default route table. Set false when the TGW uses custom route tables and another account manages the association. | `bool` | `true` | no |
| <a name="input_tgw_attachment_default_route_table_propagation"></a> [tgw\_attachment\_default\_route\_table\_propagation](#input\_tgw\_attachment\_default\_route\_table\_propagation) | Propagate this VPC's CIDR to the TGW's default route table. Set false when propagation is managed by the TGW owner account. | `bool` | `true` | no |
| <a name="input_tgw_attachment_dns_support"></a> [tgw\_attachment\_dns\_support](#input\_tgw\_attachment\_dns\_support) | Whether the TGW attachment resolves DNS hostnames to private addresses across attachments. Accepts 'enable' or 'disable'. | `string` | `"enable"` | no |
| <a name="input_tgw_id"></a> [tgw\_id](#input\_tgw\_id) | ID of the pre-existing (and, if cross-account, RAM-shared) Transit Gateway to attach the VPC to. Required when `enable_tgw_attachment` is true. | `string` | `null` | no |
| <a name="input_tgw_propagated_cidrs"></a> [tgw\_propagated\_cidrs](#input\_tgw\_propagated\_cidrs) | Destination CIDRs to route via the TGW attachment from every private route table. Defaults to the agentro management surface (VPN client pool + ArgoCD mgmt VPC). | `list(string)` | <pre>["10.126.0.0/15",<br>"10.162.0.0/16"]</pre> | no |
| <a name="input_vpc_cidr"></a> [vpc\_cidr](#input\_vpc\_cidr) | CIDR block for the VPC (must be a valid RFC1918 private range) | `string` | `"10.0.0.0/16"` | no |
| <a name="input_vpc_interface_endpoints_allowed_cidrs"></a> [vpc\_interface\_endpoints\_allowed\_cidrs](#input\_vpc\_interface\_endpoints\_allowed\_cidrs) | Additional CIDR blocks allowed to reach interface VPC endpoints on 443 (in addition to the VPC's own CIDR). Defaults to the agentro management surface: 10.162.0.0/16 (ArgoCD mgmt VPC) + 10.126.0.0/15 (VPN client pool). Set to `[]` to allow only in-VPC traffic. | `list(string)` | <pre>["10.162.0.0/16",<br>"10.126.0.0/15"]</pre> | no |
| <a name="input_vpc_interface_endpoints_services"></a> [vpc\_interface\_endpoints\_services](#input\_vpc\_interface\_endpoints\_services) | Override list of interface endpoint service short-names (without the `com.amazonaws.<region>.` prefix). When empty, defaults to: ecr.api, ecr.dkr, sts, ec2, ec2messages, ssm, ssmmessages, sqs, secretsmanager, logs, monitoring, eks. `sqs` covers Karpenter spot-interruption queues. | `list(string)` | `[]` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_azs"></a> [azs](#output\_azs) | List of availability zones in the region |
| <a name="output_private_subnets"></a> [private\_subnets](#output\_private\_subnets) | List of IDs for private subnets provisioned in the VPC |
| <a name="output_public_subnets"></a> [public\_subnets](#output\_public\_subnets) | List of IDs for public subnets provisioned in the VPC |
| <a name="output_vpc_id"></a> [vpc\_id](#output\_vpc\_id) | ID of the provisioned VPC |
