---
name: workspace-sync
description: 跨设备同步 Claude Code 工作空间(对话摘要 + 涉及的 git 项目状态)。支持 GitLab 或 MinIO 两种存储后端,首次使用会引导用户选择和配置。当用户输入 /workspace-sync、`workspace-sync push/pull/list`、或明确提到把当前对话/工作同步到云端、从云端恢复工作空间、跨设备继续之前工作时使用。
---

# Workspace Sync

## 概述

把当前对话的工作状态(对话摘要 + 涉及的所有 git 项目的 branch/upstream/HEAD)打包上传到云端。另一台设备 pull 下来后,Claude 读摘要就能恢复上下文;代码侧只恢复到已经提交并已推送的状态,不负责搬运本地未推/未提交改动。

**自动适配三种场景**(不需要区分模式):
- 纯讨论:projects 为空,只存摘要和对话
- 单项目:一次对话只改了一个 git 仓库
- 多项目:一次对话修改了前端+后台等多个仓库

## 存储后端

支持两种,二选一(在首次使用时配置):

| 后端 | 用户需要准备的前置条件 |
|------|------------------------|
| **GitLab** | 一个**已存在**的空仓库,以及有 read/write 权限的 Personal Access Token |
| **MinIO** | 一个**已存在**的 bucket,有读写权限的 access_key/secret_key,以及 `mc` 客户端已安装 |

**skill 不会自动创建仓库或 bucket**,如果目标不存在会直接报错并提示用户先去创建。

## 何时触发

用户说以下内容时进入本 skill:
- `/workspace-sync push [<name>]`
- `/workspace-sync pull <name>`
- `/workspace-sync list`
- `/workspace-sync clean <name>`
- `/workspace-sync clean --all`
- "把这次对话同步到云端"、"push 到工作空间"
- "从 XX 工作空间继续"、"pull workspace XX"

## 配置文件

`~/.claude/skills/workspace-sync/config.json`:

```json
{
  "backend": "gitlab" | "minio" | null,
  "gitlab": {
    "host": "your.gitlab.com",
    "token": "glpat-xxx",
    "project_path": "namespace/repo-name",
    "branch": "main"
  },
  "minio": {
    "endpoint": "https://minio.example.com",
    "access_key": "xxx",
    "secret_key": "xxx",
    "bucket": "claude-workspaces",
    "prefix": "workspaces/",
    "mc_alias": "claude-workspace-sync"
  },
  "cache_dir": "~/.claude/workspace-cache",
  "local_paths_file": "~/.claude/skills/workspace-sync/local-paths.json"
}
```

`backend` 为 `null` 或字段不完整时,必须先跑首次配置流程。

## 工作空间目录结构(两种后端共用)

```
<workspace-name>/
├── manifest.json          (元数据 + 项目列表)
├── summary.md             (对话摘要,按项目分段)
├── conversation.jsonl     (完整对话备份)
└── projects/
    └── <project-name>/
        └── meta.json      (remote/upstream/branch/head)
```

如果某些 skill 需要跨设备恢复工作区级状态,额外保存:

```text
<workspace-name>/
└── skill-states/
    └── <skill-name>/
        ├── manifest.json
        └── <artifact>.tgz
```

这一层的边界必须明确:
- `workspace-sync` 不猜测 skill 内部目录结构
- `workspace-sync` 不理解 skill 内部格式
- `workspace-sync` 只负责调用 skill 的 export/import、保存产物、记录结果
- 哪些内容可导出/可恢复,由各 skill 通过统一契约自己定义

## Skill State 标准接口

每个要接入 `workspace-sync` 的 skill,如果需要同步自身状态,必须在自己的 skill 根目录提供:

```text
workspace-sync.contract.json
```

格式:

```json
{
  "contract_version": 1,
  "skill": "sdd",
  "states": [
    {
      "name": "project-state",
      "scope": "project",
      "portability": "portable",
      "export_command": "./scripts/export-workspace-state.sh",
      "import_command": "./scripts/import-workspace-state.sh"
    },
    {
      "name": "global-cache",
      "scope": "global",
      "portability": "nonportable"
    }
  ]
}
```

