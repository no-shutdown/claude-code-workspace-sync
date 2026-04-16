# Skill State Contract

`workspace-sync` 不为任何 skill 做专用适配。
如果一个 skill 需要把自己的“工作现场状态”纳入跨设备同步，就必须自己暴露一个标准契约文件：

```text
workspace-sync.contract.json
```

放置位置：

```text
~/.claude/skills/<skill-name>/workspace-sync.contract.json
```

## 目标

这个契约只解决两件事：

- 告诉 `workspace-sync` 哪些状态允许跨设备迁移
- 告诉 `workspace-sync` 这些状态该如何导出和导入

它不解决这些事情：

- 不猜 skill 的内部目录结构
- 不扫描 `.sdd`、`.ccb`、`.cache` 之类的私有目录
- 不判断哪些文件“看起来像是重要状态”
- 不替 skill 做兼容性适配

结论很简单：
`workspace-sync` 只编排，skill 自己定义边界并负责实现。

## 两档迁移模式

`workspace-sync` 支持两种工作模式，**优先使用 `sync_paths`**，只有在需要自定义逻辑时才使用脚本。

### 模式一：`sync_paths`（推荐）

直接声明哪些相对路径需要同步，`workspace-sync` 框架自动完成 tar 打包和原子提取，**不需要编写任何导出/导入脚本**。

```json
{
  "contract_version": 1,
  "skill": "sdd",
  "states": [
    {
      "name": "project-state",
      "scope": "project",
      "portability": "portable",
      "sync_paths": [
        ".sdd/specs",
        ".sdd/tasks/current.json"
      ]
    }
  ]
}
```

适用于：把若干固定的文件或目录原封不动地搬到另一台设备的大多数场景。

### 模式二：`export_command` / `import_command`（自定义脚本）

