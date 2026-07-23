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

# ---------------------------------------------------------------------------
# Modularized Infrastructure Components
# ---------------------------------------------------------------------------

module "iam" {
  source               = "../modules/iam"
  iam_instance_profile = var.iam_instance_profile
  tags                 = var.tags
}

module "ssm" {
  source  = "../modules/ssm"
  ssm_dir = "${path.module}/../ssm"
  tags    = var.tags
}

module "lb" {
  count      = var.create_load_balancer ? 1 : 0
  source     = "../modules/lb"
  name       = var.instance_name
  vpc_id     = var.vpc_id
  subnet_ids = length(var.subnet_ids) > 0 ? var.subnet_ids : [var.subnet_id]
  tags       = var.tags
}

module "launch_template" {
  source                    = "../modules/launch_template"
  name                      = var.instance_name
  ami_id                    = var.ami_id
  instance_type             = var.instance_type
  key_name                  = var.key_name
  security_group_id         = var.security_group_id
  iam_instance_profile_name = module.iam.instance_profile_name
  user_data_path            = "${path.module}/../user-data.sh"
  tags                      = var.tags

  depends_on = [module.ssm]
}

module "asg" {
  source             = "../modules/asg"
  name               = var.instance_name
  launch_template_id = module.launch_template.id
  subnet_ids         = length(var.subnet_ids) > 0 ? var.subnet_ids : [var.subnet_id]
  target_group_arns  = compact([
    var.create_load_balancer ? module.lb[0].target_group_arn : "",
    var.existing_target_group_arn
  ])
  min_size          = var.asg_min_size
  max_size          = var.asg_max_size
  desired_capacity  = var.asg_desired_capacity
  health_check_type = var.create_load_balancer || var.existing_target_group_arn != "" ? "ELB" : "EC2"
}
