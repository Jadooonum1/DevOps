# DevSecOps Pipeline

Author: Parth Agarwal

## Goal

Take a small Flask service, `loan-service` (members borrow and return library books), and put it behind a
GitHub Actions pipeline where **security checks are gates**: secrets, source code, dependencies,
infrastructure-as-code and the final container image are each scanned, and the image is only built
when every earlier gate passes. The workflow is `/.github/workflows/devsecops.yml` at the repo root and
only triggers for changes in this folder.

## Concepts in brief

- **Shift left** - find security problems at commit/PR time, when they are cheapest to fix, instead of after deployment.
- **Secret scanning** (gitleaks) - regex + entropy rules that spot API keys, tokens and private keys in files.
- **SAST** (Static Application Security Testing: Bandit, Semgrep) - reads source code without running it, looking
  for dangerous patterns such as SQL built from strings, `debug=True`, `subprocess(..., shell=True)`.
- **SCA** (Software Composition Analysis: pip-audit) - compares pinned dependency versions against vulnerability
  databases (PyPI advisory DB / OSV).
- **IaC scanning** (`trivy config`) - checks Dockerfiles and Kubernetes YAML for misconfigurations (root user,
  privilege escalation, missing limits ...).
- **Image scanning** (`trivy image`) - scans OS packages and Python packages *inside the built image*.
- **Defence in depth** - even if one layer fails, the hardened runtime (non-root, read-only FS, no capabilities,
  NetworkPolicy, Pod Security "restricted") limits the damage.

## Pipeline

```
          ┌─ secrets  (gitleaks dir, custom rule for lib_live_ keys)
          ├─ sast     (bandit, semgrep: .semgrep.yml + p/python + p/flask)
 push/PR ─┼─ sca      (pip-audit --strict on requirements.txt)
          ├─ test     (pytest)
          └─ iac      (trivy config: Dockerfile + k8s/, HIGH/CRITICAL)
                         │ all green
                         ▼
                      image  (docker build -> trivy image, fixable HIGH/CRITICAL fail
                              -> run with --read-only --cap-drop ALL and smoke test)
```

No registry push and no secrets are needed. Gitleaks runs as the official CLI container (`zricethezav/gitleaks`),
which avoids the licence key that `gitleaks-action` wants for organisation accounts. `trivy-action` is pinned to
a full commit SHA rather than a tag, because tags can be moved by whoever controls the action's repository.

## Files

```
DevSecOps Pipeline/
├── loan_service/
│   ├── app.py          routes, strict input validation, security headers, JSON errors
│   ├── db.py           SQLite with parameterised queries only
│   └── wsgi.py         gunicorn entry point
├── tests/test_app.py   behaviour + "injection-looking input is rejected" tests
├── Dockerfile          multi-stage, venv copied into runtime, apt upgrade, pip removed, UID 10001, HEALTHCHECK
├── .dockerignore       allow-list style: only requirements.txt and loan_service/ enter the build context
├── k8s/
│   ├── namespace.yaml        Pod Security Admission = restricted
│   ├── serviceaccount.yaml   no API token mounted
│   ├── deployment.yaml       runAsNonRoot, readOnlyRootFilesystem, drop ALL caps, seccomp RuntimeDefault, limits
│   ├── service.yaml
│   └── networkpolicy.yaml    default-deny + allow 8080 from library pods, DNS egress only
├── .gitleaks.toml      default rules + custom "library-catalogue-api-key" rule
├── .semgrep.yml        custom rules: SQL string formatting, Flask debug, hard-coded SECRET_KEY
├── requirements.txt    every runtime package pinned (incl. transitive ones)
└── requirements-dev.txt
```

## Run the gates locally

```bash
cd "DevSecOps Pipeline"
python3 -m venv .venv && . .venv/bin/activate
pip install -r requirements-dev.txt           # app + pytest, bandit, pip-audit
# semgrep 1.181.0 requires click~=8.4.2, which conflicts with the app's click==8.5.0, so give it its own environment
# (the CI sast job installs it on its own runner, so it has no conflict there):
pipx install semgrep==1.181.0                 # or: python3 -m venv ~/.venvs/semgrep && ~/.venvs/semgrep/bin/pip install semgrep==1.181.0

pytest
bandit -r loan_service --severity-level low --confidence-level low
semgrep scan --metrics=off --error --config .semgrep.yml --config p/python --config p/flask loan_service
pip-audit -r requirements.txt --strict --desc
docker run --rm -v "$PWD:/src:ro" zricethezav/gitleaks:v8.30.1 dir /src --config /src/.gitleaks.toml --redact --no-banner --no-color -v
docker run --rm -v "$PWD:/src:ro" aquasec/trivy:0.75.0 config --severity HIGH,CRITICAL --exit-code 1 /src

docker build -t loan-service:local .
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy:0.75.0 \
  image --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 loan-service:local
docker run -d --name loan -p 8080:8080 --read-only --cap-drop ALL \
  --security-opt no-new-privileges --tmpfs /data:uid=10001,gid=10001 loan-service:local
curl -i localhost:8080/healthz
curl -s -XPOST localhost:8080/loans -H 'content-type: application/json' \
  -d '{"member_id":"M00001","isbn":"9780132350884"}'
docker rm -f loan
```

