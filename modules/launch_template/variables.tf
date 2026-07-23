variable "name" {
  description = "Name prefix for Launch Template"
  type        = string
}

variable "ami_id" {
  description = "AMI ID"
  type        = string
}

variable "instance_type" {
  description = "Instance type"
  type        = string
}

variable "key_name" {
  description = "SSH Key pair name"
  type        = string
}

variable "security_group_id" {
  description = "Security Group ID"
  type        = string
}

variable "iam_instance_profile_name" {
  description = "IAM Instance Profile Name"
  type        = string
}

variable "user_data_path" {
  description = "Path to user-data script file"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
