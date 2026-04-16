# uninstall

## 命令

```bash
./uninstall.sh
```

## 作用

从本地 Claude Skills 目录中移除已经安装的 `workspace-sync`。

## 适用场景

- 你不再使用该 skill
- 你准备重新安装
- 你要清理本地无用的 skill 目录

## 注意事项

- 卸载的是本地安装目录
- 如果你保留了配置、缓存或远端 workspace，这些内容通常不会因为卸载自动从远端一起删除

## 示例

```bash
./uninstall.sh
```
