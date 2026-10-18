resource "aws_s3_bucket" "covers" {
  bucket        = var.bucket_name
  force_destroy = true # demo only: lets destroy remove a non-empty bucket
}

resource "aws_s3_bucket_versioning" "covers" {
  bucket = aws_s3_bucket.covers.id
  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "covers" {
  bucket = aws_s3_bucket.covers.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "covers" {
  bucket                  = aws_s3_bucket.covers.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# one small object per seed book, created with for_each so adding a map entry adds an object
resource "aws_s3_object" "blurb" {
  for_each = var.seed_books

  bucket       = aws_s3_bucket.covers.id
  key          = "blurbs/${each.key}.txt"
  content      = "${each.value} (ISBN ${each.key})\n"
  content_type = "text/plain"
}