当需要以下逻辑时才使用：
- 路径转换（绝对路径 → 相对路径）
- 索引重建
- schema 版本迁移
- 过滤部分文件

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
    }
  ]
}
```

**自定义脚本的 stdout 约束**：`workspace-sync` 框架通过 stdout 捕获 runner 的 JSON 结果。脚本的进度日志、调试信息**必须写到 stderr**，不得写 stdout，否则会污染 runner 的 JSON 输出，导致框架无法解析结果。

### 两种模式的对比

| | `sync_paths` | 自定义脚本 |
|---|---|---|
| 实现成本 | 零，只写 JSON | 需编写 bash 脚本 |
| 适用场景 | 固定路径的文件复制 | 需要转换/过滤/重建逻辑 |
| global scope | 不支持 | 支持 |
| 原子性 | 内置保证 | 脚本自己负责 |

---

## 契约格式

最小可用格式（`sync_paths` 模式）：

```json
{
  "contract_version": 1,
  "skill": "sdd",
  "description": "同步 SDD 的项目工作现场，不同步本机缓存和运行态",
  "states": [
    {
      "name": "project-state",
      "description": "当前项目的 spec / task / plan 状态",
      "scope": "project",
      "portability": "portable",
      "sync_paths": [
        ".sdd/specs",
        ".sdd/tasks/current.json"
      ]
    },
    {
      "name": "daemon-cache",
      "description": "本机 daemon 运行缓存",
      "scope": "global",
      "portability": "nonportable"
    }
  ]
}
```

兼容性规则：

- 当前 `contract_version` 固定为 `1`
- `workspace-sync` 只依赖本文档声明的必需字段
- 未识别的额外字段应被忽略，不应导致失败

## 字段约束

### 顶层字段

必需字段：

- `contract_version`
  固定为 `1`
- `skill`
  skill 名称，应与 skill 目录名一致
- `states`
  该 skill 暴露给 `workspace-sync` 的状态列表

推荐字段：

- `description`
  一句话说明这个 contract 的边界，方便人工排查

### `states[]` 字段

每个 state 都必须声明：

- `name`
  稳定标识符。建议短、稳定、可读，例如 `project-state`、`workspace-index`
- `scope`
  取值只能是 `project` 或 `global`
- `portability`
  取值只能是 `portable` 或 `nonportable`

推荐声明：

- `description`
  一句话说明这个 state 存的是什么

当 `portability=portable` 时，必须额外提供以下之一（二选一）：

- `sync_paths`（推荐）：路径列表，框架自动完成 tar/untar
- `export_command` + `import_command`：自定义脚本，处理复杂迁移逻辑

两者同时提供时，`export_command`/`import_command` 优先。

当 `portability=nonportable` 时：

- 不应提供 `export_command`、`import_command` 或 `sync_paths`
- `workspace-sync` 不会尝试导出或导入它

## 语义规则

### 1. `scope` 和 `portability` 是两个正交维度

- `scope=project`
  表示状态绑定某个具体项目工作区
- `scope=global`
  表示状态绑定当前设备上的 skill 全局环境
- `portability=portable`
  表示这个状态允许跨设备迁移
- `portability=nonportable`
  表示这个状态只适合留在本机

典型组合：

- `project + portable`
  例如某个项目的 spec、task、checklist、索引元数据
- `project + nonportable`
  例如某个项目的本机临时缓存、锁文件、socket
- `global + portable`
  例如与设备无关的全局模板索引或可重建配置
- `global + nonportable`
  例如 daemon 进程状态、机器绑定绝对路径、认证缓存

### 2. 什么应该标成 `portable`

只有满足下面条件的状态，才应该考虑 `portable`：

- 跨设备恢复后仍然有意义
- 不依赖当前机器的进程状态
- 不依赖当前机器的绝对路径
- 不包含敏感凭证，或凭证不应被跨设备复制
- 丢失它会影响工作现场恢复，而不只是影响性能

### 3. 什么必须标成 `nonportable`

下面这些内容，默认都应是 `nonportable`：

- `pid`
- `lock`
- `sock`
- `tmp`
- daemon 运行态
- 机器绑定绝对路径缓存
- 认证 token / session
- 只为提速存在的本机 cache

### 4. `workspace-sync` 不理解 skill 私有格式

`workspace-sync` 只会做这些事：

- 读取 `workspace-sync.contract.json`
- 对 `portable` 状态调用 `export_command` / `import_command`
- 记录 `restored` / `skipped` / `missing` / `deferred`

它不会：

- 解读导出包内部结构
- 替你迁移目录结构
- 猜测哪些文件需要恢复

### 5. 兼容性判断由 skill 自己负责

如果导入前需要做这些判断：

- skill 版本校验
- 平台校验
- 目录存在性校验
- 索引重建
- schema 升级

这些都应该在 `import_command` 内部处理。

## 推荐的命令接口

当前 repo 里 `workspace-sync` 还没有把命令行参数完全固化成代码，但 contract 建议统一成下面这组参数。这样不同 skill 的实现会更一致，后续也更容易收敛成真正的标准接口。

这个 repo 现在已经提供了两个通用执行器,用于按 contract 查找 state 并调用对应脚本:

- [`scripts/run-skill-state-export.sh`](../scripts/run-skill-state-export.sh)
- [`scripts/run-skill-state-import.sh`](../scripts/run-skill-state-import.sh)

如果上层已经拿到了“workspace 名、stage 目录、项目映射”，还可以直接使用单个 skill 的编排器:

- [`scripts/export-skill-states.sh`](../scripts/export-skill-states.sh)
- [`scripts/import-skill-states.sh`](../scripts/import-skill-states.sh)

建议 contract 中的 `export_command` / `import_command` 写成”可执行文件路径”:

- 优先使用相对 skill 根目录的路径,例如 `./scripts/export-workspace-state.sh`
- 也可以是绝对路径或 `PATH` 里的命令名
- **必须是单一可执行路径，不能包含空格**（`bash ./scripts/export.sh` 这类 shell 片段会直接报错）

### `export_command`

推荐调用方式：

```bash
./scripts/export-workspace-state.sh \
  --workspace-name "<workspace-name>" \
  --state-name "<state-name>" \
  --scope project \
  --project-name "<project-name>" \
  --project-path "<project-path>" \
  --output-dir "<output-dir>"
