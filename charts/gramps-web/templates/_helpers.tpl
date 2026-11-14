{{- define "gramps-web.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "gramps-web.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{- define "gramps-web.selectorLabels" -}}
app.kubernetes.io/name: {{ include "gramps-web.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "gramps-web.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{ include "gramps-web.selectorLabels" . }}
app.kubernetes.io/version: {{ .Values.image.tag | default .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "gramps-web.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "gramps-web.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{- define "gramps-web.image" -}}
{{- $tag := .Values.image.tag | default .Chart.AppVersion -}}
{{- if .Values.image.digest -}}
{{ .Values.image.repository }}:{{ $tag }}@{{ .Values.image.digest }}
{{- else -}}
{{ .Values.image.repository }}:{{ $tag }}
{{- end -}}
{{- end }}

{{/* redis://[user:$(REDIS_PASSWORD)@]host:port/<db>; $(VAR) is expanded by Kubernetes from the env list. */}}
{{- define "gramps-web.redisURL" -}}
{{- $root := index . 0 -}}
{{- $db := index . 1 -}}
{{- $r := $root.Values.redis -}}
{{- if $r.existingSecret.name -}}
redis://{{ $r.username }}:$(REDIS_PASSWORD)@{{ $r.host }}:{{ $r.port }}/{{ $db }}
{{- else -}}
redis://{{ $r.host }}:{{ $r.port }}/{{ $db }}
{{- end -}}
{{- end }}

{{/* Env shared by the web and Celery containers. */}}
{{- define "gramps-web.env" -}}
- name: GRAMPSWEB_TREE
  value: {{ .Values.gramps.tree | quote }}
- name: GRAMPSWEB_BASE_URL
  value: {{ required "gramps.baseURL is required" .Values.gramps.baseURL | quote }}
- name: GRAMPSWEB_REGISTRATION_DISABLED
  value: {{ .Values.gramps.registrationDisabled | quote }}
- name: GRAMPSWEB_DISABLE_TELEMETRY
  value: {{ .Values.gramps.disableTelemetry | quote }}
- name: GRAMPSWEB_MEDIA_PREFIX_TREE
  value: {{ .Values.gramps.mediaPrefixTree | quote }}
- name: GRAMPSWEB_SECRET_KEY
  valueFrom:
    secretKeyRef:
      name: {{ required "secretKey.existingSecret is required" .Values.secretKey.existingSecret }}
      key: {{ .Values.secretKey.key }}
{{- if .Values.postgres.enabled }}
- name: PG_USER
  valueFrom:
    secretKeyRef:
      name: {{ required "postgres.existingSecret is required" .Values.postgres.existingSecret }}
      key: {{ .Values.postgres.usernameKey }}
- name: PG_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ .Values.postgres.existingSecret }}
      key: {{ .Values.postgres.passwordKey }}
- name: GRAMPSWEB_NEW_DB_BACKEND
  value: sharedpostgresql
- name: GRAMPSWEB_POSTGRES_HOST
  value: {{ required "postgres.host is required" .Values.postgres.host | quote }}
- name: GRAMPSWEB_POSTGRES_PORT
  value: {{ .Values.postgres.port | quote }}
- name: GRAMPSWEB_POSTGRES_USER
  value: $(PG_USER)
- name: GRAMPSWEB_POSTGRES_PASSWORD
  value: $(PG_PASSWORD)
- name: GRAMPSWEB_USER_DB_URI
  value: postgresql://$(PG_USER):$(PG_PASSWORD)@{{ .Values.postgres.host }}:{{ .Values.postgres.port }}/{{ .Values.postgres.userDatabase }}
- name: GRAMPSWEB_SEARCH_INDEX_DB_URI
  value: postgresql://$(PG_USER):$(PG_PASSWORD)@{{ .Values.postgres.host }}:{{ .Values.postgres.port }}/{{ .Values.postgres.treeDatabase }}
{{- end }}
{{- if .Values.redis.enabled }}
{{- if .Values.redis.existingSecret.name }}
- name: REDIS_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ .Values.redis.existingSecret.name }}
      key: {{ .Values.redis.existingSecret.key }}
{{- end }}
{{- $caches := dict "THUMBNAIL_CACHE_CONFIG" .Values.redis.databases.thumbnailCache "REQUEST_CACHE_CONFIG" .Values.redis.databases.requestCache "PERSISTENT_CACHE_CONFIG" .Values.redis.databases.persistentCache }}
{{- range $name, $db := $caches }}
- name: GRAMPSWEB_{{ $name }}__CACHE_TYPE
  value: RedisCache
