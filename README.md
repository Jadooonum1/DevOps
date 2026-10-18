# DevOps Projects

Twenty-one hands-on DevOps projects, one folder per topic. Every project is built around the same
small domain — a **library / book catalogue** (`bookshelf`, `catalog-api`, `loan-service`, `reader-web`) —
so the same ideas carry from a single container all the way to Kubernetes, CI/CD and Terraform.

Each folder has its own `README.md` with the goal, the concepts, the files, the exact commands to run
and what to look for. Each `screenshots/` folder lists the screenshots to capture from your own run.

| # | Folder | Topic |
|---|---|---|
| 1 | [`Linux Fundamentals/`](Linux%20Fundamentals) | Files, permissions, links, users and groups, processes, `journalctl` |
| 2 | [`Shell Scripting/`](Shell%20Scripting) | Variables, input, conditionals, loops, functions, redirection |
| 3 | [`Networking Fundamentals/`](Networking%20Fundamentals) | `ip`, `ss`, `ping`, `curl`, `wget`, `dig`/`nslookup`, `traceroute` |
| 4 | [`Git and Github/`](Git%20and%20Github) | `commit -a` vs `-m`, branching, `cherry-pick` |
| 5 | [`Docker Fundamentals/`](Docker%20Fundamentals) | Hello World containers in Node.js, Python, Java, Apache, React, Nginx |
| 6 | [`DockerFiles and Images/`](DockerFiles%20and%20Images) | Multi-stage builds and image size |
| 7 | [`Docker Networks/`](Docker%20Networks) | Bridge, multi-network, host, bind mounts, overlay |
| 8 | [`Kubernetes Fundamentals/`](Kubernetes%20Fundamentals) | Cluster architecture, system Pods, first Pod, namespaces |
| 9 | [`Kubernetes Workloads/`](Kubernetes%20Workloads) | Pods, ReplicaSets, Deployments, rollouts and rollback, DaemonSets |
| 10 | [`Kubernetes Services/`](Kubernetes%20Services) | ClusterIP, NodePort, LoadBalancer, Headless, ExternalName |
| 11 | [`Kubernetes Ingress and Config/`](Kubernetes%20Ingress%20and%20Config) | ConfigMaps, Secrets, NGINX Ingress |
| 12 | [`Kubernetes Ingress and Config Advanced/`](Kubernetes%20Ingress%20and%20Config%20Advanced) | Mounted config and live updates, TLS, broken → fixed scenarios |
| 13 | [`Kubernetes Storage HPA and Probes/`](Kubernetes%20Storage%20HPA%20and%20Probes) | Volumes, PV/PVC, StorageClass, HPA, probes |
| 14 | [`Kubernetes Troubleshooting/`](Kubernetes%20Troubleshooting) | 11 common failures, triage gauntlet, mini project |
| 15 | [`Helm/`](Helm) | Chart scaffolding, upgrade and rollback, dev and prod values |
| 16 | [`CI-CD GitHub Actions/`](CI-CD%20GitHub%20Actions) | Lint, test, build and smoke-test pipeline |
| 17 | [`DevSecOps Pipeline/`](DevSecOps%20Pipeline) | Secret scanning, SAST, dependency and image scanning, hardening |
| 18 | [`Terraform and AWS/`](Terraform%20and%20AWS) | IAM, EC2, S3, VPC, DynamoDB/RDS, Terraform workflow on LocalStack |
| 19 | [`Cloud Terraform Project/`](Cloud%20Terraform%20Project) | VPC, subnets, security group, EC2 user data, S3 in one project |
| 20 | [`Monitoring Observability and GitOps/`](Monitoring%20Observability%20and%20GitOps) | Prometheus, Alertmanager, Loki, Grafana, Argo CD |
| 21 | [`Final DevOps Project & Troubleshooting/`](Final%20DevOps%20Project%20%26%20Troubleshooting) | Three-tier app with Docker Compose, API tests, debugging |

## Environment

- macOS with Colima (Docker engine); Linux-only commands run in `ubuntu:24.04` containers
- Kubernetes: Minikube with the Docker driver (`minikube start --driver=docker`)
- AWS: [LocalStack](https://github.com/localstack/localstack) in Docker, so no real AWS account is needed
- Tools: `kubectl`, `helm`, `terraform`, `awscli`

The CI/CD and DevSecOps pipelines run on GitHub Actions from [`.github/workflows/`](.github/workflows).

**Author:** Parth Agarwal