字段约束:
- `scope`:
  - `project`: 绑定到某个项目工作区
  - `global`: 绑定到当前设备上的全局 skill 状态
- `portability`:
  - `portable`: 可跨设备导出/导入
  - `nonportable`: 不允许跨设备同步
- `export_command` / `import_command`:
  - 只有 `portable` 状态才允许提供
  - 由 skill 自己负责实现

标准规则:
- `workspace-sync` 只处理声明为 `portable` 的状态
- `project` 和 `global` 都允许存在,但都必须显式声明 portability
- `nonportable` 状态一律不得导出
- `workspace-sync` 不为任何 skill 实现专用执行器
- 其他 skill 只要遵守该接口,就可以被 `workspace-sync` 编排

## manifest.json 格式

```json
{
  "name": "存量名单导入重构",
  "version": 3,
  "previous_version": 2,
  "conversation_id": "71fc3842-...",
  "source_device": "company-pc",
  "source_cwd": "D:\\A-ukon-work\\shanks-manage",
  "created_at": "2026-04-15T18:00:00+08:00",
  "projects": [
    {
      "name": "shanks-manage",
      "remote": "git@your.gitlab.com:namespace/your-project.git",
      "upstream": "origin/feature/import",
      "branch": "feature/import",
      "head": "abc123"
    }
  ],
  "skill_states": [
    {
      "skill": "sdd",
      "state": "project-state",
      "scope": "project",
      "portability": "portable",
      "project": "shanks-manage",
      "status": "exported",
      "artifact": "skill-states/sdd/shanks-manage-project-state.tgz"
    }
  ]
}
```

`skill_states` 可以为空或省略。启用 skill 状态同步后:
- `status=exported`: 该 skill 成功导出了可移植的 workspace state
- `status=skipped`: 检测到该 skill,但当前环境无法导出
- `status=not_exported`: 当前 workspace 没有启用该 skill 的状态同步
- `status=deferred`: 导出产物存在,但当前环境暂不导入

版本字段:
- `version`: 当前 workspace 的远端版本号,每次 push 递增
- `previous_version`: 本次 push 之前看到的远端版本
- `workspace-sync` 必须用这两个字段做乐观并发校验

这里记录的是**导出/恢复结果**,不是 skill 的内部数据结构。

## summary.md 格式

```markdown
# 工作空间:<name>

## 整体目标
<1-2 句描述核心目标>

## 讨论脉络
<纯讨论场景:达成的共识、待议问题、关键决策;项目场景可省略>

## 项目:shanks-manage
- **分支**:feature/import
- **已完成**:...
- **进行中**:(卡在哪)
- **下一步**:<必须具体>
- **关键文件**:path:line

## 项目:shanks-admin
...
```

---

# 通用执行入口

## Step 0: 加载配置 & 检查完整性

```bash
CONFIG="$HOME/.claude/skills/workspace-sync/config.json"
read_json() { grep -oE "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$CONFIG" | sed -E 's/^"[^"]*"[[:space:]]*:[[:space:]]*"//; s/"$//'; }
read_json_nested() {
  # read_json_nested gitlab token → 读嵌套字段
  python3 -c "import json,sys; c=json.load(open('$CONFIG')); print((c.get('$1') or {}).get('$2','') or '')" 2>/dev/null \
    || node -e "const c=require('$CONFIG'); console.log((c.$1||{}).$2||'')" 2>/dev/null
}

BACKEND=$(python3 -c "import json; print(json.load(open('$CONFIG')).get('backend') or '')" 2>/dev/null)

validate_ws_name() {
  local name="$1"
  [[ -n "$name" ]] || return 1
  [[ "$name" != "." && "$name" != ".." ]] || return 1
  [[ "$name" != *[[:space:]]* ]] || return 1
  [[ "$name" != *[[:cntrl:]]* ]] || return 1
  [[ "$name" != *"/"* ]] || return 1
  [[ "$name" != *"\\"* ]] || return 1
  [[ "$name" != *"<"* ]] || return 1
  [[ "$name" != *">"* ]] || return 1
  [[ "$name" != *":"* ]] || return 1
  [[ "$name" != *"\""* ]] || return 1
  [[ "$name" != *"|"* ]] || return 1
  [[ "$name" != *[?]* ]] || return 1
  [[ "$name" != *[*]* ]] || return 1
}
```

