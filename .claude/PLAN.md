# Navidrome IaC — Completion Plan

Work through each phase in order. Steps marked **[YOU]** require manual action.
Steps marked **[CODE]** are already done in the repo.

---

## PHASE 1 — Chameleon Auth (15 min)

### 1.1 Get clouds.yaml [YOU]
1. Go to https://chi.tacc.chameleoncloud.org → login
2. Top-right → your username → **OpenStack RC File** → download
3. Save as `~/.config/openstack/clouds.yaml`
4. Make sure the cloud name inside is `openstack` (matches `tf/kvm/provider.tf`)

### 1.2 Verify CLI works [YOU]
```bash
pip install python-openstackclient   # if not installed
openstack flavor list
```
Expected: list of flavors. If auth error, check `clouds.yaml`.

### 1.3 Get flavor UUIDs [YOU]
```bash
openstack flavor list --format table -c ID -c Name | grep -E "m1.large|m1.xlarge"
```
Note two UUIDs: one for `m1.large`, one for `m1.xlarge`.

### 1.4 Verify security groups exist [YOU]
```bash
openstack security group list --format value -c Name
```
You must see ALL of these: `allow-ssh`, `allow-http-80`, `allow-8000`,
`allow-8080`, `allow-8081`, `allow-8082`, `allow-9001`, `allow-9090`

If any are missing, create them in Horizon UI:
Network → Security Groups → Create Security Group → add ingress rule for that port.

---

## PHASE 2 — Terraform (15 min)

### 2.1 Apply [YOU]
```bash
cd tf/kvm
terraform init
terraform apply -var="reservation_id=<your-blazar-reservation-id>"
```

### 2.2 Note outputs [YOU]
After apply completes, note:
- `floating_ip_out` — your public IP (e.g. `129.114.x.x`)
- `minio_volume_id` — Cinder volume attached to node3

### 2.3 Update floating IP in inventory files [YOU]
In **two files**, replace `FLOATING_IP_HERE` with your actual floating IP:
- `ansible/inventory.yml`
- `ansible/k8s/inventory/mycluster/hosts.yaml`

### 2.4 Update externalIP in Helm values [YOU]
Edit `k8s/platform/values.yaml` — replace all `0.0.0.0` with your floating IP:
```yaml
navidrome:
  externalIP: "129.114.x.x"   # your floating IP
minio:
  externalIP: "129.114.x.x"
mlflow:
  externalIP: "129.114.x.x"
gateway:
  externalIP: "129.114.x.x"
```

---

## PHASE 3 — Ansible (45 min total, mostly waiting)

Run all commands from repo root. SSH key must be loaded (`ssh-add ~/.ssh/id_rsa_chameleon`).

### 3.1 Node prep (~5 min) [YOU]
```bash
ansible-playbook -i ansible/inventory.yml ansible/pre_k8s/pre_k8s_configure.yml
```

### 3.2 Kubernetes install (~30 min) [YOU]
```bash
ansible-playbook -i ansible/k8s/inventory/mycluster/hosts.yaml \
  ansible/k8s/kubespray/cluster.yml
```
Go get coffee. This takes ~25-30 min.

### 3.3 Post-K8s setup (~5 min) [YOU]
```bash
ansible-playbook -i ansible/inventory.yml ansible/post_k8s/post_k8s_configure.yml
```
This will:
- Copy kubeconfig to `~/.kube/config` on node1/node2
- Install ArgoCD CLI
- Install Argo Workflows + Argo Events
- Print ArgoCD admin password — **save it**

---

## PHASE 4 — Secrets (5 min)

SSH into node1 first:
```bash
ssh -J cc@<FLOATING_IP> cc@192.168.1.11
```

### 4.1 Create namespace [YOU]
```bash
kubectl create namespace navidrome-platform
```

### 4.2 Create postgres-credentials secret [YOU]
```bash
kubectl create secret generic postgres-credentials \
  --from-literal=username=postgres \
  --from-literal=password=<choose-a-password> \
  --from-literal=dbname=mlflow \
  --from-literal=navidrome_dbname=navidrome \
  -n navidrome-platform
```

