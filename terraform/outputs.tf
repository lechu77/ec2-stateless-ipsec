output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.vpn.id
}

output "instance_private_ip" {
  description = "Primary private IP address assigned by DHCP"
  value       = aws_instance.vpn.private_ip
}

output "instance_arn" {
  description = "EC2 instance ARN"
  value       = aws_instance.vpn.arn
}

output "iam_role_arn" {
  description = "ARN of the IAM role attached to the instance"
  value       = aws_iam_role.ec2_vpn_role.arn
}

output "iam_instance_profile_name" {
  description = "Name of the IAM instance profile"
  value       = aws_iam_instance_profile.ec2_vpn_instance_profile.name
}