如果 `BACKEND` 为空或对应 backend 的必填字段为空 → 进入 **首次配置流程**(见下方)。

配置完整后按 backend 分派到对应实现。

---

# 首次配置流程(Claude 主导的交互)

**触发条件**:config.json 中 `backend=null` 或对应 backend 的必填字段缺失。

**Claude 必须按下面这个顺序跟用户交互,不要一次问所有东西:**

## 第 1 步:选择后端

```
Claude 输出:
  这是你第一次使用 workspace-sync,请选择云端存储后端:

  [1] GitLab   - 把工作空间作为 commit 推到一个已存在的 GitLab 仓库
                 你需要准备:仓库地址 + Personal Access Token
  
  [2] MinIO    - 把工作空间作为对象存到一个已存在的 bucket 的某个前缀下
                 你需要准备:endpoint、access_key、secret_key、bucket 名
                 另外本机需要装 mc 客户端(MinIO CLI)

  请回复 1 或 2。
```

等用户回复。

## 第 2 步(如果选 GitLab):收集 GitLab 配置

一次问一个字段,收齐后**立即验证仓库存在**:

```
Claude 问:
  1. GitLab 主机(例如 gitlab.com 或 your.gitlab.com):
  2. Personal Access Token(scope 需要 api + read_repository + write_repository):
  3. 仓库路径(namespace/name 格式,例如 your-name/claude-workspaces)
     注意: 必须是一个已存在的仓库,skill 不会帮你创建
  4. 使用的分支(默认 main,可直接回车):
```

**验证仓库存在:**
```bash
GITLAB_HOST="..."
GITLAB_TOKEN="..."
GITLAB_PROJECT_PATH="your-name/claude-workspaces"
ENC_PATH=$(printf '%s' "$GITLAB_PROJECT_PATH" | sed 's|/|%2F|g')

RESULT=$(no_proxy="$GITLAB_HOST" curl -s -o /dev/null -w "%{http_code}" \
  --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  "https://${GITLAB_HOST}/api/v4/projects/${ENC_PATH}")

if [[ "$RESULT" != "200" ]]; then
  echo "❌ 仓库验证失败 (HTTP $RESULT)"
  # 401 = token 无效/过期
  # 404 = 仓库不存在或无权限
  exit 1
fi
echo "✓ 仓库验证通过"
```

验证失败 → 告诉用户具体原因(401 还是 404),停止配置,让用户修复后重试。
验证成功 → 写 config.json,继续原来的命令。

## 第 3 步(如果选 MinIO):收集 MinIO 配置

**先检查 mc 是否安装:**
```bash
if ! command -v mc &>/dev/null; then
  echo "❌ 未找到 mc(MinIO 客户端)"
  echo "请先安装:"
  echo "  Windows: scoop install mc  或  choco install minio-client"
  echo "  macOS:   brew install minio/stable/mc"
  echo "  Linux:   curl https://dl.min.io/client/mc/release/linux-amd64/mc -o mc && chmod +x mc"
  exit 1
fi
```

mc 可用后,依次问:
```
  1. MinIO endpoint (例如 https://minio.example.com):
  2. Access Key:
  3. Secret Key:
  4. Bucket 名称(必须已存在):
  5. Bucket 内的前缀/文件夹(例如 workspaces/,留空则存在根):
```

**配置 mc alias 并验证 bucket 存在:**
```bash
MC_ALIAS="claude-workspace-sync"
mc alias set "$MC_ALIAS" "$MINIO_ENDPOINT" "$MINIO_AK" "$MINIO_SK" --api S3v4

# 验证 bucket
if ! mc ls "$MC_ALIAS/$MINIO_BUCKET" &>/dev/null; then
  echo "❌ Bucket '$MINIO_BUCKET' 不存在或无权限访问"
  exit 1
fi
echo "✓ Bucket 验证通过"
```

