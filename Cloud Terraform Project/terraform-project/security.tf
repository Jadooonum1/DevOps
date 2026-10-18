resource "aws_security_group" "web" {
  name        = "${local.name}-web"
  description = "reader-web: HTTP from anywhere, SSH from the admin CIDR only"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${local.name}-web" }
}

resource "aws_vpc_security_group_ingress_rule" "http" {
  security_group_id = aws_security_group.web.id
  description       = "HTTP"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "ssh_admin" {
  security_group_id = aws_security_group.web.id
  description       = "SSH from admin"
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = var.admin_cidr
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.web.id
  description       = "package installs and S3"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
