#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./workspace-sync-lib.sh
source "$SCRIPT_DIR/workspace-sync-lib.sh"

CONFIG_PATH="$(ws_home_dir)/.claude/skills/workspace-sync/config.json"
LOCAL_PATHS_FILE=""
REMOTE_URL=""
REPO_NAME=""
HEAD_COMMIT=""
WRITE_MAPPING=1
declare -a EXTRA_SCAN_ROOTS=()

usage() {
  cat <<'EOF'
Usage: ./resolve-project-path.sh --remote <remote> [options]

Resolves a local git repository path for a workspace project.

Options:
  --remote <remote>        Required. Project remote URL.
  --repo-name <name>       Optional. Project or repository name hint.
  --head <commit>          Optional. Target commit to probe in candidates.
  --config <path>          Override config.json path.
  --local-paths <path>     Override local-paths.json path.
  --scan-root <path>       Add a scan root. Repeatable.
  --no-write-mapping       Do not persist unique matches back to local-paths.json.
  -h, --help               Show this help.
EOF
}

emit_candidates_json() {
  local file="$1"
  local first=1
  local path branch clean contains_head remote_key

  echo -n "["
  [[ -f "$file" ]] || {
    echo -n "]"
    return 0
  }

  while IFS=$'\t' read -r path branch clean contains_head remote_key; do
    [[ -n "$path" ]] || continue
    [[ $first -eq 0 ]] && echo -n ","
    first=0
    printf '{"path":"%s","branch":"%s","clean":%s,"contains_head":%s,"remote_key":"%s"}' \
      "$(ws_json_escape "$path")" \
      "$(ws_json_escape "$branch")" \
      "$clean" \
      "$contains_head" \
      "$(ws_json_escape "$remote_key")"
  done < "$file"

  echo -n "]"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --remote)
      REMOTE_URL="${2:-}"
      shift 2
      ;;
    --repo-name)
      REPO_NAME="${2:-}"
      shift 2
      ;;
    --head)
      HEAD_COMMIT="${2:-}"
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
    --scan-root)
      EXTRA_SCAN_ROOTS+=("${2:-}")
      shift 2
      ;;
    --no-write-mapping)
      WRITE_MAPPING=0
      shift
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

[[ -n "$REMOTE_URL" ]] || {
  usage >&2
  ws_die "--remote is required"
}

CONFIG_PATH="$(ws_expand_home "$CONFIG_PATH")"
if [[ -z "$LOCAL_PATHS_FILE" ]]; then
  LOCAL_PATHS_FILE="$(ws_get_config_string "$CONFIG_PATH" "local_paths_file")"
fi
[[ -n "$LOCAL_PATHS_FILE" ]] || LOCAL_PATHS_FILE="~/.claude/skills/workspace-sync/local-paths.json"
LOCAL_PATHS_FILE="$(ws_expand_home "$LOCAL_PATHS_FILE")"

REMOTE_KEY="$(ws_normalize_remote "$REMOTE_URL")"
[[ -n "$REMOTE_KEY" ]] || ws_die "Unable to normalize remote: $REMOTE_URL"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

SCAN_ROOTS_FILE="$TMP_DIR/scan-roots.txt"
REPO_ROOTS_FILE="$TMP_DIR/repo-roots.txt"
EXACT_MATCHES_FILE="$TMP_DIR/exact-matches.tsv"
WEAK_MATCHES_FILE="$TMP_DIR/weak-matches.tsv"

: > "$SCAN_ROOTS_FILE"
: > "$REPO_ROOTS_FILE"
: > "$EXACT_MATCHES_FILE"
: > "$WEAK_MATCHES_FILE"

INVALID_MAPPING_REMOVED=false
MAPPED_PATH="$(ws_get_local_mapping_path "$LOCAL_PATHS_FILE" "$REMOTE_KEY" || true)"

