#!/usr/bin/env bash
# Teste manual do OTLP HTTP (4318): 1 log + 1 trace com erro.
# Uso: ./loadgen/generate.sh [host]   (padrão: localhost)
set -euo pipefail
HOST="${1:-localhost}"
URL="http://${HOST}:4318"
NOW=$(date +%s)000000000
TRACE=$(openssl rand -hex 16)
SPAN=$(openssl rand -hex 8)

curl -sS -o /dev/null -w "logs   -> HTTP %{http_code}\n" -X POST "$URL/v1/logs" \
  -H 'Content-Type: application/json' -d "{
  \"resourceLogs\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"manual-test\"}}]},
  \"scopeLogs\":[{\"logRecords\":[{\"timeUnixNano\":\"$NOW\",\"severityText\":\"ERROR\",\"body\":{\"stringValue\":\"log de teste manual\"}}]}]}]}"

curl -sS -o /dev/null -w "traces -> HTTP %{http_code}\n" -X POST "$URL/v1/traces" \
  -H 'Content-Type: application/json' -d "{
  \"resourceSpans\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"manual-test\"}}]},
  \"scopeSpans\":[{\"spans\":[{\"traceId\":\"$TRACE\",\"spanId\":\"$SPAN\",\"name\":\"teste\",\"kind\":1,
  \"startTimeUnixNano\":\"$NOW\",\"endTimeUnixNano\":\"$NOW\",\"status\":{\"code\":2}}]}]}]}"
