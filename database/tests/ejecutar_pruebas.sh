#!/usr/bin/env bash
# Crea una base PostgreSQL 16 local, simula Supabase, aplica todas las migraciones
# en orden y corre las pruebas. Uso: bash database/tests/ejecutar_pruebas.sh
set -euo pipefail
cd "$(dirname "$0")/.."

PGBIN=${PGBIN:-/usr/lib/postgresql/16/bin}
DATA=/tmp/elius-pg
PORT=5433
PSQL="$PGBIN/psql -h /tmp -p $PORT -U postgres -v ON_ERROR_STOP=1 -q"
COMO="runuser -u postgres --"

if ! $COMO $PGBIN/pg_ctl -D $DATA status >/dev/null 2>&1; then
  rm -rf $DATA && mkdir -p $DATA && chown postgres:postgres $DATA
  $COMO $PGBIN/initdb -D $DATA -U postgres --auth=trust >/dev/null
  $COMO $PGBIN/pg_ctl -D $DATA -o "-p $PORT -k /tmp" -l $DATA/log start >/dev/null
  sleep 2
fi

$PSQL -d postgres -c "drop database if exists elius" -c "create database elius"
$PSQL -d elius -f tests/00_supabase_simulado.sql
for f in supabase/migrations/*.sql; do
  echo "→ $(basename "$f")"
  $PSQL -d elius -f "$f"
done
for f in tests/[1-9]*.sql; do
  [ -e "$f" ] || continue
  echo "== $(basename "$f")"
  $PSQL -d elius -f "$f"
done
echo "TODO OK"
