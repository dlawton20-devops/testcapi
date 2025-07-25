{{/*
Shared helper functions for Rook Ceph sub-charts
This file contains common helper functions used across all sub-charts
*/}}

{{/*
Common namespace definition
*/}}
{{- define "rook-ceph.namespace" -}}
{{- .Values.namespace | default "rook-ceph" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "rook-ceph.labels" -}}
helm.sh/chart: {{ include "rook-ceph.chart" . }}
{{ include "rook-ceph.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "rook-ceph.selectorLabels" -}}
app.kubernetes.io/name: {{ include "rook-ceph.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Fullname
*/}}
{{- define "rook-ceph.fullname" -}}
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

{{/*
Chart name and version
*/}}
{{- define "rook-ceph.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Name
*/}}
{{- define "rook-ceph.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }} 