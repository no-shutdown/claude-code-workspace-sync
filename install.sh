#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${HOME}/.claude/skills/workspace-sync"
INIT_CONFIG=1

usage() {
  cat <<'EOF'
Usage: ./install.sh [--target <dir>] [--no-init-config]

Installs the workspace-sync skill into the local Claude skills directory.

Options:
  --target <dir>      Install into a custom target directory.
  --no-init-config    Do not create config.json from the example template.
  -h, --help          Show this help.
EOF
}

assert_safe_target() {
  local target="$1"

  [[ -n "$target" ]] || {
    echo "Refusing to install to an empty target path." >&2
    exit 1
  }

  case "$target" in
    /|.|"$HOME"|"$HOME/.claude"|"$HOME/.claude/skills")
      echo "Refusing to install to unsafe target: $target" >&2
      exit 1
      ;;
  esac
}

copy_file() {
  local src="$1"
  local dest="$2"

  mkdir -p "$(dirname "$dest")"
  cp "$src" "$dest"
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
    --no-init-config)
      INIT_CONFIG=0
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

mkdir -p "$TARGET_DIR/scripts"
mkdir -p "$TARGET_DIR/docs"

copy_file "$SCRIPT_DIR/SKILL.md" "$TARGET_DIR/SKILL.md"
copy_file "$SCRIPT_DIR/README.md" "$TARGET_DIR/README.md"
copy_file "$SCRIPT_DIR/install.sh" "$TARGET_DIR/install.sh"
copy_file "$SCRIPT_DIR/uninstall.sh" "$TARGET_DIR/uninstall.sh"
copy_file "$SCRIPT_DIR/templates/config.json.example" "$TARGET_DIR/config.json.example"
copy_file "$SCRIPT_DIR/templates/workspace-sync.contract.example.json" "$TARGET_DIR/workspace-sync.contract.example.json"
copy_file "$SCRIPT_DIR/scripts/detect-projects.sh" "$TARGET_DIR/scripts/detect-projects.sh"
copy_file "$SCRIPT_DIR/docs/skill-state-contract.md" "$TARGET_DIR/docs/skill-state-contract.md"

chmod +x "$TARGET_DIR/scripts/detect-projects.sh"
chmod +x "$TARGET_DIR/install.sh" "$TARGET_DIR/uninstall.sh"

if [[ "$INIT_CONFIG" == "1" && ! -f "$TARGET_DIR/config.json" ]]; then
  copy_file "$SCRIPT_DIR/templates/config.json.example" "$TARGET_DIR/config.json"
fi

cat <<EOF
Installed workspace-sync to:
  $TARGET_DIR

Files:
  $TARGET_DIR/SKILL.md
  $TARGET_DIR/install.sh
  $TARGET_DIR/uninstall.sh
  $TARGET_DIR/scripts/detect-projects.sh
  $TARGET_DIR/config.json.example
  $TARGET_DIR/workspace-sync.contract.example.json

Next steps:
  1. Review $TARGET_DIR/config.json
  2. Start Claude Code and run /workspace-sync push <name>
EOF
