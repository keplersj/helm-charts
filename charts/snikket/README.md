# snikket

[Snikket](https://snikket.org) (a Prosody-based XMPP server with invites, a web portal and
built-in Let's Encrypt) as one Deployment. The four upstream images (`snikket-server`,
`snikket-web-portal`, `snikket-web-proxy`, `snikket-cert-manager`) run in one pod sharing a data
volume and a network namespace, which is the layout upstream's `docker-compose.yml` gets from
`network_mode: host`.

## Install

```sh
helm install snikket oci://ghcr.io/keplersj/charts/snikket \
  --namespace snikket --create-namespace \
  --set snikket.domain=chat.example.com \
  --set snikket.adminEmail=admin@example.com \
  --set service.type=LoadBalancer
```

Point `chat.example.com`, `groups.chat.example.com` and `share.chat.example.com` at the Service's
external address. The cert-manager container gets certificates over HTTP-01 on port 80, so port 80
must be reachable from the internet. Then create an admin invite:

```sh
kubectl -n snikket exec deploy/snikket -c server -- create-invite --admin --group default
```

## Things to know

- **Images move together.** `image.tag` (default: the chart's `appVersion`, e.g.
  `stable.20260611`) applies to all four. Pin `image.<component>.digest` for reproducibility.
  Avoid `dev`.
- **Data:** everything (accounts, message archive, uploads, certificates) is under `/snikket` on one
  PVC. A chart-created PVC carries `helm.sh/resource-policy: keep`. To adopt an existing volume, set
  `persistence.existingClaim`.
- **`Recreate` only.** Two pods on the same volume would corrupt it.
- **Calls / TURN:** the STUN/TURN control ports are on the Service, but TURN's media relay range
  (`SNIKKET_TWEAK_TURNSERVER_PORT_RANGE`) isn't practical behind a Service. For reliable calls,
  either set `hostNetwork: true` (and pin the node), or point Snikket at an external TURN server
  with the `SNIKKET_TWEAK_TURNSERVER*` settings in `snikket.env`.
- **Extra settings:** anything in `snikket.env` goes into the shared ConfigMap. See upstream's
  [advanced config](https://github.com/snikket-im/snikket-server/blob/master/docs/advanced/config.md).

## Migrating from hand-written manifests

Use this to keep a LoadBalancer Service's external IP, which DNS points at, while moving to the
chart. It takes two separate applies.

1. **Mark the existing Service for adoption** and leave everything else alone. Add to it:
   - annotations `meta.helm.sh/release-name: <release>`, `meta.helm.sh/release-namespace: <ns>`
     and `helm.sh/resource-policy: keep`, so `helm uninstall` never deletes it or its IP
   - label `app.kubernetes.io/managed-by: Helm`
   - if a GitOps tool manages it, whatever stops that tool deleting it once it's no longer in
     its sources (Flux: `kustomize.toolkit.fluxcd.io/prune: disabled`)
2. **Install the chart** and stop applying the old Deployment, ConfigMap and Service:
   - `fullnameOverride: <the Service's name>`
   - `persistence.existingClaim: <the existing PVC>`
   - `service.type`, `service.annotations` (include the three above) and `service.ports` copied
     from the live Service, so the load balancer's configuration doesn't change
   - `podLabels:` the old Deployment's pod labels, so the adopted Service selects the new pod even
     if its old selector keys survive the merge
   - `image.tag` / `image.<component>.digest` set to what is running now. Moving between `dev`,
     `beta` and `stable` is a separate step; going backwards isn't safe against an existing
     database.
   - only the `SNIKKET_*` settings the old containers actually received. The chart passes every
     `snikket.env` key to every container.

The old Deployment is deleted, not adopted: the selectors differ and `selector` is immutable.
Expect a short outage while the volume moves to the new pod; `Recreate` would cause that anyway.
If the old Deployment still exists when Helm installs, the install fails on the name clash. Let it
retry once the old one is gone.
