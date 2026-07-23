output "bootstrap_helpers_arn" {
  description = "ARN of bootstrap helpers SSM parameter"
  value       = aws_ssm_parameter.bootstrap_helpers.arn
}

output "bootstrap_vars_arn" {
  description = "ARN of bootstrap vars SSM parameter"
  value       = aws_ssm_parameter.bootstrap_vars.arn
}

output "bootstrap_config_arn" {
  description = "ARN of bootstrap config SSM parameter"
  value       = length(aws_ssm_parameter.bootstrap_config) > 0 ? aws_ssm_parameter.bootstrap_config[0].arn : ""
}
