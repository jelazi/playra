#!/usr/bin/env bash
# flutter-env.sh
# Runs a flutter command with the build-time defines from env.json, when that
# file exists. Without it the command runs unchanged and the app asks for the
# TMDB key in Settings instead.
#
# Usage:  ./scripts/flutter-env.sh run -d macos
#         ./scripts/flutter-env.sh build macos --release

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$PROJECT_DIR/env.json"

cd "$PROJECT_DIR"

DEFINES=()
if [[ -f "$ENV_FILE" ]]; then
  DEFINES+=(--dart-define-from-file=env.json)
  echo "Using build-time defines from env.json"
else
  echo "No env.json — the app will ask for the TMDB key in Settings"
fi

set -x
exec flutter "$@" "${DEFINES[@]+"${DEFINES[@]}"}"
