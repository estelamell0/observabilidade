#!/usr/bin/env bash
# ============================================================
# Lab Aula 4: Geração de logs estruturados em JSON para o pipeline
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOG_DIR="${PROJECT_ROOT}/logs"
LOG_FILE="${LOG_DIR}/pipeline.log"

mkdir -p "${LOG_DIR}"

# 1. Limpar logs anteriores
> "${LOG_FILE}"

# Gerador de strings hexadecimais aleatórias
gen_hex() {
  local len=$1 result=""
  for ((i=0; i<len; i++)); do
    result+=$(printf '%x' $((RANDOM % 16)))
  done
  echo "$result"
}

# Identificadores fixos da execução
PIPELINE_ID="${ULTIMATE_PIPELINE_ID:-pipe-$(gen_hex 8)}"
COMMIT_SHA="${ULTIMATE_COMMIT_SHA:-$(gen_hex 8)}"
TRACE_ID="${ULTIMATE_TRACE_ID:-$(gen_hex 32)}"

# Função portátil para obter timestamp ISO-8601 UTC com milissegundos
get_timestamp() {
  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")
  if [[ "$ts" == *"%3N"* ]]; then
    # Fallback caso %3N não seja suportado (ex.: macOS BSD date)
    ts=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")
  fi
  echo "$ts"
}

# Escreve um log estruturado em JSON no arquivo
write_log() {
  local level="$1"
  local event="$2"
  local message="$3"
  local extra_fields="${4:-}"
  
  local ts
  ts=$(get_timestamp)
  local span_id
  span_id=$(gen_hex 16)
  
  local json="{\"timestamp\":\"${ts}\",\"level\":\"${level}\",\"service\":\"ci-pipeline\",\"event\":\"${event}\",\"ci.pipeline_id\":\"${PIPELINE_ID}\",\"ci.commit_sha\":\"${COMMIT_SHA}\",\"ci.branch\":\"main\",\"trace_id\":\"${TRACE_ID}\",\"span_id\":\"${span_id}\",\"message\":\"${message}\""
  if [[ -n "$extra_fields" ]]; then
    json="${json},${extra_fields}"
  fi
  json="${json}}"
  
  echo "$json" >> "${LOG_FILE}"
}

echo "🚀 Iniciando simulação do pipeline (Lab Aula 4)..."
echo "   Pipeline ID: ${PIPELINE_ID}"
echo "   Commit SHA:  ${COMMIT_SHA}"
echo "   Trace ID:    ${TRACE_ID}"
echo "   Arquivo:     ${LOG_FILE}"
echo ""

# 1. pipeline.started
echo "  [1/9] pipeline.started"
write_log "INFO" "pipeline.started" "Pipeline execution started for branch main"
sleep 0.5

# 2. checkout.completed
echo "  [2/9] checkout.completed"
write_log "INFO" "checkout.completed" "Source code checked out successfully from git repository"
sleep 0.5

# 3. build.completed
echo "  [3/9] build.completed"
write_log "INFO" "build.completed" "Application build finished successfully, artifact created"
sleep 0.5

# 4. test.completed
echo "  [4/9] test.completed"
write_log "INFO" "test.completed" "Unit tests completed: 154 passed, 0 failed"
sleep 0.5

# 5. gate.passed (SCA)
echo "  [5/9] gate.passed"
write_log "INFO" "gate.passed" "SCA (Software Composition Analysis) dependency scan completed successfully" '"gate":"SCA","findings_critical":0,"findings_high":0'
sleep 0.5

# 6. gate.failed (SAST)
echo "  [6/9] gate.failed"
write_log "ERROR" "gate.failed" "SAST security gate failed with critical vulnerabilities detected in codebase" '"gate":"SAST","findings_critical":2,"findings_high":5'
sleep 0.5

# 7. secret.accessed (com CPF fictício no campo user_cpf)
echo "  [7/9] secret.accessed (Audit - Contém CPF)"
write_log "WARN" "secret.accessed" "Vault database secrets accessed by deployment workflow" '"secret_name":"prod-database-credentials","user_cpf":"123.456.789-00"'
sleep 0.5

# 8. deploy.approved (com email fictício e approver)
echo "  [8/9] deploy.approved (Audit - Contém E-mail)"
write_log "INFO" "deploy.approved" "Manual deploy to production approved by supervisor" '"approver":"admin-estela","user_email":"estela.auditora@empresa.com"'
sleep 0.5

# 9. deploy.completed
echo "  [9/9] deploy.completed"
write_log "INFO" "deploy.completed" "Deployment to production environment completed successfully"
sleep 0.5

echo ""
echo "✅ Pipeline simulado e logs gravados em ${LOG_FILE}!"
echo ""
echo "   📝 Trace ID Gerado: ${TRACE_ID}"
echo ""
echo "   💡 Dicas de Verificação no Grafana:"
echo "      1. Verifique no Loki que o CPF foi mascarado para '[CPF_REDACTED]'"
echo "      2. Verifique que o e-mail foi parcialmente mascarado para 'est***@empresa.com'"
echo "      3. Clique no 'trace_id' azul no log do Loki para navegar ao trace no Tempo"
echo "      4. No Tempo, use o link de 'Logs' para voltar ao log no Loki"
echo ""

# ============================================================
# QUERIES LOGQL DE REFERÊNCIA PARA O LAB (COPIAR E COLAR NO EXPLORE)
# ============================================================
#
# 1. Todos os erros do pipeline:
#    {job="ci-pipeline", level="ERROR"}
#
# 2. Erros filtrando por gate.failed no conteúdo:
#    {job="ci-pipeline", level="ERROR"} |= "gate.failed"
#
# 3. Contagem de gates reprovados por tipo (metric query, 5 min):
#    sum by (gate) (count_over_time({job="ci-pipeline"} | json | event="gate.failed" [5m]))
#
# 4. Buscar logs de um trace específico pelo trace_id:
#    {job="ci-pipeline"} | json | trace_id="${TRACE_ID}"
#
# 5. Taxa de erro por serviço (rate, 5 min):
#    sum by (service) (rate({job="ci-pipeline"} | json | level="ERROR" [5m]))
#
# 6. Verificar que o CPF foi mascarado (deve retornar [CPF_REDACTED]):
#    {job="ci-pipeline"} |= "CPF_REDACTED"
#
# 7. Verificar que o CPF original NÃO aparece (deve retornar ZERO resultados):
#    {job="ci-pipeline"} |~ "\\d{3}\\.\\d{3}\\.\\d{3}-\\d{2}"
#
