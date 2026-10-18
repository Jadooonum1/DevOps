# terraform-s3-demo

A first Terraform configuration: an encrypted, versioned, private S3 bucket for book covers plus one sample
object per entry in `var.seed_books`, created against LocalStack. See `../README.md` for the full walkthrough.

| File | Contents |
|---|---|
| `versions.tf` | Terraform and provider version constraints |
| `provider.tf` | AWS provider pointed at LocalStack (`endpoints`, dummy credentials, path-style S3) |
| `variables.tf` | region, endpoint, bucket name (with validation), owner, versioning flag, seed books |
| `main.tf` | bucket, versioning, SSE, public access block, `for_each` objects |
| `outputs.tf` | bucket name/ARN and the created keys |
| `terraform.tfvars` | values for this run |
| `.terraform.lock.hcl` | exact provider version + checksums (committed on purpose) |

```bash
terraform init && terraform fmt -check && terraform validate
terraform plan -out=demo.tfplan && terraform apply demo.tfplan
terraform output
terraform destroy
```
