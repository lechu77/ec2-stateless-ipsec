variable "iam_instance_profile" {
  description = "IAM instance profile and role name"
  type        = string
  default     = "EC2-VPN-Gateway-Role"
}

variable "tags" {
  description = "Tags to apply to IAM resources"
  type        = map(string)
  default     = {}
}
