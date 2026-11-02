#!/usr/bin/env bash
# Print the current public IPv4 of this machine as a /32 CIDR.
set -euo pipefail
ip=$(curl -fsS --max-time 10 https://api.ipify.org)
[[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "could not resolve public IP" >&2; exit 1; }
echo "${ip}/32"
