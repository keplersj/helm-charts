# beeper-server

Runs a headless [Beeper Server](https://github.com/beeper/cli) — the Beeper Client API without
Beeper Desktop — as a single-replica StatefulSet, using
[`ghcr.io/keplersj/beeper-server`](https://github.com/keplersj/containers/tree/main/apps/beeper-server)
(beeper-server + the `beeper` CLI, non-root, no systemd).

> **Read this first.** The API this chart runs can read and send messages as you on every chat
> network you connect. The defaults are deliberately closed: ClusterIP only (any other Service
> type needs `allowExternalService: true`), no Ingress, a default-deny NetworkPolicy for ingress
> **and** egress, no ServiceAccount token, read-only root filesystem. Loosen them on purpose, not
> by accident.

## Install

```sh
helm install beeper oci://ghcr.io/keplersj/charts/beeper-server \
  --namespace beeper-server --create-namespace \
  --set image.digest=sha256:<digest> \
  --set 'networkPolicy.ingress.allowNamespaces={my-mcp-client-namespace}'
```

Nothing secret goes into values. All state is created at bootstrap time, on the PVC.

## What lives on the volume

Everything, at `/data` (one PVC):

| Path | Contents |
| --- | --- |
| `/data/server` | Beeper account login, device verification + end-to-end encryption keys, bridge sessions |
| `/data/cli` | CLI config and `targets/*.json` (**contains an access token**) |

Treat the PVC and any backup of it as a credential.

## Bootstrap (one time, interactive)

`kubectl exec` needs a TTY (`-it`) for the prompts and the WhatsApp QR code. `POD` below is
`<release>-beeper-server-0` (or `<fullnameOverride>-0`).

1. **Check the server is up** (unauthenticated discovery endpoint):

   ```sh
   kubectl -n beeper-server exec POD -- beeper api get /v1/info --base-url http://127.0.0.1:23373 --json
   ```

   Note `server.mcp_enabled`, `server.remote_access`, `server.hostname` and `endpoints.mcp`; see
   [MCP](#mcp) and [Bind address](#bind-address).

2. **Sign in with an emailed code.** The pod runs the server itself, so the CLI talks to it as a
   *remote* target named `server` (not `beeper setup --server`, which would try to install and
   launch a second copy on port 23374):

   ```sh
   kubectl -n beeper-server exec -it POD -- \
     beeper setup --remote http://127.0.0.1:23373 --target server --email you@example.com
   ```

   Enter the code from the email when prompted. Non-interactive alternative:
   `beeper auth email start --email … -t server --json`, then
   `beeper auth email response --setup-request-id <id> --code <code> -t server --json`.

3. **Verify the device** so it can decrypt messages. Approve it from another signed-in Beeper
   device, or use your recovery key, keeping it out of shell history:

   ```sh
   read -rs BEEPER_RECOVERY_KEY
   kubectl -n beeper-server exec POD -- beeper verify recovery-key -t server --key "$BEEPER_RECOVERY_KEY"
   unset BEEPER_RECOVERY_KEY
   kubectl -n beeper-server exec POD -- beeper verify status -t server
   ```

4. **Add chat networks**, one per run. Each bridge drives its own login (QR, code, cookie, …):

   ```sh
   kubectl -n beeper-server exec -it POD -- beeper accounts add -t server
   kubectl -n beeper-server exec POD -- beeper accounts list -t server
   ```

5. **Get an access token for your client.** Two options:

   - **Preferred: a separate OAuth token.** From your workstation, with the CLI installed
     (`npm i -g beeper-cli`):

     ```sh
     kubectl -n beeper-server port-forward svc/<release>-beeper-server 23373:23373 &
     beeper setup --remote http://127.0.0.1:23373 --target k8s   # browser OAuth/PKCE
     beeper auth status -t k8s
     ```

     The token is stored in `~/.beeper/targets/k8s.json` on your workstation. It can be revoked on
     its own with `beeper auth logout -t k8s`, without touching the server's own sign-in.
   - **Fallback: the token the in-pod CLI stored at sign-in**
     (`/data/cli/targets/server.json`, `.auth.accessToken`). In CLI 0.6.x email sign-in stores the
     login's **Matrix access token**, so it is broader than an API token. Use it only if OAuth
     doesn't work against your server.

   Put the token in your secret manager; never in values or git.

No `beeper targets enable` / `loginctl enable-linger` here: the StatefulSet restarts the server.

## Verify

```sh
POD=<release>-beeper-server-0; NS=beeper-server
# Discovery + auth from inside the pod
kubectl -n $NS exec $POD -- beeper status -t server
kubectl -n $NS exec $POD -- beeper chats list -t server --limit 3

# From an allowed namespace (or via port-forward), with your token
TOKEN=...   # from step 5
curl -fsS http://<release>-beeper-server.$NS.svc:23373/v1/info
curl -fsS -H "Authorization: Bearer $TOKEN" http://<release>-beeper-server.$NS.svc:23373/v1/accounts

# MCP (Streamable HTTP), if the server provides it
curl -sS -X POST http://<release>-beeper-server.$NS.svc:23373/v0/mcp \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"curl","version":"0"}}}'
```

A JSON-RPC `result` with `serverInfo` means MCP works. A 404 means this server build has no MCP
endpoint.

Also confirm the NetworkPolicy from a namespace that is **not** allowed. This should time out:

```sh
kubectl run np-test --rm -it --restart=Never --image=curlimages/curl -n default -- \
  curl -m 5 http://<release>-beeper-server.beeper-server.svc:23373/v1/info
```

## MCP

Beeper Desktop serves MCP at `/v0/mcp`. **Whether Beeper Server does is not documented**. The
CLI never mentions MCP, but the Client API's `/v1/info` schema (shared by Desktop and Server)
reports `server.mcp_enabled` and `endpoints.mcp`. Use step 1 and the curl above to find out on
your build.

If it doesn't, the smallest bridge is Beeper's official MCP server for the same API,
[`@beeper/desktop-mcp`](https://www.npmjs.com/package/@beeper/desktop-mcp), run as
`--transport=http` next to the server. It reads `BEEPER_DESKTOP_BASE_URL` and passes the caller's
`Authorization: Bearer` through to the REST API. This chart doesn't include it yet.

## Bind address

The CLI launches beeper-server with `--host=127.0.0.1`. This chart passes `--host=0.0.0.0`
(`server.host`) so the Service can reach it. That's a real server flag, so no proxy sidecar is
needed. Desktop additionally gates non-local clients behind "Remote Access", and `/v1/info`
reports a `server.remote_access` flag on Server too. If requests through the Service are refused
while `exec`'d requests to 127.0.0.1 work, the server is enforcing that. The readiness probe
(`GET /v1/info` from the kubelet) will then report the pod unready rather than restart it. Open
an issue with the `/v1/info` output.

## Backup and restore

The volume holds live SQLite databases and encryption keys, so copy it **with the server
stopped**:

```sh
NS=beeper-server; STS=<release>-beeper-server; PVC=data-$STS-0
kubectl -n $NS scale statefulset $STS --replicas=0
kubectl -n $NS wait --for=delete pod/$STS-0 --timeout=120s
kubectl -n $NS run beeper-backup --restart=Never --image=busybox:1.37 \
  --overrides='{"spec":{"securityContext":{"runAsUser":10001,"runAsGroup":10001,"fsGroup":10001},
    "volumes":[{"name":"d","persistentVolumeClaim":{"claimName":"'$PVC'"}}],
    "containers":[{"name":"c","image":"busybox:1.37","command":["sleep","3600"],"volumeMounts":[{"name":"d","mountPath":"/data"}]}]}}'
kubectl -n $NS wait --for=condition=Ready pod/beeper-backup
kubectl -n $NS exec beeper-backup -- tar -C /data -czf - . | age -r <your-age-recipient> > beeper-$(date +%F).tgz.age
kubectl -n $NS delete pod beeper-backup
kubectl -n $NS scale statefulset $STS --replicas=1
```

To restore, do the same with the server scaled to 0, but stream the archive in:

```sh
age -d -i key.txt beeper-YYYY-MM-DD.tgz.age | kubectl -n $NS exec -i beeper-backup -- sh -c 'rm -rf /data/* /data/.[!.]* ; tar -C /data -xzf -'
```

Only restore onto a server that isn't also running elsewhere: two servers with the same device
keys will conflict. Volume snapshots (CSI `VolumeSnapshot`, Velero) work too, taken while scaled
to 0.

## Values

See [`values.yaml`](values.yaml). The ones you'll usually set:

| Key | Default | |
| --- | --- | --- |
| `image.digest` | `""` | Pin the image |
| `networkPolicy.ingress.allowNamespaces` | `[]` | Namespaces allowed to call the API |
| `networkPolicy.ingress.allowFrom` | `[]` | Finer-grained peers |
| `networkPolicy.egress.exceptCIDRs` | private, CGNAT, link-local | Add your node/pod CIDRs if they're public |
| `persistence.storageClass` / `size` | cluster default / `5Gi` | |
| `ingress.*` | disabled | Only with a private ingress class |
