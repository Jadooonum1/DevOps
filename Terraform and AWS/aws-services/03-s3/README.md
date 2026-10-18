# 03 - S3: Simple Storage Service

## Concepts

- **Bucket** - a globally-uniquely-named container in one region. **Object** - key (e.g. `blurbs/978...txt`) +
  bytes + metadata; "folders" are just key prefixes.
- **Storage classes** - STANDARD, STANDARD_IA (cheaper storage, retrieval fee), INTELLIGENT_TIERING, GLACIER /
  DEEP_ARCHIVE (archive, slow retrieval). Choose per object.
- **Versioning** - every overwrite keeps the old version; a delete just adds a *delete marker*. Protects against
  accidental overwrites and deletes.
- **Lifecycle rules** - move objects to cheaper classes or expire them after N days (`policies/lifecycle.json`:
  scans -> IA after 30 days -> Glacier after 180; old versions removed after 60 days).
- **Encryption** - SSE-S3 (AES256, AWS-managed keys) by default; SSE-KMS when you need key control/audit.
- **Block Public Access + bucket policy** - public access blocked at bucket level; `policies/require-tls.json`
  denies any request not made over HTTPS.
- Common uses: static websites, backups, data lakes, build artifacts, Terraform remote state.

## Run

```bash
cd "Terraform and AWS/aws-services/03-s3"
bash commands.sh
bash cleanup.sh     # deletes every version + delete marker, then the bucket
```

## What to look for

- versioning `Enabled`, encryption `AES256`
- two versions of `blurbs/9780132350884.txt`, only one `IsLatest`
- `scans/page-001.txt` stored as `STANDARD_IA`
- after copying the old version on top, `s3 cp ... -` prints the *first* edition text again
- after `s3 rm`, the object still has 1 version plus 1 delete marker

Real output (LocalStack 4.9.2, trimmed):

```
|  AaFPWFnDjvxTP6i7h7UQZLubPoBIMLdD |  True  |  29  |
|  AaFPWFnCAZrJhr9RbOrs1sG4.XhMDdc_ |  False |  33  |
[ "STANDARD_IA", "AES256" ]
[ "archive-old-scans", "expire-old-versions" ]
Clean Code - first edition blurb
{ "versions": 1, "deleteMarkers": 1 }
```

## Screenshots to capture

`screenshots/s3-versioning.png` (version table + restored text), `screenshots/s3-lifecycle-policy.png`
(lifecycle rule IDs and bucket policy).
