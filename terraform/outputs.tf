output "launch_template_id" {
  description = "ID of the EC2 Launch Template"
  value       = module.launch_template.id
}

output "launch_template_latest_version" {
  description = "Latest version of the EC2 Launch Template"
  value       = module.launch_template.latest_version
}

output "autoscaling_group_id" {
  description = "ID of the Auto Scaling Group"
  value       = module.asg.id
}

output "autoscaling_group_name" {
  description = "Name of the Auto Scaling Group"
  value       = module.asg.name
}

output "nlb_dns_name" {
  description = "DNS name of the Network Load Balancer (if created)"
  value       = var.create_load_balancer ? module.lb[0].dns_name : "N/A (using existing or no NLB)"
}

output "target_group_arn" {
  description = "ARN of the Target Group attached to the ASG"
  value       = var.create_load_balancer ? module.lb[0].target_group_arn : var.existing_target_group_arn
}

output "iam_role_arn" {
  description = "ARN of the IAM role attached to the instances"
  value       = module.iam.role_arn
}

output "iam_instance_profile_name" {
  description = "Name of the IAM instance profile"
  value       = module.iam.instance_profile_name
}
