# HyperDX no PC + ClickHouse na VM (via tunel SSH)

```
PC (Docker)                                        VM e2-micro (GCP)
 HyperDX :8080 + MongoDB                            ClickHouse :8123 (so em 127.0.0.1)
   └─ http://host.docker.internal:18123 ──tunel SSH──▶ localhost:8123
```

Por que tunel e nao abrir a 8123 no firewall: a conexao HTTP do ClickHouse nao tem TLS aqui (usuario e
senha iriam em texto puro pela internet) e o IPv4 residencial pode ser compartilhado (CGNAT). Pelo tunel
SSH tudo vai cifrado, a 8123 nao fica exposta e nao ha mudanca no firewall do Terraform.

## 1. Repo / VM: publicar a 8123 somente em loopback

No `docker-compose.yml` do repo, servico `clickhouse`, adicione (e remova o comentario "Sem 'ports'"):

```yaml
    ports:
      - "127.0.0.1:8123:8123"   # so acessivel pelo tunel SSH; NAO liberar no firewall do GCP
```

Commit/push no PC; na VM:

```bash
cd /opt/otel-lab && sudo git pull
sudo docker compose --env-file /etc/otel-lab.env up -d     # recria so o clickhouse (reinicia, pode levar 1-3 min)
sudo docker compose ps
```

O collector tem retry e fila em disco, entao o reinicio e tolerado. Evite fazer isso no meio de um teste de carga.

## 2. Terraform: segredo da senha (1 recurso)

Copie `terraform/hyperdx.tf` para `terraform/` e:

```powershell
cd terraform
terraform plan "-var-file=environments/lab/terraform.tfvars" -out=tfplan   # esperado: 1 to add
terraform apply tfplan
```

## 3. Gerar a senha e guardar no Secret Manager (PC, PowerShell)

Atencao: nao use `"senha" | gcloud ... --data-file=-` no PowerShell; ele acrescenta quebra de linha ao valor.

```powershell
$b = New-Object byte[] 24
[Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b)
$pw = ([Convert]::ToBase64String($b)) -replace '[^A-Za-z0-9]',''
$tmp = New-TemporaryFile
[IO.File]::WriteAllText($tmp.FullName, $pw)
gcloud secrets versions add otel-lab-hyperdx-password "--data-file=$($tmp.FullName)"
Remove-Item $tmp.FullName
Set-Clipboard $pw        # para colar no prompt da VM e no formulario do HyperDX
```

Para recuperar depois: `$pw = gcloud secrets versions access latest --secret=otel-lab-hyperdx-password`

## 4. VM: criar o usuario somente leitura

Copie `clickhouse/create-hyperdx-user.sh` para o repo (commit/push/pull na VM) e:

```bash
cd /opt/otel-lab && sudo chmod +x clickhouse/create-hyperdx-user.sh && sudo ./clickhouse/create-hyperdx-user.sh
```

Cola a senha no prompt. O usuario so tem `SELECT` em `otel.*` e um perfil que limita cada consulta a
256 MiB, 2 threads e 30 s (a UI nao deve derrubar a VM).

## 5. PC: tunel + teste

Terminal dedicado, deixe aberto (porta local 18123 para nao conflitar com um ClickHouse local):

```powershell
gcloud compute ssh otel-lab-vm --zone us-central1-a --project phlab-otel-lab-01 -- -N -L 18123:localhost:8123 -o ServerAliveInterval=30
```

Em outro terminal:

```powershell
curl.exe -s http://localhost:18123/ping                                                       # Ok.
curl.exe -s -u "hyperdx:$pw" --data-binary "SELECT count() FROM otel.otel_logs" http://localhost:18123/
curl.exe -s -u "hyperdx:$pw" --data-binary "CREATE TABLE otel.zz_teste (x UInt8) ENGINE = Memory" http://localhost:18123/   # deve dar ACCESS_DENIED
```

## 6. PC: subir o HyperDX

```powershell
cd hyperdx
Copy-Item .env.example .env        # edite os valores
docker compose up -d
```

Abra `http://localhost:8080`, crie o usuario local e, quando pedir a conexao ClickHouse:

- Host: `http://host.docker.internal:18123`
- Usuario: `hyperdx` / Senha: a do Secret Manager

A doc oficial diz que as consultas passam pelo servidor do HyperDX; se a conexao testar mas as buscas
falharem, me diga a mensagem.

## 7. Sources (Team Settings -> Sources)

Confira primeiro as colunas reais (o schema depende da versao do exporter contrib):

```bash
sudo docker exec otel-lab-clickhouse-1 clickhouse-client -q "DESCRIBE TABLE otel.otel_logs" --format TSV
sudo docker exec otel-lab-clickhouse-1 clickhouse-client -q "DESCRIBE TABLE otel.otel_traces" --format TSV
```

A doc diz que, ao informar a tabela, o restante e auto-detectado. Se algo vier vazio, estes sao os
valores esperados para o schema do exporter (ajuste ao `DESCRIBE`):

| Source | Campo | Valor |
|---|---|---|
| Logs (`otel_logs`) | Timestamp Column | `TimestampTime` se existir, senao `Timestamp` |
| | Default Select | `Timestamp, ServiceName, SeverityText, Body` |
| | Service Name / Log Level / Body | `ServiceName` / `SeverityText` / `Body` |
| | Log Attributes / Resource Attributes | `LogAttributes` / `ResourceAttributes` |
| | Trace Id / Span Id | `TraceId` / `SpanId` |
| Traces (`otel_traces`) | Timestamp Column | `Timestamp` |
| | Duration Expression / Precision | `Duration` / 9 (ns) |
| | Trace Id / Span Id / Parent Span Id | `TraceId` / `SpanId` / `ParentSpanId` |
| | Span Name / Span Kind | `SpanName` / `SpanKind` |
| | Status Code / Status Message | `StatusCode` / `StatusMessage` |
| | Service Name / Resource Attributes / Event Attributes | `ServiceName` / `ResourceAttributes` / `SpanAttributes` |
| | Span Events Expression | `Events` |
| Metrics | Database | `otel`; tabelas `otel_metrics_gauge`, `_sum`, `_histogram`, `_exponential_histogram` |

## 8. Validar

Gere carga (`stress.ps1` ou um estagio curto) e confira no HyperDX: logs por servico (`stress-logs`),
traces (`stress-err` sempre presentes; `stress-ok` ~10%), metricas e a navegacao trace <-> log.

## 9. Encerrar / reverter

```powershell
docker compose down            # no PC (-v apaga o MongoDB local)
```
Ctrl+C no terminal do tunel. Na VM: `clickhouse-client -q "DROP USER hyperdx"` e remover a linha `ports` do compose.

## Pendencias / riscos

- Tags de imagem sao placeholders (MongoDB e HyperDX). Fixe as que funcionarem.
- A doc nao documenta pre-provisionamento de conexao/sources por variavel de ambiente; a configuracao e manual na UI.
- O servico de padroes de log do HyperDX (`MINER_API_URL`) nao esta incluido; a feature de log patterns pode nao funcionar.
- O comparativo de custo de consulta por UI pede o `system.query_log` ligado (hoje removido no `memory.xml`) e usuarios
  separados por UI (HyperDX ja tem o seu; falta um usuario proprio para o Grafana).
