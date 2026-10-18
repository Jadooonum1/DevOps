data "aws_ami" "linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = [var.ami_name_pattern]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

resource "aws_instance" "web" {
  count = var.instance_count

  ami                    = data.aws_ami.linux.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public[count.index % var.public_subnet_count].id
  vpc_security_group_ids = [aws_security_group.web.id]
  iam_instance_profile   = aws_iam_instance_profile.web.name

  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    bucket     = aws_s3_bucket.site.bucket
    region     = var.region
    site_title = var.site_title
    server     = "${local.name}-${count.index + 1}"
  })
  # a changed bootstrap script only runs on first boot, so replace the instance when it changes
  user_data_replace_on_change = true

  metadata_options {
    http_tokens = "required" # IMDSv2 only
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 8
    encrypted   = true
  }

  tags = { Name = "${local.name}-${count.index + 1}" }

  depends_on = [aws_s3_object.site, aws_route.internet]
}
