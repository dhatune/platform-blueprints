# Reaching a private cluster from a workstation

This landing zone's cluster has **no public API server**. There is no address
to point `kubectl` at from a laptop, a build agent, or anywhere outside the
virtual network. That is deliberate (it is most of what "private cluster"
buys) and it means the first question anyone joining this work asks is the
one this document answers.

Two things must both be true before any command reaches the cluster, and they
fail differently. Confusing them costs hours.

| Plane | What it decides | How a failure looks |
| --- | --- | --- |
| **Network** | Can a packet get there at all | Connection refused, or a timeout that never ends |
| **Authorization** | May this identity do this | A 403 that arrives immediately |

They are easy to confuse. Read a timeout as a missing route and
an immediate refusal as a missing role, and never the other way round.

---

## The three ways in

| | Infrastructure needed | Real `kubectl`? | Cost |
| --- | --- | --- | --- |
| **A. Managed command channel** | None | No | Nothing |
| **B. Jump host and a tunnel** | One small VM, one firewall rule | Yes | A VM by the hour |
| **C. Site-to-site or point-to-site VPN** | A gateway | Yes | A gateway by the hour, and it is not cheap |

**A is what this laboratory uses.** It needs nothing built, which is why it is
first. It is also not really `kubectl`, and the section on its limits explains
exactly where that stops being acceptable.

---

## A. The managed command channel

### What it actually is

`az aks command invoke` does not connect you to the cluster. It asks the
Azure control plane to **run your command inside the cluster**, in a pod it
creates for that purpose, and hand you back the output.

```
your laptop ──▶ Azure control plane ──▶ pod in the cluster ──▶ API server
     ▲                                                              │
     └──────────────────── stdout comes back ───────────────────────┘
```

Nothing is routed to your machine. The private API server is reached from
inside the network, where reaching it is ordinary. Your laptop never needs a
route, a tunnel, or DNS for the private zone.

Files are uploaded with `--file` and land in the pod's working directory,
which is why `kubectl apply -f 01-x.yaml` works with a bare filename.

### What you need to be allowed to use it

Network reachability is not the question here, there is none to have. The
question is only authorization, and it is in two layers:

1. **Azure**, to invoke the command at all. The operator on this laboratory
   holds `Owner` on the subscription, which covers it. The least-privilege
   answer is a role carrying `Microsoft.ContainerService/managedClusters/runcommand/action`
   and `.../commandResults/read`.
2. **Kubernetes**, for whatever the command then does. This cluster has local
   accounts disabled and resolves Kubernetes permissions through Azure roles,
   so an identity that can invoke a command but holds no cluster role gets a
   clean `Forbidden` from `kubectl`, the command ran, and the cluster said
   no. `live/lab/20-workload` grants whoever applies it
   `Azure Kubernetes Service RBAC Cluster Admin` on the cluster, and nothing
   wider.

That second layer is the one people forget. **Being able to run the command
is not being able to do anything with it.**

### First command

```bash
az aks command invoke \
  -g <spoke resource group> \
  -n <cluster> \
  --command "kubectl get nodes" \
  --query logs -o tsv
```

`--query logs -o tsv` exists because the raw response is a JSON envelope
around the output. Without it you read the envelope.

### Its limits, which are real

| Limit | Consequence |
| --- | --- |
| **Uploads are capped at 1048576 bytes** | Measured against this cluster: a 1026141-byte file is accepted; a 1.4 MB manifest is refused. The error names a Secret and says nothing about your file, because the channel packs uploads into a Kubernetes Secret and Kubernetes caps those. Large manifests have to be split before they are sent. |
| **No port forwarding** | Any web interface inside the cluster is unreachable this way. It has to be published through the ingress, or reached through a jump host or a VPN, neither of which this laboratory builds. |
| **Every call creates a pod** | Seconds of latency per command. Fine for applying a manifest, miserable for working. |
| **No interactive session** | No shell you stay in, no `watch`, no editor. |
| **It is audited as one action** | For some auditors that is a feature; for others "an operator ran an arbitrary command in the cluster" is exactly what they did not want to see as a single event. |

Its honest place: **installing and inspecting, not operating.** Everything in
this repository that touches the cluster goes through it. Interactive work
needs B or C, which are named above for comparison and are not built here.

---

## Reading list when something does not work

| Symptom | Look at |
| --- | --- |
| A command times out with no output | Network plane. Is there a route at all? |
| An immediate `Forbidden` or 403 | Authorization plane. Which of the two layers? |
| A pod stuck in `ImagePullBackOff` | The image is not in our registry, or the manifest points elsewhere |
| An error naming a Secret and a byte count | The upload cap. Split the file. |
| The name does not resolve but `curl -H "Host: ..."` works | DNS only. Nothing else is wrong. |
| A load balancer with no healthy backend and no logs anywhere | The health probe rule. `docs/decisions/0012`. |
