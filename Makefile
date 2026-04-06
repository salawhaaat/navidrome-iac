RESERVATION_ID ?= $(error Set RESERVATION_ID: make <target> RESERVATION_ID=<uuid>)
KUBESPRAY_DIR  := ansible/k8s/kubespray
VENV           := $(KUBESPRAY_DIR)/kubespray-venv
VENV_ANSIBLE   := $(VENV)/bin/ansible-playbook
KUBECONFIG     := /tmp/navidrome-kubeconfig

# Derive IPs from Terraform output (after apply)
FLOATING_IP    := $(shell terraform -chdir=tf/kvm output -raw floating_ip_out 2>/dev/null)
INTERNAL_IP    := $(shell terraform -chdir=tf/kvm output -raw node1_internal_ip_out 2>/dev/null)

.PHONY: all infra pre-k8s k8s post-k8s kubeconfig helm-install helm-upgrade deploy wait-ssh

## Full deploy from scratch
all: infra pre-k8s k8s post-k8s kubeconfig helm-install

## 1. Provision VM + floating IP + security group rules on KVM@TACC
infra:
	terraform -chdir=tf/kvm init -upgrade
	terraform -chdir=tf/kvm apply -auto-approve -var="reservation_id=$(RESERVATION_ID)"

## 2. Pre-K8s: disable firewalld, configure Docker registry
pre-k8s: wait-ssh
	ansible-playbook -i ansible/inventory.yml ansible/pre_k8s/pre_k8s_configure.yml \
		-e "jump_host=$(FLOATING_IP)"

## 3. Install Kubernetes via kubespray (uses pinned ansible in venv)
k8s: $(VENV_ANSIBLE)
	cd $(KUBESPRAY_DIR) && $(abspath $(VENV_ANSIBLE)) \
		-i ../inventory/mycluster/hosts.yaml cluster.yml \
		-e "jump_host=$(FLOATING_IP)"

## 4. Post-K8s: kubectl, ArgoCD, Argo Workflows
post-k8s: wait-ssh
	ansible-playbook -i ansible/inventory.yml ansible/post_k8s/post_k8s_configure.yml \
		-e "jump_host=$(FLOATING_IP)"

## 5. Fetch kubeconfig from node and patch to use tunnel
kubeconfig:
	ssh -i ~/.ssh/id_rsa_chameleon -o StrictHostKeyChecking=no cc@$(FLOATING_IP) \
		"cat ~/.kube/config" > $(KUBECONFIG)
	@echo "Kubeconfig saved to $(KUBECONFIG)"
	@echo "Start SSH tunnel before using helm/kubectl locally:"
	@echo "  ssh -i ~/.ssh/id_rsa_chameleon -L 6443:127.0.0.1:6443 -N cc@$(FLOATING_IP) &"

## 6. Install platform Helm chart
helm-install:
	KUBECONFIG=$(KUBECONFIG) helm install navidrome-platform ./k8s/platform \
		--namespace navidrome-platform \
		--set navidrome.externalIP=$(INTERNAL_IP) \
		--set minio.externalIP=$(INTERNAL_IP) \
		--set mlflow.externalIP=$(INTERNAL_IP) \
		--set gateway.externalIP=$(INTERNAL_IP)

## Upgrade platform Helm chart (use after config changes)
helm-upgrade:
	KUBECONFIG=$(KUBECONFIG) helm upgrade navidrome-platform ./k8s/platform \
		--namespace navidrome-platform \
		--set navidrome.externalIP=$(INTERNAL_IP) \
		--set minio.externalIP=$(INTERNAL_IP) \
		--set mlflow.externalIP=$(INTERNAL_IP) \
		--set gateway.externalIP=$(INTERNAL_IP)

## Create kubespray venv with pinned ansible version
$(VENV_ANSIBLE):
	python3 -m venv $(VENV)
	$(VENV)/bin/pip install -q -r $(KUBESPRAY_DIR)/requirements.txt

## Wait for SSH to be ready (handles post-kubespray reboot)
wait-ssh:
	@echo "Waiting for SSH on $(FLOATING_IP)..."
	@until ssh -i ~/.ssh/id_rsa_chameleon -o StrictHostKeyChecking=no \
		-o ConnectTimeout=5 cc@$(FLOATING_IP) true 2>/dev/null; do \
		sleep 5; \
	done
	@echo "SSH ready."
