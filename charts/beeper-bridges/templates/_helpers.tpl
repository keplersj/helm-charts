{{- define "beeper-bridges.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "beeper-bridges.fullname" -}}
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

{{- define "beeper-bridges.selectorLabels" -}}
app.kubernetes.io/name: {{ include "beeper-bridges.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "beeper-bridges.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{ include "beeper-bridges.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "beeper-bridges.image" -}}
{{- $tag := .Values.image.tag | default .Chart.AppVersion -}}
{{- if .Values.image.digest }}{{ printf "%s:%s@%s" .Values.image.repository $tag .Values.image.digest }}{{ else }}{{ printf "%s:%s" .Values.image.repository $tag }}{{ end -}}
{{- end }}

{{- define "beeper-bridges.claimName" -}}
{{- .Values.persistence.existingClaim | default (printf "%s-data" (include "beeper-bridges.fullname" .)) }}
{{- end }}

{{- define "beeper-bridges.externalImage" -}}
{{- $i := .image -}}
{{- if $i.digest }}{{ printf "%s:%s@%s" $i.repository ($i.tag | default "latest") $i.digest }}{{ else }}{{ printf "%s:%s" $i.repository ($i.tag | default "latest") }}{{ end -}}
{{- end }}
