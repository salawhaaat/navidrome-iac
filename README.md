# navidrome-iac

Infrastructure-as-code for the Navidrome MLOps course project (ECE-GY 9183).
Provisions a single-node Kubernetes cluster on Chameleon Cloud (KVM@TACC) and deploys
Navidrome + MLflow + PostgreSQL + MinIO as the shared platform for the team.

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full component diagram.

---

## Repo Layout

```
tf/kvm/               Terraform — VM, network, floating IP, security groups
ansible/
  pre_k8s/            Node prep (firewalld, Docker registry)
  k8s/kubespray/      Kubespray submodule — Kubernetes install
  k8s/inventory/      Kubespray inventory (single node)
  post_k8s/           Post-install (kubectl, ArgoCD, Argo Workflows/Events)
k8s/platform/         Helm chart — Navidrome, MLflow, PostgreSQL, MinIO
workflows/            Argo WorkflowTemplates (ML train/serve pipelines)
Makefile              Full deploy automation
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

```bash
# 1. Provision VM + network + security groups
make infra RESERVATION_ID=<blazar-reservation-uuid>

# Export IPs automatically from Terraform
export FLOATING_IP=$(terraform -chdir=tf/kvm output -raw floating_ip_out)

# 2-4. Bootstrap Kubernetes (pre-k8s → kubespray → post-k8s)
make pre-k8s k8s post-k8s

# 5. Fetch kubeconfig + start SSH tunnel
make kubeconfig
ssh -i ~/.ssh/id_rsa_chameleon -L 6443:127.0.0.1:6443 -N cc@$FLOATING_IP &

# 6. Create secrets (never stored in Git)
KUBECONFIG=/tmp/navidrome-kubeconfig kubectl create secret generic postgres-credentials \
  --from-literal=username=navidrome \
  --from-literal=password=<choose> \
  --from-literal=dbname=mlflow \
  --from-literal=navidrome_dbname=navidrome \
  -n navidrome-platform

KUBECONFIG=/tmp/navidrome-kubeconfig kubectl create secret generic minio-credentials \
  --from-literal=accesskey=minioadmin \
  --from-literal=secretkey=<choose> \
  -n navidrome-platform

# 7. Deploy platform services
make helm-install
```

After deploy, services are available at:

| Service | URL |
|---|---|
| Navidrome | `http://<FLOATING_IP>:4533` |
| MLflow | `http://<FLOATING_IP>:8000` |
| MinIO console | `http://<FLOATING_IP>:9001` |

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

AI-assisted files are noted in [.claude/](.claude/).
