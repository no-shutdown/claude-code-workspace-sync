# push

## 命令

```bash
/workspace-sync push <workspace-name>
```

## 作用

把当前会话的工作上下文保存为一个 workspace，并上传到已配置的远端后端。

保存内容通常包括：

- 对话摘要
- 对话备份
- 当前会话涉及项目的 git 指针信息
- 其他 skill 通过 contract 导出的 portable 状态

## 适用场景

- 你准备离开当前设备
- 你希望在另一台设备继续当前任务
- 你想把当前阶段性成果固化为一个可恢复的 workspace

## 执行前要求

- 相关 git 项目工作区必须是干净的
- 当前分支必须已经配置 upstream
- 本地提交必须已经推送到上游
- `workspace-sync` 已完成后端配置

## 执行时会做什么

1. 识别本次会话涉及到的 git 项目
2. 生成当前工作摘要
3. 校验项目状态是否满足同步要求
4. 记录每个项目的 `remote`、`upstream`、`branch`、`HEAD`
5. 导出其他 skill 的 portable 状态
6. 上传 workspace 到远端存储

## 常见失败原因

- 存在未提交改动
- 存在已暂存但未提交改动
- 当前分支没有 upstream
- 本地与 upstream 不同步
- 远端配置不完整

## 示例

```bash
/workspace-sync push feature-import
```
