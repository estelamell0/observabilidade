#!/usr/bin/env bash
# ============================================================
# Lab Aula 3: Simula 5 pipelines e empurra métricas ao Pushgateway
# ============================================================
set -euo pipefail

PUSHGATEWAY="${PUSHGATEWAY:-http://localhost:9091}"
BRANCHES=("main" "feature/auth" "feature/payments")
BUCKETS=(60 120 180 300 600 900)

echo "🚀 Simulando 5 execuções de pipeline..."
echo "   Pushgateway: ${PUSHGATEWAY}"
echo ""

for i in $(seq 1 5); do
  # ── Sorteia parâmetros ──────────────────────────────────
  BRANCH="${BRANCHES[$((RANDOM % ${#BRANCHES[@]}))]}"
  DURATION=$(( RANDOM % 841 + 60 ))  # 60-900s

  # Garante pelo menos 2 falhas (runs 2 e 4)
  if (( i == 2 || i == 4 )); then
    STATUS="failed"
  else
    (( RANDOM % 3 == 0 )) && STATUS="failed" || STATUS="success"
  fi

  # Findings aleatórios
  SAST_CRIT=$(( RANDOM % 4 ))       # 0-3
  SAST_HIGH=$(( RANDOM % 6 ))       # 0-5
  SAST_MED=$(( RANDOM % 10 ))       # 0-9
  SAST_LOW=$(( RANDOM % 15 ))       # 0-14
  SCA_CRIT=$(( RANDOM % 3 ))        # 0-2
  SCA_HIGH=$(( RANDOM % 9 ))        # 0-8
  SCA_MED=$(( RANDOM % 8 ))         # 0-7
  SCA_LOW=$(( RANDOM % 12 ))        # 0-11

  # Deploy
  if [[ "$STATUS" == "success" ]]; then
    DEPLOY_ENV="prod"; DEPLOY_RESULT="success"; GATE_EXEC="true"
  else
    DEPLOY_ENV="prod"; DEPLOY_RESULT="failed"; GATE_EXEC="false"
  fi

  # ── Calcula buckets do histogram ────────────────────────
  B60=0; B120=0; B180=0; B300=0; B600=0; B900=0
  (( DURATION <= 60 ))  && B60=1  || true
  (( DURATION <= 120 )) && B120=1 || true
  (( DURATION <= 180 )) && B180=1 || true
  (( DURATION <= 300 )) && B300=1 || true
  (( DURATION <= 600 )) && B600=1 || true
  (( DURATION <= 900 )) && B900=1 || true

  # ── Imprime resumo ─────────────────────────────────────
  printf "  [Run %d] %-20s status=%-7s duration=%4ds\n" "$i" "branch=${BRANCH}" "$STATUS" "$DURATION"
  printf "          findings: sast(C=%d H=%d M=%d L=%d) sca(C=%d H=%d M=%d L=%d)\n" \
    "$SAST_CRIT" "$SAST_HIGH" "$SAST_MED" "$SAST_LOW" \
    "$SCA_CRIT" "$SCA_HIGH" "$SCA_MED" "$SCA_LOW"

  # ── Push para Pushgateway ──────────────────────────────
  # Escapa a barra do nome da branch para a URL
  BRANCH_URL=$(echo "$BRANCH" | sed 's|/|%2F|g')

  cat <<METRICS | curl -s --data-binary @- "${PUSHGATEWAY}/metrics/job/ci_pipeline/branch/${BRANCH_URL}/run/${i}"
# TYPE pipeline_runs_total counter
pipeline_runs_total{status="${STATUS}"} 1
# TYPE pipeline_duration_seconds histogram
pipeline_duration_seconds_bucket{le="60"} ${B60}
pipeline_duration_seconds_bucket{le="120"} ${B120}
pipeline_duration_seconds_bucket{le="180"} ${B180}
pipeline_duration_seconds_bucket{le="300"} ${B300}
pipeline_duration_seconds_bucket{le="600"} ${B600}
pipeline_duration_seconds_bucket{le="900"} ${B900}
pipeline_duration_seconds_bucket{le="+Inf"} 1
pipeline_duration_seconds_sum ${DURATION}
pipeline_duration_seconds_count 1
# TYPE gate_findings gauge
gate_findings{gate="sast",severity="critical"} ${SAST_CRIT}
gate_findings{gate="sast",severity="high"} ${SAST_HIGH}
gate_findings{gate="sast",severity="medium"} ${SAST_MED}
gate_findings{gate="sast",severity="low"} ${SAST_LOW}
gate_findings{gate="sca",severity="critical"} ${SCA_CRIT}
gate_findings{gate="sca",severity="high"} ${SCA_HIGH}
gate_findings{gate="sca",severity="medium"} ${SCA_MED}
gate_findings{gate="sca",severity="low"} ${SCA_LOW}
# TYPE deploy_total counter
deploy_total{env="${DEPLOY_ENV}",result="${DEPLOY_RESULT}",gate_executed="${GATE_EXEC}"} 1
METRICS

done

echo ""
echo "✅ 5 pipelines simulados e enviados ao Pushgateway"
echo ""
echo "📊 Próximos passos:"
echo "   Prometheus:  http://localhost:9090 → query: pipeline_runs_total"
echo "   Pushgateway: http://localhost:9091"
echo "   Dashboard:   http://localhost:3000/d/saude-esteira/saude-da-esteira"
