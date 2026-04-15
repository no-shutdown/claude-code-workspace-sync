#!/bin/bash
# detect-projects.sh <jsonl-path>
# 从 Claude Code session jsonl 中提取所有涉及的 git 项目
# 输出 JSON 数组:[{"name","path","remote","branch","head","touched_files"}]

set -euo pipefail

JSONL="${1:-}"
if [[ -z "$JSONL" || ! -f "$JSONL" ]]; then
  echo "[]"
  exit 0
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

FILE_PATHS="$TMP_DIR/file-paths.txt"
DIR_HINTS="$TMP_DIR/dir-hints.txt"
ROOT_DIRS="$TMP_DIR/root-dirs.txt"
ROOT_HITS="$TMP_DIR/root-hits.txt"

: > "$FILE_PATHS"
: > "$DIR_HINTS"
: > "$ROOT_DIRS"
: > "$ROOT_HITS"

extract_json_values() {
  local key="$1"
  grep -oE "\"$key\":\"([^\"\\\\]|\\\\.)*\"" "$JSONL" 2>/dev/null | \
    sed -E "s/^\"$key\":\"//; s/\"$//" | \
    sed 's/\\\\/\\/g; s/\\"/"/g' | \
    sort -u || true
}

# 把 Windows 路径转成 Git Bash 能识别的形式
to_unix_path() {
  local p="$1"
  if [[ "$p" =~ ^[A-Za-z]: ]]; then
    local drive="${p:0:1}"
    local rest="${p:2}"
    local lower_drive
    local gitbash_path
    local wsl_path

    rest="${rest//\\//}"
    lower_drive="$(printf '%s' "$drive" | tr '[:upper:]' '[:lower:]')"
    gitbash_path="/${lower_drive}${rest}"
    wsl_path="/mnt/${lower_drive}${rest}"

    if [[ -e "$gitbash_path" || -d "$(dirname "$gitbash_path")" ]]; then
      printf '%s\n' "$gitbash_path"
    elif [[ -e "$wsl_path" || -d "$(dirname "$wsl_path")" ]]; then
      printf '%s\n' "$wsl_path"
    else
      printf '%s\n' "$gitbash_path"
    fi
  else
    printf '%s\n' "${p//\\//}"
  fi
}

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

find_git_root() {
  local path="$1"
  local dir

  if [[ -d "$path" ]]; then
    dir="$path"
  else
    dir="$(dirname "$path")"
  fi

  while [[ "$dir" != "/" && "$dir" != "." && -n "$dir" ]]; do
    if [[ -d "$dir/.git" ]]; then
      printf '%s\n' "$dir"
      return 0
    fi
    parent="$(dirname "$dir")"
    [[ "$parent" == "$dir" ]] && break
    dir="$parent"
  done

  return 1
}

extract_json_values "file_path" > "$FILE_PATHS"
{
  extract_json_values "cwd"
  extract_json_values "workdir"
} | sort -u > "$DIR_HINTS"

while IFS= read -r raw; do
  [[ -z "$raw" ]] && continue
  unix_path="$(to_unix_path "$raw")"
  root="$(find_git_root "$unix_path" || true)"
  [[ -z "$root" ]] && continue
  printf '%s\n' "$root" >> "$ROOT_DIRS"
  printf '%s\n' "$root" >> "$ROOT_HITS"
done < "$FILE_PATHS"

while IFS= read -r raw; do
  [[ -z "$raw" ]] && continue
  unix_path="$(to_unix_path "$raw")"
  root="$(find_git_root "$unix_path" || true)"
  [[ -z "$root" ]] && continue
  printf '%s\n' "$root" >> "$ROOT_DIRS"
done < "$DIR_HINTS"

if [[ ! -s "$ROOT_DIRS" ]]; then
  echo "[]"
  exit 0
fi

echo -n "["
first=1
while IFS= read -r root; do
  [[ -z "$root" ]] && continue
  [[ $first -eq 0 ]] && echo -n ","
  first=0

  name="$(basename "$root")"
  count="$(grep -Fxc "$root" "$ROOT_HITS" 2>/dev/null || true)"
  [[ -z "$count" ]] && count=0

  (
    cd "$root" 2>/dev/null || exit 0
    remote="$(git config --get remote.origin.url 2>/dev/null || echo "")"
    branch="$(git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null || echo "")"
    head="$(git rev-parse HEAD 2>/dev/null || echo "")"
    printf '{"name":"%s","path":"%s","remote":"%s","branch":"%s","head":"%s","touched_files":%s}' \
      "$(json_escape "$name")" \
      "$(json_escape "$root")" \
      "$(json_escape "$remote")" \
      "$(json_escape "$branch")" \
      "$(json_escape "$head")" \
      "$count"
  )
done < <(sort -u "$ROOT_DIRS")
echo "]"
