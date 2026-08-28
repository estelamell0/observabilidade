#!/usr/bin/env bash
# ============================================================
# Lab Aula 1: Emite métrica OTLP/HTTP pipeline_runs_total
# Uso: ./emitir-metrica-otlp.sh [--branch BRANCH] [--status STATUS]
# ============================================================
set -euo pipefail

OTEL_ENDPOINT="${OTEL_ENDPOINT:-http://localhost:4318}"
BRANCH="main"
STATUS="success"

while [[ $# -gt 0 ]]; do
  case $1 in
    --branch) BRANCH="$2"; shift 2 ;;
    --status) STATUS="$2"; shift 2 ;;
    *) echo "Uso: $0 [--branch BRANCH] [--status STATUS]"; exit 1 ;;
  esac
done

NOW=$(date +%s)
NOW_NS="${NOW}000000000"
START=$((NOW - 60))
START_NS="${START}000000000"

echo "📡 Emitindo métrica OTLP para ${OTEL_ENDPOINT}/v1/metrics"
echo "   pipeline_runs_total{branch=\"${BRANCH}\", status=\"${STATUS}\"} = 1"

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
  "${OTEL_ENDPOINT}/v1/metrics" \
  -H "Content-Type: application/json" \
  -d "{
  \"resourceMetrics\": [{
    \"resource\": {
      \"attributes\": [
        {\"key\": \"service.name\", \"value\": {\"stringValue\": \"ci-pipeline\"}}
      ]
    },
    \"scopeMetrics\": [{
      \"scope\": {\"name\": \"lab-aula1\", \"version\": \"1.0\"},
      \"metrics\": [{
        \"name\": \"pipeline_runs_total\",
        \"sum\": {
          \"dataPoints\": [{
            \"asInt\": \"1\",
            \"startTimeUnixNano\": \"${START_NS}\",
            \"timeUnixNano\": \"${NOW_NS}\",
            \"attributes\": [
              {\"key\": \"branch\", \"value\": {\"stringValue\": \"${BRANCH}\"}},
              {\"key\": \"status\", \"value\": {\"stringValue\": \"${STATUS}\"}}
            ]
          }],
          \"aggregationTemporality\": 2,
          \"isMonotonic\": true
        }
      }]
    }]
  }]
}")

if [[ "$HTTP_CODE" == "200" ]]; then
  echo "✅ Métrica enviada com sucesso (HTTP ${HTTP_CODE})"
  echo "   Verifique em: http://localhost:9090 → query: pipeline_runs_total"
else
  echo "❌ Erro ao enviar métrica (HTTP ${HTTP_CODE})"
  exit 1
fi
