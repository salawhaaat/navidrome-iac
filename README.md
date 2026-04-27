# navidrome-iac

Infrastructure-as-code for the Navidrome MLOps course project (ECE-GY 9183).

Provisions a Kubernetes cluster on Chameleon Cloud (KVM@TACC) and deploys a full MLOps platform:

- **Navidrome** — music server with ML recommendation engine
- **navidrome-serve** — FastAPI inference service (GRU4Rec recommendations)
- **MLflow** — model registry and experiment tracking
- **PostgreSQL** — shared database (MLflow + Navidrome)
- **MinIO** — S3-compatible object storage (model artifacts, datasets, audio cache)
- **Redis** — cache (sessions, embeddings, recommendation features)
- **Prometheus + Grafana + Alertmanager** — monitoring and alerting
- **Argo Workflows** — ML pipeline orchestration (train, build, finetune, promote)

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the full service map.  
See [DEPLOYMENT.md](DEPLOYMENT.md) for step-by-step provisioning instructions.

---

## Repo Layout

```
tf/kvm/                   Terraform — VMs, networks, floating IP, security groups
ansible/
  pre_k8s/                Node prep (firewalld, Docker registry)
  k8s/kubespray/          Kubespray submodule — Kubernetes install
  k8s/inventory/          Kubespray inventory
  post_k8s/               Post-install (kubectl, Argo Workflows)
k8s/
  platform/               Helm chart — Navidrome, MLflow, PostgreSQL, MinIO, Redis
  monitoring/             Helm chart — Prometheus, Grafana, Alertmanager, NVIDIA plugin
workflows/                Argo WorkflowTemplates (train, build, finetune, promote, GPU)
docs/                     Architecture diagrams, safeguarding plan
Makefile                  Full deploy automation
```

---

## Prerequisites

```bash
brew install terraform ansible helm kubectl

# OpenStack credentials for KVM@TACC
# Place at ~/.config/openstack/clouds.yaml

# SSH key registered on Chameleon
# Expected at ~/.ssh/id_rsa_chameleon
```

---

## Deploy

```bash
# 1. Set Blazar lease IDs from Chameleon UI
export RESERVATION_ID="<cpu-lease-uuid>"
export GPU_RESERVATION_ID="<gpu-lease-uuid>"   # optional

# 2. Deploy full stack (~90 min)
make all RESERVATION_ID=$RESERVATION_ID GPU_RESERVATION_ID=$GPU_RESERVATION_ID

# 3. Verify
export FLOATING_IP=$(terraform -chdir=tf/kvm output -raw floating_ip_out)
kubectl cluster-info
kubectl get pods -A
```

Full instructions: [DEPLOYMENT.md](DEPLOYMENT.md)

After deploy, services are available at:

| Service | URL | Credentials |
|---|---|---|
| Navidrome | `http://$IP:4533` | Create user in UI |
| MLflow | `http://$IP:8000` | No auth |
| MinIO Console | `http://$IP:9001` | minioadmin / \<password\> |
| Prometheus | `http://$IP:9090` | No auth |
| Grafana | `http://$IP:3000` | admin / admin |
| Alertmanager | `http://$IP:9093` | No auth |
| Argo Workflows | `https://$IP:2746` | No auth |

---

## Persistent Storage

All data is stored on the secondary disk (`/dev/vdb`, 98GB, mounted at `/mnt/music-vol`). Nothing important lives on the root disk (`/dev/vda3`, 37GB). The cluster survives VM reboots without data loss.

### Disk Layout (`/dev/vdb` → `/mnt/music-vol`)

```
/mnt/music-vol/
  music/audio_complete/     Music files (navidrome-music-pvc, 50Gi, Retain)
  pvc-storage/              All Kubernetes PVC data (local-path-provisioner)
    pvc-*_postgres-pvc/     PostgreSQL data
    pvc-*_minio-pvc/        MinIO buckets (artifacts, audio-cache, datasets, metadata)
    pvc-*_navidrome-data-pvc/ Navidrome index and cache
    pvc-*_redis-data/       Redis dump
    pvc-*_serve-artifacts-pvc/ GRU4Rec model weights + vocab
    pvc-*_prometheus-storage/ Prometheus TSDB
    pvc-*_grafana-storage/  Grafana dashboards
    pvc-*_alertmanager-storage/ Alertmanager state
  docker-overlay2/          Docker image layers (bind-mounted to /var/lib/docker/overlay2)
  registry-data/            In-cluster Docker registry images (hostPath)
```

### How It Works

- **`local-path-provisioner`** is configured to provision all PVCs under `/mnt/music-vol/pvc-storage/` (not the default `/opt/local-path-provisioner/` on root)
- **All PVs** have `ReclaimPolicy: Retain` — deleting a PVC does not delete the data
- **`navidrome-music-pvc`** is a static PV bound to `/mnt/music-vol/music/audio_complete`
- **Docker overlay2** is bind-mounted (not symlinked — runc rejects symlinks as rootfs) from `/mnt/music-vol/docker-overlay2` to `/var/lib/docker/overlay2`. Entry in `/etc/fstab` ensures it survives reboots
- **Registry** (`kube-system/registry`) uses `hostPath: /mnt/music-vol/registry-data` instead of emptyDir

### Reconfigure `local-path-provisioner` (already applied on cluster)

