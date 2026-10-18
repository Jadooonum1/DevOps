# When var.localstack_endpoint is set, every service used here is redirected to LocalStack and
# dummy credentials are used. Set it to null (see terraform.tfvars) to target real AWS with your
# normal credential chain (env vars, ~/.aws/config, SSO).
provider "aws" {
  region = var.region

  access_key                  = local.on_localstack ? "test" : null
  secret_key                  = local.on_localstack ? "test" : null
  skip_credentials_validation = local.on_localstack
  skip_metadata_api_check     = local.on_localstack
  skip_requesting_account_id  = local.on_localstack
  s3_use_path_style           = local.on_localstack

  dynamic "endpoints" {
    for_each = local.on_localstack ? [var.localstack_endpoint] : []
    content {
      ec2 = endpoints.value
      iam = endpoints.value
      s3  = endpoints.value
      sts = endpoints.value
    }
  }

  default_tags {
    tags = local.tags
  }
}
