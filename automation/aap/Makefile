# Single entrypoint for the AAP PoC. Run `make help` for the list of targets.
SHELL := /bin/bash
.DEFAULT_GOAL := help

-include .env
export

# Red Hat Automation Hub token for certified/validated collections (see ansible.cfg).
export ANSIBLE_GALAXY_SERVER_RH_CERTIFIED_TOKEN := $(AH_TOKEN)
export ANSIBLE_GALAXY_SERVER_RH_VALIDATED_TOKEN := $(AH_TOKEN)

VENV := .venv
ACT  := source $(VENV)/bin/activate &&

.PHONY: help venv lint check-secrets bootstrap destroy-all tf-init tf-test up down plan allow-my-ip start stop ssh-aap outputs

TF_DIR    := infra/terraform
SSH_KEY   := $(subst ~,$(HOME),$(SSH_KEY_PATH))
VMS       := aap-01 rhel-dev-01 rhel-prod-01 ubu-dev-01
# Terraform authenticates with a short-lived token of the personal account (never ADC).
TF_AUTH   = GOOGLE_OAUTH_ACCESS_TOKEN="$$(gcloud auth print-access-token --account $(GCP_ACCOUNT))"
TF_VARS   = -var project_id=$(PROJECT_ID) -var region=$(REGION) -var zone=$(ZONE) \
            -var "admin_cidrs=$$(bash $(CURDIR)/scripts/admin-cidrs.sh)" -var ssh_public_key="$$(cat $(SSH_KEY).pub)"
GC        = --project $(PROJECT_ID) --zone $(ZONE) --account $(GCP_ACCOUNT)

bootstrap: ## One-shot: create GCP project, billing link, APIs, state bucket, budget
	bash bootstrap/bootstrap.sh

destroy-all: ## Delete the WHOLE GCP project (asks for typed confirmation)
	bash bootstrap/destroy-all.sh

help: ## List targets
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  %-18s %s\n",$$1,$$2}'

venv: ## Create local Python venv with ansible-core, linters and ansible-builder
	python3 -m venv $(VENV)
	$(ACT) pip install -q --upgrade pip && pip install -q -r requirements-dev.txt

check-secrets: ## Fail if a secret is tracked by git
	bash scripts/check-secrets.sh --self-test
	bash scripts/check-secrets.sh

lint: check-secrets ## Secret scan, YAML lint, ansible-lint, terraform fmt/tflint, inventory parity
	$(ACT) yamllint -s .
	$(ACT) bash tests/check-group-parity.sh
	@if ls playbooks roles >/dev/null 2>&1; then $(ACT) ansible-lint; else echo "ansible-lint: nothing to lint yet"; fi
	@if [ -d infra/terraform ]; then terraform fmt -check -recursive infra && (cd infra/terraform && tflint); else echo "terraform: nothing to lint yet"; fi

tf-init: ## terraform init against the GCS state bucket
	cd $(TF_DIR) && $(TF_AUTH) terraform init -input=false -backend-config="bucket=$(PROJECT_ID)-tfstate"

tf-test: ## Terraform security tests (mocked provider, no cloud calls)
	cd $(TF_DIR) && terraform init -backend=false -input=false >/dev/null && terraform test

plan: tf-init ## terraform plan
	cd $(TF_DIR) && $(TF_AUTH) terraform plan -input=false $(TF_VARS)

up: tf-init ## Create/update all PoC infrastructure (opens 443 to your current IP only)
	cd $(TF_DIR) && $(TF_AUTH) terraform apply -input=false -auto-approve $(TF_VARS)

down: tf-init ## Destroy PoC infrastructure (project and state bucket remain)
	cd $(TF_DIR) && $(TF_AUTH) terraform destroy -input=false -auto-approve $(TF_VARS)

allow-my-ip: tf-init ## Re-point the HTTPS firewall rule to your current public IP
	cd $(TF_DIR) && $(TF_AUTH) terraform apply -input=false -auto-approve $(TF_VARS) -target=google_compute_firewall.allow_https_admin

outputs: ## Show Terraform outputs
	@cd $(TF_DIR) && $(TF_AUTH) terraform output

start: ## Start all PoC VMs
	gcloud compute instances start $(VMS) $(GC)

stop: ## Stop all PoC VMs (disks keep billing, compute stops)
	gcloud compute instances stop $(VMS) $(GC)

ssh-aap: ## SSH into aap-01 through IAP
	bash scripts/iap-ssh.sh aap-01

verify-platform: ## Check every AAP component answers and a subscription is attached
	$(ACT) ANSIBLE_STDOUT_CALLBACK=default ansible-playbook -i localhost, tests/verify-platform.yml

install-aap: ## Launch the AAP containerized installer on aap-01 (detached)
	bash installer/install.sh start

install-status: ## Show progress of the AAP installer
	bash installer/install.sh status

install-finish: ## Post-install: shred inventory on host, install Ops Agent
	bash installer/install.sh finish

ah-test: ## Check the Automation Hub token by downloading ansible.platform
	@d=$$(mktemp -d) && $(ACT) ansible-galaxy collection download ansible.platform --no-deps -p $$d >/dev/null 2>&1 \
	  && echo "AH token OK: $$(ls $$d | grep -m1 ansible-platform)" || echo "AH token FAILED"

