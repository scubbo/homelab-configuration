{{/*
Expand the name of the chart.
*/}}
{{- define "arr-stack.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "arr-stack.fullname" -}}
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
Create chart name and version as used by the chart label.
*/}}
{{- define "arr-stack.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "arr-stack.labels" -}}
helm.sh/chart: {{ include "arr-stack.chart" . }}
{{ include "arr-stack.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "arr-stack.selectorLabels" -}}
app.kubernetes.io/name: {{ include "arr-stack.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "arr-stack.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "arr-stack.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Templatify creation of standard config PV-and-PVCs
Accepts `service` as a parameter, which should be a mapping containing:
* name - a string (like `sonarr` or `qbit`)
* size - a string (with the standard Kubernetes restrictions on size-strings)
* path - a string (defining the path in the NFS server where this config dir lives)

Note that this assumes NFS as the storage type. A more extensible definition would permit arbitrary storage types. But hey, this is just for me :P

Not currently working, but I'm keeping it checked-in for future inspiration!

*/}}
{{- define "arr-stack.configvolumedefinition" -}}
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: ( include "arr-stack.fullname" . )-( .name )-config-pv
spec:
  capacity:
    storage: {{ .size }}
  accessModes:
    - ReadWriteMany
  nfs:
    server: {{ $.Values.volume.nfsServer }}
    path: {{ .path }}
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ( include "arr-stack.fullname" . )-{{ .name }}-config-pvc
spec:
  storageClassName: ""
  volumeName: ( include "arr-stack.fullname" . )-{{ .name }}-config-pv
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: {{ .size }}
{{- end }}