```bash
kubectl edit configmap local-path-config -n local-path-storage
# Set paths to ["/mnt/music-vol/pvc-storage/"]
```

---

## CI/CD — Building Container Images

### navidrome-custom (frontend + Go server)

Triggered by push to `navidrome-custom` branch via `.github/workflows/deploy.yml`.  
Can also be triggered manually:

```bash
kubectl create -f - <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  generateName: ci-build-navidrome-
  namespace: argo
spec:
  workflowTemplateRef:
    name: build-navidrome-custom
EOF
```

### navidrome-serve (Python inference service)

```bash
argo submit --from workflowtemplate/build-serve -n argo

# Watch the build
kubectl logs -n argo -l workflows.argoproj.io/workflow=<name> -f --prefix
# Or via Argo UI: https://$IP:2746
```

**Note:** The buildcache (`--export-cache`/`--import-cache`) is intentionally disabled. The registry uses a hostPath on `/dev/vdb` so storage is not a concern, but BuildKit cache with `mode=max` accumulated ~13GB of intermediate layers that caused node evictions. Builds are cold but reliable (~7-10 min).

---

## Argo Workflows

| WorkflowTemplate | Purpose | Schedule |
|---|---|---|
| `cron-train` | Full GRU4Rec training from scratch | Weekly |
| `cron-finetune` | Incremental finetune on recent plays | Every 6h |
| `build-serve` | Build + push `navidrome-serve` image | On demand |
| `build-navidrome-custom` | Build + push `navidrome-custom` image | On push to branch |
| `train-model` | Manual training trigger | On demand |
| `train-gpu` | GPU training on MI100 via SSH | On demand |
| `inference-gpu` | GPU inference batch job | On demand |
| `promote-model` | Promote staged model to production | On demand |

```bash
# List all workflows
kubectl get workflow -n argo --sort-by='.metadata.creationTimestamp'

# Submit finetune manually
argo submit --from cronworkflow/cron-finetune -n argo

# Clean up completed/failed pods
kubectl delete pod -n argo --field-selector=status.phase=Succeeded
kubectl delete pod -n argo --field-selector=status.phase=Failed
```

---

## RBAC Notes

The `argo` namespace `default` ServiceAccount is used by CI workflows and has:
- `workflowtaskresults` create permission (built-in from argo install)
- `argo-default-deploy` RoleBinding — allows `kubectl rollout restart deployment/navidrome -n navidrome-platform`

The `argo-workflow` ServiceAccount is used by CronWorkflows (train, finetune) and has the `finetune-deploy` ClusterRole via `argo-workflow-finetune-deploy` binding.

---

## Operational Runbook

### Connect to the cluster

```bash
# SSH tunnel (run once, keep in background)
nohup ssh -i ~/.ssh/id_rsa_chameleon -o StrictHostKeyChecking=no \
  -o ServerAliveInterval=30 -L 6443:127.0.0.1:6443 \
  -N cc@129.114.27.204 > /dev/null 2>&1 &

# Fetch kubeconfig
ssh -i ~/.ssh/id_rsa_chameleon cc@129.114.27.204 "cat ~/.kube/config" \
  > /tmp/navidrome-kubeconfig
export KUBECONFIG=/tmp/navidrome-kubeconfig

# Verify
kubectl get nodes
```

### Check disk health

```bash
# On the node
ssh -i ~/.ssh/id_rsa_chameleon cc@129.114.27.204 "df -h / /mnt/music-vol"

# Root disk breakdown (excluding bind mounts)
sudo du -shx /var/lib/docker/containers /var/lib/kubelet/pods \
  /opt/local-path-provisioner /usr /tmp 2>/dev/null | sort -rh
```

### Registry maintenance

```bash
# Check registry contents
kubectl exec -n kube-system <registry-pod> -- \
  sh -c "wget -qO- http://localhost:5000/v2/_catalog"

# Run garbage collection (safe to run anytime)
kubectl exec -n kube-system <registry-pod> -- \
  registry garbage-collect /etc/docker/registry/config.yml
```

### If a pod is in CrashLoopBackOff

```bash
# Check logs
kubectl logs -n <namespace> <pod> --previous

# Common causes:
# - MinIO bucket missing → check double-nesting in /mnt/music-vol/pvc-storage/pvc-*_minio-pvc/
# - PVC mounted at wrong path → kubectl describe pod <pod>
# - Image not in registry → argo submit --from workflowtemplate/build-serve -n argo
```

### If Docker overlay2 bind mount is missing after reboot

```bash
# Should be in /etc/fstab — verify:
grep docker-overlay2 /etc/fstab

# Re-mount manually if needed:
sudo mount --bind /mnt/music-vol/docker-overlay2 /var/lib/docker/overlay2
sudo systemctl restart docker
```

---

## Security

- Secrets are never stored in Git — apply with `kubectl create secret` after provisioning
- All Chameleon resources are named with `-proj05` suffix per course policy
- Registry is in-cluster only (`registry.kube-system.svc.cluster.local:5000`), not exposed externally

---

## AI Disclosure

Infrastructure code and configurations in this repository were developed with assistance from Claude (Anthropic) as an implementation tool. All design decisions, architecture choices, and tradeoffs were made by the team. AI assistance was used to accelerate implementation of IaC patterns (Terraform, Ansible, Helm, Kubernetes manifests) based on the team's specifications.

Per course policy: *"You tell the LLM what to do, based on the design you developed."*
