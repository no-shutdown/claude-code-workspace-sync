#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./workspace-sync-lib.sh
source "$SCRIPT_DIR/workspace-sync-lib.sh"

SKILL_DIR=""
CONTRACT_PATH=""
WORKSPACE_NAME=""
STAGE_DIR=""
MANIFEST_PATH=""
declare -a PROJECT_SPECS=()
declare -a STATE_FILTERS=()

usage() {
  cat <<'EOF'
Usage: ./import-skill-states.sh --skill-dir <dir> --workspace-name <name> --stage-dir <dir> --manifest <file> [options]

Imports all matching skill state entries for a single skill from a workspace manifest.

Options:
  --skill-dir <dir>        Required. Skill root directory.
  --contract <path>        Optional. Override workspace-sync.contract.json path.
  --workspace-name <name>  Required. Workspace name.
  --stage-dir <dir>        Required. Workspace staging directory.
  --manifest <file>        Required. Workspace manifest.json path.
  --project <name=path>    Optional. Local project mapping for project-scoped states. Repeatable.
  --state-name <name>      Optional. Limit import to selected state names. Repeatable.
  -h, --help               Show this help.
EOF
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

find_project_path() {
  local target_name="$1"
  local spec
  local project_name
  local project_path

  for spec in "${PROJECT_SPECS[@]}"; do
    project_name="${spec%%=*}"
    project_path="${spec#*=}"
    [[ "$spec" == *=* ]] || continue
    [[ "$project_name" == "$target_name" ]] || continue
    printf '%s\n' "$(ws_to_unix_path "$(ws_expand_home "$project_path")")"
    return 0
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
    --manifest)
      MANIFEST_PATH="${2:-}"
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
[[ -n "$MANIFEST_PATH" ]] || {
  usage >&2
  ws_die "--manifest is required"
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
[[ -d "$STAGE_DIR" ]] || ws_die "Stage directory not found: $STAGE_DIR"

MANIFEST_PATH="$(ws_to_unix_path "$(ws_expand_home "$MANIFEST_PATH")")"
[[ -f "$MANIFEST_PATH" ]] || ws_die "Manifest not found: $MANIFEST_PATH"

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

append_status_result() {
  local state_name="$1"
  local scope="$2"
  local project_name="$3"
  local status="$4"
  local reason="${5:-}"

  if [[ -n "$reason" ]]; then
    append_result "$(printf '{"skill":"%s","state":"%s","scope":"%s","project":"%s","status":"%s","reason":"%s"}' \
      "$(ws_json_escape "$SKILL_NAME")" \
      "$(ws_json_escape "$state_name")" \
      "$(ws_json_escape "$scope")" \
      "$(ws_json_escape "$project_name")" \
      "$(ws_json_escape "$status")" \
      "$(ws_json_escape "$reason")")"
  else
    append_result "$(printf '{"skill":"%s","state":"%s","scope":"%s","project":"%s","status":"%s"}' \
      "$(ws_json_escape "$SKILL_NAME")" \
      "$(ws_json_escape "$state_name")" \
      "$(ws_json_escape "$scope")" \
      "$(ws_json_escape "$project_name")" \
      "$(ws_json_escape "$status")")"
  fi
}

append_restored_result() {
  local state_name="$1"
  local scope="$2"
  local project_name="$3"
  local input_dir_rel="$4"
  local result_file="$5"
  local artifact
  local relative_file
  local first=1

  artifact="$(ws_get_json_string "$result_file" "artifact")"

  printf '{"skill":"%s","state":"%s","scope":"%s","project":"%s","status":"restored","artifact":"%s","artifacts":' \
    "$(ws_json_escape "$SKILL_NAME")" \
    "$(ws_json_escape "$state_name")" \
    "$(ws_json_escape "$scope")" \
    "$(ws_json_escape "$project_name")" \
    "$(ws_json_escape "$input_dir_rel/$artifact")" >> "$RESULTS_FILE"

  echo -n "[" >> "$RESULTS_FILE"
  while IFS= read -r relative_file; do
    [[ -n "$relative_file" ]] || continue
    [[ $first -eq 0 ]] && echo -n "," >> "$RESULTS_FILE"
    first=0
    printf '"%s"' "$(ws_json_escape "$input_dir_rel/$relative_file")" >> "$RESULTS_FILE"
  done < <(ws_list_relative_files "$STAGE_DIR/$input_dir_rel")
  echo "]}" >> "$RESULTS_FILE"
}

run_import() {
  local state_name="$1"
  local scope="$2"
  local project_name="$3"
  local project_path="$4"
  local input_dir_rel="$5"
  local input_dir="$STAGE_DIR/$input_dir_rel"
  local result_file="$TMP_DIR/${state_name}-${project_name:-global}.json"
  local error_file="$TMP_DIR/${state_name}-${project_name:-global}.err"
  local error_text=""
  local -a cmd_args=(
    --skill-dir "$SKILL_DIR"
    --contract "$CONTRACT_PATH"
    --workspace-name "$WORKSPACE_NAME"
    --state-name "$state_name"
    --input-dir "$input_dir"
  )

  [[ -d "$input_dir" ]] || {
    append_status_result "$state_name" "$scope" "$project_name" "skipped" "state_input_dir_missing"
    return 0
  }

  if [[ -n "$project_name" ]]; then
    cmd_args+=(--project-name "$project_name")
  fi

  if [[ -n "$project_path" ]]; then
    cmd_args+=(--project-path "$project_path")
  fi

  if "$SCRIPT_DIR/run-skill-state-import.sh" "${cmd_args[@]}" >"$result_file" 2>"$error_file"; then
    append_restored_result "$state_name" "$scope" "$project_name" "$input_dir_rel" "$result_file"
  else
    error_text="$(tr '\r\n' ' ' < "$error_file" | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')"
    [[ -n "$error_text" ]] || error_text="import_failed"
    append_status_result "$state_name" "$scope" "$project_name" "skipped" "$error_text"
  fi
}

ENTRY_COUNT=0

while IFS=$'\t' read -r state_name state_scope portability project_name export_status artifact first_artifact; do
  [[ -n "$state_name" ]] || continue
  state_selected "$state_name" || continue
  ENTRY_COUNT=$((ENTRY_COUNT + 1))

  if [[ "$export_status" == "not_exported" ]]; then
    append_status_result "$state_name" "$state_scope" "$project_name" "missing"
    continue
  fi

  if [[ "$export_status" == "deferred" ]]; then
    append_status_result "$state_name" "$state_scope" "$project_name" "deferred"
    continue
  fi

  if [[ "$export_status" != "exported" ]]; then
    append_status_result "$state_name" "$state_scope" "$project_name" "skipped" "source_state_not_exported"
    continue
  fi

  input_hint="$first_artifact"
  [[ -n "$input_hint" ]] || input_hint="$artifact"
  [[ -n "$input_hint" ]] || {
    append_status_result "$state_name" "$state_scope" "$project_name" "skipped" "missing_artifact_path"
    continue
  }

  input_dir_rel="$(ws_relative_dirname "$input_hint")"
  if [[ "$input_dir_rel" == "." ]]; then
    append_status_result "$state_name" "$state_scope" "$project_name" "skipped" "invalid_artifact_layout"
    continue
  fi

  if [[ "$state_scope" == "project" ]]; then
    if [[ -z "$project_name" ]]; then
      append_status_result "$state_name" "$state_scope" "" "skipped" "missing_project_name"
      continue
    fi

    if ! project_path="$(find_project_path "$project_name")"; then
      append_status_result "$state_name" "$state_scope" "$project_name" "skipped" "missing_project_mapping"
      continue
    fi

    if [[ ! -d "$project_path" ]]; then
      append_status_result "$state_name" "$state_scope" "$project_name" "skipped" "project_path_not_found"
      continue
    fi

    run_import "$state_name" "$state_scope" "$project_name" "$project_path" "$input_dir_rel"
  else
    run_import "$state_name" "$state_scope" "" "" "$input_dir_rel"
  fi
done < <(ws_list_manifest_skill_entries "$MANIFEST_PATH" "$SKILL_NAME")

printf '{"skill":"%s","source_entries":%s,"results":' \
  "$(ws_json_escape "$SKILL_NAME")" \
  "$ENTRY_COUNT"
ws_emit_json_lines_array "$RESULTS_FILE"
echo "}"
