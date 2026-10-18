# 01 - IAM: Identity and Access Management

## Concepts

- **User** - a long-lived identity for a person or legacy app (password and/or access keys).
- **Group** - a collection of users; attach policies to groups, not to individual users.
- **Role** - an identity with no permanent credentials. Something (an EC2 instance, a Lambda, a user in another
  account) *assumes* it and gets short-lived credentials from STS. The **trust policy** says who may assume it;
  the **permission policies** say what it may do.
- **Instance profile** - the wrapper that lets an EC2 instance carry a role.
- **Policy** - JSON with `Effect`, `Action`, `Resource` (and optional `Condition`). AWS-managed vs customer-managed
  vs inline.
- **Evaluation** - everything is implicitly denied; an `Allow` grants; an explicit `Deny` beats any `Allow`.
- **Least privilege** - grant only the actions and resources a job needs (here: read the `bookshelf-covers` bucket,
  nothing else). Use roles instead of access keys, enable MFA, never use the root user day to day.

## Files

| File | Purpose |
|---|---|
| `policies/catalog-covers-read-only.json` | customer-managed policy: `s3:ListBucket` on the bucket, `s3:GetObject` on its objects |
| `policies/deny-delete-catalog.json` | inline guard-rail: explicit Deny on deleting the bucket or its objects |
| `policies/ec2-assume-role-trust.json` | trust policy: only `ec2.amazonaws.com` may assume the role |
| `commands.sh` / `cleanup.sh` | the hands-on, and its reverse |

## Run

```bash
docker run -d --name lib-localstack -p 4566:4566 localstack/localstack:4.9   # once, see ../../README.md
cd "Terraform and AWS/aws-services/01-iam"
bash commands.sh
bash cleanup.sh
```

## What to look for

- Group `library-staff` contains `asha-librarian` and `ravi-cataloguer`, has one attached managed policy and one
  inline policy.
- The role is inside the instance profile, and `sts assume-role` returns a temporary access key with an expiry
  roughly one hour ahead.

Real output (LocalStack 4.9.2, trimmed):

```
$ awsl iam get-group --group-name library-staff --query 'Users[].UserName'
[ "asha-librarian", "ravi-cataloguer" ]
$ awsl iam get-instance-profile --instance-profile-name bookshelf-ec2-profile --query 'InstanceProfile.Roles[].RoleName'
[ "bookshelf-ec2-role" ]
```

Note: LocalStack community stores IAM objects but does not enforce policies, so "access denied" behaviour has to
be shown on real AWS (or with the IAM policy simulator in the console).

## Screenshots to capture

`screenshots/iam-group-users.png` (get-group + attached policies), `screenshots/iam-role-profile.png`
(instance profile + assume-role output).
