output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnets" {
  description = "subnet id => CIDR / AZ"
  value       = { for s in aws_subnet.public : s.id => "${s.cidr_block} (${s.availability_zone})" }
}

output "security_group_id" {
  value = aws_security_group.web.id
}

output "site_bucket" {
  value = aws_s3_bucket.site.bucket
}

output "instance_profile" {
  value = aws_iam_instance_profile.web.name
}

output "ami" {
  value = "${data.aws_ami.linux.id} (${data.aws_ami.linux.name})"
}

output "web_servers" {
  description = "Name => public IP"
  value       = { for i in aws_instance.web : i.tags["Name"] => i.public_ip }
}

output "site_urls" {
  value = [for i in aws_instance.web : "http://${i.public_ip}/"]
}
