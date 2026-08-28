#!/usr/bin/env bash
# ============================================================
# Lab Aula 5: Trace completo de pipeline com waterfall rico
# Gera via OTLP HTTP JSON (não precisa de otel-cli)
# ============================================================
set -euo pipefail

OTEL_ENDPOINT="${OTEL_ENDPOINT:-http://localhost:4318}"
BRANCH="main"
FORCE_DEPLOY=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --branch) BRANCH="$2"; shift 2 ;;
    --force-deploy) FORCE_DEPLOY="1"; shift ;;
    *) echo "Uso: $0 [--branch BRANCH] [--force-deploy]"; exit 1 ;;
  esac
done

# ── Gera IDs hexadecimais ────────────────────────────────────
gen_hex() {
  local len=$1 result=""
  for ((i=0; i<len; i++)); do
    result+=$(printf '%x' $((RANDOM % 16)))
  done
  echo "$result"
}

TRACE_ID="${ULTIMATE_TRACE_ID:-$(gen_hex 32)}"
COMMIT_SHA="${ULTIMATE_COMMIT_SHA:-$(gen_hex 8)}"
PIPELINE_ID="${ULTIMATE_PIPELINE_ID:-pipe-$(gen_hex 8)}"

# Span IDs
SID_ROOT=$(gen_hex 16)
SID_CHECKOUT=$(gen_hex 16)
SID_BUILD=$(gen_hex 16)
SID_CACHE=$(gen_hex 16)
SID_COMPILE=$(gen_hex 16)
SID_TEST=$(gen_hex 16)
SID_SECURITY=$(gen_hex 16)
SID_SAST=$(gen_hex 16)
SID_SCA=$(gen_hex 16)
SID_DAST=$(gen_hex 16)
SID_DEPLOY=$(gen_hex 16)

# ── Timestamps (nanosegundos) ────────────────────────────────
# Trace "aconteceu" ~8 minutos atrás com durações realistas
NOW=$(date +%s)
T=$((NOW - 492))
ns() { echo "$((T + $1))000000000"; }

# Boundaries (offset em segundos a partir de T):
#   checkout:       0 → 12       build:        12 → 137
#     restore-cache: 12 → 30       compile:     30 → 137
#   test-unit:    137 → 237
#   security:     237 → 462
#     sast-scan:  237 → 317       sca-scan:   317 → 372
#     dast-scan:  372 → 462       event gate.failed @ 450
#   deploy-staging: 462 → 492 (só com --force-deploy)

# Findings aleatórios
SAST_FINDINGS=$((RANDOM % 5))
SCA_FINDINGS=$((RANDOM % 3))
DAST_CRITICAL=$((RANDOM % 3 + 1))

# ── Sumário visual ───────────────────────────────────────────
echo "🚀 Pipeline ${PIPELINE_ID} (commit: ${COMMIT_SHA})"
echo "   Branch:   ${BRANCH}"
echo "   Trace ID: ${TRACE_ID}"
echo ""
echo "   Waterfall:"
echo "   ├─ checkout                    [12s]   OK"
echo "   ├─ build                       [2m05s] OK"
echo "   │   ├─ restore-cache           [18s]   OK"
echo "   │   └─ compile                 [1m47s] OK"
echo "   ├─ test-unit                   [1m40s] OK"
echo "   ├─ security                    [3m45s] ERROR"
echo "   │   ├─ sast-scan               [1m20s] OK   (${SAST_FINDINGS} findings)"
echo "   │   ├─ sca-scan                [55s]   OK   (${SCA_FINDINGS} findings)"
echo "   │   └─ dast-scan               [1m30s] ERROR (${DAST_CRITICAL} critical)"
if [[ -n "$FORCE_DEPLOY" ]]; then
echo "   └─ deploy-staging              [30s]   OK   (⚠ sem gate!)"
else
echo "   └─ deploy-staging              [skipped]"
fi
echo ""

