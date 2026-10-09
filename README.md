# Lab Observabilidade

Stack open-source para os laboratórios das Aulas 1, 2 e 3 da disciplina
**Observabilidade, Auditoria e Compliance de Pipelines DevSecOps**.

## Pré-requisitos

| Ferramenta | Obrigatório | Link |
|---|---|---|
| Docker + Docker Compose | Sim | https://docs.docker.com/get-docker/ |
| curl | Sim | Já incluso na maioria dos OS |
| bash | Sim | Git Bash (Windows), Terminal (macOS/Linux) |
| otel-cli | Lab Aula 2 | https://github.com/equinix-labs/otel-cli/releases |

## Quick Start

```bash
# Subir toda a stack
docker compose up -d

# Verificar status
docker compose ps
```

## Acesso aos Serviços

| Serviço | URL | Notas |
|---|---|---|
| **Grafana** | http://localhost:3000 | Login anônimo, role Admin |
| **Prometheus** | http://localhost:9090 | |
| **Pushgateway** | http://localhost:9091 | |
| **OTel Collector** | http://localhost:13133 | Health check |
| **Tempo** | http://localhost:3200 | API de consulta (usado pelo Grafana) |
| **Loki** | http://localhost:3100 | |
| **Promtail** | http://localhost:9080 | Health / targets |

---

## Lab Aula 1 — Métrica OTLP/HTTP

Emite a métrica `pipeline_runs_total` via POST OTLP/HTTP para o Collector.

```bash
# Emitir com valores padrão (branch=main, status=success)
./scripts/emitir-metrica-otlp.sh

# Emitir com parâmetros customizados
./scripts/emitir-metrica-otlp.sh --branch feature/auth --status failed
```

**Verificação:**

1. Abra http://localhost:9090 → aba **Graph**
2. Query: `pipeline_runs_total`
3. Abra http://localhost:3000 → dashboard **Saúde da Esteira**

---

## Lab Aula 2 — Trace de Pipeline com otel-cli

Gera um trace completo simulando 4 stages de pipeline como spans-filhos.

### Instalar otel-cli

```bash
# Linux/macOS
curl -L https://github.com/equinix-labs/otel-cli/releases/latest/download/otel-cli_Linux_x86_64.tar.gz \
  | tar xz -C /usr/local/bin otel-cli

# Verificar
otel-cli version
```

### Executar

```bash
# Execução padrão (sast-scan FALHA, deploy-staging é pulado)
./scripts/gerar-trace-pipeline.sh

# Forçar deploy mesmo após falha
FORCE_DEPLOY=1 ./scripts/gerar-trace-pipeline.sh
```

**Verificação:**

1. Copie o **Trace ID** impresso no terminal
2. Abra http://localhost:3000 → **Explore**
3. Selecione datasource **Tempo**
4. Cole o Trace ID → clique em **Run query**
5. Visualize os spans: `init → build → sast-scan (erro) → deploy-staging`

---

## Lab Aula 3 — Simulação de Pipelines + Dashboard

Empurra métricas de 5 pipelines simuladas ao Pushgateway.

```bash
./scripts/simular-pipelines.sh
```

**Verificação:**

1. **Prometheus** — http://localhost:9090
   - `pipeline_runs_total` — contadores por branch/status
   - `pipeline_duration_seconds_bucket` — histograma de duração
   - `gate_findings` — findings por gate/severidade
   - `deploy_total` — deploys por env/resultado
   - `pipeline:success_rate:1h` — recording rule
   - `pipeline:duration_p95:1h` — recording rule

2. **Dashboard** — http://localhost:3000/d/saude-esteira/saude-da-esteira
   - Use a variável `$branch` para filtrar por branch
   - Verifique os 6 painéis: Taxa de Sucesso, Duração, Findings, Deploy Frequency, Change Failure Rate, Cobertura de Gate

3. **Alertas** — http://localhost:9090/alerts
   - `AltaTaxaDeFalhaPipeline` — dispara se >20% falhas em 15m
   - `FindingCriticoEmGate` — dispara se existir finding crítico
   - `DeploySemCoberturaDeGate` — dispara se deploy prod sem gate

4. **Forçar alertas:** Execute 3+ vezes com falhas:
   ```bash
   for i in 1 2 3; do
     ./scripts/emitir-metrica-otlp.sh --status failed
   done
   ```

