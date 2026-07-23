terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

resource "aws_instance" "vpn" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [var.security_group_id]
  key_name               = var.key_name
  iam_instance_profile   = var.iam_instance_profile

  depends_on = [
    aws_ssm_parameter.bootstrap_helpers,
    aws_ssm_parameter.bootstrap_vars,
    aws_ssm_parameter.bootstrap_config,
  ]

  # user-data is uploaded as a file to avoid the 16 KB console paste limit.
  # Always use: terraform apply (destroy + create) to replace the instance.
  user_data = file("${path.module}/../user-data.sh")

  # Replace instance when user-data changes
  user_data_replace_on_change = true

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 8
    iops                  = 3000
    delete_on_termination = true
  }

  tags = merge(var.tags, {
    Name = var.instance_name
  })
}