验证通过 → 写 config.json,继续原来的命令。

## 第 4 步:写入 config.json

用 Write 工具(或 python inline)更新 config.json,只改相关字段,保留其他。

写入完成后 Claude 输出:
```
✓ 配置已保存。继续执行 /workspace-sync <原命令>...
```

然后继续原本用户请求的操作。

---

# Push 流程(backend 无关部分)

## Step 1: 加载配置(同上 Step 0)

## Step 2: 定位当前 session jsonl

```bash
WIN_PWD=$(cygpath -w "$PWD" 2>/dev/null || echo "$PWD")
ENCODED_CWD=$(echo "$WIN_PWD" | sed 's|[:\\/]|-|g')
SESSIONS_DIR="$HOME/.claude/projects/$ENCODED_CWD"
SESSION_JSONL=$(ls -t "$SESSIONS_DIR"/*.jsonl 2>/dev/null | head -1)
[[ -z "$SESSION_JSONL" ]] && { echo "未找到当前会话 jsonl"; exit 1; }
```

## Step 3: 自动识别涉及的项目

```bash
SCRIPT="$HOME/.claude/skills/workspace-sync/scripts/detect-projects.sh"
chmod +x "$SCRIPT"
PROJECTS_JSON=$(bash "$SCRIPT" "$SESSION_JSONL")
```

## Step 4: 确认

```
检测到本次对话涉及 N 个项目:
  [1] shanks-manage  (feature/import, 3 个文件)
  ...
工作空间名称: <用户传入或建议>
确认推送? [Y/n]
```

N=0 → 纯讨论模式继续。

所有接受 `<name>` 的命令(至少 `push`/`pull`)在真正读写本地路径或云端对象前,都必须先校验工作空间名称。

Push 确认通过后先校验工作空间名称:

```bash
validate_ws_name "$WS_NAME" || {
  echo "❌ 非法工作空间名称: $WS_NAME"
  echo "   支持中文命名"
  echo "   不允许空白、路径分隔符、控制字符或 Windows 非法文件名字符"
  exit 1
}
```

## Step 5: 准备工作空间暂存目录(本地 staging)

```bash
CACHE_DIR="${CACHE_DIR:-$HOME/.claude/workspace-cache}"
STAGE_ROOT="$CACHE_DIR/staging"
STAGE_DIR="$STAGE_ROOT/$WS_NAME"
[[ "$STAGE_DIR" == "$STAGE_ROOT/"* ]] || { echo "非法 staging 路径"; exit 1; }
rm -rf -- "$STAGE_DIR"
mkdir -p "$STAGE_DIR/projects"

# 复制 session jsonl
cp "$SESSION_JSONL" "$STAGE_DIR/conversation.jsonl"
```

## Step 6: 读取当前远端版本并计算下一个版本号

```bash
CURRENT_REMOTE_VERSION=0

# backend-specific:
# - 如果远端 workspace 已存在,读取其 manifest.json.version
# - 不存在则保持 0

NEXT_VERSION=$((CURRENT_REMOTE_VERSION + 1))
```

如果读取失败但远端对象存在,直接报错,不要盲目覆盖。

## Step 7: 校验每个项目已经提交并推送

当前原则是:工作空间同步重点是聊天上下文恢复,代码恢复只支持**已经提交且已经推送**的状态。

```bash
for each detected project:
  cd "$PROJECT_PATH"

  [[ -z "$(git status --porcelain)" ]] || {
    echo "❌ 项目 $PROJECT_NAME 存在未提交改动,请先 commit/push 后再执行 workspace-sync push"
    exit 1
  }

  UPSTREAM=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)
  [[ -n "$UPSTREAM" ]] || {
    echo "❌ 项目 $PROJECT_NAME 当前分支没有上游分支,请先 push -u"
    exit 1
  }

  git fetch --prune
  COUNTS=$(git rev-list --left-right --count HEAD...@{u})
  AHEAD=$(echo "$COUNTS" | awk '{print $1}')
  BEHIND=$(echo "$COUNTS" | awk '{print $2}')
  [[ "$AHEAD" == "0" && "$BEHIND" == "0" ]] || {
    echo "❌ 项目 $PROJECT_NAME 与上游分支不同步(ahead=$AHEAD behind=$BEHIND),请先同步代码后再执行 workspace-sync push"
    exit 1
  }
```

