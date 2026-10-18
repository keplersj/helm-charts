# helm-charts

Helm charts by [@keplersj](https://github.com/keplersj), published as OCI artifacts to
`oci://ghcr.io/keplersj/charts`.

| Chart | App | Image |
| --- | --- | --- |
| [`beeper-bridges`](charts/beeper-bridges) | Self-hosted [Beeper bridges](https://github.com/beeper/bridge-manager) (`bbctl run`) | upstream `ghcr.io/beeper/bridge-manager` |
| [`beeper-server`](charts/beeper-server) | Headless [Beeper Server](https://github.com/beeper/cli) (Beeper Client API) | [`ghcr.io/keplersj/beeper-server`](https://github.com/keplersj/containers/tree/main/apps/beeper-server) |
| [`snikket`](charts/snikket) | [Snikket](https://snikket.org) XMPP server | upstream `snikket/*` |

```sh
helm install <release> oci://ghcr.io/keplersj/charts/<chart> --version <version> -f values.yaml
```

Flux:

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: keplersj
spec:
  type: oci
  url: oci://ghcr.io/keplersj/charts
  interval: 1h
```

## Development

- Charts live in `charts/<name>/`. Images this repo's charts need, where upstream ships none, are
  built in [keplersj/containers](https://github.com/keplersj/containers), not here.
- PRs run `helm lint --strict` and `helm template | kubeconform` for every chart, with each
  chart's `ci/*-values.yaml` files.
- Merging to `main` publishes any chart whose `version` isn't in the registry yet. **Bump
  `version` in `Chart.yaml` to release**; published versions are never overwritten.

## License

[MIT](LICENSE). Upstream software packaged here keeps its own license.
