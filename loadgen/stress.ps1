<#
.SYNOPSIS
  Teste de carga em estagios contra o collector da VM (telemetrygen em Docker).
.DESCRIPTION
  Cada estagio sobe 4 geradores em paralelo: traces OK, traces com erro (~10% do rate),
  logs e metricas (~20% do rate). Entre estagios espera DrainSeconds para a fila esvaziar.
  Rate e por worker, aproximado. Confira se o gerador atingiu o alvo no resumo final.
.EXAMPLE
  .\loadgen\stress.ps1 -Target <VM_IP>
  .\loadgen\stress.ps1 -Target <VM_IP> -Rates 100 -StageSeconds 1800      # soak 30 min
  .\loadgen\stress.ps1 -Target <VM_IP> -Http                              # via OTLP HTTP 4318
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$Target,
  [int[]]$Rates = @(25, 100, 250, 500),
  [int]$StageSeconds = 120,
  [int]$DrainSeconds = 60,
  [int]$Workers = 1,
  [switch]$Http,
  [switch]$Force,
  [string]$Image = "ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:latest"
)

$ErrorActionPreference = "Stop"

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { throw "docker nao encontrado no PATH" }
if (($Rates | Where-Object { $_ -gt 500 }) -and -not $Force) {
  throw "Rate acima de 500/s numa e2-micro: use -Force se for intencional."
}

$port = if ($Http) { 4318 } else { 4317 }
$endpoint = "${Target}:${port}"

function Invoke-Stage([int]$Rate) {
  $errRate = [Math]::Max(1, [int]($Rate / 10))
  $metRate = [Math]::Max(1, [int]($Rate / 5))
  $defs = @(
    @{ Name = "sg-traces-ok-$Rate";  Cmd = @("traces",  "--rate=$Rate",    "--service=stress-ok") },
    @{ Name = "sg-traces-err-$Rate"; Cmd = @("traces",  "--rate=$errRate", "--service=stress-err", "--status-code=Error") },
    @{ Name = "sg-logs-$Rate";       Cmd = @("logs",    "--rate=$Rate",    "--service=stress-logs") },
    @{ Name = "sg-metrics-$Rate";    Cmd = @("metrics", "--rate=$metRate", "--service=stress-metrics") }
  )
  $common = @("--otlp-insecure", "--otlp-endpoint=$endpoint", "--duration=$($StageSeconds)s", "--workers=$Workers")
  if ($Http) { $common += "--otlp-http" }

  $t0 = (Get-Date).ToUniversalTime()
  Write-Host ""
  Write-Host "=== Estagio ${Rate}/s  inicio $($t0.ToString('o'))  duracao ${StageSeconds}s ===" -ForegroundColor Cyan
  Write-Host "    traces ok=$Rate  traces erro=$errRate  logs=$Rate  metricas=$metRate"

  $names = @()
  foreach ($d in $defs) {
    $runArgs = $d.Cmd + $common
    docker run -d --name $d.Name $Image @runArgs | Out-Null
    $names += $d.Name
  }

  docker wait @names | Out-Null
  $t1 = (Get-Date).ToUniversalTime()

  foreach ($n in $names) {
    $code = docker inspect -f "{{.State.ExitCode}}" $n
    Write-Host "--- $n (exit $code)"
    docker logs --tail 3 $n 2>&1 | ForEach-Object { Write-Host "    $_" }
  }
  Write-Host "Fim $($t1.ToString('o'))" -ForegroundColor Cyan
  return @{ Rate = $Rate; Start = $t0; End = $t1 }
}

$results = @()
try {
  Write-Host "Alvo: $endpoint  Imagem: $Image"
  docker pull $Image | Out-Null
  foreach ($r in $Rates) {
    $results += Invoke-Stage -Rate $r
    docker ps -aq --filter "name=sg-" | ForEach-Object { docker rm -f $_ | Out-Null }
    if ($r -ne $Rates[-1]) {
      Write-Host "Drenando fila por ${DrainSeconds}s..."
      Start-Sleep -Seconds $DrainSeconds
    }
  }
}
finally {
  docker ps -aq --filter "name=sg-" | ForEach-Object { docker rm -f $_ | Out-Null }
}

Write-Host ""
Write-Host "Resumo (UTC) - use estes horarios nas queries do ClickHouse:" -ForegroundColor Green
foreach ($x in $results) {
  Write-Host ("  {0,5}/s  {1}  ->  {2}" -f $x.Rate, $x.Start.ToString("HH:mm:ss"), $x.End.ToString("HH:mm:ss"))
}
