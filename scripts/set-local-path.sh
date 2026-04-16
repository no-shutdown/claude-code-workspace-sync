#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./workspace-sync-lib.sh
source "$SCRIPT_DIR/workspace-sync-lib.sh"

CONFIG_PATH="$(ws_home_dir)/.claude/skills/workspace-sync/config.json"
LOCAL_PATHS_FILE=""
REMOTE_URL=""
LOCAL_PATH=""
REPO_NAME=""

usage() {
  cat <<'EOF'
Usage: ./set-local-path.sh --remote <remote> --path <local-path> [options]

Persists a confirmed local repository mapping into local-paths.json.

Options:
  --remote <remote>      Required. Project remote URL.
  --path <local-path>    Required. Local repository path or subdirectory.
  --repo-name <name>     Optional. Override stored repository name.
  --config <path>        Override config.json path.
  --local-paths <path>   Override local-paths.json path.
  -h, --help             Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --remote)
      REMOTE_URL="${2:-}"
      shift 2
      ;;
    --path)
      LOCAL_PATH="${2:-}"
      shift 2
      ;;
    --repo-name)
      REPO_NAME="${2:-}"
      shift 2
      ;;
    --config)
      CONFIG_PATH="${2:-}"
      shift 2
      ;;
    --local-paths)
      LOCAL_PATHS_FILE="${2:-}"
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

[[ -n "$REMOTE_URL" && -n "$LOCAL_PATH" ]] || {
  usage >&2
  ws_die "--remote and --path are required"
}

CONFIG_PATH="$(ws_expand_home "$CONFIG_PATH")"
if [[ -z "$LOCAL_PATHS_FILE" ]]; then
  LOCAL_PATHS_FILE="$(ws_get_config_string "$CONFIG_PATH" "local_paths_file")"
fi
[[ -n "$LOCAL_PATHS_FILE" ]] || LOCAL_PATHS_FILE="~/.claude/skills/workspace-sync/local-paths.json"
LOCAL_PATHS_FILE="$(ws_expand_home "$LOCAL_PATHS_FILE")"

REMOTE_KEY="$(ws_normalize_remote "$REMOTE_URL")"
[[ -n "$REMOTE_KEY" ]] || ws_die "Unable to normalize remote: $REMOTE_URL"

LOCAL_UNIX_PATH="$(ws_to_unix_path "$LOCAL_PATH")"
[[ -e "$LOCAL_UNIX_PATH" ]] || ws_die "Local path does not exist: $LOCAL_PATH"

REPO_ROOT="$(ws_resolve_git_root "$LOCAL_UNIX_PATH")"
[[ -n "$REPO_ROOT" ]] || ws_die "Local path is not inside a git repository: $LOCAL_PATH"

ACTUAL_REMOTE="$(git -C "$REPO_ROOT" config --get remote.origin.url 2>/dev/null || true)"
[[ -n "$ACTUAL_REMOTE" ]] || ws_die "Repository has no remote.origin.url: $REPO_ROOT"

ACTUAL_REMOTE_KEY="$(ws_normalize_remote "$ACTUAL_REMOTE")"
[[ "$ACTUAL_REMOTE_KEY" == "$REMOTE_KEY" ]] || {
  ws_die "Remote mismatch. Expected $REMOTE_KEY, got $ACTUAL_REMOTE_KEY"
}

STORED_PATH="$(ws_to_host_path "$REPO_ROOT")"
STORED_NAME="${REPO_NAME:-$(basename "$REPO_ROOT")}"
ws_write_local_mapping "$LOCAL_PATHS_FILE" "$REMOTE_KEY" "$STORED_PATH" "$STORED_NAME"

printf '{"status":"written","remote_key":"%s","path":"%s","repo_name":"%s","local_paths_file":"%s"}\n' \
  "$(ws_json_escape "$REMOTE_KEY")" \
  "$(ws_json_escape "$STORED_PATH")" \
  "$(ws_json_escape "$STORED_NAME")" \
  "$(ws_json_escape "$LOCAL_PATHS_FILE")"
