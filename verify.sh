#!/bin/sh
set -eu
# macOS /bin/sh is bash; pipefail keeps tee from hiding a failed swift build or test run.
set -o pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
SCRATCH="${CHET_SCRATCH:-${TMPDIR:-/tmp}/chet-verify}"
mkdir -p "$SCRATCH"

run_logged() {
  logfile="$1"
  shift
  set +e
  "$@" 2>&1 | tee "$logfile"
  status=$?
  set -e
  if [ "$status" -ne 0 ]; then
    echo "ERROR: command failed with status $status (log: $logfile)" >&2
    exit "$status"
  fi
}

echo "==> Building Chet"
run_logged "$SCRATCH/build.log" swift build

if grep -iE "warning:.*Sources/Chet" "$SCRATCH/build.log" | grep -v "ImplicitStrongCapture"; then
  echo "ERROR: unexpected source warnings in build log"
  exit 1
fi

echo "==> Running unit checks (CHET_UNIT_TESTS=1)"
run_logged "$SCRATCH/test.log" env CHET_UNIT_TESTS=1 swift run
grep -q "All unit checks passed" "$SCRATCH/test.log"
if grep -q "FAIL " "$SCRATCH/test.log"; then
  echo "ERROR: unit checks reported FAIL"
  exit 1
fi

echo "==> Checking Sources/Chet for @State (SwiftUIMacros unavailable under CommandLineTools)"
if grep -R "@State" Sources/Chet --include="*.swift"; then
  echo "ERROR: @State found in Sources/Chet"
  exit 1
fi

BINARY=""
for candidate in .build/debug/Chet .build/out/Products/Debug/Chet; do
  if [ -x "$candidate" ]; then
    BINARY="$candidate"
    break
  fi
done

if [ -z "$BINARY" ]; then
  echo "ERROR: Chet executable not found after build"
  exit 1
fi

launch_checked() {
  bin="$1"
  logfile="$2"
  label="$3"
  "$bin" >/dev/null 2>&1 &
  pid=$!
  sleep 1
  if kill -0 "$pid" 2>/dev/null; then
    echo "PASS: $label stayed alive for 1s (PID $pid)" | tee -a "$logfile"
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    return 0
  else
    echo "ERROR: $label exited before run loop started" | tee -a "$logfile"
    return 1
  fi
}

echo "==> Launching $BINARY (run 1)"
launch_checked "$BINARY" "$SCRATCH/launch-1.log" "Chet"

echo "==> Launching $BINARY (run 2)"
launch_checked "$BINARY" "$SCRATCH/launch-2.log" "Chet"

echo "==> Building installable app bundle"
run_logged "$SCRATCH/app-build.log" "$ROOT/scripts/build-app.sh" release

APP="$ROOT/dist/Chet.app"
APP_BINARY="$APP/Contents/MacOS/Chet"
test -d "$APP"
test -x "$APP_BINARY"
test -f "$APP/Contents/Resources/AppIcon.icns"
plutil -lint "$APP/Contents/Info.plist" | tee "$SCRATCH/plutil.log"

echo "==> Launching $APP (run 1)"
launch_checked "$APP_BINARY" "$SCRATCH/app-launch.log" "Chet.app"

echo "==> Launching $APP (run 2)"
launch_checked "$APP_BINARY" "$SCRATCH/app-launch.log" "Chet.app"

echo "All verify checks passed"