只要有一个项目不满足,整个 push 直接终止。不要在代码状态不确定时生成可跨设备恢复的 workspace。

## Step 8: Claude 生成 summary.md 和 manifest.json

Claude 用 Read 工具读 session jsonl,然后用 Write 工具写入:
- `$STAGE_DIR/summary.md`
- `$STAGE_DIR/manifest.json`

**摘要生成原则:**
1. 整体目标:从对话开头几条用户消息提炼,不超过 2 句
2. 按项目分段:每个 detect 到的项目一段
3. 讨论脉络(纯讨论时):共识/待议/决策
4. "下一步"必须具体:"继续写 XXController" > "继续开发"

写 manifest 时必须包含:
- `version: NEXT_VERSION`
- `previous_version: CURRENT_REMOTE_VERSION`

## Step 9: 记录每个项目的 git 指针

```bash
for each detected project:
  PROJ_DIR="$STAGE_DIR/projects/$PROJECT_NAME"
  mkdir -p "$PROJ_DIR"
  (
    cd "$PROJECT_PATH"
    UPSTREAM=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}')
    # 写 meta.json(见 manifest 格式)
  )
```

## Step 10: 调用 skill state 标准接口导出 portable 状态

如果本次 workspace 里明确涉及某个 skill,Claude 应该尝试:
1. 找到该 skill 的安装目录
2. 读取 `workspace-sync.contract.json`
3. 遍历其中 `states`
4. 只对 `portability=portable` 的状态调用 `export_command`
5. 把结果写入 `$STAGE_DIR/skill-states/<skill-name>/`

导出约束:
- `pid`、`lock`、`tmp`、daemon 状态、设备绑定信息不得标记为 `portable`
- `global` 状态是否可同步,完全由 contract 的 `portability` 决定
- `workspace-sync` 不再区分“skill 状态”和“skill 全局缓存”,统一按 `scope + portability` 处理
- 如果 skill 没有 contract:
  - 记录 `status=not_exported`
  - 不要猜测其目录结构
- 如果 contract 存在但 export 失败:
  - 记录 `status=skipped`
  - 不影响整个 workspace 的上下文保存

如果启用该能力,manifest 中要额外写入 `skill_states` 的导出结果。

## Step 11: 上传前做一次乐观并发校验

在真正覆盖远端 workspace 之前,再读取一次远端版本:

```bash
LATEST_REMOTE_VERSION=<backend-specific read>
```

如果 `LATEST_REMOTE_VERSION != CURRENT_REMOTE_VERSION`,说明在本次 push 期间远端已被其他设备更新。

Claude 必须明确提示用户:
- 你本地基于的版本: `CURRENT_REMOTE_VERSION`
- 当前远端版本: `LATEST_REMOTE_VERSION`
- 计划提交的新版本原本是: `NEXT_VERSION`

然后询问用户是否继续:
- 如果继续:
  - 重新设 `NEXT_VERSION=LATEST_REMOTE_VERSION+1`
  - 重写 manifest 中的 `version`/`previous_version`
  - 再执行上传
- 如果取消:
  - 直接停止本次 push

## Step 12: 调用 backend-specific 上传

根据 `$BACKEND` 分派到对应实现(见下方"后端实现")。

## Step 13: 报告成功

```
✓ 工作空间已推送: <name>
  - 后端: gitlab / minio
  - 版本: v<NEXT_VERSION> (previous v<CURRENT_REMOTE_VERSION>)
  - 涉及项目: N 个
  - 代码前提: 所有项目均已提交并已推送
  - skill 状态: 按 skill contract 中声明的 portable 状态导出
  - 在另一设备用 /workspace-sync pull <name> 恢复
```

