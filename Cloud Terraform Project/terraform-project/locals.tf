locals {
  on_localstack = var.localstack_endpoint != null
  name          = "${var.project}-${var.environment}"

  tags = {
    project     = var.project
    environment = var.environment
    owner       = "parth-agarwal"
    managed_by  = "terraform"
  }

  azs = slice(data.aws_availability_zones.available.names, 0, var.public_subnet_count)

  # 10.30.0.0/16 -> 10.30.1.0/24, 10.30.2.0/24, ...
  public_subnet_cidrs = [for i in range(var.public_subnet_count) : cidrsubnet(var.vpc_cidr, 8, i + 1)]

  site_files = fileset("${path.module}/site", "**")
  mime_types = {
    html = "text/html"
    css  = "text/css"
    js   = "application/javascript"
    txt  = "text/plain"
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}
