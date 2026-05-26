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
| <a name="input_enable_tgw_prep"></a> [enable\_tgw\_prep](#input\_enable\_tgw\_prep) | Tag private subnets with `tgw_connect=true` so a future TGW attachment can target them. The attachment itself is created separately. | `bool` | `false` | no |
| <a name="input_enable_vpc_flow_logs"></a> [enable\_vpc\_flow\_logs](#input\_enable\_vpc\_flow\_logs) | Enable VPC Flow Logs to CloudWatch (creates the IAM role and log group when true) | `bool` | `false` | no |
| <a name="input_enable_vpc_interface_endpoints"></a> [enable\_vpc\_interface\_endpoints](#input\_enable\_vpc\_interface\_endpoints) | Provision interface VPC endpoints for AWS-managed services so workloads can reach them without NAT/Internet egress. Required when flipping EKS API / RDS / ElastiCache endpoints private-only. | `bool` | `false` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Deployment environment, i.e. dev/stage/prod, etc | `string` | n/a | yes |
| <a name="input_private_subnet_tags"></a> [private\_subnet\_tags](#input\_private\_subnet\_tags) | A map of tags for private subnets | `map(string)` | `{}` | no |
| <a name="input_public_subnet_tags"></a> [public\_subnet\_tags](#input\_public\_subnet\_tags) | A map of tags for public subnets | `map(string)` | `{}` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region to provision resources in | `string` | n/a | yes |
| <a name="input_single_nat_gateway"></a> [single\_nat\_gateway](#input\_single\_nat\_gateway) | Controls whether single NAT gateway used for all public subnets | `bool` | n/a | yes |
| <a name="input_vpc_cidr"></a> [vpc\_cidr](#input\_vpc\_cidr) | CIDR block for the VPC (must be a valid RFC1918 private range) | `string` | `"10.0.0.0/16"` | no |
| <a name="input_vpc_interface_endpoints_allowed_cidrs"></a> [vpc\_interface\_endpoints\_allowed\_cidrs](#input\_vpc\_interface\_endpoints\_allowed\_cidrs) | Additional CIDR blocks allowed to reach interface VPC endpoints on 443 (in addition to the VPC's own CIDR). Defaults to the agentro management surface: 10.162.0.0/16 (ArgoCD mgmt VPC) + 10.126.0.0/15 (VPN client pool). Set to `[]` to allow only in-VPC traffic. | `list(string)` | <pre>["10.162.0.0/16",<br>"10.126.0.0/15"]</pre> | no |
| <a name="input_vpc_interface_endpoints_services"></a> [vpc\_interface\_endpoints\_services](#input\_vpc\_interface\_endpoints\_services) | Override list of interface endpoint service short-names (without the `com.amazonaws.<region>.` prefix). When empty, defaults to: ecr.api, ecr.dkr, sts, ec2, ec2messages, ssm, ssmmessages, secretsmanager, logs, monitoring, eks. | `list(string)` | `[]` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_azs"></a> [azs](#output\_azs) | List of availability zones in the region |
| <a name="output_private_subnets"></a> [private\_subnets](#output\_private\_subnets) | List of IDs for private subnets provisioned in the VPC |
| <a name="output_public_subnets"></a> [public\_subnets](#output\_public\_subnets) | List of IDs for public subnets provisioned in the VPC |
| <a name="output_vpc_id"></a> [vpc\_id](#output\_vpc\_id) | ID of the provisioned VPC |
