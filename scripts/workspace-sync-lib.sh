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

ws_trim_quotes() {
  local value="${1:-}"
  value="${value%$'\r'}"
  value="${value#\"}"
  value="${value%\"}"
  value="${value#\'}"
  value="${value%\'}"
  printf '%s\n' "$value"
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

ws_get_json_string() {
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
if value is None:
    print("")
else:
    print(str(value))
' "$file" "$key"
  elif ws_command_exists node; then
    ws_json_with_node '
const fs = require("fs");
const path = require("path");

const file = process.argv[2].replace(/^~(?=$|[\\/])/, process.env.HOME || "");
const key = process.argv[3];
const data = JSON.parse(fs.readFileSync(path.resolve(file), "utf8"));
const value = data[key];
console.log(value == null ? "" : String(value));
' "$file" "$key"
  fi
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

ws_get_contract_state_string() {
  local file="$1"
  local state_name="$2"
  local key="$3"

  [[ -f "$file" ]] || return 0

  if ws_command_exists python3; then
    ws_json_with_python '
import json
import sys
from pathlib import Path

path = Path(sys.argv[1]).expanduser()
state_name = sys.argv[2]
key = sys.argv[3]
with path.open(encoding="utf-8") as handle:
    data = json.load(handle)
states = data.get("states") or []
for state in states:
    if isinstance(state, dict) and state.get("name") == state_name:
        value = state.get(key, "")
        print("" if value is None else str(value))
        break
else:
    print("")
' "$file" "$state_name" "$key"
  elif ws_command_exists node; then
    ws_json_with_node '
const fs = require("fs");
const path = require("path");

const file = process.argv[2].replace(/^~(?=$|[\\/])/, process.env.HOME || "");
const stateName = process.argv[3];
const key = process.argv[4];
const data = JSON.parse(fs.readFileSync(path.resolve(file), "utf8"));
const states = Array.isArray(data.states) ? data.states : [];
const state = states.find((item) => item && item.name === stateName) || {};
const value = state[key];
console.log(value == null ? "" : String(value));
' "$file" "$state_name" "$key"
  fi
}

ws_list_contract_states() {
  local file="$1"
  local portability_filter="${2:-}"

  [[ -f "$file" ]] || return 0

  if ws_command_exists python3; then
    ws_json_with_python '
import json
import sys
from pathlib import Path

path = Path(sys.argv[1]).expanduser()
portability_filter = sys.argv[2]
with path.open(encoding="utf-8") as handle:
    data = json.load(handle)
states = data.get("states") or []
for state in states:
    if not isinstance(state, dict):
        continue
    name = state.get("name")
    scope = state.get("scope", "")
    portability = state.get("portability", "")
    if not isinstance(name, str) or not name:
        continue
    if portability_filter and portability != portability_filter:
        continue
    print(f"{name}\t{scope}\t{portability}")
' "$file" "$portability_filter"
  elif ws_command_exists node; then
    ws_json_with_node '
const fs = require("fs");
const path = require("path");

const file = process.argv[2].replace(/^~(?=$|[\\/])/, process.env.HOME || "");
const portabilityFilter = process.argv[3];
const data = JSON.parse(fs.readFileSync(path.resolve(file), "utf8"));
const states = Array.isArray(data.states) ? data.states : [];
for (const state of states) {
  if (!state || typeof state.name !== "string" || !state.name) {
    continue;
  }
  const portability = typeof state.portability === "string" ? state.portability : "";
  if (portabilityFilter && portability !== portabilityFilter) {
    continue;
  }
  const scope = typeof state.scope === "string" ? state.scope : "";
  console.log(`${state.name}\t${scope}\t${portability}`);
}
' "$file" "$portability_filter"
  fi
}

ws_list_manifest_skill_entries() {
  local file="$1"
  local skill_name="$2"

  [[ -f "$file" ]] || return 0

  if ws_command_exists python3; then
    ws_json_with_python '
import json
import sys
from pathlib import Path

path = Path(sys.argv[1]).expanduser()
skill_name = sys.argv[2]
with path.open(encoding="utf-8") as handle:
    data = json.load(handle)
entries = data.get("skill_states") or []
for entry in entries:
    if not isinstance(entry, dict):
        continue
    if entry.get("skill") != skill_name:
        continue
    state = entry.get("state", "") or ""
    scope = entry.get("scope", "") or ""
    portability = entry.get("portability", "") or ""
    project = entry.get("project", "") or ""
    status = entry.get("status", "") or ""
    artifact = entry.get("artifact", "") or ""
    artifacts = entry.get("artifacts") or []
    first_artifact = ""
    if isinstance(artifacts, list):
        for item in artifacts:
            if isinstance(item, str) and item:
                first_artifact = item
                break
    print(f"{state}\t{scope}\t{portability}\t{project}\t{status}\t{artifact}\t{first_artifact}")
' "$file" "$skill_name"
  elif ws_command_exists node; then
    ws_json_with_node '
const fs = require("fs");
const path = require("path");

const file = process.argv[2].replace(/^~(?=$|[\\/])/, process.env.HOME || "");
const skillName = process.argv[3];
const data = JSON.parse(fs.readFileSync(path.resolve(file), "utf8"));
const entries = Array.isArray(data.skill_states) ? data.skill_states : [];
for (const entry of entries) {
  if (!entry || entry.skill !== skillName) {
    continue;
  }
  const artifacts = Array.isArray(entry.artifacts) ? entry.artifacts : [];
  const firstArtifact = artifacts.find((item) => typeof item === "string" && item) || "";
  console.log([
    entry.state || "",
    entry.scope || "",
    entry.portability || "",
    entry.project || "",
    entry.status || "",
    entry.artifact || "",
    firstArtifact
  ].join("\t"));
}
' "$file" "$skill_name"
  fi
}

ws_relative_dirname() {
  local path="${1:-}"

  case "$path" in
    */*)
      printf '%s\n' "${path%/*}"
      ;;
    *)
      printf '.\n'
      ;;
  esac
}

ws_get_manifest_artifacts() {
  local file="$1"

  [[ -f "$file" ]] || return 0

  if ws_command_exists python3; then
    ws_json_with_python '
import json
import sys
from pathlib import Path

path = Path(sys.argv[1]).expanduser()
with path.open(encoding="utf-8") as handle:
    data = json.load(handle)
value = data.get("artifacts") or []
if isinstance(value, list):
    for item in value:
        if isinstance(item, str):
            print(item)
' "$file"
  elif ws_command_exists node; then
    ws_json_with_node '
const fs = require("fs");
const path = require("path");

const file = process.argv[2].replace(/^~(?=$|[\\/])/, process.env.HOME || "");
const data = JSON.parse(fs.readFileSync(path.resolve(file), "utf8"));
const value = Array.isArray(data.artifacts) ? data.artifacts : [];
for (const item of value) {
  if (typeof item === "string") {
    console.log(item);
  }
}
' "$file"
  fi
}

ws_resolve_command_spec() {
  local base_dir="$1"
  local command_spec

  command_spec="$(ws_trim_quotes "${2:-}")"
  [[ -n "$command_spec" ]] || return 0

  if [[ "$command_spec" =~ [[:space:]] ]]; then
    ws_die "Command spec must be a single executable path or command name: $command_spec"
  fi

  if [[ "$command_spec" =~ ^[A-Za-z]: || "$command_spec" == /* ]]; then
    printf '%s\n' "$(ws_to_unix_path "$command_spec")"
  elif [[ "$command_spec" == */* || "$command_spec" == ./* || "$command_spec" == ../* ]]; then
    printf '%s\n' "$base_dir/$command_spec"
  else
    printf '%s\n' "$command_spec"
  fi
}

ws_run_command_spec() {
  local base_dir="$1"
  local command_spec="$2"
  shift 2

  local resolved
  resolved="$(ws_resolve_command_spec "$base_dir" "$command_spec")"
  [[ -n "$resolved" ]] || ws_die "Empty command spec"

  if [[ "$resolved" == */* || "$resolved" =~ ^[A-Za-z]: || "$resolved" == /* ]]; then
    [[ -f "$resolved" ]] || ws_die "Command not found: $resolved"
    if [[ -x "$resolved" ]]; then
      "$resolved" "$@"
    else
      bash "$resolved" "$@"
    fi
  else
    ws_command_exists "$resolved" || ws_die "Command not found in PATH: $resolved"
    "$resolved" "$@"
  fi
}

ws_list_relative_files() {
  local dir="$1"

  [[ -d "$dir" ]] || return 0

  find "$dir" -type f -print 2>/dev/null | while IFS= read -r file; do
    file="${file#"$dir"/}"
    printf '%s\n' "$file"
  done | sort
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

# 将 JSONL 文件中每行作为原始 JSON 值输出为数组(元素已经是 JSON 对象/值)
ws_emit_json_lines_array() {
  local file="$1"
  local first=1
  local line

  printf '['
  if [[ -f "$file" ]]; then
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      [[ $first -eq 0 ]] && printf ','
      first=0
      printf '%s' "$line"
    done < "$file"
  fi
  printf ']'
}

# 将文本文件中每行作为 JSON 字符串输出为数组(自动转义)
ws_emit_json_string_array() {
  local file="$1"
  local first=1
  local item

  printf '['
  if [[ -f "$file" ]]; then
    while IFS= read -r item; do
      [[ -n "$item" ]] || continue
      [[ $first -eq 0 ]] && printf ','
      first=0
      printf '"%s"' "$(ws_json_escape "$item")"
    done < "$file"
  fi
  printf ']'
}

# 读取 contract 中指定 state 的 sync_paths 列表，每行一条
ws_get_contract_state_paths() {
  local file="$1"
  local state_name="$2"

  [[ -f "$file" ]] || return 0

  if ws_command_exists python3; then
    ws_json_with_python '
import json
import sys
from pathlib import Path

path = Path(sys.argv[1]).expanduser()
state_name = sys.argv[2]
with path.open(encoding="utf-8") as handle:
    data = json.load(handle)
states = data.get("states") or []
for state in states:
    if isinstance(state, dict) and state.get("name") == state_name:
        paths = state.get("sync_paths") or []
        if isinstance(paths, list):
            for item in paths:
                if isinstance(item, str) and item:
                    print(item)
        break
' "$file" "$state_name"
  elif ws_command_exists node; then
    ws_json_with_node '
const fs = require("fs");
const path = require("path");

const file = process.argv[2].replace(/^~(?=$|[\\/])/, process.env.HOME || "");
const stateName = process.argv[3];
const data = JSON.parse(fs.readFileSync(path.resolve(file), "utf8"));
const states = Array.isArray(data.states) ? data.states : [];
const state = states.find((s) => s && s.name === stateName) || {};
const paths = Array.isArray(state.sync_paths) ? state.sync_paths : [];
for (const item of paths) {
  if (typeof item === "string" && item) {
    console.log(item);
  }
}
' "$file" "$state_name"
  fi
}

# 检查 contract 中 state name 是否有重复；重复名称打印到 stdout，无重复则静默
ws_validate_contract_state_names() {
  local file="$1"

  [[ -f "$file" ]] || return 0

  if ws_command_exists python3; then
    ws_json_with_python '
import json
import sys
from pathlib import Path

path = Path(sys.argv[1]).expanduser()
with path.open(encoding="utf-8") as handle:
    data = json.load(handle)
states = data.get("states") or []
seen = set()
for state in states:
    if not isinstance(state, dict):
        continue
    name = state.get("name")
    if not isinstance(name, str) or not name:
        continue
    if name in seen:
        print(name)
    seen.add(name)
' "$file"
  elif ws_command_exists node; then
    ws_json_with_node '
const fs = require("fs");
const path = require("path");

const file = process.argv[2].replace(/^~(?=$|[\\/])/, process.env.HOME || "");
const data = JSON.parse(fs.readFileSync(path.resolve(file), "utf8"));
const states = Array.isArray(data.states) ? data.states : [];
const seen = new Set();
for (const state of states) {
  if (!state || typeof state.name !== "string" || !state.name) continue;
  if (seen.has(state.name)) {
    console.log(state.name);
  }
  seen.add(state.name);
}
' "$file"
  fi
}
