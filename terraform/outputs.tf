output "launch_template_id" {
  description = "ID of the EC2 Launch Template"
  value       = aws_launch_template.vpn.id
}

output "launch_template_latest_version" {
  description = "Latest version of the EC2 Launch Template"
  value       = aws_launch_template.vpn.latest_version
}

output "autoscaling_group_id" {
  description = "ID of the Auto Scaling Group"
  value       = aws_autoscaling_group.vpn.id
}

output "autoscaling_group_name" {
  description = "Name of the Auto Scaling Group"
  value       = aws_autoscaling_group.vpn.name
}

output "nlb_dns_name" {
  description = "DNS name of the Network Load Balancer (if created)"
  value       = var.create_load_balancer ? aws_lb.vpn[0].dns_name : "N/A (using existing or no NLB)"
}

output "target_group_arn" {
  description = "ARN of the Target Group attached to the ASG"
  value       = var.create_load_balancer ? aws_lb_target_group.vpn[0].arn : var.existing_target_group_arn
}

output "iam_role_arn" {
  description = "ARN of the IAM role attached to the instances"
  value       = aws_iam_role.ec2_vpn_role.arn
}

output "iam_instance_profile_name" {
  description = "Name of the IAM instance profile"
  value       = aws_iam_instance_profile.ec2_vpn_instance_profile.name
}
