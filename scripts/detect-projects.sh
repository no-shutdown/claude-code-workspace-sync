#!/bin/bash
# detect-projects.sh <jsonl-path>
# 从 Claude Code session jsonl 中提取所有涉及的 git 项目
# 输出 JSON 数组:[{"name","path","remote","branch","head","changed_files_count"}]

set -e

JSONL="$1"
if [[ ! -f "$JSONL" ]]; then
  echo "[]"
  exit 0
fi

# 把 Windows 路径转成 Git Bash 能识别的形式
to_unix_path() {
  local p="$1"
  # C:\Users\foo -> /c/Users/foo
  if [[ "$p" =~ ^[A-Za-z]: ]]; then
    local drive="${p:0:1}"
    local rest="${p:2}"
    rest="${rest//\\//}"
    echo "/${drive,,}${rest}"
  else
    echo "${p//\\//}"
  fi
}

# 提取所有 file_path 值(Read/Edit/Write 工具),以及 Bash 工具的 cwd
# jsonl 里路径被 JSON 转义:C:\\Users\\foo  -> 原始值 C:\Users\foo
raw_paths=$(grep -oE '"file_path":"([^"\\]|\\.)*"' "$JSONL" 2>/dev/null | \
  sed -E 's/^"file_path":"//; s/"$//' | \
  sed 's/\\\\/\\/g; s/\\"/"/g' | \
  sort -u || true)

# 遍历路径,找到每个文件对应的 git root
declare -A git_roots         # key: unix_path, value: original(windows)_path
declare -A git_roots_count   # key: unix_path, value: file count

while IFS= read -r raw; do
  [[ -z "$raw" ]] && continue
  unix=$(to_unix_path "$raw")
  # 从文件所在目录向上找 .git
  dir="$(dirname "$unix")"
  while [[ "$dir" != "/" && "$dir" != "." && -n "$dir" ]]; do
    if [[ -d "$dir/.git" ]]; then
      git_roots["$dir"]="$dir"
      git_roots_count["$dir"]=$(( ${git_roots_count["$dir"]:-0} + 1 ))
      break
    fi
    parent="$(dirname "$dir")"
    [[ "$parent" == "$dir" ]] && break
    dir="$parent"
  done
done <<< "$raw_paths"

# 输出 JSON 数组
echo -n "["
first=1
for root in "${!git_roots[@]}"; do
  [[ $first -eq 0 ]] && echo -n ","
  first=0
  name="$(basename "$root")"
  count="${git_roots_count["$root"]}"
  (
    cd "$root" 2>/dev/null || exit 0
    remote=$(git config --get remote.origin.url 2>/dev/null || echo "")
    branch=$(git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null || echo "")
    head=$(git rev-parse HEAD 2>/dev/null || echo "")
    printf '{"name":"%s","path":"%s","remote":"%s","branch":"%s","head":"%s","touched_files":%s}' \
      "$name" "$root" "$remote" "$branch" "$head" "$count"
  )
done
echo "]"
