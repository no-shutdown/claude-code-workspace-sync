#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./workspace-sync-lib.sh
source "$SCRIPT_DIR/workspace-sync-lib.sh"

SKILL_DIR=""
CONTRACT_PATH=""
WORKSPACE_NAME=""
STATE_NAME=""
PROJECT_NAME=""
PROJECT_PATH=""
INPUT_DIR=""

usage() {
  cat <<'EOF'
Usage: ./run-skill-state-import.sh --skill-dir <dir> --workspace-name <name> --state-name <name> --input-dir <dir> [options]

Imports one portable state declared in workspace-sync.contract.json.
Supports two modes: sync_paths (built-in atomic extraction) or import_command (custom script).

Options:
  --skill-dir <dir>        Required. Skill root directory.
  --contract <path>        Optional. Override workspace-sync.contract.json path.
  --workspace-name <name>  Required. Workspace name.
  --state-name <name>      Required. State name declared in the contract.
  --project-name <name>    Optional. Required when scope=project.
  --project-path <path>    Optional. Required when scope=project.
  --input-dir <dir>        Required. State input directory.
  -h, --help               Show this help.
EOF
}


while [[ $# -gt 0 ]]; do
  case "$1" in
    --skill-dir)
      SKILL_DIR="${2:-}"
      shift 2
      ;;
    --contract)
      CONTRACT_PATH="${2:-}"
      shift 2
      ;;
    --workspace-name)
      WORKSPACE_NAME="${2:-}"
      shift 2
      ;;
    --state-name)
      STATE_NAME="${2:-}"
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
      ws_die "Unknown argument: $1"
      ;;
  esac
done

[[ -n "$SKILL_DIR" ]] || {
  usage >&2
  ws_die "--skill-dir is required"
}
[[ -n "$WORKSPACE_NAME" ]] || {
  usage >&2
  ws_die "--workspace-name is required"
}
[[ -n "$STATE_NAME" ]] || {
  usage >&2
  ws_die "--state-name is required"
}
[[ -n "$INPUT_DIR" ]] || {
  usage >&2
  ws_die "--input-dir is required"
}

SKILL_DIR="$(ws_to_unix_path "$(ws_expand_home "$SKILL_DIR")")"
[[ -d "$SKILL_DIR" ]] || ws_die "Skill directory not found: $SKILL_DIR"

if [[ -n "$CONTRACT_PATH" ]]; then
  CONTRACT_PATH="$(ws_to_unix_path "$(ws_expand_home "$CONTRACT_PATH")")"
else
  CONTRACT_PATH="$SKILL_DIR/workspace-sync.contract.json"
fi
[[ -f "$CONTRACT_PATH" ]] || ws_die "Contract not found: $CONTRACT_PATH"

INPUT_DIR="$(ws_to_unix_path "$(ws_expand_home "$INPUT_DIR")")"
[[ -d "$INPUT_DIR" ]] || ws_die "Input directory not found: $INPUT_DIR"

if [[ -n "$PROJECT_PATH" ]]; then
  PROJECT_PATH="$(ws_to_unix_path "$(ws_expand_home "$PROJECT_PATH")")"
fi

CONTRACT_VERSION="$(ws_get_json_string "$CONTRACT_PATH" "contract_version")"
[[ "$CONTRACT_VERSION" == "1" ]] || ws_die "Unsupported contract_version: ${CONTRACT_VERSION:-<empty>}"

SKILL_NAME="$(ws_get_json_string "$CONTRACT_PATH" "skill")"
[[ -n "$SKILL_NAME" ]] || ws_die "Missing skill name in contract: $CONTRACT_PATH"

STATE_SCOPE="$(ws_get_contract_state_string "$CONTRACT_PATH" "$STATE_NAME" "scope")"
[[ -n "$STATE_SCOPE" ]] || ws_die "State not found in contract: $STATE_NAME"

PORTABILITY="$(ws_get_contract_state_string "$CONTRACT_PATH" "$STATE_NAME" "portability")"
[[ "$PORTABILITY" == "portable" ]] || ws_die "State is not portable: $STATE_NAME"

IMPORT_COMMAND="$(ws_get_contract_state_string "$CONTRACT_PATH" "$STATE_NAME" "import_command")"
HAS_SYNC_PATHS=0
while IFS= read -r _sp; do
  [[ -n "$_sp" ]] && { HAS_SYNC_PATHS=1; break; }
