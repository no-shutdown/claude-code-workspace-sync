#!/usr/bin/env bash

ws_die() {
  echo "$*" >&2
  exit 1
}

ws_command_exists() {
  command -v "$1" >/dev/null 2>&1
}

ws_home_dir() {
  local candidate=""

  if [[ -n "${WS_HOME_OVERRIDE:-}" ]]; then
    printf '%s\n' "$(ws_to_unix_path "$WS_HOME_OVERRIDE")"
    return 0
  fi

  if [[ -n "${USERPROFILE:-}" ]]; then
    candidate="$(ws_to_unix_path "$USERPROFILE")"
    if [[ -d "$candidate/.claude" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  fi

  if [[ -n "${HOME:-}" && -d "$HOME/.claude" ]]; then
    printf '%s\n' "$HOME"
    return 0
  fi

  for candidate in /c/Users/* /mnt/c/Users/*; do
    [[ -d "$candidate/.claude" ]] || continue
    printf '%s\n' "$candidate"
    return 0
  done

  if [[ -n "${USERPROFILE:-}" ]]; then
    printf '%s\n' "$(ws_to_unix_path "$USERPROFILE")"
    return 0
  fi

  printf '%s\n' "${HOME:-}"
}

ws_expand_home() {
  local path="${1:-}"
  local home_dir

  home_dir="$(ws_home_dir)"
  path="${path%$'\r'}"
  path="${path#\"}"
  path="${path%\"}"
  case "$path" in
    "~")
      printf '%s\n' "$home_dir"
      ;;
    "~/"*)
      printf '%s\n' "$home_dir/${path:2}"
      ;;
    *)
      printf '%s\n' "$path"
      ;;
  esac
}

ws_to_unix_path() {
  local path="${1:-}"
  if [[ "$path" =~ ^[A-Za-z]: ]]; then
    local drive="${path:0:1}"
    local rest="${path:2}"
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
    printf '%s\n' "${path//\\//}"
  fi
}

ws_to_host_path() {
  local path="${1:-}"
  if ws_command_exists cygpath; then
    cygpath -w "$path"
  else
    printf '%s\n' "$path"
  fi
}

ws_json_escape() {
  printf '%s' "${1:-}" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

ws_resolve_git_root() {
  local path="${1:-}"
  git -C "$path" rev-parse --show-toplevel 2>/dev/null || true
}

ws_normalize_remote() {
  local remote="${1:-}"
  local host
  local rest

  [[ -n "$remote" ]] || return 0

  remote="${remote#ssh://}"
  remote="${remote#https://}"
  remote="${remote#http://}"
  remote="${remote#git://}"
  remote="${remote#*@}"
  remote="${remote#//}"
  remote="${remote%.git}"

  if [[ "$remote" =~ ^[^/]+:.+$ ]]; then
    remote="${remote/:/\/}"
  fi

  host="${remote%%/*}"
  rest=""
  if [[ "$remote" == */* ]]; then
    rest="${remote#*/}"
  fi

  host="$(printf '%s' "$host" | tr '[:upper:]' '[:lower:]')"
  if [[ -n "$rest" ]]; then
    printf '%s/%s\n' "$host" "$rest"
  else
    printf '%s\n' "$host"
  fi
}

ws_json_with_python() {
  local script="$1"
  shift
  python3 - "$@" <<PY
$script
PY
}

ws_json_with_node() {
  local script="$1"
  shift
  node - "$@" <<NODE
$script
NODE
}

ws_get_config_string() {
  local file="$1"
  local key="$2"

  [[ -f "$file" ]] || return 0

  if ws_command_exists python3; then
    ws_json_with_python '
import json
import sys
from pathlib import Path

path = Path(sys.argv[1]).expanduser()
key = sys.argv[2]
with path.open(encoding="utf-8") as handle:
    data = json.load(handle)
value = data.get(key, "")
if isinstance(value, str):
    print(value)
elif value is None:
    print("")
else:
    print("")
' "$file" "$key"
  elif ws_command_exists node; then
    ws_json_with_node '
const fs = require("fs");
const path = require("path");

const file = process.argv[2].replace(/^~(?=$|[\\/])/, process.env.HOME || "");
const key = process.argv[3];
const data = JSON.parse(fs.readFileSync(path.resolve(file), "utf8"));
const value = data[key];
if (typeof value === "string") {
  console.log(value);
} else {
  console.log("");
}
' "$file" "$key"
  fi
}

