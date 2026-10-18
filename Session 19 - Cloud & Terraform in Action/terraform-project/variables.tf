variable "project" {
  description = "Prefix for every resource name"
  type        = string
  default     = "reader-web"
}

variable "environment" {
  description = "dev / staging / prod"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging or prod."
  }
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "localstack_endpoint" {
  description = "LocalStack URL, or null for real AWS"
  type        = string
  default     = null
}

variable "vpc_cidr" {
  type    = string
  default = "10.30.0.0/16"
}

variable "public_subnet_count" {
  description = "How many public subnets (one per AZ) to carve out of the VPC"
  type        = number
  default     = 2

  validation {
    condition     = var.public_subnet_count >= 1 && var.public_subnet_count <= 4
    error_message = "Use between 1 and 4 public subnets."
  }
}

variable "instance_count" {
  description = "Number of web servers, spread round-robin across the public subnets"
  type        = number
  default     = 1
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "ami_name_pattern" {
  description = "Name filter for the newest Amazon-owned AMI to use"
  type        = string
  default     = "al2023-ami-2023.*-x86_64"
}

variable "admin_cidr" {
  description = "Only this CIDR may SSH in. Use your own public IP with /32."
  type        = string
  default     = "203.0.113.10/32"

  validation {
    condition     = can(cidrhost(var.admin_cidr, 0)) && var.admin_cidr != "0.0.0.0/0"
    error_message = "admin_cidr must be a valid CIDR and must not be 0.0.0.0/0."
  }
}

variable "site_title" {
  description = "Heading rendered into the web page by user_data"
  type        = string
  default     = "Bookshelf - community library catalogue"
}