ee: ## Build the custom EE on aap-01 and push it to the private hub
	bash ee/build.sh start

verify-ee: ## Check the custom EE is published in the private hub
	$(ACT) ANSIBLE_STDOUT_CALLBACK=default ansible-playbook -i localhost, tests/verify-ee.yml

ee-status: ## Show progress of the EE build
	bash ee/build.sh status

.PHONY: verify verify-audit preflight eda-prereqs verify-eda verify-patching verify-rbac verify-compliance adhoc-ping trust-hub-ca configure verify-inventory collections ee ee-status verify-ee verify-platform install-aap install-status install-finish ah-test

collections: ## Install config-as-code collections into .collections (needs AH_TOKEN)
	$(ACT) ansible-galaxy collection install -r aap-config/requirements.yml -p .collections
	$(ACT) ansible-galaxy collection install -r ee/requirements.yml -p .collections

verify-inventory: ## Case 1: sync the GCP dynamic inventory and check hosts/groups
	$(ACT) ANSIBLE_STDOUT_CALLBACK=default ansible-playbook -i localhost, tests/verify-inventory.yml

# Connection settings for ansible.platform (gateway) and ansible.controller.
# macOS: lookups that make HTTP calls in forked workers die without these (error 33).
AAP_CONN = OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES no_proxy='*' AAP_HOSTNAME=https://$(AAP_HOST) AAP_USERNAME=admin AAP_PASSWORD="$(AAP_ADMIN_PASSWORD)" AAP_VALIDATE_CERTS=false \
           CONTROLLER_HOST=https://$(AAP_HOST) CONTROLLER_USERNAME=admin CONTROLLER_PASSWORD="$(AAP_ADMIN_PASSWORD)" CONTROLLER_VERIFY_SSL=false

preflight: ## Refuse to configure with a half-filled .env or an inventory for another project
	@test -n "$(AAP_PROJECT_SCM_URL)" || { echo "AAP_PROJECT_SCM_URL is empty in .env"; exit 1; }
	@test -n "$(AAP_INTERNAL_IP)" || { echo "AAP_INTERNAL_IP is empty in .env (terraform output aap_internal_ip)"; exit 1; }
	@grep -qE "^  - $(PROJECT_ID)( |$$)" inventories/gcp_compute.yml || { echo "inventories/gcp_compute.yml does not list PROJECT_ID=$(PROJECT_ID)"; exit 1; }
	@echo "preflight OK"

configure: preflight ## Apply AAP configuration as code (aap-config/site.yml). Idempotent
	$(ACT) $(AAP_CONN) ANSIBLE_STDOUT_CALLBACK=default ansible-playbook -i localhost, aap-config/site.yml

trust-hub-ca: ## Trust the AAP CA for the hub registry (rootless Podman, user ansible)
	bash installer/install.sh trust-hub-ca

adhoc-ping: ## Ad-hoc ping through AAP to all inventory hosts
	bash scripts/adhoc-ping.sh

verify-compliance: ## Case 2: scan -> harden -> scan, score improves, evidence in bucket
	$(ACT) ANSIBLE_STDOUT_CALLBACK=default ansible-playbook -i localhost, tests/verify-compliance.yml

verify-rbac: ## Case 4: check each user can do exactly what their team allows
	$(ACT) ANSIBLE_STDOUT_CALLBACK=default ansible-playbook -i localhost, tests/verify-rbac.yml

verify-patching: ## Case 3: approval (op1 403, sec1 OK), forced failure rollback, no-op rollback
	$(ACT) ANSIBLE_STDOUT_CALLBACK=default ansible-playbook -i localhost, tests/verify-patching.yml

verify-eda: ## Case 6: stop nginx -> EDA remediates -> nginx active again
	$(ACT) ANSIBLE_STDOUT_CALLBACK=default ansible-playbook -i localhost, tests/verify-eda.yml

verify-audit: ## Case 7: aud1 exports jobs/approvals to the bucket; logs in Cloud Logging
	$(ACT) ANSIBLE_STDOUT_CALLBACK=default ansible-playbook -i localhost, tests/verify-audit.yml

verify: verify-platform verify-ee verify-inventory verify-rbac verify-compliance verify-patching verify-eda verify-audit ## Run every verification (cases 1-7)


eda-prereqs: ## Create the EDA event stream token and fetch the platform CA into ~/.aap-lab (once)
	@mkdir -p $(HOME)/.aap-lab && chmod 700 $(HOME)/.aap-lab
	@test -s $(HOME)/.aap-lab/eda-token || (python3 -c 'import secrets; print(secrets.token_urlsafe(32), end="")' > $(HOME)/.aap-lab/eda-token && chmod 600 $(HOME)/.aap-lab/eda-token && echo "eda-token created")
	@bash scripts/iap-ssh.sh aap-01 'cat ~/aap/tls/ca.cert' 2>/dev/null | sed -n '/BEGIN CERTIFICATE/,/END CERTIFICATE/p' > $(HOME)/.aap-lab/aap-ca.crt
	@openssl x509 -in $(HOME)/.aap-lab/aap-ca.crt -noout -subject >/dev/null && echo "platform CA saved to ~/.aap-lab/aap-ca.crt"