ws_get_config_array() {
  local file="$1"
  local key="$2"

  [[ -f "$file" ]] || return 0

  if ws_command_exists python3; then
    ws_json_with_python '
import json
import sys
from pathlib import Path

path = Path(sys.argv[1]).expanduser()
key = sys.argv[2]
with path.open(encoding="utf-8") as handle:
    data = json.load(handle)
value = data.get(key) or []
if isinstance(value, list):
    for item in value:
        if isinstance(item, str):
            print(item)
' "$file" "$key"
  elif ws_command_exists node; then
    ws_json_with_node '
const fs = require("fs");
const path = require("path");

const file = process.argv[2].replace(/^~(?=$|[\\/])/, process.env.HOME || "");
const key = process.argv[3];
const data = JSON.parse(fs.readFileSync(path.resolve(file), "utf8"));
const value = Array.isArray(data[key]) ? data[key] : [];
for (const item of value) {
  if (typeof item === "string") {
    console.log(item);
  }
}
' "$file" "$key"
  fi
}

ws_get_local_mapping_path() {
  local file="$1"
  local remote_key="$2"

  [[ -f "$file" ]] || return 0

  if ws_command_exists python3; then
    ws_json_with_python '
import json
import sys
from pathlib import Path

path = Path(sys.argv[1]).expanduser()
remote_key = sys.argv[2]
with path.open(encoding="utf-8") as handle:
    data = json.load(handle)
entry = (data.get("projects") or {}).get(remote_key) or {}
value = entry.get("path", "")
if isinstance(value, str):
    print(value)
' "$file" "$remote_key"
  elif ws_command_exists node; then
    ws_json_with_node '
const fs = require("fs");
const path = require("path");

const file = process.argv[2].replace(/^~(?=$|[\\/])/, process.env.HOME || "");
const remoteKey = process.argv[3];
const data = JSON.parse(fs.readFileSync(path.resolve(file), "utf8"));
const entry = ((data.projects || {})[remoteKey]) || {};
console.log(typeof entry.path === "string" ? entry.path : "");
' "$file" "$remote_key"
  fi
}

ws_write_local_mapping() {
  local file="$1"
  local remote_key="$2"
  local path="$3"
  local repo_name="$4"

  if ws_command_exists python3; then
    ws_json_with_python '
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

path_obj = Path(sys.argv[1]).expanduser()
remote_key = sys.argv[2]
repo_path = sys.argv[3]
repo_name = sys.argv[4]

path_obj.parent.mkdir(parents=True, exist_ok=True)
if path_obj.exists():
    with path_obj.open(encoding="utf-8") as handle:
        data = json.load(handle)
else:
    data = {}

projects = data.setdefault("projects", {})
data["version"] = 1
projects[remote_key] = {
    "path": repo_path,
    "repo_name": repo_name,
    "last_verified_at": datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")
}

with path_obj.open("w", encoding="utf-8", newline="\n") as handle:
    json.dump(data, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
' "$file" "$remote_key" "$path" "$repo_name"
  elif ws_command_exists node; then
    ws_json_with_node '
const fs = require("fs");
const path = require("path");

const file = process.argv[2].replace(/^~(?=$|[\\/])/, process.env.HOME || "");
const remoteKey = process.argv[3];
const repoPath = process.argv[4];
const repoName = process.argv[5];
const resolved = path.resolve(file);
fs.mkdirSync(path.dirname(resolved), { recursive: true });

let data = {};
if (fs.existsSync(resolved)) {
  data = JSON.parse(fs.readFileSync(resolved, "utf8"));
}

data.version = 1;
data.projects = data.projects || {};
data.projects[remoteKey] = {
  path: repoPath,
  repo_name: repoName,
  last_verified_at: new Date().toISOString()
};

fs.writeFileSync(resolved, JSON.stringify(data, null, 2) + "\n", "utf8");
' "$file" "$remote_key" "$path" "$repo_name"
  else
    ws_die "python3 or node is required to update local-paths.json"
  fi
}

ws_remove_local_mapping() {
  local file="$1"
  local remote_key="$2"

  [[ -f "$file" ]] || return 0

  if ws_command_exists python3; then
    ws_json_with_python '
import json
import sys
from pathlib import Path

path_obj = Path(sys.argv[1]).expanduser()
remote_key = sys.argv[2]
with path_obj.open(encoding="utf-8") as handle:
    data = json.load(handle)

projects = data.get("projects") or {}
projects.pop(remote_key, None)
data["projects"] = projects

with path_obj.open("w", encoding="utf-8", newline="\n") as handle:
    json.dump(data, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
' "$file" "$remote_key"
  elif ws_command_exists node; then
    ws_json_with_node '
const fs = require("fs");
const path = require("path");

const file = process.argv[2].replace(/^~(?=$|[\\/])/, process.env.HOME || "");
const remoteKey = process.argv[3];
const resolved = path.resolve(file);
const data = JSON.parse(fs.readFileSync(resolved, "utf8"));
data.projects = data.projects || {};
delete data.projects[remoteKey];
fs.writeFileSync(resolved, JSON.stringify(data, null, 2) + "\n", "utf8");
' "$file" "$remote_key"
  else
    ws_die "python3 or node is required to update local-paths.json"
  fi
}
