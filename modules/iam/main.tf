resource "aws_iam_role" "ec2_vpn_role" {
  name = var.iam_instance_profile

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name = var.iam_instance_profile
  })
}

resource "aws_iam_policy" "ec2_vpn_policy" {
  name        = "${var.iam_instance_profile}-policy"
  description = "IAM Policy for EC2 Stateless IPsec instance (SSM, EC2 EIP, CodeCommit)"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SSMParameterAccess"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParameterHistory",
          "ssm:GetParametersByPath"
        ]
        Resource = [
          "arn:aws:ssm:*:*:parameter/vpn-gateway/*"
        ]
      },
      {
        Sid      = "KMSDecryptAccess"
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = "*"
      },
      {
        Sid    = "EC2NetworkingAccess"
        Effect = "Allow"
        Action = [
          "ec2:DescribeAddresses",
          "ec2:DescribeNetworkInterfaces",
          "ec2:AssignPrivateIpAddresses",
          "ec2:AssociateAddress"
        ]
        Resource = "*"
      },
      {
        Sid    = "CodeCommitGitPullAccess"
        Effect = "Allow"
        Action = [
          "codecommit:GitPull",
          "codecommit:BatchGet*",
          "codecommit:BatchGetRepositories",
          "codecommit:Get*",
          "codecommit:GetObject",
          "codecommit:GetRepository"
        ]
        Resource = [
          "arn:aws:codecommit:*:*:webservice",
          "arn:aws:codecommit:*:*:plataforma"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "custom_policy_attachment" {
  role       = aws_iam_role.ec2_vpn_role.name
  policy_arn = aws_iam_policy.ec2_vpn_policy.arn
}

resource "aws_iam_role_policy_attachment" "ssm_managed_core" {
  role       = aws_iam_role.ec2_vpn_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_vpn_instance_profile" {
  name = var.iam_instance_profile
  role = aws_iam_role.ec2_vpn_role.name
}
