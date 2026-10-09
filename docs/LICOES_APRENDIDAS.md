# Lições Aprendidas — Lab Local de Observabilidade (ClickHouse + OTel)

> Parte 1 do lab: subir a stack local em Docker Compose replicando o pipeline mínimo
> que a VM e2-micro (GCP free tier) vai executar via cloud-init, e validar o ciclo
> OTLP → Collector → ClickHouse antes do provisionamento Terraform.

## 1. Stack

- `clickhouse/clickhouse-server` — armazenamento (tabelas `otel_*`)
- `otel/opentelemetry-collector-contrib` — gateway OTLP (4317 gRPC / 4318 HTTP)
- `grafana/grafana-oss` — visualização (datasource ClickHouse provisionado)

Configurações relevantes:

- `docker-compose.yml`: healthcheck do ClickHouse (`SELECT 1`), `depends_on` com
  `condition: service_healthy` para collector e grafana.
- `clickhouse/config.d/memory.xml`: limites reduzidos para o contrato da e2-micro
  (1 GB + swap) — `max_server_memory_usage` 512 MiB, `background_pool_size` 4,
  `background_schedule_pool_size` 4, logs de sistema desabilitados.
- `clickhouse/users.d`: usuário `default` com access management SQL-driven
  (`CLICKHOUSE_DEFAULT_ACCESS_MANAGEMENT=1`).
- `otel-collector/gateway.yaml`: receivers otlp, processors memory_limiter
  (409 MiB) + resourcedetection + batch, exporter clickhouse.

## 2. Problemas encontrados e correções (em ordem)

### 2.1 Entrypoint não conseguia criar `default-user.xml` (loop de restart)

- Sintoma: `/entrypoint.sh: line 130: ... users.d/default-user.xml: Read-only file system` repetido; container em `Restarting (1)`.
- Causa: montagem `./clickhouse/users.d:...:ro` impedia o entrypoint de gravar o
  arquivo do usuário quando o acesso SQL-driven está ativo.
- Fix: remover `:ro` da montagem do `users.d` (o `config.d` pode continuar `:ro`).
- Extra: adicionar ao `.gitignore` o arquivo gerado (`clickhouse/users.d/*-user.xml`).

### 2.2 Sanity check do MergeTree — `number_of_free_entries_in_pool_to_execute_mutation`

- Sintoma: `Code: 36 BAD_ARGUMENTS` — default 20 > `background_pool_size` ×
  `background_merges_mutations_concurrency_ratio` (4 × 2 = 8).
- Causa: ao reduzir o pool para economizar RAM, o sanity check exige que os
  settings `number_of_free_entries_in_pool_to_execute_*` fiquem ≤ 8.
- Fix: dentro de `<merge_tree>` (NÃO na raiz do `<clickhouse>`), definir o setting
  com valor 8.

### 2.3 Armadilha: `..._execute_other` não existe

- Tentativa de "adivinhar" um setting gêmeo → `Code: 115 UNKNOWN_SETTING`.
- Lição: não inventar settings; deixar o sanity check revelar qual é o próximo
  válido (o `.err.log` sempre aponta o nome exato).

### 2.4 Sanity check — `number_of_free_entries_in_pool_to_execute_optimize_entire_partition`

- Após 2.2 resolvido, surgiu o segundo (default 25 > 8). Fix: mesmo tratamento,
  valor 8 dentro de `<merge_tree>`.

### 2.5 ClickHouse escutando só em loopback → `connection refused` no collector

- Sintoma: collector em loop `dial tcp 172.18.0.2:9000: connection refused`;
  ClickHouse `healthy` (healthcheck via localhost passa dentro do container).
- Causa: `config.xml` default com `<listen_host>::1</listen_host>` e
  `<listen_host>127.0.0.1</listen_host>` — nada na interface da rede do compose.
- Fix: criar `clickhouse/config.d/listen.xml` com `<listen_host>0.0.0.0</listen_host>`
  (o `config.d` é mesclado depois do `config.xml`).
- Diagnóstico que confirmou:
  - `clickhouse-client --host 172.18.0.2 --query 'SELECT 1'` → Connection refused;
  - `grep listen_host /etc/clickhouse-server/` dentro do container.

### 2.6 Volume poluído por execuções quebradas

- Após vários ciclos de correção, o volume `clickhouse-data` guardava estado
  inconsistente. Fix: `docker compose down -v` (lab sem dados reais). Não afeta
  o repositório nem a VM.

### 2.7 loadgen — WSL sem `/bin/bash` e imagem sem `openssl`

- Sintoma: `bash loadgen/generate.sh` → `execvpe(/bin/bash) failed` no relay WSL;
  e `bash:latest` não tem `openssl rand`.
- Fix: gerar a mesma carga via PowerShell (`Invoke-RestMethod` em `/v1/logs` e
  `/v1/traces`), postando 1 log ERROR + 1 trace com status de erro.
- Lição: não depender do bash do WSL; para rodar o script original num container,
  usar uma imagem com openssl ou injetar os IDs via env.

## 3. Checklist para subir a stack do zero

1. `docker compose down -v` — reset limpo
2. `docker compose up -d`
3. `docker compose ps` — clickhouse `healthy`; collector e grafana `up`
   (nunca `Restarting`)
4. `curl.exe -s localhost:13133` → `{"status":"Server available",...}`
5. Postar carga OTLP HTTP em `/v1/logs` e `/v1/traces`
6. `docker compose exec clickhouse clickhouse-client -q "SHOW TABLES FROM otel"`
   → `otel_logs`, `otel_traces`, `otel_metrics_*`
7. `SELECT count()` nas tabelas → > 0
8. Grafana em `http://localhost:3000` (datasource ClickHouse)

## 4. Troubleshooting que funcionou

- **Erro real do servidor**: o entrypoint não imprime a exceção no stdout; o
  servidor escreve em `/var/log/clickhouse-server/clickhouse-server.err.log`
  dentro do container. Capturar fora do loop de restart:
  `docker run --rm --user clickhouse -v .../config.d:... -v .../users.d:... imagem bash -c "clickhouse-server --config-file=/etc/clickhouse-server/config.xml & sleep 8; cat .../clickhouse-server.err.log"`
- **Rede**: `docker network inspect otel-clickhouse-lab_default --format "{{range .Containers}}{{.Name}} -> {{.IPv4Address}}{{end}}"`
- **Distinguir listener vs DNS**: testar `clickhouse-client --host <IP-da-rede>`
  (não localhost).

## 5. Observações e próximos passos

- Os mesmos arquivos corrigidos (users.d rw, memory.xml, listen.xml) são
  consumidos pela VM e2-micro via cloud-init. Sem eles, o ClickHouse sobe
  `healthy` na VM mas recusa conexão do collector — o mesmo sintoma da seção 2.5.
- Contrato do lab: e2-micro (1 GB + swap), região `southamerica-east1`,
  provisionamento Terraform a partir do GitHub.
- Pipeline validado localmente: OTLP HTTP 4318 → Collector → ClickHouse
  (log + trace com erro confirmados via `SELECT count()`).
- Pendências opcionais no lab local: ingestão de métricas (`/v1/metrics`) e
  teste de gRPC 4317 (telemetrygen).
- Próximo passo: `terraform plan`/apply do lab GCP free tier, revisitando os
  mesmos pontos (rede, listener, healthchecks) já de olho nos erros desta lista.