# ── Span de deploy (condicional) ─────────────────────────────
DEPLOY_SPAN=""
if [[ -n "$FORCE_DEPLOY" ]]; then
  DEPLOY_SPAN=',
        {
          "traceId": "'"${TRACE_ID}"'",
          "spanId": "'"${SID_DEPLOY}"'",
          "parentSpanId": "'"${SID_ROOT}"'",
          "name": "deploy-staging",
          "kind": 1,
          "startTimeUnixNano": "'"$(ns 462)"'",
          "endTimeUnixNano": "'"$(ns 492)"'",
          "attributes": [
            {"key": "deploy.env", "value": {"stringValue": "staging"}},
            {"key": "gate.executed", "value": {"boolValue": false}}
          ],
          "status": {"code": 1}
        }'
  PIPELINE_END=$(ns 492)
else
  PIPELINE_END=$(ns 462)
fi

# ── Envia trace completo via OTLP HTTP ───────────────────────
TMPFILE=$(mktemp)
trap 'rm -f "$TMPFILE"' EXIT

cat > "$TMPFILE" << TRACE_JSON
{
  "resourceSpans": [{
    "resource": {
      "attributes": [
        {"key": "service.name", "value": {"stringValue": "ci-pipeline"}},
        {"key": "ci.pipeline.id", "value": {"stringValue": "${PIPELINE_ID}"}},
        {"key": "ci.branch", "value": {"stringValue": "${BRANCH}"}},
        {"key": "ci.commit_sha", "value": {"stringValue": "${COMMIT_SHA}"}}
      ]
    },
    "scopeSpans": [{
      "scope": {"name": "lab-aula5", "version": "1.0"},
      "spans": [
        {
          "traceId": "${TRACE_ID}",
          "spanId": "${SID_ROOT}",
          "name": "pipeline",
          "kind": 1,
          "startTimeUnixNano": "$(ns 0)",
          "endTimeUnixNano": "${PIPELINE_END}",
          "attributes": [
            {"key": "ci.pipeline.id", "value": {"stringValue": "${PIPELINE_ID}"}},
            {"key": "ci.branch", "value": {"stringValue": "${BRANCH}"}},
            {"key": "ci.commit_sha", "value": {"stringValue": "${COMMIT_SHA}"}}
          ],
          "status": {"code": 2, "message": "DAST encontrou vulnerabilidade crítica"}
        },
        {
          "traceId": "${TRACE_ID}",
          "spanId": "${SID_CHECKOUT}",
          "parentSpanId": "${SID_ROOT}",
          "name": "checkout",
          "kind": 1,
          "startTimeUnixNano": "$(ns 0)",
          "endTimeUnixNano": "$(ns 12)",
          "attributes": [
            {"key": "git.ref", "value": {"stringValue": "${BRANCH}"}},
            {"key": "git.commit", "value": {"stringValue": "${COMMIT_SHA}"}}
          ],
          "status": {"code": 1}
        },
        {
          "traceId": "${TRACE_ID}",
          "spanId": "${SID_BUILD}",
          "parentSpanId": "${SID_ROOT}",
          "name": "build",
          "kind": 1,
          "startTimeUnixNano": "$(ns 12)",
          "endTimeUnixNano": "$(ns 137)",
          "status": {"code": 1}
        },
        {
          "traceId": "${TRACE_ID}",
          "spanId": "${SID_CACHE}",
          "parentSpanId": "${SID_BUILD}",
          "name": "restore-cache",
          "kind": 3,
          "startTimeUnixNano": "$(ns 12)",
          "endTimeUnixNano": "$(ns 30)",
          "events": [
            {
              "name": "cache.hit",
              "timeUnixNano": "$(ns 14)",
              "attributes": [
                {"key": "cache.key", "value": {"stringValue": "build-deps-${COMMIT_SHA}"}},
                {"key": "cache.hit", "value": {"boolValue": true}}
              ]
            }
          ],
          "status": {"code": 1}
        },
        {
          "traceId": "${TRACE_ID}",
          "spanId": "${SID_COMPILE}",
          "parentSpanId": "${SID_BUILD}",
          "name": "compile",
          "kind": 1,
          "startTimeUnixNano": "$(ns 30)",
          "endTimeUnixNano": "$(ns 137)",
          "status": {"code": 1}
        },
        {
          "traceId": "${TRACE_ID}",
          "spanId": "${SID_TEST}",
          "parentSpanId": "${SID_ROOT}",
          "name": "test-unit",
          "kind": 1,
          "startTimeUnixNano": "$(ns 137)",
          "endTimeUnixNano": "$(ns 237)",
          "attributes": [
            {"key": "test.passed", "value": {"intValue": "142"}},
            {"key": "test.failed", "value": {"intValue": "0"}},
            {"key": "test.coverage_pct", "value": {"doubleValue": 87.3}}
          ],
          "status": {"code": 1}
        },
        {
          "traceId": "${TRACE_ID}",
          "spanId": "${SID_SECURITY}",
          "parentSpanId": "${SID_ROOT}",
          "name": "security",
          "kind": 1,
          "startTimeUnixNano": "$(ns 237)",
          "endTimeUnixNano": "$(ns 462)",
          "attributes": [
            {"key": "gate.result", "value": {"stringValue": "failed"}}
          ],
          "status": {"code": 2, "message": "Gate de segurança falhou"}
        },
        {
          "traceId": "${TRACE_ID}",
          "spanId": "${SID_SAST}",
          "parentSpanId": "${SID_SECURITY}",
          "name": "sast-scan",
          "kind": 1,
          "startTimeUnixNano": "$(ns 237)",
          "endTimeUnixNano": "$(ns 317)",
          "attributes": [
            {"key": "gate.name", "value": {"stringValue": "sast"}},
            {"key": "gate.result", "value": {"stringValue": "passed"}},
            {"key": "gate.findings.total", "value": {"intValue": "${SAST_FINDINGS}"}},
            {"key": "gate.findings.critical", "value": {"intValue": "0"}}
          ],
          "status": {"code": 1}
        },
        {
          "traceId": "${TRACE_ID}",
          "spanId": "${SID_SCA}",
          "parentSpanId": "${SID_SECURITY}",
          "name": "sca-scan",
          "kind": 1,
          "startTimeUnixNano": "$(ns 317)",
          "endTimeUnixNano": "$(ns 372)",
          "attributes": [
            {"key": "gate.name", "value": {"stringValue": "sca"}},
            {"key": "gate.result", "value": {"stringValue": "passed"}},
            {"key": "gate.findings.total", "value": {"intValue": "${SCA_FINDINGS}"}},
            {"key": "gate.findings.critical", "value": {"intValue": "0"}}
          ],
          "status": {"code": 1}
        },
        {
          "traceId": "${TRACE_ID}",
          "spanId": "${SID_DAST}",
          "parentSpanId": "${SID_SECURITY}",
          "name": "dast-scan",
          "kind": 1,
          "startTimeUnixNano": "$(ns 372)",
          "endTimeUnixNano": "$(ns 462)",
          "attributes": [
            {"key": "gate.name", "value": {"stringValue": "dast"}},
            {"key": "gate.result", "value": {"stringValue": "failed"}},
            {"key": "gate.findings.total", "value": {"intValue": "${DAST_CRITICAL}"}},
            {"key": "gate.findings.critical", "value": {"intValue": "${DAST_CRITICAL}"}}
          ],
          "events": [
            {
              "name": "gate.failed",
              "timeUnixNano": "$(ns 450)",
              "attributes": [
                {"key": "gate.name", "value": {"stringValue": "dast"}},
                {"key": "reason", "value": {"stringValue": "critical-vulnerability-found"}},
                {"key": "findings.critical", "value": {"intValue": "${DAST_CRITICAL}"}},
                {"key": "cve", "value": {"stringValue": "CVE-2026-0001"}}
              ]
            }
          ],
          "status": {"code": 2, "message": "DAST encontrou ${DAST_CRITICAL} vulnerabilidade(s) crítica(s)"}
        }${DEPLOY_SPAN}
      ]
    }]
  }]
}
TRACE_JSON

