variable "name" {
  description = "Name prefix for NLB resources"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the target group will be created"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for the NLB"
  type        = list(string)
}

variable "tags" {
  description = "Tags to apply to LB resources"
  type        = map(string)
  default     = {}
}
