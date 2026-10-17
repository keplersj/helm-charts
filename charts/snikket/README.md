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

Use `persistence.existingClaim: <your-pvc>` and keep the PVC outside Helm. The Deployment's
selector labels differ from typical hand-written ones, so the old Deployment must be deleted, not
adopted (brief downtime; `Recreate` would cause that anyway). A Service whose external IP you want
to keep can be adopted: add the `meta.helm.sh/release-name` / `meta.helm.sh/release-namespace`
annotations and the `app.kubernetes.io/managed-by: Helm` label to it, and set `fullnameOverride` to
its name, before installing.
