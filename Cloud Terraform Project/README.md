# Cloud Terraform Project - reader-web

Author: Parth Agarwal

## Goal

Provision a complete small web stack for the library's public catalogue page with Terraform:
a VPC with public subnets in two AZs, an internet gateway and routes, a security group, an IAM role +
instance profile, a private S3 bucket holding the static site, and EC2 web servers that pull the site
from S3 at first boot via a **templated `user_data`** script. Run it end to end against LocalStack,
verify it, test the bootstrap script, scale it, move state to a remote backend, and destroy it.

## Concepts in brief

- **Split configuration** - Terraform loads every `*.tf` in the folder as one module; splitting by concern
  (network, security, iam, storage, compute) is purely for readability.
- **Variables, locals, outputs** - inputs with types/validation, computed values (`cidrsubnet`, tags),
  and results printed after apply.
- **`count` / `for_each`** - one block, many resources (subnets per AZ, instances, one object per site file).
- **`templatefile()`** - renders `user_data.sh.tftpl` with the bucket name, region, title and server name.
  `user_data_replace_on_change = true` replaces the instance when the script changes, since cloud-init only
  runs it on first boot.
- **Implicit vs explicit dependencies** - references create edges in the graph; `depends_on` adds the ones
  Terraform can't see (the site must be uploaded and the internet route exist before an instance boots).
- **Instance profile** - how an EC2 instance gets IAM role credentials (no access keys on the box). IMDSv2 is
  enforced (`http_tokens = "required"`).
- **Remote state** - S3 backend with `use_lockfile` (S3-native locking, Terraform >= 1.10).

## Layout

```
Cloud Terraform Project/
├── terraform-project/
│   ├── versions.tf             terraform + provider constraints (aws ~> 5.80, random ~> 3.6)
│   ├── provider.tf             LocalStack endpoints when localstack_endpoint != null, default tags
│   ├── variables.tf            inputs with validation (environment, admin_cidr, subnet count ...)
│   ├── locals.tf               names, tags, AZs, subnet CIDRs, site file list, MIME map
│   ├── network.tf              VPC, IGW, public subnets, route table, route, associations
│   ├── security.tf             security group + separate ingress/egress rule resources
│   ├── iam.tf                  trust policy, read-site policy, role, instance profile
│   ├── storage.tf              random suffix, S3 bucket (versioned, SSE, public access blocked), site objects
│   ├── compute.tf              AMI lookup, aws_instance with templated user_data, IMDSv2, encrypted root
│   ├── user_data.sh.tftpl      bootstrap script template
│   ├── outputs.tf              ids, subnets, bucket, web server IPs and URLs
│   ├── terraform.tfvars        LocalStack values (comments show what to change for real AWS)
│   ├── backend.tf.example      S3 remote state
│   ├── localstack.s3.tfbackend backend overrides for LocalStack
│   ├── site/index.html         the page served by nginx
│   └── .terraform.lock.hcl     provider pins (committed)
├── scripts/boot-test.sh        runs the instance's real user_data in an Amazon Linux 2023 container
├── diagrams/architecture.md    Mermaid: infrastructure, boot sequence, dependency graph
└── screenshots/
```

## Running it

```bash
# LocalStack
docker run -d --name lib-localstack -p 4566:4566 localstack/localstack:4.9
cd "Cloud Terraform Project/terraform-project"

terraform init
terraform fmt -check -recursive && terraform validate
terraform plan -out=tfplan
terraform apply tfplan
terraform output
terraform state list
terraform graph > graph.dot            # dot -Tpng graph.dot -o graph.png  (needs graphviz)
```

Real AWS: comment out `localstack_endpoint` and `ami_name_pattern` in `terraform.tfvars` (the default pattern
picks the newest Amazon Linux 2023 AMI), set `admin_cidr` to your IP/32, then run the same commands. This
creates billable resources - destroy them afterwards.

## What happened when I ran it (LocalStack 4.9.2, Terraform 1.16.6, aws provider 5.100.0)

All results below are real, trimmed.

**Plan / apply** - `Plan: 22 to add, 0 to change, 0 to destroy.` then
`Apply complete! Resources: 22 added, 0 changed, 0 destroyed.`

