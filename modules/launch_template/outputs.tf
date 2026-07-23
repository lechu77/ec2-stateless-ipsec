output "id" {
  description = "ID of the Launch Template"
  value       = aws_launch_template.vpn.id
}

output "latest_version" {
  description = "Latest version of the Launch Template"
  value       = aws_launch_template.vpn.latest_version
}

output "arn" {
  description = "ARN of the Launch Template"
  value       = aws_launch_template.vpn.arn
}
