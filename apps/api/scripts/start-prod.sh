#!/bin/sh
set -eu

RUN_MIGRATIONS="${RUN_MIGRATIONS:-true}"
MIGRATION_MAX_RETRIES="${MIGRATION_MAX_RETRIES:-10}"
MIGRATION_RETRY_DELAY_SECONDS="${MIGRATION_RETRY_DELAY_SECONDS:-5}"
MIGRATION_STRICT="${MIGRATION_STRICT:-true}"
FAILED_MIGRATION_NAME="${FAILED_MIGRATION_NAME:-20260502043000_add_status_history_user_name_and_created_at}"

run_prisma_migrate_deploy() {
  log_file="${TMPDIR:-/tmp}/prisma-migrate-deploy.$$.$1.log"

  if npx prisma migrate deploy >"$log_file" 2>&1; then
    cat "$log_file"
    rm -f "$log_file"
    return 0
  fi

  status=$?
  cat "$log_file"

  if grep -q "P3009" "$log_file" && grep -q "$FAILED_MIGRATION_NAME" "$log_file"; then
    echo "[startup] detected P3009 for migration ${FAILED_MIGRATION_NAME}"
    echo "[startup] invoking safe resolver"

    if node scripts/resolve-failed-migration.cjs "$FAILED_MIGRATION_NAME" --deploy-after-resolve; then
      echo "[startup] safe resolver completed for migration ${FAILED_MIGRATION_NAME}"
      rm -f "$log_file"
      return 0
    fi

    resolver_status=$?
    echo "[startup] safe resolver failed for migration ${FAILED_MIGRATION_NAME}"
    rm -f "$log_file"
    return "$resolver_status"
  fi

  rm -f "$log_file"
  return "$status"
}

if [ "$RUN_MIGRATIONS" = "true" ] || [ "$RUN_MIGRATIONS" = "1" ]; then
  echo "[startup] prisma migrate deploy (retries: ${MIGRATION_MAX_RETRIES})"
  attempt=1
  while [ "$attempt" -le "$MIGRATION_MAX_RETRIES" ]; do
    if run_prisma_migrate_deploy "$attempt"; then
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
