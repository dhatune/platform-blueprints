# ReadWriteMany for the bench

Two pieces, and they are often confused for one.

`nfs-server.yaml` is the server: a pod exporting a directory from a
single-attach disk. It provides a filesystem several pods can mount at once.

A **provisioner** is what turns that into a storage class the chart can ask
for. Without it every volume is a static object somebody wrote by hand. The
usual one is `nfs-subdir-external-provisioner`, installed from its own chart
and pointed at the service above. It is not vendored here for the same reason
the ERP's chart is not: a copy of somebody else's chart in this repository
would look maintained and would drift.

```
helm install nfs-provisioner nfs-subdir-external-provisioner \
  --repo https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner \
  --namespace storage \
  --set nfs.server=nfs-server.storage.svc.cluster.local \
  --set nfs.path=/exports \
  --set storageClass.name=nfs \
  --set storageClass.accessModes=ReadWriteMany
```

The chart's `persistence.*.storageClass` then names `nfs`.

## What breaks, and how it looks when it does

**The server pod moves.** Its disk detaches from one node and attaches to
another, which takes minutes. Every mount is unresponsive for that whole
window, processes block on the filesystem rather than erroring, so the pods
stay Running and answer nothing. Monitoring that watches restarts sees a
healthy deployment.

**The server comes back.** Clients that were mounted across the gap hold stale
handles and get errors on every access until they remount. In practice the
workloads need restarting, which turns a storage blip into a restart of the
whole ERP.

**The disk fills.** The bench writes site files, logs and backups to the same
volume. It fills quietly and the first symptom is usually a failed background
job rather than a disk alert.

None of these are reasons not to do it. They are the reasons to know it is what
you chose.
