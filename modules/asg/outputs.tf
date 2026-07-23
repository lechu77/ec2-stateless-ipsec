output "id" {
  description = "ID of the Auto Scaling Group"
  value       = aws_autoscaling_group.vpn.id
}

output "name" {
  description = "Name of the Auto Scaling Group"
  value       = aws_autoscaling_group.vpn.name
}

output "arn" {
  description = "ARN of the Auto Scaling Group"
  value       = aws_autoscaling_group.vpn.arn
}
