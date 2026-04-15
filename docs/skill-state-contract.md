# Skill State Contract

`workspace-sync` 不为任何 skill 实现专用适配器。

要接入跨设备的 skill 状态同步，其他 skill 必须自己提供标准契约文件：

```text
workspace-sync.contract.json
```

放置位置：

```text
~/.claude/skills/<skill-name>/workspace-sync.contract.json
```

## 目标

这个契约只解决一件事：

- 告诉 `workspace-sync` 哪些 skill 状态是可移植的
- 告诉 `workspace-sync` 如何导出与导入这些状态

`workspace-sync` 不会：
- 猜目录结构
- 扫描 `.sdd` / `.ccb`
- 推断哪些文件可以跨设备同步

---

## 契约格式

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

## 字段说明

### 顶层字段

- `contract_version`
  - 当前固定为 `1`
- `skill`
  - skill 名称
- `states`
  - 该 skill 向 `workspace-sync` 暴露的状态列表

### states 字段

每一项都必须包含：

- `name`
  - 状态名，供 manifest 和恢复报告引用
- `scope`
  - `project`：项目级状态
  - `global`：skill 全局状态
- `portability`
  - `portable`：允许跨设备导出/导入
  - `nonportable`：不允许跨设备同步

当 `portability=portable` 时，允许提供：

- `export_command`
- `import_command`

---

## 标准规则

### 1. `scope` 和 `portability` 必须同时声明

因为：
- `project/global` 只表示作用域
- `portable/nonportable` 只表示可迁移性

两者是正交的。

例如：
- `project + portable`：可以同步
- `project + nonportable`：不能同步
- `global + portable`：可以同步
- `global + nonportable`：不能同步

### 2. `nonportable` 一律不得导出

典型 `nonportable` 内容：
- `pid`
- `lock`
- `sock`
- `tmp`
- daemon 状态
- 机器绑定的绝对路径
- 本机进程运行状态

### 3. `workspace-sync` 只编排，不理解格式

`workspace-sync` 只会：
- 读取 contract
- 调用 export/import
- 记录结果
- 在 pull 后汇报 `restored / skipped / missing / deferred`

它不会理解导出包内部结构。

### 4. skill 自己负责兼容性判断

如果某个 skill 的导入需要：
- 版本校验
- 平台校验
- 目录存在性校验
- 重建索引

都应在 skill 自己的 `import_command` 中处理。

---

## export / import 的预期行为

### export_command

输入建议由 `workspace-sync` 提供：
- 当前 workspace 名
- 当前项目路径或项目标识
- 导出目录

输出：
- 一个或多个归档文件
- 供 `workspace-sync` 写入 manifest 的结果

### import_command

输入建议由 `workspace-sync` 提供：
- 当前项目路径或目标路径
- 对应导出归档路径
- 当前 workspace 名

输出：
- 成功：记为 `restored`
- 不满足条件：记为 `skipped`
- 缺少 skill / 无法立即导入：记为 `deferred`

---

## manifest 中的记录方式

推荐在 workspace 的 `manifest.json` 中记录：

```json
{
  "skill": "sdd",
  "state": "project-state",
  "scope": "project",
  "portability": "portable",
  "project": "my-api",
  "status": "exported",
  "artifact": "skill-states/sdd/my-api-project-state.tgz"
}
```

---

## 建议

- 如果一个状态丢失后只影响性能，不影响正确性，它更像 cache，应优先标为 `nonportable`
- 如果一个状态是工作现场的一部分，且跨设备后仍有意义，才考虑标为 `portable`
- 不要把 `workspace-sync` 当成 skill 私有内部目录的兜底备份器
