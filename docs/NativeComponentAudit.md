# Orgenda 原生组件替代清单

优先替换文档模式切换的 UIKit 桥接、标题拖拽桥接、文件浏览的手工列表外观、计划编辑表单和大纲展开控件。月历、键盘工具条和源码编辑器涉及专门的交互要求，应先做替代原型。保留已经基于系统控件的业务封装。

审查日期为 2026 年 10 月 10 日，基于工作区当时的代码，包括已有未提交修改；基准提交为 c4d9734。完整通读 Components、DesignSystem、Features 及 App 顶层的 110 个 Swift 文件，共 15,858 行。另读图片加载服务及相关测试片段核对行为。范围不包括开发 fixture、第三方包实现、全部领域与存储代码。本文是源码审查清单；未改动应用源码，未运行替换原型或 UI 回归。

这里的“原生”包括 SwiftUI 与 UIKit。UIViewRepresentable 包装系统控件仍然是原生；替换它的价值在于减少桥接和同步代码。HStack、Canvas、Layout 使用系统基础能力，但仍可能自行实现了系统成品控件已有的行为。

## 建议优先替换

P1 表示优先实施或验证，P2 表示收益较小或布局取舍较多；它们是改造顺序，不是缺陷严重度。各项会重叠，不能把涉及文件行数相加当作可删除行数。

| 编号 | 顺序 | 组件和位置 | 原生替代 | 可以简化什么及保留条件 |
| --- | --- | --- | --- | --- |
| R01 | P1 | [OrgDocumentView.swift:208](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Document/OrgDocumentView.swift:208) 的 NativeModePicker | Picker + .pickerStyle(.segmented) | 当前只创建 UISegmentedControl、同步 index、设字体和无障碍信息，属于很薄的桥接。保留 modeBinding 内的 suspendEditing；大字体继续使用现有 menu 分支。验证工具栏宽度、模式切换后光标与滚动位置。 |
| R02 | P1 | [OrgHeadingDrag.swift:41](/Users/roifewu/.config/orgenda/Orgenda/Components/Gestures/OrgHeadingDrag.swift:41) 的 OrgHeadingDragSource；[DocumentOutline.swift:447](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Document/DocumentOutline.swift:447)、[OrgPreviewHeading.swift:51](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/OrgPreviewHeading.swift:51) 的透明覆盖层 | SwiftUI .draggable／.onDrag、.onDragSessionUpdated、.dragConfiguration | 本机 iOS 27 SDK 已有拖拽生命周期回调，原注释所述的“需要 UIKit 接收取消后的结束通知”值得重新验证。可去掉 UIView、UIDragInteractionDelegate、手工 UILabel 预览及透明点击转发。保留开始时源码快照校验、仅应用内拖动、结束清理和拖拽预览；覆盖成功、取消、拖出应用三条路径。现有 DropDelegate 已是原生，不必连带删除。 |
| R03 | P1 | [FilesView.swift:118](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/FilesView.swift:118)、[WorkspaceBrowser.swift:13](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/WorkspaceBrowser.swift:13)、[WorkspaceFileActions.swift:13](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/WorkspaceFileActions.swift:13) | List(selection:) + NavigationLink(value:) + .listStyle(.sidebar／.plain) | 当前手画分隔线、右箭头、选中底色，使用 Button 推导航，并为紧凑分栏补 preferredCompactColumn。让系统列表和链接管理这些展示与导航行为；保留文件树、路径请求、删除确认、拖放验证和快捷预览。左侧图标独立拖动与标题长按菜单须回归，不能直接让整个 NavigationLink 同时承担所有手势。 |
| R04 | P1 | [OrgPlanningEditorSheet.swift:24](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/OrgPlanningEditorSheet.swift:24)、[OrgPlanningEditorSheet.swift:129](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/OrgPlanningEditorSheet.swift:129) | Form + Section + DatePicker + Toggle + 现有 OrgRecurrenceEditor | DatePicker 本身已经原生；可替换的是外面的 ScrollView、卡片背景、标题、Divider 和人工间距。开始／结束分别放 Section，错误放 footer。前后一天按钮如需保留可放原生 Button 行。不得丢失范围、时间、重复规则和 trailingText 中的提醒偏移。 |
| R05 | P1 | [DocumentOutline.swift:214](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Document/DocumentOutline.swift:214)、[DocumentOutline.swift:408](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Document/DocumentOutline.swift:408) | List + 递归 DisclosureGroup(isExpanded:) | 可去掉手画箭头、旋转动画、空白占位及分隔线。保留 expandedHeadingIDs、过滤时强制展开、移动后的 ID 映射和标题点击定位。优先可绑定的 DisclosureGroup；直接套 OutlineGroup 无法自动满足现有展开状态控制。树形 before／after／child 移动仍需领域逻辑，不能拿 .onMove 当完整替代。 |
| R06 | P1 | [WorkspaceFileActions.swift:95](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/WorkspaceFileActions.swift:95)、[ConfigurationSettingsView.swift:112](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/ConfigurationSettingsView.swift:112)、[StorageConflictView.swift:113](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/StorageConflictView.swift:113) 等 | .alert(_:item:actions:message:)／.confirmationDialog(_:item:...) | SDK 已提供可绑定 Optional 数据的现代重载，可替换重复的 Binding(get: optional != nil, set: 清空 optional) 和另传 presenting。保留动作中的期望版本、错误信息与异步处理；这是状态连接的简化，弹窗本身已经是系统弹窗。 |
| R07 | P2 | [AgendaTaskLists.swift:8](/Users/roifewu/.config/orgenda/Orgenda/Features/Agenda/AgendaTaskLists.swift:8)、[AgendaTaskLists.swift:57](/Users/roifewu/.config/orgenda/Orgenda/Features/Agenda/AgendaTaskLists.swift:57)、[AgendaPerspectiveContent.swift:15](/Users/roifewu/.config/orgenda/Orgenda/Features/Agenda/AgendaPerspectiveContent.swift:15) | List + Section + 原有 OrgItemRow | 无日历联动的 Unscheduled、Overdue、Dashboard 可以交给系统管理行、组头、间距。保留多区域重复出现任务的稳定 ID。AgendaCalendarView 的连续日期时间线另行保留，它依赖可见日期与日历双向同步。现有滑动操作已原生，改 List 的理由不是“让 swipeActions 能用”。 |
| R08 | P2 | [OrgendaCalendar.swift:437](/Users/roifewu/.config/orgenda/Orgenda/Components/Calendar/OrgendaCalendar.swift:437)、[OrgendaCalendar.swift:562](/Users/roifewu/.config/orgenda/Orgenda/Components/Calendar/OrgendaCalendar.swift:562) | ScrollView + LazyVStack + .scrollTargetBehavior(.paging) | 周视图仍手算拖动距离、预测阈值、offset 和进出动画；可复用本文件月／年视图的原生分页做法。保留跨月周、selectedDate、Reduce Motion，以及内外纵向滚动的协调。月份和年份分页已经原生，无须重写。 |
| R09 | P2 | [AgendaView.swift:181](/Users/roifewu/.config/orgenda/Orgenda/Features/Agenda/AgendaView.swift:181) | .navigationTitle + .toolbarTitleMenu | 当前是原生 Menu 外加手拼标题及 chevron；若接受系统标题菜单的位置和样式，可以删掉标题外观代码。iPad sidebar 下继续使用当前透视名称；属于外观取舍，不是 Menu 用错。 |
| R10 | P2 | [AgendaDayContent.swift:18](/Users/roifewu/.config/orgenda/Orgenda/Features/Agenda/AgendaDayContent.swift:18)、[SearchSuggestionsView.swift:17](/Users/roifewu/.config/orgenda/Orgenda/Features/Search/SearchSuggestionsView.swift:17) | Button 的 .borderedProminent／.bordered + .buttonBorderShape(.capsule) + .tint | Overdue 胶囊、搜索标签按钮手配 padding、背景和 .plain。系统按钮样式可管理按下反馈和控件尺寸；标签颜色和字号可能变化。只适用于可点击标签，静态 OrgendaTagList 不应改成按钮。 |
| R11 | P2 | [OrgPreviewClockValue.swift:51](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Markup/OrgPreviewClockValue.swift:51)；[OrgPreviewDateText.swift:8](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Markup/OrgPreviewDateText.swift:8) | Duration 的 FormatStyle／Date.FormatStyle | 时长目前手拼 h、m；可使用系统本地化单位。日期部分可评估移除自建 DateFormatter 缓存，但必须保留 Gregorian 语义、同年省略年份及时间范围。Org 重复规则和提醒注释仍由应用解释。这是展示辅助逻辑的简化。 |
| R12 | P2 | [OrgItemEditor.swift:353](/Users/roifewu/.config/orgenda/Orgenda/Features/ItemEditor/OrgItemEditor.swift:353)、[OrgPreviewDrawer.swift:36](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/OrgPreviewDrawer.swift:36) | LabeledContent + Label | “File + 路径”和 “Clock + 时长”等信息对可交由原生信息行排版。保留多行路径、时间区间、文本选择及大字体；短代码收益有限，可随相关页面一起整理。 |

