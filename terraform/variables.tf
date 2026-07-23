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

variable "vpc_id" {
  description = "VPC ID where the target group / load balancer will be deployed"
  type        = string
  default     = ""
}

variable "subnet_id" {
  description = "Primary subnet ID where resources will be deployed"
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "List of public subnet IDs across multiple AZs for ASG and NLB"
  type        = list(string)
  default     = []
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
  description = "IAM instance profile / role name for the EC2 instance"
  type        = string
  default     = "EC2-VPN-Gateway-Role"
}

variable "instance_name" {
  description = "Name tag for the EC2 instance and Launch Template"
  type        = string
  default     = "VPN-Gateway-Instance"
}

# ---------------------------------------------------------------------------
# Auto Scaling Group Configuration
# ---------------------------------------------------------------------------

variable "asg_min_size" {
  description = "Minimum capacity for the Auto Scaling Group"
  type        = number
  default     = 1
}

variable "asg_max_size" {
  description = "Maximum capacity for the Auto Scaling Group"
  type        = number
  default     = 1
}

variable "asg_desired_capacity" {
  description = "Desired capacity for the Auto Scaling Group"
  type        = number
  default     = 1
}

# ---------------------------------------------------------------------------
# Load Balancer Integration
# ---------------------------------------------------------------------------

variable "create_load_balancer" {
  description = "Set to true to create a new Network Load Balancer (NLB) and Target Group"
  type        = bool
  default     = true
}

variable "existing_target_group_arn" {
  description = "ARN of an existing Target Group if create_load_balancer is false"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}
