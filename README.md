# DevOps Projects

Hands-on DevOps assignments for Sessions 1–21, one folder per session. Every project is built around the same
small domain — a **library / book catalogue** (`bookshelf`, `catalog-api`, `loan-service`, `reader-web`) —
so the same ideas carry from a single container all the way to Kubernetes, CI/CD and Terraform.

Each folder has its own `README.md` with the goal, the concepts, the files, the exact commands to run
and what to look for. Every project was run end to end, and each README embeds screenshots from that real run.

| Session | Topic | What it covers |
|---|---|---|
| 1 & 2 | [Linux Fundamentals](Session%2001-02%20-%20Linux%20Fundamentals/README.md) | Links, users, `journalctl`, everyday commands |
| 3 | [Shell Scripting](Session%2003%20-%20Shell%20Scripting/README.md) | Variables, input, files, redirection, exit codes |
| 4 | [Networking](Session%2004%20-%20Networking/README.md) | `ip`, `ss`, `ping`, `curl`, `wget`, `dig`, `traceroute` |
| 5 | [Git and GitHub](Session%2005%20-%20Git%20and%20GitHub/README.md) | `commit -a` vs `-m`, branches, `cherry-pick`, conflicts |
| 6 | [Docker Fundamentals](Session%2006%20-%20Docker%20Fundamentals/README.md) | Hello World in Node.js, Python, Java, Apache, React, Nginx |
| 7 | [Docker Images](Session%2007%20-%20Docker%20Images/README.md) | Multi-stage build: 469 MB toolchain → 13 MB image |
| 8 | [Docker Networking](Session%2008%20-%20Docker%20Networking/README.md) | Bridge, multi-network, host, bind mounts, volumes, overlay |
| 9 | [Kubernetes Fundamentals](Session%2009%20-%20Kubernetes%20Fundamentals/README.md) | Architecture, system Pods, first Pod, namespaces |
| 10 | [Kubernetes Pods, ReplicaSets & Deployments](Session%2010%20-%20Kubernetes%20Pods%2C%20ReplicaSets%20%26%20Deployments/README.md) | Self-healing, scaling, rolling update, rollback, DaemonSet |
| 11 | [Kubernetes Networking & Services](Session%2011%20-%20Kubernetes%20Networking%20%26%20Services/README.md) | ClusterIP, NodePort, LoadBalancer, Headless, ExternalName |
| 12 | [Kubernetes Ingress, ConfigMaps & Secrets](Session%2012%20-%20Kubernetes%20Ingress%2C%20ConfigMaps%20%26%20Secrets/README.md) | ConfigMaps, Secrets, Ingress, TLS + advanced troubleshooting |
| 13 | [Kubernetes Storage, HPA & Probes](Session%2013%20-%20Kubernetes%20Storage%2C%20HPA%20%26%20Probes/README.md) | Volumes, PV/PVC, StorageClass, HPA, probes |
| 14 | [Kubernetes Troubleshooting](Session%2014%20-%20Kubernetes%20Troubleshooting/README.md) | 11 failures broken → fixed, triage gauntlet |
| 15 | [Helm](Session%2015%20-%20Helm/README.md) | Charts, upgrade, rollback, dev/prod values |
| 16 | [CI/CD & GitHub Actions](Session%2016%20-%20CI-CD%20%26%20GitHub%20Actions/README.md) | Lint → test → Docker build → smoke test |
| 17 | [Complete CI/CD & DevSecOps](Session%2017%20-%20Complete%20CI-CD%20%26%20DevSecOps/README.md) | gitleaks, Bandit, Semgrep, pip-audit, Trivy, hardening |
| 18 | [Terraform & Infrastructure as Code](Session%2018%20-%20Terraform%20%26%20Infrastructure%20as%20Code/README.md) | IAM, EC2, S3, VPC, DynamoDB + Terraform on LocalStack |
| 19 | [Cloud & Terraform in Action](Session%2019%20-%20Cloud%20%26%20Terraform%20in%20Action/README.md) | VPC, subnets, SG, IAM, EC2 user data, S3, remote state |
| 20 | [Monitoring, Observability & GitOps](Session%2020%20-%20Monitoring%2C%20Observability%20%26%20GitOps/README.md) | Prometheus, Alertmanager, Loki, Grafana, Argo CD |
| 21 | [Final DevOps Project & Troubleshooting](Session%2021%20-%20Final%20DevOps%20Project%20%26%20Troubleshooting/README.md) | Three-tier app with Docker Compose, API tests, debugging |

## Environment

- macOS with Colima (Docker engine); Linux-only commands run in `ubuntu:24.04` containers
- Kubernetes: Minikube with the Docker driver (`minikube start --driver=docker`)
- AWS: [LocalStack](https://github.com/localstack/localstack) in Docker, so no real AWS account is needed
- Tools: `kubectl`, `helm`, `terraform`, `awscli`

The CI/CD and DevSecOps pipelines run on GitHub Actions from [`.github/workflows/`](.github/workflows).

**Author:** Parth Agarwal
