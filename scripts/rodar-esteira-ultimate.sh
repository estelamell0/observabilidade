#!/usr/bin/env bash
# ==============================================================================
# GABARITO PROJETO FINAL: O LAB "ULTIMATE"
# ==============================================================================
# Este script orquestra toda a jornada da disciplina de Observabilidade e
# Compliance (Aulas 1 a 9). Ele gera um único contexto (Trace ID e Commit SHA)
# e faz ele fluir através de TODAS as ferramentas: Tracing, Logging, Metrics,
# Hash Chaining, Policy-as-Code e geração de Dossiê.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}/.."

# ── 1. Geração do Contexto Único ──────────────────────────────────────────────
gen_hex() {
  local len=$1 result=""
  for ((i=0; i<len; i++)); do result+=$(printf '%x' $((RANDOM % 16))); done
  echo "$result"
}

export ULTIMATE_TRACE_ID=$(gen_hex 32)
export ULTIMATE_COMMIT_SHA=$(gen_hex 8)
export ULTIMATE_PIPELINE_ID="ultimate-$(gen_hex 8)"
DEPLOY_ID="deploy-$(gen_hex 4)"

echo "🚀 INICIANDO GABARITO DO PROJETO FINAL (LAB ULTIMATE)"
echo "======================================================"
echo " 🆔 Contexto Global Criado:"
echo "    - Trace ID:   ${ULTIMATE_TRACE_ID}"
echo "    - Commit SHA: ${ULTIMATE_COMMIT_SHA}"
echo "    - Deploy ID:  ${DEPLOY_ID}"
echo "======================================================"
echo ""

# ── 2. Tracing Completo & Exemplars (Aulas 2 e 5) ─────────────────────────────
echo "⏳ [1/6] Gerando Traces e Waterfall OTLP..."
./scripts/gerar-trace-completo.sh --branch main
echo "✅ Traces injetados no Tempo e Jaeger."
echo ""

# ── 3. Logging Estruturado e Sanitização de PII (Aula 4) ──────────────────────
echo "⏳ [2/6] Gerando Logs Estruturados com PII..."
# O script abaixo usará o mesmo TRACE_ID por causa das env vars
./scripts/gerar-logs-pipeline.sh > /dev/null
echo "✅ Logs gerados em logs/pipeline.log (PII será mascarado pelo OTel Collector)."
echo ""

# ── 4. Policy-as-Code (Aula 7) ────────────────────────────────────────────────
echo "⏳ [3/6] Validando manifestos contra políticas OPA..."
# Simulamos que os manifestos válidos passaram (vamos gerar apenas o evidence file)
mkdir -p evidence
docker run --rm -v "/$(pwd)":/app -w /app openpolicyagent/conftest test manifests/deployment-valid.yaml --policy policy/ --output json > evidence/policy.json 2>/dev/null || true
echo "✅ Validação OPA concluída. Resultado salvo em evidence/policy.json."
echo ""

# ── 5. Auditoria Imutável (Aula 6) ────────────────────────────────────────────
echo "⏳ [4/6] Consolidando Cadeia de Custódia da Aprovação..."
# Chamamos o script Python para validar o hash chain mockado
PYTHONUTF8=1 PYTHONIOENCODING=utf-8 python3 ./scripts/lab-auditoria-hash-chain.py || true
# Vamos manualmente injetar o evento de deploy.approved no Loki para o Dossiê via OTLP
# Isso simula que o pipeline emitiu o log de aprovação
echo "{\"timestamp\":\"$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")\",\"level\":\"INFO\",\"job\":\"ci_pipeline\",\"event\":\"deploy.approved\",\"ci_commit_sha\":\"${ULTIMATE_COMMIT_SHA}\",\"approver\":\"diretoria-ciso\"}" >> logs/pipeline.log
echo "✅ Evento de aprovação auditável gerado."
echo ""

# ── 6. Disparo de Anomalia para Falco (Aula 6) ────────────────────────────────
echo "⏳ [5/6] Simulando anomalia no ambiente para o Falco..."
# Para fins de simulação local, apenas lemos o shadow se o falco estiver rodando localmente
# Em um container rodando, isso dispararia o alerta.
cat /etc/shadow 2>/dev/null || echo "Acesso negado a shadow (esperado)" > /dev/null
echo "✅ Evento sensível emitido (verifique logs do Falco)."
echo ""

# ── 7. Dossiê de Compliance Contínuo (Aula 8) ─────────────────────────────────
echo "⏳ [6/6] Gerando Dossiê Automático de Compliance (CaC)..."
./scripts/gerar_dossie.sh "${DEPLOY_ID}" "${ULTIMATE_COMMIT_SHA}"
echo ""

echo "======================================================"
echo "🎯 LAB ULTIMATE CONCLUÍDO COM SUCESSO!"
echo "======================================================"
echo "O que fazer agora:"
echo "1. Abra o Grafana (http://localhost:3000)"
echo "2. Vá no Explore -> Loki e pesquise por:"
echo "   {job=\"ci-pipeline\"} |= \"${ULTIMATE_TRACE_ID}\""
echo "3. Clique no botão azul do trace_id e veja o waterfall no Tempo."
echo "4. Vá no Dashboard 'Compliance e Auditoria Contínua' e verifique as métricas."
echo "5. Verifique a pasta dossie/${DEPLOY_ID} localmente."
