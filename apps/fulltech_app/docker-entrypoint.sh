#!/bin/sh
set -eu

WEB_ROOT="/usr/share/nginx/html"
ENV_FILE="$WEB_ROOT/assets/.env"
EXAMPLE_FILE="$WEB_ROOT/assets/.env.example"

# Ensure the env file exists (so flutter_dotenv can load it as an asset).
if [ ! -f "$ENV_FILE" ] && [ -f "$EXAMPLE_FILE" ]; then
  cp "$EXAMPLE_FILE" "$ENV_FILE"
fi

# If EasyPanel provides runtime env vars, write them into the asset env file.
# This avoids rebuilding the image just to change API endpoints.
if [ "${API_BASE_URL:-}" != "" ] || [ "${API_TIMEOUT_MS:-}" != "" ]; then
  {
    echo "# Generated at container start"
    if [ "${API_BASE_URL:-}" != "" ]; then
      echo "API_BASE_URL=${API_BASE_URL}"
    fi
    if [ "${API_TIMEOUT_MS:-}" != "" ]; then
      echo "API_TIMEOUT_MS=${API_TIMEOUT_MS}"
    fi
  } > "$ENV_FILE"
fi

exec nginx -g "daemon off;"
