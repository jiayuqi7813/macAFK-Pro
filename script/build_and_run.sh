#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="MacAfk Pro"
BUNDLE_ID="com.snowywar.MacAfk"
SCHEME="MacAfk"
CONFIGURATION="Debug"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="$ROOT_DIR/Build/RunDerivedData"
APP_BUNDLE="$DERIVED_DATA/Build/Products/$CONFIGURATION/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

usage() {
  echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
}

stop_app() {
  osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  pkill -f "$APP_BINARY" >/dev/null 2>&1 || true
}

build_app() {
  xcodebuild \
    -project "$ROOT_DIR/MacAfk.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA" \
    -destination "platform=macOS" \
    build
}

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

verify_app() {
  sleep 2
  if pgrep -x "$APP_NAME" >/dev/null 2>&1 || pgrep -f "$APP_BINARY" >/dev/null 2>&1; then
    echo "$APP_NAME is running"
  else
    echo "$APP_NAME did not start" >&2
    exit 1
  fi
}

stop_app
build_app

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    verify_app
    ;;
  *)
    usage
    exit 2
    ;;
esac
