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

Runs the import_command for one portable state declared in workspace-sync.contract.json.

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

emit_json_array() {
  local file="$1"
  local first=1
  local item

  echo -n "["
  [[ -f "$file" ]] || {
    echo -n "]"
    return 0
  }

  while IFS= read -r item; do
    [[ -n "$item" ]] || continue
    [[ $first -eq 0 ]] && echo -n ","
    first=0
    printf '"%s"' "$(ws_json_escape "$item")"
  done < "$file"

  echo -n "]"
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
[[ -n "$IMPORT_COMMAND" ]] || ws_die "Missing import_command for state: $STATE_NAME"

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

CMD_ARGS=(
  --workspace-name "$WORKSPACE_NAME"
  --state-name "$STATE_NAME"
  --scope "$STATE_SCOPE"
  --input-dir "$INPUT_DIR"
)

if [[ -n "$PROJECT_NAME" ]]; then
  CMD_ARGS+=(--project-name "$PROJECT_NAME")
fi

if [[ -n "$PROJECT_PATH" ]]; then
  CMD_ARGS+=(--project-path "$PROJECT_PATH")
fi

ws_run_command_spec "$SKILL_DIR" "$IMPORT_COMMAND" "${CMD_ARGS[@]}"

MAIN_ARTIFACT="$(head -n 1 "$ARTIFACTS_FILE" | tr -d '\r')"

printf '{"status":"restored","skill":"%s","state":"%s","scope":"%s","project":"%s","input_dir":"%s","artifact":"%s","artifacts":' \
  "$(ws_json_escape "$SKILL_NAME")" \
  "$(ws_json_escape "$STATE_NAME")" \
  "$(ws_json_escape "$STATE_SCOPE")" \
  "$(ws_json_escape "$PROJECT_NAME")" \
  "$(ws_json_escape "$(ws_to_host_path "$INPUT_DIR")")" \
  "$(ws_json_escape "$MAIN_ARTIFACT")"
emit_json_array "$ARTIFACTS_FILE"
echo "}"
