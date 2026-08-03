#!/usr/bin/env bash
# Export locally-built linux/amd64 Capka images to a gzip tarball for scp.
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT="${1:-$ROOT/.deploy-artifacts/capka-amd64-images.tar.gz}"
mkdir -p "$(dirname "$OUT")"

IMAGES=(
  ghcr.io/lyosu/capka-sandbox:latest
  ghcr.io/lyosu/capka-controller:latest
  ghcr.io/lyosu/capka-platform:latest
)

echo "==> Checking images are linux/amd64"
for img in "${IMAGES[@]}"; do
  arch="$(docker image inspect "$img" --format '{{.Architecture}}')"
  os="$(docker image inspect "$img" --format '{{.Os}}')"
  echo "  $img → $os/$arch"
  if [ "$arch" != "amd64" ] || [ "$os" != "linux" ]; then
    echo "ERROR: $img is $os/$arch (need linux/amd64)" >&2
    exit 1
  fi
done

echo "==> Saving to $OUT"
docker save "${IMAGES[@]}" | gzip -1 >"$OUT"
ls -lh "$OUT"
echo "Done."
