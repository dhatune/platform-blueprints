# n8n on Kubernetes

Workflow automation: a service that runs jobs on a schedule and in response to
webhooks, holding credentials for everything it talks to.

## The thing that makes it interesting

n8n keeps all of its state in Postgres. No persistent volume, nothing of
consequence in the container. Every instinct says this is the ideal candidate
for the cheapest capacity available — preemptible nodes, aggressive
consolidation, restart it whenever.

That instinct is right about restarts and wrong about executions, and the
distinction is the section's whole point. See ADR 8.

## Layout

```
base/   namespace, database, deployment, three services, secret example
test/   overlay that runs the base in a throwaway local cluster
```

## What was verified

The base was deployed to a disposable cluster, exercised, and torn down.

```
all pods ready               n8n and Postgres, 0 restarts
health probe                 200 on all three services
schema                       30 tables created against Postgres
credentials at rest          stored ciphertext; the plaintext secret
                             appears nowhere in the database
```

The credential check is worth describing because it is the claim the manifest
leans on hardest. A credential was created through the API with a recognisable
password, then the database was searched for that string. It is not there; what
is stored begins with the header of an AES ciphertext. That is what the
encryption key does, and it is why losing that key loses every credential even
with a perfect database backup.

## A defect the deployment found

The first deployment came up correctly with two restarts. n8n exits rather than
retrying when the database refuses a connection, so on a cold start of the
namespace it crashed twice before Postgres was accepting.

Kubernetes recovered on its own and the end state was right, which is exactly
why this is easy to leave alone. It matters because of what it does to
monitoring: the restarts are recorded with reason `Error` and a non-zero exit
code, indistinguishable from a real crash. Any alert on restart count fires on
every deployment, and an alert that always fires is one nobody reads.

An init container that waits for the database turns the crash loop into an init
phase. Redeployed, the restart count is zero.

This is the kind of thing that only appears when the manifest is actually run.
`kubectl apply --dry-run` reports it as valid, because it is.

## What you have to supply

A secret with the database password and the encryption key, a database that is
managed rather than the pod included here, and a gateway in front that attaches
the right policy to each of the three services.

The node placement names pools that will not exist in your cluster. The test
overlay shows how to remove it; do not copy the labels.
