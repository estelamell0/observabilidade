#!/usr/bin/env bash
# ============================================================
# Lab Aula 2: Gera trace de pipeline com otel-cli
# Pré-requisito: otel-cli (https://github.com/equinix-labs/otel-cli)
# ============================================================
set -euo pipefail

ENDPOINT="${OTEL_EXPORTER_OTLP_ENDPOINT:-localhost:4317}"

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
OTEL_CLI="$DIR/otel-cli.exe"

# Verifica se otel-cli está instalado
if [ ! -f "$OTEL_CLI" ]; then
  if command -v otel-cli &>/dev/null; then
    OTEL_CLI="otel-cli"
  else
    echo "❌ otel-cli.exe não encontrado na pasta scripts nem no PATH. Instale:"
    echo "   https://github.com/equinix-labs/otel-cli/releases"
    exit 1
  fi
fi

# Gera identificadores aleatórios
gen_hex() {
  local len=$1 result=""
  for ((i=0; i<len; i++)); do
    result+=$(printf '%x' $((RANDOM % 16)))
  done
  echo "$result"
}

PIPELINE_ID="pipe-$(gen_hex 8)"
COMMIT_SHA=$(gen_hex 8)
COMMON_ATTRS="ci.pipeline.id=${PIPELINE_ID},ci.branch=main,ci.commit_sha=${COMMIT_SHA}"

# Gera W3C Trace Context para agrupar spans no mesmo trace
TRACE_ID=$(gen_hex 32)
SPAN_ID=$(gen_hex 16)
export TRACEPARENT="00-${TRACE_ID}-${SPAN_ID}-01"

echo "🚀 Pipeline ${PIPELINE_ID} (commit: ${COMMIT_SHA:0:8})"
echo "   Trace ID: ${TRACE_ID}"
echo "   Endpoint: ${ENDPOINT}"
echo ""

# ─── Stage 1: init ───────────────────────────────────────────
echo "  [1/4] init (2s)"
"$OTEL_CLI" exec \
  --service "ci-pipeline" \
  --name "init" \
  --attrs "${COMMON_ATTRS}" \
  --endpoint "${ENDPOINT}" \
  --protocol grpc \
  --insecure \
  -- sleep 2

# ─── Stage 2: build ─────────────────────────────────────────
echo "  [2/4] build (5s)"
"$OTEL_CLI" exec \
  --service "ci-pipeline" \
  --name "build" \
  --attrs "${COMMON_ATTRS}" \
  --endpoint "${ENDPOINT}" \
  --protocol grpc \
  --insecure \
  -- sleep 5

# ─── Stage 3: sast-scan (FALHA) ─────────────────────────────
echo "  [3/4] sast-scan (3s) — FALHA simulada"
"$OTEL_CLI" exec \
  --service "ci-pipeline" \
  --name "sast-scan" \
  --attrs "${COMMON_ATTRS},gate.name=sast" \
  --endpoint "${ENDPOINT}" \
  --protocol grpc \
  --insecure \
  -- bash -c 'sleep 3; exit 1' || true

# ─── Stage 4: deploy-staging (condicional) ───────────────────
if [[ -n "${FORCE_DEPLOY:-}" ]]; then
  echo "  [4/4] deploy-staging (2s)"
  "$OTEL_CLI" exec \
    --service "ci-pipeline" \
    --name "deploy-staging" \
    --attrs "${COMMON_ATTRS},gate.name=deploy" \
    --endpoint "${ENDPOINT}" \
    --protocol grpc \
    --insecure \
    -- sleep 2
else
  echo "  [4/4] deploy-staging ⏭ SKIP (defina FORCE_DEPLOY=1 para executar)"
fi

echo ""
echo "✅ Trace completo!"
echo "   Trace ID: ${TRACE_ID}"
echo ""
echo "   Abra no Grafana:"
echo "   http://localhost:3000/explore → Datasource: Tempo → TraceID: ${TRACE_ID}"