```

对于 `global` state，可以不传 `--project-name` 和 `--project-path`。

推荐行为：

- 成功时退出码为 `0`
- 在 `--output-dir` 下写入导出产物
- 至少写一个 `manifest.json`
- 可以额外写一个或多个归档文件，例如 `state.tgz`
- 如果使用本 repo 的通用执行器,它会在调用前校验 contract 和 state，并在调用后校验产物

推荐输出目录结构：

```text
<output-dir>/
├── manifest.json
└── state.tgz
```

`manifest.json` 推荐包含：

```json
{
  "skill": "sdd",
  "state": "project-state",
  "scope": "project",
  "project": "shanks-manage",
  "format_version": 1,
  "artifacts": [
    "state.tgz"
  ]
}
```

### `import_command`

推荐调用方式：

```bash
./scripts/import-workspace-state.sh \
  --workspace-name "<workspace-name>" \
  --state-name "<state-name>" \
  --scope project \
  --project-name "<project-name>" \
  --project-path "<project-path>" \
  --input-dir "<input-dir>"
```

推荐行为：

- 成功恢复时退出码为 `0`
- 当前环境不满足恢复条件时，应明确报错并返回非零
- 不要部分覆盖后静默成功
- 导入过程应尽量幂等；重复导入同一份状态不应产生破坏性结果
- 如果使用本 repo 的通用执行器,它会在调用前校验 contract、scope 和输入产物完整性

## `workspace-sync` manifest 中的记录

推荐在 workspace 的 `manifest.json` 里记录：

```json
{
  "skill": "sdd",
  "state": "project-state",
  "scope": "project",
  "portability": "portable",
  "project": "shanks-manage",
  "status": "exported",
  "artifact": "skill-states/sdd/shanks-manage-project-state/state.tgz",
  "artifacts": [
    "skill-states/sdd/shanks-manage-project-state/manifest.json",
    "skill-states/sdd/shanks-manage-project-state/state.tgz"
  ]
}
```

其中：

- `status=exported`
  skill 成功导出了该状态
- `status=skipped`
  当前环境不适合导出，或该状态当前不存在
- `status=not_exported`
  该 workspace 没有启用该 skill 的状态同步
- `status=deferred`
  产物存在，但当前设备暂不导入

## 实际例子：SDD skill

下面给一个更贴近真实场景的例子。假设 `sdd` skill 的状态目录结构是：

```text
<project-root>/
└── .sdd/
    ├── specs/
    ├── tasks/
    │   └── current.json
    ├── cache/
    └── daemon/
```

边界判断：

- `.sdd/specs/`
  是工作现场的一部分，应该同步
- `.sdd/tasks/current.json`
  是当前任务上下文，应该同步
- `.sdd/cache/`
  只是本机缓存，不应同步
- `.sdd/daemon/`
  是运行态，不应同步

因此 contract 应这样写：

```json
{
  "contract_version": 1,
  "skill": "sdd",
  "description": "同步 SDD 项目工作现场，不同步本机 cache 和 daemon 状态",
  "states": [
    {
      "name": "project-state",
      "description": "项目内的 spec 和当前任务状态",
      "scope": "project",
      "portability": "portable",
      "export_command": "./scripts/export-workspace-state.sh",
      "import_command": "./scripts/import-workspace-state.sh"
    },
    {
      "name": "daemon-runtime",
      "description": "本机 daemon、锁和缓存",
      "scope": "global",
      "portability": "nonportable"
    }
  ]
}
```

对应的导出策略：

- 只打包 `.sdd/specs/` 和 `.sdd/tasks/current.json`
- 显式排除 `.sdd/cache/`、`.sdd/daemon/`、锁文件、临时文件

对应的导入策略：

- 校验目标项目路径存在
- 校验 `.sdd/` 基础目录可创建
- 解包 `state.tgz`
- 如果旧版本 schema 不兼容，在导入阶段转换或失败退出

完整参考文件见：

- [`examples/sdd/workspace-sync.contract.json`](../examples/sdd/workspace-sync.contract.json)
- [`examples/sdd/scripts/export-workspace-state.sh`](../examples/sdd/scripts/export-workspace-state.sh)
- [`examples/sdd/scripts/import-workspace-state.sh`](../examples/sdd/scripts/import-workspace-state.sh)

## 设计建议

- 如果一个状态丢失后只影响性能，不影响正确性，它更像 cache，应优先标为 `nonportable`
- 如果一个状态是工作现场的一部分，且跨设备后仍然有意义，才考虑标为 `portable`
- `name` 要稳定，不要把版本号、设备名、用户名放进 `name`
- export/import 脚本要自己做输入校验，不要假设上层一定传对
- 导入要优先保证“要么成功，要么明确失败”，不要留下半恢复现场
