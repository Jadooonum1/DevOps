# CI/CD with GitHub Actions

Author: Parth Agarwal

## Goal

Build a small `catalog-api` service for a library (books + loan fines) and wire it into a GitHub Actions
pipeline that lints, tests and builds a Docker image on every change, then smoke-tests the running
container. Nothing is pushed to a registry, so the pipeline needs **no secrets** to go green.

## Concepts in brief

| Term | Meaning here |
|------|--------------|
| **CI** (Continuous Integration) | Every push/PR is automatically linted, tested and built so broken code is caught before merge. |
| **CD** (Continuous Delivery/Deployment) | The verified artifact (our image, tagged with the commit SHA) is ready to ship; a later step would push it and roll it out to Kubernetes. |
| **Workflow** | A YAML file in `.github/workflows/`. GitHub only reads workflows from the *repository root*, which is why `ci-cd.yml` lives at `/.github/workflows/ci-cd.yml` and not in this folder. |
| **Job** | A set of steps that runs on a fresh runner VM. Jobs run in parallel unless linked with `needs:`. |
| **Step** | A shell command (`run:`) or a reusable action (`uses:`). |
| **Runner** | The machine executing a job (`ubuntu-latest`, GitHub-hosted). |
| **Matrix** | One job definition fanned out over several values - here Python 3.11 and 3.12. |
| **Artifact** | A file uploaded from a job (the JUnit XML test report) that you can download from the run page. |
| **Path filter** | `on.push.paths` - the workflow only triggers when files in this folder (or the workflow itself) change, so other coursework folders don't trigger it. |

## Pipeline

```
push / PR touching "CI-CD GitHub Actions/**"
        |
     [lint] flake8
        |
     [test] pytest  (matrix: 3.11, 3.12)  -> uploads test-results-*.xml
        |
    [docker] docker build (tag = short SHA) -> run container -> curl /healthz, /books, /version
```

`defaults.run.working-directory: "CI-CD GitHub Actions"` makes every `run:` step execute inside this
folder (the path is quoted because it contains spaces).

## Files

```
CI-CD GitHub Actions/
├── catalog/
│   ├── __init__.py        version string
│   ├── loans.py           pure functions: due_date, overdue_fine, is_valid_isbn13
│   └── app.py             Flask routes: /healthz /version /books /books/<isbn> /loans/quote
├── tests/
│   ├── test_loans.py      unit tests for the business rules
│   └── test_api.py        API tests via Flask's test client
├── k8s/                   namespace, deployment (probes + limits), service  (namespace: library)
├── Dockerfile             python:3.12-slim, gunicorn, non-root user, GIT_SHA build arg
├── Makefile               venv / lint / test / build / run / smoke / clean
├── requirements*.txt      pinned runtime and dev dependencies
├── .flake8, pytest.ini, .dockerignore
└── screenshots/
../.github/workflows/ci-cd.yml   the pipeline
```

## Run it locally first

```bash
cd "CI-CD GitHub Actions"
make venv          # creates .venv and installs requirements-dev.txt
make lint          # flake8
make test          # pytest
make run           # docker build + run on :8000
make smoke         # curl /healthz and /books
curl "http://localhost:8000/loans/quote?borrowed=2025-03-01&returned=2025-03-20"
make clean
```

Expected behaviour: flake8 prints nothing, pytest reports all tests passing, `/healthz` returns
`{"status":"ok"}`, `/version` shows the commit the image was built from, and the loan quote above
returns a due date of 2025-03-15 and a fine of 1.25 (5 days late x 0.25).

Real output from building and running the image locally while writing this:

```
$ curl localhost:18000/version
{"commit":"abc1234","version":"1.0.0"}
$ docker exec cicd-smoke id
uid=10001(librarian) gid=10001(librarian) groups=10001(librarian)
```

## Running it on GitHub

1. Push the repository to GitHub (the workflow is already at the repo root).
2. Edit any file in this folder (or run the workflow manually from the **Actions** tab - `workflow_dispatch`).
3. Open **Actions -> ci-cd (catalog-api)** and watch `lint -> test (3.11, 3.12) -> docker`.
4. Open the run summary: the docker job writes the image tag and size to the job summary, and the
   test reports appear under **Artifacts**.

### Show that CI blocks bad code

- **Lint failure**: add an unused import to `catalog/app.py`, push -> `lint` goes red and `test`/`docker` are skipped.
- **Test failure**: change `FINE_PER_DAY` in `catalog/loans.py` to `0.5`, push -> `test` goes red on both matrix legs.
- Revert and push again -> the run is green.

### Deploying (needs a cluster, not done in CI)

```bash
kind load docker-image catalog-api:local     # or minikube image load
kubectl apply -f k8s/namespace.yaml -f k8s/deployment.yaml -f k8s/service.yaml
kubectl -n library rollout status deploy/catalog-api
kubectl -n library port-forward svc/catalog-api 8080:80
```

## Screenshots to capture (`screenshots/`)

- `local-lint-test.png` - `make lint` and `make test` passing locally
- `workflow-graph.png` - the Actions run graph showing lint -> test (matrix) -> docker
- `ci-red-lint.png` / `ci-red-test.png` - a run failing on lint, and one failing on tests
- `ci-green.png` - the fixed, passing run
- `artifacts-summary.png` - the job summary and the downloaded test-results artifacts
- `smoke-test-step.png` - the expanded "Smoke test the container" step

## Cleanup

```bash
make clean && rm -rf .venv
kubectl delete namespace library   # if deployed
```
