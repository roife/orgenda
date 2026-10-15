# 架构说明

Org 文件是工作区的内容来源。界面、索引和存储围绕同一份源码协作，编辑时保留未知语法和未修改的文本。

## 目录与职责

| 目录 | 职责 |
| --- | --- |
| `Orgenda/App` | 应用入口、系统快捷操作和显式启用的开发用数据 |
| `Orgenda/Features` | 页面、导航、编辑草稿和页面专用的预览组件 |
| `Orgenda/Components` | 跨页面使用的日历、文本编辑器、手势与工作流控件 |
| `Orgenda/DesignSystem` | 颜色、字体、日期展示、布局、动效与触觉反馈 |
| `Orgenda/Domain` | 数据模型、配置校验、Org 日期规则与源码变更 |
| `Orgenda/Services` | 工作区状态、索引、文件访问、同步、图片加载与通知 |
| `Packages/OrgTreeSitter` | Org 语法、外部 scanner、Tree-sitter 运行时与 Swift 封装 |

## 状态与数据流

`OrgendaRootView` 持有 `WorkspaceStore`，负责顶层导航、快捷操作和工作区生命周期。`WorkspaceStore` 在主 actor 上维护文档、解析结果、议程集合和保存状态；按职责拆分的扩展仍属于同一个 store。

页面负责交互状态和未保存草稿，通过 store 执行内容变更。日历中的任务与日记共用 `AgendaCalendarView`；日记内容和输入由 `JournalDayContent`、`JournalComposer` 提供。`OrgDocumentView` 协调源码编辑器、交互预览与大纲定位，`OrgEditorSession` 保留文本视图和撤销历史。

搜索用 `.task(id:)` 随查询、范围和工作区内容变化取消并重启防抖任务。捕获表单将输入与预览分开保存；预览同时记录生成文本、目标文件基线、配置版本和工作区身份，提交时核对同一份快照。`App/WorkspaceStore+Preview.swift` 仅在 Debug 编译，用于 `--demo-workspace` 手动调试。

`OrgIndexService` 在独立 actor 上解析文档，生成带 UTF-8 字节范围的快照；任务和日记条目复用同一棵语法树，文件变化时只更新该文件的结果。编辑器高亮独立解析当前文本，并复用该次解析修正工作流关键词，不再调用完整工作区索引。异步索引发布前核对解析代次与源码，避免旧结果覆盖较新的编辑。同步解析入口用于测试和需要等待索引的操作。

`OrgSourceMutation`、`OrgWorkflowOperations` 等领域代码根据源码位置修改目标文本。预览中的操作复用这些变更入口；新增变更应继续核对原始内容、保留相邻结构和换行约定。

新生成的 Org 日期统一通过 `Date.orgDateText` 与 `Date.orgTimestamp` 输出，使用公历和英文星期名；编辑已有时间戳仍由 planning draft 保留原有拼写、警告与重复规则。

## 保存与同步

`WorkspaceStore` 只持有一个 `WorkspaceSession`，维护界面状态、编辑基线与同步状态。文档和图片读写、恢复副本、移动与同步统一交给 Session。`WorkspaceSession` 使用本机 blob 与 manifest 保存文档、待上传修改和冲突，再通过 `WorkspaceFileStore` 访问系统文件夹，或通过 `RemoteWorkspaceBackend` 同步远端。

每个 session 的后端由互斥的 `Source` 枚举表示，必须是文件夹或远端之一。草稿同步与跨文件移动复用同一个条件上传入口，统一核对目标路径和返回文件类型。

界面的保存状态区分本机保存和存储位置写入。工作区更换、文件移动、归档与冲突处理沿用现有恢复副本和源码核对流程。WebDAV 与系统文件夹实现位于 `Services/Storage`，配置及实际存储位置验收见 [存储与同步说明](Storage.md)。

## 扩展与验证

页面专用代码放在对应 feature；多个页面实际复用后再移到 `Components`。领域规则和源码处理放在 `Domain`，文件与网络操作放在 `Services`。数据安全回归放在 `OrgendaTests`，导航和手势通过 `--demo-workspace` 手动验证。

修改语法时编辑 `grammar.js` 或 `src/scanner.c`；`src/parser.c`、`src/grammar.json` 和 `src/node-types.json` 由 Tree-sitter 生成。第三方运行时位于 `Vendor/tree-sitter`，来源与许可证见包内 `THIRD_PARTY_NOTICES.md`。

`project.yml` 是 Xcode 工程配置的来源。新增、删除或移动源码后使用 XcodeGen 重新生成工程，并运行 README 中相应的应用或解析器测试。
