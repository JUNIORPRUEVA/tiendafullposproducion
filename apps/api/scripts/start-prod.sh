#!/bin/sh
set -eu

RUN_MIGRATIONS="${RUN_MIGRATIONS:-true}"
MIGRATION_MAX_RETRIES="${MIGRATION_MAX_RETRIES:-10}"
MIGRATION_RETRY_DELAY_SECONDS="${MIGRATION_RETRY_DELAY_SECONDS:-5}"
MIGRATION_STRICT="${MIGRATION_STRICT:-false}"

if [ "$RUN_MIGRATIONS" = "true" ] || [ "$RUN_MIGRATIONS" = "1" ]; then
  echo "[startup] prisma migrate deploy (retries: ${MIGRATION_MAX_RETRIES})"
  attempt=1
  while [ "$attempt" -le "$MIGRATION_MAX_RETRIES" ]; do
    if npx prisma migrate deploy; then
      echo "[startup] migrations applied"
      break
    fi

    if [ "$attempt" -eq "$MIGRATION_MAX_RETRIES" ]; then
      echo "[startup] migrations failed after ${MIGRATION_MAX_RETRIES} attempts"
      if [ "$MIGRATION_STRICT" = "true" ] || [ "$MIGRATION_STRICT" = "1" ]; then
        echo "[startup] MIGRATION_STRICT enabled -> exiting"
        exit 1
      fi
      echo "[startup] MIGRATION_STRICT disabled -> continuing startup without successful migrations"
      break
    fi

    echo "[startup] migrate failed (attempt ${attempt}/${MIGRATION_MAX_RETRIES}), retrying in ${MIGRATION_RETRY_DELAY_SECONDS}s..."
    attempt=$((attempt + 1))
    sleep "$MIGRATION_RETRY_DELAY_SECONDS"
  done
else
  echo "[startup] RUN_MIGRATIONS disabled -> skipping prisma migrate deploy"
fi

if [ "${RUN_SEED:-}" = "true" ] || [ "${RUN_SEED:-}" = "1" ]; then
  echo "[startup] RUN_SEED enabled -> prisma db seed"
  npx prisma db seed
else
  echo "[startup] RUN_SEED not enabled -> skipping seed"
fi

echo "[startup] starting api"
exec node dist/main.js
