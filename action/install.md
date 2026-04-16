# install

## 命令

```bash
./install.sh
./install.sh --target /path/to/skills/workspace-sync
./install.sh --no-init-config
```

## 作用

把当前仓库安装到本地 Claude Skills 目录，供 Claude Code 调用。

## 默认安装位置

```text
~/.claude/skills/workspace-sync
```

## 执行时会做什么

- 复制 skill 运行所需文件
- 在目标目录初始化基础结构
- 如果目标目录不存在 `config.json`，默认会按模板初始化

## 参数说明

- `--target`：指定自定义安装目录
- `--no-init-config`：跳过 `config.json` 初始化

## 适用场景

- 首次安装 `workspace-sync`
- 更新 skill 到新的本地目录
- 希望把 skill 安装到非默认路径

## 示例

```bash
./install.sh
./install.sh --target ~/.claude/skills/workspace-sync
```
