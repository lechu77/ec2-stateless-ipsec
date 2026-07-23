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
# EC2 Launch Template (Stateless Auto-Healing Instance Spec)
# ---------------------------------------------------------------------------

resource "aws_launch_template" "vpn" {
  name_prefix   = "${var.instance_name}-lt-"
  image_id      = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name

  user_data = filebase64("${path.module}/../user-data.sh")

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_vpn_instance_profile.name
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [var.security_group_id]
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = 8
      volume_type           = "gp3"
      iops                  = 3000
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(var.tags, {
      Name = var.instance_name
    })
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(var.tags, {
      Name = "${var.instance_name}-root-volume"
    })
  }

  tags = merge(var.tags, {
    Name = "${var.instance_name}-lt"
  })

  depends_on = [
    aws_ssm_parameter.bootstrap_helpers,
    aws_ssm_parameter.bootstrap_vars,
  ]
}

# ---------------------------------------------------------------------------
# Auto Scaling Group (Stateless Auto-Healing & Target Group Attachment)
# ---------------------------------------------------------------------------

resource "aws_autoscaling_group" "vpn" {
  name_prefix         = "${var.instance_name}-asg-"
  min_size            = var.asg_min_size
  max_size            = var.asg_max_size
  desired_capacity    = var.asg_desired_capacity
  vpc_zone_identifier = length(var.subnet_ids) > 0 ? var.subnet_ids : [var.subnet_id]

  health_check_type         = var.create_load_balancer || var.existing_target_group_arn != "" ? "ELB" : "EC2"
  health_check_grace_period = 300

  target_group_arns = compact([
    var.create_load_balancer ? aws_lb_target_group.vpn[0].arn : "",
    var.existing_target_group_arn
  ])

  launch_template {
    id      = aws_launch_template.vpn.id
    version = "$Latest"
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 0
    }
    triggers = ["tag"]
  }

  lifecycle {
    create_before_destroy = true
  }
}
