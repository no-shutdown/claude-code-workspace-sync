# list

## 命令

```bash
/workspace-sync list
```

## 作用

列出当前后端中已经保存的 workspace，并在列出后允许你直接选择一个继续恢复，不需要再手动输入一次 `pull`。

## 适用场景

- 你忘了之前保存过哪些 workspace
- 你需要确认远端是否已经存在某个 workspace
- 你准备执行 `pull` 或 `clean`
- 你想先看列表，再从里面挑一个继续当前工作

## 执行结果

通常会展示：

- 序号
- workspace 名称
- 版本信息
- 创建时间或最近更新时间

列出后，Claude 应继续提示你：

- 回复序号继续
- 回复 workspace 名称继续
- 回复 `cancel` 只查看不恢复

## 示例

```bash
/workspace-sync list
```

看到列表后，可以直接回复：

```text
2
```

或者：

```text
feature-import
```

Claude 应把这次选择直接当作：

```bash
/workspace-sync pull feature-import
```
