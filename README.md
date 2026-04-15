# workspace-sync

一个用于 [Claude Code](https://claude.ai/code) 的 skill，用来在多台设备之间同步工作空间上下文。

它同步的是：
- 对话历史备份
- AI 生成的工作摘要
- 本次对话涉及项目的精确 git 指针信息

它不同步的是：
- 本地未提交改动
- 已提交但未 push 的本地提交
- `.gitignore` 忽略文件

当前 v1 的设计目标很明确：优先恢复工作空间上下文，代码侧只恢复“已经提交且已经推送”的状态。

---

## 这个 skill 解决什么问题

Claude Code 的上下文默认是本地的。

你在公司电脑上做了一半，回家后换一台机器继续时，通常会丢失这些信息：
- 刚才聊到了哪
- 当前目标是什么
- 哪些项目被改过
- 下一个具体动作是什么

`workspace-sync` 的作用就是：

1. 在离开当前设备前，把这次工作会话打包成一个 workspace
2. 在另一台设备上拉取这个 workspace
3. 让 Claude 恢复这次工作的讨论上下文，并把相关项目切到对应代码位置

---

## 工作方式

```bash
/workspace-sync push "feature-x"   # 离开当前设备前
/workspace-sync pull "feature-x"   # 在另一台设备继续
/workspace-sync list               # 查看已保存的 workspace
```

### push 时会做什么

- 自动识别当前对话涉及到的 git 项目
- 让 Claude 生成一份结构化摘要
- 校验每个项目是否已经：
  - 没有未提交改动
  - 已设置 upstream
  - 与 upstream 完全同步
- 记录每个项目的：
  - `remote`
  - `upstream`
  - `branch`
  - `HEAD`
- 上传到你配置的后端

### pull 时会做什么

- 下载指定 workspace
- 恢复 `summary.md` 和 `conversation.jsonl`
- 根据每个项目记录的 git 指针恢复代码位置
- 把摘要重新注入当前 Claude 会话，方便继续工作

---

## v1 的边界

这版是一个保守实现。

为了避免“聊天上下文恢复了，但代码现场其实不一致”这种误导，v1 直接采用严格规则：

- `push` 前，相关项目必须先把代码处理干净
- 只允许同步“已提交且已 push”的代码状态
- 只要有一个项目不满足要求，整个 `push` 直接失败

也就是说，在执行 `/workspace-sync push <name>` 之前，你应该先完成这些事：

```bash
git status            # 必须干净
git push              # 本地提交必须已经推送
```

不满足以下任一条件时，`push` 会直接终止：
- 有未提交改动
- 有 staged 但未 commit 的改动
- 当前分支没有 upstream
- 本地和 upstream 不同步

---

## 支持的场景

- 纯讨论：没有代码改动，只同步上下文
- 单项目：一次对话只涉及一个仓库
- 多项目：一次对话同时涉及多个仓库

---

## 存储后端

当前支持两种后端，二选一：

- GitLab
- MinIO

前提要求：

### GitLab

你需要准备：
- 一个已经存在的仓库
- 有权限的 Personal Access Token

### MinIO

你需要准备：
- 一个已经存在的 bucket
- 有权限的 `access_key` / `secret_key`
- 本机已经安装 `mc`

这个 skill 不会自动创建 GitLab 仓库或 MinIO bucket。

---

## 环境要求

- [Claude Code](https://claude.ai/code) CLI
- Git
- 一个 bash 兼容环境
- 常见 Unix 命令：`bash`、`grep`、`sed`、`cp`、`rm`
- GitLab 模式下需要有效的 PAT
- MinIO 模式下需要 `mc`

Windows 下建议使用：
- Git Bash
- 或其他可运行 bash 脚本的环境

---

## 安装

```bash
# 克隆仓库
git clone https://github.com/<your-username>/workspace-sync
cd workspace-sync

# 安装到 ~/.claude/skills/workspace-sync
./install.sh
```

安装完成后，会把运行时需要的文件复制到：

```text
~/.claude/skills/workspace-sync
```

首次安装时，如果目标目录下还没有 `config.json`，安装脚本会自动用模板初始化一份。

### 安装参数

```bash
# 安装到自定义目录
./install.sh --target /path/to/skills/workspace-sync

# 不初始化 config.json
./install.sh --no-init-config
```

### 卸载

```bash
./uninstall.sh
```

---

## 仓库结构

```text
workspace-sync/
├── SKILL.md
├── README.md
├── install.sh
├── uninstall.sh
├── scripts/
│   └── detect-projects.sh
└── templates/
    └── config.json.example
```

说明：

- `SKILL.md`：Claude 实际遵循的 skill 定义
- `scripts/`：skill 运行时会用到的辅助脚本
- `templates/`：安装时使用的模板文件
- `install.sh`：安装脚本
- `uninstall.sh`：卸载脚本

---

## 配置

安装后，配置文件默认位于：

```text
~/.claude/skills/workspace-sync/config.json
```

它由 `templates/config.json.example` 初始化而来。

示例：

```json
{
  "backend": "gitlab",
  "gitlab": {
    "host": "gitlab.com",
    "token": "glpat-xxx",
    "project_path": "your-name/claude-workspaces",
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

注意：

- `backend` 可选 `gitlab` / `minio`
- 首次使用时如果未配置完整，Claude 会进入交互式配置流程
- `config.json` 和 `local-paths.json` 都应保留在本地，不应提交到仓库

---

## 使用方式

### 1. 保存当前 workspace

```bash
/workspace-sync push my-task
```

这个命令会：
- 收集当前会话上下文
- 校验相关项目是否都已经提交并推送
- 保存摘要、会话备份和项目 git 指针

### 2. 在另一台设备恢复

```bash
/workspace-sync pull my-task
```

这个命令会：
- 下载该 workspace
- 恢复摘要和会话备份
- 尝试把每个相关项目切回记录的分支和提交

### 3. 查看远端已有 workspace

```bash
/workspace-sync list
```

---

## Workspace 存储格式

每个 workspace 最终会保存成一个目录：

```text
<workspace-name>/
├── manifest.json
├── summary.md
├── conversation.jsonl
└── projects/
    └── <project-name>/
        └── meta.json
```

其中：

- `manifest.json`：workspace 元数据与项目列表
- `summary.md`：Claude 生成的结构化摘要
- `conversation.jsonl`：完整对话备份
- `projects/<project>/meta.json`：项目的 `remote / upstream / branch / head`

---

## 跨设备项目路径映射

不同设备上，同一个项目的本地路径可能完全不同：

- 目录名不同
- 父目录不同
- 操作系统不同

所以这个 skill 不依赖“源设备路径”来恢复项目，而是依赖：

- git remote
- 本地 `local-paths.json` 映射

第一次在新设备上 `pull` 某个项目时，如果找不到本地路径，Claude 会询问你该项目在本机的仓库目录，并写入：

```text
~/.claude/skills/workspace-sync/local-paths.json
```

后续再拉取同一个项目时，就会直接复用这份映射。

---

## pull 时的恢复结果

`pull` 后的结果要分成两层理解：

### 1. 工作空间上下文恢复

只要 `summary.md` 和 `conversation.jsonl` 成功恢复，Claude 就能知道：
- 上次做到哪
- 当前目标是什么
- 下一步准备做什么

### 2. 项目代码恢复

每个项目会单独判断是否恢复成功。

常见情况：

- `exact`：成功恢复到记录的 `HEAD`
- `skipped`：没有恢复成功

项目会被跳过的典型原因：
- 目标设备本地目录没映射上
- 本地工作区有未提交改动
- 记录的 `HEAD` 在目标设备不可用

所以这个 skill 的正确使用方式是：

- 先把代码状态整理干净再 `push`
- 再用 workspace 同步上下文和代码指针

---

## 重要约束

- workspace 名称只能使用：
  - 字母
  - 数字
  - 点 `.`
  - 下划线 `_`
  - 短横线 `-`
- `push` 时如果检测到项目代码不干净，会直接失败
- `pull` 时如果本地项目有未提交改动，该项目会被跳过，不会强制覆盖

---

## 路线图

- 同步更多 skill 状态，如 `.sdd/`、`.ccb/`
- 多设备并发冲突保护
- workspace 自动清理 / TTL
- GitHub / S3 后端支持

---

## 开发说明

核心文件：

- [SKILL.md](./SKILL.md)
- [scripts/detect-projects.sh](./scripts/detect-projects.sh)

如果要新增后端实现，建议沿着 `SKILL.md` 里的后端章节扩展。
