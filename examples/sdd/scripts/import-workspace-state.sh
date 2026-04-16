#!/usr/bin/env bash
set -euo pipefail

WORKSPACE_NAME=""
STATE_NAME=""
SCOPE=""
PROJECT_NAME=""
PROJECT_PATH=""
INPUT_DIR=""

usage() {
  cat <<'EOF'
Usage: import-workspace-state.sh --workspace-name <name> --state-name <name> --scope <project|global> --input-dir <dir> [--project-name <name>] [--project-path <path>]
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace-name)
      WORKSPACE_NAME="${2:-}"
      shift 2
      ;;
    --state-name)
      STATE_NAME="${2:-}"
      shift 2
      ;;
    --scope)
      SCOPE="${2:-}"
      shift 2
      ;;
    --project-name)
      PROJECT_NAME="${2:-}"
      shift 2
      ;;
    --project-path)
      PROJECT_PATH="${2:-}"
      shift 2
      ;;
    --input-dir)
      INPUT_DIR="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

[[ -n "$WORKSPACE_NAME" ]] || { usage >&2; exit 1; }
[[ -n "$STATE_NAME" ]] || { usage >&2; exit 1; }
[[ "$SCOPE" == "project" || "$SCOPE" == "global" ]] || { usage >&2; exit 1; }
[[ -n "$INPUT_DIR" ]] || { usage >&2; exit 1; }

if [[ "$SCOPE" == "project" ]]; then
  [[ -n "$PROJECT_NAME" ]] || { echo "--project-name is required for project scope" >&2; exit 1; }
  [[ -n "$PROJECT_PATH" ]] || { echo "--project-path is required for project scope" >&2; exit 1; }
fi

if [[ "$SCOPE" != "project" || "$STATE_NAME" != "project-state" ]]; then
  echo "This example only imports the SDD project-state." >&2
  exit 1
fi

[[ -d "$PROJECT_PATH" ]] || { echo "Project path not found: $PROJECT_PATH" >&2; exit 1; }
[[ -f "$INPUT_DIR/state.tgz" ]] || { echo "Missing artifact: $INPUT_DIR/state.tgz" >&2; exit 1; }

mkdir -p "$PROJECT_PATH/.sdd"
tar -C "$PROJECT_PATH" -xzf "$INPUT_DIR/state.tgz"
