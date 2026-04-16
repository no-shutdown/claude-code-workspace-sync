#!/usr/bin/env bash
# 自定义导出脚本示例 —— 仅在需要特殊处理时使用（如路径转换、索引重建等）。
# 对于简单的文件同步场景，直接在 workspace-sync.contract.json 中声明 sync_paths 即可，
# 无需编写此脚本。
#
# 约定：
#   - 成功时退出码为 0，失败时退出非零
#   - 所有日志写到 stderr，stdout 保留给 workspace-sync 框架使用
#   - 在 --output-dir 下写 manifest.json + state.tgz

set -euo pipefail

WORKSPACE_NAME=""
STATE_NAME=""
SCOPE=""
PROJECT_NAME=""
PROJECT_PATH=""
OUTPUT_DIR=""

usage() {
  cat <<'EOF'
Usage: export-workspace-state.sh --workspace-name <name> --state-name <name> --scope <project|global> --output-dir <dir> [--project-name <name>] [--project-path <path>]
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace-name) WORKSPACE_NAME="${2:-}"; shift 2 ;;
    --state-name)     STATE_NAME="${2:-}";     shift 2 ;;
    --scope)          SCOPE="${2:-}";           shift 2 ;;
    --project-name)   PROJECT_NAME="${2:-}";   shift 2 ;;
    --project-path)   PROJECT_PATH="${2:-}";   shift 2 ;;
    --output-dir)     OUTPUT_DIR="${2:-}";     shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

[[ -n "$WORKSPACE_NAME" ]] || { usage >&2; exit 1; }
[[ -n "$STATE_NAME" ]]     || { usage >&2; exit 1; }
[[ "$SCOPE" == "project" || "$SCOPE" == "global" ]] || { usage >&2; exit 1; }
[[ -n "$OUTPUT_DIR" ]]     || { usage >&2; exit 1; }

if [[ "$SCOPE" == "project" ]]; then
  [[ -n "$PROJECT_NAME" ]] || { echo "--project-name is required for project scope" >&2; exit 1; }
  [[ -n "$PROJECT_PATH" ]] || { echo "--project-path is required for project scope" >&2; exit 1; }
fi

if [[ "$SCOPE" != "project" || "$STATE_NAME" != "project-state" ]]; then
  echo "This script only handles: scope=project, state=project-state" >&2
  exit 1
fi

[[ -d "$PROJECT_PATH" ]] || { echo "Project path not found: $PROJECT_PATH" >&2; exit 1; }

mkdir -p "$OUTPUT_DIR"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

HAS_CONTENT=0

if [[ -d "$PROJECT_PATH/.sdd/specs" ]]; then
  mkdir -p "$TMP_DIR/.sdd"
  cp -R "$PROJECT_PATH/.sdd/specs" "$TMP_DIR/.sdd/specs"
  HAS_CONTENT=1
fi

if [[ -f "$PROJECT_PATH/.sdd/tasks/current.json" ]]; then
  mkdir -p "$TMP_DIR/.sdd/tasks"
  cp "$PROJECT_PATH/.sdd/tasks/current.json" "$TMP_DIR/.sdd/tasks/current.json"
  HAS_CONTENT=1
fi

if [[ "$HAS_CONTENT" -eq 0 ]]; then
  echo "No SDD project state found in: $PROJECT_PATH/.sdd/" >&2
  exit 1
fi

cat > "$OUTPUT_DIR/manifest.json" <<EOF
{
  "skill": "sdd",
  "state": "project-state",
  "scope": "project",
  "workspace_name": "$WORKSPACE_NAME",
  "project": "$PROJECT_NAME",
  "format_version": 1,
  "artifacts": [
    "state.tgz"
  ]
}
EOF

tar -C "$TMP_DIR" -czf "$OUTPUT_DIR/state.tgz" ./ >&2
echo "Exported SDD project-state for $PROJECT_NAME" >&2
