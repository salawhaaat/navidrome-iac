# Architecture

## Platform Overview

![Architecture Diagram](navidrome.drawio.png)

---

## Service Map

All services run in the `navidrome-platform` namespace on a single node (m1.xlarge, KVM@TACC).
Internal communication via Kubernetes DNS (`<svc>.navidrome-platform.svc.cluster.local`).

```
navidrome-platform namespace
├── Navidrome          :4533   Music server (custom fork with recs page)
├── MLflow             :5000   Model registry + experiment tracking
├── PostgreSQL         :5432   Shared DB (mlflow + navidrome databases)
├── MinIO              :9000   S3-compatible object storage (artifacts, data)
├── Redis              :6379   Cache (sessions, embeddings, counters, features)
└── Redis Exporter     :9121   Prometheus metrics for Redis

navidrome-monitoring namespace
├── Prometheus         :9090   Metrics collection + alert rules
├── Grafana            :3000   Dashboards
└── Alertmanager       :9093   Alert routing

navidrome-staging      :8082   Staging deployment of navidrome-app
navidrome-canary       :8081   Canary deployment
navidrome-production   :8080   Production deployment

argo namespace         Argo Workflows (train, build, test, promote)
argocd namespace       ArgoCD GitOps controller
```

External access via floating IP on the same ports.

---

## Resource Requirements

| Service | CPU req | CPU limit | Mem req | Mem limit | Storage |
|---|---|---|---|---|---|
| Navidrome | 100m | 500m | 256Mi | 512Mi | 2Gi + 10Gi PVC |
| MLflow | 200m | 1000m | 1Gi | 2Gi | MinIO (S3) |
| PostgreSQL | 100m | 500m | 256Mi | 1Gi | 5Gi PVC |
| MinIO | 100m | 500m | 256Mi | 1Gi | 20Gi PVC |
| Redis | 100m | 500m | 256Mi | 1Gi | 5Gi PVC |
| Prometheus | 250m | 1000m | 512Mi | 2Gi | 10Gi PVC |
| Grafana | 100m | 500m | 256Mi | 1Gi | 5Gi PVC |
| Alertmanager | 100m | 500m | 128Mi | 512Mi | 2Gi PVC |

> Evidence: run `kubectl top pods -n navidrome-platform` on Chameleon after load.

---

## Autoscaling

HPA configured for:
- **MLflow:** 1-3 replicas (CPU 70%, memory 75%)
- **Navidrome:** 1-2 replicas (CPU 80%, memory 85%)

---

## Redis Database Layout

| DB | Purpose | TTL |
|----|---------|-----|
| 0 | User sessions | 1-24h |
| 1 | User/item embeddings | 1-24h |
| 2 | Event counters | 24h |
| 3 | Feature store (ML) | 12-24h |

Connection: `redis.navidrome-platform.svc.cluster.local:6379`
