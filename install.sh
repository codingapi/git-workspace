#!/bin/sh
# git-workspace installer for Linux / macOS / Windows (Git Bash, MSYS, Cygwin)
#
# Usage:
#   ./install.sh [--prefix DIR] [--uninstall]
#
# Default prefix: $HOME/.local  ->  installs $HOME/.local/bin/git-workspace
# For native Windows (cmd/PowerShell) use install.ps1 instead.

set -eu

PREFIX="${PREFIX:-$HOME/.local}"
UNINSTALL=0
REPO_URL="https://github.com/codingapi/git-workspace.git"

while [ $# -gt 0 ]; do
    case "$1" in
        --prefix)
            [ $# -ge 2 ] || { echo "error: --prefix requires a value" >&2; exit 1; }
            PREFIX="$2"; shift 2 ;;
        --prefix=*)
            PREFIX="${1#*=}"; shift ;;
        --uninstall)
            UNINSTALL=1; shift ;;
        -h|--help)
            cat <<EOF
Usage: install.sh [--prefix DIR] [--uninstall]

  --prefix DIR   installation prefix (default: \$HOME/.local)
                 the CLI is installed to DIR/bin/git-workspace
  --uninstall    remove the installed git-workspace command
EOF
            exit 0 ;;
        *)
            echo "error: unknown option: $1 (see --help)" >&2; exit 1 ;;
    esac
done

BIN="$PREFIX/bin/git-workspace"

if [ "$UNINSTALL" = 1 ]; then
    rm -f "$BIN"
    echo "==> removed $BIN"
    exit 0
fi

# ---- platform ------------------------------------------------------------
OS="$(uname -s 2>/dev/null || echo unknown)"
case "$OS" in
    Linux|Darwin)
        ;;
    MINGW*|MSYS*|CYGWIN*)
        echo "note: Windows Git Bash / MSYS / Cygwin detected — installing the POSIX CLI."
        echo "      For native Windows (cmd / PowerShell) use install.ps1 instead."
        ;;
    *)
        echo "warning: unrecognized platform '$OS' — attempting install anyway" >&2
        ;;
esac

# ---- locate sources: beside this script, or clone the repo (curl|sh mode)
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SRC_DIR="$SCRIPT_DIR"
TMP_CLONE=""
if [ ! -f "$SRC_DIR/git-workspace" ]; then
    command -v git >/dev/null 2>&1 || {
        echo "error: git is required to clone the repository" >&2; exit 1; }
    TMP_CLONE=$(mktemp -d)
    trap 'rm -rf "$TMP_CLONE"' EXIT
    echo "==> cloning $REPO_URL"
    git clone --depth 1 --quiet "$REPO_URL" "$TMP_CLONE"
    SRC_DIR="$TMP_CLONE"
fi

# ---- dependency checks: python3, git, PyYAML ------------------------------
command -v python3 >/dev/null 2>&1 || {
    echo "error: python3 not found — install Python 3.8+" >&2; exit 1; }
command -v git >/dev/null 2>&1 || {
    echo "error: git not found" >&2; exit 1; }
if ! python3 -c "import yaml" >/dev/null 2>&1; then
    echo "==> PyYAML missing — attempting: python3 -m pip install --user pyyaml"
    python3 -m pip install --user pyyaml || {
        echo "error: could not install PyYAML — install it manually (pip install pyyaml)" >&2
        exit 1; }
fi

# ---- install ---------------------------------------------------------------
mkdir -p "$PREFIX/bin"
cp "$SRC_DIR/git-workspace" "$BIN"
chmod +x "$BIN"
echo "==> installed: $BIN"

case ":$PATH:" in
    *":$PREFIX/bin:"*)
        ;;
    *)
        echo "note: $PREFIX/bin is not in your PATH — add it, e.g.:"
        echo "      echo 'export PATH=\"$PREFIX/bin:\$PATH\"' >> ~/.profile   # then re-login or source it"
        ;;
esac

echo "==> done. Try: git-workspace version"
