#!/usr/bin/env python3
"""Refuse a workload whose probe port the network does not allow.

The load balancer's probes arrive from published ranges and are permitted to
reach a fixed list of ports. A workload serving on a port that is not on that
list is marked unhealthy while running perfectly: every request gets a 503, and
nothing in any log connects it to a list that lives in a Terraform module three
directories away.

The coupling cannot be removed. A manifest cannot open a firewall, and a
firewall cannot read a manifest. What it can be is loud: this compares the two
and fails the build, which turns a silent runtime failure into a message
naming the port and both files.
"""

import glob
import re
import sys

import yaml

STACK = "lab/main.tf"


def probe_ports():
    """Ports the workload manifests ask the platform to probe."""
    found = {}
    for path in sorted(glob.glob("platform/*/route/route.yaml")):
        for doc in yaml.safe_load_all(open(path, encoding="utf-8")):
            if not doc or doc.get("kind") != "HealthCheckPolicy":
                continue
            port = (
                doc.get("spec", {})
                .get("default", {})
                .get("config", {})
                .get("httpHealthCheck", {})
                .get("port")
            )
            if port is not None:
                found.setdefault(str(port), []).append(path)
    return found


def allowed_ports():
    """Ports the network module permits the probes to reach."""
    text = open(STACK, encoding="utf-8").read()
    match = re.search(r"health_check_ports\s*=\s*\[([^\]]*)\]", text)
    if not match:
        print(f"::error::{STACK} does not declare health_check_ports.")
        sys.exit(1)
    return {p.strip().strip('"') for p in match.group(1).split(",") if p.strip()}


def main():
    wanted = probe_ports()
    allowed = allowed_ports()

    missing = sorted(set(wanted) - allowed)
    if missing:
        for port in missing:
            for path in wanted[port]:
                print(f"::error file={path}::Probes port {port}, which {STACK} does not allow.")
        print()
        print("The backend will be marked unhealthy and every request will get a 503")
        print("while the application runs perfectly. Add the port to health_check_ports")
        print(f"in {STACK}.")
        return 1

    print(f"ok  every probed port ({', '.join(sorted(wanted))}) is allowed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