---

# Pull 流程(backend 无关部分)

## Step 1: 加载配置

## Step 2: 根据 backend 下载工作空间到本地 staging

```bash
validate_ws_name "$WS_NAME" || {
  echo "❌ 非法工作空间名称: $WS_NAME"
  echo "   支持中文命名"
  echo "   不允许空白、路径分隔符、控制字符或 Windows 非法文件名字符"
  exit 1
}

CACHE_DIR="${CACHE_DIR:-$HOME/.claude/workspace-cache}"
STAGE_ROOT="$CACHE_DIR/staging"
STAGE_DIR="$STAGE_ROOT/$WS_NAME"
[[ "$STAGE_DIR" == "$STAGE_ROOT/"* ]] || { echo "非法 staging 路径"; exit 1; }
rm -rf -- "$STAGE_DIR"
mkdir -p "$STAGE_DIR"
```

backend-specific 下载(见下方)。

## Step 3: 读 manifest.json,遍历 projects

对每个 project:
1. 查 `local-paths.json`,用 git_remote 找本地路径
2. 找不到 → 询问用户,写入 local-paths.json
3. 到本地路径执行:
   - 如果本地项目有未提交改动:`git status --porcelain` 非空 → 报错并跳过该项目,不要覆盖当前工作区
   - `git fetch --all --prune`
   - 校验 `meta.json`/`manifest.json` 里的 `head` 是否存在:`git cat-file -e <head>^{commit}`
   - 不存在 → 报错并跳过该项目
   - 存在 → `git checkout -B <branch> <head>`
   - 如果记录了 `upstream`,则把本地 branch 重新关联到该 upstream

pull 的汇报必须分两层:
- 工作空间上下文恢复: `summary.md` + `conversation.jsonl`
- 项目代码恢复: exact / skipped

再增加第三层:
- skill 状态恢复: restored / skipped / missing / deferred

含义:
- `restored`: skill 的可移植 workspace state 已恢复
- `skipped`: 检测到该 skill,但当前环境或版本不满足恢复条件
- `missing`: 本次 workspace 明确没有导出该 skill 状态
- `deferred`: 技能状态归档已保留,但需等 skill 安装后再 import

只要摘要成功恢复,就可以继续对话;但如果某些项目被 skip,Claude 必须明确告诉用户这些项目的代码现场没有完全恢复,不能把 summary 当作当前代码事实。

如果工作空间明确提到了某个 skill,但该 skill 状态没有恢复成功,Claude 必须额外说明:
- 当前 workspace 涉及该 skill
- 但该 skill 的工作区状态未完全恢复
- 与该 skill 相关的摘要只能作为参考,不能当作当前现场事实

## Step 4: 调用 skill state 标准接口导入 portable 状态

对 `manifest.skill_states` 中的每一项:
- 找到对应 skill 的安装目录
- 读取其 `workspace-sync.contract.json`
- 找到匹配的 `state`
- 如果存在 `import_command`,则执行导入

恢复规则:
- skill 未安装 → `deferred`
- contract 缺失 → `deferred`
- contract 存在但 state 不兼容/版本不符 → `skipped`
- import 成功 → `restored`
- 本次 workspace 没有该 skill 的导出记录 → `missing`

## Step 5: 注入 summary.md 到当前上下文

Claude 用 Read 工具读 summary.md,告诉用户恢复了什么,准备继续工作。

---

# Clean 流程

## Step 1: 解析命令

支持:
- `/workspace-sync clean <name>`
- `/workspace-sync clean --all`

不支持部分 pull,也不做自动 TTL 清理。

## Step 2: 列出将要删除的内容

`clean <name>`:
- 远端保存的 `<name>`
- 本地 staging 缓存中的 `<name>`
- 本地 pending/deferred skill state 中与 `<name>` 相关的缓存

`clean --all`:
- 当前 backend 下的全部 workspace
- 本地全部 workspace staging 缓存
- 本地全部 pending/deferred skill state 缓存