echo "📡 Enviando trace para ${OTEL_ENDPOINT}/v1/traces..."

HTTP_TRACE=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
  "${OTEL_ENDPOINT}/v1/traces" \
  -H "Content-Type: application/json" \
  -d @"$TMPFILE")

if [[ "$HTTP_TRACE" == "200" ]]; then
  echo "✅ Trace enviado (HTTP ${HTTP_TRACE})"
else
  echo "❌ Erro ao enviar trace (HTTP ${HTTP_TRACE})"
fi

# ── Emite métrica histogram com exemplar (métrica→trace) ─────
DURATION=492
# Buckets OTLP (não-cumulativos) para 492s com bounds [60,120,180,300,600,900]
cat > "$TMPFILE" << METRIC_JSON
{
  "resourceMetrics": [{
    "resource": {
      "attributes": [
        {"key": "service.name", "value": {"stringValue": "ci-pipeline"}}
      ]
    },
    "scopeMetrics": [{
      "scope": {"name": "lab-aula5", "version": "1.0"},
      "metrics": [{
        "name": "pipeline_duration_seconds",
        "histogram": {
          "aggregationTemporality": 2,
          "dataPoints": [{
            "startTimeUnixNano": "$(ns 0)",
            "timeUnixNano": "$(ns ${DURATION})",
            "count": "1",
            "sum": ${DURATION}.0,
            "bucketCounts": ["0","0","0","0","1","0","0"],
            "explicitBounds": [60.0,120.0,180.0,300.0,600.0,900.0],
            "exemplars": [{
              "timeUnixNano": "$(ns ${DURATION})",
              "asDouble": ${DURATION}.0,
              "traceId": "${TRACE_ID}",
              "spanId": "${SID_ROOT}"
            }],
            "attributes": [
              {"key": "branch", "value": {"stringValue": "${BRANCH}"}},
              {"key": "status", "value": {"stringValue": "failed"}}
            ]
          }]
        }
      },
      {
        "name": "pipeline_runs_total",
        "sum": {
          "dataPoints": [{
            "asInt": "1",
            "startTimeUnixNano": "$(ns 0)",
            "timeUnixNano": "$(ns ${DURATION})",
            "attributes": [
              {"key": "branch", "value": {"stringValue": "${BRANCH}"}},
              {"key": "status", "value": {"stringValue": "failed"}}
            ],
            "exemplars": [{
              "timeUnixNano": "$(ns ${DURATION})",
              "asDouble": 1.0,
              "traceId": "${TRACE_ID}",
              "spanId": "${SID_ROOT}"
            }]
          }],
          "aggregationTemporality": 2,
          "isMonotonic": true
        }
      }]
    }]
  }]
}
METRIC_JSON

