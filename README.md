# navidrome-iac

Infrastructure-as-code for the Navidrome MLOps course project (ECE-GY 9183).

Provisions a Kubernetes cluster on Chameleon Cloud (KVM@TACC) and deploys:
- **Navidrome** — music server with ML recommendation engine
- **MLflow** — model registry and experiment tracking
- **PostgreSQL** — shared database (MLflow + Navidrome)
- **MinIO** — S3-compatible object storage
- **Redis** — cache (sessions, embeddings, features)
- **Prometheus + Grafana + Alertmanager** — monitoring and alerting
- **HPA** — autoscaling for MLflow and Navidrome

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the service map and resource requirements.
See [docs/SAFEGUARDING.md](docs/SAFEGUARDING.md) for the safeguarding plan.

---

## Repo Layout

```
tf/kvm/                 Terraform — VMs, networks, floating IP, security groups
ansible/
  pre_k8s/              Node prep (firewalld, Docker registry)
  k8s/kubespray/        Kubespray submodule — Kubernetes install
  k8s/inventory/        Kubespray inventory
  post_k8s/             Post-install (kubectl, ArgoCD, Argo Workflows/Events)
k8s/
  platform/             Helm chart — Navidrome, MLflow, PostgreSQL, MinIO, Redis, HPA
  monitoring/           Helm chart — Prometheus, Grafana, Alertmanager, NVIDIA plugin
  staging/              Staging env deployment
  canary/               Canary env deployment
  production/           Production env deployment
workflows/              Argo WorkflowTemplates (train, build, test, promote, GPU)
docs/                   Architecture, safeguarding plan
Makefile                Full deploy automation
```

---

## Prerequisites

```bash
# Install dependencies
brew install terraform ansible helm

# OpenStack credentials for KVM@TACC
# Place your clouds.yaml at ~/.config/openstack/clouds.yaml

# SSH key registered on Chameleon
# Default expected at ~/.ssh/id_rsa_chameleon
```

---

## Deploy

**TL;DR:**
```bash
# 1. Get Blazar lease IDs
export RESERVATION_ID="<cpu-lease-uuid>"
export GPU_RESERVATION_ID="<gpu-lease-uuid>"  # optional

# 2. Deploy entire system (takes ~90 min)
make all RESERVATION_ID=$RESERVATION_ID GPU_RESERVATION_ID=$GPU_RESERVATION_ID

# 3. Export IPs and verify
export FLOATING_IP=$(terraform -chdir=tf/kvm output -raw floating_ip_out)
kubectl cluster-info
kubectl get pods -A
```

**Full instructions:** See [DEPLOYMENT.md](DEPLOYMENT.md)

After deploy, services are available at:

| Service | URL | Purpose |
|---------|-----|---------|
| Navidrome | `http://$INTERNAL_IP:4533` | 🎵 Music server + recommendations |
| MLflow | `http://$INTERNAL_IP:8000` | 🤖 Model registry & tracking |
| MinIO | `http://$INTERNAL_IP:9001` | 📦 S3-compatible object storage |
| Prometheus | `http://$INTERNAL_IP:9090` | 📊 Metrics collection |
| Grafana | `http://$INTERNAL_IP:3000` | 📈 Dashboards (admin/admin) |
| Alertmanager | `http://$INTERNAL_IP:9093` | 🚨 Alert routing |

**GPU Support (optional):**
```bash
# If GPU_RESERVATION_ID set:
kubectl label nodes node3 gpu=true
make gpu-plugin

# Submit GPU training job:
argo submit -n argo --from workflowtemplate/train-model-gpu
```

---

## Security

- Secrets are never stored in Git — apply with `kubectl create secret` after provisioning
- All Chameleon resources are named with `-proj05` suffix as required by course policy

---

## AI Disclosure

Infrastructure code and configurations in this repository were developed with assistance
from Claude (Anthropic) as an implementation tool. All design decisions, architecture
choices, and tradeoffs were made by the author. AI assistance was used to accelerate
implementation of IaC patterns (Terraform, Ansible, Helm, Kubernetes manifests) based
on the author's specifications.

Per course policy: *"You tell the LLM what to do, based on the design you developed."*

Commits that include AI-generated code note this in the commit message.