---

## Lab Aula 4 — Logs Centralizados e Logging Seguro

**Pré-requisito:** stack já rodando (`docker compose up -d`) com o serviço `promtail` adicionado.

1. Verifique que Promtail está saudável: http://localhost:9080/targets (deve mostrar o job "ci-logs" com o path `/var/log/ci/*.log`).

2. Execute o script de geração de logs:
   ```bash
   chmod +x scripts/gerar-logs-pipeline.sh
   ./scripts/gerar-logs-pipeline.sh
   ```
   Anote o `trace_id` impresso na saída.

3. No Grafana → Explore → selecione Loki:
   a. Consulte `{job="ci-pipeline", level="ERROR"}` — veja os erros.
   b. Consulte `{job="ci-pipeline"} |= "CPF_REDACTED"` — confirme que o CPF foi mascarado pelo Promtail.
   c. Consulte `{job="ci-pipeline"} |~ "\\d{3}\\.\\d{3}\\.\\d{3}-\\d{2}"` — confirme que retorna ZERO resultados (CPF original não está no Loki).
   d. Consulte `{job="ci-pipeline"} | json | trace_id="<SEU_TRACE_ID>"` — veja todos os logs daquela execução.

4. Clique no `trace_id` que aparece como link azul no log (derived field) → deve abrir o trace correspondente no Tempo.

5. No Tempo, abra um span → clique em "Logs for this span" → deve voltar para os logs correlacionados no Loki (trace-to-logs).

**Resultado esperado:** Logs estruturados pesquisáveis via LogQL, PII comprovadamente mascarada antes do armazenamento, e navegação bidirecional funcional log ↔ trace.

### Queries LogQL de Referência para o Lab

Você pode copiar e colar estas queries no Grafana Explore (Loki):

```logql
# 1. Todos os erros do pipeline
{job="ci-pipeline", level="ERROR"}

# 2. Erros filtrando por gate.failed no conteúdo
{job="ci-pipeline", level="ERROR"} |= "gate.failed"

# 3. Contagem de gates reprovados por tipo (metric query, 5 min)
sum by (gate) (
  count_over_time({job="ci-pipeline"} | json | event="gate.failed" [5m])
)

# 4. Buscar logs de um trace específico pelo trace_id
{job="ci-pipeline"} | json | trace_id="<TRACE_ID_GERADO>"

# 5. Taxa de erro por serviço (rate, 5 min)
sum by (service) (rate({job="ci-pipeline"} | json | level="ERROR" [5m]))

# 6. Verificar que o CPF foi mascarado (deve retornar [CPF_REDACTED])
{job="ci-pipeline"} |= "CPF_REDACTED"

# 7. Verificar que o CPF original NÃO aparece (deve retornar ZERO resultados)
{job="ci-pipeline"} |~ "\\d{3}\\.\\d{3}\\.\\d{3}-\\d{2}"
```

**Troubleshooting:**
- **Nenhum log aparece**: Promtail não está lendo o diretório; verifique http://localhost:9080/targets e os bind-mounts.
- **CPF aparece em claro**: regra de replace no Promtail não está capturando; verifique o regex e rode `docker compose logs promtail`.
- **Link de trace_id não aparece**: derived field mal configurado no datasource Loki; verifique o regex e o UID do Tempo.
- **Loki está lento/instável**: você promoveu um campo de alta cardinalidade (`trace_id`, `commit_sha`) a label do Loki; reverta.
- **"Logs for this span" não funciona**: `tracesToLogs` no datasource Tempo não está configurado ou o UID do Loki está incorreto.

---

## Lab Aula 5 — OpenTelemetry (Exemplars e Tail Sampling)

**Objetivo:** Demonstrar a correlação de Métrica ➡️ Trace (Exemplars) e a configuração de retenção inteligente (Tail Sampling) no OTel Collector.

1. **Gere os dados completos:**
   ```bash
   ./scripts/gerar-trace-completo.sh
   ```

