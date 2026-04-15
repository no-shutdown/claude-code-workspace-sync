#!/usr/bin/env bash
set -euo pipefail

TARGET_DIR="${HOME}/.claude/skills/workspace-sync"
ASSUME_YES=0

usage() {
  cat <<'EOF'
Usage: ./uninstall.sh [--target <dir>] [--yes]

Removes the installed workspace-sync skill directory.

Options:
  --target <dir>  Remove a custom installation directory.
  --yes           Do not prompt for confirmation.
  -h, --help      Show this help.
EOF
}

assert_safe_target() {
  local target="$1"

  [[ -n "$target" ]] || {
    echo "Refusing to uninstall an empty target path." >&2
    exit 1
  }

  case "$target" in
    /|.|"$HOME"|"$HOME/.claude"|"$HOME/.claude/skills")
      echo "Refusing to uninstall unsafe target: $target" >&2
      exit 1
      ;;
  esac
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      [[ $# -ge 2 ]] || {
        echo "--target requires a path." >&2
        exit 1
      }
      TARGET_DIR="$2"
      shift 2
      ;;
    --yes)
      ASSUME_YES=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

assert_safe_target "$TARGET_DIR"

if [[ ! -e "$TARGET_DIR" ]]; then
  echo "Nothing to remove: $TARGET_DIR"
  exit 0
fi

if [[ "$ASSUME_YES" != "1" ]]; then
  read -r -p "Remove workspace-sync from '$TARGET_DIR'? [y/N] " reply
  case "$reply" in
    y|Y|yes|YES)
      ;;
    *)
      echo "Aborted."
      exit 1
      ;;
  esac
fi

rm -rf -- "$TARGET_DIR"
echo "Removed: $TARGET_DIR"
