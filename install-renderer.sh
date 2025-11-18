#!/usr/bin/env bash
set -euo pipefail

REPO_OWNER="promptics-org"
REPO_NAME="promptics-adoc-renderer"
DEFAULT_BRANCH="main"
DEFAULT_TARGET_DIR="doc-renderer"

BRANCH="$DEFAULT_BRANCH"
TARGET_DIR="$DEFAULT_TARGET_DIR"
SKIP_BOOTSTRAP=false

usage() {
  cat <<'EOF'
Usage: install-renderer.sh [options]

Options:
  -d, --dir <path>         Destination directory (default: doc-renderer)
      --branch <name>      Source branch or tag to install (default: main)
      --skip-bootstrap     Copy files without running generate.sh --bootstrap
  -h, --help               Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--dir)
      [[ $# -ge 2 ]] || { echo "Missing value for $1" >&2; exit 1; }
      TARGET_DIR="$2"
      shift 2
      ;;
    --branch)
      [[ $# -ge 2 ]] || { echo "Missing value for $1" >&2; exit 1; }
      BRANCH="$2"
      shift 2
      ;;
    --skip-bootstrap)
      SKIP_BOOTSTRAP=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

command -v curl >/dev/null || { echo "curl is required" >&2; exit 1; }
command -v tar >/dev/null || { echo "tar is required" >&2; exit 1; }

TARGET_DIR="${TARGET_DIR%/}"
[[ -n "$TARGET_DIR" ]] || { echo "Target directory cannot be empty" >&2; exit 1; }

if [[ -d "$TARGET_DIR" && -n "$(find "$TARGET_DIR" -mindepth 1 -maxdepth 1 2>/dev/null)" ]]; then
  echo "Target directory '$TARGET_DIR' already exists and is not empty." >&2
  echo "Choose an empty directory or remove existing files." >&2
  exit 1
fi

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

ARCHIVE_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}/archive/refs/heads/${BRANCH}.tar.gz"
ARCHIVE_PATH="$TMPDIR/source.tar.gz"

echo "Downloading renderer from ${ARCHIVE_URL} ..."
curl -fsSL "$ARCHIVE_URL" -o "$ARCHIVE_PATH"

tar -xzf "$ARCHIVE_PATH" -C "$TMPDIR"
SOURCE_DIR="$TMPDIR/${REPO_NAME}-${BRANCH}/doc-renderer"

[[ -d "$SOURCE_DIR" ]] || { echo "Failed to locate doc-renderer directory in archive" >&2; exit 1; }

mkdir -p "$TARGET_DIR"
cp -R "$SOURCE_DIR"/. "$TARGET_DIR"/
chmod +x "$TARGET_DIR/generate.sh"

echo "Renderer installed into $TARGET_DIR"

if [[ "$SKIP_BOOTSTRAP" == true ]]; then
  exit 0
fi

if [[ -x "$TARGET_DIR/generate.sh" ]]; then
  echo "Running bootstrap (downloads fonts and PlantUML jar as needed) ..."
  (cd "$TARGET_DIR" && ./generate.sh --bootstrap)
  echo "Bootstrap complete."
fi
