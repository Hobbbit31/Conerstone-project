#!/usr/bin/env bash
# run_dashboard.sh — Build the VHDL simulator and launch the Tkinter UI.
#
# All paths are relative to this script's own location, so the project
# runs unchanged on any machine that checks it out.
#
# Usage (from anywhere):
#   ./ui/run_dashboard.sh              # build (incremental) + launch UI
#   ./ui/run_dashboard.sh --clean      # make clean before building
#   ./ui/run_dashboard.sh --no-build   # skip compile, just launch the UI

set -euo pipefail

# Always operate from the UI directory so every path below can be relative.
cd "$(dirname "${BASH_SOURCE[0]}")"

DO_CLEAN=0
DO_BUILD=1

while [[ $# -gt 0 ]]; do
    case "$1" in
        --clean)    DO_CLEAN=1; shift ;;
        --no-build) DO_BUILD=0; shift ;;
        -h|--help)
            grep '^#' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)  echo "Unknown option: $1" >&2; exit 2 ;;
    esac
done

echo "========================================================"
echo " Parallel VHDL Simulator — Dashboard"
echo "========================================================"
echo

# ── Build step ────────────────────────────────────────────────────────
if [[ "${DO_BUILD}" -eq 1 ]]; then
    echo "[1/3] Building C++ simulator..."
    (
        cd ..
        if [[ "${DO_CLEAN}" -eq 1 ]]; then
            make clean
        fi
        make
    )
    echo
fi

# Locate the binary relative to ui/. The Makefile produces `simulator`
# (no .exe suffix) on Linux/WSL/macOS and `simulator.exe` under
# MSYS2/MinGW. A stale `simulator.exe` committed from a Windows build can
# coexist with a fresh `simulator` on Linux and will be the one WITHOUT
# flex/bison support — so on non-Windows platforms we ignore .exe
# outright.
IS_WINDOWS=0
case "$(uname -s 2>/dev/null)" in
    MINGW*|MSYS*|CYGWIN*) IS_WINDOWS=1 ;;
esac

if [[ "${IS_WINDOWS}" -eq 1 && -x "../simulator.exe" ]]; then
    BIN_REL="../simulator.exe"
elif [[ -x "../simulator" ]]; then
    BIN_REL="../simulator"
elif [[ -x "../simulator.exe" ]]; then
    BIN_REL="../simulator.exe"
else
    echo "Error: simulator binary not found next to the project Makefile." >&2
    echo "       Run without --no-build, or run 'make' in the parent dir." >&2
    exit 1
fi
echo "Binary  : ${BIN_REL}"
echo

# ── Python check ──────────────────────────────────────────────────────
# The dashboard uses only Python's standard library (tkinter, subprocess,
# threading, …), so no pip/venv is required. We just verify that Python 3
# and the tkinter module are available.
echo "[2/3] Checking Python stdlib..."

if   command -v python3 >/dev/null 2>&1; then PY=python3
elif command -v python  >/dev/null 2>&1; then PY=python
else
    echo "Error: python not found on PATH" >&2
    exit 1
fi

if ! "${PY}" -c "import tkinter" >/dev/null 2>&1; then
    echo "Error: Python's tkinter module is not installed." >&2
    echo "  On Debian/Ubuntu/WSL: sudo apt install python3-tk" >&2
    echo "  On Fedora/RHEL      : sudo dnf install python3-tkinter" >&2
    echo "  On macOS (Homebrew) : brew install python-tk" >&2
    exit 1
fi

echo "  using ${PY} ($("${PY}" --version 2>&1))"
echo

# ── Launch dashboard ──────────────────────────────────────────────────
echo "[3/3] Launching dashboard..."
echo

# Hand the relative binary path to the Python app so it too stays
# location-independent. dashboard.py resolves it against its own location.
export VHDL_SIM_BIN_REL="${BIN_REL}"

# Keep OpenMP worker threads spinning between parallel regions instead
# of parking on futexes. Without this, short back-to-back parallel
# regions pay wake-up latency every time a new process starts one —
# that noise dominates the scaling numbers on small designs. The
# dashboard also sets this per-subprocess, but exporting it here makes
# the contract explicit if someone launches dashboard.py manually.
export OMP_WAIT_POLICY=active

exec "${PY}" dashboard.py