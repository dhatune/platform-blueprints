#!/usr/bin/env bash
# Install AAP (containerized, growth all-in-one) on aap-01.
#   install.sh start   -> copy tarball + rendered inventory, launch installer detached
#   install.sh status  -> tail the remote install log
#   install.sh finish  -> shred the inventory on the host and install the Ops Agent
#   install.sh trust-hub-ca -> let rootless Podman (user ansible) trust the AAP CA for the hub registry
set -euo pipefail
cd "$(dirname "$0")/.."
set -a
# .env is local and never committed.
# shellcheck source=/dev/null
source .env
set +a

KEY="${SSH_KEY_PATH/#\~/$HOME}"
TARBALL="${AAP_SETUP_TARBALL/#\~/$HOME}"
G=(--zone "$ZONE" --project "$PROJECT_ID" --account "$GCP_ACCOUNT" --tunnel-through-iap
   --ssh-key-file "$KEY" --strict-host-key-checking=no --quiet)
REMOTE_DIR=aap-install
SETUP_DIR=$(basename "$TARBALL" .tar.gz)

# -n: stdin from /dev/null so non-interactive sessions never hang waiting on input.
remote() { gcloud compute ssh ansible@aap-01 "${G[@]}" --ssh-flag=-n --command "$*"; }
copy()   { gcloud compute scp "${G[@]}" "$@"; }

case "${1:-}" in
  start)
    bash installer/render.sh
    remote "mkdir -p ~/$REMOTE_DIR && chmod 700 ~/$REMOTE_DIR"
    copy "$TARBALL" installer/.rendered/inventory "ansible@aap-01:~/$REMOTE_DIR/"
    # ansible-core runs the installer; it installs podman and everything else.
    remote "sudo dnf install -y -q ansible-core tar python3-requests && cd ~/$REMOTE_DIR && \
      tar -xzf $(basename "$TARBALL") && mv -f inventory $SETUP_DIR/inventory-poc && \
      chmod 600 $SETUP_DIR/inventory-poc && cd $SETUP_DIR && \
      (nohup ansible-playbook -i inventory-poc ansible.containerized_installer.install \
        < /dev/null > ~/$REMOTE_DIR/install.log 2>&1 &) ; echo launched"
    ;;
  status)
    remote "tail -n 15 ~/$REMOTE_DIR/install.log; echo; pgrep -f '[c]ontainerized_installer[.]install' >/dev/null && echo RUNNING || echo FINISHED"
    ;;
  finish)
    remote "shred -u ~/$REMOTE_DIR/$SETUP_DIR/inventory-poc 2>/dev/null || true"
    copy installer/ops-agent.yaml "ansible@aap-01:/tmp/ops-agent.yaml"
    remote "curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh && \
      sudo bash add-google-cloud-ops-agent-repo.sh --also-install -q && \
      sudo install -m 644 /tmp/ops-agent.yaml /etc/google-cloud-ops-agent/config.yaml && \
      sudo systemctl restart google-cloud-ops-agent && rm -f /tmp/ops-agent.yaml add-google-cloud-ops-agent-repo.sh && \
      systemctl is-active google-cloud-ops-agent"
    rm -f installer/.rendered/inventory
    ;;
  trust-hub-ca)
    # Scoped trust: only this registry host, only for the ansible user (not system-wide).
    remote "for h in $AAP_HOST aap-01.${ZONE}.c.${PROJECT_ID}.internal; do \
      mkdir -p ~/.config/containers/certs.d/\$h && \
      cp ~/aap/tls/ca.cert ~/.config/containers/certs.d/\$h/ca.crt; done && \
      podman pull -q $AAP_HOST/ee-aap-poc:1.0.0 >/dev/null && echo 'hub CA trusted: pull with TLS verification OK'"
    ;;
  *) echo "usage: $0 start|status|finish|trust-hub-ca" >&2; exit 2 ;;
esac
