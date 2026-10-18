# Points every call at LocalStack. For real AWS delete the credentials/skip_* lines and the
# endpoints block and let the provider use your normal credential chain.
provider "aws" {
  region                      = var.region
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  s3_use_path_style           = true

  endpoints {
    s3  = var.localstack_endpoint
    sts = var.localstack_endpoint
  }

  default_tags {
    tags = {
      project    = "bookshelf"
      managed_by = "terraform"
      owner      = var.owner
    }
  }
}
