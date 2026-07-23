variable "name" {
  description = "Name prefix for ASG"
  type        = string
}

variable "launch_template_id" {
  description = "ID of the Launch Template"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for the ASG"
  type        = list(string)
}

variable "target_group_arns" {
  description = "List of target group ARNs to attach to the ASG"
  type        = list(string)
  default     = []
}

variable "min_size" {
  description = "Minimum size"
  type        = number
  default     = 1
}

variable "max_size" {
  description = "Maximum size"
  type        = number
  default     = 1
}

variable "desired_capacity" {
  description = "Desired capacity"
  type        = number
  default     = 1
}

variable "health_check_type" {
  description = "Health check type (ELB or EC2)"
  type        = string
  default     = "EC2"
}
