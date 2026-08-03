#!/usr/bin/env bash
# Deploy this China-team Capka fork to a remote Docker host (build-from-source).
#
# Usage:
#   ./scripts/deploy-remote.sh ubuntu@111.231.24.43 /Users/hanxin/Downloads/mac.pem
#
# Optional env:
#   PUBLIC_URL=http://111.231.24.43:3000
#   REMOTE_DIR=/home/ubuntu/capka
#   PLATFORM_PORT=3000
#   SANDBOX_ALLOW_NETWORK=true
#
# Requires: ssh, rsync, remote docker + docker compose.
set -euo pipefail

HOST="${1:?usage: $0 user@host /path/to/key.pem}"
KEY="${2:?usage: $0 user@host /path/to/key.pem}"
REMOTE_DIR="${REMOTE_DIR:-/home/ubuntu/capka}"
PUBLIC_URL="${PUBLIC_URL:-http://111.231.24.43:3000}"
PLATFORM_PORT="${PLATFORM_PORT:-3000}"
SANDBOX_ALLOW_NETWORK="${SANDBOX_ALLOW_NETWORK:-true}"

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SSH=(ssh -i "$KEY" -o StrictHostKeyChecking=accept-new -o ServerAliveInterval=30)
RSYNC=(rsync -az --delete
  --exclude node_modules
  --exclude .next
  --exclude .git
  --exclude data
  --exclude '*.pem'
  --exclude .env
  --exclude .env.local
  -e "ssh -i $KEY -o StrictHostKeyChecking=accept-new"
)

echo "==> Probe SSH $HOST"
"${SSH[@]}" "$HOST" 'echo SSH_OK; uname -a; docker --version; docker compose version'

echo "==> Ensure remote dir $REMOTE_DIR"
"${SSH[@]}" "$HOST" "mkdir -p '$REMOTE_DIR'"

echo "==> Sync source (China fork, build locally on server)"
"${RSYNC[@]}" "$ROOT/" "$HOST:$REMOTE_DIR/"

echo "==> Write / merge remote .env"
"${SSH[@]}" "$HOST" "bash -s" <<EOF
set -euo pipefail
cd '$REMOTE_DIR'
touch .env
chmod 600 .env
ensure() {
  k="\$1"; v="\$2"
  if ! grep -q "^\$k=" .env 2>/dev/null; then
    printf '%s=%s\n' "\$k" "\$v" >> .env
    echo "  set \$k"
  fi
}
gen() {
  if command -v openssl >/dev/null; then openssl rand -hex 32
  else head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \\n'
  fi
}
ensure POSTGRES_PASSWORD "\$(gen)"
ensure CONTROLLER_SECRET "\$(gen)"
ensure CAPKA_MASTER_KEY "\$(gen)"
ensure PUBLIC_URL '$PUBLIC_URL'
ensure PLATFORM_PORT '$PLATFORM_PORT'
ensure SANDBOX_ALLOW_NETWORK '$SANDBOX_ALLOW_NETWORK'
ensure SANDBOX_RUNTIME runc
ensure SANDBOX_ENTRYPOINT_HOST "$REMOTE_DIR/sandbox-entrypoint.sh"
ensure NEXT_PUBLIC_PRODUCT_NAME 'BOSS & YOUNG'
ensure NEXT_PUBLIC_PRODUCT_TAGLINE 'Shanghai Boss \& Young Attorneys-at-Law'
# China-reachable web search defaults in the agent sandbox prompt
ensure CAPKA_REGION cn
# Preload Tavily under MCP defer (explicit; code also defaults when CAPKA_REGION=cn)
ensure MCP_ALWAYS_LOAD tavily
# Build-from-source (fork), not pull GHCR upstream images
ensure CAPKA_BUILD 1
chmod +x sandbox-entrypoint.sh
EOF

echo "==> Build & start from source (never pull GHCR — fork images stay local)"
"${SSH[@]}" "$HOST" "bash -s" <<EOF
set -euo pipefail
cd '$REMOTE_DIR'
chmod +x sandbox-entrypoint.sh
export CAPKA_BUILD=1
# Prefer up.sh when available; it layers build overlay when CAPKA_BUILD=1.
# Explicit --pull never: do NOT docker compose pull (would overwrite the China
# fork platform image with upstream ghcr.io/lyosu/capka-*).
if [ -x scripts/up.sh ]; then
  PUBLIC_URL='$PUBLIC_URL' PLATFORM_PORT='$PLATFORM_PORT' CAPKA_BUILD=1 ./scripts/up.sh
else
  docker compose -f docker-compose.yml -f docker-compose.build.yml \
    up -d --build --pull never --remove-orphans
fi
docker compose ps
EOF

echo
echo "Done. Open: $PUBLIC_URL/setup"
echo "If login fails with INVALID_ORIGIN, set PUBLIC_URL in $REMOTE_DIR/.env to the exact browser origin and re-run."
