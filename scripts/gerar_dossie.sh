#!/usr/bin/env bash
# gerar_dossie.sh — monta o dossiê de compliance de um deploy específico
set -euo pipefail

if [ "$#" -lt 2 ]; then
  echo "Uso: $0 <DEPLOY_ID> <COMMIT_SHA>"
  echo "Ex: $0 deploy-123 7f8a9b2c"
  exit 1
fi

DEPLOY_ID="$1"
SHA="$2"
PROM="http://localhost:9090"
LOKI="http://localhost:3100"
OUT="dossie/$DEPLOY_ID"
mkdir -p "$OUT"

echo "Gerando dossiê de compliance para deploy $DEPLOY_ID (commit: $SHA)..."

# 1) Resultados dos gates (métricas)
echo "  - Coletando resultados de gates (Prometheus)..."
# Busca a métrica gate_findings filtrando pelo commit (se estiver instrumentado assim)
# Ou busca genericamente
curl -s -g "$PROM/api/v1/query" \
  --data-urlencode "query=gate_findings" > "$OUT/gates.json" || true

# 2) Aprovações (eventos de auditoria)
echo "  - Coletando eventos de aprovação (Loki)..."
curl -s -g "$LOKI/loki/api/v1/query_range" \
  --data-urlencode 'query={job="ci_pipeline"} | json | event="deploy.approved"' \
  > "$OUT/approvals.json" || true

# 3) Resultado das políticas (PaC)
echo "  - Buscando avaliação de políticas (se existir)..."
if [ -f "evidence/policy.json" ]; then
  cp evidence/policy.json "$OUT/" 2>/dev/null || true
else
  echo "{\"status\": \"no_policy_evidence_found\"}" > "$OUT/policy.json"
fi

# 4) Manifesto de integridade (cadeia de custódia)
echo "  - Gerando manifesto de integridade (SHA-256)..."
( cd "$OUT" && sha256sum ./* > MANIFEST.sha256 )

echo ""
echo "✅ Dossiê pronto em $OUT/"
echo "Conteúdo do manifesto:"
cat "$OUT/MANIFEST.sha256"
echo ""
echo "Verifique a integridade a qualquer momento com:"
echo "cd $OUT && sha256sum -c MANIFEST.sha256"