2. **Exemplars (Métrica ➡️ Trace):**
   - Vá no Prometheus (http://localhost:9090) e pesquise por `pipeline_duration_seconds_bucket`.
   - Veja os *diamantes azuis* flutuando. Clique em um deles para ver o `trace_id`.
   - No Grafana, visualize o painel "Duração das Execuções (com Exemplars)". Ao passar o mouse nos pontos marcados, clique em "Query with Tempo" para pular direto para o Trace.

3. **Tail Sampling:**
   - Gere traces simulando pipelines bem-sucedidos (`./scripts/gerar-trace-completo.sh`).
   - Tente pesquisar esses traces no Tempo. Eles **não** aparecerão, pois o Tail Sampling descarta sucessos normais (retendo apenas 10%).
   - Gere com erro (`./scripts/gerar-trace-completo.sh --force-deploy`). Ele será 100% retido por ser crítico.

---

## Lab Aula 6 — Segurança, Falco e Trilha Imutável (Hash Chaining)

**Objetivo:** Detectar anomalias em tempo de execução via eBPF e demonstrar criptografia para compliance.

1. **Suba o laboratório de segurança:**
   ```bash
   docker compose --profile aula6 up -d
   ```

2. **Teste o Falco na prática:**
   ```bash
   # Entre no container "ci-runner" simulando uma invasão
   docker exec -it ci-runner sh
   # Leia um arquivo sensível
   cat /etc/shadow
   ```
   - Vá no Grafana → Loki e pesquise `{app="falcosidekick"}` para ver os alertas gerados!

3. **Trilha Imutável (Hash Chaining):**
   - Execute o script autônomo para ver como a matemática protege uma trilha de auditoria:
     ```bash
     python scripts/lab-auditoria-hash-chain.py
     ```

---

## Lab Aula 7 — Policy-as-Code (OPA e Conftest)

**Objetivo:** Validar manifestos Kubernetes e saídas JSON automaticamente via código (Rego).

1. **Testando SAST:**
   ```bash
   docker run --rm -v ${PWD}:/app -w /app openpolicyagent/opa eval -i manifests/sast-result.json -d policy/ci/sast_gate.rego "data.ci.deny"
   ```

2. **Rodando Testes Unitários de Política:**
   ```bash
   docker run --rm -v ${PWD}:/app -w /app openpolicyagent/opa test policy/ -v
   ```

3. **Validando Manifestos (Conftest):**
   ```bash
   # Manifesto válido
   docker run --rm -v ${PWD}:/app -w /app openpolicyagent/conftest test manifests/deployment-valid.yaml --policy policy/
   
   # Manifesto inválido (erro: executa como root)
   docker run --rm -v ${PWD}:/app -w /app openpolicyagent/conftest test manifests/deployment-invalid.yaml --policy policy/
   ```

---

## Cleanup

```bash
# Parar e remover containers + volumes
docker compose down -v
```

---

## Troubleshooting

| Problema | Solução |
|---|---|
| Métrica não aparece no Prometheus | Confirme que o target `otel-collector:8889` está UP em http://localhost:9090/targets |
| Spans não aparecem no Tempo | Verifique logs: `docker compose logs otel-collector` |
| "connection refused" | Verifique se os containers estão rodando: `docker compose ps` |
| Métrica fantasma no Pushgateway | Delete o grupo: `curl -X DELETE http://localhost:9091/metrics/job/ci_pipeline/branch/BRANCH/run/N` |
| Percentil estranho no histogram | Ajuste os buckets (60,120,180,300,600,900) ou envie mais amostras |
| Dashboard sem dados | Aguarde ~30s após enviar métricas (scrape interval = 15s) |

---

## Arquitetura

```
┌─────────────┐  OTLP gRPC/HTTP   ┌──────────────────┐
│  Scripts /   │──────────────────▶│  OTel Collector   │
│  otel-cli    │                   │  :4317 :4318      │
└─────────────┘                   └───────┬───┬───┬───┘
                                          │   │   │
                           traces ────────┘   │   └──────── logs
                                              │
                              metrics ────────┘
                                  │
┌──────────┐  scrape    ┌─────────▼──┐         ┌────────┐
│Pushgateway│◀─────────│ Prometheus  │         │  Loki  │
│  :9091    │──────────▶│   :9090     │         │ :3100  │
└──────────┘           └──────┬──────┘         └───┬────┘
                              │                    │
                       ┌──────▼────────────────────▼────┐
                       │         Grafana :3000           │
                       │  Datasources: Prom, Loki, Tempo│
                       └────────────────────────────────┘
                              ▲
                       ┌──────┴──────┐
                       │  Tempo :3200 │
                       └─────────────┘
```
