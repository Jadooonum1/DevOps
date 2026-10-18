# Session 18: Terraform & Infrastructure as Code

Author: Parth Agarwal

## Goal

1. Learn the core AWS building blocks - IAM, EC2, S3, VPC, DynamoDB/RDS - by driving them with the AWS CLI.
2. Manage infrastructure as code with Terraform: write, plan, apply, inspect state, change, detect drift, destroy.

Everything runs against **LocalStack**, a local emulator of the AWS APIs, so no AWS account, credit card or
cleanup bill is involved. The same commands work on real AWS by dropping `--endpoint-url` (and the LocalStack
settings in `provider.tf`).

## Layout

```
Session 18 - Terraform & Infrastructure as Code/
├── aws-services/
│   ├── localstack.env        credentials + the `awsl` helper (aws --endpoint-url http://localhost:4566)
│   ├── 01-iam/               users, group, managed + inline policy, role, instance profile, STS
│   ├── 02-ec2/               AMI, key pair, security group, instance, EBS volume, lifecycle
│   ├── 03-s3/                versioning, encryption, storage class, lifecycle, TLS-only policy, restore
│   ├── 04-vpc/               CIDR maths, VPC, public/private subnets, IGW, route table, NACL
│   └── 05-dynamodb-rds/      DynamoDB table + GSI + query/scan/conditional update; RDS reference commands
├── terraform-s3-demo/        first Terraform project (S3)
└── screenshots/
```

Each `aws-services/*` folder has its own README with the concepts, commands and what to look for.

## Start LocalStack

```bash
docker run -d --name lib-localstack -p 4566:4566 localstack/localstack:4.9
curl -s localhost:4566/_localstack/health      # services should report "available"/"running"
```

If the `aws` CLI isn't installed, use the container instead:
`alias aws='docker run --rm -it --network host -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_DEFAULT_REGION -v "$PWD":/aws amazon/aws-cli'`.

## Part 1 - AWS services with the CLI

```bash
cd "Session 18 - Terraform & Infrastructure as Code/aws-services/01-iam" && bash commands.sh && bash cleanup.sh
cd ../02-ec2 && bash commands.sh
cd ../03-s3  && bash commands.sh && bash cleanup.sh
cd ../04-vpc && bash commands.sh
cd ../05-dynamodb-rds && bash commands.sh
```

All five scripts were run end-to-end against LocalStack 4.9.2 while writing this (exit code 0); their sub-READMEs
contain trimmed real output. RDS is not part of the free LocalStack image, so `rds-commands.sh` is reference only.

They were run again on 18 Oct 2026 (LocalStack 4.9.2, all exit 0); the screenshots live next to each script:
[IAM](aws-services/01-iam/README.md#screenshots), [EC2](aws-services/02-ec2/README.md#screenshots),
[S3](aws-services/03-s3/README.md#screenshots), [VPC](aws-services/04-vpc/README.md#screenshots),
[DynamoDB / RDS](aws-services/05-dynamodb-rds/README.md#screenshots). For example the VPC run:

![04-vpc commands.sh](aws-services/04-vpc/screenshots/01-vpc-commands.png)

## Part 2 - Terraform S3 demo

Terraform concepts in brief:

- **Provider** - plugin that turns HCL resources into API calls (`hashicorp/aws`). `versions.tf` pins it; the
  `.terraform.lock.hcl` file records the exact version and checksums and is committed.
- **Resource** - one managed object (`aws_s3_bucket.covers`). **Variable** / **output** - inputs and results.
- **State** - Terraform's record of what it created (`terraform.tfstate`). It maps config to real IDs, can contain
  secrets, and is never committed (see `.gitignore`); teams keep it in a remote backend (S3 + locking).
- **Plan** - the diff between config, state and reality. **Apply** executes it. **Destroy** removes everything.
- **Drift** - a change made outside Terraform; the next plan detects it and proposes to put things back.

```bash
cd "Session 18 - Terraform & Infrastructure as Code/terraform-s3-demo"
terraform init                         # downloads hashicorp/aws into .terraform/
terraform fmt -check && terraform validate
terraform plan -out=demo.tfplan
terraform apply demo.tfplan
terraform state list
terraform output
aws --endpoint-url http://localhost:4566 s3 ls s3://bookshelf-covers-demo --recursive

# change: suspend versioning (shows an in-place update, "~")
terraform plan -var enable_versioning=false

# drift: delete an object behind Terraform's back, then plan
aws --endpoint-url http://localhost:4566 s3 rm s3://bookshelf-covers-demo/blurbs/9781491950357.txt
terraform plan            # proposes to re-create that object
terraform apply -auto-approve
terraform plan -detailed-exitcode   # exit code 0 = no changes, back in sync

terraform destroy
```

Real results from running this here (Terraform 1.16.6, hashicorp/aws 5.x, LocalStack 4.9.2):

```
Plan: 6 to add, 0 to change, 0 to destroy.
Apply complete! Resources: 6 added, 0 changed, 0 destroyed.
blurb_keys = tolist([ "blurbs/9780132350884.txt", "blurbs/9781491950357.txt" ])
bucket_arn = "arn:aws:s3:::bookshelf-covers-demo"

# -var enable_versioning=false
  ~ status     = "Enabled" -> "Suspended"
Plan: 0 to add, 1 to change, 0 to destroy.

# after deleting an object with the CLI
  # aws_s3_object.blurb["9781491950357"] will be created
Plan: 1 to add, 0 to change, 0 to destroy.

Destroy complete! Resources: 6 destroyed.
```

## Screenshots (terraform-s3-demo against LocalStack 4.9.2)

`terraform init` installs the provider version pinned in `.terraform.lock.hcl`; `fmt -check` and `validate` are clean:

![terraform init](screenshots/01-tf-init.png)

![terraform fmt and validate](screenshots/02-tf-fmt-validate.png)

The plan: 6 resources to add (the noisy `(known after apply)` attribute lines are filtered out with `grep -v`):

![terraform plan](screenshots/03-tf-plan.png)

![terraform apply](screenshots/04-tf-apply.png)

State, outputs, and the same bucket seen through the AWS CLI (objects, versioning, default tags):

![state list, output, aws s3 ls](screenshots/05-tf-state-output-verify.png)

Changing a variable gives an in-place update (`~`), deleting an object with the CLI is detected as drift and repaired, and
`plan -detailed-exitcode` returns 0 once config, state and reality agree again:

![in-place change](screenshots/06-tf-change-diff.png)

![drift detection](screenshots/07-tf-drift.png)

![terraform destroy and cleanup](screenshots/08-tf-destroy.png)

## Cleanup

```bash
terraform -chdir="Session 18 - Terraform & Infrastructure as Code/terraform-s3-demo" destroy
rm -rf "Session 18 - Terraform & Infrastructure as Code/terraform-s3-demo/.terraform" "Session 18 - Terraform & Infrastructure as Code/terraform-s3-demo/"terraform.tfstate*
docker rm -f lib-localstack
```
