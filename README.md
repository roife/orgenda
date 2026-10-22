# orgenda

基于 SwiftUI 的 Org 文件工作区，提供任务议程、日历、日记、搜索和可交互的 Org 编辑与预览。

iPad 侧边栏上方提供 Calendar、Files、Search，下方 Dashboard 分组直接列出当前工作区可用的各个视图。侧边栏的显示方式及点选后的收起行为由 iPadOS 原生组件决定。顶部 Tab 栏通过同一个原生 Dashboard 分组呈现这些视图，切换侧栏时保留当前选择，无需增删 Tab 或改写选择状态。

Dashboard 顶部视图菜单和 iPad 侧边栏按工作区工作流顺序列出未完成状态（如 TODO、NEXT、SOMEDAY），保留概览、逾期和未安排视图。状态视图包含对应状态的所有未完成任务，包括已安排日期的任务；名称和图标跟随工作流设置。

iPad 支持横竖屏和可调整大小的窗口，顶层标签可切换为侧边栏。普通 iPad 布局的日历仅提供月、年视图；进入底部标签栏的紧凑布局时也可使用周视图。空间充足时日历与议程时间线并排显示，窄窗口和辅助大字体使用上下布局，高度不足时可滚动整页。文件列表与文档使用分栏导航，阅读和搜索内容保持合适的行宽。在仪表盘可用外接键盘的 `⌘N` 新建任务。

日记按天显示在议程任务下方。轻点日历 + 新建任务，长按直接新建日记。

支持 Haptic Touch：长按议程条目可预览内容并使用快捷操作；长按文件或文件夹可预览内容、打开、移动或删除。日期选择、任务完成与保存、文件操作提供系统触觉反馈，实际振动效果需在支持触觉反馈的 iPhone 上体验。

文件页提供「置顶」「最近使用」和「所有文件」分组。长按或向右轻扫文件、文件夹可置顶或取消置顶；最近使用按打开顺序保留最近 10 个文档。记录按工作区保存在本机，移动文件后继续保留，删除的项目自动隐藏，恢复后重新显示。

每个文件会在本机记住上次阅读位置，重新打开或重启应用后继续阅读。Preview 与 Edit 切换时按源码位置同步到对应内容；从大纲、任务或搜索主动跳转时优先显示目标位置。

## 存储与同步

在「设置 → 工作区与同步」通过系统「文件」App 选择文件夹，或连接 WebDAV。系统文件夹可位于本机或 iCloud Drive；工作区需要授予整个目录的访问权限。接入方式与验收步骤见 [存储与同步说明](docs/Storage.md)。

文件先可靠保存到本机，再同步到存储位置。已下载的文本可离线打开、编辑和新建；已缓存的图片可离线查看。移动、删除、恢复和跨文件归档需要存储位置可用并且待同步修改已处理。iCloud 的云端传输由系统管理，应用会区分本机保存与文件夹写入状态。

两端冲突时保留修改，由用户选择保留两份或使用其中一版；恢复副本位于「文件 → orgenda → Unsaved Edits」。更换存储位置不会自动搬移旧工作区；有待同步修改时可先保留本机副本。WebDAV 要求 HTTPS，并会测试服务器是否正确执行条件写入。

长按主屏幕上的 App 图标可直接新建任务、查看今天、搜索或打开文件列表。快捷操作会等待工作区加载完成；若已有编辑窗口，则在关闭该窗口后继续，保留当前草稿。

长按标题区域显示预览菜单；拖动左侧的文件图标或任务状态图标可移动文件或安排任务日期。Habit 预览显示与编辑页一致的 28 天完成记录。

## 工作区配置

在设置首页直接进入「工作流」「Capture 模板」「文件与议程」。
工作流包含状态、图标／色板、日志和选择键；文件与议程包含来源和目标路径。
提醒开关、权限和时间统一在「提醒」页。主题、Dashboard 布局、
标签与优先级样式及应用快捷键保持内置行为，不提供定制。
工作区设置修改后自动保存；状态和模板使用原生列表排序控件，把手始终显示在行末，可直接拖动。长按状态可移动分组或删除。输入无效或保存失败时会保留修改，离开页面时可继续编辑、重试保存或放弃。
配置保存在工作区根目录的 `config.json`，先保存到本机，再随文件同步。
本机外观和通知开关立即生效；提醒时间规则随工作区共享，并提供实际触发时间预览。
无配置时使用通用 TODO/DONE 默认规则。「经典工作流预设」仅替换任务状态、状态样式、状态历史和默认操作，不覆盖模板、文件位置或提醒规则。
文件与议程提供路径选择、匹配文件和归档目标预览。
设置中可复制从 Emacs 提取配置的 prompt，再导入或粘贴检查过的 JSON，验证通过后自动保存；应用不上传 Emacs 配置。
格式、支持范围及示例见 [配置说明](docs/Configuration.md)。

