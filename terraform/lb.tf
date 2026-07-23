# ---------------------------------------------------------------------------
# Network Load Balancer (NLB) & Target Group Resources
# Created when var.create_load_balancer = true
# ---------------------------------------------------------------------------

resource "aws_lb" "vpn" {
  count = var.create_load_balancer ? 1 : 0

  name               = "${var.instance_name}-nlb"
  internal           = false
  load_balancer_type = "network"
  subnets            = length(var.subnet_ids) > 0 ? var.subnet_ids : [var.subnet_id]

  enable_cross_zone_load_balancing = true

  tags = merge(var.tags, {
    Name = "${var.instance_name}-nlb"
  })
}

resource "aws_lb_target_group" "vpn" {
  count = var.create_load_balancer ? 1 : 0

  name        = "${var.instance_name}-tg"
  port        = 80
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    enabled             = true
    protocol            = "HTTP"
    port                = "80"
    path                = "/healthCheck.php"
    interval            = 10
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = merge(var.tags, {
    Name = "${var.instance_name}-tg"
  })
}

resource "aws_lb_listener" "vpn" {
  count = var.create_load_balancer ? 1 : 0

  load_balancer_arn = aws_lb.vpn[0].arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.vpn[0].arn
  }
}
