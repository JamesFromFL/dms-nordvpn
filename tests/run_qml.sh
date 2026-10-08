#!/usr/bin/env bash
set -euo pipefail
task_test_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
task_runner=/usr/lib/qt6/bin/qmltestrunner
if [ ! -x "$task_runner" ]; then
    task_runner="$(command -v qmltestrunner6 || true)"
fi
if [ -z "$task_runner" ] || [ ! -x "$task_runner" ]; then
    echo "Qt 6 Quick Test is required to run the QML fixture suite." >&2
    exit 1
fi
task_runtime_dir="$(mktemp -d)"
trap 'rm -rf -- "$task_runtime_dir"' EXIT
chmod 700 "$task_runtime_dir"
cd "$task_runtime_dir"
XDG_RUNTIME_DIR="$task_runtime_dir" XDG_CACHE_HOME="$task_runtime_dir/cache" \
QML_IMPORT_PATH="$task_test_dir/qmlhost/imports" \
QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
QT_QPA_PLATFORMTHEME=generic QT_STYLE_OVERRIDE=Fusion \
"$task_runner" -input "$task_test_dir/qmlhost" -import "$task_test_dir/qmlhost/imports"
if [ -n "${NORDVPN_TEST_CAPTURE_DIR:-}" ]; then
    mkdir -p -- "$NORDVPN_TEST_CAPTURE_DIR"
    cp -- "$task_runtime_dir"/qml-*.png "$NORDVPN_TEST_CAPTURE_DIR/"
fi