### 4.3 Create minio-credentials secret [YOU]
```bash
kubectl create secret generic minio-credentials \
  --from-literal=accesskey=minioadmin \
  --from-literal=secretkey=<choose-a-password> \
  -n navidrome-platform
```

---

## PHASE 5 — ArgoCD + Platform Deploy (10 min)

### 5.1 Add ArgoCD apps [YOU]
```bash
ansible-playbook -i ansible/inventory.yml ansible/argocd/argocd_add_platform.yml
```

### 5.2 Watch sync [YOU]
```bash
kubectl get pods -n navidrome-platform -w
```
Wait until all pods are `Running`. Should see:
- `navidrome-*`
- `mlflow-*`
- `postgres-*`
- `minio-*`
- `traefik-*` (or gateway)

### 5.3 Verify services are reachable [YOU]
- Navidrome: `http://<FLOATING_IP>:4533`
- MLflow: `http://<FLOATING_IP>:8000`
- MinIO console: `http://<FLOATING_IP>:9001`

---

## PHASE 6 — Extra Credit: Sealed Secrets (20 min)

### 6.1 Install Sealed Secrets controller [YOU]
```bash
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.27.0/controller.yaml
```

### 6.2 Install kubeseal CLI [YOU]
```bash
brew install kubeseal
```

### 6.3 Seal postgres-credentials [YOU]
```bash
kubectl create secret generic postgres-credentials \
  --from-literal=username=postgres \
  --from-literal=password=<your-password> \
  --from-literal=dbname=mlflow \
  --from-literal=navidrome_dbname=navidrome \
  -n navidrome-platform \
  --dry-run=client -o yaml \
  | kubeseal --format yaml \
  > k8s/platform/templates/postgres-sealed-secret.yaml
```

### 6.4 Seal minio-credentials [YOU]
```bash
kubectl create secret generic minio-credentials \
  --from-literal=accesskey=minioadmin \
  --from-literal=secretkey=<your-password> \
  -n navidrome-platform \
  --dry-run=client -o yaml \
  | kubeseal --format yaml \
  > k8s/platform/templates/minio-sealed-secret.yaml
```

### 6.5 Commit sealed secrets to git [YOU]
```bash
git add k8s/platform/templates/postgres-sealed-secret.yaml
git add k8s/platform/templates/minio-sealed-secret.yaml
git commit -m "feat: add sealed secrets for postgres and minio credentials"
git push
```
ArgoCD will now deploy secrets automatically on every sync — no manual `kubectl create secret` needed.

---

## PHASE 7 — Navidrome Fork

Fork: https://github.com/yeshavyas27/navidrome_mlops (already has Dockerfile)

### 7.1 Image in navidrome.yaml [CODE — already done]
Image is set to `registry.kube-system.svc.cluster.local:5000/navidrome-custom:latest`

### 7.2 Add build workflow for custom Navidrome [YOU]
After cluster is up, run a one-time build to push the fork image to the in-cluster registry:
```bash
# SSH into node1, then:
docker build https://github.com/yeshavyas27/navidrome_mlops.git \
  -t registry.kube-system.svc.cluster.local:5000/navidrome-custom:latest
docker push registry.kube-system.svc.cluster.local:5000/navidrome-custom:latest
```

### 7.3 Add to Argo CronWorkflow [TODO — optional for now]
Add a rebuild step for navidrome-custom to the existing ML pipeline WorkflowTemplate
so the image rebuilds automatically when the fork changes.

---

## PHASE 8 — Screenshots + Videos (30 min)

### 8.1 Infrastructure table screenshot [YOU]
```bash
kubectl top pods -n navidrome-platform
```
Screenshot this output — needed for Q2.1 PDF.

### 8.2 Video 1: Navidrome demo (Q2.3) [YOU]
Record (sped up):
1. `kubectl get pods -n navidrome-platform` — show all running
2. Open browser → `http://<FLOATING_IP>:4533` — show Navidrome UI
3. Create a user, show it's functional

### 8.3 Video 2: Platform services demo (Q2.4) [YOU]
Record (sped up):
1. `kubectl get pods -n navidrome-platform` — show all running
2. `kubectl get pvc -n navidrome-platform` — show persistent volumes bound
3. Open browser → `http://<FLOATING_IP>:8000` — show MLflow
4. Open browser → `http://<FLOATING_IP>:9001` — show MinIO console
5. Restart a pod (`kubectl rollout restart deployment/postgres -n navidrome-platform`)
6. Show data persists after restart

