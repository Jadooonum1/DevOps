output "bucket_name" {
  value = aws_s3_bucket.covers.bucket
}

output "bucket_arn" {
  value = aws_s3_bucket.covers.arn
}

output "blurb_keys" {
  description = "Object keys created from var.seed_books"
  value       = sort([for o in aws_s3_object.blurb : o.key])
}
