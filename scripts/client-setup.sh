#!/usr/bin/env bash
# Configures sbx on this machine to use your registry for kits: allows the registry as a
# kit source and stores the registry pull credential.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

resolve_registry
sources="[\"$KIT_NS/\"]"

require_env REGISTRY_USERNAME REGISTRY_PASSWORD
require_tool sbx "Install Docker Sandboxes (sbx 0.45 or later)."

# The value replaces the whole allowlist, so docker.io/ is no longer an allowed kit source.
sbx settings set kit.allowedSources "$sources"
printf '%s' "$REGISTRY_PASSWORD" | sbx secret set --registry "$REGISTRY" --username "$REGISTRY_USERNAME" --password-stdin
echo "sbx is configured to use $KIT_NS/"