```
ami = "ami-760aaa0f (amzn-ami-hvm-2017.09.1.20171103-x86_64-gp2)"
public_subnets = {
  "subnet-ba5f3c61532f3e483" = "10.30.1.0/24 (us-east-1a)"
  "subnet-fcb16ee36d87af00e" = "10.30.2.0/24 (us-east-1b)"
}
site_bucket = "reader-web-dev-site-94976c21"
web_servers = { "reader-web-dev-1" = "54.214.164.169" }
```

`terraform state list` showed 26 entries: the 22 managed resources plus 4 data sources
(`aws_ami`, `aws_availability_zones`, two `aws_iam_policy_document`).

**Verifying with the AWS CLI** (`aws --endpoint-url http://localhost:4566 ...`):

```
10.30.1.0/24	us-east-1a	True
10.30.2.0/24	us-east-1b	True
reader-web-dev-1	subnet-ba5f...	arn:aws:iam::000000000000:instance-profile/reader-web-dev-web-profile	required
site/index.html  (723 bytes)
0.0.0.0/0	igw-cc0821e4a8cb16634
```

i.e. both subnets auto-assign public IPs, the instance carries the instance profile and enforces IMDSv2,
the site object is in the bucket, and the public route table points `0.0.0.0/0` at the IGW.

**Boot-testing user_data - and fixing it.** LocalStack never boots a VM, so `scripts/boot-test.sh` fetches the
user data Terraform attached to the instance (`describe-instance-attribute --attribute userData`), checks it with
`bash -n`, and runs it as root in an `amazonlinux:2023` container that can reach LocalStack's S3 (systemctl is
stubbed). The first version of the script used `aws s3 sync ... /usr/share/nginx/html/ --delete`; the boot test
failed with exit code 2 and
`warning: Skipping file /usr/share/nginx/html/poweredby.png. File does not exist.` - deleting the stock nginx files
left a dangling symlink and `aws s3 sync` treats that warning as a failure, which under `set -e` would abort the
bootstrap before nginx starts. The fix was to clear the directory and use `aws s3 cp --recursive`. Because of
`user_data_replace_on_change`, the next plan showed:

```
  # aws_instance.web[0] must be replaced
      ~ user_data = "6049ed07..." -> "60f6f359..." # forces replacement
Plan: 1 to add, 0 to change, 1 to destroy.
```

and the boot test then passed:

```
user_data: bash syntax OK
bootstrapping reader-web-dev-1
reader-web is serving on reader-web-dev-1
  <h1>Bookshelf - community library catalogue</h1>
  <footer>Served by reader-web-dev-1 - provisioned with Terraform</footer>
```

**Scaling out** - `terraform plan -var instance_count=2` -> `aws_instance.web[1] will be created`,
`Plan: 1 to add, 0 to change, 0 to destroy.`; after apply the second server landed in the second subnet
(`count.index % public_subnet_count`) and `web_servers` listed `reader-web-dev-1` and `reader-web-dev-2`.

**Remote state** - created bucket `reader-web-tfstate`, copied `backend.tf.example` to `backend.tf`, and ran
`terraform init -migrate-state -force-copy -backend-config=localstack.s3.tfbackend`. The state object appeared at
`s3://reader-web-tfstate/cloud-terraform-project/dev.tfstate` and a follow-up
`terraform plan -detailed-exitcode` exited 0 (no changes), proving the remote copy matched reality.

**Destroy** - `Destroy complete! Resources: 23 destroyed.` and no running instances were left. The state bucket,
`.terraform/`, `backend.tf` and all state files were then removed; none are committed.

## Commands for each step

```bash
bash ../scripts/boot-test.sh                          # after apply
terraform plan -var instance_count=2                  # scale out
terraform apply -var instance_count=2

# remote state
aws --endpoint-url http://localhost:4566 s3 mb s3://reader-web-tfstate
cp backend.tf.example backend.tf
terraform init -migrate-state -backend-config=localstack.s3.tfbackend
aws --endpoint-url http://localhost:4566 s3 ls s3://reader-web-tfstate --recursive

terraform destroy -var instance_count=2
```

## Screenshots to capture (`screenshots/`)

`init.png`, `fmt-validate.png`, `plan.png` (22 to add), `apply.png` (outputs), `state.png`, `graph.png`,
`verify-cli.png`, `boot-test-fail.png` and `boot-test-pass.png`, `change-replace.png` (forces replacement),
`scale-out.png`, `remote-state.png`, `destroy.png`.

## Cleanup

```bash
terraform destroy
rm -rf .terraform terraform.tfstate* backend.tf
docker rm -f lib-localstack
```