### 8.4 Extra credit video (Q3) [YOU]
Record (sped up):
1. Show `postgres-sealed-secret.yaml` in git — encrypted, safe to commit
2. Delete the secret: `kubectl delete secret postgres-credentials -n navidrome-platform`
3. ArgoCD sync: `argocd app sync navidrome-platform`
4. Show secret is recreated automatically: `kubectl get secret postgres-credentials -n navidrome-platform`
5. Show pods still running — no manual intervention needed

---

## PHASE 9 — Submission PDFs (30 min)

### 9.1 Q1 Container table PDF [YOU]
Create a table with these columns: **Container | Role | Dockerfile | K8s Manifest**

| Container | Role | Dockerfile | K8s Manifest |
|-----------|------|------------|--------------|
| navidrome-custom | Music server + new recommendations page | navidrome fork /Dockerfile | k8s/platform/templates/navidrome.yaml |
| mlflow | ML experiment tracking + model registry | ghcr.io/mlflow/mlflow (upstream) | k8s/platform/templates/mlflow.yaml |
| postgres | Shared DB for MLflow + Navidrome playlists | docker.io/postgres:18 (upstream) | k8s/platform/templates/postgres.yaml |
| minio | Object store for datasets + model artifacts | minio/minio (upstream) | k8s/platform/templates/minio.yaml |
| traefik | Ingress gateway | upstream | k8s/platform/templates/gateway.yaml |
| navidrome-serve | Recommendation inference + playlist writer | navidrome-serve repo /Dockerfile | (Job manifest — team to provide) |
| navidrome-train | BPR-MF + BPR-kNN training | navidrome-train repo /Dockerfile | workflows/ Argo WorkflowTemplate |

Save as PDF.

### 9.2 Q2.1 Infrastructure requirements PDF [YOU]
Table with CPU/mem requests+limits per service (from manifests) + `kubectl top pods` screenshot as evidence.

### 9.3 Q2.2 Zip repo + write bring-up steps [YOU]
```bash
cd ..
zip -r navidrome-iac.zip navidrome-iac/ --exclude "*.tfstate*" --exclude ".terraform/*"
```

Bring-up steps text (paste into submission text field):
```
1. terraform apply -var="flavor_default=<uuid>" -var="flavor_xlarge=<uuid>"
2. Update FLOATING_IP_HERE in ansible/inventory.yml and ansible/k8s/inventory/mycluster/hosts.yaml
3. Update externalIP values in k8s/platform/values.yaml
4. ansible-playbook -i ansible/inventory.yml ansible/pre_k8s/pre_k8s_configure.yml
5. ansible-playbook -i ansible/k8s/inventory/mycluster/hosts.yaml ansible/k8s/kubespray/cluster.yml
6. ansible-playbook -i ansible/inventory.yml ansible/post_k8s/post_k8s_configure.yml
7. kubectl create namespace navidrome-platform
8. kubectl create secret generic postgres-credentials --from-literal=username=postgres --from-literal=password=<pass> --from-literal=dbname=mlflow --from-literal=navidrome_dbname=navidrome -n navidrome-platform
9. kubectl create secret generic minio-credentials --from-literal=accesskey=minioadmin --from-literal=secretkey=<pass> -n navidrome-platform
10. ansible-playbook -i ansible/inventory.yml ansible/argocd/argocd_add_platform.yml
```

---

## Summary Checklist

- [ ] Phase 1: clouds.yaml + flavor UUIDs + security groups verified
- [ ] Phase 2: terraform apply + floating IP noted + values.yaml updated
- [ ] Phase 3: all 3 ansible playbooks complete
- [ ] Phase 4: secrets created on cluster
- [ ] Phase 5: all pods Running, services reachable in browser
- [ ] Phase 6: Sealed Secrets installed + sealed YAMLs committed to git
- [ ] Phase 7: coordinate with team on navidrome fork + image
- [ ] Phase 8: screenshots + 2 demo videos (+ extra credit video) recorded
- [ ] Phase 9: 3 PDFs + repo zip ready to upload
