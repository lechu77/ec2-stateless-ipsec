variable "region" {
  description = "AWS region where resources will be deployed"
  type        = string
  default     = "us-east-1"
}

variable "ami_id" {
  description = "Amazon Linux 2023 ARM64 AMI ID"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type (ARM64-based)"
  type        = string
  default     = "t4g.micro"
}

variable "subnet_id" {
  description = "Subnet ID where the instance will be deployed (must be public)"
  type        = string
}

variable "security_group_id" {
  description = "Security group ID to attach to the instance"
  type        = string
}

variable "key_name" {
  description = "EC2 key pair name for SSH access"
  type        = string
}

variable "iam_instance_profile" {
  description = "IAM instance profile name (must have SSM/EC2 permissions)"
  type        = string
}

variable "instance_name" {
  description = "Name tag for the EC2 instance"
  type        = string
  default     = "VPN-Gateway-Instance"
}

variable "tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}