- name: GRAMPSWEB_{{ $name }}__CACHE_REDIS_URL
  value: {{ include "gramps-web.redisURL" (list $ $db) | quote }}
{{- end }}
- name: GRAMPSWEB_RATELIMIT_STORAGE_URI
  value: {{ include "gramps-web.redisURL" (list . .Values.redis.databases.rateLimit) | quote }}
- name: GRAMPSWEB_CELERY_CONFIG__broker_url
  value: {{ include "gramps-web.redisURL" (list . .Values.redis.databases.celery) | quote }}
- name: GRAMPSWEB_CELERY_CONFIG__result_backend
  value: {{ include "gramps-web.redisURL" (list . .Values.redis.databases.celery) | quote }}
{{- end }}
{{- if .Values.s3.enabled }}
- name: GRAMPSWEB_MEDIA_BASE_DIR
  value: s3://{{ required "s3.bucket is required" .Values.s3.bucket }}
- name: AWS_DEFAULT_REGION
  value: {{ .Values.s3.region | quote }}
{{- with .Values.s3.endpointURL }}
- name: AWS_ENDPOINT_URL
  value: {{ . | quote }}
{{- end }}
{{- if .Values.s3.checksumWhenRequired }}
# boto3 >= 1.36 sends checksum headers that some S3-compatible stores (Cloudflare R2) reject.
- name: AWS_REQUEST_CHECKSUM_CALCULATION
  value: when_required
- name: AWS_RESPONSE_CHECKSUM_VALIDATION
  value: when_required
{{- end }}
- name: AWS_ACCESS_KEY_ID
  valueFrom:
    secretKeyRef:
      name: {{ required "s3.existingSecret is required" .Values.s3.existingSecret }}
      key: {{ .Values.s3.accessKeyIdKey }}
- name: AWS_SECRET_ACCESS_KEY
  valueFrom:
    secretKeyRef:
      name: {{ .Values.s3.existingSecret }}
      key: {{ .Values.s3.secretAccessKeyKey }}
{{- end }}
{{- if .Values.oidc.enabled }}
- name: GRAMPSWEB_OIDC_ENABLED
  value: "true"
- name: GRAMPSWEB_OIDC_ISSUER
  value: {{ required "oidc.issuer is required" .Values.oidc.issuer | quote }}
- name: GRAMPSWEB_OIDC_NAME
  value: {{ .Values.oidc.name | quote }}
- name: GRAMPSWEB_OIDC_SCOPES
  value: {{ .Values.oidc.scopes | quote }}
- name: GRAMPSWEB_OIDC_AUTO_REDIRECT
  value: {{ .Values.oidc.autoRedirect | quote }}
- name: GRAMPSWEB_OIDC_DISABLE_LOCAL_AUTH
  value: {{ .Values.oidc.disableLocalAuth | quote }}
- name: GRAMPSWEB_OIDC_CLIENT_ID
  valueFrom:
    secretKeyRef:
      name: {{ required "oidc.existingSecret is required" .Values.oidc.existingSecret }}
      key: {{ .Values.oidc.clientIdKey }}
- name: GRAMPSWEB_OIDC_CLIENT_SECRET
  valueFrom:
    secretKeyRef:
      name: {{ .Values.oidc.existingSecret }}
      key: {{ .Values.oidc.clientSecretKey }}
{{- with .Values.oidc.roleClaim }}
- name: GRAMPSWEB_OIDC_ROLE_CLAIM
  value: {{ . | quote }}
{{- end }}
{{- with .Values.oidc.groups.admin }}
- name: GRAMPSWEB_OIDC_GROUP_ADMIN
  value: {{ . | quote }}
{{- end }}
{{- with .Values.oidc.groups.editor }}
- name: GRAMPSWEB_OIDC_GROUP_EDITOR
  value: {{ . | quote }}
{{- end }}
{{- with .Values.oidc.groups.member }}
- name: GRAMPSWEB_OIDC_GROUP_MEMBER
  value: {{ . | quote }}
{{- end }}
{{- end }}
{{- with .Values.extraEnv }}
{{ toYaml . }}
{{- end }}
{{- end }}