echo "📡 Enviando métricas com exemplar..."

HTTP_METRIC=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
  "${OTEL_ENDPOINT}/v1/metrics" \
  -H "Content-Type: application/json" \
  -d @"$TMPFILE")

if [[ "$HTTP_METRIC" == "200" ]]; then
  echo "✅ Métricas com exemplar enviadas (HTTP ${HTTP_METRIC})"
else
  echo "❌ Erro ao enviar métricas (HTTP ${HTTP_METRIC})"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 Trace ID: ${TRACE_ID}"
echo ""
echo "🔍 Visualizar no Grafana (Tempo):"
echo "   http://localhost:3000/explore"
echo "   → Datasource: Tempo → TraceID: ${TRACE_ID}"
echo ""
echo "🔍 Visualizar no Jaeger:"
echo "   http://localhost:16686"
echo "   → Service: ci-pipeline → Find Traces"
echo ""
echo "📊 TraceQL para experimentar:"
echo '   { resource.service.name = "ci-pipeline" && status = error }'
echo '   { name = "dast-scan" && duration > 60s }'
echo '   { name = "sast-scan" && span.gate.findings.critical > 0 }'
echo '   { resource.service.name = "ci-pipeline" } >> { name = "deploy-staging" }'
echo ""
echo "🔗 Exemplar (métrica→trace):"
echo "   No Grafana → Explore → Prometheus"
echo "   Query: pipeline_duration_seconds_bucket"
echo "   Ative 'Exemplars' no painel → clique no diamante para saltar ao trace"
