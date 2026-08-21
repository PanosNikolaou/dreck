#!/usr/bin/env bash
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SDK_ROOT="$HOME/.Garmin/ConnectIQ/Sdks"
SDK_DIR="$(ls -d "$SDK_ROOT"/connectiq-sdk-lin-* 2>/dev/null | sort | tail -n 1)"

if [[ -z "$SDK_DIR" ]]; then
  echo "Error: no Garmin Connect IQ SDK found under $SDK_ROOT"
  exit 1
fi

MONKEYC="$SDK_DIR/bin/monkeyc"
MONKEYDO="$SDK_DIR/bin/monkeydo"
SIMULATOR="$SDK_DIR/bin/simulator"
DEV_KEY="$APP_DIR/developer_key"
OUTPUT_PRG="/tmp/gsensros_test.prg"
DEVICE_ID="instinct2x"

usage() {
  echo "Usage: $0 [--build-only] [--run-only] [--device DEVICE_ID]"
  echo ""
  echo "Examples:"
  echo "  $0"
  echo "  $0 --build-only"
  echo "  $0 --run-only"
  echo "  $0 --device instinct2x"
}

build_app() {
  echo "[1/3] Checking toolchain..."
  echo "Using SDK: $SDK_DIR"
  if [[ ! -x "$MONKEYC" ]]; then
    echo "Error: monkeyc not found at $MONKEYC"
    exit 1
  fi

  if [[ ! -f "$DEV_KEY" ]]; then
    echo "Error: developer key not found at $DEV_KEY"
    exit 1
  fi

  echo "[2/3] Building app..."
  cd "$APP_DIR"
  "$MONKEYC" \
    -y "$DEV_KEY" \
    -o "$OUTPUT_PRG" \
    -d "$DEVICE_ID" \
    -f monkey.jungle

  echo "[3/3] Build complete: $OUTPUT_PRG"
  ls -l "$OUTPUT_PRG"
}

start_simulator() {
  echo "Starting Garmin simulator..."

  if [[ -n "${DISPLAY:-}" ]]; then
    "$SIMULATOR" >/tmp/ciq_sim.log 2>&1 &
  elif command -v xvfb-run >/dev/null 2>&1; then
    xvfb-run -a "$SIMULATOR" >/tmp/ciq_sim.log 2>&1 &
  else
    echo "Error: no display available and xvfb-run is not installed."
    echo "Run this on a desktop/GUI machine or install xvfb."
    exit 1
  fi

  echo "Simulator started in background. Log: /tmp/ciq_sim.log"
}

run_app() {
  if [[ ! -f "$OUTPUT_PRG" ]]; then
    echo "Build artifact not found at $OUTPUT_PRG. Building first..."
    build_app
  fi

  echo "Launching app on simulator..."
  "$MONKEYDO" "$OUTPUT_PRG" "$DEVICE_ID"
}

ACTION="all"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --build-only)
      ACTION="build"
      ;;
    --run-only)
      ACTION="run"
      ;;
    --device)
      shift
      DEVICE_ID="${1:-instinct2x}"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1"
      usage
      exit 1
      ;;
  esac
  shift
done

case "$ACTION" in
  build)
    build_app
    ;;
  run)
    start_simulator
    run_app
    ;;
  all)
    build_app
    start_simulator
    run_app
    ;;
  *)
    echo "Unsupported action: $ACTION"
    exit 1
    ;;
 esac
