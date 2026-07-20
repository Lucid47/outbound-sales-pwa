#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONFIG_FILE="$ROOT_DIR/native/.google-drive-oauth.local"
PROJECT="$ROOT_DIR/native/OutboundSalesiOS/OutboundSalesiOS.xcodeproj"
SCHEME="OutboundSalesiOS"
DERIVED_DATA="$ROOT_DIR/native/DerivedData/OutboundSalesiOS"
CONFIGURATION="Debug"
DEVICE_ID=""
INSTALL_APP="false"
XCODE_DESTINATION="generic/platform=iOS"

usage() {
  cat <<'USAGE'
Usage:
  native/scripts/build-ios-with-google-drive.sh [--device-id DEVICE_ID] [--install] [--destination XCODE_DESTINATION]

Environment or native/.google-drive-oauth.local:
  GOOGLE_DRIVE_OAUTH_CLIENT_ID   Required for real Google Drive login
  GOOGLE_DRIVE_REDIRECT_SCHEME   Optional, default: com.lucid47.outboundsales
  DEVELOPER_DIR                  Optional, selected Xcode path

Examples:
  cp native/.google-drive-oauth.local.example native/.google-drive-oauth.local
  native/scripts/build-ios-with-google-drive.sh
  native/scripts/build-ios-with-google-drive.sh --device-id D3EECFBE-79C9-5DA3-A17F-1A7CF2AAE198 --install
  native/scripts/build-ios-with-google-drive.sh --destination 'id=00008150-000C4D5E36E2401C'
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --device-id)
      DEVICE_ID="${2:-}"
      shift 2
      ;;
    --install)
      INSTALL_APP="true"
      shift
      ;;
    --destination)
      XCODE_DESTINATION="${2:-}"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ -f "$CONFIG_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
  set +a
fi

GOOGLE_DRIVE_OAUTH_CLIENT_ID="${GOOGLE_DRIVE_OAUTH_CLIENT_ID:-}"
GOOGLE_DRIVE_REDIRECT_SCHEME="${GOOGLE_DRIVE_REDIRECT_SCHEME:-com.lucid47.outboundsales}"

if [[ -z "$GOOGLE_DRIVE_OAUTH_CLIENT_ID" || "$GOOGLE_DRIVE_OAUTH_CLIENT_ID" == YOUR_IOS_OAUTH_CLIENT_ID* ]]; then
  cat >&2 <<'WARNING'
Warning: GOOGLE_DRIVE_OAUTH_CLIENT_ID is not configured.
The app will build, but Google Drive login will stay disabled.
Create native/.google-drive-oauth.local from the example file to enable it.
WARNING
fi

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "$XCODE_DESTINATION" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA" \
  GOOGLE_DRIVE_OAUTH_CLIENT_ID="$GOOGLE_DRIVE_OAUTH_CLIENT_ID" \
  GOOGLE_DRIVE_REDIRECT_SCHEME="$GOOGLE_DRIVE_REDIRECT_SCHEME" \
  build

if [[ "$INSTALL_APP" == "true" ]]; then
  if [[ -z "$DEVICE_ID" ]]; then
    echo "--install requires --device-id" >&2
    exit 2
  fi
  APP_PATH="$DERIVED_DATA/Build/Products/${CONFIGURATION}-iphoneos/OutboundSalesiOS.app"
  xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH"
fi
