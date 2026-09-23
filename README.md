# orgenda

基于 SwiftUI 的 Org 文件工作区，提供任务议程、日历、日记、搜索和可交互的 Org 编辑与预览。

支持 Haptic Touch：长按议程条目可预览内容并使用快捷操作；长按文件或文件夹可预览内容、打开、移动或删除。日期选择、任务完成与保存、文件操作提供系统触觉反馈，实际振动效果需在支持触觉反馈的 iPhone 上体验。

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

解析器可以独立验证：

```sh
swift test --package-path Packages/OrgTreeSitter
```

真实数学语料审计需要显式启用和准备数据，默认会跳过；具体条件写在 `OrgendaTests/Integration/OrgMathCorpusAuditTests.swift` 中。日常界面调试可为运行方案添加 `--demo-workspace` 参数。
