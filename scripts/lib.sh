#!/usr/bin/env bash
# Shared helpers, sourced by the other scripts. Not meant to be run directly.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/.build"

# Reads .env without executing it. A variable already set in the environment is
# left alone, so exported values win over the file.
load_env() {
  local file="$ROOT/.env" line key value
  [[ -f "$file" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*# || -z "${line//[[:space:]]/}" ]] && continue
    [[ "$line" == *=* ]] || continue
    key="${line%%=*}"
    key="${key//[[:space:]]/}"
    value="${line#*=}"
    value="${value%\"}"
    value="${value#\"}"
    if [[ -z "${!key+x}" ]]; then
      export "$key=$value"
    fi
  done < "$file"
}

load_env

: "${CLAUDE_KIT_VERSION:=2.1.267}"
: "${KUBECTL_VERSION:=1.32.0}"
: "${HELM_VERSION:=3.17.0}"
: "${K8S_TOOLS_KIT_VERSION:=1.0.0}"
: "${CLAUDE_K8S_KIT_VERSION:=1.0.0}"

die() {
  echo "error: $*" >&2
  exit 1
}

require_env() {
  local missing=() name
  for name in "$@"; do
    [[ -n "${!name:-}" ]] || missing+=("$name")
  done
  if ((${#missing[@]})); then
    die "missing ${missing[*]}. Set them in .env or the environment (see .env.example)."
  fi
}

require_tool() {
  command -v "$1" >/dev/null 2>&1 || die "$1 not found. $2"
}

# Validates the registry settings and derives KIT_NS, the repository prefix every
# kit reference is built from.
resolve_registry() {
  require_env REGISTRY REGISTRY_NAMESPACE
  [[ "$REGISTRY" != *"://"* && "$REGISTRY" != */* ]] \
    || die "REGISTRY must be a bare host (and optional port), without a scheme or path."
  [[ "$REGISTRY_NAMESPACE" != /* && "$REGISTRY_NAMESPACE" != */ ]] \
    || die "REGISTRY_NAMESPACE must not start or end with a slash."
  KIT_NS="$REGISTRY/$REGISTRY_NAMESPACE"
  [[ "$KIT_NS" =~ ^[a-z0-9][a-z0-9._:/-]*$ ]] \
    || die "REGISTRY and REGISTRY_NAMESPACE must be lowercase letters, digits and . _ : / -"
}

# Fills the @PLACEHOLDER@ markers in every kits/**/*.tmpl into .build/kits.
# BuildKit reads the "# syntax=" line literally, so the registry cannot be an
# environment variable inside the descriptors themselves.
render_kits() {
  resolve_registry
  rm -rf "$BUILD/kits"
  local src rel dst
  while IFS= read -r src; do
    rel="${src#"$ROOT/kits/"}"
    dst="$BUILD/kits/${rel%.tmpl}"
    mkdir -p "$(dirname "$dst")"
    sed \
      -e "s|@KIT_NS@|$KIT_NS|g" \
      -e "s|@KUBECTL_VERSION@|$KUBECTL_VERSION|g" \
      -e "s|@HELM_VERSION@|$HELM_VERSION|g" \
      -e "s|@CLAUDE_KIT_VERSION@|$CLAUDE_KIT_VERSION|g" \
      -e "s|@K8S_TOOLS_KIT_VERSION@|$K8S_TOOLS_KIT_VERSION|g" \
      -e "s|@CLAUDE_K8S_KIT_VERSION@|$CLAUDE_K8S_KIT_VERSION|g" \
      "$src" > "$dst"
    if grep -q -E '@[A-Z0-9_]+@' "$dst"; then
      die "unfilled placeholder in $dst"
    fi
  done < <(find "$ROOT/kits" -name '*.tmpl' | sort)
}
