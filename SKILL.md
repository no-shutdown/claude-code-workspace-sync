---
name: workspace-sync
description: 跨设备同步 Claude Code 工作空间(对话摘要 + 涉及的 git 项目状态)。支持 GitLab 或 MinIO 两种存储后端,首次使用会引导用户选择和配置。当用户输入 /workspace-sync、`workspace-sync push/pull/list`、或明确提到把当前对话/工作同步到云端、从云端恢复工作空间、跨设备继续之前工作时使用。
---

# Workspace Sync

## 概述

把当前对话的工作状态(对话摘要 + 涉及的所有 git 项目的 branch/HEAD/未提交改动)打包上传到云端。另一台设备 pull 下来后,Claude 读摘要就能恢复上下文,每个项目的分支和未提交改动也会自动恢复。

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
        ├── meta.json      (remote/branch/head)
        └── uncommitted.patch
```

## manifest.json 格式

```json
{
  "name": "存量名单导入重构",
  "conversation_id": "71fc3842-...",
  "source_device": "company-pc",
  "source_cwd": "D:\\A-ukon-work\\shanks-manage",
  "created_at": "2026-04-15T18:00:00+08:00",
  "projects": [
    {
      "name": "shanks-manage",
      "remote": "git@your.gitlab.com:namespace/your-project.git",
      "branch": "feature/import",
      "head": "abc123",
      "has_patch": true
    }
  ]
}
```

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
  "http://${GITLAB_HOST}/api/v4/projects/${ENC_PATH}")

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

## Step 5: 准备工作空间暂存目录(本地 staging)

```bash
STAGE_DIR="$HOME/.claude/workspace-cache/staging/$WS_NAME"
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR/projects"

# 复制 session jsonl
cp "$SESSION_JSONL" "$STAGE_DIR/conversation.jsonl"
```

## Step 6: Claude 生成 summary.md 和 manifest.json

Claude 用 Read 工具读 session jsonl,然后用 Write 工具写入:
- `$STAGE_DIR/summary.md`
- `$STAGE_DIR/manifest.json`

**摘要生成原则:**
1. 整体目标:从对话开头几条用户消息提炼,不超过 2 句
2. 按项目分段:每个 detect 到的项目一段
3. 讨论脉络(纯讨论时):共识/待议/决策
4. "下一步"必须具体:"继续写 XXController" > "继续开发"

## Step 7: 捕获每个项目的 git 状态

```bash
for each detected project:
  PROJ_DIR="$STAGE_DIR/projects/$PROJECT_NAME"
  mkdir -p "$PROJ_DIR"
  (
    cd "$PROJECT_PATH"
    git diff HEAD > "$PROJ_DIR/uncommitted.patch"
    # 写 meta.json(见 manifest 格式)
  )
```

## Step 8: 调用 backend-specific 上传

根据 `$BACKEND` 分派到对应实现(见下方"后端实现")。

## Step 9: 报告成功

```
✓ 工作空间已推送: <name>
  - 后端: gitlab / minio
  - 涉及项目: N 个
  - 在另一设备用 /workspace-sync pull <name> 恢复
```

---

# Pull 流程(backend 无关部分)

## Step 1: 加载配置

## Step 2: 根据 backend 下载工作空间到本地 staging

```bash
STAGE_DIR="$HOME/.claude/workspace-cache/staging/$WS_NAME"
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"
```

backend-specific 下载(见下方)。

## Step 3: 读 manifest.json,遍历 projects

对每个 project:
1. 查 `local-paths.json`,用 git_remote 找本地路径
2. 找不到 → 询问用户,写入 local-paths.json
3. 到本地路径执行:
   - 备份本地未提交改动到 `~/.claude/workspace-backup/<时间戳>/`
   - `git fetch` + `git checkout <branch>`
   - `git apply --3way uncommitted.patch`,冲突不中断其他项目

## Step 4: 注入 summary.md 到当前上下文

Claude 用 Read 工具读 summary.md,告诉用户恢复了什么,准备继续工作。

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
    "http://oauth2:${GITLAB_TOKEN}@${GITLAB_HOST}/${GITLAB_PROJECT_PATH}.git" \
    "$LOCAL_REPO"
else
  (cd "$LOCAL_REPO" && no_proxy="$GITLAB_HOST" git pull --ff-only)
fi
```

**⚠ clone 失败就直接报错退出**,不尝试创建。

## Push

```bash
WS_DIR="$LOCAL_REPO/$WS_NAME"
rm -rf "$WS_DIR"
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
| 项目路径未映射(pull 时) | 交互询问用户,写入 local-paths.json |
| patch 冲突 | 使用 `git apply --3way`,失败不中断其他项目 |
| 本地有未提交改动 | 备份到 `~/.claude/workspace-backup/<时间戳>/` |

---

# 不在 v1 范围内的功能

- skill 状态同步(`.sdd/`、`.ccb/` 等)
- 多设备并发冲突保护(乐观锁)
- 部分 pull(`--only backend`)
- workspace 自动清理 / TTL
