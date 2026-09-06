# Fleet Commander

Fleet Commander is a Kubernetes-themed demo application that simulates a fleet management system using a shipping metaphor. It exposes REST API endpoints for managing harbors, ships, voyages, and deployment-like operations, while also exposing Prometheus metrics.

The project combines:
- FastAPI as the API layer
- Docker for containerization
- Kubernetes / AKS for deployment
- Helm for packaging
- ArgoCD for GitOps-based deployment
- Terraform for Azure infrastructure provisioning
- Prometheus and Grafana for observability
- GitHub Actions for CI/CD automation

## Overview

The application is intentionally designed as a playful analogy for Kubernetes concepts:

- Harbor = Namespace
- Ship = Pod / workload
- Voyage = Deployment rollout / event
- Fleet summary = cluster overview

The core service is implemented in [app/main.py](app/main.py) and runs via [app/Dockerfile](app/Dockerfile).

## Architecture

The project consists of several layers:

1. API service
   - FastAPI app
   - in-memory fleet state
   - Prometheus metrics middleware

2. Containerization
   - Docker image for the Python service

3. Kubernetes deployment
   - Helm chart in [helm/fleet-commander](helm/fleet-commander)
   - Ingress, service, autoscaling, probes

4. GitOps
   - ArgoCD applications in [argocd](argocd)

5. Cloud infrastructure
   - Azure AKS provisioning in [infra/terraform](infra/terraform)

6. Observability
   - Prometheus metrics endpoint
   - monitoring configuration via [monitoring](monitoring)

## Tech stack

- Python 3.12
- FastAPI
- Uvicorn
- Pydantic
- Prometheus Client
- Docker
- Kubernetes
- Helm
- Azure AKS
- Terraform
- ArgoCD
- Grafana / Prometheus
- GitHub Actions

## Project structure

```text
fleet-commander/
├── app/
│   ├── main.py
│   ├── requirements.txt
│   └── Dockerfile
├── helm/
│   └── fleet-commander/
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
├── argocd/
│   ├── root-application.yaml
│   ├── monitoring-application.yaml
│   └── fleet-application.yaml
├── monitoring/
│   ├── fleet-dashboard.yaml
│   └── servicemonitor.yaml
├── infra/
│   └── terraform/
│       ├── aks.tf
│       ├── keyvault.tf
│       ├── providers.tf
│       ├── resource_group.tf
│       ├── outputs.tf
│       ├── variables.tf
│       └── versions.tf
├── README.md
└── .github/