if [[ -n "$MAPPED_PATH" ]]; then
  MAPPED_UNIX="$(ws_to_unix_path "$MAPPED_PATH")"
  MAPPED_ROOT="$(ws_resolve_git_root "$MAPPED_UNIX")"
  if [[ -n "$MAPPED_ROOT" ]]; then
    MAPPED_REMOTE="$(git -C "$MAPPED_ROOT" config --get remote.origin.url 2>/dev/null || true)"
    MAPPED_REMOTE_KEY="$(ws_normalize_remote "$MAPPED_REMOTE")"
    if [[ "$MAPPED_REMOTE_KEY" == "$REMOTE_KEY" ]]; then
      STORED_PATH="$(ws_to_host_path "$MAPPED_ROOT")"
      printf '{"status":"exact","path":"%s","source":"local-paths","remote_key":"%s","mapping_written":false,"invalid_mapping_removed":false,"candidates":[]}\n' \
        "$(ws_json_escape "$STORED_PATH")" \
        "$(ws_json_escape "$REMOTE_KEY")"
      exit 0
    fi
  fi

  ws_remove_local_mapping "$LOCAL_PATHS_FILE" "$REMOTE_KEY"
  INVALID_MAPPING_REMOVED=true
fi

while IFS= read -r root; do
  [[ -n "$root" ]] && printf '%s\n' "$root" >> "$SCAN_ROOTS_FILE"
done < <(ws_get_config_array "$CONFIG_PATH" "scan_roots" || true)

for root in "${EXTRA_SCAN_ROOTS[@]}"; do
  [[ -n "$root" ]] && printf '%s\n' "$root" >> "$SCAN_ROOTS_FILE"
done

if [[ -s "$SCAN_ROOTS_FILE" ]]; then
  sort -fu "$SCAN_ROOTS_FILE" -o "$SCAN_ROOTS_FILE"
fi

while IFS= read -r raw_root; do
  [[ -n "$raw_root" ]] || continue
  unix_root="$(ws_to_unix_path "$raw_root")"
  [[ -e "$unix_root" ]] || continue

  top_level="$(ws_resolve_git_root "$unix_root")"
  [[ -n "$top_level" ]] && printf '%s\n' "$top_level" >> "$REPO_ROOTS_FILE"

  if [[ -d "$unix_root" ]]; then
    if [[ -n "$REPO_NAME" ]]; then
      if [[ -d "$unix_root/$REPO_NAME" ]]; then
        repo_root="$(ws_resolve_git_root "$unix_root/$REPO_NAME")"
        [[ -n "$repo_root" ]] && printf '%s\n' "$repo_root" >> "$REPO_ROOTS_FILE"
      fi
    else
      while IFS= read -r git_marker; do
        [[ -n "$git_marker" ]] || continue
        repo_root="$(ws_resolve_git_root "$(dirname "$git_marker")")"
        [[ -n "$repo_root" ]] && printf '%s\n' "$repo_root" >> "$REPO_ROOTS_FILE"
      done < <(find "$unix_root" -maxdepth 3 \( -type d -name .git -o -type f -name .git \) -print 2>/dev/null)
    fi
  fi
done < "$SCAN_ROOTS_FILE"

if [[ -s "$REPO_ROOTS_FILE" ]]; then
  sort -fu "$REPO_ROOTS_FILE" -o "$REPO_ROOTS_FILE"
fi