R02 的回调与拖动配置已在本机 SDK 中确认 iOS 27 可用，符合 project.yml 的最低版本。Apple 文档说明该回调用于 SwiftUI 拖动操作的更新；它不替代 Org 的树移动校验。[拖拽回调文档](https://developer.apple.com/documentation/swiftui/view/ondragsessionupdated(_:)), [拖动配置文档](https://developer.apple.com/documentation/swiftui/dragconfiguration)。

大纲的关键是是否需要控制展开状态：DisclosureGroup 支持 isExpanded 绑定，OutlineGroup 按树生成展开组；当前项目需要在过滤和移动后主动调整展开状态。[DisclosureGroup](https://developer.apple.com/documentation/swiftui/disclosuregroup), [OutlineGroup](https://developer.apple.com/documentation/swiftui/outlinegroup)。

## 需要先确认交互取舍的替代

| 编号 | 组件和位置 | 原生候选 | 判断和代价 |
| --- | --- | --- | --- |
| C01 | [OrgendaCalendar.swift:3](/Users/roifewu/.config/orgenda/Orgenda/Components/Calendar/OrgendaCalendar.swift:3)、[OrgendaCalendarDayGrid.swift:3](/Users/roifewu/.config/orgenda/Orgenda/Components/Calendar/OrgendaCalendarDayGrid.swift:3)、[OrgendaDateButton.swift:16](/Users/roifewu/.config/orgenda/Orgenda/Components/Calendar/OrgendaDateButton.swift:16) | UICalendarView + UICalendarSelectionSingleDate + 日期 decorations | 可以承接月历选择、事件点、地区日历和可见月份。若只需选日期，也可以 DatePicker(.graphical)，但它不能等价呈现现有事件标记。公开 UICalendarView 接口没有现有周／年密度变形和每个日期的拖放接口；不要依赖私有日期 cell 层级。若要求保留这些功能，当前自定义日历有理由存在。整组 8 文件共 1,790 行，是最大取舍项，不能承诺全部删除。 |
| C02 | [OrgendaCalendar.swift:296](/Users/roifewu/.config/orgenda/Orgenda/Components/Calendar/OrgendaCalendar.swift:296)、[OrgendaCalendarResizeContent.swift:14](/Users/roifewu/.config/orgenda/Orgenda/Components/Calendar/OrgendaCalendarResizeContent.swift:14)、[OrgendaCalendarResizePreview.swift:3](/Users/roifewu/.config/orgenda/Orgenda/Components/Calendar/OrgendaCalendarResizePreview.swift:3)、[OrgendaDateHeading.swift:34](/Users/roifewu/.config/orgenda/Orgenda/Components/Calendar/OrgendaDateHeading.swift:34) | “周／月／年” Picker(.segmented／.menu) + 普通系统动画 | 即使保留自定义日历网格，也可以单独放弃连续拖拽缩放。这样能去掉 density 拖动状态机、Canvas 过渡副本、尺寸插值和标题锚点移动。尺寸计算中仍被最终网格使用的部分要保留；切换方式与目前手势不同，不能当成无损清理。 |
| C03 | [OrgKeyboardAccessory.swift:7](/Users/roifewu/.config/orgenda/Orgenda/Components/Editor/OrgKeyboardAccessory.swift:7)、[OrgKeyboardAccessory.swift:70](/Users/roifewu/.config/orgenda/Orgenda/Components/Editor/OrgKeyboardAccessory.swift:70)、[OrgKeyboardAccessory.swift:113](/Users/roifewu/.config/orgenda/Orgenda/Components/Editor/OrgKeyboardAccessory.swift:113) | SwiftUI ToolbarItemGroup(placement: .keyboard)，或 UITextView.inputAccessoryView + UIToolbar | 优先验证系统工具条能否承接七个动作与键盘定位。当前已经使用 UIButton、UIMenu、UIGlassEffect、keyboardLayoutGuide；自定义部分是排列、浮动容器、68pt inset 和 hitTest。源码明确记录了 UIToolbar 在手机宽度下把末尾动作移入 overflow，测试要求各动作可见可点。若保留“七个动作同时可见、玻璃下继续滚动、边缘可点”要求，应保留必要包装。 |
| C04 | [SearchView.swift:38](/Users/roifewu/.config/orgenda/Orgenda/Features/Search/SearchView.swift:38)、[SearchView.swift:84](/Users/roifewu/.config/orgenda/Orgenda/Features/Search/SearchView.swift:84) | .searchScopes($scope, activation: .onSearchPresentation) | 可删除手工 scopeBar、额外顶部 inset 和“Search category”行。系统 scope bar 的显示由搜索激活策略决定，当前菜单在未搜索时也常驻，而且有七个类别；窄屏和大字体可能更适合现有原生 Menu。只有接受显示时机和布局变化才改。 |
| C05 | [SearchSuggestionsView.swift:11](/Users/roifewu/.config/orgenda/Orgenda/Features/Search/SearchSuggestionsView.swift:11) | .searchSuggestions + .searchCompletion | “Try a tag”确实是补全候选，适合原生 suggestion；Recent journal、Browse files、Browse Settings 是直接导航入口，应继续作为浏览内容。不能把整页统一改为 searchCompletion，否则会改变点击行为与非激活态内容。 |
| C06 | [SearchView.swift:226](/Users/roifewu/.config/orgenda/Orgenda/Features/Search/SearchView.swift:226) 的 SearchEmptyState | ContentUnavailableView.search(text:)／ContentUnavailableView(label:description:actions:) | 可以删掉手配 48pt 图标、标题和说明间距。但注释明确说明原生空状态在搜索激活、键盘缩放时会出现二次位置跳动。先在 iOS 27 复现该问题是否仍存在，再迁移；筛选范围和 Search All／Clear Search 按钮要保留。 |
| C07 | [OrgSyntaxTextEditor.swift:8](/Users/roifewu/.config/orgenda/Orgenda/Components/Editor/OrgSyntaxTextEditor.swift:8)、[OrgEditorSession.swift:7](/Users/roifewu/.config/orgenda/Orgenda/Components/Editor/OrgEditorSession.swift:7)、[OrgSyntaxPresentation.swift:5](/Users/roifewu/.config/orgenda/Orgenda/Components/Editor/OrgSyntaxPresentation.swift:5) | TextEditor 绑定 AttributedString + AttributedTextSelection | iOS 26 起已有富文本 TextEditor，所以不能用“SwiftUI 不支持富文本”作为永久保留理由。但当前承担 Tree-sitter 展示属性、中文 marked text 保护、Org 换行命令、统一撤销、外部修订清空历史、UTF-8／UTF-16 定位和模式切换恢复。先做行为原型；高亮与源码模型不会因换控件而消失。现有 UITextView + TextKit 2 已是原生编辑器。 |
| C08 | [OrgPreviewImageView.swift:171](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Images/OrgPreviewImageView.swift:171)、[OrgPreviewImageView.swift:192](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Images/OrgPreviewImageView.swift:192) | QuickLook 的 .quickLookPreview／QLPreviewController | 可以承接独立图片预览，但现状只持有降采样 UIImage；Quick Look 需要可访问的文件 URL。需要让加载服务提供原文件或管理临时导出及生命周期，不能假设 UIImage 可直接传入。当前 UIScrollView 原生缩放只用约 67 行，保持内存图像预览时未必值得换。 |
| C09 | [OrgItemEditor.swift:306](/Users/roifewu/.config/orgenda/Orgenda/Features/ItemEditor/OrgItemEditor.swift:306)、[JournalComposer.swift:26](/Users/roifewu/.config/orgenda/Orgenda/Features/Journal/JournalComposer.swift:26) | TextField(prompt:axis: .vertical) | 如果备注／日记定位是短多行输入，可移除 TextEditor 上方的手工占位文字和 8／5pt 偏移。长篇输入更适合当前 TextEditor；本机 SDK 的 TextEditor 初始化器没有 prompt 参数，不应虚构这个 API。 |
| C10 | [JournalComposer.swift:70](/Users/roifewu/.config/orgenda/Orgenda/Features/Journal/JournalComposer.swift:70)、[OrgItemEditor.swift:125](/Users/roifewu/.config/orgenda/Orgenda/Features/ItemEditor/OrgItemEditor.swift:125)、[ConfigurationEditors.swift:116](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/ConfigurationEditors.swift:116)、[OrgPlanningEditorSheet.swift:97](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/OrgPlanningEditorSheet.swift:97) | .dismissalConfirmationDialog | 本机 SDK 标记 iOS 27 可用，可验证是否适用于这些页面的系统关闭路径。Apple 文档区分用户发起关闭和代码 dismiss；iOS 上不能假设所有代码关闭或 NavigationStack 返回都会被拦截。非取消动作会允许关闭，因此不能直接替代“异步保存成功后再离开”的逻辑。保存失败保留草稿、主动 Cancel 按钮和移动态禁退仍须单独处理。 |

UICalendarView 提供日期选择、可见日期以及日期装饰；这些能力适合月历，但不足以证明它能覆盖当前所有自定义交互。[Apple 日历文档](https://developer.apple.com/documentation/uikit/uicalendarview)。

搜索 scope 的系统激活策略与常驻菜单不同；建议只迁移适合搜索补全的那部分内容。[搜索修饰符](https://developer.apple.com/documentation/swiftui/view-search), [scope 默认激活策略](https://developer.apple.com/documentation/swiftui/searchscopeactivation/automatic)。

富文本输入能力已由 Apple 示例确认；当前源码编辑器的撤销与输入法需求是本项目的额外条件。[原生富文本编辑示例](https://developer.apple.com/documentation/swiftui/building-rich-swiftui-text-experiences), [AttributedTextSelection](https://developer.apple.com/documentation/swiftui/attributedtextselection)。

Quick Look 以 URL 为输入。[Quick Look 文档](https://developer.apple.com/documentation/swiftui/view/quicklookpreview(_:))。系统关闭确认的触发条件和允许关闭的动作规则见 [关闭确认文档](https://developer.apple.com/documentation/swiftui/view/dismissalconfirmationdialog(_:shouldpresent:actions:message:))。

## 可以直接清理的未使用组件

D01：[OrgendaHorizontalPan.swift:6](/Users/roifewu/.config/orgenda/Orgenda/Components/Gestures/OrgendaHorizontalPan.swift:6) 共 48 行。全仓应用与测试搜索只找到定义，没有调用。建议删掉这个未使用的 UIGestureRecognizerRepresentable，并按仓库要求重新生成 Xcode 工程。当前日历与 Agenda／Journal 的分页并不依赖它，不需要找新的手势组件替代。

## 建议保留的封装

| 组件 | 已使用的系统能力 | 保留理由 |
| --- | --- | --- |
| [OrgRecurrenceEditor.swift:17](/Users/roifewu/.config/orgenda/Orgenda/Components/OrgRecurrenceEditor.swift:17) | Toggle、Stepper、Picker、LabeledContent | 自定义的是 Org 的 +、++、.+ 和 habit 最大间隔规则。系统 DatePicker 没有这些完整语义，也没有可直接代替的 Org 重复规则编辑器。 |
| [OrgWorkflowControls.swift:22](/Users/roifewu/.config/orgenda/Orgenda/Components/Workflow/OrgWorkflowControls.swift:22) | Picker(.menu)、Label、SF Symbols | 已经原生；状态颜色、符号与快捷键来自工作区配置。不要用 Bool Toggle 替代多状态工作流。 |
| [OrgItemRow.swift:39](/Users/roifewu/.config/orgenda/Orgenda/Components/OrgItemRow.swift:39)、[OrgPreviewHeading.swift:281](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/OrgPreviewHeading.swift:281) | Button、swipeActions、contextMenu、draggable | 完成操作可能推进重复任务日期，预览复选框需要写回源码，不能一概改 Bool 开关。本机 SDK 的 ToggleStyle.checkbox 不支持 iOS。需要完整勾选外观时保留小型 Button 封装。 |
| [OrgendaFlowLayout.swift:3](/Users/roifewu/.config/orgenda/Orgenda/DesignSystem/Layout/OrgendaFlowLayout.swift:3)、[OrgendaTagList.swift:4](/Users/roifewu/.config/orgenda/Orgenda/Components/Tags/OrgendaTagList.swift:4) | SwiftUI Layout 协议 | 当前要求是不等宽标签自然换行。Grid／LazyVGrid 的列布局不等价；换成网格会改变语义与宽度。可减少使用场景，不必重写这 43 行布局。 |
| [HabitHistoryView.swift:3](/Users/roifewu/.config/orgenda/Orgenda/Components/HabitHistoryView.swift:3) | LazyVGrid + RoundedRectangle | 已是简单原生组合；热力格子不是系统现成控件。为 28 个格子引入 Charts 不会明显减少复杂度。 |
| [OrgendaRootView.swift:190](/Users/roifewu/.config/orgenda/Orgenda/Features/Root/OrgendaRootView.swift:190) | TabView、TabSection、sidebarAdaptable | 顶层标签、侧栏及搜索角色已交给系统。保留路由、配置透视和启动时机。 |
| [SettingsRow.swift:12](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/SettingsRow.swift:12)、[SettingsValueRow.swift:8](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/SettingsValueRow.swift:8)、[ConfigurationFilesSections.swift:200](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/ConfigurationFilesSections.swift:200) | Label、LabeledContent、List(selection:) | 设置图文行、信息行、路径多选已原生。品牌图标、长路径和配置校验是应用内容。限定色板的 Picker 不等于任意 ColorPicker，后者会扩大配置值范围。 |
| [AgendaStartupSkeleton.swift:22](/Users/roifewu/.config/orgenda/Orgenda/Features/Agenda/AgendaStartupSkeleton.swift:22)、[OrgendaEmptyState.swift:6](/Users/roifewu/.config/orgenda/Orgenda/DesignSystem/Layout/OrgendaEmptyState.swift:6) | .redacted、ContentUnavailableView、ScrollView 的默认锚点 | 加载占位复用真实行，空状态只补充短窗口／大字体可滚动布局。不是自制加载引擎或空状态控件。 |
| [OrgPreviewDrawer.swift:8](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/OrgPreviewDrawer.swift:8)、[OrgPreviewTable.swift:7](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Blocks/OrgPreviewTable.swift:7)、[OrgPreviewRichText.swift:24](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Blocks/OrgPreviewRichText.swift:24) | DisclosureGroup、Grid、Text(AttributedString) | Drawer 已是原生展开组；Org 表格需要任意列、分隔行及嵌入段落，Table 不一定等价；富文本展示已经使用系统文本。 |
| [OrgPreviewMarkup.swift:99](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Markup/OrgPreviewMarkup.swift:99)、[OrgMathRendering.swift:24](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Rendering/OrgMathRendering.swift:24)、[OrgCodeHighlighting.swift:14](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Rendering/OrgCodeHighlighting.swift:14) | AttributedString、Image、NSCache；领域渲染由解析器与第三方库补充 | Org 语法、公式、编程语言高亮不是基础控件替换能解决的。Text(markdown:) 不能等价解释 Org。不要为了“原生”丢弃公式、源代码高亮或原文回写位置。 |
| [OrgPreviewImageView.swift:147](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Images/OrgPreviewImageView.swift:147) | task、Image、ProgressView；URLSession／ImageIO 在加载服务 | AsyncImage 不能直接替代工作区相对路径、attachment:、权限检查、流式大小限制及降采样。保留加载服务；C08 只讨论点击后的预览外壳。 |
| [OrgContextPreview.swift:14](/Users/roifewu/.config/orgenda/Orgenda/Components/OrgContextPreview.swift:14)、[WorkspaceDocumentContextPreview.swift:7](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/WorkspaceDocumentContextPreview.swift:7) | 系统 contextMenu(preview:) 中的普通 SwiftUI 内容 | 自定义的是文件／任务摘要，系统菜单呈现已经原生。 |
| [AgendaView.swift:110](/Users/roifewu/.config/orgenda/Orgenda/Features/Agenda/AgendaView.swift:110)、[WorkspaceFileActions.swift:214](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/WorkspaceFileActions.swift:214) | safeAreaInset、Button、Material／glassEffect | Undo 提示条没有一对一系统 toast 成品。可统一两处样式，但 UndoManager 只解决撤销管理，不会自动生成提示条；文件事务回滚仍是领域行为。 |
| [OrgendaHaptics.swift:6](/Users/roifewu/.config/orgenda/Orgenda/DesignSystem/OrgendaHaptics.swift:6)、[OrgendaMotion.swift:7](/Users/roifewu/.config/orgenda/Orgenda/DesignSystem/OrgendaMotion.swift:7)、[OrgendaTheme.swift:3](/Users/roifewu/.config/orgenda/Orgenda/DesignSystem/OrgendaTheme.swift:3) | UIKit 反馈生成器、SwiftUI Animation、动态系统颜色 | 小型策略层可保留。反馈生成器在视图即将关闭时仍能触发是现有设计原因，不必为了统一 .sensoryFeedback 增加额外状态。 |

## 建议实施顺序与验收

1. 先做 R01、R06、D01：去桥接、去重复状态连接、去未使用手势，改造范围最小。
2. 再做 R02：保留源树校验，验证拖放成功、取消、出应用、子树嵌套、撤销，确认后移除 UIKit 覆盖层。
3. 做 R03、R04、R05：统一系统列表、表单和展开控件。检查 iPhone 返回手势、iPad 窄窗口分栏、大字体和 VoiceOver。
4. 再评估 R07、R08，以及 C01／C02：这些会影响主浏览体验和日历设计，需要用替代原型比较，而不是只按代码行数决定。
5. C03、C06、C07 保持独立验证：已有代码和测试专门保护键盘按钮、搜索布局、输入法与撤销，不能把其包装代码简单视为冗余。

可复用的现有回归入口包括 OrgSyntaxTextEditorTests 的输入法组合与撤销测试，UIUXPolishUITests 的键盘工具条和图片预览测试，MotionFlowUITests 的取消拖拽、模式切换、文件操作与日历联动测试，以及 IPadLayoutUITests 的旋转、短窗口和大字体测试。新增、删除、移动源码后，应按 README 执行 XcodeGen；仅增加本清单不需要生成工程。

## 逐文件阅读记录

每行代表全文已读，行数包含空行与注释。“保留”表示该文件没有值得单独进行的控件替换；不代表对所有业务逻辑或运行时行为作出正确性保证。R、C、D 编号对应上面的改造项。同一文件可以同时含原生控件和可简化的局部代码。

### 应用入口

| 文件 | 行数 | 结论 | 具体判断 |
| --- | ---: | --- | --- |
| [OrgendaApp.swift](/Users/roifewu/.config/orgenda/Orgenda/App/OrgendaApp.swift:1) | 40 | 保留 | WindowGroup 与 UIApplicationDelegateAdaptor 是系统入口；测试视口仅 DEBUG 使用。 |
| [OrgendaQuickActions.swift](/Users/roifewu/.config/orgenda/Orgenda/App/OrgendaQuickActions.swift:1) | 71 | 保留 | 系统快捷操作与 scene delegate；窗口外观处理还兼顾已打开的 sheet。 |

### 共享组件

| 文件 | 行数 | 结论 | 具体判断 |
| --- | ---: | --- | --- |
| [OrgendaCalendar.swift](/Users/roifewu/.config/orgenda/Orgenda/Components/Calendar/OrgendaCalendar.swift:1) | 860 | R08、C01、C02 | 月／年已原生分页；周拖动、密度状态机及整套日历分别评估。 |
| [OrgendaCalendarDayGrid.swift](/Users/roifewu/.config/orgenda/Orgenda/Components/Calendar/OrgendaCalendarDayGrid.swift:1) | 112 | C01 | 按天选择、标记和 dropDestination；替换需处理逐日期拖放的差异。 |
| [OrgendaCalendarResizeContent.swift](/Users/roifewu/.config/orgenda/Orgenda/Components/Calendar/OrgendaCalendarResizeContent.swift:1) | 240 | C02 | Canvas 过渡副本、几何插值与快照；放弃连续变形后才可移除。 |
| [OrgendaCalendarResizePreview.swift](/Users/roifewu/.config/orgenda/Orgenda/Components/Calendar/OrgendaCalendarResizePreview.swift:1) | 74 | C02 | Animatable 包装与 DEBUG 帧采样；随密度交互决定。 |
| [OrgendaCalendarSizing.swift](/Users/roifewu/.config/orgenda/Orgenda/Components/Calendar/OrgendaCalendarSizing.swift:1) | 104 | C02 | 最终网格与过渡共用尺寸规则；不能因为删除动画而全部删除。 |
| [OrgendaCalendarYearGrid.swift](/Users/roifewu/.config/orgenda/Orgenda/Components/Calendar/OrgendaCalendarYearGrid.swift:1) | 136 | C01、C02 | 全年迷你月份网格没有相同成品系统控件；与日历方案一起决定。 |
| [OrgendaDateButton.swift](/Users/roifewu/.config/orgenda/Orgenda/Components/Calendar/OrgendaDateButton.swift:1) | 120 | C01 | Button 已原生，选择圆与日期标记手画；随月历方案决定。 |
| [OrgendaDateHeading.swift](/Users/roifewu/.config/orgenda/Orgenda/Components/Calendar/OrgendaDateHeading.swift:1) | 144 | C02 | 保留日期文本；年份锚点、缩放与位移属于自定义变形。 |
| [HighlightedOrgEditor.swift](/Users/roifewu/.config/orgenda/Orgenda/Components/Editor/HighlightedOrgEditor.swift:1) | 44 | 保留 | 高亮的取消与修订校验独立于底层控件；C07 成功后仍需要。 |
| [OrgEditorSession.swift](/Users/roifewu/.config/orgenda/Orgenda/Components/Editor/OrgEditorSession.swift:1) | 167 | C07 | TextKit 2、UndoManager、光标定位和跨模式会话，属于有必要的协调。 |
| [OrgKeyboardAccessory.swift](/Users/roifewu/.config/orgenda/Orgenda/Components/Editor/OrgKeyboardAccessory.swift:1) | 153 | C03 | 按钮和玻璃效果原生；容器、inset、排列与 hitTest 可评估。 |
| [OrgSyntaxPresentation.swift](/Users/roifewu/.config/orgenda/Orgenda/Components/Editor/OrgSyntaxPresentation.swift:1) | 263 | 保留 | 语法节点到原生文本属性的映射；换控件不会消除领域语义。 |
| [OrgSyntaxTextEditor.swift](/Users/roifewu/.config/orgenda/Orgenda/Components/Editor/OrgSyntaxTextEditor.swift:1) | 368 | C07 | 原生 UITextView 包装负责输入法、源文同步与撤销；不能直接扔掉。 |
| [OrgHeadingDrag.swift](/Users/roifewu/.config/orgenda/Orgenda/Components/Gestures/OrgHeadingDrag.swift:1) | 175 | R02 | 迁移拖拽源生命周期；保留 DropDelegate、落点分区及循环嵌套防护。 |
| [OrgendaHorizontalPan.swift](/Users/roifewu/.config/orgenda/Orgenda/Components/Gestures/OrgendaHorizontalPan.swift:1) | 48 | D01 | 全仓没有调用，建议删掉未使用的横向识别器。 |
| [HabitHistoryView.swift](/Users/roifewu/.config/orgenda/Orgenda/Components/HabitHistoryView.swift:1) | 20 | 保留 | 20 行 LazyVGrid 热力格和逐日无障碍值；无需引入 Charts。 |
| [OrgContextPreview.swift](/Users/roifewu/.config/orgenda/Orgenda/Components/OrgContextPreview.swift:1) | 86 | 保留 | 系统长按预览中的业务摘要及 28 天记录。 |
| [OrgItemRow.swift](/Users/roifewu/.config/orgenda/Orgenda/Components/OrgItemRow.swift:1) | 237 | 保留 | Button、swipeActions、contextMenu、draggable 已原生；完成操作不总是 Bool。 |
| [OrgRecurrenceEditor.swift](/Users/roifewu/.config/orgenda/Orgenda/Components/OrgRecurrenceEditor.swift:1) | 136 | 保留 | 原生控件组成 Org 重复规则输入；没有等价系统重复规则编辑器。 |
| [OrgendaTagList.swift](/Users/roifewu/.config/orgenda/Orgenda/Components/Tags/OrgendaTagList.swift:1) | 20 | 保留 | 不等宽静态标签自然换行；网格和按钮都不是等价替代。 |
| [OrgWorkflowControls.swift](/Users/roifewu/.config/orgenda/Orgenda/Components/Workflow/OrgWorkflowControls.swift:1) | 68 | 保留 | 原生 Picker、Label、SF Symbols；配置状态与快捷键保持业务封装。 |

### 设计系统

| 文件 | 行数 | 结论 | 具体判断 |
| --- | ---: | --- | --- |
| [ConfigurationColor+Presentation.swift](/Users/roifewu/.config/orgenda/Orgenda/DesignSystem/ConfigurationColor+Presentation.swift:1) | 31 | 保留 | 限定色板到动态系统颜色的映射；ColorPicker 会改变配置支持范围。 |
| [ConfigurationEnvironment.swift](/Users/roifewu/.config/orgenda/Orgenda/DesignSystem/ConfigurationEnvironment.swift:1) | 6 | 保留 | 原生 Environment @Entry，无自制状态容器。 |
| [OrgendaDatePresentation.swift](/Users/roifewu/.config/orgenda/Orgenda/DesignSystem/Formatting/OrgendaDatePresentation.swift:1) | 105 | 保留 | 已经使用 Date.FormatStyle 和 RelativeDateTimeFormatter。 |
| [OrgendaEmptyState.swift](/Users/roifewu/.config/orgenda/Orgenda/DesignSystem/Layout/OrgendaEmptyState.swift:1) | 14 | 保留 | 系统 ScrollView 居中和按需滚动，兼顾短窗口与大字体。 |
| [OrgendaFlowLayout.swift](/Users/roifewu/.config/orgenda/Orgenda/DesignSystem/Layout/OrgendaFlowLayout.swift:1) | 43 | 保留 | 43 行 Layout 实现自然换行，固定列网格不等价。 |
| [OrgWorkflow+Presentation.swift](/Users/roifewu/.config/orgenda/Orgenda/DesignSystem/OrgWorkflow+Presentation.swift:1) | 14 | 保留 | 状态到图标和文字颜色的展示映射。 |
| [OrgendaHaptics.swift](/Users/roifewu/.config/orgenda/Orgenda/DesignSystem/OrgendaHaptics.swift:1) | 17 | 保留 | 原生反馈生成器可在发起操作的视图关闭时触发；无需强迁 sensoryFeedback。 |
| [OrgendaMotion.swift](/Users/roifewu/.config/orgenda/Orgenda/DesignSystem/OrgendaMotion.swift:1) | 66 | 保留 | 原生 Animation／Transition 的 Reduce Motion 策略。 |
| [OrgendaTheme.swift](/Users/roifewu/.config/orgenda/Orgenda/DesignSystem/OrgendaTheme.swift:1) | 80 | 保留 | 语义颜色和深浅适配不是控件重造，改全系统配色属于视觉调整。 |

### 议程

| 文件 | 行数 | 结论 | 具体判断 |
| --- | ---: | --- | --- |
| [AgendaCalendarView.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/Agenda/AgendaCalendarView.swift:1) | 343 | 保留 | Agenda／Journal 已 TabView(.page)；AnyLayout 与日期同步有专门需求。 |
| [AgendaDayContent.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/Agenda/AgendaDayContent.swift:1) | 104 | R10 | Overdue 胶囊可用系统按钮样式；全天事件、完成动作与菜单保留。 |
| [AgendaDayHeader.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/Agenda/AgendaDayHeader.swift:1) | 39 | 保留 | 原生 Text 与日期计数组头，作为时间线 pinned header。 |
| [AgendaPerspectiveContent.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/Agenda/AgendaPerspectiveContent.swift:1) | 97 | R07 | 普通透视适合 List + Section；分组数据与跨组标识保留。 |
| [AgendaRescheduleSheet.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/Agenda/AgendaRescheduleSheet.swift:1) | 52 | 保留 | NavigationStack + Form + graphical DatePicker 已是原生选择器。 |
| [AgendaStartupSkeleton.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/Agenda/AgendaStartupSkeleton.swift:1) | 68 | 保留 | 复用真实行并 redacted，未重新绘制加载控件。 |
| [AgendaTaskLists.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/Agenda/AgendaTaskLists.swift:1) | 99 | R07 | Unscheduled／Overdue 是标准分组列表，可迁 List。 |
| [AgendaView.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/Agenda/AgendaView.swift:1) | 287 | R09 | 透视菜单可用 toolbarTitleMenu；Undo 提示及透视保活有业务理由。 |
| [OrgAgendaPerspective+Presentation.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/Agenda/OrgAgendaPerspective+Presentation.swift:1) | 66 | 保留 | 名称、图标、工作流状态映射，没有 UI 控件可替代。 |

### 文档与大纲

| 文件 | 行数 | 结论 | 具体判断 |
| --- | ---: | --- | --- |
| [DocumentEditingControls.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Document/DocumentEditingControls.swift:1) | 55 | 保留 | 保存失败 alert、设置 sheet、日期 Form 已原生。 |
| [DocumentOutline.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Document/DocumentOutline.swift:1) | 546 | R05 | 树行展开和列表展示可替换；过滤、节点构建、定位与移动规则保留。 |
| [OrgDocumentView.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Document/OrgDocumentView.swift:1) | 257 | R01 | NativeModePicker 可换分段 Picker；会话保活、键盘与路由逻辑保留。 |

### Org 预览

| 文件 | 行数 | 结论 | 具体判断 |
| --- | ---: | --- | --- |
| [OrgPreviewMathBlock.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Blocks/OrgPreviewMathBlock.swift:1) | 27 | 保留 | 原生 Image／Text + ScrollView；公式排版仍需数学渲染器。 |
| [OrgPreviewMathFlow.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Blocks/OrgPreviewMathFlow.swift:1) | 22 | 保留 | 行内文本与展示公式分段，最后通过原生布局显示。 |
| [OrgPreviewMetadata.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Blocks/OrgPreviewMetadata.swift:1) | 57 | 保留 | 标题、caption、fallback 已使用 Text／LazyVStack，Org 关键字解释保留。 |
| [OrgPreviewParagraph.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Blocks/OrgPreviewParagraph.swift:1) | 71 | 保留 | 原生文本与 OpenURLAction；时间戳编辑链接是业务语义。 |
| [OrgPreviewQuote.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Blocks/OrgPreviewQuote.swift:1) | 24 | 保留 | 24 行原生文字与引用竖线；引入通用阅读器反而更复杂。 |
| [OrgPreviewRichText.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Blocks/OrgPreviewRichText.swift:1) | 45 | 保留 | Text(AttributedString) 和 Text(Image) 已原生；公式基线与图片分流保留。 |
| [OrgPreviewSourceBlock.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Blocks/OrgPreviewSourceBlock.swift:1) | 56 | 保留 | Text／ScrollView 展示代码；系统基础控件不自动提供编程语言高亮。 |
| [OrgPreviewTable.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Blocks/OrgPreviewTable.swift:1) | 54 | 保留 | Grid／GridRow 已原生；任意列与分隔行不宜盲换 Table。 |
| [OrgPreviewImageReference.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Images/OrgPreviewImageReference.swift:1) | 226 | 保留 | Org 路径、attachment 属性继承和 URL 转换属于领域适配。 |
| [OrgPreviewImageView.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Images/OrgPreviewImageView.swift:1) | 258 | C08 | 可评估点击后的 Quick Look；行内图片、工作区上下文、重试保留。 |
| [InteractiveOrgPreview.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/InteractiveOrgPreview.swift:1) | 349 | 保留 | ScrollView／sheet 已原生；乐观替换、源范围校验和折叠连续性保留。 |
| [OrgMathParser.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Markup/OrgMathParser.swift:1) | 215 | 保留 | 公式发现与原始字节范围处理，没有 UI 成品控件代替。 |
| [OrgPreviewClockValue.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Markup/OrgPreviewClockValue.swift:1) | 56 | R11 | 时长格式可原生化；CLOCK 解析和跨日处理保留。 |
| [OrgPreviewContainerMath.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Markup/OrgPreviewContainerMath.swift:1) | 45 | 保留 | 公式分段、容器文本与原始范围适配，不属于控件。 |
| [OrgPreviewDateText.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Markup/OrgPreviewDateText.swift:1) | 118 | R11 | 日期展示与缓存可统一 FormatStyle；Org 重复及尾部扩展保留。 |
| [OrgPreviewInlineFragment.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Markup/OrgPreviewInlineFragment.swift:1) | 7 | 保留 | 文本、数学、图片的轻量枚举。 |
| [OrgPreviewMarkup.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Markup/OrgPreviewMarkup.swift:1) | 327 | 保留 | Org AST 到 AttributedString／片段，不能用 Markdown 解释器等价替代。 |
| [OrgPlanningEditorSheet.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/OrgPlanningEditorSheet.swift:1) | 236 | R04、C10 | 外层卡片可换 Form + Section，系统关闭确认需验证具体触发路径。 |
| [OrgPreviewContent.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/OrgPreviewContent.swift:1) | 408 | 保留 | 扁平正文和数学跨行合并不是导航树；不能直接用 OutlineGroup 取代。 |
| [OrgPreviewDrawer.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/OrgPreviewDrawer.swift:1) | 255 | R12 | Drawer／Comment 已 DisclosureGroup；Clock 信息行可局部 LabeledContent。 |
| [OrgPreviewHeading.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/OrgPreviewHeading.swift:1) | 327 | R02 | 标题拖拽覆盖层可迁移；扁平正文折叠、复选框和首行对齐保留。 |
| [OrgPreviewOutline.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/OrgPreviewOutline.swift:1) | 268 | 保留 | 预览行、层级、特殊块与排序是数据逻辑，不是系统 outline 控件。 |
| [OrgPreviewPlanning.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/OrgPreviewPlanning.swift:1) | 125 | 保留 | 原生 Button／contextMenu 显示并编辑完整时间戳；简单 DatePicker 不覆盖重复与范围。 |
| [OrgCodeHighlighting.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Rendering/OrgCodeHighlighting.swift:1) | 44 | 保留 | Highlighter 到 AttributedString 的缓存适配，没有系统通用代码高亮控件。 |
| [OrgLatexCompatibility.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Rendering/OrgLatexCompatibility.swift:1) | 342 | 保留 | 数学引擎兼容转换，不应为了组件原生化删除。 |
| [OrgMathRendering.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Rendering/OrgMathRendering.swift:1) | 81 | 保留 | SwiftMath 渲染、Image 和 NSCache；保留源文本 fallback。 |
| [OrgPreviewFontMetrics.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Rendering/OrgPreviewFontMetrics.swift:1) | 9 | 保留 | 9 行 UIFont.preferredFont 桥接，已按 Dynamic Type 取字体。 |

### 文件浏览

| 文件 | 行数 | 结论 | 具体判断 |
| --- | ---: | --- | --- |
| [FilesView.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/FilesView.swift:1) | 248 | R03 | List(selection:) 和 NavigationLink 可取代手工行展示；路径请求保留。 |
| [WorkspaceBrowser.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/WorkspaceBrowser.swift:1) | 109 | R03 | 文件夹容器可换 List；文件详情和隐式目录筛选保留。 |
| [WorkspaceDocumentContextPreview.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/WorkspaceDocumentContextPreview.swift:1) | 33 | 保留 | 系统 contextMenu 预览里的文件／目录摘要。 |
| [WorkspaceFileActions.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/WorkspaceFileActions.swift:1) | 245 | R03、R06 | 手工行箭头和选中色可原生化，Optional 弹窗可简化；文件事务及 Undo 保留。 |

### 项目编辑

| 文件 | 行数 | 结论 | 具体判断 |
| --- | ---: | --- | --- |
| [ConfiguredCaptureView.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/ItemEditor/ConfiguredCaptureView.swift:1) | 127 | 保留 | Form、Picker、DatePicker、TextField 都原生；模板展开流程保留。 |
| [OrgItemDetailsSection.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/ItemEditor/OrgItemDetailsSection.swift:1) | 67 | 保留 | 状态、优先级和 Context 已 Picker；标签是带说明的 TextField。 |
| [OrgItemEditor.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/ItemEditor/OrgItemEditor.swift:1) | 542 | R12、C09、C10 | 主 Form 保留；文件信息行、短备注占位和关闭触发可局部评估。 |
| [OrgItemEditorField.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/ItemEditor/OrgItemEditorField.swift:1) | 5 | 保留 | FocusState 字段枚举。 |
| [OrgItemEditorSupport.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/ItemEditor/OrgItemEditorSupport.swift:1) | 62 | 保留 | 只读高亮编辑器外壳和 Org 源文拼装；后者是领域规则。 |
| [OrgItemScheduleSection.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/ItemEditor/OrgItemScheduleSection.swift:1) | 153 | 保留 | DatePicker、Toggle、Stepper 已原生；可选日期绑定和大字体适配有用。 |

### 日记

| 文件 | 行数 | 结论 | 具体判断 |
| --- | ---: | --- | --- |
| [JournalComposer.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/Journal/JournalComposer.swift:1) | 103 | C09、C10 | 短文可考虑多行 TextField；长篇仍适合 TextEditor，关闭路径需验证。 |
| [JournalDayContent.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/Journal/JournalDayContent.swift:1) | 73 | 保留 | 原生文字与装饰性时间线，不存在更简单的交互控件替代。 |

### 顶层导航

| 文件 | 行数 | 结论 | 具体判断 |
| --- | ---: | --- | --- |
| [OrgendaRootView.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/Root/OrgendaRootView.swift:1) | 325 | 保留 | TabView、TabSection、sidebarAdaptable、ToolbarContent 均系统方案。 |

### 搜索

| 文件 | 行数 | 结论 | 具体判断 |
| --- | ---: | --- | --- |
| [SearchExcerpt.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/Search/SearchExcerpt.swift:1) | 14 | 保留 | 根据查询提取匹配附近摘要，属于业务数据转换。 |
| [SearchJournalDetail.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/Search/SearchJournalDetail.swift:1) | 26 | 保留 | ScrollView、Label、Text 与文本选择已原生。 |
| [SearchListSurface.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/Search/SearchListSurface.swift:1) | 11 | 保留 | 11 行 List 样式包装。 |
| [SearchPresentation.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/Search/SearchPresentation.swift:1) | 13 | 保留 | 用于 sheet(item:) 的原生路由枚举。 |
| [SearchResultLabel.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/Search/SearchResultLabel.swift:1) | 65 | 保留 | Text + AttributedString 高亮；图标块可调整但替换收益有限。 |
| [SearchResultRow.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/Search/SearchResultRow.swift:1) | 82 | 保留 | Button／NavigationLink 已区分编辑弹窗与内容导航。 |
| [SearchSuggestions.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/Search/SearchSuggestions.swift:1) | 44 | 保留 | 按 scope 生成标签与建议可用性的数据逻辑。 |
| [SearchSuggestionsView.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/Search/SearchSuggestionsView.swift:1) | 98 | R10、C05 | 标签按钮可用系统样式，补全可移 searchSuggestions，浏览导航应保留。 |
| [SearchView.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/Search/SearchView.swift:1) | 254 | C04、C06 | searchable 已原生；scopeBar 和空状态涉及常驻布局与键盘跳动取舍。 |

### 设置

| 文件 | 行数 | 结论 | 具体判断 |
| --- | ---: | --- | --- |
| [AppearanceSettingsView.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/AppearanceSettingsView.swift:1) | 30 | 保留 | 原生 List + inline Picker。 |
| [ConfigurationEditors.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/ConfigurationEditors.swift:1) | 506 | C10 | 状态与模板 Form、色板 Picker、文件 List 已原生；关闭确认另行验证。 |
| [ConfigurationFieldSupport.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/ConfigurationFieldSupport.swift:1) | 146 | 保留 | TextField + Picker 封装；即时无效输入必须阻止保存，不能直接删掉校验。 |
| [ConfigurationFilesSections.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/ConfigurationFilesSections.swift:1) | 247 | 保留 | 路径字段、选择、多选 List 和 DisclosureGroup 都原生。 |
| [ConfigurationImportEditor.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/ConfigurationImportEditor.swift:1) | 56 | C10 | Form、TextEditor、确认已原生；仅关闭触发可评估。 |
| [ConfigurationPromptView.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/ConfigurationPromptView.swift:1) | 89 | 保留 | DisclosureGroup、可选中文字和系统剪贴板，prompt 属于业务内容。 |
| [ConfigurationSettingsView.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/ConfigurationSettingsView.swift:1) | 635 | R06 | 排序 onMove／onDelete 已原生；Optional 弹窗简化。Back 承担保存失败留稿，不能直接删除。 |
| [ReminderSettingsView.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/ReminderSettingsView.swift:1) | 249 | 保留 | Toggle、分段／菜单 Picker、Form 已原生；数值分钟规则不等于时刻选择。 |
| [SettingsRow.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/SettingsRow.swift:1) | 57 | 保留 | 本身已是 Label，只封装多行副标题与云盘图标。 |
| [SettingsValueRow.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/SettingsValueRow.swift:1) | 18 | 保留 | 本身已是 LabeledContent，只补长值换行。 |
| [SettingsView.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/SettingsView.swift:1) | 100 | 保留 | 系统 List、NavigationStack、NavigationLink 与 sheet 尺寸。 |
| [StorageConflictView.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/StorageConflictView.swift:1) | 185 | R06 | 列表与确认已原生，Optional 绑定可简化；版本对比和冲突解决保留。 |
| [StorageProviderPicker.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/StorageProviderPicker.swift:1) | 181 | R06 | List 与 fileImporter 已原生；可简化 Optional 连接确认。 |
| [StorageReconnectAction.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/StorageReconnectAction.swift:1) | 96 | 保留 | 原生 Button、ProgressView、SecureField；credential sheet 已用 item。 |
| [StorageSyncView.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/StorageSyncView.swift:1) | 140 | 保留 | ProgressView、LabeledContent、SF Symbols；隐藏图标保留基线避免行高跳动。 |
| [StorageWebDAVView.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/StorageWebDAVView.swift:1) | 161 | R06 | Form、SecureField、FocusState 已原生；Optional 连接确认可简化。 |
| [WorkspaceSettingsView.swift](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/WorkspaceSettingsView.swift:1) | 136 | 保留 | 列表导航与确认都是系统组件；待同步保护与恢复事务是应用逻辑。 |

## API 核对记录

最低部署版本来自 [project.yml](/Users/roifewu/.config/orgenda/project.yml:1)，为 iOS 27.0。以下声明在本机 iPhoneOS 27 SDK 的 SwiftUI.swiftinterface 中核对：onDragSessionUpdated 与 dragConfiguration 在 iOS 27 可用；swipeActionsContainer 在 iOS 27 可用；AttributedString TextEditor 在 iOS 26 可用；dismissalConfirmationDialog 在 iOS 27 可用；ToggleStyle.checkbox 明确不支持 iOS。现代 alert／confirmationDialog 的 item 重载也已存在。UICalendarView 的公开头文件提供选择与 decoration，未暴露现有逐日期拖放及周月年连续变形接口。

这些声明确认 API 可用性，不代表与本项目现有交互无损等价。C 类条目的迁移条件应以对应原型和回归结果为准。

