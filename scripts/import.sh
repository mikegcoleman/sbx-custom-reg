#!/usr/bin/env bash
# Copies the three Docker Hub artifacts the kit build needs into your registry:
#   - Docker's published Claude Code kit
#   - the kit build frontend named in each descriptor's "# syntax=" line
#   - the base image the tools kit builds from
#
# Run this once, from a machine that is allowed to reach Docker Hub. If your
# registry already proxies Docker Hub (for example an Artifactory remote repository),
# you can skip this script and make the same three images available at the same paths.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_env REGISTRY_USERNAME REGISTRY_PASSWORD
resolve_registry
require_tool regctl "Install it from https://github.com/regclient/regclient (macOS: brew install regclient)."

printf '%s' "$REGISTRY_PASSWORD" | regctl registry login "$REGISTRY" -u "$REGISTRY_USERNAME" --pass-stdin

copy() {
  echo "copy $1 -> $2"
  regctl image copy "$1" "$2"
}

copy "docker.io/docker/sbx-kit-claude:$CLAUDE_KIT_VERSION" "$KIT_NS/sbx-kit-claude:$CLAUDE_KIT_VERSION"
copy "docker.io/docker/sandbox-kit:3" "$KIT_NS/sandbox-kit:3"
copy "docker.io/library/debian:bookworm-slim" "$KIT_NS/debian:bookworm-slim"
