#!/bin/bash
# Script para facilitar os testes das políticas do OPA

echo "=== Testando políticas com OPA ==="
# Executa testes em todos os arquivos _test.rego no diretório policy
opa test policy/ -v

echo ""
echo "=== Testando Conftest com manifestos ==="
# Validando manifesto válido
echo "-> Testando deployment-valid.yaml"
conftest test manifests/deployment-valid.yaml --policy policy/

# Validando manifesto inválido
echo "-> Testando deployment-invalid.yaml"
# Esse teste falhará por design, então permitimos que o script continue
conftest test manifests/deployment-invalid.yaml --policy policy/ || echo "=> Falha esperada no manifesto inválido."

echo ""
echo "=== Gerando evidência JSON com Conftest ==="
mkdir -p evidence
conftest test manifests/deployment-valid.yaml --policy policy/ --output json > evidence/policy-result-valid.json
echo "=> Evidência de sucesso gerada em evidence/policy-result-valid.json"