while IFS= read -r repo_root; do
  [[ -n "$repo_root" ]] || continue
  remote_url="$(git -C "$repo_root" config --get remote.origin.url 2>/dev/null || true)"
  [[ -n "$remote_url" ]] || continue

  candidate_remote_key="$(ws_normalize_remote "$remote_url")"
  stored_repo_root="$(ws_to_host_path "$repo_root")"
  basename_hint="$(basename "$repo_root")"

  if [[ "$candidate_remote_key" == "$REMOTE_KEY" ]]; then
    branch="$(git -C "$repo_root" symbolic-ref --short HEAD 2>/dev/null || git -C "$repo_root" rev-parse --short HEAD 2>/dev/null || true)"
    if git -C "$repo_root" diff --no-ext-diff --quiet --ignore-submodules HEAD -- >/dev/null 2>&1 && \
       git -C "$repo_root" diff --no-ext-diff --cached --quiet --ignore-submodules -- >/dev/null 2>&1; then
      clean=true
    else
      clean=false
    fi

    if [[ -n "$HEAD_COMMIT" ]] && git -C "$repo_root" cat-file -e "${HEAD_COMMIT}^{commit}" >/dev/null 2>&1; then
      contains_head=true
    else
      contains_head=false
    fi

    printf '%s\t%s\t%s\t%s\t%s\n' \
      "$stored_repo_root" "$branch" "$clean" "$contains_head" "$candidate_remote_key" >> "$EXACT_MATCHES_FILE"
  elif [[ -n "$REPO_NAME" && "$basename_hint" == "$REPO_NAME" ]]; then
    branch="$(git -C "$repo_root" symbolic-ref --short HEAD 2>/dev/null || git -C "$repo_root" rev-parse --short HEAD 2>/dev/null || true)"
    if git -C "$repo_root" diff --no-ext-diff --quiet --ignore-submodules HEAD -- >/dev/null 2>&1 && \
       git -C "$repo_root" diff --no-ext-diff --cached --quiet --ignore-submodules -- >/dev/null 2>&1; then
      clean=true
    else
      clean=false
    fi

    if [[ -n "$HEAD_COMMIT" ]] && git -C "$repo_root" cat-file -e "${HEAD_COMMIT}^{commit}" >/dev/null 2>&1; then
      contains_head=true
    else
      contains_head=false
    fi

    printf '%s\t%s\t%s\t%s\t%s\n' \
      "$stored_repo_root" "$branch" "$clean" "$contains_head" "$candidate_remote_key" >> "$WEAK_MATCHES_FILE"
  fi
done < "$REPO_ROOTS_FILE"

exact_count=0
if [[ -f "$EXACT_MATCHES_FILE" ]]; then
  exact_count="$(wc -l < "$EXACT_MATCHES_FILE" | tr -d ' ')"
fi

if [[ "$exact_count" == "1" ]]; then
  IFS=$'\t' read -r matched_path matched_branch matched_clean matched_contains_head matched_remote_key < "$EXACT_MATCHES_FILE"
  if [[ "$WRITE_MAPPING" == "1" ]]; then
    ws_write_local_mapping "$LOCAL_PATHS_FILE" "$REMOTE_KEY" "$matched_path" "${REPO_NAME:-$(basename "$matched_path")}"
    mapping_written=true
  else
    mapping_written=false
  fi

  printf '{"status":"exact","path":"%s","source":"scan","remote_key":"%s","mapping_written":%s,"invalid_mapping_removed":%s,"candidates":[]}\n' \
    "$(ws_json_escape "$matched_path")" \
    "$(ws_json_escape "$REMOTE_KEY")" \
    "$mapping_written" \
    "$INVALID_MAPPING_REMOVED"
  exit 0
fi

if [[ "$exact_count" -gt 1 ]]; then
  printf '{"status":"ambiguous","remote_key":"%s","mapping_written":false,"invalid_mapping_removed":%s,"candidates":' \
    "$(ws_json_escape "$REMOTE_KEY")" \
    "$INVALID_MAPPING_REMOVED"
  emit_candidates_json "$EXACT_MATCHES_FILE"
  echo "}"
  exit 0
fi

printf '{"status":"missing","remote_key":"%s","mapping_written":false,"invalid_mapping_removed":%s,"candidates":' \
  "$(ws_json_escape "$REMOTE_KEY")" \
  "$INVALID_MAPPING_REMOVED"
emit_candidates_json "$WEAK_MATCHES_FILE"
echo "}"
