# clean

## 命令

```bash
/workspace-sync clean <workspace-name>
/workspace-sync clean --all
```

## 作用

删除远端 workspace，并清理本地 staging 缓存及待导入状态缓存。

## 适用场景

- 某个 workspace 已经过期，不再需要保留
- 你想清理测试数据
- 你要重建一套更干净的 workspace 集合

## 执行时会做什么

- 删除指定 workspace，或删除当前 backend 下的全部 workspace
- 清理本地相关缓存
- 在执行删除前要求二次确认

## 注意事项

- `clean --all` 会清空当前后端下的全部 workspace
- 这是破坏性操作，执行前应确认远端中没有仍需保留的数据

## 示例

```bash
/workspace-sync clean feature-import
/workspace-sync clean --all
```
