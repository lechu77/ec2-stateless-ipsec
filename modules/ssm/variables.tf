variable "ssm_dir" {
  description = "Path to directory containing SSM parameter source files"
  type        = string
}

variable "tags" {
  description = "Tags to apply to SSM resources"
  type        = map(string)
  default     = {}
}
