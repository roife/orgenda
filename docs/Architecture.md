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
| `Packages/OrgTreeSitter` | Org 语法、外部 scanner 与 Swift 封装；运行时依赖官方 TreeSitter 包 |

## 状态与数据流

`OrgendaRootView` 持有 `WorkspaceStore`，负责顶层导航、快捷操作和工作区生命周期。`WorkspaceStore` 在主 actor 上按路径维护文档、本机 blob 基线、解析结果、议程集合和保存状态，同步状态订阅自 `SyncEngine`；按职责拆分的扩展仍属于同一个 store。文档数组是按需生成的界面投影，保存和单文件索引直接按路径查找。

页面负责交互状态和未保存草稿，通过 store 执行内容变更。日历中的任务与日记共用 `AgendaCalendarView`；日记内容和输入由 `JournalDayContent`、`JournalComposer` 提供。`OrgDocumentView` 协调源码编辑器、交互预览与大纲定位，`OrgEditorSession` 保留文本视图和撤销历史。

搜索用 `.task(id:)` 随查询、范围和工作区内容变化取消并重启防抖任务。捕获表单将输入与预览分开保存；预览同时记录生成文本、目标文件基线、配置版本和工作区身份，提交时核对同一份快照。`App/WorkspaceStore+Preview.swift` 仅在 Debug 编译，用于 `--demo-workspace` 手动调试。

`OrgIndexService` 在独立 actor 上解析文档，生成带 UTF-8 字节范围的快照；任务和日记条目复用同一棵语法树，文件变化时只更新该文件的结果。编辑器高亮独立解析当前文本，并复用该次解析修正工作流关键词，不再调用完整工作区索引。异步索引发布前核对解析代次与源码，避免旧结果覆盖较新的编辑。同步解析入口用于测试和需要等待索引的操作。

`OrgSourceMutation`、`OrgWorkflowOperations` 等领域代码根据源码位置修改目标文本。预览中的操作复用这些变更入口；新增变更应继续核对原始内容、保留相邻结构和换行约定。

新生成的 Org 日期统一通过 `Date.orgDateText` 与 `Date.orgTimestamp` 输出，使用公历和英文星期名；编辑已有时间戳仍由 planning draft 保留原有拼写、警告与重复规则。

## 保存与同步

`LocalStore` actor 持有不可变 `blobs/<sha256>` 与 `state.sqlite`。状态库包含 `files`、`drafts`、`conflicts`、`ops`、`trash`、`attachments`、`meta`；SQLite WAL 配合 `synchronous=FULL`，事务提交是唯一提交点。blob 在提交前写入，事务失败保留上一版状态；没有被引用的新 blob 可稍后清理。普通保存和上传确认只提交单文件补丁，避免复制整个文件表或重写全量状态。

文件使用本机 UUID。`files` 索引逻辑路径、远端路径及规范化后的大小写路径；草稿和冲突关联稳定文件 ID，正文通过 blob 引用保存。离线操作记录顺序及前置版本，逻辑路径立即反映本机意图，远端路径在回放确认后前移。状态格式直接使用 SQLite，不读取或迁移旧 manifest，也不自动删除旧缓存。

`SyncEngine` 合并同步请求，统一管理退避、服务器 Retry-After、网络恢复、前台刷新与定时拉取。编辑后的同步仅推送 pending；进入前台、手动、定时及条件写入失败时拉取。`LocalStore` 的变更流携带修订号与变化路径，Store 按修订号读取文本增量；超过增量保留窗口时回退到完整快照。blob LRU 缓存最多 16 MiB / 4096 项，磁盘读入时校验哈希。

推送逐路径确认，单文件失败保留队列并允许其他路径继续；离线、认证失败和服务器限流按全局失败处理。WebDAV 最多并发 4 个请求，强 PUT ETag 可直接确认写入，其余情况读回校验。完整目录扫描中的异常子树显式隔离并保留旧缓存，不能把不完整枚举当成删除。文件夹扫描以资源身份、mtime、size 跳过未变化文件；`NSFilePresenter` 和 iCloud `NSMetadataQuery` 触发定向读取，定时扫描负责补充核对。

移动、删除、恢复先在本机事务中入队，回放仍使用不覆盖目标的操作及内容/版本前置条件；冲突保留本机内容。跨文件 refile 在一个事务中提交两份草稿，源文件以目标文件的稳定 ID 和确切 blob 为依赖，先确认目标再上传源文件。目标在中断后改变时保留源端内容，避免重试重复追加。三方文本合并只接受互不重叠的字节精确行修改，重叠修改交由用户处理。

WebDAV 的路径身份不能证明所有远端改名；只有后端稳定 ID，或唯一且未变化的版本与 blob，才用于跟踪改名。无法唯一识别时保守地保留草稿并报告冲突。配置与实际存储位置验收见 [存储与同步说明](Storage.md)，可重复基准见 [基准数据](StorageBenchmark.json)。

## 扩展与验证

页面专用代码放在对应 feature；多个页面实际复用后再移到 `Components`。领域规则和源码处理放在 `Domain`，文件与网络操作放在 `Services`。数据安全回归放在 `OrgendaTests`，导航和手势通过 `--demo-workspace` 手动验证。

数学公式由语法树的 `latex_fragment`（`$…$`、`\(…\)`）和 `latex_block`（`$$…$$`、`\[…\]`、白名单环境）识别。外部 scanner 匹配完整公式和同名嵌套环境，公式内的 Org 标记保持 TeX 原文；源码块、行内 code/verbatim 和链接仍按字面量处理。预览从节点构造表达式，去除数学定界符，保留环境命令，由固定版本的 RaTeX 解析并通过 Core Graphics 绘制；不再改写 LaTeX。图片按模式、主题、字号、屏幕缩放和原始 LaTeX 缓存，行内基线采用 RaTeX 的 depth × 字号。编辑器也直接遍历数学节点进行高亮。

修改语法时编辑 `grammar.js` 或 `src/scanner.c`，在包目录执行 `npm ci && npm run generate`。CLI 固定为与运行时一致的 0.26.3，生成 ABI 15 的 `src/parser.c`，并保留生成器需要的 `src/grammar.json` 规则；不保留未使用的 `node-types.json`。运行时通过 SwiftPM 从官方 `tree-sitter/tree-sitter` 仓库解析，不再随源码维护副本。本地 `src/tree_sitter/` 是生成 parser/scanner 使用的支持头文件，来源与许可证见包内 `THIRD_PARTY_NOTICES.md`。

`project.yml` 是 Xcode 工程配置的来源。新增、删除或移动源码后使用 XcodeGen 重新生成工程，并运行 README 中相应的应用或解析器测试。
