#!/bin/sh
# git-workspace installer for Linux / macOS / Windows (Git Bash, MSYS, Cygwin)
#
# Usage:
#   ./install.sh [--prefix DIR] [--uninstall]
#   curl -fsSL https://raw.githubusercontent.com/codingapi/git-workspace/main/install.sh | sh
#   curl -fsSL .../install.sh | sh -s -- --uninstall
#
# Standalone mode (curl|sh) installs the LATEST RELEASE TAG, not the
# development branch. Default prefix: $HOME/.local  ->  $HOME/.local/bin/git-workspace
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

# ---- preflight: required dependencies (git, python3) ---------------------
# Checked up front so every missing dependency is reported together before any
# work is done. git is needed to clone (standalone mode) and at runtime;
# python3 runs the CLI.
MISSING=""
command -v git >/dev/null 2>&1 || MISSING="$MISSING git"
command -v python3 >/dev/null 2>&1 || MISSING="$MISSING python3"
if [ -n "$MISSING" ]; then
    echo "error: missing required dependencies:$MISSING" >&2
    echo "  git      -> https://git-scm.com" >&2
    echo "  python3  -> https://python.org (Python 3.8+)" >&2
    exit 1
fi

# ---- locate sources: beside this script, or clone the repo (curl|sh mode)
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SRC_DIR="$SCRIPT_DIR"
TMP_CLONE=""
if [ ! -f "$SRC_DIR/git-workspace" ]; then
    TMP_CLONE=$(mktemp -d)
    trap 'rm -rf "$TMP_CLONE"' EXIT
    # install from the latest release tag, not the development branch
    TAG=$(git ls-remote --tags --refs --sort=-v:refname "$REPO_URL" 2>/dev/null \
        | head -n 1 | sed 's|.*refs/tags/||')
    if [ -n "$TAG" ]; then
        echo "==> cloning $REPO_URL @ $TAG (latest release)"
        git clone --depth 1 --quiet --branch "$TAG" "$REPO_URL" "$TMP_CLONE"
    else
        echo "warning: no release tags found — installing from the default branch" >&2
        echo "==> cloning $REPO_URL"
        git clone --depth 1 --quiet "$REPO_URL" "$TMP_CLONE"
    fi
    SRC_DIR="$TMP_CLONE"
fi

# ---- dependency check: PyYAML (git + python3 verified in preflight) -------
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
VER=$("$BIN" version 2>/dev/null || echo "unknown")
echo "==> installed: $BIN ($VER)"

case ":$PATH:" in
    *":$PREFIX/bin:"*)
        ;;
    *)
        echo "note: $PREFIX/bin is not in your PATH — add it, e.g.:"
        echo "      echo 'export PATH=\"$PREFIX/bin:\$PATH\"' >> ~/.profile   # then re-login or source it"
        ;;
esac

echo "==> done. Try: git-workspace version"
