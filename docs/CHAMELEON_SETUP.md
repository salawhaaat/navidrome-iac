# Chameleon Reservation Guide — Navidrome Setup

## Your Strategy: Single Node + Occasional GPU

This is the **optimal approach** for a course project:
- ✅ **Single m1.xlarge node** (always running) — hosts all platform services
- ✅ **GPU node on-demand** (request only during retraining) — save costs
- ✅ **Cost-efficient:** ~$15-20/week baseline, +$5/day when GPU needed
- ✅ **Flexible:** No long-term GPU lease, use only when needed

---

## STEP 1: Choose Region

**Available Chameleon Sites:**

| Site | Location | Best For | Resource Availability |
|------|----------|----------|----------------------|
| **KVM@TACC** | Texas (Austin) | General purpose, stable | Good (recommended) |
| KVM@CHI | Chicago | Lower latency (US East) | Good |
| Bare Metal@TACC | Texas | GPU, high-performance | Limited |

**Recommendation:** `KVM@TACC` (what you've been using) — reliable, good availability

---

## STEP 2: Reserve Control-Plane Node (Always-On)

**Duration:** 7+ days (duration of course, until Apr 27+)

### Via Chameleon Web UI:

1. Go to: https://chi.tacc.chameleoncloud.org/
2. **Leases** → **Create Lease**
3. Fill in:
   ```
   Lease Name:        navidrome-control-plane-proj05
   Resource Type:     Compute (KVM)
   Location:          TACC (KVM@TACC)
   Flavor:            m1.xlarge
   Node Count:        1
   Start Time:        Now
   Duration:          7 days (or until Apr 27)
   
   → Click "Create Lease"
   ```
4. **Status** → Wait until **ACTIVE** (blue checkmark)
5. **Copy Reservation ID** (UUID format like `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`)

**Save this ID:**
```bash
export CONTROL_PLANE_RESERVATION_ID="<paste-here>"
```

**Resource details:**
- 16 CPU cores
- 32 GB RAM
- 160 GB local storage
- Sufficient for: Navidrome + MLflow + PostgreSQL + MinIO + Redis + Monitoring

---

## STEP 3: Reserve GPU Node (On-Demand, Only During Retraining)

**Duration:** 1-2 days (only when training models)

### Same process, but different flavor:

1. **Leases** → **Create Lease** (again)
2. Fill in:
   ```
   Lease Name:        navidrome-gpu-training-proj05
   Resource Type:     Compute (GPU - Bare Metal)
   Location:          TACC
   Flavor:            gpu_v100
   Node Count:        1
   Start Time:        [When you start training]
   Duration:          2 days
   
   → Click "Create Lease"
   ```

**Cost:** ~$5-10/day (only pay when GPU lease is active)

**When to reserve GPU:**
- Week of April 14-20: Reserve 2-3 days for initial training runs
- Week of April 20-27: Reserve as needed for retraining
- After Apr 27: Delete lease to stop costs

---

## STEP 4: Check Security Groups (Pre-Requisite)

Before deploying, verify these security groups exist on Chameleon:

1. Go to: **Network** → **Security Groups**
2. Verify these exist (if not, create them):
   - `allow-ssh` (port 22 inbound from anywhere)
   - `navidrome-sg-proj05` (ports: 4533, 8000, 9000, 9001, 3000, 9090, 9093)

**Note:** Default is usually there; `allow-ssh` and custom SG may need creation

Get their **IDs** for deployment:

```bash
openstack security group list --format table -c ID -c Name

# Example output:
# +----------------------------------+---------------------+
# | ID                               | Name                |
# +----------------------------------+---------------------+
# | 12345678-1234-1234-1234-123456   | default             |
# | 87654321-4321-4321-4321-456789   | allow-ssh           |
# | abcdef00-abcd-ef00-abcd-ef000000 | navidrome-sg-proj05 |
# +----------------------------------+---------------------+

export SG_DEFAULT_ID="12345678-1234-1234-1234-123456"
export SG_SSH_ID="87654321-4321-4321-4321-456789"
export SG_NAVIDROME_ID="abcdef00-abcd-ef00-abcd-ef000000"
```

---

## STEP 5: Deploy Control-Plane (Now)

```bash
# 1. Set variables
export RESERVATION_ID="$CONTROL_PLANE_RESERVATION_ID"
export GPU_RESERVATION_ID=""  # Leave empty for now

export SG_DEFAULT_ID="<from-step-4>"
export SG_SSH_ID="<from-step-4>"
export SG_NAVIDROME_ID="<from-step-4>"

# 2. Clone navidrome-iac if not already done
git clone https://github.com/<org>/navidrome-iac.git
cd navidrome-iac

# 3. Create terraform.tfvars
cat > tf/kvm/terraform.tfvars <<EOF
reservation_id = "$RESERVATION_ID"
gpu_reservation_id = ""
sg_default_id = "$SG_DEFAULT_ID"
sg_ssh_id = "$SG_SSH_ID"
sg_navidrome_id = "$SG_NAVIDROME_ID"
EOF

# 4. Deploy (takes ~90 min)
make all RESERVATION_ID=$RESERVATION_ID

# Watch progress:
# ├─ Terraform (5 min)
# ├─ Ansible pre-k8s (5 min)
# ├─ Kubespray install (30-40 min) ☕
# ├─ Ansible post-k8s (5 min)
# ├─ Helm platform install (5 min)
# └─ Helm monitoring install (5 min)
```

**When done:**
```bash
# Get IPs
export FLOATING_IP=$(terraform -chdir=tf/kvm output -raw floating_ip_out)
export INTERNAL_IP=$(terraform -chdir=tf/kvm output -raw node1_internal_ip_out)

echo "Floating IP (external): $FLOATING_IP"
echo "Internal IP (services): $INTERNAL_IP"

# Verify services running
kubectl get pods -A | grep Running
```

---

## STEP 6: Deploy GPU Node (Only When Needed)

**When:** Week of Apr 14-20 (or whenever you're training models)

### 6a. Create GPU Lease

Same as Step 3, but activate it when you need GPU

### 6b. Update navidrome-iac for GPU

```bash
# Get the GPU reservation ID from Chameleon UI
export GPU_RESERVATION_ID="<gpu-lease-id>"

# Update terraform
cat > tf/kvm/terraform.tfvars <<EOF
reservation_id = "$RESERVATION_ID"
gpu_reservation_id = "$GPU_RESERVATION_ID"
sg_default_id = "$SG_DEFAULT_ID"
sg_ssh_id = "$SG_SSH_ID"
sg_navidrome_id = "$SG_NAVIDROME_ID"
EOF

# Re-provision with GPU
cd tf/kvm
terraform plan  # Review changes
terraform apply

# Install GPU support
cd ../..
make setup-gpu
```

### 6c. Run Training Job

```bash
# Submit GPU training workflow
argo submit -n argo --from workflowtemplate/train-model-gpu

# Watch progress
argo logs -n argo <workflow-id> -f

# Monitor GPU
kubectl exec -it <gpu-job-pod> -- nvidia-smi
```

### 6d. Delete GPU Lease (After Training)

```bash
# Via Chameleon UI: Leases → <gpu-lease> → Delete
# (Or via CLI: openstack lease delete <gpu-lease-id>)

# Update terraform to remove GPU
cat > tf/kvm/terraform.tfvars <<EOF
reservation_id = "$RESERVATION_ID"
gpu_reservation_id = ""  # Clear GPU
sg_default_id = "$SG_DEFAULT_ID"
sg_ssh_id = "$SG_SSH_ID"
sg_navidrome_id = "$SG_NAVIDROME_ID"
EOF

terraform apply

# System continues on CPU only
```

---

## Timeline & Cost Estimate

### Week 1 (Apr 7-13): Initial Setup
- **Reservation:** Control-plane (m1.xlarge) - 7 days
- **Cost:** ~$15-20
- **Activity:** Deploy infrastructure, verify services running

### Week 2 (Apr 14-20): Initial Training
- **Reservation:** Control-plane (7 days) + GPU (2-3 days on-demand)
- **Cost:** ~$25-30 (control-plane) + $10-15 (GPU)
- **Activity:** Submit training workflows, iterate on model

### Week 3 (Apr 20-27): System Implementation
- **Reservation:** Control-plane (7 days) + GPU (as-needed, 1-2 days)
- **Cost:** ~$30-35 total
- **Activity:** Final training runs, monitoring, demo recording

### AFTER Apr 27: Cleanup
- **Delete GPU lease** (if not already done)
- **Keep control-plane for production demo** until submission deadline
- **Delete control-plane after feedback period** (May 4)

**Total Cost:** ~$80-100 for 4 weeks (very reasonable for a course project)

---

## Quick Reference: What Each Node Does

### Control-Plane Node (Always Running)

```
Host Everything:
  - Kubernetes master (API, scheduler, etcd)
  - Navidrome music server
  - MLflow model registry
  - PostgreSQL database
  - MinIO object storage
  - Redis cache
  - Prometheus monitoring
  - Grafana dashboards
  - Argo Workflows
  - ArgoCD

Access:
  http://<floating-ip>:4533     (Navidrome)
  http://<floating-ip>:8000     (MLflow)
  http://<floating-ip>:9090     (Prometheus)
  http://<floating-ip>:3000     (Grafana)
```

### GPU Node (On-Demand, Occasional)

```
Used For:
  - Model training (GPU-accelerated)
  - Batch inference (if needed)
  - Data preprocessing (optional)

Not used for:
  - Serving (inference can run on CPU)
  - Session caching (Redis handles this)
  - Monitoring (runs on control-plane)

Reserve only when:
  - You're ready to train
  - You have training data ready
  - You want to test model performance
```

---

## Deployment Checklist

```
BEFORE RESERVING:
[ ] Have Chameleon account with project set up
[ ] SSH key registered on Chameleon
[ ] OpenStack credentials downloaded (~/.config/openstack/clouds.yaml)
[ ] Local tools installed: terraform, ansible, helm, kubectl

CONTROL-PLANE RESERVATION:
[ ] Reserve m1.xlarge at KVM@TACC, 7 days
[ ] Get Reservation ID (UUID)
[ ] Verify security groups exist
[ ] Get security group IDs

DEPLOYMENT:
[ ] Export RESERVATION_ID, security group IDs
[ ] Create terraform.tfvars
[ ] Run: make all RESERVATION_ID=...
[ ] Wait ~90 min
[ ] Get floating IP and internal IP
[ ] Verify services running: kubectl get pods -A

TESTING:
[ ] Access Navidrome at http://<floating-ip>:4533
[ ] Access MLflow at http://<floating-ip>:8000
[ ] Access Prometheus at http://<floating-ip>:9090
[ ] Test Redis: kubectl exec redis-xxx -- redis-cli PING

FOR GPU (Later):
[ ] Create gpu_v100 lease when ready to train
[ ] Export GPU_RESERVATION_ID
[ ] Run: make setup-gpu
[ ] Submit training: argo submit -n argo --from workflowtemplate/train-model-gpu
[ ] Delete GPU lease when done
```

---

## Troubleshooting

### Lease Not Available
```
Error: "No available nodes matching your request"
→ Try different site (KVM@CHI instead of KVM@TACC)
→ Reduce node count (try 1 instead of 2)
→ Wait 30 min and retry (leases become available)
```

### Reservation ID is Blazar, Not Flavor ID
```
Q: Is the reservation_id the Blazar lease ID or flavor ID?
A: Blazar lease ID (UUID). Terraform uses it as flavor_id automatically.
```

### GPU Node Not Joining Cluster
```
# Check GPU node status
kubectl get nodes

# Label GPU node manually if needed
kubectl label nodes node3 gpu=true

# Check NVIDIA driver
ssh -i ~/.ssh/id_rsa_chameleon cc@<internal-ip-node3>
nvidia-smi  # Should show V100 GPU
```

### Services Not Accessible
```
# Check if services are running
kubectl get pods -n navidrome-platform

# Check floating IP is attached
openstack server list | grep node1-mlops
# Should show floating IP in address field

# Check security groups allow traffic
openstack security group rule list | grep 4533
```

---

## Summary

| Item | What to Do |
|------|-----------|
| **Region** | KVM@TACC (what you've been using) |
| **Control-Plane Node** | m1.xlarge (1 node, always-on, 7+ days) |
| **GPU Node** | gpu_v100 (1 node, on-demand, 1-2 days when needed) |
| **Reservation Duration** | Control-plane: week-long; GPU: 2-3 days (repeat as needed) |
| **Total Cost** | ~$80-100 for 4 weeks (control-plane + occasional GPU) |
| **Deployment Time** | ~90 min (automated via Makefile) |
| **Services Running** | 16 core services (music, ML, monitoring, caching) |

---

**You're ready to deploy! 🚀**

Next steps:
1. Go to Chameleon UI → create m1.xlarge lease for 7 days
2. Get Reservation ID + security group IDs
3. Run `make all RESERVATION_ID=...`
4. Wait 90 min
5. Access services via floating IP

Questions about any step? The entire setup is automated in the Makefile!
