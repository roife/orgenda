# orgenda

基于 SwiftUI 的 Org 文件工作区，提供任务议程、日历、日记、搜索和可交互的 Org 编辑与预览。

iPad 侧边栏上方提供 Calendar、Files、Search，下方 Dashboard 分组直接列出当前工作区可用的各个视图。侧边栏的显示方式及点选后的收起行为由 iPadOS 原生组件决定。顶部 Tab 栏通过同一个原生 Dashboard 分组呈现这些视图，切换侧栏时保留当前选择，无需增删 Tab 或改写选择状态。

iPad 支持横竖屏和可调整大小的窗口，顶层标签可切换为侧边栏。普通 iPad 布局的日历仅提供月、年视图；进入底部标签栏的紧凑布局时也可使用周视图。空间充足时日历与当天任务或日记并排显示，窄窗口和辅助大字体使用上下布局，高度不足时可滚动整页。文件列表与文档使用分栏导航，阅读和搜索内容保持合适的行宽。在仪表盘可用外接键盘的 `⌘N` 新建任务。

支持 Haptic Touch：长按议程条目可预览内容并使用快捷操作；长按文件或文件夹可预览内容、打开、移动或删除。日期选择、任务完成与保存、文件操作提供系统触觉反馈，实际振动效果需在支持触觉反馈的 iPhone 上体验。

## 存储与同步

在「设置 → 工作区与同步」选择一个存储位置：本机／系统文件夹、iCloud Drive、WebDAV，或直接登录 OneDrive、Google Drive、Dropbox。三家云盘使用 Orgenda 专属目录，支持电脑端新增和修改普通 Org 文件。云盘登录需要先配置发行者自己的 OAuth 应用；配置键、权限与真实服务验收步骤见 [云端存储说明](docs/CloudStorage.md)。

文件先可靠保存到本机，再同步到存储位置。已下载的文本可离线打开、编辑和新建；已缓存的图片可离线查看。移动、删除、恢复和跨文件归档需要存储位置可用并且待同步修改已处理。iCloud 的云端传输由系统管理，应用会区分本机保存与文件夹写入状态。

两端冲突时保留修改，由用户选择保留两份或使用其中一版；恢复副本位于「文件 → orgenda → Unsaved Edits」。更换存储位置不会自动搬移旧工作区；有待同步修改时可先保留本机副本。WebDAV 首版要求 HTTPS，并会测试服务器是否正确执行条件写入。

长按主屏幕上的 App 图标可直接新建任务、查看今天、搜索或打开文件列表。快捷操作会等待工作区加载完成；若已有编辑窗口，则在关闭该窗口后继续，保留当前草稿。

长按标题区域显示预览菜单；拖动左侧的文件图标或任务状态图标可移动文件或安排任务日期。Habit 预览显示与编辑页一致的 28 天完成记录。

## 从哪里开始

| 需要修改的内容 | 入口 |
| --- | --- |
| 应用启动、工作区生命周期和顶层导航 | `Orgenda/App`、`Orgenda/Features/Root` |
| 议程、日历与日记切换 | `Orgenda/Features/Agenda` |
| 项目编辑、计划日期、捕获模板 | `Orgenda/Features/ItemEditor`、`Orgenda/Domain/Org` |
| 文件浏览、源码编辑与预览 | `Orgenda/Features/Files` |
| 搜索与设置 | `Orgenda/Features/Search`、`Orgenda/Features/Settings` |
| 跨页面使用的控件 | `Orgenda/Components` |
| 颜色、动效、布局与日期展示 | `Orgenda/DesignSystem` |
| 数据结构、Org 规则与日期计算 | `Orgenda/Domain` |
| 文件读写、索引、图片加载与通知 | `Orgenda/Services` |
| 离线快照、同步队列、WebDAV 与云盘登录 | `Orgenda/Services/Storage` |
| Tree-sitter 语法与 Swift 封装 | `Packages/OrgTreeSitter` |

目录边界、状态归属和扩展方式见 [架构说明](docs/Architecture.md)。

## 构建

需要 Xcode 27、iOS 27 Simulator，以及 [XcodeGen](https://github.com/yonaskolb/XcodeGen)。

```sh
xcodegen generate --spec project.yml
open Orgenda.xcodeproj
```

`project.yml` 是项目配置的来源，生成后的 Xcode 工程一并提交。新增、移动源码或修改构建设置后重新生成工程；构建设置应先写入 YAML，避免下次生成时丢失。

命令行构建（可将设备名替换为本机已安装的模拟器）：

```sh
xcodebuild -project Orgenda.xcodeproj -scheme Orgenda \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  build CODE_SIGNING_ALLOWED=NO
```

## 验证

单元测试按被测代码的职责放在 `OrgendaTests` 对应目录：

```sh
xcodebuild -project Orgenda.xcodeproj -scheme Orgenda \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:OrgendaTests test CODE_SIGNING_ALLOWED=NO
```

界面测试覆盖日期选择、日历切换、任务编辑、搜索、文件同步和导航：

```sh
xcodebuild -project Orgenda.xcodeproj -scheme Orgenda \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:OrgendaUITests test CODE_SIGNING_ALLOWED=NO
```

iPad 专项回归覆盖旋转、不同窗口尺寸、完整月历显示、分栏文件编辑和搜索导航。尺寸用例在全屏模拟器中以 760×480 和 600×600 视口渲染真实界面：

```sh
xcodebuild -project Orgenda.xcodeproj -scheme Orgenda \
  -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)' \
  -only-testing:OrgendaUITests/IPadLayoutUITests test CODE_SIGNING_ALLOWED=NO
```

解析器可以独立验证：

```sh
swift test --package-path Packages/OrgTreeSitter
```

真实数学语料审计需要显式启用和准备数据，默认会跳过；具体条件写在 `OrgendaTests/Integration/OrgMathCorpusAuditTests.swift` 中。日常界面调试可为运行方案添加 `--demo-workspace` 参数。