## 开发入口

| 需要修改的内容 | 入口 |
| --- | --- |
| 应用启动、工作区生命周期和顶层导航 | `Orgenda/App`、`Orgenda/Features/Root` |
| 议程、日历与每日日记 | `Orgenda/Features/Agenda` |
| 项目编辑、计划日期、捕获模板 | `Orgenda/Features/ItemEditor`、`Orgenda/Domain/Org` |
| 文件浏览、源码编辑与预览 | `Orgenda/Features/Files` |
| 搜索与设置 | `Orgenda/Features/Search`、`Orgenda/Features/Settings` |
| 跨页面使用的控件 | `Orgenda/Components` |
| 颜色、动效、布局与日期展示 | `Orgenda/DesignSystem` |
| 数据结构、Org 规则与日期计算 | `Orgenda/Domain` |
| 文件读写、索引、图片加载与通知 | `Orgenda/Services` |
| 离线快照、同步队列、WebDAV 与系统文件夹访问 | `Orgenda/Services/Storage` |
| Tree-sitter 语法与 Swift 封装 | `Packages/OrgTreeSitter` |

目录边界、状态归属和扩展方式见 [架构说明](docs/Architecture.md)。

## 构建

需要 Xcode 27、iOS 27 Simulator，以及 [XcodeGen](https://github.com/yonaskolb/XcodeGen)。

```sh
xcodegen generate --spec project.yml
open Orgenda.xcodeproj
```

`project.yml` 是唯一的项目配置来源，生成的 `Orgenda.xcodeproj` 已加入 `.gitignore`。首次克隆，以及新增、移动源码或修改构建设置后，先运行上面的 XcodeGen 命令；构建设置统一写入 YAML。

配置模型使用 MetaCodable 宏生成编解码代码。首次打开项目时，在 Xcode 的宏提示中启用 MetaCodable 的 `MacroPlugin`，再运行命令行构建或测试。

命令行构建（可将设备名替换为本机已安装的模拟器）：

```sh
xcodebuild -project Orgenda.xcodeproj -scheme Orgenda \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  build CODE_SIGNING_ALLOWED=NO
```

## 验证

只保留容易改错、且失误会丢失或破坏用户数据的回归测试，放在 `OrgendaTests` 对应目录：

- 离线草稿恢复、同步冲突、上传和移动中断后的恢复，以及并发编辑。
- 旧版本写入保护、文件夹切换时保留草稿、不完整快照与路径越界。
- Org 源文字节边界、子树移动、重复任务修改的原子性与日期计算。
- 中文输入组合过程与撤销，避免高亮刷新打断输入。

展示、布局、导航、常规读写、性能计数、通知与调度机制，以及重复覆盖不保留自动化测试。新增测试必须对应具体的数据丢失、错误覆盖或源码破坏风险；修复过问题本身不构成保留测试的理由。

```sh
xcodebuild -project Orgenda.xcodeproj -scheme Orgenda \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:OrgendaTests test CODE_SIGNING_ALLOWED=YES \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM=''
```

模拟器测试使用临时签名，不需要发行证书。关闭签名后，增量构建的 XCTest runner 可能保留无效签名，导致测试在启动前退出；仅构建应用时仍可使用 `CODE_SIGNING_ALLOWED=NO`。

界面改动使用独立测试工作区手动检查；涉及 iPad 布局时检查旋转、窄窗口与辅助大字体。

解析器只保留源码边界回归：嵌入空字符不能截断文档，源码块和嵌套公式必须正确结束，未闭合公式不能吞掉后续标题。可以独立验证：

```sh
swift test --package-path Packages/OrgTreeSitter
```

日常界面调试使用独立测试工作区，通过正常启动和文件夹连接流程加载测试数据。
