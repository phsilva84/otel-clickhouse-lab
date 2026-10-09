#!/usr/bin/env bash
# Cria (ou atualiza a senha de) o usuario somente leitura "hyperdx" no ClickHouse da VM.
# Rodar NA VM:  sudo ./clickhouse/create-hyperdx-user.sh
# A senha e pedida sem eco e vai por stdin (nao aparece em argumentos nem no historico).
# Os usuarios ficam no volume do ClickHouse: apos 'docker compose down -v' rode de novo.
set -euo pipefail
CH="${CH:-otel-lab-clickhouse-1}"
D="docker"; [ "$(id -u)" -ne 0 ] && D="sudo docker"

read -r -s -p "Senha do usuario hyperdx (minimo 16 caracteres, sem aspas simples nem barra invertida): " PW; echo
[ "${#PW}" -ge 16 ] || { echo "senha curta demais" >&2; exit 1; }
case "$PW" in
  *"'"*|*'\'*) echo "a senha nao pode conter ' nem \\" >&2; exit 1 ;;
esac

$D exec -i "$CH" clickhouse-client --multiquery <<SQL
CREATE USER IF NOT EXISTS hyperdx IDENTIFIED WITH sha256_password BY '${PW}';
ALTER USER hyperdx IDENTIFIED WITH sha256_password BY '${PW}';
GRANT SELECT ON otel.* TO hyperdx;
CREATE SETTINGS PROFILE IF NOT EXISTS hyperdx_profile SETTINGS max_memory_usage = 268435456, max_execution_time = 30, max_threads = 2 TO hyperdx;
SQL

echo "--- grants de hyperdx:"
$D exec "$CH" clickhouse-client -q "SHOW GRANTS FOR hyperdx"
echo "--- perfil de limites:"
$D exec "$CH" clickhouse-client -q "SHOW CREATE SETTINGS PROFILE hyperdx_profile"
