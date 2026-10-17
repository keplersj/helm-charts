{{- define "snikket.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "snikket.fullname" -}}
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

{{- define "snikket.selectorLabels" -}}
app.kubernetes.io/name: {{ include "snikket.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "snikket.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{ include "snikket.selectorLabels" . }}
app.kubernetes.io/version: {{ .Values.image.tag | default .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/* snikket.image: pass (list $ "server") */}}
{{- define "snikket.image" -}}
{{- $root := index . 0 -}}
{{- $c := index $root.Values.image (index . 1) -}}
{{- $tag := $c.tag | default $root.Values.image.tag | default $root.Chart.AppVersion -}}
{{- $ref := printf "%s/%s:%s" $root.Values.image.registry $c.repository $tag -}}
{{- if $c.digest }}{{ printf "%s@%s" $ref $c.digest }}{{ else }}{{ $ref }}{{ end -}}
{{- end }}

{{- define "snikket.claimName" -}}
{{- .Values.persistence.existingClaim | default (printf "%s-data" (include "snikket.fullname" .)) }}
{{- end }}
