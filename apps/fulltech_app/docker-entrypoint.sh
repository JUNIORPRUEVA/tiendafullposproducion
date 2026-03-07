#!/bin/sh
set -eu

WEB_ROOT="/usr/share/nginx/html"
ENV_FILE="$WEB_ROOT/assets/.env"
EXAMPLE_FILE="$WEB_ROOT/assets/.env.example"

js_escape() {
  # Escape backslashes and double quotes for safe JS string literals.
  printf '%s' "$1" | sed 's/\\\\/\\\\\\\\/g; s/"/\\"/g'
}

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

# Generate runtime config for Flutter Web (NOT part of flutter_service_worker RESOURCES).
# This avoids stale config caused by PWA caching of assets.
API_BASE_URL_ESC="$(js_escape "${API_BASE_URL:-}")"
API_TIMEOUT_MS_ESC="$(js_escape "${API_TIMEOUT_MS:-}")"
cat > "$WEB_ROOT/env.js" <<EOF
// Generated at container start
window.__ENV = window.__ENV || {};
// Primary (string) values for current builds
window.API_BASE_URL = "${API_BASE_URL_ESC}";
window.API_TIMEOUT_MS = "${API_TIMEOUT_MS_ESC}";

// Backwards compatibility for older cached builds that expect functions:
//   __ENV.API_BASE_URL() / __ENV.API_TIMEOUT_MS()
// Also keep value mirrors for any code that reads __ENV.* as strings.
window.__ENV.API_BASE_URL_VALUE = window.API_BASE_URL;
window.__ENV.API_TIMEOUT_MS_VALUE = window.API_TIMEOUT_MS;
window.__ENV.API_BASE_URL = function () { return window.__ENV.API_BASE_URL_VALUE; };
window.__ENV.API_TIMEOUT_MS = function () { return window.__ENV.API_TIMEOUT_MS_VALUE; };

// Convenience aliases (string)
window.__ENV.API_BASE_URL_STR = window.API_BASE_URL;
window.__ENV.API_TIMEOUT_MS_STR = window.API_TIMEOUT_MS;
EOF

exec nginx -g "daemon off;"
