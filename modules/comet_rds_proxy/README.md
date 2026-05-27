## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | n/a |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_db_proxy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_proxy) | resource |
| [aws_db_proxy_default_target_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_proxy_default_target_group) | resource |
| [aws_db_proxy_target.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_proxy_target) | resource |
| [aws_iam_role.proxy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.proxy_read_secret](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_secretsmanager_secret.proxy_auth](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret_version.proxy_auth](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [aws_security_group.proxy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_vpc_security_group_egress_rule.proxy_aws_api](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_egress_rule.proxy_to_mysql](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.mysql_from_proxy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.proxy_from_caller](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_allowed_sg_ids"></a> [allowed\_sg\_ids](#input\_allowed\_sg\_ids) | Security group IDs allowed to connect to the proxy on the MySQL port (typically the EKS nodegroup SG) | `list(string)` | `[]` | no |
| <a name="input_common_tags"></a> [common\_tags](#input\_common\_tags) | Tags applied to all resources | `map(string)` | `{}` | no |
| <a name="input_connection_borrow_timeout"></a> [connection\_borrow\_timeout](#input\_connection\_borrow\_timeout) | Seconds a client request waits for an available connection from the pool before failing | `number` | `120` | no |
| <a name="input_debug_logging"></a> [debug\_logging](#input\_debug\_logging) | Enable proxy debug logging (verbose; useful when troubleshooting connection issues, otherwise off) | `bool` | `false` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Deployment environment, i.e. dev/stage/prod, etc | `string` | n/a | yes |
| <a name="input_idle_client_timeout"></a> [idle\_client\_timeout](#input\_idle\_client\_timeout) | Seconds a client connection can be idle before the proxy closes it | `number` | `1800` | no |
| <a name="input_max_connections_percent"></a> [max\_connections\_percent](#input\_max\_connections\_percent) | Maximum percentage of the cluster's max\_connections the proxy will open. Defaults match AWS guidance for Aurora MySQL. | `number` | `100` | no |
| <a name="input_max_idle_connections_percent"></a> [max\_idle\_connections\_percent](#input\_max\_idle\_connections\_percent) | Maximum percentage of idle connections the proxy will keep warm | `number` | `50` | no |
| <a name="input_mysql_cluster_id"></a> [mysql\_cluster\_id](#input\_mysql\_cluster\_id) | Aurora MySQL cluster identifier the proxy targets | `string` | n/a | yes |
| <a name="input_mysql_master_password"></a> [mysql\_master\_password](#input\_mysql\_master\_password) | MySQL master password (written to the proxy auth secret) | `string` | n/a | yes |
| <a name="input_mysql_master_username"></a> [mysql\_master\_username](#input\_mysql\_master\_username) | MySQL master username (written to the proxy auth secret) | `string` | n/a | yes |
| <a name="input_mysql_sg_id"></a> [mysql\_sg\_id](#input\_mysql\_sg\_id) | Security group ID of the MySQL cluster — the module adds an ingress rule to allow the proxy SG to reach it | `string` | n/a | yes |
| <a name="input_require_tls"></a> [require\_tls](#input\_require\_tls) | Require TLS for client connections to the proxy. Recommended ON when `rds_require_secure_transport` is true at the cluster. | `bool` | `true` | no |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | Subnet IDs the proxy ENIs are placed in (private subnets of the VPC, matching the RDS cluster) | `list(string)` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | ID of the VPC the proxy ENIs live in | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_proxy_arn"></a> [proxy\_arn](#output\_proxy\_arn) | ARN of the RDS Proxy |
| <a name="output_proxy_auth_secret_arn"></a> [proxy\_auth\_secret\_arn](#output\_proxy\_auth\_secret\_arn) | ARN of the Secrets Manager secret holding proxy auth credentials |
| <a name="output_proxy_endpoint"></a> [proxy\_endpoint](#output\_proxy\_endpoint) | Writer endpoint of the RDS Proxy — clients connect here instead of the cluster endpoint |
| <a name="output_proxy_sg_id"></a> [proxy\_sg\_id](#output\_proxy\_sg\_id) | Security group ID of the proxy ENIs |