## Step 3: 二次确认

Claude 必须先展示将删除的目标,然后确认:

```text
将删除以下内容:
  - 远端 workspace: <name>
  - 本地缓存: <name>

确认继续? [y/N]
```

`clean --all` 必须使用更强确认:

```text
这会删除当前 backend 下的全部 workspace 及本地缓存。
请明确回复: DELETE ALL
```

## Step 4: 执行删除

先删除远端,再删除本地缓存。每一步都必须做路径校验,避免误删。

## Step 5: 报告结果

```text
✓ 已清理 workspace: <name>
  - 远端: deleted
  - 本地缓存: deleted
  - pending skill state: deleted
```

---

# 后端实现:GitLab

## Setup 验证

见首次配置流程第 2 步。

## 准备本地 clone(push/pull/list 都需要)

```bash
LOCAL_REPO="$HOME/.claude/workspace-cache/gitlab/$(echo $GITLAB_PROJECT_PATH | sed 's|/|_|g')"

if [[ ! -d "$LOCAL_REPO/.git" ]]; then
  mkdir -p "$(dirname "$LOCAL_REPO")"
  no_proxy="$GITLAB_HOST" git clone \
    "https://oauth2:${GITLAB_TOKEN}@${GITLAB_HOST}/${GITLAB_PROJECT_PATH}.git" \
    "$LOCAL_REPO"
else
  (cd "$LOCAL_REPO" && no_proxy="$GITLAB_HOST" git pull --ff-only)
fi
```

**⚠ clone 失败就直接报错退出**,不尝试创建。

## Push

```bash
WS_DIR="$LOCAL_REPO/$WS_NAME"
CURRENT_REMOTE_VERSION=0
if [[ -f "$WS_DIR/manifest.json" ]]; then
  CURRENT_REMOTE_VERSION=$(python3 -c "import json; print(json.load(open(r'$WS_DIR/manifest.json')).get('version', 0) or 0)" 2>/dev/null || echo 0)
fi

[[ "$WS_DIR" == "$LOCAL_REPO/"* ]] || { echo "非法 workspace 路径"; exit 1; }
rm -rf -- "$WS_DIR"
mkdir -p "$WS_DIR"
cp -r "$STAGE_DIR"/* "$WS_DIR/"

(
  cd "$LOCAL_REPO"
  git checkout "$GITLAB_BRANCH" 2>/dev/null || git checkout -b "$GITLAB_BRANCH"
  git add "$WS_NAME"
  git -c user.email="workspace-sync@local" -c user.name="workspace-sync" \
      commit -m "workspace: update $WS_NAME from $(hostname)" || echo "nothing to commit"
  no_proxy="$GITLAB_HOST" git push origin "$GITLAB_BRANCH"
)
```

## Pull

```bash
# 先确保 LOCAL_REPO 是最新的(见"准备本地 clone")
WS_DIR="$LOCAL_REPO/$WS_NAME"
if [[ ! -d "$WS_DIR" ]]; then
  echo "工作空间 $WS_NAME 不存在"
  exit 1
fi
# 复制到 staging
cp -r "$WS_DIR"/* "$STAGE_DIR/"
```

## List

```bash
cd "$LOCAL_REPO"
for WS in */; do
  WS="${WS%/}"
  [[ "$WS" == ".git" ]] && continue
  [[ -f "$WS/manifest.json" ]] || continue
  echo "- $WS"
done
```

## Clean

```bash
cd "$LOCAL_REPO"

if [[ "$WS_NAME" == "--all" ]]; then
  for WS in */; do
    WS="${WS%/}"
    [[ "$WS" == ".git" ]] && continue
    [[ -f "$WS/manifest.json" ]] || continue
    rm -rf -- "$WS"
  done
else
  WS_DIR="$LOCAL_REPO/$WS_NAME"
  [[ "$WS_DIR" == "$LOCAL_REPO/"* ]] || { echo "非法 workspace 路径"; exit 1; }
  rm -rf -- "$WS_DIR"
fi

git add -A
git -c user.email="workspace-sync@local" -c user.name="workspace-sync" \
    commit -m "workspace: clean ${WS_NAME} from $(hostname)" || echo "nothing to commit"
no_proxy="$GITLAB_HOST" git push origin "$GITLAB_BRANCH"
```

