#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./workspace-sync-lib.sh
source "$SCRIPT_DIR/workspace-sync-lib.sh"

SKILL_DIR=""
CONTRACT_PATH=""
WORKSPACE_NAME=""
STAGE_DIR=""
declare -a PROJECT_SPECS=()
declare -a STATE_FILTERS=()

usage() {
  cat <<'EOF'
Usage: ./export-skill-states.sh --skill-dir <dir> --workspace-name <name> --stage-dir <dir> [options]

Exports all portable states for a single skill into the workspace staging directory.

Options:
  --skill-dir <dir>        Required. Skill root directory.
  --contract <path>        Optional. Override workspace-sync.contract.json path.
  --workspace-name <name>  Required. Workspace name.
  --stage-dir <dir>        Required. Workspace staging directory.
  --project <name=path>    Optional. Project mapping for project-scoped states. Repeatable.
  --state-name <name>      Optional. Limit export to selected state names. Repeatable.
  -h, --help               Show this help.
EOF
}

emit_json_lines_array() {
  local file="$1"
  local first=1
  local line

  echo -n "["
  [[ -f "$file" ]] || {
    echo -n "]"
    return 0
  }

  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    [[ $first -eq 0 ]] && echo -n ","
    first=0
    printf '%s' "$line"
  done < "$file"

  echo -n "]"
}

