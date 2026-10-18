variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "localstack_endpoint" {
  description = "LocalStack edge URL"
  type        = string
  default     = "http://localhost:4566"
}

variable "bucket_name" {
  description = "Name of the bucket that stores book cover images"
  type        = string
  default     = "bookshelf-covers-demo"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "Bucket names are 3-63 chars of lowercase letters, digits, dots and hyphens."
  }
}

variable "owner" {
  description = "Value for the owner tag"
  type        = string
  default     = "parth-agarwal"
}

variable "enable_versioning" {
  description = "Keep old versions of overwritten objects"
  type        = bool
  default     = true
}

variable "seed_books" {
  description = "ISBN -> title of sample blurbs uploaded into the bucket"
  type        = map(string)
  default = {
    "9780132350884" = "Clean Code"
    "9781491950357" = "Building Microservices"
  }
}
