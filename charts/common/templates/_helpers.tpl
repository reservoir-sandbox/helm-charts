{{/*
Fully qualified app name: <release>-<chart> либо просто <release>, если nameOverride пуст
*/}}
{{- define "common.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/*
Стандартные labels — вешаются на все объекты через metadata.labels
*/}}
{{- define "common.labels" -}}
app.kubernetes.io/name: {{ default .Chart.Name .Values.nameOverride }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
{{- end -}}

{{/*
Selector labels — то, по чему matchLabels ищут поды (Service, NetworkPolicy, Deployment.spec.selector).
Никогда не меняются между релизами одного и того же workload'а, поэтому отдельно от common.labels.
*/}}
{{- define "common.selectorLabels" -}}
app.kubernetes.io/name: {{ default .Chart.Name .Values.nameOverride }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Имя ServiceAccount: либо заданное явно, либо common.fullname, либо "default"
*/}}
{{- define "common.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "common.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{/*
УЛУЧШЕНИЕ 1: Image string с поддержкой маркеров Flux Image Automation
Генерирует строку образа. Если в values передан маркер политики Flux,
макрос автоматически дописывает правильный комментарий на ту же строчку.
*/}}
{{- define "common.image" -}}
{{- $repo := .Values.image.repository -}}
{{- $imageStr := "" -}}
{{- if .Values.image.digest -}}
  {{- $imageStr = printf "%s@%s" $repo .Values.image.digest -}}
{{- else -}}
  {{- $imageStr = printf "%s:%s" $repo (.Values.image.tag | default .Chart.AppVersion) -}}
{{- end -}}
{{- if .Values.image.fluxPolicy -}}
  {{- printf "%s # {\"$imagepolicy\": \"%s\"}" $imageStr .Values.image.fluxPolicy -}}
{{- else -}}
  {{- $imageStr -}}
{{- end -}}
{{- end -}}

{{/*
УЛУЧШЕНИЯ 2 и 3: Generic NetworkPolicy, рендерящий ресурс ЦЕЛИКОМ.
Включает автоматическое разрешение CoreDNS при наличии Egress-правил
и стандартизированную кросс-неймспейс фильтрацию по системному лейблу кубера.
*/}}
{{- define "common.networkpolicy" -}}
{{- if .Values.networkPolicy.enabled }}
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ include "common.fullname" . }}
  # Автоматически подставляем неймспейс текущего релиза (apps, jobs или infra)
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "common.labels" . | nindent 4 }}
spec:
  podSelector:
    matchLabels:
      {{- include "common.selectorLabels" . | nindent 6 }}
  policyTypes:
    {{- toYaml .Values.networkPolicy.policyTypes | nindent 4 }}

  {{- if .Values.networkPolicy.ingress }}
  ingress:
    {{- range .Values.networkPolicy.ingress }}
    - from:
      {{- if .from }}
        {{- range .from }}
        # Если в правиле указан targetNamespace, активируем кросс-неймспейс селектор (Улучшение 3)
        {{- if .targetNamespace }}
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: {{ .targetNamespace }}
          {{- if .podLabels }}
          podSelector:
            matchLabels:
              {{- toYaml .podLabels | nindent 14 }}
          {{- else }}
          podSelector: {} # Разрешить всем подам из целевого неймспейса
          {{- end }}
        {{- else }}
        # Иначе используем стандартный локальный podSelector внутри текущего пространства имен
        - podSelector:
            matchLabels:
              {{- toYaml .podLabels | nindent 14 }}
        {{- end }}
        {{- end }}
      {{- else }}
      # Если секция .from пустая, значит это открытый входящий порт (например, для nginx ingress)
      {{- end }}
      {{- if .ports }}
      ports:
        {{- toYaml .ports | nindent 8 }}
      {{- end }}
    {{- end }}
  {{- end }}

  {{- if or .Values.networkPolicy.egress (has "Egress" .Values.networkPolicy.policyTypes) }}
  egress:
    # УЛУЧШЕНИЕ 2: Жестко зашитый дефолтный Egress в kube-system для CoreDNS (порт 53)
    # Защищает поды от потери связи со встроенным DNS-сервером кластера при включении изоляции.
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
          podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
    # Кастомные правила Egress из values (например, бэк идет к postgres в infra)
    {{- if .Values.networkPolicy.egress }}
      {{- range .Values.networkPolicy.egress }}
    - to:
        {{- range .to }}
        {{- if .targetNamespace }}
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: {{ .targetNamespace }}
          {{- if .podLabels }}
          podSelector:
            matchLabels:
              {{- toYaml .podLabels | nindent 14 }}
          {{- else }}
          podSelector: {}
          {{- end }}
        {{- else }}
        - podSelector:
            matchLabels:
              {{- toYaml .podLabels | nindent 14 }}
        {{- end }}
        {{- end }}
      {{- if .ports }}
      ports:
        {{- toYaml .ports | nindent 8 }}
      {{- end }}
      {{- end }}
    {{- end }}
  {{- end }}
{{- end }}
{{- end -}}
