#!/usr/bin/env bash
# Every inventory source (GCP, AWS, VMware) must produce the same group prefixes
# (env, app, os) so playbooks and RBAC do not depend on where hosts live.
set -euo pipefail
cd "$(dirname "$0")/.."

files=(inventories/gcp_compute.yml inventories/examples/aws_ec2.yml inventories/examples/vmware_vm_inventory.yml)
rc=0
for f in "${files[@]}"; do
  if [[ ! -f "$f" ]]; then echo "MISSING: $f"; rc=1; continue; fi
  prefixes=$(python3 -c '
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
print(" ".join(sorted(g.get("prefix", "") for g in doc.get("keyed_groups", []))))
' "$f")
  if [[ "$prefixes" == "app env os" ]]; then
    echo "OK   $f -> $prefixes"
  else
    echo "FAIL $f -> '$prefixes' (expected 'app env os')"; rc=1
  fi
done
exit $rc