done < <(ws_get_contract_state_paths "$CONTRACT_PATH" "$STATE_NAME")

if [[ -z "$IMPORT_COMMAND" && "$HAS_SYNC_PATHS" -eq 0 ]]; then
  ws_die "State '$STATE_NAME' requires either import_command or sync_paths in contract"
fi

if [[ "$STATE_SCOPE" == "project" ]]; then
  [[ -n "$PROJECT_NAME" ]] || ws_die "--project-name is required for project scope"
  [[ -n "$PROJECT_PATH" ]] || ws_die "--project-path is required for project scope"
  [[ -d "$PROJECT_PATH" ]] || ws_die "Project path not found: $PROJECT_PATH"
else
  PROJECT_NAME=""
  PROJECT_PATH=""
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
ARTIFACTS_FILE="$TMP_DIR/artifacts.txt"
: > "$ARTIFACTS_FILE"

MANIFEST_FILE="$INPUT_DIR/manifest.json"
if [[ -f "$MANIFEST_FILE" ]]; then
  while IFS= read -r item; do
    [[ -n "$item" ]] || continue
    [[ -f "$INPUT_DIR/$item" ]] || ws_die "Manifest-listed artifact missing: $INPUT_DIR/$item"
    printf '%s\n' "$item" >> "$ARTIFACTS_FILE"
  done < <(ws_get_manifest_artifacts "$MANIFEST_FILE")
fi

if [[ ! -s "$ARTIFACTS_FILE" ]]; then
  if [[ -f "$INPUT_DIR/state.tgz" ]]; then
    printf 'state.tgz\n' >> "$ARTIFACTS_FILE"
  else
    while IFS= read -r item; do
      [[ -n "$item" ]] || continue
      [[ "$item" == "manifest.json" ]] && continue
      printf '%s\n' "$item" >> "$ARTIFACTS_FILE"
    done < <(ws_list_relative_files "$INPUT_DIR")
  fi
fi

[[ -s "$ARTIFACTS_FILE" ]] || ws_die "No importable artifacts found in: $INPUT_DIR"

if [[ -n "$IMPORT_COMMAND" ]]; then
  # 自定义脚本模式：把脚本的 stdout 重定向到 stderr，保证本 runner 的 stdout 只输出 JSON
  CMD_ARGS=(
    --workspace-name "$WORKSPACE_NAME"
    --state-name "$STATE_NAME"
    --scope "$STATE_SCOPE"
    --input-dir "$INPUT_DIR"
  )
  [[ -n "$PROJECT_NAME" ]] && CMD_ARGS+=(--project-name "$PROJECT_NAME")
  [[ -n "$PROJECT_PATH" ]] && CMD_ARGS+=(--project-path "$PROJECT_PATH")

  ws_run_command_spec "$SKILL_DIR" "$IMPORT_COMMAND" "${CMD_ARGS[@]}" >&2
else
  # 内置 sync_paths 模式：原子提取——先解到临时目录，成功后再合并到项目目录
  [[ "$STATE_SCOPE" != "global" ]] || \
    ws_die "sync_paths import not supported for global scope; use import_command instead"

  [[ -f "$INPUT_DIR/state.tgz" ]] || ws_die "Missing state archive: $INPUT_DIR/state.tgz"

  RESTORE_TMP="$TMP_DIR/restore"
  mkdir -p "$RESTORE_TMP"

  tar -C "$RESTORE_TMP" -xzf "$INPUT_DIR/state.tgz" >&2 || \
    ws_die "Failed to extract state archive for state: $STATE_NAME"

  cp -R "$RESTORE_TMP/." "$PROJECT_PATH/" >&2 || \
    ws_die "Failed to restore state to: $PROJECT_PATH"
fi

MAIN_ARTIFACT="$(head -n 1 "$ARTIFACTS_FILE" | tr -d '\r')"

printf '{"status":"restored","skill":"%s","state":"%s","scope":"%s","project":"%s","input_dir":"%s","artifact":"%s","artifacts":' \
  "$(ws_json_escape "$SKILL_NAME")" \
  "$(ws_json_escape "$STATE_NAME")" \
  "$(ws_json_escape "$STATE_SCOPE")" \
  "$(ws_json_escape "$PROJECT_NAME")" \
  "$(ws_json_escape "$(ws_to_host_path "$INPUT_DIR")")" \
  "$(ws_json_escape "$MAIN_ARTIFACT")"
ws_emit_json_string_array "$ARTIFACTS_FILE"
echo "}"
