#!/usr/bin/env bash
# Monitor na VM durante o teste de carga.
# Uso: ./loadgen/vm-monitor.sh [intervalo_s]      (CH_COUNTS=0 desliga as contagens do ClickHouse)
set -u
INT="${1:-10}"
CH="otel-lab-clickhouse-1"; OC="otel-lab-otel-collector-1"; GF="otel-lab-grafana-1"
D="docker"; [ "$(id -u)" -ne 0 ] && D="sudo docker"

while true; do
  echo "=== $(date -u +%FT%TZ) ==="
  echo "load: $(cut -d' ' -f1-3 /proc/loadavg) | $(free -m | awk '/Mem:/{printf "ram %s/%s MB", $3,$2} /Swap:/{printf " | swap %s MB", $3}')"
  vmstat 1 2 | tail -1 | awk '{printf "swap in/out: %s/%s | cpu us/sy/id/st: %s/%s/%s/%s\n",$7,$8,$13,$14,$15,$17}'
  $D stats --no-stream --format "  {{.Name}}  cpu={{.CPUPerc}}  mem={{.MemUsage}}" $CH $OC $GF
  $D inspect -f '  {{.Name}} restarts={{.RestartCount}} oom={{.State.OOMKilled}}' $CH $OC $GF
  echo "collector:"
  curl -s localhost:8888/metrics \
    | grep -E '^otelcol_(receiver_(accepted|refused)|exporter_(sent|send_failed|enqueue_failed))_(spans|log_records|metric_points)|^otelcol_exporter_queue_size' \
    | sed -E 's/\{[^}]*\}//' \
    | awk '{a[$1]+=$2} END{for(k in a) printf "  %-60s %.0f\n",k,a[k]}' | sort
  if [ "${CH_COUNTS:-1}" = "1" ]; then
    echo "clickhouse (linhas):"
    $D exec $CH clickhouse-client -q "SELECT 'traces', count() FROM otel.otel_traces UNION ALL SELECT 'logs', count() FROM otel.otel_logs UNION ALL SELECT 'metrics_gauge', count() FROM otel.otel_metrics_gauge" --format TSV 2>&1 | sed 's/^/  /'
  fi
  echo "disco: $(df -h / | awk 'NR==2{print $3"/"$2" ("$5")"}')"
  sleep "$INT"
done
