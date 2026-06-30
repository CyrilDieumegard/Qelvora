#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/Qelvora.xcodeproj"
SCHEME="Qelvora"
DERIVED_DATA="${SPARKLE_DERIVED_DATA:-/tmp/qelvora-sparkle-derived}"
ARCHIVES_DIR="${1:-$ROOT_DIR/dist}"
SPARKLE_ACCOUNT="${SPARKLE_ACCOUNT:-qelvora}"
DOWNLOAD_URL_PREFIX="${DOWNLOAD_URL_PREFIX:-https://github.com/CyrilDieumegard/Qelvora/releases/latest/download/}"
PRODUCT_LINK="${PRODUCT_LINK:-https://qelvora.app}"
MAXIMUM_VERSIONS="${MAXIMUM_VERSIONS:-1}"

find_sparkle_tool() {
  local tool_name="$1"
  local configured_var="SPARKLE_$(printf '%s' "$tool_name" | tr '[:lower:]' '[:upper:]')"
  local configured_path="${!configured_var:-}"

  if [[ -n "$configured_path" && -x "$configured_path" ]]; then
    printf '%s\n' "$configured_path"
    return 0
  fi

  local artifact_path="$DERIVED_DATA/SourcePackages/artifacts/sparkle/Sparkle/bin/$tool_name"
  if [[ -x "$artifact_path" ]]; then
    printf '%s\n' "$artifact_path"
    return 0
  fi

  return 1
}

if ! GENERATE_APPCAST="$(find_sparkle_tool generate_appcast)"; then
  xcodebuild \
    -resolvePackageDependencies \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -derivedDataPath "$DERIVED_DATA"

  GENERATE_APPCAST="$(find_sparkle_tool generate_appcast)"
fi

if [[ ! -d "$ARCHIVES_DIR" ]]; then
  echo "Archives directory not found: $ARCHIVES_DIR" >&2
  exit 1
fi

"$GENERATE_APPCAST" \
  --account "$SPARKLE_ACCOUNT" \
  --download-url-prefix "$DOWNLOAD_URL_PREFIX" \
  --link "$PRODUCT_LINK" \
  --maximum-versions "$MAXIMUM_VERSIONS" \
  "$ARCHIVES_DIR"

echo "Appcast ready: $ARCHIVES_DIR/appcast.xml"
