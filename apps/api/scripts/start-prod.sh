#!/bin/sh
set -eu

echo "[startup] prisma migrate deploy"
npx prisma migrate deploy

if [ "${RUN_SEED:-}" = "true" ] || [ "${RUN_SEED:-}" = "1" ]; then
  echo "[startup] RUN_SEED enabled -> prisma db seed"
  npx prisma db seed
else
  echo "[startup] RUN_SEED not enabled -> skipping seed"
fi

echo "[startup] starting api"
node dist/main.js