state_selected() {
  local state_name="$1"
  local item

  [[ ${#STATE_FILTERS[@]} -eq 0 ]] && return 0

  for item in "${STATE_FILTERS[@]}"; do
    [[ "$item" == "$state_name" ]] && return 0
  done

  return 1
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
    --stage-dir)
      STAGE_DIR="${2:-}"
      shift 2
      ;;
    --project)
      PROJECT_SPECS+=("${2:-}")
      shift 2
      ;;
    --state-name)
      STATE_FILTERS+=("${2:-}")
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
[[ -n "$STAGE_DIR" ]] || {
  usage >&2
  ws_die "--stage-dir is required"
}

SKILL_DIR="$(ws_to_unix_path "$(ws_expand_home "$SKILL_DIR")")"
[[ -d "$SKILL_DIR" ]] || ws_die "Skill directory not found: $SKILL_DIR"

if [[ -n "$CONTRACT_PATH" ]]; then
  CONTRACT_PATH="$(ws_to_unix_path "$(ws_expand_home "$CONTRACT_PATH")")"
else
  CONTRACT_PATH="$SKILL_DIR/workspace-sync.contract.json"
fi
[[ -f "$CONTRACT_PATH" ]] || ws_die "Contract not found: $CONTRACT_PATH"

STAGE_DIR="$(ws_to_unix_path "$(ws_expand_home "$STAGE_DIR")")"
mkdir -p "$STAGE_DIR"

CONTRACT_VERSION="$(ws_get_json_string "$CONTRACT_PATH" "contract_version")"
[[ "$CONTRACT_VERSION" == "1" ]] || ws_die "Unsupported contract_version: ${CONTRACT_VERSION:-<empty>}"

SKILL_NAME="$(ws_get_json_string "$CONTRACT_PATH" "skill")"
[[ -n "$SKILL_NAME" ]] || ws_die "Missing skill name in contract: $CONTRACT_PATH"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
RESULTS_FILE="$TMP_DIR/results.jsonl"
: > "$RESULTS_FILE"

append_result() {
  printf '%s\n' "$1" >> "$RESULTS_FILE"
}

append_exported_result() {
  local state_name="$1"
  local scope="$2"
  local project_name="$3"
  local relative_dir="$4"
  local result_file="$5"
  local artifact
  local relative_file
  local first=1

  artifact="$(ws_get_json_string "$result_file" "artifact")"

  printf '{"skill":"%s","state":"%s","scope":"%s","portability":"portable","project":"%s","status":"exported","artifact":"%s","artifacts":' \
    "$(ws_json_escape "$SKILL_NAME")" \
    "$(ws_json_escape "$state_name")" \
    "$(ws_json_escape "$scope")" \
    "$(ws_json_escape "$project_name")" \
    "$(ws_json_escape "$relative_dir/$artifact")" >> "$RESULTS_FILE"

  echo -n "[" >> "$RESULTS_FILE"
  while IFS= read -r relative_file; do
    [[ -n "$relative_file" ]] || continue
    [[ $first -eq 0 ]] && echo -n "," >> "$RESULTS_FILE"
    first=0
    printf '"%s"' "$(ws_json_escape "$relative_dir/$relative_file")" >> "$RESULTS_FILE"
  done < <(ws_list_relative_files "$STAGE_DIR/$relative_dir")
  echo "]}" >> "$RESULTS_FILE"
}

append_skipped_result() {
  local state_name="$1"
  local scope="$2"
  local project_name="$3"
  local reason="$4"

  append_result "$(printf '{"skill":"%s","state":"%s","scope":"%s","portability":"portable","project":"%s","status":"skipped","reason":"%s"}' \
    "$(ws_json_escape "$SKILL_NAME")" \
    "$(ws_json_escape "$state_name")" \
    "$(ws_json_escape "$scope")" \
    "$(ws_json_escape "$project_name")" \
    "$(ws_json_escape "$reason")")"
}

run_export() {
  local state_name="$1"
  local scope="$2"
  local project_name="$3"
  local project_path="$4"
  local relative_dir="$5"
  local output_dir="$STAGE_DIR/$relative_dir"
  local result_file="$TMP_DIR/${state_name}-${project_name:-global}.json"
  local error_file="$TMP_DIR/${state_name}-${project_name:-global}.err"
  local error_text=""
  local -a cmd_args=(
    --skill-dir "$SKILL_DIR"
    --contract "$CONTRACT_PATH"
    --workspace-name "$WORKSPACE_NAME"
    --state-name "$state_name"
    --output-dir "$output_dir"
  )

  mkdir -p "$output_dir"

  if [[ -n "$project_name" ]]; then
    cmd_args+=(--project-name "$project_name")
  fi

  if [[ -n "$project_path" ]]; then
    cmd_args+=(--project-path "$project_path")
  fi

  if "$SCRIPT_DIR/run-skill-state-export.sh" "${cmd_args[@]}" >"$result_file" 2>"$error_file"; then
    append_exported_result "$state_name" "$scope" "$project_name" "$relative_dir" "$result_file"
  else
    error_text="$(tr '\r\n' ' ' < "$error_file" | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')"
    [[ -n "$error_text" ]] || error_text="export_failed"
    append_skipped_result "$state_name" "$scope" "$project_name" "$error_text"
  fi
}

while IFS=$'\t' read -r state_name state_scope state_portability; do
  [[ -n "$state_name" ]] || continue
  state_selected "$state_name" || continue

  if [[ "$state_scope" == "global" ]]; then
    run_export "$state_name" "$state_scope" "" "" "skill-states/$SKILL_NAME/global-$state_name"
    continue
  fi

  if [[ "$state_scope" != "project" ]]; then
    append_skipped_result "$state_name" "$state_scope" "" "unsupported_scope"
    continue
  fi

  if [[ ${#PROJECT_SPECS[@]} -eq 0 ]]; then
    append_skipped_result "$state_name" "$state_scope" "" "missing_project_context"
    continue
  fi

  for spec in "${PROJECT_SPECS[@]}"; do
    project_name="${spec%%=*}"
    project_path="${spec#*=}"

    if [[ "$spec" != *=* || -z "$project_name" || -z "$project_path" ]]; then
      append_skipped_result "$state_name" "$state_scope" "" "invalid_project_spec"
      continue
    fi

    project_path="$(ws_to_unix_path "$(ws_expand_home "$project_path")")"
    if [[ ! -d "$project_path" ]]; then
      append_skipped_result "$state_name" "$state_scope" "$project_name" "project_path_not_found"
      continue
    fi

    run_export "$state_name" "$state_scope" "$project_name" "$project_path" "skill-states/$SKILL_NAME/$project_name-$state_name"
  done
done < <(ws_list_contract_states "$CONTRACT_PATH" "portable")

printf '{"skill":"%s","results":' "$(ws_json_escape "$SKILL_NAME")"
emit_json_lines_array "$RESULTS_FILE"
echo "}"
