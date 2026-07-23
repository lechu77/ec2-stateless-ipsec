resource "aws_autoscaling_group" "vpn" {
  name_prefix         = "${var.name}-asg-"
  min_size            = var.min_size
  max_size            = var.max_size
  desired_capacity    = var.desired_capacity
  vpc_zone_identifier = var.subnet_ids

  health_check_type         = var.health_check_type
  health_check_grace_period = 300

  target_group_arns = var.target_group_arns

  launch_template {
    id      = var.launch_template_id
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
