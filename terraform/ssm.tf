# ---------------------------------------------------------------------------
# SSM Parameter Store Resources
# ---------------------------------------------------------------------------

resource "aws_ssm_parameter" "bootstrap_helpers" {
  name  = "/vpn-gateway/bootstrap/helpers"
  type  = "SecureString"
  value = file("${path.module}/../ssm/bootstrap-helpers.sh")

  tags = merge(var.tags, {
    Name = "/vpn-gateway/bootstrap/helpers"
  })
}

resource "aws_ssm_parameter" "bootstrap_vars" {
  name  = "/vpn-gateway/bootstrap/vars"
  type  = "SecureString"
  value = file("${path.module}/../ssm/bootstrap-vars.sh")

  tags = merge(var.tags, {
    Name = "/vpn-gateway/bootstrap/vars"
  })
}

resource "aws_ssm_parameter" "bootstrap_config" {
  count = fileexists("${path.module}/../ssm/bootstrap-config.json") ? 1 : 0

  name  = "/vpn-gateway/bootstrap/config"
  type  = "SecureString"
  value = file("${path.module}/../ssm/bootstrap-config.json")

  tags = merge(var.tags, {
    Name = "/vpn-gateway/bootstrap/config"
  })
}

resource "aws_ssm_parameter" "ipsec_config" {
  count = fileexists("${path.module}/../ssm/ipsec.conf") ? 1 : 0

  name  = "/vpn-gateway/ipsec/ipsec.conf"
  type  = "SecureString"
  value = file("${path.module}/../ssm/ipsec.conf")

  tags = merge(var.tags, {
    Name = "/vpn-gateway/ipsec/ipsec.conf"
  })
}

resource "aws_ssm_parameter" "ipsec_psk" {
  count = fileexists("${path.module}/../ssm/psk") ? 1 : 0

  name  = "/vpn-gateway/ipsec/psk"
  type  = "SecureString"
  value = file("${path.module}/../ssm/psk")

  tags = merge(var.tags, {
    Name = "/vpn-gateway/ipsec/psk"
  })
}

resource "aws_ssm_parameter" "vhost_config" {
  count = fileexists("${path.module}/../ssm/vhost.conf") ? 1 : 0

  name  = "/vpn-gateway/httpd/vhost.conf"
  type  = "SecureString"
  value = file("${path.module}/../ssm/vhost.conf")

  tags = merge(var.tags, {
    Name = "/vpn-gateway/httpd/vhost.conf"
  })
}

resource "aws_ssm_parameter" "remote_gateway" {
  count = fileexists("${path.module}/../ssm/remote-gateway") ? 1 : 0

  name  = "/vpn-gateway/ipsec/remote-gateway"
  type  = "SecureString"
  value = file("${path.module}/../ssm/remote-gateway")

  tags = merge(var.tags, {
    Name = "/vpn-gateway/ipsec/remote-gateway"
  })
}

resource "aws_ssm_parameter" "remote_hosts" {
  count = fileexists("${path.module}/../ssm/remote-hosts") ? 1 : 0

  name  = "/vpn-gateway/ipsec/remote-hosts"
  type  = "SecureString"
  value = file("${path.module}/../ssm/remote-hosts")

  tags = merge(var.tags, {
    Name = "/vpn-gateway/ipsec/remote-hosts"
  })
}
