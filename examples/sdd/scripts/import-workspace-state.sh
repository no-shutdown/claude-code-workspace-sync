#!/usr/bin/env bash
# 自定义导入脚本示例 —— 仅在需要特殊处理时使用（如 schema 升级、索引重建等）。
# 对于简单的文件同步场景，直接在 workspace-sync.contract.json 中声明 sync_paths 即可，
# 无需编写此脚本。
#
# 约定：
#   - 成功时退出码为 0，失败时退出非零
#   - 所有日志写到 stderr，stdout 保留给 workspace-sync 框架使用
#   - 采用"先提取到临时目录、再整体合并"的原子策略，避免部分覆盖

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
    --workspace-name) WORKSPACE_NAME="${2:-}"; shift 2 ;;
    --state-name)     STATE_NAME="${2:-}";     shift 2 ;;
    --scope)          SCOPE="${2:-}";           shift 2 ;;
    --project-name)   PROJECT_NAME="${2:-}";   shift 2 ;;
    --project-path)   PROJECT_PATH="${2:-}";   shift 2 ;;
    --input-dir)      INPUT_DIR="${2:-}";      shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

[[ -n "$WORKSPACE_NAME" ]] || { usage >&2; exit 1; }
[[ -n "$STATE_NAME" ]]     || { usage >&2; exit 1; }
[[ "$SCOPE" == "project" || "$SCOPE" == "global" ]] || { usage >&2; exit 1; }
[[ -n "$INPUT_DIR" ]]      || { usage >&2; exit 1; }

if [[ "$SCOPE" == "project" ]]; then
  [[ -n "$PROJECT_NAME" ]] || { echo "--project-name is required for project scope" >&2; exit 1; }
  [[ -n "$PROJECT_PATH" ]] || { echo "--project-path is required for project scope" >&2; exit 1; }
fi

if [[ "$SCOPE" != "project" || "$STATE_NAME" != "project-state" ]]; then
  echo "This script only handles: scope=project, state=project-state" >&2
  exit 1
fi

[[ -d "$PROJECT_PATH" ]] || { echo "Project path not found: $PROJECT_PATH" >&2; exit 1; }
[[ -f "$INPUT_DIR/state.tgz" ]] || { echo "Missing artifact: $INPUT_DIR/state.tgz" >&2; exit 1; }

# 原子策略：先提取到临时目录，成功后再合并到项目，避免部分覆盖
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

tar -C "$TMP_DIR" -xzf "$INPUT_DIR/state.tgz" >&2 || {
  echo "Failed to extract state.tgz" >&2
  exit 1
}

mkdir -p "$PROJECT_PATH/.sdd"
cp -R "$TMP_DIR/." "$PROJECT_PATH/" >&2

echo "Imported SDD project-state for $PROJECT_NAME" >&2
