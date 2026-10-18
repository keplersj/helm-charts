# beeper-bridges

Runs Beeper's [self-hosted bridges](https://github.com/beeper/bridge-manager) (`bbctl run`) in
Kubernetes: one container per enabled bridge, all in a single pod, sharing one volume at `/data`.

> **Credentials.** The Beeper access token and `bbctl.json` are account-level credentials. This
> chart never creates the token Secret; point it at one you manage (External Secrets, SOPS, …).
> The data volume holds every bridge's session and database: treat it, and its backups, as secret.

## Install

```sh
kubectl -n beeper create secret generic beeper-secrets --from-literal=MATRIX_ACCESS_TOKEN=...
helm install bridges oci://ghcr.io/keplersj/charts/beeper-bridges \
  --namespace beeper --version <version> \
  --set image.digest=sha256:<digest>
```

`bbctl` needs a `bbctl.json` on the volume (`BBCTL_CONFIG`, default `/data/bbctl.json`), created
by `bbctl login` / `bbctl register`. Create it once, for example by running `bbctl` in a
throwaway pod that mounts the same PVC.

## Choosing bridges

`bridges.<name>` is a container. All twelve upstream bridges are on by default; trim what you
don't use:

```yaml
bridges:
  discord: {enabled: false}
  whatsapp:
    resources: {limits: {memory: 512Mi}}
    extraArgs: [--verbose]
  matrix-thing:            # any other bbctl bridge
    enabled: true
    bridge: sh-mautrix-thing
```

Disabling a bridge removes the container only; its data stays on the volume.

## Why one pod

The bridges share a ReadWriteOnce volume, so they must schedule together. The Deployment uses
`Recreate` and one replica; one bridge crashing restarts only its container.

## Migrating from hand-written manifests

The shape this chart was extracted from: Deployment `bridges`, ConfigMap `beeper-env`, PVC
`beeper-data`, Secret `beeper-secrets`, all in one namespace.

1. Keep the PVC as is: `persistence.existingClaim: beeper-data`. Remove it from your
   kustomization with pruning disabled (or keep the object unmanaged) so it is never deleted.
2. Use `fullnameOverride: bridges`. The chart then creates Deployment `bridges` and ConfigMap
   `bridges-env`; delete the old Deployment and ConfigMap `beeper-env` in the same change.
3. Expect a short outage while the old pod releases the volume.

See `ci/adopt-values.yaml`.
