# gramps-web

[Gramps Web](https://www.grampsweb.org) (`ghcr.io/gramps-project/grampsweb`) with its Celery worker,
packaged for a **stateless** deployment: no PersistentVolumeClaims.

| Data | Where it lives |
| --- | --- |
| Family trees (multi-tree, `sharedpostgresql`) | PostgreSQL (`postgres.treeDatabase`) |
| User database | PostgreSQL (`postgres.userDatabase`) |
| Search index | PostgreSQL (`postgres.treeDatabase`) |
| Media | S3-compatible bucket (`s3.*`), e.g. Cloudflare R2 |
| Celery broker/results, rate limits, thumbnail/request/persistent caches | Redis/Valkey (`redis.*`) |
| Export/report scratch files | `emptyDir` shared by the web and Celery containers |

Web and Celery are containers of one pod because Celery writes exports and reports that the web
process serves from the shared scratch dir. Scale with `replicaCount`.

## Install

Nothing secret goes into values; every credential is an `existingSecret` reference.

```sh
helm install tree oci://ghcr.io/keplersj/charts/gramps-web --version 0.1.0 -f values.yaml
```

See [`ci/full-values.yaml`](ci/full-values.yaml) for every integration enabled. Set `postgres.enabled`,
`redis.enabled`, `s3.enabled` to `false` to fall back to Gramps' defaults (SQLite and local files
under the container's filesystem, which are then **not** persisted; add `extraVolumes` plus a
matching `extraEnv`/mount yourself).

## Notes

- `postgres`: the server needs the locales Gramps sorts by (stock CNPG images have them). The
  password is embedded in connection URIs, so keep it alphanumeric. The role needs to be able to
  create tables in both databases.
- `redis`: the password is embedded in `redis://` URLs; keep it URL-safe. Each concern uses its own
  database number (`redis.databases.*`).
- `s3.checksumWhenRequired` (default on) works around boto3's default checksum headers, which
  Cloudflare R2 rejects.
- `oidc`: register `<baseURL>/api/oidc/callback/custom` as the redirect URI if the provider does
  not support wildcards. The tree is never part of the redirect URI.
- `gramps.tree: "*"` (multi-tree) is required to put trees in PostgreSQL. The first visit shows the
  owner-account setup form.
