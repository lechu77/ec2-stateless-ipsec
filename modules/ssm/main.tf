resource "aws_ssm_parameter" "bootstrap_helpers" {
  name  = "/vpn-gateway/bootstrap/helpers"
  type  = "SecureString"
  value = file("${var.ssm_dir}/bootstrap-helpers.sh")

  tags = merge(var.tags, {
    Name = "/vpn-gateway/bootstrap/helpers"
  })
}

resource "aws_ssm_parameter" "bootstrap_vars" {
  name  = "/vpn-gateway/bootstrap/vars"
  type  = "SecureString"
  value = file("${var.ssm_dir}/bootstrap-vars.sh")

  tags = merge(var.tags, {
    Name = "/vpn-gateway/bootstrap/vars"
  })
}

resource "aws_ssm_parameter" "bootstrap_config" {
  count = fileexists("${var.ssm_dir}/bootstrap-config.json") ? 1 : 0

  name  = "/vpn-gateway/bootstrap/config"
  type  = "SecureString"
  value = file("${var.ssm_dir}/bootstrap-config.json")

  tags = merge(var.tags, {
    Name = "/vpn-gateway/bootstrap/config"
  })
}

resource "aws_ssm_parameter" "ipsec_config" {
  count = fileexists("${var.ssm_dir}/ipsec.conf") ? 1 : 0

  name  = "/vpn-gateway/ipsec/ipsec.conf"
  type  = "SecureString"
  value = file("${var.ssm_dir}/ipsec.conf")

  tags = merge(var.tags, {
    Name = "/vpn-gateway/ipsec/ipsec.conf"
  })
}

resource "aws_ssm_parameter" "ipsec_psk" {
  count = fileexists("${var.ssm_dir}/psk") ? 1 : 0

  name  = "/vpn-gateway/ipsec/psk"
  type  = "SecureString"
  value = file("${var.ssm_dir}/psk")

  tags = merge(var.tags, {
    Name = "/vpn-gateway/ipsec/psk"
  })
}

resource "aws_ssm_parameter" "vhost_config" {
  count = fileexists("${var.ssm_dir}/vhost.conf") ? 1 : 0

  name  = "/vpn-gateway/httpd/vhost.conf"
  type  = "SecureString"
  value = file("${var.ssm_dir}/vhost.conf")

  tags = merge(var.tags, {
    Name = "/vpn-gateway/httpd/vhost.conf"
  })
}

resource "aws_ssm_parameter" "remote_gateway" {
  count = fileexists("${var.ssm_dir}/remote-gateway") ? 1 : 0

  name  = "/vpn-gateway/ipsec/remote-gateway"
  type  = "SecureString"
  value = file("${var.ssm_dir}/remote-gateway")

  tags = merge(var.tags, {
    Name = "/vpn-gateway/ipsec/remote-gateway"
  })
}

resource "aws_ssm_parameter" "remote_hosts" {
  count = fileexists("${var.ssm_dir}/remote-hosts") ? 1 : 0

  name  = "/vpn-gateway/ipsec/remote-hosts"
  type  = "SecureString"
  value = file("${var.ssm_dir}/remote-hosts")

  tags = merge(var.tags, {
    Name = "/vpn-gateway/ipsec/remote-hosts"
  })
}
