#!/usr/bin/env bash
# Builds the tools kit and the combined Claude kit set from the templates in kits/,
# and pushes both to your registry. Every image the build touches resolves from
# that registry, so run scripts/import.sh first.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_env REGISTRY_USERNAME REGISTRY_PASSWORD
render_kits
require_tool docker "Install Docker with buildx."

BUILDER="${SBX_KIT_BUILDER:-sbx-kit-builder}"

printf '%s' "$REGISTRY_PASSWORD" | docker login "$REGISTRY" -u "$REGISTRY_USERNAME" --password-stdin

# The builder is a container with its own trust store, so a private CA has to be
# handed to it explicitly. To change the CA later, run: docker buildx rm "$BUILDER"
if ! docker buildx inspect "$BUILDER" >/dev/null 2>&1; then
  create_args=(--name "$BUILDER" --driver docker-container --bootstrap)
  if [[ -n "${REGISTRY_CA_FILE:-}" ]]; then
    [[ -f "$REGISTRY_CA_FILE" ]] || die "REGISTRY_CA_FILE does not exist: $REGISTRY_CA_FILE"
    mkdir -p "$BUILD"
    ca="$(cd "$(dirname "$REGISTRY_CA_FILE")" && pwd)/$(basename "$REGISTRY_CA_FILE")"
    printf '[registry."%s"]\n  ca = ["%s"]\n' "$REGISTRY" "$ca" > "$BUILD/buildkitd.toml"
    create_args+=(--config "$BUILD/buildkitd.toml")
  fi
  docker buildx create "${create_args[@]}"
fi

build() {
  local name="$1" version="$2"
  docker buildx build --builder "$BUILDER" \
    -f "$BUILD/kits/$name/$name.yaml" \
    --platform linux/amd64,linux/arm64 --provenance=mode=min \
    --build-arg "KIT_REGISTRY=$KIT_NS" \
    -t "$KIT_NS/sbx-kit-$name:$version" --push \
    "$BUILD/kits/$name"
  echo "pushed $KIT_NS/sbx-kit-$name:$version"
}

build k8s-tools "$K8S_TOOLS_KIT_VERSION"
build claude-k8s "$CLAUDE_K8S_KIT_VERSION"

echo
echo "Run it with:"
echo "  sbx run --name demo $KIT_NS/sbx-kit-claude-k8s:$CLAUDE_K8S_KIT_VERSION ."
