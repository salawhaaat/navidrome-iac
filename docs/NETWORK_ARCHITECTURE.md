# Network Architecture — All Services on Local IP

Complete network topology showing how all Navidrome platform services communicate via Kubernetes internal DNS.

---

## Service Network Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        KUBERNETES CLUSTER                               │
│                 (Internal IP: 192.168.1.11)                             │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  NAVIDROME-PLATFORM NAMESPACE                                            │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │                                                                  │   │
│  │  Service Connectivity (DNS-based):                              │   │
│  │  ├─ navidrome.navidrome-platform.svc.cluster.local:4533       │   │
│  │  ├─ mlflow.navidrome-platform.svc.cluster.local:5000          │   │
│  │  ├─ postgres.navidrome-platform.svc.cluster.local:5432        │   │
│  │  ├─ minio.navidrome-platform.svc.cluster.local:9000           │   │
│  │  ├─ redis.navidrome-platform.svc.cluster.local:6379  ← NEW    │   │
│  │  └─ gateway.navidrome-platform.svc.cluster.local:80/443       │   │
│  │                                                                  │   │
│  │  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐      │   │
│  │  │  NAVIDROME   │    │   MLFLOW     │    │  POSTGRES    │      │   │
│  │  │              │    │              │    │              │      │   │
│  │  │  Port: 4533  │    │  Port: 5000  │    │  Port: 5432  │      │   │
│  │  │  (Music UI)  │    │  (Registry)  │    │  (Database)  │      │   │
│  │  └──────┬───────┘    └──────┬───────┘    └──────┬───────┘      │   │
│  │         │                   │                   │              │   │
│  │         └───────────────────┼───────────────────┘              │   │
│  │                             │                                   │   │
│  │              ┌──────────────▼──────────────┐                   │   │
│  │              │     REDIS (NEW)              │                   │   │
│  │              │  Session & Embeddings Cache │                   │   │
│  │              │  Port: 6379                 │                   │   │
│  │              │  5Gi PVC Storage            │                   │   │
│  │              │  DB 0: Sessions             │                   │   │
│  │              │  DB 1: Embeddings           │                   │   │
│  │              │  DB 2: Counters             │                   │   │
│  │              │  DB 3: Features             │                   │   │
│  │              └──────┬───────────────────────┘                   │   │
│  │                     │                                            │   │
│  │         ┌───────────┼───────────┐                               │   │
│  │         │           │           │                               │   │
│  │  ┌──────▼──────┐  ┌─▼──────────┬┘  ┌────────────────┐          │   │
│  │  │   MINIO     │  │ REDIS-EXP. │   │ GATEWAY/NGINX  │          │   │
│  │  │             │  │ (Metrics)  │   │ (Ingress)      │          │   │
│  │  │ Port: 9000  │  │ Port: 9121 │   │ Port: 80/443   │          │   │
│  │  │ (Object S3) │  │            │   │                │          │   │
│  │  └─────────────┘  └────────────┘   └────────────────┘          │   │
│  │                                                                  │   │
│  └──────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  NAVIDROME-MONITORING NAMESPACE                                          │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │                                                                  │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐           │   │
│  │  │ PROMETHEUS   │  │   GRAFANA    │  │ ALERTMANAGER │           │   │
│  │  │ Port: 9090   │  │ Port: 3000   │  │ Port: 9093   │           │   │
│  │  └──────────────┘  └──────────────┘  └──────────────┘           │   │
│  │        │                  │                  │                   │   │
│  │        └──────────────────┼──────────────────┘                   │   │
│  │                           │                                      │   │
│  │                      Scrapes Metrics From:                       │   │
│  │                      - Prometheus (9090)                         │   │
│  │                      - Redis Exporter (9121)                     │   │
│  │                      - Kubelet (10250)                           │   │
│  │                      - CoreDNS (9153)                            │   │
│  │                      - Pod metrics (prometheus.io/*)             │   │
│  │                                                                  │   │
│  └──────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  ARGO NAMESPACE                                                          │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │  - Argo Workflows (orchestration)                               │   │
│  │  - Argo Server (API)                                            │   │
│  │  - GPU jobs (if available)                                      │   │
│  │  Communicates with:                                             │   │
│  │  - MLflow (model registry)                                      │   │
│  │  - Redis (job state cache)                                      │   │
│  │  - MinIO (training data)                                        │   │
│  └──────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  ARGOCD NAMESPACE                                                        │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │  - ArgoCD Server (GitOps controller)                            │   │
│  │  - ArgoCD Repo Server                                           │   │
│  │  - Application CRDs (staging/canary/production)                 │   │
│  └──────────────────────────────────────────────────────────────────┘   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Service Discovery & Communication

### Kubernetes DNS Names (All Services on Same Local IP)

Every service is accessible via Kubernetes DNS:

```yaml
# Internal DNS (accessible from any pod)
<service-name>.<namespace>.svc.cluster.local:<port>

# Examples for navidrome-platform namespace:
navidrome.navidrome-platform.svc.cluster.local:4533
redis.navidrome-platform.svc.cluster.local:6379
postgres.navidrome-platform.svc.cluster.local:5432
mlflow.navidrome-platform.svc.cluster.local:5000
minio.navidrome-platform.svc.cluster.local:9000
```

### Port Mapping

| Service | Internal Port | External Port | Protocol | DNS Name |
|---------|---------------|---------------|----------|----------|
| **Navidrome** | 4533 | 4533 | HTTP | navidrome.navidrome-platform.svc.cluster.local |
| **MLflow** | 5000 | 8000 | HTTP | mlflow.navidrome-platform.svc.cluster.local |
| **PostgreSQL** | 5432 | — | TCP | postgres.navidrome-platform.svc.cluster.local |
| **MinIO API** | 9000 | 9000 | S3/HTTP | minio.navidrome-platform.svc.cluster.local |
| **MinIO Console** | 9001 | 9001 | HTTP | minio.navidrome-platform.svc.cluster.local |
| **Redis** | 6379 | 6379 | TCP | redis.navidrome-platform.svc.cluster.local |
| **Prometheus** | 9090 | 9090 | HTTP | prometheus.navidrome-monitoring.svc.cluster.local |
| **Grafana** | 3000 | 3000 | HTTP | grafana.navidrome-monitoring.svc.cluster.local |
| **Alertmanager** | 9093 | 9093 | HTTP | alertmanager.navidrome-monitoring.svc.cluster.local |
| **Redis Exporter** | 9121 | 9121 | HTTP | redis-exporter.navidrome-platform.svc.cluster.local |

---

## All Services on Same Local IP

### Why This Design?

1. ✅ **Simplified networking** — no external hostname needed
2. ✅ **Kubernetes DNS** — services discovered automatically
3. ✅ **Same internal IP (192.168.1.11)** — all services reachable via single IP:port
4. ✅ **No inter-pod DNS latency** — CoreDNS caches entries
5. ✅ **Service isolation** — port-based routing (no hostname collision)
6. ✅ **Multi-replica safe** — DNS load balances across replicas

### Single Shared Local IP

```
All services → 192.168.1.11 (node1 internal sharednet1 IP)

Access pattern:
Navidrome:      http://192.168.1.11:4533
MLflow:         http://192.168.1.11:8000
PostgreSQL:     192.168.1.11:5432
Redis:          192.168.1.11:6379
MinIO:          http://192.168.1.11:9000
Prometheus:     http://192.168.1.11:9090
Grafana:        http://192.168.1.11:3000

OR via floating IP (external access):
Navidrome:      http://129.114.x.x:4533
MLflow:         http://129.114.x.x:8000
```

---

## Service Communication Patterns

### 1. Navidrome → Redis (Session Caching)

```python
# In Navidrome (running in navidrome-platform namespace)
import redis

# Kubernetes DNS auto-resolves
r = redis.Redis(
    host='redis.navidrome-platform.svc.cluster.local',  # Or just 'redis'
    port=6379,
    db=0  # Sessions
)

# Store session
r.setex('session:user123', 3600, session_data_json)

# Retrieve session
session = r.get('session:user123')
```

### 2. MLflow → PostgreSQL → Redis

```python
# MLflow uses PostgreSQL as backend store
# Connection string:
DATABASE_URL = "postgresql://postgres:password@postgres.navidrome-platform.svc.cluster.local:5432/mlflow"

# MLflow can also cache model artifacts in Redis
# (for faster serving layer access)
artifact_cache = redis.Redis(
    host='redis.navidrome-platform.svc.cluster.local',
    port=6379,
    db=3  # Features/artifacts
)
```

### 3. Recommendation Service → Redis + MLflow

```python
# Serving service uses Redis for embeddings, MLflow for model
import redis
import mlflow

cache = redis.Redis(
    host='redis.navidrome-platform.svc.cluster.local',
    port=6379,
    db=1  # Embeddings
)

mlflow.set_tracking_uri('http://mlflow.navidrome-platform.svc.cluster.local:5000')
model = mlflow.pyfunc.load_model('models:NavidromeFood11Model/production')

def recommend(user_id):
    # Get cached embedding
    embedding = cache.get(f'embedding:user:{user_id}')
    if not embedding:
        # Compute and cache
        embedding = model.predict(...)
        cache.setex(f'embedding:user:{user_id}', 3600, embedding)
    
    return embedding
```

### 4. Training Job → MinIO + MLflow + Redis

```bash
# Argo Workflow task (GPU job)
python train.py \
  --data-path s3://mlflow-artifacts/training-data \
  --model-name NavidromeFood11Model \
  --tracking-uri http://mlflow.navidrome-platform.svc.cluster.local:5000 \
  --cache-redis redis.navidrome-platform.svc.cluster.local:6379
```

### 5. Monitoring → All Services

```yaml
# Prometheus scrapes metrics from:
- prometheus.navidrome-monitoring.svc.cluster.local:9090 (self)
- redis-exporter.navidrome-platform.svc.cluster.local:9121 (Redis)
- kubelet:10250 (Kubernetes nodes)
- coredns:9153 (DNS metrics)
- alertmanager.navidrome-monitoring.svc.cluster.local:9093
- All pods with prometheus.io/scrape: "true" annotation
```

---

## Data Flow: End-to-End Recommendation

```
1. USER REQUEST
   Browser → Navidrome (4533)
   GET /api/recommendations?user_id=123

2. NAVIDROME SESSION CHECK
   Navidrome → Redis (6379, db=0)
   GET session:user123
   [Cache hit: validate session]

3. RETRIEVE USER EMBEDDINGS
   Navidrome → Redis (6379, db=1)
   GET embedding:user:123
   [If miss, call Serving service]

4. SERVING SERVICE (if embedding cache miss)
   Serving → MLflow (5000)
   GET models/NavidromeFood11Model/production
   
   Serving → Redis (6379, db=3)
   GET features:user:123
   [Cached features for inference]
   
   Serving → ML Model (in-memory)
   PREDICT(features) → embedding vector
   
   Serving → Redis (6379, db=1)
   SET embedding:user:123 (3600s TTL)

5. SCORE RECOMMENDATIONS
   Serving → Redis (6379, db=1)
   MGET embedding:item:1, embedding:item:2, ...
   [Batch get item embeddings]
   
   Serving → ML Model
   SCORE(user_embedding, item_embeddings) → scores

6. STORE SESSION STATE (optional)
   Serving → Redis (6379, db=2)
   INCR recommendations_served:today
   [Real-time counter for analytics]

7. RETURN RECOMMENDATIONS
   Serving → Navidrome (via HTTP)
   {"recommendations": [song1, song2, ...]}

8. MONITORING
   Prometheus scrape
   - Redis metrics: hits/misses/memory from redis-exporter
   - Navidrome metrics: request latency, cache hit rate
   - MLflow metrics: model inference time
   - Serving metrics: P99 latency, cache effectiveness
```

---

## Network Policies (Optional, For Security)

If enabling NetworkPolicies:

```yaml
# Allow navidrome-platform pods to communicate with each other
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-platform-internal
  namespace: navidrome-platform
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector: {}  # Allow intra-namespace communication
    ports:
    - protocol: TCP
      port: 6379   # Redis
    - protocol: TCP
      port: 5432   # PostgreSQL
    - protocol: TCP
      port: 9000   # MinIO
    - protocol: TCP
      port: 5000   # MLflow

---
# Allow monitoring namespace to scrape metrics
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-prometheus-scrape
  namespace: navidrome-platform
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: navidrome-monitoring
    ports:
    - protocol: TCP
      port: 9121  # Redis exporter
    - protocol: TCP
      port: 9090  # Prometheus (for federation)
```

---

## Verification Commands

### Check All Services Running

```bash
# List all services with DNS names
kubectl get svc -A

# Output should include:
# navidrome-platform   navidrome         ClusterIP   10.x.x.x   4533/TCP
# navidrome-platform   redis             ClusterIP   10.x.x.x   6379/TCP
# navidrome-platform   postgres          ClusterIP   10.x.x.x   5432/TCP
# navidrome-platform   mlflow            ClusterIP   10.x.x.x   5000/TCP
# navidrome-platform   minio             ClusterIP   10.x.x.x   9000/TCP
```

### Test Connectivity

```bash
# From any pod in the cluster:
kubectl exec -it <pod-name> -n navidrome-platform -- sh

# Test DNS resolution
nslookup redis.navidrome-platform.svc.cluster.local
nslookup postgres.navidrome-platform.svc.cluster.local

# Test connection (nc or curl)
nc -zv redis.navidrome-platform.svc.cluster.local 6379
curl http://mlflow.navidrome-platform.svc.cluster.local:5000/

# From Python
python3 -c "
import socket
print(socket.gethostbyname('redis.navidrome-platform.svc.cluster.local'))
"
```

### Monitor Network Traffic

```bash
# Check resource usage across services
kubectl top pods -n navidrome-platform

# Monitor network connections
kubectl exec -it <pod-name> -n navidrome-platform -- netstat -antp
```

---

## Summary

| Aspect | Value |
|--------|-------|
| **Single Local IP** | 192.168.1.11 (node1 internal) |
| **Service Discovery** | Kubernetes DNS (*.svc.cluster.local) |
| **Total Services** | 9 (7 platform + 2 monitoring) |
| **Total Ports** | 4533, 5000, 5432, 6379, 9000, 9001, 9090, 3000, 9093, 9121 |
| **Database Count** | 1 PostgreSQL (multi-DB) + 1 Redis (16 DBs) |
| **Cache Layer** | Redis (5Gi, LRU eviction) |
| **Monitoring** | Prometheus + Grafana + Alertmanager |
| **Network Isolation** | Namespace-scoped (optionally NetworkPolicy) |

**All services communicate internally via Kubernetes DNS. External access via floating IP (129.114.x.x) on same ports.**

---

**Last Updated:** April 2026
