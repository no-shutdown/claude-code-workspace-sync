# workspace-sync 使用说明

## 1. 这个 skill 是做什么的

`workspace-sync` 用来在多台设备之间同步 Claude Code 的工作上下文。它同步的是“工作现场信息”，不是完整代码仓库本身。

典型同步内容包括：

- 对话摘要
- 对话备份
- 当前会话涉及项目的 git 指针
- 其他 skill 通过标准 contract 声明的 portable 状态

它不会同步：

- 未提交的本地改动
- 已提交但尚未 push 的本地提交
- `.gitignore` 忽略文件
- 未声明为 portable 的 skill 状态

## 2. 基本流程

推荐流程如下：

1. 在设备 A 完成阶段性工作，并确保相关仓库已经提交且推送
2. 执行 `/workspace-sync push <workspace-name>`
3. 在设备 B 执行 `/workspace-sync pull <workspace-name>`
4. 继续之前的任务

如果只是查看已有记录，使用：

```bash
/workspace-sync list
```

如果要删除记录，使用：

```bash
/workspace-sync clean <workspace-name>
/workspace-sync clean --all
```

## 3. 环境要求

使用前建议确认：

- 已安装 Claude Code CLI
- 已安装 Git
- 有可运行 bash 脚本的环境
- 已配置一个远端后端：GitLab 或 MinIO

Windows 下建议使用 Git Bash 或其他兼容 bash 的环境。

## 4. 安装

先克隆仓库：

```bash
git clone https://github.com/<your-username>/workspace-sync
cd workspace-sync
```

再执行安装：

```bash
./install.sh
```

默认会安装到：

```text
~/.claude/skills/workspace-sync
```

可选参数：

```bash
./install.sh --target /path/to/skills/workspace-sync
./install.sh --no-init-config
```

## 5. 配置

安装后，配置文件默认位于：

```text
~/.claude/skills/workspace-sync/config.json
```

常见字段包括：

- `backend`：`gitlab` 或 `minio`
- `cache_dir`：本地缓存目录
- `local_paths_file`：本地项目路径映射
- `scan_roots`：扫描本地 git 项目的目录列表

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
  "local_paths_file": "~/.claude/skills/workspace-sync/local-paths.json",
  "scan_roots": [
    "D:/work",
    "D:/src"
  ]
}
```

## 6. 各 action 怎么用

### push

```bash
/workspace-sync push my-task
```

用途：保存当前工作上下文并上传。

执行前必须保证：

- git 工作区干净
- 当前分支已设置 upstream
- 本地提交已 push

### pull

```bash
/workspace-sync pull my-task
```

用途：在另一台设备恢复之前保存的 workspace。

### list

```bash
/workspace-sync list
```

用途：查看当前后端中已有的 workspace。

### clean

```bash
/workspace-sync clean my-task
/workspace-sync clean --all
```

用途：删除一个或全部 workspace，并清理相关缓存。

## 7. 推荐使用方式

一个稳妥的日常用法是：

1. 在当前设备完成提交并推送
2. `push` 一个明确命名的 workspace
3. 在新设备 `pull` 同名 workspace
4. 继续工作
5. 工作结束后按需要再次 `push`

建议 workspace 名称和任务名保持一致，例如：

- `feature-import`
- `fix-login-timeout`
- `release-2026-04`

## 8. 常见注意事项

- `push` 失败时，优先检查 git 是否干净、是否已 push、是否配置 upstream
- `pull` 只能恢复到已记录的代码位置，不能恢复未提交改动
- `clean --all` 是破坏性操作，执行前要确认
- 其他 skill 如果没有声明 contract，`workspace-sync` 不会处理它们的状态

## 9. 相关文档

- `action/`：按 action 拆开的独立说明
- `docs/skill-state-contract.md`：其他 skill 接入 `workspace-sync` 的 contract 规范
- `templates/workspace-sync.contract.example.json`：contract 示例模板
