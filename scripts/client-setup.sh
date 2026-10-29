#!/usr/bin/env bash
# Configures sbx on a developer machine to use your registry for kits.
#
#   scripts/client-setup.sh                 run the sbx commands on this machine
#   scripts/client-setup.sh --payload DIR   write settings.json into DIR instead, for
#                                           distribution with MDM; nothing is changed here
#
# The registry pull credential is a per-user secret and is only stored by the first mode.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

resolve_registry
sources="[\"$KIT_NS/\"]"

if [[ "${1:-}" == "--payload" ]]; then
  [[ -n "${2:-}" ]] || die "usage: client-setup.sh --payload DIR"
  mkdir -p "$2"
  printf '{\n  "kit.allowedSources": %s\n}\n' "$sources" > "$2/settings.json"
  echo "wrote $2/settings.json"
  exit 0
fi

require_env REGISTRY_USERNAME REGISTRY_PASSWORD
require_tool sbx "Install Docker Sandboxes (sbx 0.45 or later)."

# The value replaces the whole allowlist, so docker.io/ is no longer an allowed kit source.
sbx settings set kit.allowedSources "$sources"
printf '%s' "$REGISTRY_PASSWORD" | sbx secret set --registry "$REGISTRY" --username "$REGISTRY_USERNAME" --password-stdin
echo "sbx is configured to use $KIT_NS/"
