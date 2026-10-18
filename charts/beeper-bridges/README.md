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

`bridges.<name>` is a container. Every bridge is **off by default**: which bridges to run is a
deployment decision, and enabling one registers it on your Beeper account. The chart refuses to
render with none enabled. Turn on the ones you use:

```yaml
bridges:
  signal: {enabled: true}
  whatsapp:
    enabled: true
    resources: {limits: {memory: 512Mi}}
    extraArgs: [--verbose]
  matrix-thing:            # any other bbctl bridge
    enabled: true
    bridge: sh-mautrix-thing
```

Disabling a bridge later removes the container only; its data stays on the volume.

## Bridge notes

`values.yaml` has an entry for all 15 official bridges (Meta is two containers, `facebook` and
`instagram`). Most, including `gvoice`, are prebuilt Go binaries (Google Chat is Python) and need
nothing extra. Three have caveats:

| Key | Bridge | Runs on Kubernetes? |
|---|---|---|
| `heisenbridge` | Heisenbridge (IRC) | Yes. A Python bridge: `bbctl` creates a venv on `/data` and `pip install`s it at startup, so the pod needs PyPI egress. The image ships Python, as it does for Google Chat. |
| `imessage` | mautrix-imessage | Only via BlueBubbles. On Linux `bbctl` offers just the BlueBubbles connector, which needs a BlueBubbles server on a Mac you run yourself. |
| `imessagego` | beeper-imessage | Partly. The binary is built for Linux, but registration needs a code (`nac_token`) generated on a Mac. |

`imessage` and `imessagego` ask for connection details the first time a config is generated,
and a pod has no terminal to answer. Generate the config once (the chart passes
`--no-override-config`, so it is reused afterwards), either by running `bbctl run` in a
throwaway pod on the same PVC, or by passing the values once:

```yaml
bridges:
  imessage:
    enabled: true
    extraArgs: [--param, bluebubbles_url=https://bb.example.com, --param, bluebubbles_password=...]
```

Remove the `--param` arguments after the first start: they are visible in the pod spec.

> The `gvoice`, `heisenbridge` and iMessage entries follow `bbctl`'s source; they have not been
> run against a live Beeper account from this chart.

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
3. Enable every bridge the old Deployment ran (all are off by default).
4. Expect a short outage while the old pod releases the volume.

See `ci/adopt-values.yaml`.
