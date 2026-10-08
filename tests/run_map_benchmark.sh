#!/usr/bin/env bash
set -euo pipefail
task_test_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
task_runner=/usr/lib/qt6/bin/qmltestrunner
if [ ! -x "$task_runner" ]; then
    task_runner="$(command -v qmltestrunner6 || true)"
fi
if [ -z "$task_runner" ] || [ ! -x "$task_runner" ]; then
    echo "Qt 6 Quick Test is required to run the map benchmark." >&2
    exit 1
fi
task_backend="${NORDVPN_BENCHMARK_BACKEND:-software}"
case "$task_backend" in
    software) export QT_QUICK_BACKEND=software ;;
    opengl)
        unset QT_QUICK_BACKEND
        export QSG_RHI_BACKEND=opengl QSG_INFO=1
        ;;
    *) echo "NORDVPN_BENCHMARK_BACKEND must be software or opengl." >&2; exit 1 ;;
esac
task_runtime_dir="$(mktemp -d)"
trap 'rm -rf -- "$task_runtime_dir"' EXIT
chmod 700 "$task_runtime_dir"
task_platform="${NORDVPN_BENCHMARK_PLATFORM:-offscreen}"
task_qt_runtime_dir="$task_runtime_dir"
case "$task_platform" in
    wayland*)
        # Relative WAYLAND_DISPLAY sockets live in the desktop runtime directory.
        task_qt_runtime_dir="${XDG_RUNTIME_DIR:-}"
        if [ -z "$task_qt_runtime_dir" ] || [ ! -d "$task_qt_runtime_dir" ]; then
            echo "The Wayland benchmark requires the desktop XDG_RUNTIME_DIR." >&2
            exit 1
        fi
        ;;
esac
cd "$task_runtime_dir"
XDG_RUNTIME_DIR="$task_qt_runtime_dir" XDG_CACHE_HOME="$task_runtime_dir/cache" \
QML_IMPORT_PATH="$task_test_dir/qmlhost/imports" \
QT_QPA_PLATFORM="$task_platform" \
QT_QPA_PLATFORMTHEME=generic QT_STYLE_OVERRIDE=Fusion \
QT_LOGGING_RULES="${QT_LOGGING_RULES:-};qml.info=true" \
"$task_runner" -input "$task_test_dir/qmlperf" -import "$task_test_dir/qmlhost/imports" "$@"
