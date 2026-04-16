# pull

## 命令

```bash
/workspace-sync pull <workspace-name>
```

## 作用

从远端下载指定 workspace，并在当前设备恢复工作上下文。

## 适用场景

- 在新设备继续之前的任务
- 恢复某个已保存的工作现场
- 把上下文、摘要和相关项目位置切回到保存时的状态

## 执行时会做什么

1. 从远端下载指定 workspace
2. 恢复 `summary.md` 和 `conversation.jsonl`
3. 根据记录的 git 信息定位本地项目
4. 尝试切换到保存时的分支和提交位置
5. 调用其他 skill 的标准 import 接口恢复 portable 状态

## 依赖条件

- 本地已安装 `workspace-sync`
- 已完成后端配置
- 本地能找到对应项目，或能够通过配置的扫描路径识别项目

## 注意事项

- `workspace-sync` 恢复的是已提交且已推送的代码位置
- 它不会替你恢复未提交的本地改动
- 如果某些 skill 未安装，对应状态可能被标记为 deferred

## 示例

```bash
/workspace-sync pull feature-import
```