### What I got when running these here (real results, Oct 2026)

On this machine port 8080 was taken, so the screenshots use host port 18082, `lib-` prefixed container/image names
and a named volume (`lib-trivy-cache`) so Trivy downloads its database once.

pytest: `6 passed`; Bandit at every severity/confidence level: no issues.

![pytest and bandit](screenshots/01-pytest-bandit.png)

Semgrep, custom `.semgrep.yml` + `p/python` + `p/flask` (154 rules): 0 findings, exit 0.

![semgrep scan](screenshots/02-semgrep.png)

pip-audit `--strict`: no known vulnerabilities; gitleaks `dir`: no leaks found.

![pip-audit and gitleaks](screenshots/03-pip-audit-gitleaks.png)

Trivy config: 0 HIGH/CRITICAL misconfigurations in the Dockerfile and all five manifests. One MEDIUM,
KSV-0125 "untrusted registry", remains because the image registry in the deployment is a placeholder.

![trivy config](screenshots/06-trivy-config.png)

Trivy image (`--ignore-unfixed`, HIGH/CRITICAL): 0 findings in the Debian 13.7 base and in every Python package.

![docker build and trivy image](screenshots/07-build-trivy-image.png)

The container runs read-only with all capabilities dropped as `uid=10001(librarian)`, returns the security headers,
and rejects injection-looking input with a 400:

![hardened container](screenshots/08-hardened-container.png)

The Kubernetes manifests were validated offline with kubeconform (6 resources valid). They were **not** applied to a
cluster for this write-up because the shared cluster was reserved for other work.

![kubeconform and cleanup](screenshots/11-k8s-kubeconform-cleanup.png)

### The pipeline on GitHub Actions

Both runs of `devsecops (loan-service)` on the repository are green; the five gates run in parallel and `image` runs
after all of them (read with `gh run list` / `gh run view`):

![devsecops run: iac, sca, secrets, sast, test -> image](screenshots/09-gh-pipeline-green.png)

The Trivy tables printed by the `iac` and `image` jobs of that run (the CI action ships Trivy 0.70.0), plus the end of
the hardened smoke test:

![trivy tables from the CI logs](screenshots/10-gh-trivy-tables.png)

## Demonstrating that the gates block (do this on a branch, never on main)

| Break it | Gate that should fail |
|---|---|
| Add `PARTNER_KEY = "lib_live_` + 32 random letters/digits + `"` to `loan_service/app.py` | `secrets` - rule `library-catalogue-api-key` (verified locally: gitleaks reports 1 leak and exits 1) |
| Change a query in `db.py` to `conn.execute(f"SELECT ... WHERE member_id = '{member_id}'")` | `sast` - custom Semgrep rule (verified locally) and Bandit B608 |
| Add `app.run(debug=True)` | `sast` - Semgrep `library-flask-debug-enabled`, Bandit B201 |
| Pin an old dependency, e.g. `jinja2==3.1.2` | `sca` - pip-audit lists the advisories |
| Remove `USER 10001:10001` from the Dockerfile, or `readOnlyRootFilesystem` from the deployment | `iac` - Trivy config (DS-0002 / KSV checks) |
| Change the base image to an old one such as `python:3.9-slim-bullseye` | `image` - Trivy reports fixable HIGH/CRITICAL CVEs |

Red runs on GitHub need throw-away commits pushed to a branch, which was not done for this write-up. Instead the same
breakages were run locally with the exact gate commands. A real `lib_live_` key (random, generated in the shell so it never
appears on screen) planted in a temporary file is caught by the custom rule, and the scan is clean again once the file is
deleted:

![gitleaks catches a planted key](screenshots/04-gitleaks-planted-secret.png)

The f-string SQL, `app.run(debug=True)` and `jinja2==3.1.2` changes from the table, applied to a copy of the code in a
scratch directory (the repository was not modified): Semgrep (custom + p/flask rules), Bandit (B201, B608) and pip-audit
all exit 1.

![semgrep, bandit and pip-audit blocking](screenshots/05-sast-sca-blocked.png)

Expected behaviour: the failing job turns red, the `image` job is skipped because it `needs` every gate,
and the PR shows the check as failed. Reverting the change makes the run green again.

If a secret ever is committed: **rotate it first** (it is already public in history), then remove it
from the code, and only then consider rewriting history.

## Deploying the hardened manifests (needs a cluster)

```bash
kubectl apply -f k8s/
kubectl -n library get pods
kubectl -n library auth can-i list pods --as system:serviceaccount:library:loan-service   # expect "no"
```

Replace the placeholder image in `k8s/deployment.yaml` with your own image (ideally pinned by digest).
On a cluster with a NetworkPolicy-capable CNI (Calico, Cilium) the default-deny policy is enforced.

## Cleanup

```bash
docker rm -f loan; docker rmi loan-service:local
rm -rf .venv
kubectl delete namespace library   # if deployed
```