---

# 后端实现:MinIO

## Setup 验证

见首次配置流程第 3 步。

## 准备 mc alias(每次执行前都确保 alias 存在)

```bash
MC_ALIAS="$(read config .minio.mc_alias)"
mc alias set "$MC_ALIAS" "$MINIO_ENDPOINT" "$MINIO_AK" "$MINIO_SK" --api S3v4 &>/dev/null
BUCKET_PATH="$MC_ALIAS/$MINIO_BUCKET/$MINIO_PREFIX"
# 末尾补 /
[[ "$BUCKET_PATH" != */ ]] && BUCKET_PATH="$BUCKET_PATH/"
```

## Push

```bash
# 读取当前远端版本
CURRENT_REMOTE_VERSION=$(mc cat "$BUCKET_PATH$WS_NAME/manifest.json" 2>/dev/null | \
  python3 -c "import json,sys; print(json.load(sys.stdin).get('version', 0) or 0)" 2>/dev/null || echo 0)

# 先删除云端已有的同名工作空间(覆盖)
mc rm --recursive --force "$BUCKET_PATH$WS_NAME/" 2>/dev/null

# 上传 staging 目录
mc cp --recursive "$STAGE_DIR/" "$BUCKET_PATH$WS_NAME/"
```

## Pull

```bash
# 检查云端工作空间是否存在
if ! mc ls "$BUCKET_PATH$WS_NAME/" &>/dev/null; then
  echo "工作空间 $WS_NAME 不存在"
  exit 1
fi

# 下载到 staging
mc cp --recursive "$BUCKET_PATH$WS_NAME/" "$STAGE_DIR/"
```

## List

```bash
mc ls "$BUCKET_PATH" 2>/dev/null | awk '{print $NF}' | sed 's|/$||'
```

## Clean

```bash
if [[ "$WS_NAME" == "--all" ]]; then
  mc rm --recursive --force "$BUCKET_PATH"
else
  mc rm --recursive --force "$BUCKET_PATH$WS_NAME/"
fi
```

---

# 边界处理

| 情况 | 处理 |
|------|------|
| config 不完整 | 进入首次配置流程 |
| GitLab token 无效(401) | 配置时验证失败;命令时报错退出,提示重新配置 |
| GitLab 仓库不存在(404) | 配置时验证失败;命令时报错退出,提示先去 GitLab 创建空仓库 |
| MinIO bucket 不存在 | 验证失败,提示先去 MinIO 创建 bucket |
| mc 未安装(minio 后端) | 报错退出,给出安装命令 |
| detect-projects 返回空 | 按纯讨论模式继续 |
| push 时项目存在未提交改动 | 直接报错,要求用户先 commit/push |
| push 时项目没有 upstream | 直接报错,要求用户先 `git push -u` |
| push 时项目与 upstream 不同步 | 直接报错,要求用户先同步代码 |
| push 时发现远端版本已变化 | 告警并询问用户是否基于最新版本继续提交 |
| 项目路径未映射(pull 时) | 交互询问用户,写入 local-paths.json |
| 记录的 `head` 在目标设备不存在 | 跳过该项目并报错 |
| pull 时本地有未提交改动 | 跳过该项目并报错,不要覆盖当前工作区 |
| 某个 skill 未安装或版本不兼容 | 该 skill 状态记为 `skipped` 或 `deferred`,但不影响 workspace 上下文恢复 |
| 某个 skill 没有 export/import 契约 | 直接视为 `not_exported`,不要猜测其内部目录结构 |
| clean 时目标不存在 | 明确提示 nothing to clean,不要报致命错误 |
| workspace 名称非法 | 立即报错,不要做任何删除/覆盖操作 |

---

# 暂未实现的功能

- GitHub / S3 后端支持
- workspace 版本历史浏览与回滚
