#!/usr/bin/env bash
# ios_release_and_run.sh
# Builds a release app via Xcode and installs it on a connected iOS device.
# Usage:  ./scripts/ios_release_and_run.sh [device-id]

set -euo pipefail

WORKSPACE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
XCWORKSPACE="$WORKSPACE_DIR/ios/Runner.xcworkspace"
SCHEME="Runner"
CONFIGURATION="Release"

list_devices() {
  flutter devices --machine 2>/dev/null | python3 -c \
"import sys,json
devs=json.load(sys.stdin)
for d in devs:
  if d.get('targetPlatform','').startswith('ios') and not d.get('emulator',True):
    print(d['id']+'\t'+d.get('name',d['id'])+' ('+d.get('sdk','')+')')" \
  2>/dev/null || true
}

if [[ $# -ge 1 ]]; then
  DEVICE_ID="$1"
  echo "Using device ID: $DEVICE_ID"
else
  echo "Scanning for connected iOS devices..."
  DEVICES_RAW=$(list_devices)

  if [[ -z "$DEVICES_RAW" ]]; then
    echo "ERROR: No connected iOS device found. Connect your device and trust this Mac."
    exit 1
  fi

  DEVICE_IDS=()
  DEVICE_NAMES=()
  while IFS=$'\t' read -r uid name; do
    DEVICE_IDS+=("$uid")
    DEVICE_NAMES+=("$name")
  done <<< "$DEVICES_RAW"

  if [[ ${#DEVICE_IDS[@]} -eq 1 ]]; then
    DEVICE_ID="${DEVICE_IDS[0]}"
    echo "Found 1 device: ${DEVICE_NAMES[0]}"
  else
    echo ""
    echo "Connected iOS devices:"
    for i in "${!DEVICE_IDS[@]}"; do
      printf "  [%d] %s\n      ID: %s\n" "$((i+1))" "${DEVICE_NAMES[$i]}" "${DEVICE_IDS[$i]}"
    done
    echo ""
    while true; do
      read -rp "Select device [1-${#DEVICE_IDS[@]}]: " CHOICE
      if [[ "$CHOICE" =~ ^[0-9]+$ ]] && (( CHOICE >= 1 && CHOICE <= ${#DEVICE_IDS[@]} )); then
        DEVICE_ID="${DEVICE_IDS[$((CHOICE-1))]}"
        echo "Selected: ${DEVICE_NAMES[$((CHOICE-1))]}"
        break
      else
        echo "Invalid choice, try again."
      fi
    done
  fi
fi

echo ""
echo "flutter build ios --release"
cd "$WORKSPACE_DIR"
DEFINES=()
if [[ -f "$WORKSPACE_DIR/env.json" ]]; then
  DEFINES+=(--dart-define-from-file=env.json)
  echo "Using build-time defines from env.json"
fi
flutter build ios --release "${DEFINES[@]+"${DEFINES[@]}"}"

echo ""
echo "xcodebuild: building Release app"
xcodebuild \
  -workspace "$XCWORKSPACE" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "generic/platform=iOS" \
  -allowProvisioningUpdates \
  build

APP_PATH="$WORKSPACE_DIR/build/ios/Release-iphoneos/Runner.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "ERROR: Built app not found at $APP_PATH"
  exit 1
fi

echo ""
echo "Installing and launching on $DEVICE_ID"
ios-deploy \
  --id "$DEVICE_ID" \
  --bundle "$APP_PATH" \
  --no-wifi

echo ""
echo "Done. App installed and launched on device."
