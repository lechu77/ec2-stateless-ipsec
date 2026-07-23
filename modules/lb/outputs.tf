output "lb_arn" {
  description = "ARN of the Network Load Balancer"
  value       = aws_lb.vpn.arn
}

output "dns_name" {
  description = "DNS name of the Network Load Balancer"
  value       = aws_lb.vpn.dns_name
}

output "target_group_arn" {
  description = "ARN of the Target Group"
  value       = aws_lb_target_group.vpn.arn
}
