# 自定义 UI 组件系统替代审查（2026-10-15）

后续实施及原型验证见 [系统组件替换实施记录](NativeComponentMigration-2026-10-15.md)。本文保留审查当时的判断与代码证据。

审查基于当前 `main` 工作区（HEAD `7e15de3`，包含已有未提交重构），共 **136 个 UI 单元**。每项由一个专属 subagent 独立阅读代码并判断，合计 **136 个组件分析 agent**；三位调度者及清单复核者不计入该数量。

范围包含 SwiftUI View、ViewModifier、Layout、ToolbarContent，UIKit 子类及桥接，可复用 View 扩展与直接生成 UIView 的工厂，包括 private 和嵌套组件。页面也纳入，避免只检查 Components 目录而遗漏自定义实现。内部布局函数、模型、解析器、状态辅助、PreferenceKey、样式常量和测试 fixture 归入拥有它们的组件，不重复算作 UI 组件。

系统组件包括 SwiftUI、UIKit 和 Foundation。自定义类型名称不等于自绘控件；业务封装即使全部使用系统控件，仍可能有保留价值。本轮仅做代码与 API 审查，没有修改应用实现或执行新的 UI 原型，需运行验证的项目明确列出。部署目标为 iOS 27.0。

## 结论分布

| 结论 | 数量 |
| --- | ---: |
| 可直接替代 | 0 |
| 可局部替代 | 3 |
| 需原型或产品取舍 | 4 |
| 保留：已是系统组件组合 | 121 |
| 保留：无等价系统组件 | 8 |
| 可删除：未使用 | 0 |

P1/P2/P3 表示替代工作的建议顺序，不表示缺陷等级。下文的收益是静态判断，未通过原型的候选不视为可直接替换。

## 可替代或值得做原型的组件

| 编号 | 组件 | 结论 | 系统候选 | 预期收益 |
| --- | --- | --- | --- | --- |
| C001 | [OrgendaCalendar](/Users/roifewu/.config/orgenda/Orgenda/Components/Calendar/OrgendaCalendar.swift:3) | P2 · 可局部替代 | 优先局部化简周视图：ScrollView(.vertical) + LazyVStack(spacing: 0) + 等视口高周页面 + scrollTargetBehavior(.paging) + scrollPosition(id:)，沿用现有月/年分页结构；若必须每次手势只进一周，使用 .viewAligned(limitBehavior: .alwaysByOne) 与 scrollTargetLayout。整体替代另可探索 UICalendarView + UICalendarSelectionSingleDate + decoration，但仍需产品取舍；DatePicker(.graphical) 仅适合普通选日器。 | 周分页可移除 verticalPageSwipe 的方向/阈值判断、verticalDrag 的拖动位移与回弹处理，减少周翻页专用 transition/id 驱动；新增周锚点和滚动选择协调，已有日格及伸缩实现继续保留。若另行整体改用 UICalendarView，可减少月网格维护，但全交互保留时桥接收益未证实。 |
| C013 | [OrgEditorTextView](/Users/roifewu/.config/orgenda/Orgenda/Components/Editor/OrgEditorSession.swift:141) | P3 · 可局部替代 | 仅把 make() 的手工 TextKit 2 对象链替换为 OrgEditorTextView(frame: .zero, textContainer: nil)，随后保留文本容器尺寸、widthTracksTextView 与撤销配置；保留子类和文档级撤销管理器。 | 只减少 TextKit 2 初始化和所有权管理代码；保留有业务价值的短子类，不引入新桥接层。 |
| C041 | [AgendaView](/Users/roifewu/.config/orgenda/Orgenda/Features/Agenda/AgendaView.swift:3) | P2 · 需原型或产品取舍 | 仅 perspectiveMenu 的标题入口可考虑 navigationTitle(displayedPerspective.title) + toolbarTitleMenu { 原有 Picker }，系统接管标题菜单指示器；其余页面仍保留原生组合与业务编排。 | 若原型通过，可去掉手拼标题与箭头，并将标题菜单的呈现交给系统；只减少少量外观组合，不能消除页面状态和业务回调。当前没有可直接替换整个 AgendaView 的系统控件。 |
| C085 | [WorkspaceFolderDropTarget](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/WorkspaceFileActions.swift:229) | P2 · 需原型或产品取舍 | iOS 27 SwiftUI .dropDestination(for: WorkspaceFileTransfer.self) + .dropConfiguration + .onDropSessionUpdated；用 DropSession.localSession、itemsCount 和 suggestedOperations 表达本地单项 move，保留收到的完整 Transferable。若 List 行内投放路由成立，可移除 UIKit 覆盖层并恢复已有 NavigationLink 点击。 | 原型成功后可删除 UIViewRepresentable、Coordinator、手工 NSItemProvider 解码和点击转发；具体收益集中在交互适配层，业务文件操作仍需保留。若 List 路由仍受限，现有短小公开 UIKit 封装已属系统组件组合，没有已证实可安全单独替换的部分。 |
| C088 | [OrgItemDetailsSection](/Users/roifewu/.config/orgenda/Orgenda/Features/ItemEditor/OrgItemDetailsSection.swift:3) | P3 · 需原型或产品取舍 | 局部候选为 LabeledContent("Tags") { 现有 TextField }，让系统负责标签与输入内容的关联及 Form 布局；其余 Picker、Section 及业务封装保留。 | 最多省去 Tags 的手工标题排版并获得系统表单标签布局；收益很小，不涉及标签解析、状态配置或编辑器状态管理的减少。 |
| C089 | [OrgItemEditor](/Users/roifewu/.config/orgenda/Orgenda/Features/ItemEditor/OrgItemEditor.swift:4) | P3 · 可局部替代 | 仅 Source 的 File 信息对可改为 LabeledContent("File") { Text(draft.source.file)… }，保留 Text 的 textSelection(.enabled)、fixedSize(horizontal:false, vertical:true) 和字体设置。Line 已使用此控件，无剩余替换收益。Notes 保留 TextEditor 与不接收点击、不进入辅助功能树的占位文本；TextField(prompt:axis:.vertical) 仅是需要另行原型的替代候选，不纳入直接替换建议。 | 局部收益只在一个 Source 元数据行：减少标签和值的手工容器与语义组合维护，跟随系统表单布局。没有可删除整个编辑器或 Notes 占位层的已证明等价方案；不应为此增加 UIKit 桥接或自定义 LabeledContentStyle。 |
| C105 | [SearchEmptyState](/Users/roifewu/.config/orgenda/Orgenda/Features/Search/SearchView.swift:234) | P3 · 需原型或产品取舍 | ContentUnavailableView(label:description:actions:)；其通用构造器可容纳现有文案和恢复按钮。 | 若原型证明等价，可删去手动图标字号、间距及文本样式；分类文案、恢复动作和适配滚动容器仍需保留。 |

## 全部组件索引

| 编号 | 组件 | 结论 |
| --- | --- | --- |
| [C001](#c001) | `OrgendaCalendar` | 可局部替代 |
| [C002](#c002) | `OrgendaCalendarDayGrid` | 保留：无等价系统组件 |
| [C003](#c003) | `OrgendaCalendarResizeContent` | 保留：无等价系统组件 |
| [C004](#c004) | `OrgendaCalendarMorphingMonth` | 保留：无等价系统组件 |
| [C005](#c005) | `OrgendaCalendarYearCanvas` | 保留：无等价系统组件 |
| [C006](#c006) | `OrgendaCalendarResizePreview` | 保留：已是系统组件组合 |
| [C007](#c007) | `OrgendaCalendarYearGrid` | 保留：无等价系统组件 |
| [C008](#c008) | `MiniMonth` | 保留：无等价系统组件 |
| [C009](#c009) | `CalendarSelectionGeometry` | 保留：已是系统组件组合 |
| [C010](#c010) | `OrgendaDateButton` | 保留：已是系统组件组合 |
| [C011](#c011) | `OrgendaDateHeading` | 保留：已是系统组件组合 |
| [C012](#c012) | `HighlightedOrgEditor` | 保留：已是系统组件组合 |
| [C013](#c013) | `OrgEditorTextView` | 可局部替代 |
| [C014](#c014) | `OrgKeyboardAccessory` | 保留：已是系统组件组合 |
| [C015](#c015) | `OrgEditorContainer` | 保留：已是系统组件组合 |
| [C016](#c016) | `OrgKeyboardAccessoryContainer` | 保留：无等价系统组件 |
| [C017](#c017) | `OrgSyntaxTextEditor` | 保留：已是系统组件组合 |
| [C018](#c018) | `OrgHeadingDragSource` | 保留：已是系统组件组合 |
| [C019](#c019) | `OrgHeadingDropModifier` | 保留：已是系统组件组合 |
| [C020](#c020) | `HabitHistoryView` | 保留：已是系统组件组合 |
| [C021](#c021) | `OrgContextPreview` | 保留：已是系统组件组合 |
| [C022](#c022) | `OrgItemContextPreview` | 保留：已是系统组件组合 |
| [C023](#c023) | `OrgItemRow` | 保留：已是系统组件组合 |
| [C024](#c024) | `OrgRecurrenceEditor` | 保留：已是系统组件组合 |
| [C025](#c025) | `OrgendaTagList` | 保留：已是系统组件组合 |
| [C026](#c026) | `OrgWorkflowIcon` | 保留：已是系统组件组合 |
| [C027](#c027) | `OrgWorkflowPicker` | 保留：已是系统组件组合 |
| [C028](#c028) | `OrgWorkflowLabel` | 保留：已是系统组件组合 |
| [C029](#c029) | `View.orgendaEmptyState` | 保留：已是系统组件组合 |
| [C030](#c030) | `OrgendaFlowLayout` | 保留：无等价系统组件 |
| [C031](#c031) | `AgendaCalendarView` | 保留：已是系统组件组合 |
| [C032](#c032) | `AgendaCalendarTabletLayout` | 保留：已是系统组件组合 |
| [C033](#c033) | `AgendaDayContent` | 保留：已是系统组件组合 |
| [C034](#c034) | `AgendaDayHeader` | 保留：已是系统组件组合 |
| [C035](#c035) | `AgendaPerspectiveContent` | 保留：已是系统组件组合 |
| [C036](#c036) | `AgendaRescheduleSheet` | 保留：已是系统组件组合 |
| [C037](#c037) | `AgendaStartupSkeleton` | 保留：已是系统组件组合 |
| [C038](#c038) | `AgendaTodoList` | 保留：已是系统组件组合 |
| [C039](#c039) | `AgendaOverdueList` | 保留：已是系统组件组合 |
| [C040](#c040) | `View.agendaListSurface` | 保留：已是系统组件组合 |
| [C041](#c041) | `AgendaView` | 需原型或产品取舍 |
| [C042](#c042) | `DocumentSaveFailureFeedback` | 保留：已是系统组件组合 |
| [C043](#c043) | `OrgInsertDateSheet` | 保留：已是系统组件组合 |
| [C044](#c044) | `DocumentOutlineSheet` | 保留：已是系统组件组合 |
| [C045](#c045) | `DocumentOutlineFilterSheet` | 保留：已是系统组件组合 |
| [C046](#c046) | `DocumentOutlineBranch` | 保留：已是系统组件组合 |
| [C047](#c047) | `OrgDocumentView` | 保留：已是系统组件组合 |
| [C048](#c048) | `FilesView` | 保留：已是系统组件组合 |
| [C049](#c049) | `OrgPreviewMathBlock` | 保留：已是系统组件组合 |
| [C050](#c050) | `OrgPreviewMathFlow` | 保留：已是系统组件组合 |
| [C051](#c051) | `OrgPreviewKeyword` | 保留：已是系统组件组合 |
| [C052](#c052) | `OrgPreviewFallback` | 保留：已是系统组件组合 |
| [C053](#c053) | `OrgPreviewParagraph` | 保留：已是系统组件组合 |
| [C054](#c054) | `OrgPreviewQuote` | 保留：已是系统组件组合 |
| [C055](#c055) | `OrgPreviewRichText` | 保留：已是系统组件组合 |
| [C056](#c056) | `OrgPreviewInlineText` | 保留：已是系统组件组合 |
| [C057](#c057) | `OrgPreviewSourceBlock` | 保留：已是系统组件组合 |
| [C058](#c058) | `OrgPreviewTable` | 保留：已是系统组件组合 |
| [C059](#c059) | `OrgPreviewImageFlow` | 保留：已是系统组件组合 |
| [C060](#c060) | `OrgPreviewImageView` | 保留：已是系统组件组合 |
| [C061](#c061) | `OrgPreviewImageSheet` | 保留：已是系统组件组合 |
| [C062](#c062) | `OrgZoomableImage` | 保留：已是系统组件组合 |
| [C063](#c063) | `OrgZoomableImage.ImageScrollView` | 保留：已是系统组件组合 |
| [C064](#c064) | `InteractiveOrgPreview` | 保留：已是系统组件组合 |
| [C065](#c065) | `OrgPlanningEditorSheet` | 保留：已是系统组件组合 |
| [C066](#c066) | `OrgPlanningTimestampEditor` | 保留：已是系统组件组合 |
| [C067](#c067) | `OrgPreviewContent` | 保留：已是系统组件组合 |
| [C068](#c068) | `OrgPreviewRowView` | 保留：已是系统组件组合 |
| [C069](#c069) | `OrgPreviewDrawer` | 保留：已是系统组件组合 |
| [C070](#c070) | `OrgPreviewClock` | 保留：已是系统组件组合 |
| [C071](#c071) | `OrgPreviewReadOnlyContent` | 保留：已是系统组件组合 |
| [C072](#c072) | `OrgPreviewComment` | 保留：已是系统组件组合 |
| [C073](#c073) | `OrgPreviewTextBlock` | 保留：已是系统组件组合 |
| [C074](#c074) | `OrgPreviewHeading` | 保留：已是系统组件组合 |
| [C075](#c075) | `OrgPreviewListItem` | 保留：已是系统组件组合 |
| [C076](#c076) | `OrgPreviewPlanning` | 保留：已是系统组件组合 |
| [C077](#c077) | `OrgPreviewPlanningEntryControl` | 保留：已是系统组件组合 |
| [C078](#c078) | `WorkspaceFolderView` | 保留：已是系统组件组合 |
| [C079](#c079) | `WorkspaceFileRow` | 保留：已是系统组件组合 |
| [C080](#c080) | `WorkspaceDocumentContextPreview` | 保留：已是系统组件组合 |
| [C081](#c081) | `WorkspaceBrowserRow` | 保留：已是系统组件组合 |
| [C082](#c082) | `WorkspaceMoveSheet` | 保留：已是系统组件组合 |
| [C083](#c083) | `WorkspaceRecentlyDeleted` | 保留：已是系统组件组合 |
| [C084](#c084) | `WorkspaceFileFeedback` | 保留：已是系统组件组合 |
| [C085](#c085) | `WorkspaceFolderDropTarget` | 需原型或产品取舍 |
| [C086](#c086) | `ConfiguredCaptureView` | 保留：已是系统组件组合 |
| [C087](#c087) | `ConfigurationCaptureDateField` | 保留：已是系统组件组合 |
| [C088](#c088) | `OrgItemDetailsSection` | 需原型或产品取舍 |
| [C089](#c089) | `OrgItemEditor` | 可局部替代 |
| [C090](#c090) | `OrgSourceView` | 保留：已是系统组件组合 |
| [C091](#c091) | `OrgItemCaptureSheet` | 保留：已是系统组件组合 |
| [C092](#c092) | `OrgItemRefileDestinations` | 保留：已是系统组件组合 |
| [C093](#c093) | `OrgItemScheduleSection` | 保留：已是系统组件组合 |
| [C094](#c094) | `JournalComposer` | 保留：已是系统组件组合 |
| [C095](#c095) | `JournalDayContent` | 保留：已是系统组件组合 |
| [C096](#c096) | `JournalTimelineEntry` | 保留：已是系统组件组合 |
| [C097](#c097) | `OrgendaRootView` | 保留：已是系统组件组合 |
| [C098](#c098) | `OrgendaCaptureToolbar` | 保留：已是系统组件组合 |
| [C099](#c099) | `SearchJournalDetail` | 保留：已是系统组件组合 |
| [C100](#c100) | `View.searchListSurface` | 保留：已是系统组件组合 |
| [C101](#c101) | `SearchResultLabel` | 保留：已是系统组件组合 |
| [C102](#c102) | `SearchResultRow` | 保留：已是系统组件组合 |
| [C103](#c103) | `SearchSuggestionsView` | 保留：已是系统组件组合 |
| [C104](#c104) | `SearchView` | 保留：已是系统组件组合 |
| [C105](#c105) | `SearchEmptyState` | 需原型或产品取舍 |
| [C106](#c106) | `AppearanceSettingsView` | 保留：已是系统组件组合 |
| [C107](#c107) | `ConfigurationKeywordEditor` | 保留：已是系统组件组合 |
| [C108](#c108) | `ConfigurationTemplateEditor` | 保留：已是系统组件组合 |
| [C109](#c109) | `ConfigurationEditorErrorSection` | 保留：已是系统组件组合 |
| [C110](#c110) | `ConfigurationTemplateFilePicker` | 保留：已是系统组件组合 |
| [C111](#c111) | `ConfigurationFieldError` | 保留：已是系统组件组合 |
| [C112](#c112) | `ConfigurationLogRulePicker` | 保留：已是系统组件组合 |
| [C113](#c113) | `ConfigurationIntegerField` | 保留：已是系统组件组合 |
| [C114](#c114) | `ConfigurationFilesSections` | 保留：已是系统组件组合 |
| [C115](#c115) | `ConfigurationPathField` | 保留：已是系统组件组合 |
| [C116](#c116) | `ConfigurationPathSelectionRow` | 保留：已是系统组件组合 |
| [C117](#c117) | `ConfigurationPathSelectionView` | 保留：已是系统组件组合 |
| [C118](#c118) | `ConfigurationImportEditor` | 保留：已是系统组件组合 |
| [C119](#c119) | `ConfigurationPromptSection` | 保留：已是系统组件组合 |
| [C120](#c120) | `ConfigurationSettingsView` | 保留：已是系统组件组合 |
| [C121](#c121) | `WorkspaceReminderTimingSections` | 保留：已是系统组件组合 |
| [C122](#c122) | `ReminderTimingRow` | 保留：已是系统组件组合 |
| [C123](#c123) | `ReminderTimingEditor` | 保留：已是系统组件组合 |
| [C124](#c124) | `ReminderSettingsSections` | 保留：已是系统组件组合 |
| [C125](#c125) | `SettingsRow` | 保留：已是系统组件组合 |
| [C126](#c126) | `SettingsValueRow` | 保留：已是系统组件组合 |
| [C127](#c127) | `SettingsView` | 保留：已是系统组件组合 |
| [C128](#c128) | `StorageConflictsView` | 保留：已是系统组件组合 |
| [C129](#c129) | `StorageConflictView` | 保留：已是系统组件组合 |
| [C130](#c130) | `StorageVersionPreview` | 保留：已是系统组件组合 |
| [C131](#c131) | `StorageProviderPicker` | 保留：已是系统组件组合 |
| [C132](#c132) | `StorageReconnectAction` | 保留：已是系统组件组合 |
| [C133](#c133) | `StorageWebDAVCredentialsView` | 保留：已是系统组件组合 |
| [C134](#c134) | `StorageSyncSummary` | 保留：已是系统组件组合 |
| [C135](#c135) | `StorageWebDAVView` | 保留：已是系统组件组合 |
| [C136](#c136) | `WorkspaceSettingsView` | 保留：已是系统组件组合 |

## 全部组件逐项分析

<a id="c001"></a>

### C001 · OrgendaCalendar

**可局部替代 · P2**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Components/Calendar/OrgendaCalendar.swift:3)　置信度：medium

当前实现：以 SwiftUI ScrollView、LazyVStack、LazyVGrid、Button 和 DragGesture 组合周/月/年日历，协调连续拖动变形、分页选日、任务日期标记与拖放排期，并联动议程和日记。

系统候选：优先局部化简周视图：ScrollView(.vertical) + LazyVStack(spacing: 0) + 等视口高周页面 + scrollTargetBehavior(.paging) + scrollPosition(id:)，沿用现有月/年分页结构；若必须每次手势只进一周，使用 .viewAligned(limitBehavior: .alwaysByOne) 与 scrollTargetLayout。整体替代另可探索 UICalendarView + UICalendarSelectionSingleDate + decoration，但仍需产品取舍；DatePicker(.graphical) 仅适合普通选日器。

判断：周视图目前手算拖动方向、36/72 点翻页阈值、0.18 倍位移和回弹；月/年已经用系统 ScrollView 分页，可将周页面也交给原生目标对齐，保留日格、任务拖放及日期业务，直接减少这部分手势状态。普通 .paging 只保证视口对齐；现有手势每次仅进一周，可用 .viewAligned(limitBehavior: .alwaysByOne) 保持步数。选日仍需按周差保留星期位置，并处理外部选日与滚动互相更新。嵌套横向日期条、拖放、快速滑动与减少动态效果必须做原型验证，不能视作交互已经等价。整体 UICalendarView 虽有选日和标记，却没有连续三密度伸缩及逐日拖放公开入口，自定义装饰亦不可交互，因此整体替换仍需取舍。

预期收益：周分页可移除 verticalPageSwipe 的方向/阈值判断、verticalDrag 的拖动位移与回弹处理，减少周翻页专用 transition/id 驱动；新增周锚点和滚动选择协调，已有日格及伸缩实现继续保留。若另行整体改用 UICalendarView，可减少月网格维护，但全交互保留时桥接收益未证实。

必须保留：周/月/年密度及拖动中连续预览、取消与动画结束后的可交互状态；周翻页维持所选星期位置且每次交互仅移动一周；跨月标题、跨年与夏令时仍按 Calendar 计算；月份切换保留月内偏好日，年浏览不改变选日，点月份进入该月；任务标记、单任务拖放到具体日期、取消拖放不排期、业务回调与撤销链；选择日期与议程/日记及创建入口同步，Today 同时复位分页和时间线；动态字体横向日期条、VoiceOver 调整/分页、减少动态效果，以及 iPad 最低月密度

验证要求：已读但未运行 OrgendaUITests/DatePresentationUITests.swift:testCalendarHandleResizesThroughWeekMonthAndYear、testYearMonthTapSelectsMonthAndKeepsResizeWorking、testCalendarDateSelectionAtAccessibilitySize。；已读但未运行 OrgendaUITests/MotionFlowUITests.swift:testGestureCalendarDropAndCancelledDrop；原型须证明原生日期格的任务落点、悬停提示、取消及撤销仍可靠。；已读但未运行 OrgendaTests/Components/Calendar/OrgendaCalendarSizingTests.swift:testResizeKeepsAllDensitiesReachableAtRegularAndAccessibilitySizes 及 OrgendaTests/Domain/Date/OrgCalendarDatesTests.swift:testPreferredDayClampsInFebruaryAndRecoversInMarch。；若制作 UICalendarView 原型，比较大字体、VoiceOver、月底跨月选日、年浏览返回与连续伸缩；本次仅作静态源码/API审查，没有运行时等价证明。；周分页原型需覆盖慢拖、快甩与短拖取消；普通 .paging 不预设为单周限制，需要时验证 .viewAligned(limitBehavior: .alwaysByOne) 与等视口页面、边界和回中锚点。；周分页原型需验证大字体时内部横向日期条与外层纵向周分页的方向竞争、日期点击、长按任务拖放、相邻议程纵向滚动及议程/日记横向翻页；这些行为不能仅由月/年现有实现推断。；周分页原型需验证选中星期不变、跨月标题、Today/外部 selectedDate 改变时滚动回定位且无反馈循环、减少动态效果与 VoiceOver 翻页；原生滚动跟手和当前缩放位移/淡化动画不同，须确认体验可接受。

代码依据：

- [Orgenda/Components/Calendar/OrgendaCalendar.swift:434](/Users/roifewu/.config/orgenda/Orgenda/Components/Calendar/OrgendaCalendar.swift:434) — 周视图以 ZStack、pageGeneration、pageTransition、verticalDrag 和 simultaneousGesture 手动分页；562 行计算拖动阈值，695 行每次只对 selectedDate 加减一周。
- [Orgenda/Components/Calendar/OrgendaCalendar.swift:454](/Users/roifewu/.config/orgenda/Orgenda/Components/Calendar/OrgendaCalendar.swift:454) — 同一组件月分页已采用 ScrollView、LazyVStack、containerRelativeFrame、paging 与 scrollPosition，年分页同构；可供周分页复用，updateVisibleMonth 的月内偏好日算法不能直接套给周。
- [Orgenda/Components/Calendar/OrgendaCalendarDayGrid.swift:38](/Users/roifewu/.config/orgenda/Orgenda/Components/Calendar/OrgendaCalendarDayGrid.swift:38) — 大字体日期条是嵌套横向 ScrollView；94 行逐日 dropDestination 负责单任务排期，需保留。生产调用 AgendaCalendarView.swift:119 绑定 store.selectedDate 并接入创建、排期及 Today 时间线复位。

API 依据：

- [iPhoneOS 27.0 SDK — UICalendarView.h](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/UIKit.framework/Headers/UICalendarView.h)：核对 iOS 16 起提供日历、visibleDateComponents、装饰和月份变化 delegate；公开声明未提供周/年密度、日期格坐标命中或逐日 drop 配置。
- [iPhoneOS 27.0 SDK — UICalendarSelectionSingleDate.h](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/UIKit.framework/Headers/UICalendarSelectionSingleDate.h)：核对单日选择、程序化设置和选择 delegate，可桥接 selectedDate。
- [iPhoneOS 27.0 SDK — UICalendarViewDecoration.h](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/UIKit.framework/Headers/UICalendarViewDecoration.h)：可提供圆点、图片和自定义视图装饰；头文件明确自定义装饰不能进行用户交互，不能把装饰直接视为可交互日期格。
- [iPhoneOS 27.0 SDK — SwiftUI DatePicker / GraphicalDatePickerStyle](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：核对 graphical 样式和 DatePicker 的 Date 绑定、范围及 displayedComponents 初始化器；没有逐日任务标记/拖放或连续三密度配置接口。
- [Apple — PagingScrollTargetBehavior](https://developer.apple.com/documentation/swiftui/pagingscrolltargetbehavior)：已读官方 Markdown：分页按容器几何对齐，示例为 ScrollView + LazyVStack；iOS 17 起可用。不能由此推定每次只跨一个周页面。
- [Apple — ViewAlignedScrollTargetBehavior.LimitBehavior.alwaysByOne](https://developer.apple.com/documentation/swiftui/viewalignedscrolltargetbehavior/limitbehavior/alwaysbyone)：已读官方 Markdown：一次交互最多滚动一个视图；iOS 18 起可用。另核对本地 iPhoneOS 27 SwiftUI 声明及工程部署目标 27.0，可用于保留单周步数。

专属分析 agent：`/root/audit_group_a/c001`。

<a id="c002"></a>

### C002 · OrgendaCalendarDayGrid

**保留：无等价系统组件 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Components/Calendar/OrgendaCalendarDayGrid.swift:3)　置信度：high

当前实现：使用 LazyVGrid、Button 日期单元、ScrollViewReader 和原生 dropDestination，组合周/月日期网格；辅助功能字号改为横向日期条，并处理任务标记、选中范围、拖放目标及离屏可访问性。

系统候选：UICalendarView + UICalendarSelectionSingleDate + UICalendarViewDecoration 可覆盖月历选日和事件标记；DatePicker(.graphical) 仅适合较简单的选日需求。两者均非当前组件的完整替代。

判断：SDK 确认 UICalendarView 有单日选择与装饰，但没有周模式、横向大字日期条或公开的日期命中接口，且自定义装饰明确不能交互。当前按日期接收单个任务、显示落点并拒绝离屏页拖放，不能靠装饰保留；改桥接后仍需定制布局和拖放，无法实质简化。现有网格与滚动容器已使用系统组件。

预期收益：维持现有原生布局组合可避免增加 UIKit 桥接、状态同步和日期命中逻辑；未发现保留当前行为且能实质减少复杂度的系统替换。

必须保留：周布局允许跨月日期保持选中；月布局只在所属月显示选中与今天状态；辅助功能字号下扩大日期按钮、展示星期并滚动到所选日期，全部日期仍可到达；单个 OrgTaskTransfer 按日期排程、落点高亮与取消清理；离屏页拒绝接收任务；日期事件标记、今天与有日程的本地化可访问性值及离屏隐藏；父级控制的日期集合、月页、选择几何标识和选日回调

验证要求：OrgendaUITests/DatePresentationUITests.swift:183 — testCalendarDateSelectionAtAccessibilitySize；其辅助方法验证大字日期尺寸及月末日期可滚动到达。仅阅读，未运行。；OrgendaUITests/MotionFlowUITests.swift:378 — testGestureCalendarDropAndCancelledDrop；验证有效日期投放与取消投放。仅阅读，未运行。；OrgendaUITests/MotionFlowUITests.swift:1101 — testWeekSelectionCrossesMonthBoundary；验证跨月周选择状态。仅阅读，未运行。；OrgendaTests/Domain/Date/OrgCalendarDatesTests.swift:25、51 — 日期生成测试覆盖首星期、闰日及夏令时；仅阅读，未运行。；若产品接受改为系统月历，需另做原型验证最大辅助功能字号、VoiceOver 标记播报，以及不依赖私有子视图的按日拖放命中；不能据静态 SDK 声明认定交互等价。

代码依据：

- [Orgenda/Components/Calendar/OrgendaCalendarDayGrid.swift:23](/Users/roifewu/.config/orgenda/Orgenda/Components/Calendar/OrgendaCalendarDayGrid.swift:23) — 七列 LazyVGrid 与辅助功能字号横向 ScrollView 分支，选择变化后居中滚动。
- [Orgenda/Components/Calendar/OrgendaCalendarDayGrid.swift:64](/Users/roifewu/.config/orgenda/Orgenda/Components/Calendar/OrgendaCalendarDayGrid.swift:64) — 日期状态、事件标记、可访问性及逐日期 dropDestination；仅可见页且单任务才排程。
- [Orgenda/Components/Calendar/OrgendaCalendar.swift:538](/Users/roifewu/.config/orgenda/Orgenda/Components/Calendar/OrgendaCalendar.swift:538) — 月模式传入整月或六周网格，周模式允许相邻月选择，并传递选日及任务排程回调。

API 依据：

- [iPhoneOS 27.0 SDK — UICalendarView.h](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/UIKit.framework/Headers/UICalendarView.h)：核对 iOS 16 起可用的 selectionBehavior、calendar/timeZone、visibleDateComponents 与日期装饰委托；公开声明未提供周布局或坐标到日期命中接口。
- [iPhoneOS 27.0 SDK — UICalendarSelectionSingleDate.h](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/UIKit.framework/Headers/UICalendarSelectionSingleDate.h)：核对 selectedDate、setSelectedDate 以及选择/可选择日期委托，确认能支持单日期选择。
- [iPhoneOS 27.0 SDK — UICalendarViewDecoration.h](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/UIKit.framework/Headers/UICalendarViewDecoration.h)：确认系统圆点、图像及自定义视图装饰可实现事件标记；头文件明确自定义装饰受父视图裁切且不能接受用户交互。
- [iPhoneOS 27.0 SDK — SwiftUI DatePicker / GraphicalDatePickerStyle / dropDestination](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：核对 DatePicker 选择绑定与日期范围初始化器，以及图形样式；没有逐日内容构建接口。当前任务投放本身已使用系统 dropDestination。

专属分析 agent：`/root/audit_group_a/c002`。

<a id="c003"></a>

### C003 · OrgendaCalendarResizeContent

**保留：无等价系统组件 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Components/Calendar/OrgendaCalendarResizeContent.swift:3)　置信度：high

当前实现：使用 VStack、ZStack、GeometryReader 和 Canvas 子视图，根据连续拖动位置呈现周／月／年过渡；周月裁剪始终围绕选中周，月年将同一日期网格缩入年份对应月份，并为无障碍大字提供独立布局。

系统候选：无直接等价系统控件。UICalendarView 可承载普通日历及日期装饰；matchedGeometryEffect 可连接视图几何，但两者均不能直接承担现有三密度连续预览。

判断：这是供拖动及回弹使用的非交互预览，并非重复实现日期选择器。UICalendarView 公开接口没有周／月／年密度及可设置的过渡进度；matchedGeometryEffect 只同步视图几何，不负责日期字体、标记和色彩的逐帧插值。改用它仍需保留大部分进度、裁剪、目标月份定位和大字分支，未发现可实质删除自定义逻辑的系统替代。

预期收益：保留现有抽象；仅换成系统几何修饰符或 UIKit 桥接没有明确复杂度收益，且仍需实现业务过渡。

必须保留：从选中周连续展开至完整月，保持选中周位置连续；月网格缩入年份对应月份，避免同一月份日期重影；随拖动进度插值高度、背景遮罩和模糊，并与回弹动画共用；无障碍大字布局以及预览隐藏于辅助功能、禁止命中的语义

验证要求：已静态核对 OrgendaTests/Components/Calendar/OrgendaCalendarSizingTests.swift:5 的 testResizeSnapshotPreservesDatesAndInvalidatesWhenInputsChange，以及 :26 的 testMonthYearTransitionIsBoundedMonotonicAndSettlesAtEndpoints、:44 的 testResizeKeepsAllDensitiesReachableAtRegularAndAccessibilitySizes；本轮未运行。；已静态核对 OrgendaUITests/DatePresentationUITests.swift:46 的 testCalendarHandleResizesThroughWeekMonthAndYear，覆盖密度往返、选中日期与手柄高度；本轮未运行。；如果以后试用 matchedGeometryEffect，需原型验证手势中断和反向拖动时日期不重影、字体与标记连续变化，以及无障碍大字下的终点衔接；现有测试不能证明逐帧视觉等价。

代码依据：

- [Orgenda/Components/Calendar/OrgendaCalendarResizeContent.swift:15](/Users/roifewu/.config/orgenda/Orgenda/Components/Calendar/OrgendaCalendarResizeContent.swift:15) — 按连续位置分周月／月年两段，计算高度、选中周偏移、目标月份几何及大字分支。
- [Orgenda/Components/Calendar/OrgendaCalendar.swift:325](/Users/roifewu/.config/orgenda/Orgenda/Components/Calendar/OrgendaCalendar.swift:325) — 密度手势持续传递位置，settleDensity 回弹后才移除预览；:385 的生产调用传入月、年、星期与大字日期内容。
- [OrgendaTests/Components/Calendar/OrgendaCalendarSizingTests.swift:26](/Users/roifewu/.config/orgenda/OrgendaTests/Components/Calendar/OrgendaCalendarSizingTests.swift:26) — 验证过渡参数边界、单调性和终点，:44 覆盖普通及无障碍字号的三密度可达性。

API 依据：

- [UIKit UICalendarView.h（本机 iPhoneOS SDK）](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/UIKit.framework/Headers/UICalendarView.h)：已阅读完整公开声明：支持日历、日期范围、选择行为、可见日期和日期装饰，未公开三密度布局或连续过渡进度。
- [Apple — matchedGeometryEffect(id:in:properties:anchor:isSource:)](https://developer.apple.com/documentation/swiftui/view/matchedgeometryeffect(id:in:properties:anchor:issource:))：已读取官方 Markdown 正文；该修饰符关联视图几何与插入／移除时的矩形插值，渲染方式由其他过渡决定，不替代 Canvas 内日期绘制插值。

专属分析 agent：`/root/audit_group_a/c003`。

<a id="c004"></a>

### C004 · OrgendaCalendarMorphingMonth

**保留：无等价系统组件 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Components/Calendar/OrgendaCalendarResizeContent.swift:99)　置信度：high

当前实现：以原生 Canvas、GraphicsContext、Text 和 Path 绘制月份快照；按拖动进度连续插值日期位置、字号、选中圆、颜色与事件标记，让同一网格缩入年视图。

系统候选：无等价系统控件。UICalendarView 可提供日期选择和装饰，但不能接管此逐日、可随拖动反向推进的月年变形。

判断：该视图是非交互过渡图层，月视图到年缩略图始终使用同一批日期绘制，避免两份日期交叉淡化错位。已核对 iOS 27 UICalendarView 公共接口，其提供日期、选择与装饰配置，未提供网格几何或连续月年变形进度。替换为系统日历会丢失现有动画；继续使用系统 Canvas 是合理实现，无可删除的等价系统替代。

预期收益：保留独立绘制单元；没有可证实的复杂度削减。改用系统日历仍需另写变形图层和桥接，无法消除核心绘制逻辑。

必须保留：拖动进度下日期位置、字号、选中圆连续插值，并与年缩略图终点对齐；选中日、今天、周末、跨月日期及事件标记的现有颜色和淡出规则；快照复用及日期、标记、日历变化后的失效更新；父层对过渡内容隐藏辅助功能，大字号场景改走可访问日期布局

验证要求：已静态阅读 OrgendaTests/Components/Calendar/OrgendaCalendarSizingTests.swift:5，testResizeSnapshotPreservesDatesAndInvalidatesWhenInputsChange 覆盖 42 日快照、选中标记与输入失效；未运行测试。；已静态阅读同文件:26，testMonthYearTransitionIsBoundedMonotonicAndSettlesAtEndpoints 覆盖变形进度范围及端点；未运行测试。；现有测试未证明像素对齐；若改写，需运行原型验证正反拖动、年视图接缝、选中圆和标记淡出，以及大字号替代路径。

代码依据：

- [Orgenda/Components/Calendar/OrgendaCalendarResizeContent.swift:99](/Users/roifewu/.config/orgenda/Orgenda/Components/Calendar/OrgendaCalendarResizeContent.swift:99) — Canvas 根据 progress 插值网格几何、字体、颜色、今天轮廓和事件点。
- [Orgenda/Components/Calendar/OrgendaCalendarResizeContent.swift:69](/Users/roifewu/.config/orgenda/Orgenda/Components/Calendar/OrgendaCalendarResizeContent.swift:69) — 普通字号调用本组件完成单网格月年变形，大字号改用 monthGrid；父层 accessibilityHidden(true)。
- [Orgenda/Components/Calendar/OrgendaCalendar.swift:385](/Users/roifewu/.config/orgenda/Orgenda/Components/Calendar/OrgendaCalendar.swift:385) — calendarDragPreview 实际调用 ResizeContent；prepareResizeSnapshot 保持数据快照更新。

API 依据：

- [Apple SwiftUI Canvas](https://developer.apple.com/documentation/swiftui/canvas?changes=_7_11%2C_7_11)：官方说明 Canvas 是即时模式绘图视图，可绘制 Path/Text，但不为内部元素提供独立交互或辅助功能，符合此隐藏于辅助功能的过渡图层用途。
- [iOS 27 SDK — UICalendarView.h](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/UIKit.framework/Headers/UICalendarView.h)：实际检查公开声明：提供 calendar、selectionBehavior、visibleDateComponents、fontDesign 和装饰更新接口，没有单元格布局控制或月年变形进度接口。

专属分析 agent：`/root/audit_group_a/c004`。

<a id="c005"></a>

### C005 · OrgendaCalendarYearCanvas

**保留：无等价系统组件 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Components/Calendar/OrgendaCalendarResizeContent.swift:205)　置信度：high

当前实现：使用系统 Canvas、GraphicsContext、Text 和 Path，异步绘制拖动预览中的三列四行年历；绘制月份标签及其日期、选中圆点，刻意省略正在变形的月份日期。以快照身份及尺寸实现 Equatable。

系统候选：无等价系统控件。DatePicker(.graphical)、MultiDatePicker、UICalendarView 均无公开的十二月拼图及指定月份日期留空接口；继续使用 Canvas。

判断：这不是独立日期选择器，而是月年拖动动画的背景层：它按目标年历的精确间距绘制，跳过当前月份，让前景月份网格独占变形路径。现有系统日期控件没有这组布局和局部绘制接口；改成 Grid 仍需自定义日期、留空与几何逻辑，不能实质消除实现。普通字号使用此层，辅助字号走现有年网格，整个预览从无障碍树隐藏。

预期收益：没有已证实的系统控件替换收益；保留当前单个原生 Canvas 可避免引入日期控件桥接及额外遮罩同步逻辑。异步渲染的实际性能仍需运行时测量。

必须保留：三列四行、月份标签和日期网格的位置必须与变形网格的终点一致。；只省略 snapshot.monthIndex 的日期，保留该月标题，避免同一日期在过渡中重复出现。；沿用快照日期顺序、所属月份过滤及选中日期样式。；预览隐藏无障碍节点，辅助字号继续使用 yearGrid 分支；交互由实际日历承担。

验证要求：OrgendaTests/Components/Calendar/OrgendaCalendarSizingTests.swift:5 — testResizeSnapshotPreservesDatesAndInvalidatesWhenInputsChange 验证十二个月、每月42项和快照失效条件。；OrgendaTests/Components/Calendar/OrgendaCalendarSizingTests.swift:26 — testMonthYearTransitionIsBoundedMonotonicAndSettlesAtEndpoints 验证变形与遮罩曲线端点。；OrgendaUITests/IPadLayoutUITests.swift:191 — testCalendarColumnsKeepSelectedDateAndJournalAcrossRotation 涵盖月年拖动及回落。；如未来修改绘制方式，需原型检查拖动中当前月份无重影、最后一帧与实际年网格对齐，以及快速往返拖动的帧时间；本次仅静态阅读，未运行测试。

代码依据：

- [Orgenda/Components/Calendar/OrgendaCalendarResizeContent.swift:205](/Users/roifewu/.config/orgenda/Orgenda/Components/Calendar/OrgendaCalendarResizeContent.swift:205) — 唯一声明；Canvas 异步绘制，224行跳过当前月份日期。
- [Orgenda/Components/Calendar/OrgendaCalendarResizeContent.swift:45](/Users/roifewu/.config/orgenda/Orgenda/Components/Calendar/OrgendaCalendarResizeContent.swift:45) — 唯一调用位于月年过渡，前景月份按同一目标几何变形，辅助字号走 yearGrid，91行隐藏预览无障碍。
- [Orgenda/Components/Calendar/OrgendaCalendar.swift:386](/Users/roifewu/.config/orgenda/Orgenda/Components/Calendar/OrgendaCalendar.swift:386) — calendarDragPreview 传入缓存快照和实际日历视图；403行仅在输入变化时重建快照。

API 依据：

- [SwiftUICore.Canvas SDK 声明](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/SwiftUICore.framework/Modules/SwiftUICore.swiftmodule/arm64e-apple-ios.swiftinterface)：22183–22236行确认 Canvas 是原生 View，接收 GraphicsContext/CGSize renderer，公开 rendersAsynchronously；iOS 15 起可用。
- [UIKit.UICalendarView SDK 公开接口](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/UIKit.framework/Headers/UICalendarView.h)：核对完整头文件：支持日期范围、可见日期、选择行为和日期装饰；没有十二月自定义布局或跳过某个月全部日期的公开接口。
- [SwiftUI.GraphicalDatePickerStyle / MultiDatePicker SDK 声明](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：17329–17366行和24301–24327行确认系统日期选择器样式及多选日期绑定接口，未提供此组件所需的月份绘制或变形几何控制。

专属分析 agent：`/root/audit_group_a/c005`。

<a id="c006"></a>

### C006 · OrgendaCalendarResizePreview

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Components/Calendar/OrgendaCalendarResizePreview.swift:3)　置信度：high

当前实现：极小的 SwiftUI View/Animatable 适配层，将 position 作为 animatableData 逐帧传给内容闭包，驱动日历缩放预览。

系统候选：继续使用系统 Animatable；@Animatable 宏仅可减少属性样板，无可实质取代整个适配层的现成控件。

判断：组件已经把插值交给 SwiftUI Animatable，作用是让自定义日历绘制获得连续 position。调用方拖动时禁用动画，松手后以系统弹簧收敛并在完成回调恢复真实日历。普通 animation 修饰器不提供插值后的标量回调，换用阶段或关键帧动画还需重写交互衔接，收益有限。

预期收益：保留现有短适配层即可；宏只能减少少量样板，不能删除日历几何插值或内容闭包。

必须保留：拖动位置即时传递与松手弹簧插值共用同一内容路径；预览挂载、动画完成和中途重拖时的生命周期衔接；Reduce Motion 下无动画完成后恢复可交互日历

验证要求：OrgendaUITests/DatePresentationUITests.swift:46 testCalendarHandleResizesThroughWeekMonthAndYear 覆盖密度切换、选中日期恢复可点与端点高度。；OrgendaTests/Components/Calendar/OrgendaCalendarSizingTests.swift:26 testMonthYearTransitionIsBoundedMonotonicAndSettlesAtEndpoints 覆盖过渡值边界；尚不验证逐帧连续性。；若改用其他动画 API，需原型验证中途反向重拖、边界松手与 Reduce Motion 后预览移除；本次仅静态审查，未运行测试。

代码依据：

- [Orgenda/Components/Calendar/OrgendaCalendarResizePreview.swift:3](/Users/roifewu/.config/orgenda/Orgenda/Components/Calendar/OrgendaCalendarResizePreview.swift:3) — Animatable 的唯一插值数据为 position，body 直接调用内容闭包。
- [Orgenda/Components/Calendar/OrgendaCalendar.swift:108](/Users/roifewu/.config/orgenda/Orgenda/Components/Calendar/OrgendaCalendar.swift:108) — 生产调用挂载预览；:326 拖动事务禁用动画，:368 settleDensity 使用 withAnimation 及完成回调。
- [Orgenda/Components/Calendar/OrgendaCalendarResizeContent.swift:15](/Users/roifewu/.config/orgenda/Orgenda/Components/Calendar/OrgendaCalendarResizeContent.swift:15) — position 同时控制分段布局、高度、位移及月年绘制过渡。

API 依据：

- [SwiftUICore Animatable、@Animatable 与 View.animation(_:body:) SDK 声明](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/SwiftUICore.framework/Modules/SwiftUICore.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对 :18938 Animatable 要求可读写 VectorArithmetic animatableData，:19864 宏生成该属性，:22409 animation 内容闭包仅接收 PlaceholderContentView。

专属分析 agent：`/root/audit_group_a/c006`。

<a id="c007"></a>

### C007 · OrgendaCalendarYearGrid

**保留：无等价系统组件 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Components/Calendar/OrgendaCalendarYearGrid.swift:3)　置信度：high

当前实现：用 VStack/HStack、ForEach、Button 和 Text 排成 4×3 月份入口，常规字号附 MiniMonth；大辅助字号隐藏缩略日历并高亮所选月份，向父日历回传月份。

系统候选：无等价全年月份总览控件。DatePicker(.graphical) 与 UICalendarView 可作日期选择候选，但没有公开的 12 月缩略图总览配置；Grid/LazyVGrid 只能改写已有布局。

判断：这是全年导航而非单纯选日期：每格点击向父视图传入月初、切换为月密度，并与年度分页及缩放预览共用尺寸。当前 SDK 的 DatePicker 未提供仅选月份组件，UICalendarView 也未暴露全年缩略布局。换成这些控件会改变入口和缩放行为；改用 Grid 仅替换两层栈，不能消除月份语义、辅助功能或缩略视图，暂无实质替代收益。

预期收益：保留现有抽象；纯布局改写收益很小，桥接 UIKit 日期控件反而需要补回全年导航及状态同步。

必须保留：12 个月份入口及点击后选中月初、转入月视图的回调；按 selectedDate 标记月份，并向 MiniMonth 传递选择身份、命名空间和减少动态效果设置；大辅助字号只展示月份并高亮选中月份；仅当前年度页向辅助功能暴露月份按钮，保留完整月份年份标签与选择状态；与父层年度分页及拖动缩放预览保持一致尺寸

验证要求：已静态阅读 OrgendaUITests/DatePresentationUITests.swift:4 testYearMonthTapSelectsMonthAndKeepsResizeWorking，覆盖往年月份点击、月初选择、切回年度后的选择状态；未运行。；已静态阅读 OrgendaUITests/DatePresentationUITests.swift:46 testCalendarHandleResizesThroughWeekMonthAndYear，覆盖年度分页与恰好 12 个可点击月份；未运行。；已静态阅读 OrgendaTests/Domain/Date/OrgCalendarDatesTests.swift:26 testMonthGridRespectsFirstWeekdayAndCoversLeapDay，覆盖缩略日历日期基础；未运行。；若后续改变控件，需补充最大辅助字号年度页、VoiceOver 只读当前年度，以及减少动态效果下的缩放衔接原型验证。

代码依据：

- [Orgenda/Components/Calendar/OrgendaCalendarYearGrid.swift:16](/Users/roifewu/.config/orgenda/Orgenda/Components/Calendar/OrgendaCalendarYearGrid.swift:16) — 固定 4×3 原生栈布局；月份 Button、大字号分支与辅助功能配置在同一组件。
- [Orgenda/Components/Calendar/OrgendaCalendar.swift:626](/Users/roifewu/.config/orgenda/Orgenda/Components/Calendar/OrgendaCalendar.swift:626) — selectMonth 设置月初为 selectedDate 并切换为 month；:747 注入选择动画身份、尺寸和回调。
- [OrgendaUITests/DatePresentationUITests.swift:4](/Users/roifewu/.config/orgenda/OrgendaUITests/DatePresentationUITests.swift:4) — 年度月份点击需选中月初并切换到月视图；:89 验证年度页有 12 个可点击月份。

API 依据：

- [iOS 27 SDK — UICalendarView public interface](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/UIKit.framework/Headers/UICalendarView.h)：已核对公开选择、visibleDateComponents、装饰及日期变化接口；无全年 12 个缩略月份或年度密度配置。
- [iOS 27 SDK — GraphicalDatePickerStyle / DatePickerComponents](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对 GraphicalDatePickerStyle（24301 行）以及 DatePickerComponents（25431 行）：iOS 支持 date、hourAndMinute，没有公开 month-only 或 year-overview 组件选项。

专属分析 agent：`/root/audit_group_a/c007`。

<a id="c008"></a>

### C008 · MiniMonth

**保留：无等价系统组件 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Components/Calendar/OrgendaCalendarYearGrid.swift:72)　置信度：high

当前实现：以 LazyVGrid、Text、Circle 和 Foundation Calendar 绘制七列六行的微型月份；只高亮本月所选日期，非本月日期透明，选择圆点支持匹配几何与减少动态效果。作为年份视图的整月按钮标签，不独立处理日期点击。

系统候选：已核对 DatePicker(.graphical) 与 UICalendarView；未找到等价的无独立交互微型月份系统控件。

判断：MiniMonth 是全年十二个月按钮中的紧凑日期示意，只有父级整月按钮可点击。DatePicker 的绑定选择接口和 UICalendarView 的月历接口均不提供当前所需的微型无标题布局、固定日格尺寸与外部匹配几何圆点；嵌套日期控件还会改变点击语义。现有布局已使用系统网格与图形，整体替换没有明确简化收益。

预期收益：保留现有短小系统视图组合；引入完整日期选择控件需额外桥接与交互、尺寸适配，未识别可实际删除的自定义子部分。

必须保留：按当前 Calendar 首周规则生成 42 个日期，保留月外透明占位与七列对齐；仅本月所选日显示 14 点选择圆，维持选择几何标识及减少动态效果分支；保留父级整月点击语义；微型月份对辅助功能隐藏，辅助功能字号时由父级省略

验证要求：OrgendaTests/Domain/Date/OrgCalendarDatesTests.swift:25 — testMonthGridRespectsFirstWeekdayAndCoversLeapDay 覆盖 42 格、首周起点及闰日；OrgendaUITests/DatePresentationUITests.swift:4 — testYearMonthTapSelectsMonthAndKeepsResizeWorking 覆盖年份月份按钮选择与切回年份；源代码审查未运行测试；现有测试未直接证明微型日期与选择圆点视觉重合，如以后改变布局需检查普通字号、不同首周设置及减少动态效果下的选中日期动画

代码依据：

- [Orgenda/Components/Calendar/OrgendaCalendarYearGrid.swift:83](/Users/roifewu/.config/orgenda/Orgenda/Components/Calendar/OrgendaCalendarYearGrid.swift:83) — LazyVGrid 按月生成日期，选中圆点与每格 11 点高度均由此组件控制
- [Orgenda/Components/Calendar/OrgendaCalendarYearGrid.swift:31](/Users/roifewu/.config/orgenda/Orgenda/Components/Calendar/OrgendaCalendarYearGrid.swift:31) — MiniMonth 放在整月 Button 标签内，非辅助功能字号才显示且 accessibilityHidden(true)
- [Orgenda/Domain/Date/OrgCalendarDates.swift:18](/Users/roifewu/.config/orgenda/Orgenda/Domain/Date/OrgCalendarDates.swift:18) — daysInMonthGrid 由月首所在周起点生成 42 天

API 依据：

- [SwiftUI SDK — GraphicalDatePickerStyle / DatePicker](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对 GraphicalDatePickerStyle 声明和 DatePicker 的 Binding<Date>、日期范围、displayedComponents 初始化接口；没有微型月份日格或选择圆点布局配置接口。
- [UIKit SDK — UICalendarView.h](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/UIKit.framework/Headers/UICalendarView.h)：已核对 iOS 16+ 月历公开接口：calendar、locale、visibleDateComponents、selectionBehavior 与 decoration；没有此微型视图所需的日格尺寸和外部选择圆点几何接口。

专属分析 agent：`/root/audit_group_a/c008`。

<a id="c009"></a>

### C009 · CalendarSelectionGeometry

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Components/Calendar/OrgendaCalendarYearGrid.swift:116)　置信度：high

当前实现：为年视图缩略月历的选中圆点封装 SwiftUI 修饰器：正常模式采用 matchedGeometryEffect；减少动态效果时采用 opacity 转场。

系统候选：现有 SwiftUI matchedGeometryEffect、AnyTransition.opacity 与 accessibilityReduceMotion 已覆盖所需机制；没有可进一步消除策略分支的等价系统组件。

判断：实现没有自行计算动画或几何，只根据上层传入的减少动态效果偏好选择两种原生修饰器。调用方给选中圆点传递月份、密度及分页代次相关标识和共享命名空间，保留匹配范围很重要。直接内联只能减少类型声明，不能减少必要策略；改成单一动画会改变减少动态效果下的行为，保留此轻量封装更清楚。

预期收益：无实质系统替代收益；保留可集中表达无障碍动画策略，避免将条件分支搬到圆点视图。

必须保留：减少动态效果时不启用几何匹配，仅使用透明度转场；选中圆点使用既有 ID、命名空间、frame 属性及中心锚点；调用方按月份、密度和分页代次隔离几何匹配标识

验证要求：OrgendaUITests/DatePresentationUITests.swift:4 testYearMonthTapSelectsMonthAndKeepsResizeWorking 覆盖年/月切换与选择保持，但不验证动画轨迹。；若调整此封装，应分别在减少动态效果开启/关闭时验证同月选中日期变化与年/月切换，检查是否存在几何跳动或错误匹配；当前未找到直接验证此修饰器动画的测试。本审查未构建或运行测试。

代码依据：

- [Orgenda/Components/Calendar/OrgendaCalendarYearGrid.swift:116](/Users/roifewu/.config/orgenda/Orgenda/Components/Calendar/OrgendaCalendarYearGrid.swift:116) — ViewModifier 仅在 opacity 转场与原生 matchedGeometryEffect 之间分支。
- [Orgenda/Components/Calendar/OrgendaCalendarYearGrid.swift:45](/Users/roifewu/.config/orgenda/Orgenda/Components/Calendar/OrgendaCalendarYearGrid.swift:45) — 缩略月历使用带 year 前缀与月份日期键的 selectionID；第95行把修饰器施加于选中圆点。
- [Orgenda/Components/Calendar/OrgendaCalendar.swift:727](/Users/roifewu/.config/orgenda/Orgenda/Components/Calendar/OrgendaCalendar.swift:727) — ID 包含 density 和 pageGeneration；第746行将标识、共享命名空间及环境导出的 reduceMotion 传入年视图。

API 依据：

- [SwiftUICore SDK: View.matchedGeometryEffect 与 MatchedGeometryProperties](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/SwiftUICore.framework/Modules/SwiftUICore.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对第3621–3644行：原生接口支持 ID、Namespace、frame、center 与 isSource；iOS 14 起可用。
- [SwiftUICore SDK: AnyTransition.opacity 与 EnvironmentValues.accessibilityReduceMotion](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/SwiftUICore.framework/Modules/SwiftUICore.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对第5148–5149行和第23405行：透明度转场与减少动态效果环境偏好均为系统 API。

专属分析 agent：`/root/audit_group_a/c009`。

<a id="c010"></a>

### C010 · OrgendaDateButton

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Components/Calendar/OrgendaDateButton.swift:16)　置信度：high

当前实现：使用原生 Button、Text、Circle 与 VStack 呈现单日，封装选中/今日外观、事件点占位、星期、动态字体、对比度及减少动态效果适配。

系统候选：继续使用现有 SwiftUI Button；DatePicker(.graphical) 是整个日期选择器，不是可替换此单日按钮的系统单元。

判断：点击语义已由系统 Button 提供，自定义部分是日历业务标签和选中表面。调用方将各日期按钮作为独立落点并补充日程提示；事件点占位、大字星期和跨日期选中动画均依赖该粒度。SDK 的 DatePicker 仅提供整体选择绑定、范围及外部标签，不能直接承接这些单日配置。没有实质上可删除自定义实现的等价替换。

预期收益：保留此短封装可集中日期样式与辅助功能策略；改成整套日期选择器需重做父级交互，无法带来局部复杂度收益。

必须保留：完整日期朗读、今日信息及选中辅助功能特征；事件点与无事件日期的等高占位；大字模式下的星期标签及放大圆形尺寸；减少动态效果时退出 matchedGeometryEffect；调用方的单日期拖放目标和稳定辅助功能标识

验证要求：OrgendaUITests/DatePresentationUITests.swift:testCalendarDateSelectionSurvivesTabSwitching 与 testCalendarDateSelectionAtAccessibilitySize 覆盖选中状态、完整日期标签和大字尺寸；本次只读未运行。；OrgendaUITests/MotionFlowUITests.swift:testGestureCalendarDropAndCancelledDrop 覆盖父级在日期按钮上安排任务；本次只读未运行。；若改变选中表面，需要原型验证减少动态效果、增加对比度以及星期/事件点的 VoiceOver 朗读。

代码依据：

- [Orgenda/Components/Calendar/OrgendaDateButton.swift:44](/Users/roifewu/.config/orgenda/Orgenda/Components/Calendar/OrgendaDateButton.swift:44) — 原生 Button 组合日期标签、事件点和辅助功能特征。
- [Orgenda/Components/Calendar/OrgendaDateButton.swift:75](/Users/roifewu/.config/orgenda/Orgenda/Components/Calendar/OrgendaDateButton.swift:75) — 选中表面按减少动态效果切换系统动画，并按动态字体调整尺寸。
- [Orgenda/Components/Calendar/OrgendaCalendarDayGrid.swift:71](/Users/roifewu/.config/orgenda/Orgenda/Components/Calendar/OrgendaCalendarDayGrid.swift:71) — 生产调用传入星期、标记与动画命名空间，随后附加日期级拖放与朗读信息。

API 依据：

- [iOS 27 SwiftUI SDK：Button、DatePicker 与 GraphicalDatePickerStyle](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对目标 iOS 27 SDK：29179 行起的 Button.init(action:label:)、25372 行起的 DatePicker 选择绑定/范围/外部标签接口及 24301 行起的 GraphicalDatePickerStyle。Button 自 iOS 13 可用，graphical 样式自 iOS 14 可用；DatePicker 无单日内容闭包，不等价于独立日期按钮。

专属分析 agent：`/root/audit_group_a/c010`。

<a id="c011"></a>

### C011 · OrgendaDateHeading

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Components/Calendar/OrgendaDateHeading.swift:3)　置信度：high

当前实现：以 Text、HStack/VStack、ScaledMetric 和 Foundation 日期格式化展示日期；通过 Animatable、锚点偏好和 GeometryReader 让同一个可见年份随月／年密度拖动连续移动缩放，并适配大字、减少动态效果及辅助功能标签。

系统候选：继续使用现有 SwiftUI Text 与布局组合；没有可直接替代的系统日期标题。matchedGeometryEffect 可研究布局匹配，但并非当前显式拖动进度和单一可见年份的等价替代；DatePicker 是日期选择控件。

判断：调用方同时传入选中日、可见月份及连续拖动进度，标题须分别显示日／星期与浏览月份，并将同一个年份从行内位置移动到年标题。现有实现已使用系统文本、日期格式化和动画接口。DatePicker 会引入选择交互，matchedGeometryEffect 的公开接口没有进度参数，不能据此认定能删去连续变形逻辑；没有有实质收益的直接替换。

预期收益：保留现有原生组合及职责边界；仅换成另一套系统动画接口尚无已证明的复杂度收益。

必须保留：选中日期与浏览月份分离，年视图显示可见月份所属年份；拖动及弹簧收敛期间的年份连续位置、缩放和细节淡出；辅助功能大字布局、ScaledMetric 字号和减少动态效果时的文本淡入淡出；完整日期／年份的合并朗读标签及标题标识

验证要求：OrgendaUITests/DatePresentationUITests.swift:4 testYearMonthTapSelectsMonthAndKeepsResizeWorking 验证月选择后的完整日期标题；OrgendaUITests/DatePresentationUITests.swift:183 testCalendarDateSelectionAtAccessibilitySize 验证大字标题高度与日期切换；OrgendaUITests/DatePresentationUITests.swift:46 testCalendarHandleResizesThroughWeekMonthAndYear；OrgendaTests/Components/Calendar/OrgendaCalendarSizingTests.swift:26 testMonthYearTransitionIsBoundedMonotonicAndSettlesAtEndpoints 提供相邻行为覆盖；未运行测试；现有断言未直接证明年份逐帧变形，若试用 matchedGeometryEffect，需原型验证往返拖动、取消／回弹、大字及 VoiceOver 标签切换

代码依据：

- [Orgenda/Components/Calendar/OrgendaDateHeading.swift:34](/Users/roifewu/.config/orgenda/Orgenda/Components/Calendar/OrgendaDateHeading.swift:34) — 原生 Text／栈布局、大字分支和 numericText；第74行起以单一可见年份和锚点实现连续变形
- [Orgenda/Components/Calendar/OrgendaCalendar.swift:237](/Users/roifewu/.config/orgenda/Orgenda/Components/Calendar/OrgendaCalendar.swift:237) — 生产调用传入 selectedDate、visibleMonth、yearTitleProgress；第243行按密度拖动位置计算连续进度
- [OrgendaUITests/DatePresentationUITests.swift:228](/Users/roifewu/.config/orgenda/OrgendaUITests/DatePresentationUITests.swift:228) — 读取标题标签，并在大字模式约束标题高度；第252行起验证日期切换后的标签保持

API 依据：

- [SwiftUICore SDK：matchedGeometryEffect、ContentTransition.numericText(value:)、anchorPreference](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/SwiftUICore.framework/Modules/SwiftUICore.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对第3640行 matchedGeometryEffect 的公开参数不含进度、第15602行原生锚点偏好接口及第20416行 numericText(value:)；后者可用性为 iOS 17+，当前代码已直接使用。
- [SwiftUI SDK：DatePicker](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对第25375行起初始化器以 Binding<Date> 作为 selection；它提供日期选择，不能等价取代只读且与外部密度拖动联动的日期标题。

专属分析 agent：`/root/audit_group_a/c011`。

<a id="c012"></a>

### C012 · HighlightedOrgEditor

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Components/Editor/HighlightedOrgEditor.swift:5)　置信度：high

当前实现：以 SwiftUI 状态和 task(id:) 管理 Org 高亮解析：90 毫秒防抖、取消旧请求并核对文本版本，向基于 UITextView/TextKit 2 的 OrgSyntaxTextEditor 传入结果及编辑会话。

系统候选：无可直接替代本层职责的系统组件；iOS 27 SDK 的 TextEditor 支持 String 和 AttributedString，但仍须保留 Org 解析及可取消的高亮任务管理。

判断：本层没有自绘控件，主要将系统 task(id:) 与原生文本视图封装连接起来。文档编辑和只读源码都实际调用它，文本或工作流变化会重新解析，旧任务及旧文本结果受到拦截。系统富文本 TextEditor 能显示样式，却不能消除 Org 语义解析和版本管理；替换底层后这层业务职责仍然存在，拆除只会把状态与任务搬到调用处。

预期收益：保留现有薄封装最清晰；没有已证明能减少实现复杂度且保持行为的系统替代。

必须保留：文本及工作流共同触发高亮更新，保留可复用解析器生命周期；90 毫秒防抖、任务取消和提交前文本版本校验；纯文本绑定以及只读、激活状态、编辑会话和外部修订透传；下层对输入法组合、光标、滚动与跨编辑/预览撤销历史的连续性

验证要求：已静态阅读 OrgendaTests/Components/Editor/OrgSyntaxTextEditorTests.swift:130 testPreviewEditsAndNativeTypingShareUndoAcrossModes、:170 testCommandUndoRestoresSelectionAndExternalReloadClearsHistory、:202 testMarkedCompositionIsNotInterruptedByHighlightingAndCanBeUndone；未执行测试。；已静态阅读 OrgendaTests/Components/Editor/OrgSyntaxTextEditorTests.swift:660 testPresentationAttributesPreserveSelectionAndSemanticTraits、:702 testStaleHighlightRangesAreClampedWithoutMovingCaret；未执行测试。；若未来修改此任务封装，应验证快速输入及只改工作流配置时旧高亮不会覆盖新结果；当前所读测试未直接覆盖 SwiftUI task 生命周期。

代码依据：

- [Orgenda/Components/Editor/HighlightedOrgEditor.swift:39](/Users/roifewu/.config/orgenda/Orgenda/Components/Editor/HighlightedOrgEditor.swift:39) — task 标识包含文本和工作流，延迟后及发布前检查取消，发布前再次核对文本。
- [Orgenda/Features/Files/Document/OrgDocumentView.swift:39](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Document/OrgDocumentView.swift:39) — 文档使用该组件并传入稳定编辑会话、激活状态及外部文件修订。
- [Orgenda/Features/ItemEditor/OrgItemEditorSupport.swift:8](/Users/roifewu/.config/orgenda/Orgenda/Features/ItemEditor/OrgItemEditorSupport.swift:8) — OrgSourceView 使用同一组件显示不可编辑但高亮的源码。

API 依据：

- [iOS 27 SwiftUI SDK — TextEditor declarations](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对 3889–3896 行：String 编辑器及 iOS 26 起的 AttributedString/AttributedTextSelection 初始化器；样式编辑能力并不提供 Org 解析任务。
- [iOS 27 SwiftUI SDK — View.task(id:)](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对 6335–6347 行，系统提供 Equatable 标识的异步任务修饰器；当前组件已直接采用该系统机制。

专属分析 agent：`/root/audit_group_a/c012`。

<a id="c013"></a>

### C013 · OrgEditorTextView

**可局部替代 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Components/Editor/OrgEditorSession.swift:141)　置信度：high

当前实现：UITextView 薄子类，持有文档级 UndoManager，并手动组装和持有系统 TextKit 2 存储、布局管理器与文本容器。

系统候选：仅把 make() 的手工 TextKit 2 对象链替换为 OrgEditorTextView(frame: .zero, textContainer: nil)，随后保留文本容器尺寸、widthTracksTextView 与撤销配置；保留子类和文档级撤销管理器。

判断：iOS 27 SDK 明确规定指定初始化器传 nil 容器时使用 TextKit 2，且仍直接构造当前子类，可省去手动对象链及存储持有字段。整类不宜换成普通 UITextView：undoManager 是只读接口，现有覆写保证失焦后访问同一历史，并在撤销前结束输入分组；调用方依赖该管理器连接预览与原生输入。

预期收益：只减少 TextKit 2 初始化和所有权管理代码；保留有业务价值的短子类，不引入新桥接层。

必须保留：同一文档在输入、预览修改及失去第一响应者期间共享撤销/重做历史；groupsByEvent=false、最多100组及撤销前结束输入分组；TextKit 2、文本容器随视图宽度变化及无限高的滚动布局；中文输入法组合态、Unicode选区与光标滚动位置

验证要求：OrgendaTests/Components/Editor/OrgSyntaxTextEditorTests.swift:130 — testPreviewEditsAndNativeTypingShareUndoAcrossModes 覆盖跨模式共享撤销。；OrgendaTests/Components/Editor/OrgSyntaxTextEditorTests.swift:170 — testCommandUndoRestoresSelectionAndExternalReloadClearsHistory 覆盖选区恢复和外部重载清历史。；OrgendaTests/Components/Editor/OrgSyntaxTextEditorTests.swift:202 — testMarkedCompositionIsNotInterruptedByHighlightingAndCanBeUndone 同时断言组合输入与 textLayoutManager 非空。；若实施初始化简化，复用既有测试并检查首次及旋转后的换行、最后一行光标可见性；本次只静态审查，未运行测试。

代码依据：

- [Orgenda/Components/Editor/OrgEditorSession.swift:141](/Users/roifewu/.config/orgenda/Orgenda/Components/Editor/OrgEditorSession.swift:141) — 只覆盖 undoManager；make() 手动建立 TextKit 2 链并持有 storage。
- [Orgenda/Components/Editor/OrgSyntaxTextEditor.swift:42](/Users/roifewu/.config/orgenda/Orgenda/Components/Editor/OrgSyntaxTextEditor.swift:42) — 仅有 session 时使用该子类；:142 将 documentUndoManager.finishTyping 连接到协调器。
- [OrgendaTests/Components/Editor/OrgSyntaxTextEditorTests.swift:130](/Users/roifewu/.config/orgenda/OrgendaTests/Components/Editor/OrgSyntaxTextEditorTests.swift:130) — 预览状态变化与原生输入连续撤销/重做；:226 断言 TextKit 2 可用。

API 依据：

- [iOS 27 UIKit UITextView.h — 指定初始化器与 TextKit 2](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/UIKit.framework/Headers/UITextView.h)：259–261行明确 nil NSTextContainer 使用 TextKit 2，initWithFrame:textContainer: 是 designated initializer；275行暴露 textLayoutManager。
- [iOS 27 UIKit UIResponder.h — undoManager](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/UIKit.framework/Headers/UIResponder.h)：137行 undoManager 为 nullable readonly；不能通过普通赋值给 UITextView 注入文档管理器。
- [iOS 27 Foundation NSUndoManager.h — 分组与历史限制](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/Foundation.framework/Headers/NSUndoManager.h)：72–84行声明 groupsByEvent 与 levelsOfUndo，关闭自动分组需显式结束分组；对应当前输入分组保护。

专属分析 agent：`/root/audit_group_a/c013`。

<a id="c014"></a>

### C014 · OrgKeyboardAccessory

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Components/Editor/OrgKeyboardAccessory.swift:4)　置信度：high

当前实现：以 UIButton.Configuration、UIAction、UIMenu、UIStackView 和 UIGlassEffect 组合七个编辑入口，并绑定会话撤销/重做可用状态。

系统候选：无明确有益的等价替换；UIToolbar + UIBarButtonItem 是可原型比较的布局替代，但不能直接认定行为等价。

判断：按钮、缩进菜单、等宽布局和玻璃均已采用系统组件，保留的代码主要是 Org 命令接线及撤销状态同步。UIToolbar 可接管部分布局，却不能消除业务回调；源码明确记录窄屏溢出问题，而现有要求是七个入口同时可见。该溢出现象本次未运行复核，不能据此宣称所有工具栏配置都不可行，也不足以建议直接替换。

预期收益：继续使用短小的原生控件工厂，避免仅为改用工具栏引入溢出策略与新桥接；未识别到可直接删除的非原生控件实现。

必须保留：标题、复选框、缩进/反缩进、日期、撤销、重做、收键盘入口及其可访问性标识；七个按钮同时可见、至少 44 点按钮尺寸和单一交互玻璃表面；撤销/重做状态随会话刷新，命令保留输入法组合、选择范围与共享撤销历史；交由现有容器保持键盘上方悬浮、正文透出、边缘触摸穿透与末行光标可见

验证要求：OrgendaUITests/MotionFlowUITests.swift:740 — testOrgKeyboardCommandsAndCaretSurvivePreview 覆盖命令、缩进菜单、撤销、日期以及编辑/预览切换；本次未运行。；OrgendaTests/Components/Editor/OrgSyntaxTextEditorTests.swift:55 — testFloatingToolbarKeepsFinalCaretVisibleAndMarginsInteractive 覆盖光标与边缘命中；本次未运行。；OrgendaTests/Components/Editor/OrgSyntaxTextEditorTests.swift:170 — testCommandUndoRestoresSelectionAndExternalReloadClearsHistory 覆盖命令撤销选择范围与外部重载；本次未运行。；若尝试 UIToolbar，需在目标 iOS 27 的窄屏、分屏及辅助功能环境验证七入口可见性、触摸尺寸、菜单展示和撤销状态同步；SDK 声明本身不证明布局等价。

代码依据：

- [Orgenda/Components/Editor/OrgKeyboardAccessory.swift:7](/Users/roifewu/.config/orgenda/Orgenda/Components/Editor/OrgKeyboardAccessory.swift:7) — 原生按钮工厂、缩进 UIMenu、七入口 UIStackView 与 UIGlassEffect；第 50 行注释记录 UIToolbar 溢出取舍。
- [Orgenda/Components/Editor/OrgKeyboardAccessory.swift:76](/Users/roifewu/.config/orgenda/Orgenda/Components/Editor/OrgKeyboardAccessory.swift:76) — OrgEditorContainer 在存在编辑会话时实际调用 make(for:)，并将结果固定在 keyboardLayoutGuide 上方。
- [Orgenda/Components/Editor/OrgEditorSession.swift:40](/Users/roifewu/.config/orgenda/Orgenda/Components/Editor/OrgEditorSession.swift:40) — refreshHistory 更新附件按钮状态；undo、redo、perform 与 presentDate 维护共享历史、输入法组合及选区。

API 依据：

- [iOS 27 SDK — UIGlassEffect.h](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/UIKit.framework/Headers/UIGlassEffect.h)：确认 regular 玻璃和 interactive 为原生 UIKit 能力，自 iOS 26 可用，满足最低 iOS 27。
- [iOS 27 SDK — UIToolbar.h](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/UIKit.framework/Headers/UIToolbar.h)：确认 UIToolbar 接收 UIBarButtonItem items；声明没有保证任意窄宽度下七个入口同时可见，不能据此推定直接替换。
- [iOS 27 SDK — UIStackView.h](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/UIKit.framework/Headers/UIStackView.h)：确认 arrangedSubviews、横向 axis 与 fillEqually 是系统布局能力。
- [iOS 27 SDK — UIButton.h / UIControl.h](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/UIKit.framework/Headers/UIControl.h)：结合 UIButton.h 的 menu 声明确认 showsMenuAsPrimaryAction 原生支持按钮主操作展示 UIMenu。

专属分析 agent：`/root/audit_group_a/c014`。

<a id="c015"></a>

### C015 · OrgEditorContainer

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Components/Editor/OrgKeyboardAccessory.swift:70)　置信度：high

当前实现：以 UIView、Auto Layout 和 UIKeyboardLayoutGuide 承载 UITextView 与可选工具条；焦点变化控制工具条显示，并同步底部内容与滚动指示器 inset，使正文延伸至浮动控件背后。

系统候选：无实质等价替换；UITextView.inputAccessoryView 是另一种系统承载机制，但不能仅凭 API 声明认定与现有覆盖布局等价。

判断：组件已经使用系统键盘布局指南与滚动 inset，没有自绘或键盘通知测量。现有测试明确要求正文延伸到浮动控件背后、末行光标避让且透明边距可操作。inputAccessoryView 可承载附件，却不能直接证明上述布局和命中语义等价；保留这层简短原生组合更合适。

预期收益：保留系统组合即可；换用 inputAccessoryView 仍需工具条与业务会话连接，并新增覆盖布局、焦点和触摸行为验证，未发现确定的复杂度收益。

必须保留：仅有可编辑会话时创建工具条，并随文本编辑焦点显示或隐藏；UITextView 铺满容器，正文可滚动到浮动玻璃控件背后；聚焦时为末行光标与滚动指示器增加 68 点底部空间，结束编辑时复原；与工具条子容器配合，让透明边距的触摸继续到达编辑器；当前 keyboardLayoutGuide 的 usesBottomSafeArea=false 设置及其键盘位置语义

验证要求：已阅读但未运行 OrgendaTests/Components/Editor/OrgSyntaxTextEditorTests.swift:55 testFloatingToolbarKeepsFinalCaretVisibleAndMarginsInteractive：末行光标、边距命中和失焦 inset 复原。；已阅读但未运行 OrgendaUITests/MotionFlowUITests.swift:740 testOrgKeyboardCommandsAndCaretSurvivePreview：正文延伸到控件背后、预览切换后焦点与插入点保持。；已阅读但未运行 OrgendaUITests/UIUXPolishUITests.swift:4 testEditorAccessoryUndoRedoAndDismissKeyboard：键盘上方按钮可达、撤销重做及收起键盘。；如考虑 inputAccessoryView 原型，需额外验证交互式收起、硬件键盘和 iPad 浮动/拆分键盘下的覆盖范围、触摸穿透与末行可见性；当前静态测试不能证明这些运行时情形。

代码依据：

- [Orgenda/Components/Editor/OrgKeyboardAccessory.swift:70](/Users/roifewu/.config/orgenda/Orgenda/Components/Editor/OrgKeyboardAccessory.swift:70) — UITextView 四边铺满；工具条挂到 keyboardLayoutGuide.topAnchor，并由 setKeyboardFocused 同步两类底部 inset。
- [Orgenda/Components/Editor/OrgSyntaxTextEditor.swift:182](/Users/roifewu/.config/orgenda/Orgenda/Components/Editor/OrgSyntaxTextEditor.swift:182) — UITextViewDelegate 开始/结束编辑时调用容器焦点方法；构造处仅向可编辑编辑器传入会话。
- [OrgendaUITests/MotionFlowUITests.swift:758](/Users/roifewu/.config/orgenda/OrgendaUITests/MotionFlowUITests.swift:758) — 显式要求编辑器底边超过工具按钮底边，证明浮动覆盖布局属于既有行为。

API 依据：

- [UIKit UIKeyboardLayoutGuide.h（iOS 27 SDK）](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/UIKit.framework/Headers/UIKeyboardLayoutGuide.h)：核实默认跟随停靠键盘、followsUndockedKeyboard 默认 false，以及 usesBottomSafeArea=false 在键盘离屏时使用容器底边；相关 API 在 iOS 27 目标可用。
- [UIKit UITextView.h / inputAccessoryView（iOS 27 SDK）](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/UIKit.framework/Headers/UITextView.h)：核实 UITextView 提供可读写 UIView 类型 inputAccessoryView；该声明本身未承诺应用编辑器覆盖布局或透明边距触摸穿透等价。
- [UIKit UIScrollView.h（iOS 27 SDK）](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/UIKit.framework/Headers/UIScrollView.h)：核实 contentInset 用于增加内容外围滚动区域，verticalScrollIndicatorInsets 为独立系统属性；现有实现直接使用这些原生能力。

专属分析 agent：`/root/audit_group_a/c015`。

<a id="c016"></a>

### C016 · OrgKeyboardAccessoryContainer

**保留：无等价系统组件 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Components/Editor/OrgKeyboardAccessory.swift:113)　置信度：high

当前实现：UIView 容器以原生 Auto Layout 将玻璃工具栏居中并限制到 420 点宽，保留安全区边距；仅 UIControl 命中接收触摸，其余透明区域穿透到编辑器。

系统候选：未找到等价现成容器；UIView 的安全区和约束已用于布局，UIInputView 或 UIToolbar 均不能直接取代当前控件限定的命中策略。

判断：该类的必要自定义行为是沿命中视图祖先查找 UIControl，让玻璃背景及留白交还下层编辑器。普通 UIView 的透明外观不表达这种命中策略；UIInputView 的背景和自适应尺寸 API 也不提供替代。布局已使用系统约束，改换容器仍需保留事件过滤，无法实质减少实现。

预期收益：保留短小的布局与事件适配层；无明确系统组件替换收益。父容器已有固定高度约束，但清理冗余尺寸配置属于普通重构。

必须保留：68 点容器高度、48 点工具栏高度及顶部 8 点间距；安全区左右至少 12 点边距、居中且最大宽度 420 点；按钮及其子视图正常命中，工具栏背景和空白透传到编辑器

验证要求：OrgendaTests/Components/Editor/OrgSyntaxTextEditorTests.swift:54 — testFloatingToolbarKeepsFinalCaretVisibleAndMarginsInteractive 已覆盖末尾光标与左侧留白命中；本次只读未运行。；OrgendaUITests/UIUXPolishUITests.swift:4 — testEditorAccessoryUndoRedoAndDismissKeyboard 检查按钮在键盘上方可点击及撤销、重做、收起。；若调整容器，需原型验证工具栏内部非按钮区域、圆角边缘和宽屏两侧留白仍可操作文本，按钮子视图仍正常接收点击。

代码依据：

- [Orgenda/Components/Editor/OrgKeyboardAccessory.swift:124](/Users/roifewu/.config/orgenda/Orgenda/Components/Editor/OrgKeyboardAccessory.swift:124) — 安全区居中、宽度上限与高度使用 NSLayoutConstraint；143 行仅保留 UIControl 祖先链的命中。
- [Orgenda/Components/Editor/OrgKeyboardAccessory.swift:64](/Users/roifewu/.config/orgenda/Orgenda/Components/Editor/OrgKeyboardAccessory.swift:64) — 工厂实际返回该容器；90 行作为编辑器覆盖层安装，95 行锚定键盘布局指南。
- [OrgendaTests/Components/Editor/OrgSyntaxTextEditorTests.swift:54](/Users/roifewu/.config/orgenda/OrgendaTests/Components/Editor/OrgSyntaxTextEditorTests.swift:54) — 现有测试明确要求工具栏外侧留白命中底层文本视图。

API 依据：

- [iOS 27 SDK UIView.h — hitTest:withEvent:、safeAreaLayoutGuide、intrinsicContentSize](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/UIKit.framework/Headers/UIView.h)：已核对 211 行命中测试、306 行安全区及 545–548 行固有尺寸声明；固定高度可由约束表达，但事件筛选仍需实现。
- [iOS 27 SDK UIInputView.h](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/UIKit.framework/Headers/UIInputView.h)：已核对 UIInputViewStyle、allowsSelfSizing 和初始化 API；这些输入容器能力未表达仅控件命中、背景穿透策略。
- [iOS 27 SDK UIToolbar.h](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/UIKit.framework/Headers/UIToolbar.h)：已核对 items、外观及布局相关公开接口；没有可直接替代当前 UIControl 祖先筛选的命中配置。

专属分析 agent：`/root/audit_group_a/c016`。

<a id="c017"></a>

### C017 · OrgSyntaxTextEditor

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Components/Editor/OrgSyntaxTextEditor.swift:8)　置信度：high

当前实现：以 UIViewRepresentable 包装原生 UITextView/TextKit 2，将 Org 高亮原地施加到 NSTextStorage，绑定仍保存纯文本；协调输入法、选区、滚动、Org 命令和文档撤销历史。

系统候选：现有 UITextView 已是系统编辑控件。iOS 27 可用 SwiftUI TextEditor 的 AttributedString/AttributedTextSelection 初始化器，但没有已验证的整体等价替代；普通 String TextEditor 不能承载当前分段语法样式。

判断：此处主要成本是 Org 编辑语义和连续性保护，而非重造输入控件。富文本 TextEditor 已支持样式与选区，但源码还要求高亮不进入撤销历史、中文组合期间不改存储、预览修改与输入共享撤销及外部版本清空历史。直接替换会重新引入协调层；当前没有能够实质删除这些逻辑的系统控件。

预期收益：保留现有原生桥接可避免引入 AttributedString 与纯文本、异步高亮及文档历史之间的第二套同步层；没有已确认可删减的实质替换收益。

必须保留：String 源码及 Unicode/UTF-16 选区准确性；高亮、工作流颜色和动态字体不改变源码；markedTextRange 存在时延迟高亮刷新，保持中文输入组合；原地更新样式并保留选区、滚动位置和 TextKit 2；Org 列表续行、命令选区映射和打字分组；跨预览/编辑的统一撤销；外部磁盘修订清除撤销记录，避免撤销覆盖其他写入者；只读可选取、非活动视图隐藏及搜索定位

验证要求：OrgendaTests/Components/Editor/OrgSyntaxTextEditorTests.swift:130 — testPreviewEditsAndNativeTypingShareUndoAcrossModes；OrgendaTests/Components/Editor/OrgSyntaxTextEditorTests.swift:170 — testCommandUndoRestoresSelectionAndExternalReloadClearsHistory；OrgendaTests/Components/Editor/OrgSyntaxTextEditorTests.swift:202 — testMarkedCompositionIsNotInterruptedByHighlightingAndCanBeUndone；OrgendaTests/Components/Editor/OrgSyntaxTextEditorTests.swift:660、702 — testPresentationAttributesPreserveSelectionAndSemanticTraits / testStaleHighlightRangesAreClampedWithoutMovingCaret；以上只静态阅读，未运行。若以后尝试富文本 TextEditor，须用中文输入法、长文滚动、连续高亮刷新、跨模式撤销和外部重载原型验证等价性。

代码依据：

- [Orgenda/Components/Editor/OrgSyntaxTextEditor.swift:41](/Users/roifewu/.config/orgenda/Orgenda/Components/Editor/OrgSyntaxTextEditor.swift:41) — 创建原生 UITextView/TextKit 2；157 行处理外部修订，168 行拦截 Org 续行，271 行原地刷新表现属性。
- [Orgenda/Components/Editor/OrgSyntaxTextEditor.swift:282](/Users/roifewu/.config/orgenda/Orgenda/Components/Editor/OrgSyntaxTextEditor.swift:282) — 组合文本期间跳过更新；318 行禁用表现更新的撤销注册，354–355 行恢复选区和滚动位置。
- [Orgenda/Features/Files/Document/OrgDocumentView.swift:39](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Document/OrgDocumentView.swift:39) — 通过 HighlightedOrgEditor 传入文档绑定、持久编辑会话、活动状态及外部修订计数。

API 依据：

- [iOS 27 SDK SwiftUI.TextEditor 声明](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：3889–3916 行核实 String、TextSelection 及 iOS 26 起的 AttributedString/AttributedTextSelection 初始化器；后者在本项目 iOS 27 下可用。
- [iOS 27 SDK UITextView.h](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/UIKit.framework/Headers/UITextView.h)：263–281 行确认 TextKit 2 创建入口、textLayoutManager 和 textStorage；显式避免访问 layoutManager 可避免退回 TextKit 1。
- [iOS 27 SDK UITextInput.h](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/UIKit.framework/Headers/UITextInput.h)：139–141 行确认 markedTextRange 与 setMarkedText 是原生输入组合接口，支持当前协调器的组合保护实现。

专属分析 agent：`/root/audit_group_a/c017`。

<a id="c018"></a>

### C018 · OrgHeadingDragSource

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Components/Gestures/OrgHeadingDrag.swift:47)　置信度：high

当前实现：以 SwiftUI draggable、dragContainer、DragConfiguration 和拖动会话回调提供原生标题拖放；缓存本次传输令牌，调用业务层验证源文档，并按取消或传输完成清理状态。

系统候选：无实质替代；当前已使用系统拖放。iOS 27 的 draggable(_:containerNamespace:_:) 可表达单项可选载荷，但不能消除业务快照、令牌缓存和生命周期处理。

判断：这是两处页面复用的原生拖放业务包装，没有自绘拖动手势。容器在起拖时按标题 ID 请求载荷，缓存令牌避免重复取值更换验证快照；成功移动保留状态至数据交付完成。直接换为普通 draggable 或 List.onMove 会遗漏本地身份、快照和树移动语义。单项可选载荷重载最多减少容器声明，尚无值得替换此抽象的实质收益。

预期收益：保留可避免大纲与预览重复实现会话保护；改成其他系统包装无法明显减少复杂度。

必须保留：一次拖动复用同一令牌及已验证文档快照，onBegin 失败可拒绝起拖；保留 headingID 本地拖动身份供放置目标核验；允许应用内移动并禁止应用外复制；取消及时清理，成功移动不得在载荷交付前清空业务会话；预览含图标题可禁用拖动

验证要求：OrgendaUITests/MotionFlowUITests.swift:528 testOutlineDragNestsMovesOutAndUpdatesPreviewSourceAndUndo（已有，未运行）；OrgendaUITests/MotionFlowUITests.swift:622 testPreviewDragOntoHeadingNestsReparentsAndOutdentsWholeSubtree（已有，未运行）；OrgendaUITests/MotionFlowUITests.swift:677 testCancelledPreviewHeadingDragDoesNotChangeSource（已有，未运行）；OrgendaTests/Domain/Org/OrgHeadingMoveTests.swift:188 testStoreRejectsStaleSnapshotIncludingCanonicallyEqualUnicode（已有，未运行）；若试单项 draggable 重载，需验证重复载荷请求、localSession 标题 ID、取消后再次起拖及 ended(.move) 后异步交付时序；静态 SDK 声明不能证明这些交互等价

代码依据：

- [Orgenda/Components/Gestures/OrgHeadingDrag.swift:57](/Users/roifewu/.config/orgenda/Orgenda/Components/Gestures/OrgHeadingDrag.swift:57) — 已使用系统拖放，缓存载荷并区分 ended 与 dataTransferCompleted；同文件 :133 的目标校验依赖 draggedItemIDs
- [Orgenda/Features/Files/Preview/InteractiveOrgPreview.swift:149](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/InteractiveOrgPreview.swift:149) — beginHeadingDrag 拒绝未提交编辑及源文档/解析快照不一致；Orgenda/Features/Files/Preview/OrgPreviewHeading.swift:54 使用此组件并禁用含图标题
- [Orgenda/Features/Files/Document/DocumentOutline.swift:233](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Document/DocumentOutline.swift:233) — 大纲起拖执行源快照验证；:462 为第二处实际调用

API 依据：

- [iOS 27 SDK SwiftUI View 拖放声明](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对 :32078–32116，containerItemID、可选载荷重载、dragContainer、onDragSessionUpdated 和 dragConfiguration 均在最低目标 iOS 27 可用；:4057 的会话阶段及 :19462 的应用内外操作配置。
- [Apple draggable(containerItemID:containerNamespace:)](https://developer.apple.com/documentation/swiftui/view/draggable%28containeritemid%3Acontainernamespace%3A%29?language=objc%2Cobjc)：官方说明容器仅需标题 ID，在拖动开始时才请求实际载荷，并由系统生成手势与预览。
- [Apple draggable(_:id:containerNamespace:_:)](https://developer.apple.com/documentation/swiftui/view/draggable%28_%3Aid%3Acontainernamespace%3A_%3A%29?changes=_4)：核对可选单项载荷重载确实存在；文档并未替代本项目的令牌和源快照职责。

专属分析 agent：`/root/audit_group_a/c018`。

<a id="c019"></a>

### C019 · OrgHeadingDropModifier

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Components/Gestures/OrgHeadingDrag.swift:91)　置信度：high

当前实现：用 SwiftUI dropDestination、dropConfiguration 和 onDropSessionUpdated 接收本地单标题移动，依据标题几何划分前置、后置和嵌套落点，并更新目标高亮。

系统候选：现用 SwiftUI DropSession 系列已是原生方案；iOS 27 reorderable()/reorderContainer 可处理集合排序，但不能直接等价替代当前标题三段落点与 Org 子树嵌套规则。

判断：预览和大纲共享此原生拖放封装。它额外校验本地拖动标题、单项数量及会话 token，禁止拖向自身或后代，并将标题上下四分之一与中部映射为前、后、子级。iOS 27 自动排序接口提供集合标识和 before/end 位置，未直接表达标题中央嵌套及这些有效性规则；移植仍需业务适配与交互原型，未发现可无损删去此封装的系统替代。

预期收益：保留共享封装可避免大纲和预览重复维护拖放规则；现阶段没有可确认的原生替换复杂度收益。

必须保留：仅接收与已验证文档快照会话相符的本地单项标题拖动；拒绝自身和后代目标，允许跨父级移动；标题前置、后置、子级三个落点及标题边界测量的整行高度回退；会话进入、更新、离开和结束时维护共享落点高亮；通过 onMove 保留现有子树迁移、源文档保护和编辑连续性

验证要求：OrgendaTests/Domain/Org/OrgHeadingMoveTests.swift:110 — testDropZonesSeparateNestingFromReorderingAndAllowCrossParentMoves 覆盖三段落点、自身/后代拒绝与跨父级移动；本次仅阅读，未运行。；OrgendaTests/Domain/Org/OrgHeadingMoveTests.swift:188 — testStoreRejectsStaleSnapshotIncludingCanonicallyEqualUnicode 验证移动使用的源快照保护；本次仅阅读，未运行。；OrgendaUITests/MotionFlowUITests.swift:528、622、677 — 已有大纲嵌套移出与撤销、预览重挂载、取消拖动测试；本次仅阅读，未运行。；若尝试 reorderContainer，需原型验证折叠/过滤子树、标题中央嵌套、非法目标禁止反馈、会话 token 不匹配拒绝及取消后高亮清理，不能由 API 签名认定交互等价。

代码依据：

- [Orgenda/Components/Gestures/OrgHeadingDrag.swift:91](/Users/roifewu/.config/orgenda/Orgenda/Components/Gestures/OrgHeadingDrag.swift:91) — 原生 DropSession 组合；107-136 行校验单项、token、本地标题身份与祖先链，139 行按标题边界计算落点。
- [Orgenda/Features/Files/Preview/OrgPreviewContent.swift:53](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/OrgPreviewContent.swift:53) — 仅标题行启用修饰器并接入子树移动回调；DocumentOutline.swift:465 同样复用该修饰器。
- [OrgendaTests/Domain/Org/OrgHeadingMoveTests.swift:110](/Users/roifewu/.config/orgenda/OrgendaTests/Domain/Org/OrgHeadingMoveTests.swift:110) — 三段落点与跨父级规则有直接单元测试；MotionFlowUITests.swift:622 验证预览嵌套、重挂载、移出及源文本结果。

API 依据：

- [iOS 27 SDK SwiftUI dropDestination、onDropSessionUpdated、dropConfiguration 与 DropSession 声明](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：2576-2590 行确认 session 版 dropDestination 可用于 iOS 26+，另外两项可用于 iOS 27+；10778-10814 行确认 localSession、draggedItemIDs、itemsCount、location 和会话阶段。符合最低 iOS 27 目标。
- [iOS 27 SDK SwiftUI reorderable、reorderContainer 与 ReorderDifference 声明](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：12430-12479 行确认自动排序接口在 iOS 27 可用，目标位置枚举仅 before(ItemID)/end，另带 collectionID；不能据此声称标题中央嵌套、身份校验与禁入规则已获等价实现。

专属分析 agent：`/root/audit_group_a/c019`。

<a id="c020"></a>

### C020 · HabitHistoryView

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Components/HabitHistoryView.swift:3)　置信度：high

当前实现：使用 LazyVGrid、ForEach 和 RoundedRectangle 显示截至今天的 28 天习惯完成情况；正常字号 14 列、辅助字号 7 列，每天提供日期、完成状态和可访问性标识。

系统候选：保留现有 LazyVGrid 系统布局。MultiDatePicker 是日期选择控件，不能直接替代此只读完成记录；未发现能删除该业务封装的等价系统组件。

判断：该组件已由系统网格与图形组成，只封装连续 28 天记录、完成配色与可访问性语义，且在编辑器和上下文预览复用。SDK 中 MultiDatePicker 以日期集合绑定实现选择，没有此完成记录呈现契约；换为该控件会改变用途，也不能消除业务映射。保留现有小型封装最直接。

预期收益：无实质替换收益；现有封装已避免重复业务与可访问性配置，无需引入额外日历适配。

必须保留：按时间从旧到新显示今天及此前 27 天；通过 orgendaDayKey 匹配完成日期；正常 14 列、辅助字号 7 列的布局；每日日期、完成状态和 habit.history 日期标识；编辑器与上下文预览复用同一只读视图

验证要求：OrgendaUITests/MotionFlowUITests.swift:4 的 testHabitContextPreviewShowsHistoryWithoutOpeningEditor 验证预览展示 28 个历史元素且未打开编辑器；本次仅阅读，未运行。；若未来改变布局，需验证辅助字号下 7 列、跨月连续 28 天顺序及 VoiceOver 日期和完成状态；现有测试未覆盖这些交互。

代码依据：

- [Orgenda/Components/HabitHistoryView.swift:8](/Users/roifewu/.config/orgenda/Orgenda/Components/HabitHistoryView.swift:8) — 系统 LazyVGrid 以 14/7 列显示 28 个圆角方格，逐日提供可访问性标签和状态。
- [Orgenda/Components/OrgContextPreview.swift:75](/Users/roifewu/.config/orgenda/Orgenda/Components/OrgContextPreview.swift:75)；Orgenda/Features/ItemEditor/OrgItemEditor.swift:342 — 上下文预览与编辑器均复用该组件。
- [OrgendaUITests/MotionFlowUITests.swift:4](/Users/roifewu/.config/orgenda/OrgendaUITests/MotionFlowUITests.swift:4) — 上下文预览测试断言 28 个历史元素且未打开编辑器。

API 依据：

- [iOS 27 SDK SwiftUI.LazyVGrid](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：30117–30127 行确认 LazyVGrid 接受 GridItem 列配置与 View 内容，是当前已使用的系统网格。
- [iOS 27 SDK SwiftUI.MultiDatePicker](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：17329–17364 行确认其选择参数为 Binding<Set<DateComponents>>，可约束日期范围；未提供此 28 天只读完成格及 14/7 列布局契约。

专属分析 agent：`/root/audit_group_a/c020`。

<a id="c021"></a>

### C021 · OrgContextPreview

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Components/OrgContextPreview.swift:5)　置信度：high

当前实现：以 VStack、Label、Text 和系统背景组成固定宽度的只读菜单预览，接收标题、来源、副标题颜色、工作流图标及泛型内容；菜单呈现由原生 contextMenu 提供。

系统候选：无实质替代；继续使用 contextMenu(menuItems:preview:) 与现有原生视图组合。GroupBox 可包裹内容，但不能消除预览内容配置。

判断：该组件只是复用原生菜单预览的内容布局，没有自定义菜单呈现或交互。条目和文件两类调用都需要标题、来源及不同的只读摘要；GroupBox 仍需保留这些内容、限行与尺寸配置，不能实质减少实现。删除 preview 参数也会失去扩展摘要，因此保留此轻量封装。

预期收益：保留共享布局可避免条目与文件预览重复；未发现系统组件替换能带来实质复杂度收益。

必须保留：标题最多三行、来源最多两行及统一 300 点宽度；按工作流状态显示图标和标题色；泛型只读摘要可展示习惯历史、文件内容或文件夹子项；长按展示预览不打开编辑器、不导航或触发文件加载

验证要求：OrgendaUITests/MotionFlowUITests.swift:4 testHabitContextPreviewShowsHistoryWithoutOpeningEditor 覆盖历史展示及不打开编辑器。；OrgendaUITests/MotionFlowUITests.swift:18 testHapticTouchFilePreviewOpenAndMove 覆盖文件摘要及预览不导航；本次仅静态核对，未执行。

代码依据：

- [Orgenda/Components/OrgContextPreview.swift:14](/Users/roifewu/.config/orgenda/Orgenda/Components/OrgContextPreview.swift:14) — 原生 VStack/Label/Text 组合并限制尺寸，无副作用逻辑。
- [Orgenda/Components/OrgContextPreview.swift:42](/Users/roifewu/.config/orgenda/Orgenda/Components/OrgContextPreview.swift:42) — 条目摘要复用，支持工作流标记及附加内容。
- [Orgenda/Features/Files/WorkspaceDocumentContextPreview.swift:8](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/WorkspaceDocumentContextPreview.swift:8) — 文件和文件夹摘要复用，生产菜单入口见 WorkspaceFileActions.swift:37。

API 依据：

- [SwiftUI contextMenu(menuItems:preview:) 与 GroupBox SDK 声明](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：12144–12150 确认原生菜单自定义 preview 重载自 iOS 16 可用；15952–15959 确认 GroupBox 仍由调用方提供 label/content；30896–30897 确认 Label 接受自定义标题和图标，均满足 iOS 27 最低目标。

专属分析 agent：`/root/audit_group_a/c021`。

<a id="c022"></a>

### C022 · OrgItemContextPreview

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Components/OrgContextPreview.swift:38)　置信度：high

当前实现：为原生 contextMenu 的 preview 提供 OrgItem 只读快照，使用 Label、Text、VStack/HStack 和现有预览容器，显示工作流、日期、限长正文、标签及习惯的 28 日历史。

系统候选：继续使用 SwiftUI contextMenu(menuItems:preview:) 与现有 Label/Text 组合；没有能直接生成这些 Org 业务字段的等价系统预览组件。

判断：两处生产调用已经把此视图交给系统 contextMenu 的 preview 构建器。其代码负责 Org 字段选择、正文 800 字符及行数限制、工作流表现和习惯历史，而非自行实现菜单交互。系统默认预览仅复用触发视图，不能等价保留这份只读摘要；替换为 LabeledContent 等基础控件仍需相同业务组合，未见实质简化收益。

预期收益：保留现有抽象可让普通条目和全天条目共用摘要；改用另一基础系统容器不能消除业务逻辑，预计没有实质复杂度收益。

必须保留：预览只读取传入条目，不加载文件、不打开编辑器、不修改工作区；保留工作流图标与标题颜色、源文件名和有时间／无时间日期格式；正文限制为 800 字符及 8 行，标签限制为 2 行；习惯显示 28 日完成记录及日期范围，保留可访问性标识

验证要求：OrgendaUITests/MotionFlowUITests.swift:4 testHabitContextPreviewShowsHistoryWithoutOpeningEditor 已覆盖长按显示 28 个历史单元且不出现编辑器；本次仅阅读，未运行。；如以后调整预览容器，需在最大辅助字号和长正文／多标签条目下验证内容限制、菜单可用性及 VoiceOver；静态源码不能证明这些布局交互。

代码依据：

- [Orgenda/Components/OrgContextPreview.swift:38](/Users/roifewu/.config/orgenda/Orgenda/Components/OrgContextPreview.swift:38) — 条目摘要仅由不可编辑的系统视图和习惯历史视图构成，正文显式截断并限制行数。
- [Orgenda/Components/OrgItemRow.swift:132](/Users/roifewu/.config/orgenda/Orgenda/Components/OrgItemRow.swift:132) — 生产条目行直接在 SwiftUI contextMenu 的 preview 闭包使用；AgendaDayContent.swift:75 对全天条目复用。
- [OrgendaUITests/MotionFlowUITests.swift:4](/Users/roifewu/.config/orgenda/OrgendaUITests/MotionFlowUITests.swift:4) — 已有测试检查长按习惯预览的 28 日历史及不打开编辑器。

API 依据：

- [iOS 27 SDK — View.contextMenu(menuItems:preview:)](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：第 12145–12148 行确认自 iOS 16 可用，preview 是调用方提供的泛型 View；当前实现已使用此系统入口。第 30895–30907 行确认 Label 为系统 View。

专属分析 agent：`/root/audit_group_a/c022`。

<a id="c023"></a>

### C023 · OrgItemRow

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Components/OrgItemRow.swift:4)　置信度：high

当前实现：以原生 Button、Text、HStack/VStack、swipeActions、contextMenu 和 draggable 组成任务行，展示工作流状态、优先级、来源、标签及习惯历史；完成和打开编辑器是独立操作。

系统候选：继续使用现有 SwiftUI Button、swipeActions、contextMenu 和 draggable；Toggle(isOn:) 仅适合布尔状态，不是整行或重复事项完成命令的等价替代。没有可实质减少实现的单个系统组件。

判断：主要交互已经交给系统控件。完成按钮可触发工作流备注编辑或推进重复事项，不能仅改为布尔 Toggle；优先级、习惯历史和来源路径仍需业务组合。调用方传入原始任务作为拖拽载荷，并移除日历及非活跃视图的滑动宿主以保护翻页与关闭状态。替换为通用列表行不会消除这些职责。

预期收益：保留现有业务封装与系统交互即可；改用 Toggle 或 UIKit 列表单元仍需实现相同布局、回调和拖拽语义，没有明确的复杂度收益。

必须保留：完成与打开编辑器的独立点击区域，以及不能完成事项的只读状态图标；重复事项完成一次、工作流切换可能要求备注，以及由调用方处理错误和撤销；拖动使用 canonical dragItem，且仅可改期任务提供拖拽和改期入口；日历模式禁用滑动宿主，非活跃视图移除滑动动作，尾部禁用全滑执行；上下文预览、Show in File、可访问性标签/操作、减少动态效果设置、动态标题换行和习惯历史

验证要求：已阅读 OrgendaUITests/MotionFlowUITests.swift:292 testGestureTaskSwipesCompleteRescheduleAndUndo 与 :314 testNativeTaskSwipeClosesAcrossPerspectiveChanges；本次不运行测试。；已阅读 OrgendaUITests/MotionFlowUITests.swift:68 testPlainBirthdayOffersInlineCompletionAndUndo、:4 testHabitContextPreviewShowsHistoryWithoutOpeningEditor、:378 testGestureCalendarDropAndCancelledDrop，覆盖重复事项、预览和拖放。；若未来改变行结构，需在真机验证完成按钮拖拽与点击、VoiceOver 独立操作、日历横向翻页及视图切换后滑动关闭；源码不能证明手势运行时等价。

代码依据：

- [Orgenda/Components/OrgItemRow.swift:31](/Users/roifewu/.config/orgenda/Orgenda/Components/OrgItemRow.swift:31) — 条件性原生 swipeActions；:86 起组合两组独立按钮、原生拖拽和上下文预览。
- [Orgenda/Features/Agenda/AgendaView.swift:225](/Users/roifewu/.config/orgenda/Orgenda/Features/Agenda/AgendaView.swift:225) — 传入 canonical dragItem 并按模式/活跃视图移除滑动宿主；:239 起完成操作可能先进入备注编辑。
- [Orgenda/Services/Workspace/WorkspaceStore+Editing.swift:104](/Users/roifewu/.config/orgenda/Orgenda/Services/Workspace/WorkspaceStore+Editing.swift:104) — toggleDone 会推进重复日期、记录习惯、保存并保护错误，不只是翻转布尔值。

API 依据：

- [iOS 27 SDK SwiftUI.Toggle、View.swipeActions、View.contextMenu 和 View.draggable 声明](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对 6170 行 Toggle 接受 Binding<Bool>；20889 行 swipeActions、12148 行带预览 contextMenu、32121 行 Transferable draggable 均在目标平台可用。27.0 新增 onPresentationChanged 回调及 swipeActionsContainer 不直接替代业务行或强制关闭动作。

专属分析 agent：`/root/audit_group_a/c023`。

<a id="c024"></a>

### C024 · OrgRecurrenceEditor

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Components/OrgRecurrenceEditor.swift:4)　置信度：high

当前实现：以系统 Toggle、Stepper、菜单 Picker、LabeledContent 和 ViewThatFits 组合编辑 Org 重复规则，并同步可选字符串与解析后的草稿。

系统候选：继续使用现有 SwiftUI 控件；Calendar.RecurrenceRule 是日期规则模型，EKEventEditViewController 是日历事件编辑器，均不能等价替换此 Org 规则编辑视图。

判断：实际交互已由系统控件承担，封装负责 Org 的 +、++、.+ 模式、习惯最大间隔、无效规则提示及双向绑定。Foundation 的重复规则只提供模型与日期序列，EventKitUI 编辑器面向事件和事件库，不能消除这些 Org 语义。两个编辑入口共用该封装，未发现能减少实现且保持行为的系统替代。

预期收益：保持共享封装可避免两个入口复制规则绑定与校验；没有实质性系统组件替代收益。

必须保留：可选重复规则、allowsNever 限制及关闭后保留草稿；小时至年、三种完成后推进模式以及原始 Org token；习惯最大间隔与同单位时不小于基本间隔的归一化；未操作前保留不支持的原规则并提示，显式修改后替换；窄宽度的模式选择布局及现有无障碍标识

验证要求：OrgendaUITests/MotionFlowUITests.swift:1254 — testPlanningPreviewAddsYearlyRecurrence 覆盖启用、选择年及写回 token。；OrgendaUITests/MotionFlowUITests.swift:1277 — testPlainRecurringTimestampPreviewUsesControlsAndRemovesRule 覆盖间隔、完成日起算、最大间隔、移除规则及保留警告。；OrgendaTests/Domain/Org/OrgSourceMutationTests.swift:160 — testRecurrenceEditingPreservesWarningTimeRangeAndWhitespace；:553 — testStrictRepeaterParsingAcceptsConfiguredAndHabitIntervals。；仅静态阅读，未运行测试；若调整布局需验证最大动态字体下 ViewThatFits 与菜单可达性。

代码依据：

- [Orgenda/Components/OrgRecurrenceEditor.swift:17](/Users/roifewu/.config/orgenda/Orgenda/Components/OrgRecurrenceEditor.swift:17) — 系统控件组成；:87 负责最大间隔归一化和 recurrence/draft 同步。
- [Orgenda/Domain/Org/Planning/OrgRepeater.swift:5](/Users/roifewu/.config/orgenda/Orgenda/Domain/Org/Planning/OrgRepeater.swift:5) — 三种 Org 模式、五种单位及习惯最大间隔；:80 明确完成日期推进语义。
- [Orgenda/Features/ItemEditor/OrgItemEditor.swift:280](/Users/roifewu/.config/orgenda/Orgenda/Features/ItemEditor/OrgItemEditor.swift:280) 与 Orgenda/Features/Files/Preview/OrgPlanningEditorSheet.swift:152 — 两个生产编辑入口共用此组件。

API 依据：

- [iOS 27 SwiftUI SDK — Stepper、Picker、Toggle、ViewThatFits](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：核对系统控件声明及 Stepper 的 Binding/ClosedRange 初始化器；现实现已经使用这些原生 API。
- [iOS 27 Foundation SDK — Calendar.RecurrenceRule](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/Foundation.framework/Modules/Foundation.swiftmodule/arm64e-apple-ios.swiftinterface)：2337 起声明频率、间隔、结束条件和 recurrences；可用于日期模型但没有编辑 UI，也没有 Org 完成日起算模式或习惯最大间隔字段。
- [iOS 27 EventKitUI SDK — EKEventEditViewController](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/EventKitUI.framework/Headers/EKEventEditViewController.h)：核对其创建/编辑 EKEvent 并必须提供 eventStore 的契约；它不是独立的 Org 重复规则选择器。

专属分析 agent：`/root/audit_group_a/c024`。

<a id="c025"></a>

### C025 · OrgendaTagList

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Components/Tags/OrgendaTagList.swift:4)　置信度：high

当前实现：以 Text、ForEach、字体、内边距和圆角背景显示只读标签，调用 OrgendaFlowLayout 按可用宽度换行；长标签允许增加文字高度。

系统候选：保留现有原生 Text 样式封装；HStack、LazyVGrid 均不是等价替代，未发现能实质删除此封装的系统标签控件。

判断：该组件只有标签展示与统一样式，已使用系统文本和形状；标签由任务行传入且位于打开条目的 Button 内，不涉及独立选择。HStack 只排单行，LazyVGrid 按列分配单元格，均不能直接保留按各标签宽度连续换行的行为。真正的排布逻辑由共享 Layout 承担，改用网格或交互控件不会减少本组件的必要复杂度。

预期收益：保留有明确调用的短封装，维持统一标签样式；无实质系统替换收益。

必须保留：标签原始顺序及重复文本的逐项显示；可用宽度内自动换行，长标签保留完整文字高度；统一字体、颜色、圆角与间距；标签作为任务打开按钮内容，不新增独立交互

验证要求：检索 OrgendaTests 未发现 OrgendaTagList 或 OrgendaFlowLayout 的直接测试；本次仅静态审查。；若调整容器，需原型核对窄屏、动态大字体、超长单标签和重复标签的完整显示，并确认点击标签仍打开原任务。

代码依据：

- [Orgenda/Components/Tags/OrgendaTagList.swift:8](/Users/roifewu/.config/orgenda/Orgenda/Components/Tags/OrgendaTagList.swift:8) — FlowLayout 内用 Text 与系统修饰器呈现标签，按枚举 offset 标识。
- [Orgenda/Components/OrgItemRow.swift:117](/Users/roifewu/.config/orgenda/Orgenda/Components/OrgItemRow.swift:117) — 非空 item.tags 在 onOpen 按钮内容内使用该组件。
- [Orgenda/DesignSystem/Layout/OrgendaFlowLayout.swift:29](/Users/roifewu/.config/orgenda/Orgenda/DesignSystem/Layout/OrgendaFlowLayout.swift:29) — 按提议宽度测量子视图，在累计宽度超限时移到下一行。

API 依据：

- [Apple HStack](https://developer.apple.com/documentation/swiftui/hstack)：已读取官方 Markdown 文档：HStack 将子视图排成单条水平线。
- [Apple LazyVGrid](https://developer.apple.com/documentation/swiftui/lazyvgrid)：已读取官方 Markdown 文档：以 GridItem 定义列，子视图依次占据网格单元。
- [Apple fixedSize(horizontal:vertical:)](https://developer.apple.com/documentation/swiftui/view/fixedsize(horizontal:vertical:))：已读取官方 Markdown 文档：可分别控制两轴的理想尺寸；当前仅固定垂直轴。
- [iOS 27 SDK SwiftUI GridItem / LazyVGrid declarations](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：核对 GridItem.Size.adaptive 与 LazyVGrid(columns:) 声明，均为网格列 API。

专属分析 agent：`/root/audit_group_a/c025`。

<a id="c026"></a>

### C026 · OrgWorkflowIcon

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Components/Workflow/OrgWorkflowControls.swift:5)　置信度：high

当前实现：以 SwiftUI Text(Image(systemName:)) 显示工作流符号，解析传入状态或环境关键词，统一颜色、未知状态回退与辅助功能名称。

系统候选：现用 Text(Image(systemName:)) 已是系统实现；Label(...).labelStyle(.iconOnly) 可显示单图标，但不能消除工作流映射，暂无有实质收益的替代。

判断：该组件没有自绘或自建交互，只把原生符号嵌入 Text，供多行标题按首行基线排列。状态可来自传入模型或文档环境，需保留自定义图标、颜色和未知关键词回退。改用单图标 Label 仍需这些业务逻辑，基线表现也需验证，无法实质减少实现。

预期收益：保留统一封装即可；替换成其他原生显示方式不会去除业务配置，拆散后反而增加调用点重复。

必须保留：传入完整状态优先，否则按当前文档的工作流配置解析关键词；配置的符号、颜色和本地化或自定义状态名称；未知关键词使用 questionmark.circle、secondary 颜色及原关键词辅助功能名称；继承字体并与多行标题首行基线对齐，固定图标固有尺寸

验证要求：OrgendaTests/Domain/Org/WorkspaceConfigurationTests.swift:86 testSparseKeywordOverridesPreserveDefaultAppearance 覆盖配置状态默认符号和明暗颜色；本次仅阅读。；OrgendaTests/Domain/Org/WorkspaceConfigurationTests.swift:103 testExplicitStateStyleSurvivesSaveAndDoesNotAffectOtherStates 覆盖状态样式覆盖与持久化；本次仅阅读。；若试用 iconOnly Label，需原型验证大字体、多行标题首行基线，以及日志未知关键词的 VoiceOver 名称；当前未进行运行时验证。

代码依据：

- [Orgenda/Components/Workflow/OrgWorkflowControls.swift:14](/Users/roifewu/.config/orgenda/Orgenda/Components/Workflow/OrgWorkflowControls.swift:14) — 状态解析后使用 Text(Image)、foregroundStyle、fixedSize 和 accessibilityLabel。
- [Orgenda/Features/Search/SearchResultLabel.swift:23](/Users/roifewu/.config/orgenda/Orgenda/Features/Search/SearchResultLabel.swift:23) — 状态图标与可换行标题放在 firstTextBaseline HStack 中。
- [Orgenda/Features/Files/Preview/OrgPreviewDrawer.swift:103](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/OrgPreviewDrawer.swift:103) — 工作流日志通过 keyword 初始化展示前后状态，并组合辅助功能元素。

API 依据：

- [iOS 27 SDK — Text.init(_ image: Image)、Image.init(systemName:) 与 VerticalAlignment.firstTextBaseline](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUICore.framework/Modules/SwiftUICore.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对第 9670、11239、14183 行声明；Text(Image) 从 iOS 14 可用，现有方案在最低 iOS 27 上直接可用。
- [iOS 27 SDK — LabelStyle.iconOnly / IconOnlyLabelStyle](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对第 11959 行起原生单图标 Label 样式存在；声明不证明它与 Text(Image) 在当前基线布局中完全等价。

专属分析 agent：`/root/audit_group_a/c026`。

<a id="c027"></a>

### C027 · OrgWorkflowPicker

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Components/Workflow/OrgWorkflowControls.swift:22)　置信度：high

当前实现：以原生菜单样式 Picker 展示工作流状态，使用 Label、字符串 tag 与 Binding 映射完整状态，并以隐藏 Button 注册配置中的单键快捷键。

系统候选：继续使用 SwiftUI Picker、MenuPickerStyle、currentValueLabel 与 Button.keyboardShortcut；未发现可实质减少实现且保持行为的系统替代。

判断：主体已经是系统 Picker，并使用原生当前值标签能力。包装层负责将稳定 token 映射回包含图标、颜色和日志规则的配置状态，同时提供动态快捷键及可访问性标识。直接内联 Picker 只会搬移这些业务规则；改用 Menu 按钮还需重建选择语义。隐藏按钮的快捷键行为已有针对性 UI 测试，不能仅把快捷键移到无动作的选项标签就视为等价。

预期收益：保留轻量业务封装即可；替换为另一种原生容器没有已证实的复杂度收益。

必须保留：按文档工作流提供状态顺序，并以 rawValue 选择后回写完整配置状态；状态自定义或本地化名称、系统图标、颜色及当前值显示；配置的无修饰键快捷键，以及文本编辑时不误触状态切换；workflow.option.*、item.editor.state 标识和状态可访问性值

验证要求：OrgendaUITests/MotionFlowUITests.swift:1165 — testWorkflowPickerSelectsTerminalAndActiveStatesAndSaves 覆盖完成与活动状态选择、保存和 Org 源码结果。；OrgendaUITests/ConfigurationUITests.swift:525 — testWorkflowKeyboardShortcutsRespectTextEditing 覆盖 d 切换和标题输入 t 不误触；本次仅读取，未执行。；OrgendaUITests/DatePresentationUITests.swift:310 — verifyChinese 校验菜单 TODO 的简体、繁体本地化标签；若调整原生菜单或快捷键承载方式，需在 iOS 27 实机回归上述交互。

代码依据：

- [Orgenda/Components/Workflow/OrgWorkflowControls.swift:28](/Users/roifewu/.config/orgenda/Orgenda/Components/Workflow/OrgWorkflowControls.swift:28) — 原生 Picker 以 token 绑定、配置状态列表和 currentValueLabel 实现菜单选择。
- [Orgenda/Components/Workflow/OrgWorkflowControls.swift:53](/Users/roifewu/.config/orgenda/Orgenda/Components/Workflow/OrgWorkflowControls.swift:53) — 隐藏原生 Button 按配置注册 keyboardShortcut，并排除额外可访问性节点。
- [Orgenda/Features/ItemEditor/OrgItemDetailsSection.swift:15](/Users/roifewu/.config/orgenda/Orgenda/Features/ItemEditor/OrgItemDetailsSection.swift:15) — 生产调用将 draft.state 与 workflow.states 传入，并设置编辑器状态标识。

API 依据：

- [iOS 27 SDK — SwiftUI Picker currentValueLabel、MenuPickerStyle 与 keyboardShortcut](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对 18254–18257 行的 Picker 当前值标签初始化器（iOS 18+）、26817–26828 行的 View.keyboardShortcut（iOS 14+）及 30526–30546 行的 MenuPickerStyle（iOS 14+）；均满足最低 iOS 27。声明核验不构成隐藏控件或文本焦点交互的运行证明。

专属分析 agent：`/root/audit_group_a/c027`。

<a id="c028"></a>

### C028 · OrgWorkflowLabel

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Components/Workflow/OrgWorkflowControls.swift:64)　置信度：high

当前实现：将 OrgWorkflowState 的显示标题和 SF Symbol 交给原生 SwiftUI Label；用于状态 Picker 和大纲筛选 Toggle 的标签。

系统候选：现有实现就是 Label(state.title, systemImage: state.symbol)；可内联同一表达式，但没有实质系统组件替换。

判断：组件没有自定义布局、绘制或交互，直接使用系统 Label，并由调用者施加颜色和可访问性标识。状态标题支持本地化及用户配置，图标来自状态模型。内联虽等价，但只会将这层语义映射重复到三个调用点，无法消除实际自定义控制逻辑，保留短封装更合适。

预期收益：没有实质复杂度收益；保留可集中表达工作流状态标签语义。

必须保留：状态标题的本地化与用户自定义标签；状态模型指定的 SF Symbol；调用端的颜色、标签样式与可访问性标识

验证要求：OrgendaUITests/DatePresentationUITests.swift:310 verifyChinese 验证状态菜单 TODO 的简繁体可访问性标签。；OrgendaUITests/UIUXPolishUITests.swift:50 testOutlineEmptyFilterCanBeClearedInPlace 覆盖筛选状态标签所在 Toggle。；OrgendaTests/Services/Workspace/WorkspaceConnectionTests.swift:7 testConfigurationUpdatesRefreshTaskMetadataWithoutRewritingSource 覆盖配置标签和图标更新；本次仅阅读，未运行测试。

代码依据：

- [Orgenda/Components/Workflow/OrgWorkflowControls.swift:64](/Users/roifewu/.config/orgenda/Orgenda/Components/Workflow/OrgWorkflowControls.swift:64) — body 只有系统 Label；同文件第32、40行用于 Picker 选项及当前值。
- [Orgenda/Features/Files/Document/DocumentOutline.swift:337](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Document/DocumentOutline.swift:337) — 作为 Toggle 标签复用，颜色与标识在外层设置。
- [Orgenda/Domain/Org/OrgWorkflow.swift:41](/Users/roifewu/.config/orgenda/Orgenda/Domain/Org/OrgWorkflow.swift:41) — title 优先使用配置 label，否则按内置状态本地化并回退原始 token。

API 依据：

- [SwiftUI Label.init(_:systemImage:) — iOS 27 SDK](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：第30895–30928行声明 Label 及 StringProtocol 标题加 systemImage 的初始化器，自 iOS 14 可用；现有实现已经采用该系统 API。

专属分析 agent：`/root/audit_group_a/c028`。

<a id="c029"></a>

### C029 · View.orgendaEmptyState

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/DesignSystem/Layout/OrgendaEmptyState.swift:6)　置信度：high

当前实现：以原生 ScrollView 包装任意占位内容，铺满宽度；用 alignment 角色居中较短内容，并按内容大小启用回弹。多数调用者本身已使用 ContentUnavailableView。

系统候选：现有 ScrollView、defaultScrollAnchor(_:for:)、scrollBounceBehavior 已是对应系统方案；ContentUnavailableView 已用于具体占位内容，无额外实质替代项。

判断：该扩展没有自绘或手写尺寸测量，只集中配置系统滚动容器。多数调用点已是 ContentUnavailableView；删除包装会移除短内容居中、溢出滚动和按尺寸回弹配置，也影响自定义搜索占位。iOS 27 SDK 支持全部现用 API，保留此复用入口即可。

预期收益：无实质复杂度收益；当前短封装已避免多个调用点重复相同系统配置。

必须保留：较短内容在可用区域垂直居中；短窗口或大字号下文字及操作可通过滚动到达；只有内容需要滚动时回弹；兼容原生占位视图和自定义搜索内容

验证要求：OrgendaUITests/UIUXPolishUITests.swift:50 testOutlineEmptyFilterCanBeClearedInPlace 检查空筛选状态及 Clear filters 可点击并恢复列表；本次只读未运行。；现有测试未直接覆盖此扩展的大字号与矮视口组合；后续若调整配置，应验证内容居中、完整滚动可达及恢复按钮可点击。

代码依据：

- [Orgenda/DesignSystem/Layout/OrgendaEmptyState.swift:6](/Users/roifewu/.config/orgenda/Orgenda/DesignSystem/Layout/OrgendaEmptyState.swift:6) — 全实现仅为 ScrollView、frame、默认滚动锚点和回弹配置。
- [Orgenda/Features/Files/Document/DocumentOutline.swift:140](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Document/DocumentOutline.swift:140) — 原生 ContentUnavailableView 包含清除筛选操作，再应用该包装。
- [Orgenda/Features/Search/SearchView.swift:235](/Users/roifewu/.config/orgenda/Orgenda/Features/Search/SearchView.swift:235) — SearchEmptyState 的 VStack 也使用该扩展，证明其抽象不只服务 ContentUnavailableView。

API 依据：

- [Apple defaultScrollAnchor(_:for:)](https://developer.apple.com/documentation/swiftui/view/defaultscrollanchor(_:for:))：已读取官方 Markdown 文档；alignment 对应小于容器的内容对齐，API 自 iOS 18 可用。
- [Apple ScrollBounceBehavior.basedOnSize](https://developer.apple.com/documentation/swiftui/scrollbouncebehavior/basedonsize)：已读取官方 Markdown 文档；仅在内容超过滚动容器相应轴大小时回弹，自 iOS 16.4 可用。
- [iOS 27 SwiftUI SDK 声明](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：核对 ScrollAnchorRole/defaultScrollAnchor（15262–15285）、basedOnSize（15618–15633）及 ContentUnavailableView（22638 起）声明，最低 iOS 27 满足可用性。

专属分析 agent：`/root/audit_group_a/c029`。

<a id="c030"></a>

### C030 · OrgendaFlowLayout

**保留：无等价系统组件 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/DesignSystem/Layout/OrgendaFlowLayout.swift:3)　置信度：high

当前实现：基于 SwiftUI Layout 测量子视图并按可用宽度逐项换行；支持独立横纵间距，供标签、事项时间/来源和筛选状态 Toggle 使用。

系统候选：未找到可保持现有逐项自适应宽度换行并减少实现的直接系统替代。LazyVGrid(adaptive:)、Grid 或 HStack 会改变布局；UICollectionViewFlowLayout 需额外桥接及自尺寸单元格。

判断：当前需要按每个子视图测量宽度依次排布，超宽才换行，并以行内最大高度推进下一行。iOS 27 SDK 的 LazyVGrid 仍通过 GridItem 定义列，不能等价表达这些不等宽标签和控件；HStack 不换行，Grid 仍需自行分行。UIKit 流布局虽可实现类似效果，但会引入集合视图、托管与尺寸协调，不能降低此短小 Layout 的复杂度。

预期收益：保留现有 Layout 可集中维护三处共用的换行行为；没有已证实能减少维护成本的系统替换。

必须保留：保持子视图顺序及每项测量宽度，空间不足时整体换行；长标签和来源路径可在自身内部增高，按行最大高度避免重叠；横向与纵向间距可独立配置；未指定或非有限宽度按无限宽处理；有限负宽度归零；布局容纳原生 Toggle，保留选择绑定与可访问标识

验证要求：rg 在 OrgendaTests、OrgendaUITests 中未找到 OrgendaFlowLayout 或 OrgendaTagList 的直接布局测试。；OrgendaUITests/UIUXPolishUITests.swift:50 testOutlineEmptyFilterCanBeClearedInPlace 覆盖筛选状态选择与清除，未断言换行几何。；若以后改变布局，需验证窄屏、大字号、长中文/英文标签、长来源路径、不同高度控件及空内容的尺寸和可点击区域；本次仅静态审查，未运行。

代码依据：

- [Orgenda/DesignSystem/Layout/OrgendaFlowLayout.swift:21](/Users/roifewu/.config/orgenda/Orgenda/DesignSystem/Layout/OrgendaFlowLayout.swift:21) — 对宽度归一化，逐项测量并使用最大行高换行。
- [Orgenda/Components/Tags/OrgendaTagList.swift:8](/Users/roifewu/.config/orgenda/Orgenda/Components/Tags/OrgendaTagList.swift:8) — 标签通过 FlowLayout 换行；fixedSize 保留纵向可读性。
- [Orgenda/Components/OrgItemRow.swift:160](/Users/roifewu/.config/orgenda/Orgenda/Components/OrgItemRow.swift:160)；Orgenda/Features/Files/Document/DocumentOutline.swift:325 — 同一布局分别承载时间/来源元数据和多个原生状态 Toggle。

API 依据：

- [Apple SwiftUI Layout](https://developer.apple.com/documentation/swiftui/layout)：官方 Markdown 文档确认 Layout 是实现自定义几何布局的系统协议，要求 sizeThatFits 与 placeSubviews；本实现正使用此扩展点。
- [Apple SwiftUI LazyVGrid](https://developer.apple.com/documentation/swiftui/lazyvgrid)：官方 Markdown 文档确认按 GridItem 列配置将子视图放入网格单元；本机 iOS 27 SwiftUI 接口仍为 columns: [GridItem]，包含 adaptive 列尺寸。
- [iOS 27 UIKit UICollectionViewFlowLayout.h](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/UIKit.framework/Headers/UICollectionViewFlowLayout.h)：核对 minimumLineSpacing、minimumInteritemSpacing、itemSize 与 estimatedItemSize；自尺寸依赖单元格 preferredLayoutAttributesFittingAttributes，不能直接替代 SwiftUI 子视图容器。

专属分析 agent：`/root/audit_group_a/c030`。

<a id="c031"></a>

### C031 · AgendaCalendarView

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Agenda/AgendaCalendarView.swift:3)　置信度：high

当前实现：日历功能容器：组合 OrgendaCalendar、系统分页 TabView、分段 Picker、ScrollView/LazyVStack、sheet；维护选中日期与日程滚动双向同步、日记分页和捕获入口。

系统候选：无可直接替换整个容器的系统组件。UICalendarView 仅能候选替换内部日期选择区域；当前分页、滚动和弹窗已使用系统控件。

判断：主要自定义逻辑是业务状态协调：滚动选日不能触发反向跳转或打断减速，重复任务按日期隔离身份，切页保留日期并切换捕获入口。系统分页和可见性/滚动阶段 API 已在使用；UICalendarView 只提供日期选择与装饰，不能替代日程、日记及其联动。不存在已证实能实质减少此容器复杂度的等价替代。

预期收益：保留现有容器；把原生组合改成 UIKit 桥接无法消除业务同步逻辑，预计无明确复杂度收益。

必须保留：手势滚动时选择顶部日期且不回弹到当天标题，点选日期及返回今天时主动定位；396 天缓存窗口与越界重新定位、重复任务跨日期的视图身份边界；Agenda/Journal 页面身份、选中日期、按日期新建任务或日记；宽 iPad 双栏、窄窗口和辅助文字尺寸堆叠，以及布局变化后的日期重新定位；减少动态效果设置及仅活动页面驱动日期同步

验证要求：OrgendaUITests/MotionFlowUITests.swift:956 testCalendarTimelineScrollSelectsTopDay 覆盖顶部日期同步、同日滚动不回弹和返回今天；本审查未运行。；OrgendaUITests/DatePresentationUITests.swift:107 testCalendarJournalPagingKeepsDateAndCapturesOnSelectedDay 覆盖横向分页、固定日期栏及按所选日捕获；本审查未运行。；OrgendaUITests/IPadLayoutUITests.swift:191 testCalendarColumnsKeepSelectedDateAndJournalAcrossRotation；:338 testAccessibilityTextUsesStackedCalendarInWideWindow，覆盖旋转保留状态及辅助文字布局；本审查未运行。

代码依据：

- [Orgenda/Features/Agenda/AgendaCalendarView.swift:145](/Users/roifewu/.config/orgenda/Orgenda/Features/Agenda/AgendaCalendarView.swift:145) — 原生分页 TabView 同时承载日程和日记，并保持页面身份。
- [Orgenda/Features/Agenda/AgendaCalendarView.swift:184](/Users/roifewu/.config/orgenda/Orgenda/Features/Agenda/AgendaCalendarView.swift:184) — 原生惰性分节滚动及按日身份边界；可见性、滚动阶段和选择来源标记协调双向选日。
- [Orgenda/Features/Agenda/AgendaView.swift:202](/Users/roifewu/.config/orgenda/Orgenda/Features/Agenda/AgendaView.swift:202) — 日历视角的实际生产调用，注入任务操作、捕获和通用行视图。

API 依据：

- [iOS 27 SDK SwiftUI PageTabViewStyle、onScrollTargetVisibilityChange、onScrollPhaseChange](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：核实 page 分页样式和滚动可见性/阶段回调均为公开系统 API；后两者自 iOS 18 可用，目标 iOS 27 可直接使用，源码已采用。
- [iOS 27 SDK UICalendarView.h](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/UIKit.framework/Headers/UICalendarView.h)：公开契约包含 selectionBehavior、visibleDateComponents、日期装饰和可见日期回调；没有任务日程与日记分页及其同步业务接口。

专属分析 agent：`/root/audit_group_a/c031`。

<a id="c032"></a>

### C032 · AgendaCalendarTabletLayout

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Agenda/AgendaCalendarView.swift:295)　置信度：high

当前实现：以 ScrollView、AnyLayout、HStackLayout/VStackLayout 组合平板日历与详情；测量日历固有高度，保留拖柄空间，并为分页详情提供有限高度，支持短窗口整页滚动。

系统候选：保留现有系统布局组合。NavigationSplitView 的窄屏导航折叠与同时纵向展示两面板不同；ViewThatFits 只选择能容纳的候选视图，不能取代高度与滚动策略。

判断：这不是自制布局算法，而是系统布局的业务配置。AnyLayout 已实现横纵切换且保留子视图状态；外层滚动、拖柄余量和详情最小高度保证短窗口中日历与议程均可访问。NavigationSplitView 会在窄屏折叠为导航栈，ViewThatFits 不负责这些尺寸约束；替换仍需保留现有逻辑，没有实质简化。

预期收益：保留该封装集中管理平板尺寸策略；另换容器不会消除测量、有限高度或滚动协调，预计无实质复杂度收益。

必须保留：横纵布局切换时保持日历、Agenda/Journal 页面与选择状态；完整显示日历固有高度，拖柄触摸区域留出底部 14 点，堆叠面板间隔 16 点；短窗口可滚动整个布局；详情至少保有 240 点高度，分页 TabView 获得有限高度；列布局中日历宽度按窗口的 38% 计算并限制在 364–400 点；大辅助字号采用堆叠布局

验证要求：静态阅读，未运行构建或测试。OrgendaUITests/IPadLayoutUITests.swift:191 testCalendarColumnsKeepSelectedDateAndJournalAcrossRotation 覆盖旋转后的选中日期与 Journal 页面保持。；OrgendaUITests/IPadLayoutUITests.swift:338 testAccessibilityTextUsesStackedCalendarInWideWindow 覆盖大辅助字号堆叠及时间线可访问性。；OrgendaUITests/IPadLayoutUITests.swift:353 testCalendarViewportKeepsAllMonthRowsAndHandleVisible 覆盖 760×480 窗口完整月份及拖柄。；OrgendaUITests/IPadLayoutUITests.swift:390 testNarrowCalendarViewportShowsFullMonthAndScrollsToAgenda 覆盖 600×600 窗口滚动到议程且保留月份；若改容器，需实际重验这些交互。

代码依据：

- [Orgenda/Features/Agenda/AgendaCalendarView.swift:78](/Users/roifewu/.config/orgenda/Orgenda/Features/Agenda/AgendaCalendarView.swift:78) — 平板生产调用传入 calendarPanel 与 contentPanel；父视图依窗口宽度、最小密度及辅助字号决定横纵布局。
- [Orgenda/Features/Agenda/AgendaCalendarView.swift:306](/Users/roifewu/.config/orgenda/Orgenda/Features/Agenda/AgendaCalendarView.swift:306) — 已使用 AnyLayout 包装系统 HStackLayout/VStackLayout；通过实测 calendarHeight 计算详情有限高度并保留日历底部触摸空间。
- [OrgendaUITests/IPadLayoutUITests.swift:390](/Users/roifewu/.config/orgenda/OrgendaUITests/IPadLayoutUITests.swift:390) — 窄窗口测试要求日历保持 Month，并通过整页滚动露出议程，说明导航折叠不是等价行为。

API 依据：

- [Apple AnyLayout](https://developer.apple.com/documentation/swiftui/anylayout)：官方 Markdown 说明可动态更换布局容器类型而不销毁子视图状态，并给出 HStackLayout/VStackLayout 示例；与当前用法一致。
- [Apple NavigationSplitView](https://developer.apple.com/documentation/swiftui/navigationsplitview)：官方 Markdown 明确窄尺寸下列折叠为单个导航栈，与本组件窄屏仍纵向呈现两个面板不同。
- [Apple ViewThatFits](https://developer.apple.com/documentation/swiftui/viewthatfits)：官方 Markdown 说明按候选顺序选择理想尺寸能适应提议尺寸的第一个子视图，并非自动保留当前滚动与高度策略。
- [iOS 27 SDK SwiftUICore layout and geometry declarations](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUICore.framework/Modules/SwiftUICore.swiftmodule/arm64e-apple-ios.swiftinterface)：核对 VStackLayout:1379、HStackLayout:6850、onGeometryChange:7710、AnyLayout:10380 的系统声明；当前组件已使用这些原生能力。

专属分析 agent：`/root/audit_group_a/c032`。

<a id="c033"></a>

### C033 · AgendaDayContent

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Agenda/AgendaDayContent.swift:3)　置信度：high

当前实现：按全天事件与常规项目分组，组合原生 Button、ForEach、HStack、Text 与带预览的 contextMenu；显示今日逾期入口、事件完成与编辑动作，常规行由调用方注入。

系统候选：无实质替代；当前已使用 SwiftUI 原生按钮、布局与上下文菜单。

判断：该类型承载每日内容的业务组合，交互已由原生 Button 和 contextMenu 实现。完成一次重复事件是命令而非布尔开关，不能用 Toggle 等价替换。系统列表或空状态组件也不能消除全天事件分组、动作注入与 Org 工作流语义；父级另有按日布局边界保障重复事件身份，应保留现有组合。

预期收益：没有可证明的系统替换收益；保留组合可继续集中每日展示规则和动作配置。

必须保留：全天无时间事件与常规条目的分组和顺序；仅今日显示非零逾期入口；按 canComplete 提供完成本次事件动作，独立于打开编辑；44 点点击区域、辅助功能标签、值与定位源文件动作；上下文菜单预览以及父级每日布局边界

验证要求：OrgendaUITests/MotionFlowUITests.swift:68 testPlainBirthdayOffersInlineCompletionAndUndo 覆盖全天重复事件的内联完成、菜单完成及撤销；本次仅读取，未运行。；如调整布局，需验证大字体下全天标题换行、独立完成按钮命中与 VoiceOver 的 Show in File 动作。

代码依据：

- [Orgenda/Features/Agenda/AgendaDayContent.swift:15](/Users/roifewu/.config/orgenda/Orgenda/Features/Agenda/AgendaDayContent.swift:15) — 分组、今日逾期入口、原生按钮菜单及注入常规行均在此业务组合中实现。
- [Orgenda/Features/Agenda/AgendaCalendarView.swift:183](/Users/roifewu/.config/orgenda/Orgenda/Features/Agenda/AgendaCalendarView.swift:183) — 父级 Section 内以 VStack 隔离每日重复事件身份后调用 AgendaDayContent。
- [Orgenda/Domain/Org/OrgItem.swift:40](/Users/roifewu/.config/orgenda/Orgenda/Domain/Org/OrgItem.swift:40) — canComplete 包含带工作流状态项目或重复事件，并非单一布尔勾选状态。

API 依据：

- [iOS 27 SDK SwiftUI.Button](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对 29177 行起 Button(action:label:) 原生动作按钮，iOS 13 起可用。
- [iOS 27 SDK View.contextMenu(menuItems:preview:)](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对 12144 行起带预览的系统上下文菜单，iOS 16 起可用，组件已直接使用。

专属分析 agent：`/root/audit_group_a/c033`。

<a id="c034"></a>

### C034 · AgendaDayHeader

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Agenda/AgendaDayHeader.swift:3)　置信度：high

当前实现：以 Text、HStack 和 AnyLayout 组合相对日名、日期及非零事项计数；辅助字号改为纵向日期排版，周末着色，合并无障碍文本，并作为原生 Section 的固定表头复用到加载骨架。

系统候选：继续使用现有 Section(header:)、Text 与 AnyLayout；Section 的纯文字标题不能等价承载全部内容，无实质替代项。

判断：该类型没有自行实现控件或吸顶机制，吸顶已由调用方 LazyVStack 的 sectionHeaders 提供。纯文字 Section 标题无法同时保留双段日期、独立计数、周末样式及辅助字号换行；继续加入这些内容仍需同样的原生组合。保留小型封装也能让实际时间线与加载骨架共享版式。

预期收益：没有可证实的复杂度收益；展开封装会增加两个调用处的重复视图配置。

必须保留：昨天／今天／明天优先及跨年日期格式；辅助字号的日期纵排、计数不压缩及零计数隐藏；周末颜色、固定表头背景与合并无障碍朗读；orgenda.agenda.day.<日期键> 标识及骨架复用

验证要求：OrgendaUITests/MotionFlowUITests.swift:956 testCalendarTimelineScrollSelectsTopDay 依赖表头标识与位置，覆盖滚动后顶部日期选择；本次仅阅读，未运行。；OrgendaTests/DesignSystem/MotionPolicyTests.swift:24 testContextualDatePresentationOmitsOnlyTheReferenceYear 与 :66 testContextualDatePresentationUsesNearbyDayNames 覆盖日期规则；本次未运行。；若以后改变布局，需实机或原型核对最大辅助字号、长本地化日期、非零计数及 VoiceOver 合并顺序；静态分析不证明这些交互表现。

代码依据：

- [Orgenda/Features/Agenda/AgendaDayHeader.swift:8](/Users/roifewu/.config/orgenda/Orgenda/Features/Agenda/AgendaDayHeader.swift:8) — 现有布局、日期文本、条件计数和无障碍配置均由系统视图及修饰器组成。
- [Orgenda/Features/Agenda/AgendaCalendarView.swift:183](/Users/roifewu/.config/orgenda/Orgenda/Features/Agenda/AgendaCalendarView.swift:183) — LazyVStack(pinnedViews: [.sectionHeaders]) 与 Section header 承担固定表头，:200 调用该封装。
- [Orgenda/Features/Agenda/AgendaStartupSkeleton.swift:39](/Users/roifewu/.config/orgenda/Orgenda/Features/Agenda/AgendaStartupSkeleton.swift:39) — 加载骨架复用同一日期表头。

API 依据：

- [iOS 27 SDK — SwiftUI Section](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：14032–14139 核对 Section 自定义 header 初始化器及仅生成 Text 的标题初始化器；均可用于最低 iOS 27。
- [iOS 27 SDK — AnyLayout、DynamicTypeSize、PinnedScrollableViews](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUICore.framework/Modules/SwiftUICore.swiftmodule/arm64e-apple-ios.swiftinterface)：10380 核对 AnyLayout 接受任意 Layout；14746 有 isAccessibilitySize；21508 有原生 sectionHeaders 固定选项。

专属分析 agent：`/root/audit_group_a/c034`。

<a id="c035"></a>

### C035 · AgendaPerspectiveContent

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Agenda/AgendaPerspectiveContent.swift:3)　置信度：high

当前实现：以原生 List、Section、ForEach 呈现议程透视；Dashboard 组合逾期、未来七日、截止日期及工作流分组，用 LabeledContent 显示组名计数，以 ContentUnavailableView 显示整体空态。

系统候选：现有 List + Section + LabeledContent + ContentUnavailableView 已是对应系统组件，无实质替代项。

判断：组件没有自绘列表或自建空态控件。剩余代码表达 Dashboard 分组次序、期限配置、日期组为空与整体为空的不同提示，并注入带任务操作的行。组及行身份保持跨组重复任务的展示边界；改成另一原生容器仍需这些业务逻辑，不能消除该封装。

预期收益：保留现有薄业务封装；无需引入桥接或更换容器，暂无有意义的复杂度降低。

必须保留：逾期→未来七日→截止日期→工作流分组的次序，以及 deadlineWarningDays 配置；无近期日程但仍有任务时保留局部提示，仅所有输入为空才显示整体空态；组身份与组内任务组合身份，完成和撤销后其余组仍可访问；注入行保留编辑、完成、改期、拖动与活动透视滑动操作，以及无障碍标识

验证要求：OrgendaUITests/MotionFlowUITests.swift:329 testDashboardSectionsKeepOtherGroupsAfterCompletionAndUndo 覆盖局部空态、后续组可达和完成撤销后的分组保留；本次仅阅读，未运行。；OrgendaTests/Integration/EmacsProfileIntegrationTests.swift:71 testDashboardDateScopeDoesNotFilterTaskViews 验证七日范围不排除后续任务分组及完全空组输入；本次仅阅读，未运行。；如将来调整列表身份，需在 iOS 27 验证同一任务同时出现于日期、截止日期和状态组时，完成及撤销不会串用行状态。

代码依据：

- [Orgenda/Features/Agenda/AgendaPerspectiveContent.swift:16](/Users/roifewu/.config/orgenda/Orgenda/Features/Agenda/AgendaPerspectiveContent.swift:16) — 原生列表与分组，配置化期限标题和 ContentUnavailableView 空态；63 行给组与组内行设置身份。
- [Orgenda/Features/Agenda/AgendaView.swift:216](/Users/roifewu/.config/orgenda/Orgenda/Features/Agenda/AgendaView.swift:216) — 生产路径传入组、截止日期、逾期及 configuredItem；行使用规范任务对象并按透视活动状态控制滑动操作。
- [OrgendaUITests/MotionFlowUITests.swift:329](/Users/roifewu/.config/orgenda/OrgendaUITests/MotionFlowUITests.swift:329) — 专项测试要求完成和撤销之后其他 Dashboard 分组继续存在并可访问。

API 依据：

- [iOS 27 SDK SwiftUI List、Section、LabeledContent、ContentUnavailableView 声明](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对 List（8156）、Section 及 content/header 初始化器（14032 起）、LabeledContent 标题和值初始化器（5017 起）、ContentUnavailableView 标题/系统图标/说明初始化器（22638 起）；最低 iOS 27 均可直接使用，当前实现已使用这些系统 API。

专属分析 agent：`/root/audit_group_a/c035`。

<a id="c036"></a>

### C036 · AgendaRescheduleSheet

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Agenda/AgendaRescheduleSheet.swift:3)　置信度：high

当前实现：以 NavigationStack、Form、Section、图形 DatePicker 和系统工具栏按钮组成改期弹窗，提供今天、明天快捷选择与确认、取消；初始日期取任务计划日。

系统候选：无实质替换项；核心日期输入已是 SwiftUI DatePicker(.graphical)，弹窗已由系统 sheet 呈现。

判断：当前没有自绘日历或自定义弹窗容器，日期选择、表单和确认取消均使用系统组件。包装层只负责任务上下文、暂存日期和快捷提交；单独换成 DatePicker 无法省去这些业务配置。改期写入由 WorkspaceStore 处理并保留时间及 Org 规则，继续保留此轻量组合最合适。

预期收益：现有实现已将交互交给系统控件；改成 UIKit 桥接或内联到调用处没有明确复杂度收益。

必须保留：默认选中现有计划日，未计划时使用当前日期；日期选择暂存至确认；取消不提交，今天和明天立即提交并关闭；任务标题及工作流状态展示、改期语义说明和辅助功能标识；继续经 WorkspaceStore 改期，保留时间、截止日、重复与预警规则及撤销保护

验证要求：OrgendaUITests/MotionFlowUITests.swift:292 — testGestureTaskSwipesCompleteRescheduleAndUndo 覆盖打开改期、明天快捷选择和撤销（仅阅读，未运行）。；OrgendaTests/Services/Workspace/WorkspaceStoreTests.swift:54 — testGestureReschedulePreservesDeadlineTimeRepeaterAndWarningAndCanUndo 验证时间、截止日、重复规则、预警及撤销。；OrgendaTests/Services/Workspace/WorkspaceStoreTests.swift:87 — testGestureRescheduleRejectsStaleTaskAndPlainEvents 验证过期项目及普通事件保护。；若未来改变呈现方式，需运行时检查选择后取消不写入、确认仅提交一次及 VoiceOver 日期与工具栏导航；本次未构建或运行。

代码依据：

- [Orgenda/Features/Agenda/AgendaRescheduleSheet.swift:15](/Users/roifewu/.config/orgenda/Orgenda/Features/Agenda/AgendaRescheduleSheet.swift:15) — 原生导航、表单、图形日期选择器和带角色工具栏按钮；select 关闭后回调。
- [Orgenda/Features/Agenda/AgendaView.swift:102](/Users/roifewu/.config/orgenda/Orgenda/Features/Agenda/AgendaView.swift:102) — 生产调用通过 sheet(item:) 展示，并将日期传入 reschedule。
- [Orgenda/Services/Workspace/WorkspaceMoves.swift:28](/Users/roifewu/.config/orgenda/Orgenda/Services/Workspace/WorkspaceMoves.swift:28) — reschedule 保留原计划时间，经 save 写入并提供撤销信息与失效任务保护。

API 依据：

- [iOS 27 SDK SwiftUI.DatePicker、GraphicalDatePickerStyle 与 ButtonRole](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对 25348–25436 行 DatePicker 的 Date 绑定及 .date 组件，24191–24197 行 graphical 自 iOS 14 可用，11762–11770 行 confirm 自 iOS 26 可用；均满足最低 iOS 27。

专属分析 agent：`/root/audit_group_a/c036`。

<a id="c037"></a>

### C037 · AgendaStartupSkeleton

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Agenda/AgendaStartupSkeleton.swift:3)　置信度：high

当前实现：用 VStack、ScrollView 和系统 redacted(.placeholder) 复用真实日期标题及任务行，按当前视图显示日历；禁用交互并提供单一加载无障碍元素。

系统候选：现有 redacted(reason: .placeholder) 已采用系统占位能力；ProgressView 可显示等待状态，但不等价于保留内容排版的骨架屏。

判断：占位效果已经由 SwiftUI redacted 提供，自定义部分仅负责组织与正式页面一致的日期标题、任务行和日历。复用真实组件可同步字体与动态字号布局；改成 ProgressView 会丢失内容形状，也违反现有测试对非进度指示器的约束，因此没有实质系统替换收益。

预期收益：保留当前薄组合；已使用原生占位效果，无值得新增替代层的复杂度收益。

必须保留：占位数据仅在视图内创建，不进入工作区存储；保持日历密度、紧凑行距与正式内容相符；禁用滚动、点击和滑动操作；统一的 Loading workspace 标签、Calendar/Dashboard 值及 workspace.loading 标识

验证要求：OrgendaUITests/WorkspaceSyncUITests.swift:34 testStartupSkeletonKeepsFirstScreenChromeUntilIndexIsReady 验证加载元素、非进度指示器及加载前后工具栏位置；本次仅阅读未运行。；OrgendaUITests/WorkspaceSyncUITests.swift:38 testStartupSkeletonAtAccessibilitySize 复用相同断言覆盖深色及最大辅助字号；本次仅阅读未运行。

代码依据：

- [Orgenda/Features/Agenda/AgendaStartupSkeleton.swift:22](/Users/roifewu/.config/orgenda/Orgenda/Features/Agenda/AgendaStartupSkeleton.swift:22) — 复用正式组件并以 redacted 生成占位内容，集中禁用交互与设置无障碍语义。
- [Orgenda/Features/Agenda/AgendaView.swift:53](/Users/roifewu/.config/orgenda/Orgenda/Features/Agenda/AgendaView.swift:53) — 工作区启动期间实际使用此组件，并传入选中日期、日历显示状态与紧凑行配置。
- [OrgendaUITests/WorkspaceSyncUITests.swift:55](/Users/roifewu/.config/orgenda/OrgendaUITests/WorkspaceSyncUITests.swift:55) — 测试加载标签和值，并明确断言 workspace.loading 不是 progressIndicator。

API 依据：

- [iOS 27 SDK — RedactionReasons.placeholder 与 View.redacted(reason:)](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUICore.framework/Modules/SwiftUICore.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对 7729–7750 行的原生占位原因与 redacted 声明，iOS 14 起可用。
- [iOS 27 SDK — ProgressView](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对 4963 起的 ProgressView 及无进度值初始化声明；它提供等待指示，不能自动复现现有内容骨架结构。

专属分析 agent：`/root/audit_group_a/c037`。

<a id="c038"></a>

### C038 · AgendaTodoList

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Agenda/AgendaTaskLists.swift:3)　置信度：high

当前实现：用原生 List、Section、ForEach 展示未排期任务，按源文件分组并显示总数；空列表使用 ContentUnavailableView。行由调用方注入。

系统候选：现有 SwiftUI List + Section + ContentUnavailableView 已是对应系统方案，无实质替代项。

判断：实现没有自绘列表或自制空态，系统列表负责布局与滚动，业务代码只承担文件分组、排序、计数及注入任务行。直接换成 List 仍须保留这些逻辑；源数据的未排期筛选由 WorkspaceStore 提供，行操作由 AgendaView 配置，保留此薄封装能维持职责边界。

预期收益：没有可见复杂度收益；当前已直接使用系统控件，删除封装只会把分组与空态配置移入调用方。

必须保留：源文件分组、文件名排序与每组原有任务顺序；未排期任务计数及空态文案；注入行的打开、完成、改期、定位源文件及拖拽行为；agenda.view.todos 标识、统一列表表面和可滚动空态

验证要求：OrgendaUITests/MotionFlowUITests.swift:314 testNativeTaskSwipeClosesAcrossPerspectiveChanges 覆盖未排期视图返回后的滑动操作状态。；OrgendaUITests/MotionFlowUITests.swift:866 testCaptureKeepsUnsavedDraftAndSavesSearchableTask 校验新增任务及 Unscheduled · 2 open 计数。；本次仅静态审查，未运行测试；若调整分组需补充多文件排序与空列表可访问性验证。

代码依据：

- [Orgenda/Features/Agenda/AgendaTaskLists.swift:3](/Users/roifewu/.config/orgenda/Orgenda/Features/Agenda/AgendaTaskLists.swift:3) — List/Section/ForEach、ContentUnavailableView 和 groupedTodos 的完整薄封装。
- [Orgenda/Features/Agenda/AgendaView.swift:214](/Users/roifewu/.config/orgenda/Orgenda/Features/Agenda/AgendaView.swift:214) — 生产调用传入 store.openTodos 与 configuredItem；后者配置原始任务身份和交互。
- [Orgenda/Services/Workspace/WorkspaceStore.swift:122](/Users/roifewu/.config/orgenda/Orgenda/Services/Workspace/WorkspaceStore.swift:122) — openTodos 筛选未排期开放工作流任务并按优先级、标题排序。

API 依据：

- [iOS 27 SDK SwiftUI List、Section、ContentUnavailableView 声明](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对 List（8156）、Section 内容与标题构造器（14079）及 ContentUnavailableView（22638，含 systemImage/description 初始化）；这些 API 在 iOS 27 均可用且当前组件已经采用。

专属分析 agent：`/root/audit_group_a/c038`。

<a id="c039"></a>

### C039 · AgendaOverdueList

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Agenda/AgendaTaskLists.swift:37)　置信度：high

当前实现：以原生 List、Section、ForEach、Label 呈现逾期任务，按 agendaDate 的自然日升序分组；空列表使用 ContentUnavailableView，并注入调用方的任务行。

系统候选：继续使用现有 SwiftUI List + Section + ContentUnavailableView；未发现能进一步消除业务组合的等价系统控件。

判断：主体已完全由系统列表、分节和空状态构成，自定义部分仅负责逾期计数、Org 主日期分组、日期标题及任务行注入。调用方传入经工作流过滤的数据和含编辑、完成、改期等行为的行。直接摊平为 List 会把这些业务配置搬回调用方，不能减少实质复杂度；引入 UIKit 列表反而增加桥接。

预期收益：保留短小业务封装；没有实质系统替换收益，避免将分组和空状态配置扩散到调用方。

必须保留：按 agendaDate 的自然日分节并按日期升序展示，保留调用方的项目顺序与稳定标识；逾期计数、相对日期标题、逾期色和本地化空状态文案；调用方注入的任务操作、拖拽身份和仅活动视角启用滑动操作；agenda.view.overdue 无障碍标识、统一列表宽度与短窗口可滚动空状态

验证要求：OrgendaTests/Integration/EmacsProfileIntegrationTests.swift:6 — testOverdueRequiresAnExplicitOpenWorkflowState 验证显式未完成工作流筛选；本次仅阅读，未运行。；OrgendaTests/Integration/EmacsProfileIntegrationTests.swift:17 — testOverduePerspectiveListsOpenDatedItemsOldestFirst 验证逾期数据从旧到新；本次仅阅读，未运行。；OrgendaUITests/IPadLayoutUITests.swift:15 — testSidebarGroupsDashboardViewsAndPreservesSelection 检查切换至逾期后的滚动容器标识和任务可见性；本次仅阅读，未运行。；若未来调整组合，需运行时补查同日多项分组、跨年标题和大字号空状态；现有源码检查不能替代交互验证。

代码依据：

- [Orgenda/Features/Agenda/AgendaTaskLists.swift:37](/Users/roifewu/.config/orgenda/Orgenda/Features/Agenda/AgendaTaskLists.swift:37) — List/Section/ContentUnavailableView 原生组合；groupedOverdue 按自然日分组并升序排序。
- [Orgenda/Features/Agenda/AgendaView.swift:212](/Users/roifewu/.config/orgenda/Orgenda/Features/Agenda/AgendaView.swift:212) — 生产调用传入 store.overdueItems；configuredItem 提供编辑、完成、改期、文件跳转和规范拖拽对象。
- [OrgendaTests/Integration/EmacsProfileIntegrationTests.swift:17](/Users/roifewu/.config/orgenda/OrgendaTests/Integration/EmacsProfileIntegrationTests.swift:17) — 明确验证逾期视角只含未完成有日期任务并从旧到新排序。

API 依据：

- [iOS 27 SDK SwiftUI.List、Section 与 ContentUnavailableView 声明](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：核对 List（8156 行）与 Section（14032 行）自 iOS 13 可用，ContentUnavailableView（22638 行）自 iOS 17 可用，22669 行提供 title/systemImage/description 初始化器；均满足最低 iOS 27。

专属分析 agent：`/root/audit_group_a/c039`。

<a id="c040"></a>

### C040 · View.agendaListSurface

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Agenda/AgendaTaskLists.swift:73)　置信度：high

当前实现：为三个原生 List 调用方统一应用 plain 样式、保留标题大小写、隐藏滚动背景、上下 soft 滚动边缘效果，并将列表限制在居中的 760 点宽度内。

系统候选：已直接使用 SwiftUI 的 listStyle、textCase、scrollContentBackground、scrollEdgeEffectStyle 与 frame；无有实质收益的进一步系统替代。

判断：此扩展没有自绘、桥接或自定义交互，仅集中复用系统修饰符。三个生产调用方共享相同列表外观与宽度约束；内联这些修饰符只会增加重复。iOS 27 SDK 已包含全部现用 API，保留短包装即可继续使用原生 List 的滚动和行交互。

预期收益：保留共享配置，避免三个调用方重复维护同一组原生修饰符；无可消除的自定义控件复杂度。

必须保留：三个列表调用方一致的 plain 样式与标题大小写；隐藏列表背景及上下 soft 滚动边缘效果；居中且最大 760 点的列表宽度

验证要求：OrgendaUITests/MotionFlowUITests.swift:314 testNativeTaskSwipeClosesAcrossPerspectiveChanges 覆盖 Unscheduled/Overdue 切换后的原生滑动操作状态。；OrgendaUITests/MotionFlowUITests.swift:329 testDashboardSectionsKeepOtherGroupsAfterCompletionAndUndo 覆盖 Dashboard 列表滚动可达性与分组保留。；以上仅阅读现有测试，未执行；当前未见直接断言 760 点宽度或 soft 边缘样式的测试，若改布局应在宽屏和窄屏分别验证。

代码依据：

- [Orgenda/Features/Agenda/AgendaTaskLists.swift:73](/Users/roifewu/.config/orgenda/Orgenda/Features/Agenda/AgendaTaskLists.swift:73) — 实现仅由六次系统修饰符调用组成。
- [Orgenda/Features/Agenda/AgendaTaskLists.swift:21](/Users/roifewu/.config/orgenda/Orgenda/Features/Agenda/AgendaTaskLists.swift:21) — AgendaTodoList 使用此扩展；同文件第 56 行 AgendaOverdueList 也使用。
- [Orgenda/Features/Agenda/AgendaPerspectiveContent.swift:47](/Users/roifewu/.config/orgenda/Orgenda/Features/Agenda/AgendaPerspectiveContent.swift:47) — 配置式 Dashboard/其他透视列表为第三个生产调用方。

API 依据：

- [iOS 27 SDK SwiftUI public interface](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对 listStyle:686、PlainListStyle:14607、scrollContentBackground:13730（iOS 16+）、ScrollEdgeEffectStyle.soft:15485 和 scrollEdgeEffectStyle:15497（iOS 26+），最低 iOS 27 均可用。
- [iOS 27 SDK SwiftUICore public interface](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUICore.framework/Modules/SwiftUICore.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对 textCase:10921 接受可选参数；frame:15713 提供 maxWidth，默认 alignment 为 center，足以表达现有配置。

专属分析 agent：`/root/audit_group_a/c040`。

<a id="c041"></a>

### C041 · AgendaView

**需原型或产品取舍 · P2**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Agenda/AgendaView.swift:3)　置信度：high

当前实现：日程与看板页面编排，使用 NavigationStack、Menu 内嵌 Picker、系统 sheet/alert、safeAreaInset 和 glassEffect 撤销条；缓存已访问视图，关联 Org 工作流、编辑及改期。菜单标题的 Text 与 chevron 为手工组合。

系统候选：仅 perspectiveMenu 的标题入口可考虑 navigationTitle(displayedPerspective.title) + toolbarTitleMenu { 原有 Picker }，系统接管标题菜单指示器；其余页面仍保留原生组合与业务编排。

判断：Apple 标题菜单能容纳现有 Picker，但当前看板导航标题为空，入口固定在 topBarLeading；替换会把入口交给系统导航标题布局，不能静态保证同位置与无障碍节点。iPad 侧栏出现时必须移除选择入口并显示当前视图标题，Calendar 模式还独立控制标题和导航栏可见性。需原型验证这些分支及测试定位，才可采纳局部替换。视图保活、工作流备注跳转、源文档校验撤销仍是必要业务，不能由标题菜单或通用容器替代。

预期收益：若原型通过，可去掉手拼标题与箭头，并将标题菜单的呈现交给系统；只减少少量外观组合，不能消除页面状态和业务回调。当前没有可直接替换整个 AgendaView 的系统控件。

必须保留：已访问视图的滚动状态与身份；隐藏视图不可交互、不可被辅助功能访问，返回时关闭行侧滑；侧栏显示时不重复提供视图选择菜单；当前标题、Calendar 标题和导航栏显隐逻辑；启动骨架阶段标题可见、操作禁用，加载完成不改变顶部控件位置；视图菜单的选择状态、Switch view 标签与提示，以及可定位的无障碍入口；需要备注的工作流转入编辑器，改期及完成的单步撤销拒绝覆盖后续编辑；动态字体撤销条布局、减少动态效果和错误反馈

验证要求：待原型：iOS 27 上验证导航标题菜单在 iPhone、iPad 顶部标签与侧栏之间的位置、可见性、长标题和大字体；验证条件移除 toolbarTitleMenu 后不留下菜单指示器；待原型：验证系统标题入口的 VoiceOver 标签、值、提示与稳定定位；现有 agenda.viewMenu/agenda.currentPerspective 不能假定自动迁移；现有 OrgendaUITests/IPadLayoutUITests.swift:15 testSidebarGroupsDashboardViewsAndPreservesSelection 覆盖侧栏菜单隐藏、Waiting 标题及隐藏侧栏后的选择恢复；本次未运行；现有 OrgendaUITests/WorkspaceSyncUITests.swift:34、38 两个启动骨架测试检查菜单禁用状态和加载前后位置；本次未运行；现有 OrgendaUITests/MotionFlowUITests.swift:1396 chooseAgendaView 依赖 agenda.viewMenu，且已记录系统菜单 Picker 条目不总保留 tag 标识；替换应更新并验证定位策略；现有 OrgendaUITests/MotionFlowUITests.swift:292、314、329 覆盖手势撤销、切换视图关闭侧滑及组保留；OrgendaTests/Services/Workspace/WorkspaceStoreTests.swift:69 testGestureUndoRestoresRepeatedCompletionAndRejectsNewerEdits 覆盖撤销保护；本次未运行

代码依据：

- [Orgenda/Features/Agenda/AgendaView.swift:48](/Users/roifewu/.config/orgenda/Orgenda/Features/Agenda/AgendaView.swift:48) — tabBarPlacement 控制菜单；第 73 行标题通常为空、第 82 行使用 topBarLeading、第 86 行侧栏改为 principal 标题；第 171 行 Menu/Picker 和第 185 行手拼标题箭头
- [Orgenda/Features/Agenda/AgendaView.swift:61](/Users/roifewu/.config/orgenda/Orgenda/Features/Agenda/AgendaView.swift:61) — 保留访问过的视图并控制交互及辅助功能；第 108 行原生安全区撤销条、第 226 行 canonical item 与侧滑控制、第 239 行工作流备注和撤销编排
- [Orgenda/Features/Root/OrgendaRootView.swift:158](/Users/roifewu/.config/orgenda/Orgenda/Features/Root/OrgendaRootView.swift:158) — 原生 TabView/TabSection 承载看板侧栏；第 192 行以固定 agenda 绑定创建 Calendar，第 227 行创建可切换看板 AgendaView

API 依据：

- [Apple SwiftUI toolbarTitleMenu(content:)](https://developer.apple.com/documentation/swiftui/view/toolbartitlemenu(content:))：官方说明可提供自定义菜单内容，iOS/iPadOS 通过点击导航标题呈现；没有承诺复用应用自定义入口的布局或无障碍标识。
- [iOS 27 SDK SwiftUI declarations](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对 Menu（8745）、Picker（18128）、NavigationStack（19183）及 toolbarTitleMenu（24902）；标题菜单自 iOS 16 可用，iOS 27 无可用性障碍，content 接收 View。
- [iOS 27 SDK SwiftUICore safeAreaInset and glassEffect](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUICore.framework/Modules/SwiftUICore.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对 safeAreaInset（24302）和 glassEffect（3064）为系统 API，现有撤销条容器与材质已经采用原生能力。

专属分析 agent：`/root/audit_group_a/c041`。

<a id="c042"></a>

### C042 · DocumentSaveFailureFeedback

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Document/DocumentEditingControls.swift:4)　置信度：high

当前实现：监听当前文件保存状态，首次出现及状态变化为失败时显示 SwiftUI alert；三个系统 Button 提供重试、工作区设置和继续编辑，使用 sheet 打开设置。

系统候选：保留现有 SwiftUI alert 与 sheet；iOS 27 的 alert(error:actions:message:) 可绑定 Error，但不构成有实质收益的整体替代。

判断：该组件没有自行绘制弹窗或模拟系统交互，仅把按文件失败状态与原生提示连接起来。新的错误绑定 alert 仍需将 failed(String) 转为错误模型，并保留触发、重试和设置导航逻辑；不能自动识别已本地保存的同步冲突。继续编辑只关闭提示而不清除保存错误，当前小型封装有明确业务价值，无实质替代收益。

预期收益：保留可集中维护失败反馈；改用另一 alert 重载最多调整状态表达，无法消除业务逻辑或显著降低复杂度。

必须保留：只在该路径的 failed 状态提示，初次进入失败文件也提示；重试调用 synchronizeFiles，沿用持久化、同步和草稿保护逻辑；继续编辑仅关闭提示，不丢弃草稿或清除业务错误；工作区入口打开 initialDestination 为 workspace 的设置页

验证要求：OrgendaTests/Services/Workspace/WorkspaceConnectionTests.swift:385 testDocumentStatusSeparatesDurableSaveFromSyncConflictAndRetry 覆盖按文件状态、冲突保留草稿和重试恢复；不覆盖 failed 提示界面。；未发现该修饰器或其标题的专门 UI 测试；如调整状态绑定，需验证首次失败、关闭后继续编辑、重试再次失败，以及 alert 关闭后设置 sheet 正常呈现。此次未运行测试。

代码依据：

- [Orgenda/Features/Files/Document/DocumentEditingControls.swift:4](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Document/DocumentEditingControls.swift:4) — 原生 onChange、alert、Button 与 sheet 的业务组合，保留两项展示状态。
- [Orgenda/Features/Files/Document/OrgDocumentView.swift:60](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Document/OrgDocumentView.swift:60) — 编辑与预览容器共同挂载该修饰器，存在生产调用。
- [Orgenda/Services/Workspace/WorkspaceStore+Queries.swift:87](/Users/roifewu/.config/orgenda/Orgenda/Services/Workspace/WorkspaceStore+Queries.swift:87) — saveStatus 按路径区分 failed、saving、conflict、pendingSync 等状态，不能把所有同步问题视为保存失败。

API 依据：

- [iOS 27 SDK SwiftUI.View.alert 声明](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：13345 行声明现用标题、isPresented、actions、message 重载（iOS 15+）；13479–13482 行声明 anyAppleOS 27 的 Error 可选绑定重载，仍需调用方提供错误与动作。
- [iOS 27 SDK SwiftUI.View.sheet 声明](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：9145 行声明 sheet(isPresented:onDismiss:content:)，iOS 13+ 可用；当前设置展示已经是系统呈现接口。

专属分析 agent：`/root/audit_group_a/c042`。

<a id="c043"></a>

### C043 · OrgInsertDateSheet

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Document/DocumentEditingControls.swift:26)　置信度：high

当前实现：以 NavigationStack、Form 和 graphical DatePicker 呈现仅日期选择；原生工具栏按钮取消或确认，确认后交由编辑会话插入 Org 时间戳。

系统候选：现用 DatePicker(.graphical)、NavigationStack、Button 和 dismiss 已是系统方案；无可消除业务封装的等价单一系统组件。

判断：日期网格、表单、导航和确认取消按钮均由 SwiftUI 提供，没有自绘日历。此视图仅隔离临时日期选择与确认提交；会话负责原选区、Org 格式及编辑事务，宿主负责关闭后恢复焦点。改用紧凑 DatePicker 或 UIKit 桥接不能消除这些职责，也没有实质简化收益。

预期收益：保留短小原生组合即可；未发现值得替换的自定义控件实现，增加 UIKit 桥接反而增加维护成本。

必须保留：选择只修改临时日期，取消不插入；确认仅提交一次；插入不含时间的 Org 时间戳，并使用弹出前保存的文本选区及编辑事务；关闭弹层后在编辑模式恢复编辑器焦点；保留插入按钮的辅助功能标识与原生确认、取消语义

验证要求：OrgendaUITests/MotionFlowUITests.swift:740 testOrgKeyboardCommandsAndCaretSurvivePreview 已覆盖打开日期弹层、确认并检查 Org 日期格式；本次仅静态阅读，未运行。；如未来改变呈现方式，需验证取消不修改文本、改变日期后插入到保存选区、撤销以及关闭后键盘焦点恢复。

代码依据：

- [Orgenda/Features/Files/Document/DocumentEditingControls.swift:26](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Document/DocumentEditingControls.swift:26) — 全部 UI 为原生组合，date 暂存于 State，确认调用会话后 dismiss。
- [Orgenda/Components/Editor/OrgEditorSession.swift:124](/Users/roifewu/.config/orgenda/Orgenda/Components/Editor/OrgEditorSession.swift:124) — presentDate 保存选区并结束输入；insertDate 使用 Org 格式及 performEdit 提交。
- [Orgenda/Features/Files/Document/OrgDocumentView.swift:128](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Document/OrgDocumentView.swift:128) — 生产调用通过 large sheet 呈现，onDismiss 恢复编辑器焦点。

API 依据：

- [iOS 27 SDK — DatePicker、GraphicalDatePickerStyle、ButtonRole](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对 25374–25383 的 Date 绑定与 displayedComponents 初始化、24301 的原生 graphical 样式（iOS 14 起）及 11768 的 confirm 角色（iOS 26 起），均满足最低 iOS 27。

专属分析 agent：`/root/audit_group_a/c043`。

<a id="c044"></a>

### C044 · DocumentOutlineSheet

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Document/DocumentOutline.swift:117)　置信度：high

当前实现：以 NavigationStack、ContentUnavailableView、系统 sheet/toolbar/alert 和 ScrollView/LazyVStack 承载大纲；子分支已用 DisclosureGroup。管理筛选、展开身份延续、子树拖动及跳转编辑器/预览。

系统候选：现有系统组合继续使用；OutlineGroup 或 List(children:) 可表达普通树，但不能直接替代当前受控展开与 Org 子树移动协调。没有可直接删除此业务容器的系统组件。

判断：主要实现是业务状态协调，展示和弹层已采用系统组件。SDK 的 OutlineGroup/List(children:) 不提供此处所需的展开 ID 集合绑定；现有 DisclosureGroup 已提供受控展开。普通 onMove 只回传索引位置，也不表达嵌套落点、隐藏子树和源码快照校验。替换容器仍须保留这些逻辑，未发现实质简化。

预期收益：保留现状没有新增桥接成本；换成普通树控件仅能缩短少量布局，不能移除业务协调，且可能损失展开连续性。

必须保留：筛选保留命中项祖先路径，清除筛选后恢复原树；解析及移动后重映射展开 ID，并展开移动目标祖先；拖动移动完整源码子树，包含筛选隐藏的后代，保留撤销及预览同步；拒绝过期源码快照；移动解析完成前禁止用旧字节位置跳转；编辑模式关闭大纲后定位光标，预览模式按标题身份导航；辅助功能字号对应 sheet 高度、减少动态效果与原生错误提示

验证要求：OrgendaTests/Features/Files/DocumentOutlineFilterTests.swift:55 — testAncestorsOfMatchesAreRetainedWithFilteredChildren（已读，未运行）；OrgendaTests/Domain/Org/OrgHeadingMoveTests.swift:239 — testHeadingContinuityPreservesSelectionsAcrossOutlineReparenting；:255 — testFilteredOutlineMoveIncludesHiddenChildrenAndRebuildsTree（已读，未运行）；OrgendaUITests/MotionFlowUITests.swift:528 — testOutlineDragNestsMovesOutAndUpdatesPreviewSourceAndUndo；:584 — testFilteredOutlineDragMovesHiddenContentAndPreviewNavigationStillWorks（已读，未运行）；若探索 List 容器原型，须实机验证嵌套/跨父拖放、受控展开及 sheet 内滚动；静态源码无法证明交互等价。

代码依据：

- [Orgenda/Features/Files/Document/DocumentOutline.swift:136](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Document/DocumentOutline.swift:136) — 系统导航、空状态、sheet、toolbar 与 alert；:188 解析变化时重映射展开身份。
- [Orgenda/Features/Files/Document/DocumentOutline.swift:233](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Document/DocumentOutline.swift:233) — 拖动检查源码字节一致性；:249 子树移动与目标展开；:267 移动期间保护导航位置。
- [Orgenda/Features/Files/Document/OrgDocumentView.swift:134](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Document/OrgDocumentView.swift:134) — 真实 sheet 调用，关闭后将字节位置交给编辑器；:206 根据编辑/预览模式导航。

API 依据：

- [iOS 27 SDK — OutlineGroup、List(children:) 与 DisclosureGroup](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对 4151–4198 的 OutlineGroup 初始化器及 8331–8342 的树形 List 初始化器：children 与行构造器，没有展开集合绑定；18043–18044 的 DisclosureGroup 支持 isExpanded: Binding<Bool>。均适用于最低 iOS 27。
- [iOS 27 SDK — DynamicViewContent.onMove(perform:)](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对 13692：回调签名为 (IndexSet, Int) -> Void，不提供目标标题及 before/after/child 的业务移动语义。

专属分析 agent：`/root/audit_group_a/c044`。

<a id="c045"></a>

### C045 · DocumentOutlineFilterSheet

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Document/DocumentOutline.swift:316)　置信度：high

当前实现：以 NavigationStack、Form、Section、按钮式 Toggle 和 compact DatePicker 组成大纲筛选表单；绑定文档工作流状态集合、Scheduled/Deadline 四个可选边界，并提供重置和关闭。

系统候选：继续使用现有 Form、Toggle(.button)、DatePicker；未发现可整件替代的系统筛选面板。MultiDatePicker 不等价于可分别留空的日期上下界。

判断：面板已使用系统表单和输入控件，自定义部分负责文档工作流多选、可选日期与筛选模型绑定。iOS 27 SDK 的 DatePicker 接受非可选 Date，MultiDatePicker 接受日期集合，均不能消除四个独立边界的启停语义。状态换行布局属于共享依赖；改单列开关会改变呈现，不能算等价替换。

预期收益：维持现有短业务封装即可；替换系统控件名称或增加 UIKit 桥接没有实质复杂度收益。

必须保留：从当前文档环境获取自定义工作流状态，支持多选并集及空集合代表全部；Scheduled 和 Deadline 各有独立、可为空的 From/To；启用空边界默认当天，关闭恢复 nil；筛选绑定即时生效、重置全部条件、关闭不撤销，并保留无障碍标识；状态标签图标、颜色及随可用宽度换行；大字号下由调用方提供大尺寸 sheet

验证要求：已静态阅读 OrgendaTests/Features/Files/DocumentOutlineFilterTests.swift：testScheduledRangeMatchesOnlyDatedHeadingsInsideRange、testDeadlineUpperBoundSelectsDueItems、testCombinedCriteriaAndResetRestoreAllRows；未运行测试。；已静态阅读 OrgendaUITests/MotionFlowUITests.swift:399 的 testOutlineFilterNarrowsHeadingsByStateAndRestores，覆盖多状态并集、取消单项、清除恢复；未运行测试。；如未来调整日期行，应补充界面验证四个边界分别启停、单边范围及 Reset 后日期行隐藏；现有日期过滤单测不能证明交互表现。

代码依据：

- [Orgenda/Features/Files/Document/DocumentOutline.swift:175](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Document/DocumentOutline.swift:175) — 调用方传入实时筛选 Binding、文档工作流环境，并按无障碍字号选择 sheet 高度。
- [Orgenda/Features/Files/Document/DocumentOutline.swift:321](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Document/DocumentOutline.swift:321) — 原生 NavigationStack/Form 内使用 Toggle(.button)，集合 Binding 支持多选；工具栏负责 reset 与 dismiss。
- [Orgenda/Features/Files/Document/DocumentOutline.swift:375](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Document/DocumentOutline.swift:375) — 原生 Toggle 映射 Date? 的有无；DatePicker 仅在边界启用时显示，关闭写回 nil。

API 依据：

- [iOS 27 SwiftUI SDK：ButtonToggleStyle](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对 1249–1278 行：ToggleStyle.button 和 ButtonToggleStyle 为 iOS 15 起可用的系统按钮式开关。
- [iOS 27 SwiftUI SDK：DatePicker 与 MultiDatePicker selection](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对 25372–25426 行 DatePicker 的 selection 为 Binding<Date>，17359–17364 行 MultiDatePicker 的 selection 为 Binding<Set<DateComponents>>，不能直接承接四个可空范围边界。

专属分析 agent：`/root/audit_group_a/c045`。

<a id="c046"></a>

### C046 · DocumentOutlineBranch

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Document/DocumentOutline.swift:397)　置信度：high

当前实现：递归组合原生 DisclosureGroup、Button、ForEach，提供标题跳转、受控展开、筛选时展开路径、标题拖放与落点反馈。

系统候选：现有 DisclosureGroup 已承担原生折叠；OutlineGroup 可自动递归，但未提供逐节点外部展开集合绑定，不能等价替换本组件。

判断：组件已使用系统折叠控件。iOS 27 SDK 的 OutlineGroup 初始化器只有树数据、children 和内容闭包，无逐节点展开绑定；直接替换会丢失解析后展开 ID 重映射及移动后展开目标路径。祖先 ID、筛选展开和三种落点反馈仍需业务层实现，因此没有可实质删减且行为等价的系统替代。

预期收益：保留原生组合封装；改为 OutlineGroup 仍需另建展开控制和拖放上下文，未识别出净复杂度收益。

必须保留：展开状态按标题 ID 维护，并随解析结果与标题移动重映射；筛选时显示全部保留路径，标题跳转与折叠操作独立；祖先身份用于禁止拖入自身子树，保留 before、child、after 落点及反馈；44 点标题操作区、标题层级与编辑/预览跳转无障碍提示、减少动态效果

验证要求：OrgendaUITests/MotionFlowUITests.swift:1321 testDocumentOutlineIsReadOnlyCollapsibleAndNavigatesToHeading：覆盖独立折叠、预览跳转与编辑定位。；OrgendaUITests/MotionFlowUITests.swift:528 testOutlineDragNestsMovesOutAndUpdatesPreviewSourceAndUndo；:584 testFilteredOutlineDragMovesHiddenContentAndPreviewNavigationStillWorks：覆盖嵌套、移出、隐藏子树与撤销。；OrgendaTests/Domain/Org/OrgHeadingMoveTests.swift:239 testHeadingContinuityPreservesSelectionsAcrossOutlineReparenting：覆盖 ID 连续性。；本次仅静态核对，未运行测试；若未来尝试 OutlineGroup，需原型验证外部展开恢复、筛选切换及标题按钮与展开区域的命中行为。

代码依据：

- [Orgenda/Features/Files/Document/DocumentOutline.swift:397](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Document/DocumentOutline.swift:397) — 原生 DisclosureGroup 与标题 Button 递归组合，筛选路径、祖先 ID、落点叠层和外部展开 Binding 均在本组件处理。
- [Orgenda/Features/Files/Document/DocumentOutline.swift:184](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Document/DocumentOutline.swift:184) — 宿主在解析更新时重映射 expandedHeadingIDs；:217 为生产调用，:259 在 child 移动后展开目标。
- [Orgenda/Components/Gestures/OrgHeadingDrag.swift:33](/Users/roifewu/.config/orgenda/Orgenda/Components/Gestures/OrgHeadingDrag.swift:33) — 通过 parentHeadingIDs 禁止拖入自身子树，DocumentOutlineBranch 递归累积并传递此上下文。

API 依据：

- [iOS 27 SwiftUI SDK：DisclosureGroup.init(isExpanded:content:label:)](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对 18041–18043 行，支持 Binding<Bool> 的原生 DisclosureGroup 可直接承接每个节点的受控展开。
- [iOS 27 SwiftUI SDK：OutlineGroup 初始化器](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对 4163–4201 行：普通及数据 Binding 初始化器均接收可选 children key path 与内容闭包，未提供逐节点外部展开状态参数。

专属分析 agent：`/root/audit_group_a/c046`。

<a id="c047"></a>

### C047 · OrgDocumentView

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Document/OrgDocumentView.swift:3)　置信度：high

当前实现：文档页面用 ZStack 常驻预览与编辑器，以系统分段／菜单 Picker、ViewThatFits、ToolbarItem、Button 和 sheet 组织交互；负责编辑会话、索引刷新、搜索与大纲定位、保存失败提示和返回导航。

系统候选：保留现有系统 Picker、ViewThatFits、toolbar 与 sheet 组合。DocumentGroup 是文档 Scene，不能直接替代此工作区内的文档页面；没有可实质删去协调逻辑的等价系统控件。

判断：主要代码是应用状态协调，控件本身已原生化。双视图常驻配合 OrgEditorSession 保留编辑选择、撤销及预览滚动位置；搜索与定位还依赖索引和 UTF-8 源位置。DocumentGroup 仍须提供内容视图且改变文档生命周期，不能代办这些语义。改成条件切换或 TabView 没有已证实的复杂度收益，反而需重新验证编辑连续性。

预期收益：不建议替换：现有抽象集中必要的文档生命周期与导航协调；更换系统容器不会移除这些逻辑。

必须保留：编辑／预览切换保留原 UITextView、撤销历史、插入点、键盘恢复与预览滚动位置；失焦及切换前结束输入组合，更新文档并刷新索引；保留外部修订与保存失败反馈；搜索首次进入编辑时选择匹配；大纲与外部导航按当前索引对应源字节定位；窄宽度与辅助功能字号使用菜单；非活动视图禁止命中并隐藏辅助功能元素；推入页面保留系统返回及边缘返回；宽屏详情列支持清除选择的返回动作

验证要求：OrgendaUITests/MotionFlowUITests.swift:740 testOrgKeyboardCommandsAndCaretSurvivePreview 覆盖插入点、键盘、日期面板与编辑命令；本次仅读取，未运行；OrgendaUITests/MotionFlowUITests.swift:784 testDocumentModeSwitchPreservesPreviewScrollPosition 覆盖切换后的滚动坐标；本次未运行；OrgendaUITests/WorkspaceSyncUITests.swift:4 testSearchDocumentOpensPreviewAndKeepsResults 覆盖预览默认状态及进入编辑后的首次搜索选择；本次未运行；OrgendaTests/Components/Editor/OrgSyntaxTextEditorTests.swift:130 testPreviewEditsAndNativeTypingShareUndoAcrossModes 覆盖跨模式撤销；本次未运行；OrgendaUITests/MotionFlowUITests.swift:256 testGestureEdgeBackInPreviewEditorFolderAndSettings 覆盖系统边缘返回与内容持久化；本次未运行；若今后改动容器，需实机验证窄窗口／辅助功能字号的 Picker 回退、VoiceOver 仅访问活动内容及大纲关闭后焦点恢复

代码依据：

- [Orgenda/Features/Files/Document/OrgDocumentView.swift:26](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Document/OrgDocumentView.swift:26) — ZStack 保留两个内容视图，按模式限制命中与辅助功能；后续使用原生工具栏、Picker、ViewThatFits 和 sheet
- [Orgenda/Components/Editor/OrgEditorSession.swift:64](/Users/roifewu/.config/orgenda/Orgenda/Components/Editor/OrgEditorSession.swift:64) — suspendEditing／restorePosition 保存滚动与键盘状态，selectHeading 把 UTF-8 字节位置转为 UITextView 的 UTF-16 选择范围
- [Orgenda/Features/Files/FilesView.swift:232](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/FilesView.swift:232) — 生产文档目的地传入 locationRequest 与 onBack，并以 path 维持文档身份；另有 WorkspaceBrowser:58 与 SearchResultRow:68 调用

API 依据：

- [本机 iPhoneOS SDK：SwiftUI ViewThatFits、SegmentedPickerStyle、MenuPickerStyle](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：核对 14278、16194、30529 行：ViewThatFits 支持按轴适配，segmented 与 menu 均为系统 PickerStyle，现有页面已经使用。
- [本机 iPhoneOS SDK：SwiftUI DocumentGroup 与 sheet](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：核对 28780 行 DocumentGroup 遵循 Scene 且以 Content: View 为内容，不能作为等价页面替换；9145 行提供当前使用的绑定式 sheet(isPresented:onDismiss:content:)。

专属分析 agent：`/root/audit_group_b/c047`。

<a id="c048"></a>

### C048 · FilesView

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/FilesView.swift:15)　置信度：high

当前实现：工作区文件入口：iPhone 使用 NavigationStack，iPad 使用 NavigationSplitView 加详情栈；以 List、ContentUnavailableView、toolbar、sheet、refreshable 和原生拖放组成文件浏览，协调路径、同步状态及跨标签源位置跳转。

系统候选：无实质替换；保留现有 NavigationStack/NavigationSplitView/List 组合。fileImporter 只负责选择导入 URL，UIDocumentBrowserViewController 可浏览和打开系统文档，但不是当前工作区路由与 Org 文档详情的等价替代。

判断：容器、列表、空状态和拖放已由系统提供。自有逻辑负责跨标签定位、显式与隐式目录、文件删除后的路径修剪及工作区切换清理；这些业务状态仍需应用维护。统一改用文档浏览器不会消除这些职责，且要重新接入现有文档编辑和同步流程。手机单栈与 iPad 固定分栏分别保护返回路径和编辑连续性，未发现能无损减少实现的替代控件。

预期收益：保持系统导航与交互能力；没有额外 UIKit 桥接或整屏替换带来的明确复杂度收益。保留这一集中协调工作区导航的边界。

必须保留：手机单一推入/返回栈；iPad 窗口尺寸变化时保留分栏内文档及草稿；Show in File 构造完整目录路径并把 SourceLocation 和 itemID 传至文档；显式和隐式目录可达；文件删除修剪失效路径；工作区会话变化清空旧路由；根目录拖放须经 canMoveFile 校验并调用工作区移动流程，保留当前文件身份；刷新同步、同步状态辅助功能标签、设置与最近删除入口、减少动态效果设置

验证要求：已静态阅读 OrgendaUITests/IPadLayoutUITests.swift:138 testNestedFileDraftSurvivesRotationAndTabNavigation，覆盖分栏、旋转、跨标签返回和未提交草稿保留；本次未运行。；已静态阅读 OrgendaUITests/MotionFlowUITests.swift:202 testAgendaShowInFilePreservesSourceAndFolderNavigation，覆盖源内容、标题定位和逐层边缘返回；本次未运行。；已静态阅读 OrgendaUITests/MotionFlowUITests.swift:104 testFileBrowserFolderDragMovesSubtreeAndPickerMovesItBack，覆盖子树移动后的导航；本次未运行。；若未来合并手机与平板导航容器，需原型验证窄窗折叠、尺寸变化时详情身份、草稿保留和返回栈；不能仅凭源代码认定等价。

代码依据：

- [Orgenda/Features/Root/OrgendaRootView.swift:200](/Users/roifewu/.config/orgenda/Orgenda/Features/Root/OrgendaRootView.swift:200) — Files 标签实际构造 FilesView，showInFile 在 261 行设置请求并切换该标签。
- [Orgenda/Features/Files/FilesView.swift:32](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/FilesView.swift:32) — 手机 NavigationStack 与 39 行 iPad NavigationSplitView 已使用系统容器；117 行 List 及 129/135 行原生拖放。
- [Orgenda/Features/Files/FilesView.swift:68](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/FilesView.swift:68) — 消费定位请求并构造不同设备的导航路径；89/94 行清理会话或失效路径；218 行分派显式目录、隐式目录和 Org 文档。

API 依据：

- [本地 iPhoneOS 27.0 SDK SwiftUI NavigationSplitView、NavigationStack、fileImporter 与 dragContainer 声明](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对 NavigationStack 声明 19183 行、NavigationSplitView 及 preferredCompactColumn/columnVisibility 初始化器 26970–27000 行、fileImporter 返回 URL 的接口 9053–9055 行、dragContainer 32096–32102 行；现有导航与拖放是系统 API。
- [本地 iPhoneOS 27.0 SDK UIDocumentBrowserViewController 声明](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/UIKit.framework/Headers/UIDocumentBrowserViewController.h)：已核对 43–47 行按 UTType 打开文档、94–110 行按 URL 揭示/导入/重命名文档；这些接口不能直接接替当前 WorkspaceDocument 路由和 Org 标题位置请求。

专属分析 agent：`/root/audit_group_b/c048`。

<a id="c049"></a>

### C049 · OrgPreviewMathBlock

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Blocks/OrgPreviewMathBlock.swift:3)　置信度：high

当前实现：用原生水平 ScrollView 承载公式 UIImage；随动态字号和深浅模式请求渲染，失败时显示等宽原文 Text，并为图像提供原文无障碍标签。

系统候选：保留现有 ScrollView + Image(uiImage:) + Text 组合；未找到可直接接收 Org/LaTeX 并保持现有公式排版的 SwiftUI 系统控件。

判断：该组件只是原生滚动、图像和文本的短封装，复杂公式排版已集中在 OrgMathRendering。三个生产调用入口共用其主题、字号和失败回退策略；普通 Text 无法替代现有公式图像而保持排版。移除封装只会把相同分支散入调用方，没有实质系统替代收益。

预期收益：现有实现已将展示交给系统控件；保留可避免三个调用位置重复处理渲染与回退，无需新增桥接。

必须保留：宽公式的水平滚动；动态字号及深浅模式对应的公式渲染；渲染失败时保留完整原文和等宽样式；图像的原文无障碍标签；回退文本的系统文本选择能力

验证要求：OrgendaTests/Features/Files/OrgPreviewContainerMathTests.swift:66 — testIndentedAlignmentTokensDoNotBreakDisplayFormula 覆盖缩进对齐公式提取与渲染。；OrgendaTests/Components/Editor/OrgSyntaxTextEditorTests.swift:351 — testUserAlphaExamplesRenderWithDelimiterBoundaryNewlines 覆盖显示公式的有效图像尺寸。；OrgendaTests/Components/Editor/OrgSyntaxTextEditorTests.swift:749 — testUnsupportedRaisedPayloadIsPreservedForLiteralFallback 覆盖不支持公式返回 nil，未覆盖视图回退交互。；静态审查，未运行测试；若后续修改展示，应验证宽公式滚动、动态字号、深浅模式与 VoiceOver 原文标签；图像并不因此获得可选择的 LaTeX 文本。

代码依据：

- [Orgenda/Features/Files/Preview/Blocks/OrgPreviewMathBlock.swift:9](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Blocks/OrgPreviewMathBlock.swift:9) — 原生水平 ScrollView 包含渲染图像或等宽 Text 回退。
- [Orgenda/Features/Files/Preview/Rendering/OrgMathRendering.swift:24](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Rendering/OrgMathRendering.swift:24) — 依据字号、色彩模式和表达式模式生成并缓存 MathImage 图像。
- [Orgenda/Features/Files/Preview/OrgPreviewContent.swift:188](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/OrgPreviewContent.swift:188) — math_block 生产路径调用本组件；另有 OrgPreviewParagraph.swift:24 和 OrgPreviewMathFlow.swift:17。

API 依据：

- [本地 iOS SDK：SwiftUI ScrollView、Image(uiImage:)、textSelection 与 accessibilityLabel](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：核对 ScrollView 的 Axis.Set 初始化（18995 行起）、UIImage 图像初始化（2372 行）、文本选择（2336 行）及标签（899 行起）；均已由本组件采用。
- [本地 iOS SDK：SwiftUICore Text](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/SwiftUICore.framework/Modules/SwiftUICore.swiftmodule/arm64e-apple-ios.swiftinterface)：核对 Text 的字符串及 AttributedString 接口，并搜索 SwiftUI/SwiftUICore 中 LaTeX、MathML、MathView、MathEquation 声明，未发现对应公式排版控件；不将普通 Text 视为等价替代。

专属分析 agent：`/root/audit_group_b/c049`。

<a id="c050"></a>

### C050 · OrgPreviewMathFlow

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Blocks/OrgPreviewMathFlow.swift:4)　置信度：high

当前实现：使用原生 VStack、ForEach 和 fixedSize，将 Org 富文本片段按行内内容与独立公式顺序排列，并接受正文样式和居中设置。

系统候选：现有 VStack(alignment:spacing:) 与 ForEach 已提供所需系统布局；没有可进一步替换此业务封装的等价系统组件。

判断：该类型没有自定义布局算法或交互，仅将 Org 分段结果交给原生纵向栈，按类型分派富文本和公式子视图。引用、verse、center 等容器复用此流程；用单个 Text 会丢失独立公式子视图，用其他系统容器仍需保留同样分段与分派，无法实质减少实现。

预期收益：保留能集中复用两处调用的分段展示逻辑；改写为其他系统容器没有明确复杂度收益。

必须保留：行内内容与 display 公式的原始顺序及连续公式独立成块；普通内容左对齐和 center 容器居中设置；引用的 subheadline 样式传递及行内内容按实际高度展开；通过子视图保留富文本、图片、公式渲染与失败回退行为

验证要求：OrgendaTests/Features/Files/OrgPreviewContainerMathTests.swift:102 testQuoteBodyKeepsInlineMathAndGroupsMultilineDisplayMath 验证引用分段为 inline/display/inline。；OrgendaTests/Features/Files/OrgPreviewContainerMathTests.swift:130 testVerseAndCenterPreserveIndentationAndSeparateDisplayExpressions 验证缩进及连续独立公式顺序。；仅静态审查，未运行测试；既有测试覆盖分段数据，不证明实际居中、长公式滚动及 Dynamic Type 排版。

代码依据：

- [Orgenda/Features/Files/Preview/Blocks/OrgPreviewMathFlow.swift:9](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Blocks/OrgPreviewMathFlow.swift:9) — 原生 VStack/ForEach 根据段类型分派两个子视图，间距为 4。
- [Orgenda/Features/Files/Preview/Markup/OrgPreviewContainerMath.swift:25](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Markup/OrgPreviewContainerMath.swift:25) — segments 遇到 display 公式刷新行内内容，保留公式与文本顺序。
- [Orgenda/Features/Files/Preview/OrgPreviewDrawer.swift:244](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/OrgPreviewDrawer.swift:244)、Orgenda/Features/Files/Preview/Blocks/OrgPreviewQuote.swift:7 — 生产调用分别传递 center 对齐和引用文字样式。

API 依据：

- [iPhoneOS SDK SwiftUICore VStack、ForEach 与 View.fixedSize 声明](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/SwiftUICore.framework/Modules/SwiftUICore.swiftmodule/arm64e-apple-ios.swiftinterface)：核对 VStack(alignment:spacing:content:)（1314）、fixedSize(horizontal:vertical:)（1594）与 ForEach 声明（21778 起）；布局和集合生成均为现有系统 API。

专属分析 agent：`/root/audit_group_b/c050`。

<a id="c051"></a>

### C051 · OrgPreviewKeyword

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Blocks/OrgPreviewMetadata.swift:3)　置信度：high

当前实现：按 Org 关键词分派：标题使用原生 Text、title2 字体和标题无障碍特征；caption 使用现有富文本渲染；其他关键词以可选择的次级 Text 显示。

系统候选：现有 SwiftUI Text、font、textSelection、accessibilityAddTraits 已覆盖原生显示职责；无可实质简化整个包装器的系统替代组件。

判断：该组件只有 Org 语义分派与原生样式配置，没有重复实现系统文本控件。标题需去除关键词前缀，caption 必须读取 keyword_value 并保留富文本与数学片段，其他关键词需保留原文。直接统一为 Text 会丢失 caption 渲染能力；改用 UIKit 桥接不能减少复杂度，保留此小型业务包装更合适。

预期收益：保留可集中管理关键词显示规则；没有可观的系统替换收益，无需新增桥接层。

必须保留：关键词匹配不区分大小写；标题去前缀、粗体标题字号及无障碍标题特征；caption 的 Org 富文本、数学片段及文字选择；其他关键词原文展示及文字选择

验证要求：OrgendaTests/Features/Files/OrgPreviewContainerMathTests.swift:230 — testOrdinaryContainersRemainIntactAndCaptionMathIsAvailable 验证 caption 仍产生数学片段。；静态检索未发现此 View 的独立交互测试；若将来调整显示层，应人工检查标题 VoiceOver 特征、caption 数学显示与文本选择。本次未构建或运行。

代码依据：

- [Orgenda/Features/Files/Preview/Blocks/OrgPreviewMetadata.swift:3](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Blocks/OrgPreviewMetadata.swift:3) — 三个分支分别配置标题、caption 与原文显示，已经使用 Text 及系统修饰器。
- [Orgenda/Features/Files/Preview/OrgPreviewContent.swift:205](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/OrgPreviewContent.swift:205) — keyword 行的生产渲染路径直接调用 OrgPreviewKeyword。
- [OrgendaTests/Features/Files/OrgPreviewContainerMathTests.swift:230](/Users/roifewu/.config/orgenda/OrgendaTests/Features/Files/OrgPreviewContainerMathTests.swift:230) — caption 的 keyword_value 经 fragments 转换保留数学表达式。

API 依据：

- [SwiftUICore SDK — Text / font / AccessibilityTraits.isHeader](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/SwiftUICore.framework/Modules/SwiftUICore.swiftmodule/arm64e-apple-ios.swiftinterface)：核实 Text 的 StringProtocol 初始化器（23573）、font（16307）及 isHeader（7860），现有标题和普通文本均已采用原生 API。
- [SwiftUI SDK — View.textSelection / accessibilityAddTraits](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：核实 textSelection（2336）及 accessibilityAddTraits（29563）的公开声明，选择及标题无障碍职责已有系统实现。

专属分析 agent：`/root/audit_group_b/c051`。

<a id="c052"></a>

### C052 · OrgPreviewFallback

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Blocks/OrgPreviewMetadata.swift:28)　置信度：high

当前实现：无解析文档但仍有源文件时，使用 LazyVStack、ForEach、Text 和 HStack 按行显示内容；识别星号标题中的工作流状态并显示原生符号和主题颜色，保留空行高度。

系统候选：无具有实质收益的等价替代。Text(source) 可显示原文，但不能直接保留逐行工作流图标与独立颜色；Label 仍需标题识别和星号布局。

判断：当前主要实现已经是系统文本与惰性布局的组合，自定义部分仅承担无语法树时的 Org 标题识别、工作流映射及空行占位。单个 Text 会丢失状态图标、分色和行间距，Label 也无法消除逐行识别逻辑。保留这一小型业务封装更清楚；没有可实质删除实现且保持行为的系统替代。

预期收益：保留现状；改成另一个原生包装不会减少业务逻辑，反而需要重建现有布局。

必须保留：无解析结果但源内容存在时仍可阅读；根据当前环境工作流识别星号标题、展示状态图标及颜色；普通行原文、空行占位与多行文本自然增高；org.preview.fallback 无障碍标识

验证要求：rg 搜索 OrgendaTests、OrgendaUITests 中 OrgPreviewFallback 与 org.preview.fallback，未找到直接覆盖。；OrgendaTests/Domain/Org/WorkspaceConfigurationTests.swift:86 的 testSparseKeywordOverridesPreserveDefaultAppearance 覆盖工作流符号与颜色映射，但不覆盖本视图布局。；若以后调整布局，需验证无解析数据、连续空行、长标题、大字体、未知状态和环境内自定义状态的显示；本次仅静态分析，未构建或运行。

代码依据：

- [Orgenda/Features/Files/Preview/Blocks/OrgPreviewMetadata.swift:33](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Blocks/OrgPreviewMetadata.swift:33) — 原生惰性堆栈逐行枚举，识别工作流标题并保留空行。
- [Orgenda/Features/Files/Preview/InteractiveOrgPreview.swift:69](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/InteractiveOrgPreview.swift:69) — 源文件存在且 parsedDocuments 无结果时实际调用 fallback。
- [Orgenda/Components/Workflow/OrgWorkflowControls.swift:13](/Users/roifewu/.config/orgenda/Orgenda/Components/Workflow/OrgWorkflowControls.swift:13) — 状态图标使用 Text(Image(systemName:))，并设置颜色及无障碍标签。

API 依据：

- [SwiftUICore SDK: LazyVStack、HStack、Text](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/SwiftUICore.framework/Modules/SwiftUICore.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对 LazyVStack 的 alignment/spacing/content 初始化器（10748）、HStack 的 alignment/spacing 初始化器（6782）以及 Text 字符串初始化器（23568）；现有布局与文本均是系统 API。
- [SwiftUI SDK: Label](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对 Label<Title, Icon> 的 title/icon 构造器（30896）；它提供标题和图标组合，不包含 Org 行识别或工作流映射。

专属分析 agent：`/root/audit_group_b/c052`。

<a id="c053"></a>

### C053 · OrgPreviewParagraph

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Blocks/OrgPreviewParagraph.swift:3)　置信度：high

当前实现：将 Org 段落分派为独立时间戳按钮、显示公式或富文本，使用 Group、Text/AttributedString、原生文本选择与 OpenURLAction；把行内日期链接接到现有编辑流程。

系统候选：无有实质收益的系统组件替换；Text(AttributedString)、Button 与 OpenURLAction 已通过自身或子组件采用。

判断：这是段落级语义分派与原生控件组合。Text 和链接处理已由系统提供，额外逻辑负责识别独立或行内 Org 时间戳、呈现待保存替换、阻止重复编辑及分派公式/图片内容。单独换成 Text 或 Link 仍需保留这些逻辑，无法消除有价值的封装。

预期收益：保留现有封装；进一步换成系统控件没有可证明的复杂度收益，直接内联会把业务分派搬到调用方。

必须保留：仅含一个有效时间戳时采用可编辑日期控件；混合段落保留行内日期链接。；使用 pendingReplacements 显示最新草稿，并阻止该时间戳在保存中再次编辑。；支持 Org 日期范围、重复规则、本地化呈现及原始字节定位。；允许支持的外部 URL 交给系统，其他无匹配链接丢弃。；保留公式、图片、文本选择及段落无障碍标识。

验证要求：已静态读取 OrgendaUITests/MotionFlowUITests.swift:1277 的 testPlainRecurringTimestampPreviewUsesControlsAndRemovesRule，覆盖独立时间戳入口、重复规则编辑及不添加 planning 关键字；未运行。；已静态读取 OrgendaTests/Domain/Org/OrgSourceMutationTests.swift:219 的 testInlineRecurringTimestampPatchPreservesUnicodeAndOtherDates，以及 :677 的 testReadableDateKeepsTimeRangeRepeatModesWarningsAndSource；未运行。；已静态读取 OrgendaTests/Features/Files/OrgPreviewImagePresentationTests.swift:7 的 testImageInChineseParagraphPreservesMathLinksAndUTF8SourceOffsets；未运行。；若将来改动此包装，需运行时核对混合段落日期点击、保存期间重复点击被阻止、外链路由和文本选择；当前源码与测试不足以证明这些手势交互。

代码依据：

- [Orgenda/Features/Files/Preview/Blocks/OrgPreviewParagraph.swift:11](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Blocks/OrgPreviewParagraph.swift:11) — 独立时间戳使用已有日期控件，其余内容按显示公式与富文本分支渲染。
- [Orgenda/Features/Files/Preview/Blocks/OrgPreviewParagraph.swift:32](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Blocks/OrgPreviewParagraph.swift:32) — 原生 OpenURLAction 分流外链和时间戳编辑，并检查待保存状态；:55–66 读取替换内容并构造带字节位置的日期链接。
- [Orgenda/Features/Files/Preview/OrgPreviewContent.swift:182](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/OrgPreviewContent.swift:182) — paragraph 分支实际调用此组件并传递 pendingReplacements 与 onEditPlanning。

API 依据：

- [iPhoneOS SDK — SwiftUICore Text.init(AttributedString) 与 OpenURLAction](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/SwiftUICore.framework/Modules/SwiftUICore.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对 :9832 的 AttributedString 初始化器、:3735–3746 的 URL handler 及 handled/discarded/systemAction、:3759 的可设置 openURL 环境值。当前包装已使用系统提供的富文本和链接分流能力。
- [iPhoneOS SDK — View.textSelection(_:)](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对 :2332–2336，textSelection 在 iOS 15 起可用；组件已直接启用此原生修饰器。

专属分析 agent：`/root/audit_group_b/c053`。

<a id="c054"></a>

### C054 · OrgPreviewQuote

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Blocks/OrgPreviewQuote.swift:3)　置信度：high

当前实现：将 Org 引用块正文交给共享数学与富文本流，使用 SwiftUI 字体、次要文字色、内边距、Rectangle 侧线、固定纵向尺寸和文本选择修饰器；以源码字节位置设置可访问性标识。

系统候选：无有实质收益的直接替代；GroupBox 可容纳现有正文，但仍须保留 Org 解析、数学/图片渲染及引用侧线样式。

判断：该组件只封装引用块语义与少量原生样式，正文沿用共享渲染链；主预览和只读抽屉均有实际调用。GroupBox 仅提供分组容器，不能接替 Org 正文截取、公式分段或附件语义，保留现有外观还需自定义样式。直接换成 Text 会丢失公式和图片行为，因此没有值得替换的实现层。

预期收益：保留短业务封装可复用引用样式；改用 GroupBox 无明确复杂度收益，无法删除共享解析与渲染逻辑。

必须保留：去除 Org 引用块分隔符并保留正文富文本；行内及跨空行展示公式的分段；图片附件上下文与原始 UTF-8 字节偏移；左侧主题色竖线、文字选择及基于 startByte 的可访问性标识

验证要求：OrgendaTests/Features/Files/OrgPreviewContainerMathTests.swift:102 — testQuoteBodyKeepsInlineMathAndGroupsMultilineDisplayMath 覆盖分隔符移除、行内/展示数学及强调文本。；OrgendaTests/Features/Files/OrgPreviewImagePresentationTests.swift:75 — testQuoteImageKeepsHeadingAttachmentContextAndOriginalByteOffset 覆盖附件路径上下文与源码偏移。；仅静态审查，未运行测试；现有测试不证明长引用、动态字体及选择交互的实际呈现，若改容器需针对这些行为做运行验证。

代码依据：

- [Orgenda/Features/Files/Preview/Blocks/OrgPreviewQuote.swift:6](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Blocks/OrgPreviewQuote.swift:6) — 正文使用 blockFragments/OrgPreviewMathFlow，引用外观由系统修饰器和 Rectangle 实现。
- [Orgenda/Features/Files/Preview/OrgPreviewContent.swift:168](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/OrgPreviewContent.swift:168) — 主预览 quote_block 调用；Orgenda/Features/Files/Preview/OrgPreviewDrawer.swift:96 亦在只读内容调用。
- [Orgenda/Features/Files/Preview/Markup/OrgPreviewContainerMath.swift:11](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Markup/OrgPreviewContainerMath.swift:11) — 正文按原始字节范围提取，segments 保留展示公式分段。

API 依据：

- [SwiftUI GroupBox 与 View.textSelection 本地 iOS SDK 声明](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对 15952/15996 行 GroupBox 的 label/content 和无标签构造；2336 行 textSelection 是系统 View 修饰器，iOS 15 起可用。GroupBox 声明未提供 Org 或引用正文处理。
- [SwiftUICore View.overlay、Rectangle 与 Font.italic 本地 iOS SDK 声明](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/SwiftUICore.framework/Modules/SwiftUICore.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对 4054 行 overlay(alignment:content:)、13016 行 Rectangle: Shape、15243 行 Font.italic，当前引用装饰已由系统 API 组合。

专属分析 agent：`/root/audit_group_b/c054`。

<a id="c055"></a>

### C055 · OrgPreviewRichText

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Blocks/OrgPreviewRichText.swift:4)　置信度：high

当前实现：以 SwiftUI 条件视图判断片段中是否含图片，将 fragments 与 UIFont.TextStyle 转交给图片流或行内 Text 组合；自身没有自定义布局、绘制或交互。

系统候选：无需替换；现有 ViewBuilder 条件分支已是系统能力。Text(AttributedString) 只适合已转成属性文本的内容，不能直接接收该业务片段枚举。

判断：该组件集中维护含图片与纯行内内容的渲染分流，段落、标题、表格及元数据均有实际调用。用单个 Text 替换会丢失图片流路径；把分支展开到各调用点只会重复业务判断，不能减少底层渲染实现。现有系统 ViewBuilder 已承担条件组合，没有可带来实质收益的系统控件替换。

预期收益：保留短小公共入口，避免多处重复内容分流；替换本封装没有实质复杂度收益。

必须保留：含图片时进入图片流，并保留文本、公式、图片的源顺序；无图片时使用行内文本路径；向两种路径一致传递 fragments 与 textStyle

验证要求：OrgendaTests/Features/Files/OrgPreviewImagePresentationTests.swift:7 testImageInChineseParagraphPreservesMathLinksAndUTF8SourceOffsets，覆盖混合内容及图片前后公式分段；OrgendaTests/Features/Files/OrgPreviewImagePresentationTests.swift:35 testAdjacentImagesKeepSourceOrderWithoutEmptyTextRows，覆盖连续图片顺序；OrgendaTests/Components/Editor/OrgSyntaxTextEditorTests.swift:293 testPreviewFragmentsPreserveMarkupAroundInlineMath，覆盖行内公式周围样式与链接；本次仅静态审查，未运行测试

代码依据：

- [Orgenda/Features/Files/Preview/Blocks/OrgPreviewRichText.swift:8](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Blocks/OrgPreviewRichText.swift:8) — 仅按 image 片段分流到 OrgPreviewImageFlow 或 OrgPreviewInlineText
- [Orgenda/Features/Files/Preview/Blocks/OrgPreviewParagraph.swift:26](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Blocks/OrgPreviewParagraph.swift:26) — 生产调用，并在外层配置字体、选择及链接动作
- [Orgenda/Features/Files/Preview/Images/OrgPreviewImageView.swift:56](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Images/OrgPreviewImageView.swift:56) — 图片流使用 VStack/ForEach 将文本片段与图片按顺序组合

API 依据：

- [SwiftUI ViewBuilder.buildEither 与 Text.init(AttributedString) 本地 SDK 声明](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/SwiftUICore.framework/Modules/SwiftUICore.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对 5618–5633 行条件视图构建及 9832 行属性文本初始化；系统支持现有组合方式，属性文本初始化并非 OrgPreviewInlineFragment 的解释器。

专属分析 agent：`/root/audit_group_b/c055`。

<a id="c056"></a>

### C056 · OrgPreviewInlineText

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Blocks/OrgPreviewRichText.swift:17)　置信度：high

当前实现：把 Org 行内片段归并为单一 SwiftUI Text：AttributedString 保留富文本属性，公式经 SwiftMath 渲染成 Image 后嵌入 Text 并校正基线，失败时显示原文；图片片段退回标签。

系统候选：已使用 Text(AttributedString)、Text(Image)、Text 插值及 baselineOffset；没有可进一步等价替换整层的系统组件。

判断：当前实现已把换行和文本布局交给系统 Text，自定义部分仅负责 Org 片段到文本、公式图片的转换。单独改成 Text(AttributedString) 仍需公式渲染、失败原文及基线逻辑；换成 UILabel/UITextView 会增加桥接与附件处理。该包装同时被普通富文本和图片流复用，保留有实际价值。

预期收益：没有实质系统替换收益；保留短小包装可避免两个生产调用位置重复片段映射与公式处理。

必须保留：片段顺序、AttributedString 样式及链接属性；公式按 textStyle、Dynamic Type 和明暗主题渲染；公式 descent 基线校正及渲染失败原文回退；单一 Text 的连续排版及父层文本选择、openURL 配置；图片片段标签回退

验证要求：静态核对 OrgSyntaxTextEditorTests.swift:293 testPreviewFragmentsPreserveMarkupAroundInlineMath，覆盖公式周围样式和链接；未运行。；静态核对 OrgSyntaxTextEditorTests.swift:311 testPreviewRendersEveryInlineFormulaInMixedChineseParagraph，覆盖中文混排与公式渲染；未运行。；OrgPreviewContainerMathTests.swift:27、46 覆盖强调样式及带公式的链接标签；未运行。现有单元测试不能证明最终断行和基线效果，若调整组合方式，应手动核对长中文、超大字号、明暗主题、链接及选择行为。

代码依据：

- [Orgenda/Features/Files/Preview/Blocks/OrgPreviewRichText.swift:17](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Blocks/OrgPreviewRichText.swift:17) — 完整组件仅用 Text 归并片段，公式环境参数、失败回退和基线偏移位于同一 body。
- [Orgenda/Features/Files/Preview/Images/OrgPreviewImageView.swift:61](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Images/OrgPreviewImageView.swift:61) — 图片流在文本段直接复用该组件，普通富文本入口亦在 OrgPreviewRichText.swift:12 调用。
- [Orgenda/Features/Files/Preview/Blocks/OrgPreviewParagraph.swift:26](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Blocks/OrgPreviewParagraph.swift:26) — 生产段落经富文本入口使用该组件，并在父层设置字体、文本选择和 openURL。

API 依据：

- [SwiftUICore SDK：Text 图片、AttributedString、插值与基线 API](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/SwiftUICore.framework/Modules/SwiftUICore.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对 6209/6270 行 Text 插值、9670 行 Text(Image)（iOS 14+）、9832 行 Text(AttributedString) 及 16331 行返回 Text 的 baselineOffset；证实当前本身是系统文本组合。

专属分析 agent：`/root/audit_group_b/c056`。

<a id="c057"></a>

### C057 · OrgPreviewSourceBlock

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Blocks/OrgPreviewSourceBlock.swift:3)　置信度：high

当前实现：用 VStack、Label、横向 ScrollView 与可选择的 Text(AttributedString) 展示 Org 源码、示例、导出和固定宽度块；源码委托 OrgCodeHighlighting 高亮，并适配明暗模式和动态字号。

系统候选：继续使用现有 SwiftUI Label + ScrollView + Text；无可移除 Org 语义及高亮配置的等价单一系统组件。TextEditor(AttributedString) 是编辑控件，不能直接简化此只读预览。

判断：主预览和抽屉内容均实际复用此组件。现有展示、选取和滚动已经由系统控件承担，自定义部分集中于 Org 结构剥离、块类型标题、语言提取及高亮配置。系统富文本编辑器仍需这些逻辑，并引入编辑与尺寸管理；保留封装没有实质可替代实现。

预期收益：保留短小原生组合，避免用编辑控件增加交互和尺寸管理；无明确代码复杂度收益可兑现。

必须保留：源码、示例、导出、固定宽度块各自标题和内容语义；保留代码字面文本、空白与换行，长行横向滚动；文本选择与复制、块及内容的稳定无障碍标识；源码语言高亮及明暗模式、动态字号适配

验证要求：OrgendaTests/Components/Editor/OrgSyntaxTextEditorTests.swift:266 testPreviewLiteralBlocksStripOnlyStructuralDelimiters 验证字面内容与固定宽度空行保留。；OrgendaTests/Components/Editor/OrgSyntaxTextEditorTests.swift:542 testCodeHighlightingPreservesSourceAndProducesStyledRuns 验证高亮不改源码并生成样式。；现有测试为源码静态查阅，未运行；若后续调整容器，需验证长行横向滚动、选择复制、大字号及 VoiceOver 读序。

代码依据：

- [Orgenda/Features/Files/Preview/Blocks/OrgPreviewSourceBlock.swift:9](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Blocks/OrgPreviewSourceBlock.swift:9) — Label、ScrollView、Text 原生组合；26 行开始为内容与标题业务配置。
- [Orgenda/Features/Files/Preview/OrgPreviewContent.swift:164](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/OrgPreviewContent.swift:164) — 四类块统一调用该组件；OrgPreviewDrawer.swift:94 亦复用。
- [Orgenda/Features/Files/Preview/Rendering/OrgCodeHighlighting.swift:14](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Rendering/OrgCodeHighlighting.swift:14) — 依据语言、颜色模式与动态字号生成 AttributedString，保留现有高亮缓存和回退。

API 依据：

- [iPhoneOS 27.0 SDK — SwiftUI ScrollView、textSelection 与 TextEditor 声明](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对 2336 行 textSelection、18995 行 ScrollView 轴参数及 3896 行 iOS 26+ 富文本 TextEditor；现有原生滚动与选择 API 已满足展示职责，编辑器不提供 Org 解析或语言高亮。
- [iPhoneOS 27.0 SDK — SwiftUICore Text.init(AttributedString)](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUICore.framework/Modules/SwiftUICore.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对 9832 行富文本 Text 初始化器，当前组件已直接使用该原生展示路径。

专属分析 agent：`/root/audit_group_b/c057`。

<a id="c058"></a>

### C058 · OrgPreviewTable

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Blocks/OrgPreviewTable.swift:3)　置信度：high

当前实现：以原生横向 ScrollView、Grid、GridRow、Divider 展示 Org 表格；解析管道保留空单元格、补齐列数，按分隔行识别表头；单元格支持富文本、公式、图片、文本选择及逐行辅助功能合并。

系统候选：现有 Grid/GridRow 已是合适的系统布局；SwiftUI Table 可展示结构化数据，但不是保持现有预览语义的直接替代。

判断：当前没有自制表格布局算法，主体已经使用系统 Grid。自定义部分负责 Org 空单元格、分隔线、可选表头及富文本映射，换控件仍需保留。Apple 文档明确 Table 在紧凑宽度隐藏表头和首列以外的列，与手机上横向浏览完整原表不同，迁移无实质简化收益。

预期收益：保留短小的语义适配层；没有已证实可消除的非原生布局实现，改用 Table 会增加数据与列配置适配。

必须保留：横向滚动时保留全部列及列间对齐；空单元格、不齐列补位、原始分隔行和可选表头语义；单元格 Org 富文本、链接、数学公式和图片呈现；文本选择、逐行辅助功能组合及稳定表格标识

验证要求：OrgendaTests/Features/Files/OrgPreviewContainerMathTests.swift:84 testTableCellsExtractFormulaImagesAlongsideLabelsAndLinks 覆盖单元格公式、文字与链接提取；本次仅静态阅读，未运行。；未发现针对 OrgPreviewTable 布局的直接测试；若仍试验 Table，需原型验证 iPhone 紧凑宽度完整列访问、空列/不齐列、混合富文本、VoiceOver 与文本选择，不应据静态声明推断等价。

代码依据：

- [Orgenda/Features/Files/Preview/Blocks/OrgPreviewTable.swift:7](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Blocks/OrgPreviewTable.swift:7) — 原生 ScrollView/Grid/GridRow/Divider 组合，39–53 行负责 Org 表头、列数和空单元格提取。
- [Orgenda/Features/Files/Preview/OrgPreviewContent.swift:162](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/OrgPreviewContent.swift:162) — 主预览的 table 分支实际调用；Orgenda/Features/Files/Preview/OrgPreviewDrawer.swift:93 只读容器也复用。
- [OrgendaTests/Features/Files/OrgPreviewContainerMathTests.swift:84](/Users/roifewu/.config/orgenda/OrgendaTests/Features/Files/OrgPreviewContainerMathTests.swift:84) — 表格单元格的公式、标签与链接提取已有覆盖。

API 依据：

- [iOS 27 SDK：SwiftUI Grid、GridRow 与跨列修饰符](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：核对 23197–23280 行：Grid、GridRow、gridCellColumns 和 gridCellUnsizedAxes 均为 iOS 16 起的系统 API；目标 iOS 27 可直接使用。
- [Apple SwiftUI Table：Using tables on different platforms](https://developer.apple.com/documentation/swiftui/table?changes=_8)：官方文档明确 iPhone 或紧凑水平 size class 自动隐藏表头及首列以外的列，不能视为横向完整 Org 表预览的等价控件。

专属分析 agent：`/root/audit_group_b/c058`。

<a id="c059"></a>

### C059 · OrgPreviewImageFlow

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Images/OrgPreviewImageView.swift:22)　置信度：high

当前实现：将 Org 行内片段按图片切分，过滤纯空白文字段；通过原生 VStack 与 ForEach 顺序组合富文本和独立图片视图，传递文字样式并保持文字完整高度。

系统候选：保留现有 VStack + ForEach；Text(Image) 可表达行内图片，但不能等价承载当前独立图片视图的加载、重试与打开操作。

判断：当前布局已由系统 VStack 和 ForEach 完成，自定义部分仅表达 Org 图片独占一行、相邻图片间不产生空行以及文字和公式顺序不变的规则。单个 Text(Image) 不会接管图片子视图的独立交互；改用文本附件仍需片段转换及交互桥接，不能删除这些业务规则，因此没有实质系统替代收益。

预期收益：保留短小的原生布局封装，避免把片段语义分散到调用方；没有可明显减少复杂度的系统替代。

必须保留：图片独占一行，前后富文本、链接和公式保持源顺序；相邻图片之间不插入仅含空白的文字行；原始图片引用、字节位置及文字样式继续传给对应子视图；图片加载、错误重试和打开查看仍由图片子视图处理

验证要求：已静态阅读 OrgendaTests/Features/Files/OrgPreviewImagePresentationTests.swift 的 testImageInChineseParagraphPreservesMathLinksAndUTF8SourceOffsets、testAdjacentImagesKeepSourceOrderWithoutEmptyTextRows 和 testCustomBlockImageKeepsSourceOffsetAfterGrouping；未运行测试。；若调整布局，需核对大字号下的文字高度、图片前后公式及链接顺序；当前结论来自源码及 SDK 声明，未作运行时验证。

代码依据：

- [Orgenda/Features/Files/Preview/Images/OrgPreviewImageView.swift:31](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Images/OrgPreviewImageView.swift:31) — segments 按图片边界分组，过滤纯空白文本；第 57 行使用 VStack 与 ForEach 展示子视图。
- [Orgenda/Features/Files/Preview/Blocks/OrgPreviewRichText.swift:9](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Blocks/OrgPreviewRichText.swift:9) — 生产入口只在存在图片片段时使用该组件；无图片走原生 Text 组合。
- [OrgendaTests/Features/Files/OrgPreviewImagePresentationTests.swift:7](/Users/roifewu/.config/orgenda/OrgendaTests/Features/Files/OrgPreviewImagePresentationTests.swift:7) — 覆盖中英文、数学公式、链接、UTF-8 偏移及图片分段；第 35 行覆盖相邻图片无空文本行。

API 依据：

- [iOS 27 SDK SwiftUICore：VStack、ForEach、Text(Image)](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUICore.framework/Modules/SwiftUICore.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对 VStack 的 alignment/spacing/content 初始化器（1314 行）、ForEach 的数据和内容闭包及 id 初始化器（21778 行起）、Text.init(Image)（9670 行）；系统布局原语已在使用，Text 图片构造仅接收 Image。

专属分析 agent：`/root/audit_group_b/c059`。

<a id="c060"></a>

### C060 · OrgPreviewImageView

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Images/OrgPreviewImageView.swift:71)　置信度：high

当前实现：Org 图片预览的业务包装：用 Button/Image 显示限高缩略图，ProgressView 表示加载，Label/Text/Button 表示错误与重试，contextMenu 重新加载，sheet 打开图片；以工作区会话、候选路径和重试次数驱动 task。

系统候选：无实质等价替代。已核对 iOS 27 AsyncImage(request:scale:transaction:content:) 和 asyncImageURLSession(_:)；ContentUnavailableView 可另做错误区样式选择，但不足以简化核心行为。

判断：此处没有自绘控件，复杂度主要是 Org 路径和工作区加载状态。iOS 27 AsyncImage 已支持 URLRequest 与自定义 URLSession，但仍没有直接接入 WorkspaceFileAccess、多候选读取、流式大小限制和缩略图解码的接口，成功阶段只给 SwiftUI Image，亦不能直接延续当前 UIImage 弹窗数据链。改用它需新增适配或重复加载；错误区换 ContentUnavailableView 仅改变紧凑行内布局，收益不足。

预期收益：保留现有原生控件组合与业务边界；替换为 AsyncImage 无可确认的复杂度下降，反而需要加载适配和 UIImage 获取路径。

必须保留：按文档位置、附件配置和工作区会话生成候选路径，工作区切换时避免展示旧图；保留 WorkspaceFileAccess 的访问控制、缺失文件候选回退、无本地图像缓存、远端字节预算和缩略图处理；离开视图或请求变化时取消任务，取消不显示错误；错误提示与 Retry/Reload 操作保留；点击已加载图片打开现有缩放弹窗，保留标签、源字节标识及 44 点重试触控高度

验证要求：已静态阅读 OrgendaUITests/UIUXPolishUITests.swift:188 testPreviewLoadsRelativeAndAttachmentImagesAndOpensZoom，覆盖相对/附件图、打开缩放与缺失图片重试；本次未运行。；已静态阅读 OrgendaTests/Services/Images/OrgPreviewImageLoaderTests.swift 的 testCloudAttachmentLookupTriesNextCandidateAfterMissingMetadata、testLocalImageReplacementIsNotHiddenByACache、testThumbnailIsBoundedAndAppliesEXIFOrientation、testRejectsBothAdvertisedAndStreamedOversizedResponses、testCancellingAnActiveDownloadStopsLoading；本次未运行。；如单独试验 ContentUnavailableView，需验证多图文档中的行内高度、长错误文字、Dynamic Type 与重试可达性；不能仅凭 API 存在判定布局等价。

代码依据：

- [Orgenda/Features/Files/Preview/Images/OrgPreviewImageView.swift:64](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Images/OrgPreviewImageView.swift:64) — OrgPreviewImageFlow 生产路径实例化该组件；92–166 行实现候选请求、原生控件状态切换、取消保护与 sheet。
- [Orgenda/Features/Files/Preview/InteractiveOrgPreview.swift:85](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/InteractiveOrgPreview.swift:85) — 注入实际 WorkspaceStore 和 documentPath，图片加载依赖预览文档的工作区上下文。
- [Orgenda/Services/Images/OrgPreviewImageLoader.swift:63](/Users/roifewu/.config/orgenda/Orgenda/Services/Images/OrgPreviewImageLoader.swift:63) — load 经 WorkspaceFileAccess 或网络读取候选；91 行起限制网络字节并处理取消，129 行起通过 ImageIO 有界缩略解码。

API 依据：

- [iOS 27 SwiftUI SDK — AsyncImage、AsyncImagePhase、asyncImageURLSession 与 ContentUnavailableView](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对 18674–18739 行：iOS 27 新增 URLRequest 初始化及 URLSession 注入；成功阶段为 SwiftUI Image，未提供 WorkspaceFileAccess 或解码闭包。22638 行起 ContentUnavailableView 提供 label/description/actions。
- [Apple — AsyncImage](https://developer.apple.com/documentation/swiftui/asyncimage)：已读取官方 Markdown：iOS 27 缓存依照传输协议，可经 URLRequest 改缓存策略，经 asyncImageURLSession 自定义 session；并非只能使用共享 session。
- [Apple — View.asyncImageURLSession(_:)](https://developer.apple.com/documentation/swiftui/view/asyncimageurlsession(_:))：已读取官方 Markdown：iOS 27 起为视图层级中的 AsyncImage 指定图片下载 data task 所用 URLSession。

专属分析 agent：`/root/audit_group_b/c060`。

<a id="c061"></a>

### C061 · OrgPreviewImageSheet

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Images/OrgPreviewImageView.swift:171)　置信度：high

当前实现：以 NavigationStack 承载 OrgZoomableImage，设置图片标题和 inline 导航标题；用 ToolbarItem、原生 close 角色 Button 与 dismiss 环境动作关闭上层 sheet。

系统候选：无需替代；现有弹窗外壳已由 SwiftUI 系统组件组成。整体图片预览可另行评估 QLPreviewController，但不是此 UIImage 入参外壳的等价替换。

判断：此类型仅组织系统导航、标题与关闭动作，没有自绘弹窗或手势逻辑；缩放由独立子组件负责。iOS 27 SDK 已支持其使用的 close 角色与 dismiss。Quick Look 的预览协议要求文件 URL，而当前调用传入已加载 UIImage；替换须改变数据契约并验证交互，不能仅为删除这个短封装而增加适配层。

预期收益：保留此短封装；当前没有可移除的自定义弹窗实现，内联只会搬移代码，Quick Look 适配也未证明能降低整体复杂度。

必须保留：已加载 UIImage 与 Org 图片标签直接传入；显示图片标题并将同一标签交给图片无障碍内容；关闭按钮退出当前 sheet，返回原图片位置；保留 org.preview.image.close 测试标识及子组件缩放交互

验证要求：OrgendaUITests/UIUXPolishUITests.swift:188 — testPreviewLoadsRelativeAndAttachmentImagesAndOpensZoom 覆盖图片弹窗打开、图片标签、捏合后宽度增加、关闭后回到预览，以及标题图片打开/关闭。；本次仅静态检查，未运行测试；若整体改为 Quick Look，需原型验证从 UIImage 转文件的生命周期、图片标题及无障碍标签、缩放和关闭后返回行为。

代码依据：

- [Orgenda/Features/Files/Preview/Images/OrgPreviewImageView.swift:165](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Images/OrgPreviewImageView.swift:165) — .sheet(item:) 的生产调用传入 presentation.image 与 reference.label。
- [Orgenda/Features/Files/Preview/Images/OrgPreviewImageView.swift:171](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Images/OrgPreviewImageView.swift:171) — 组件主体仅组合 NavigationStack、标题、ToolbarItem 与 Button(role: .close)，通过环境 dismiss 关闭。
- [OrgendaUITests/UIUXPolishUITests.swift:188](/Users/roifewu/.config/orgenda/OrgendaUITests/UIUXPolishUITests.swift:188) — 图片预览 UI 测试明确使用 zoom 和 close 标识验证打开、缩放、关闭及返回。

API 依据：

- [iOS 27 SDK — SwiftUI NavigationStack、DismissAction、ButtonRole.close、sheet(item:)](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对 NavigationStack 声明（19183）、dismiss（1680）、sheet(item:)（9143）及 close 角色（11770，iOS 26 起可用）；目标 iOS 27 均支持。
- [iOS 27 SDK — QLPreviewItem](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/QuickLook.framework/Headers/QLPreviewItem.h)：已核对 previewItemURL 必须是文件 URL，previewItemTitle 是可选标题；不是直接接收 UIImage 的系统弹窗。
- [iOS 27 SDK — QLPreviewController](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/QuickLook.framework/Headers/QLPreviewController.h)：已核对预览控制器以 QLPreviewControllerDataSource 返回 QLPreviewItem；替换会引入控制器和数据源适配。

专属分析 agent：`/root/audit_group_b/c061`。

<a id="c062"></a>

### C062 · OrgZoomableImage

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Images/OrgPreviewImageView.swift:192)　置信度：high

当前实现：将已加载的 UIImage 和标签桥接到原生 UIScrollView/UIImageView；仅在图片对象更换时重置缩放及尺寸，同图更新只同步无障碍标签并请求布局。

系统候选：保留 UIViewRepresentable 与 UIScrollView/UIImageView；SwiftUI Image + MagnifyGesture 需另写状态、平移与边界处理，并非可直接替代的图片查看器。

判断：这层封装已经使用 Apple 正式的 UIKit 桥接协议，职责只是创建原生视图、同步图片与无障碍标签。对象身份判断避免普通 SwiftUI 更新重置同图缩放。iOS 27 的 MagnifyGesture 仍提供手势值而非完整图片查看器；改用它需要重新实现底层视图已有的缩放和平移，没有实质简化收益。

预期收益：保留短桥接层可继续复用系统滚动和缩放机制；未发现能删除该层且保持现有行为的等价系统组件。

必须保留：同一 UIImage 实例更新不主动重置缩放；更换实例时重新设置图片尺寸与适配状态；标签始终同步到可访问的 UIImageView；继续接入底层原生捏合、平移、双击缩放及尺寸适配行为

验证要求：OrgendaUITests/UIUXPolishUITests.swift:188 testPreviewLoadsRelativeAndAttachmentImagesAndOpensZoom 验证打开查看器、图片无障碍标签以及捏合后宽度增长；本次仅阅读，未运行。；若后续更换桥接方式，需原型验证同图重复 updateUIView 不丢缩放、换图重新适配、标签独立变化仍更新；现有测试未覆盖这些桥接边界。

代码依据：

- [Orgenda/Features/Files/Preview/Images/OrgPreviewImageView.swift:178](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Images/OrgPreviewImageView.swift:178) — 图片 sheet 的 NavigationStack 实际调用 OrgZoomableImage(image:label:)。
- [Orgenda/Features/Files/Preview/Images/OrgPreviewImageView.swift:192](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Images/OrgPreviewImageView.swift:192) — UIViewRepresentable 创建 ImageScrollView，198–208 行按 UIImage 身份决定重置并同步可访问性。
- [OrgendaUITests/UIUXPolishUITests.swift:188](/Users/roifewu/.config/orgenda/OrgendaUITests/UIUXPolishUITests.swift:188) — 现有 UI 测试通过 org.preview.image.zoom 定位原生滚动视图，并断言捏合后图片宽度增加。

API 依据：

- [UIViewRepresentable | Apple Developer Documentation](https://developer.apple.com/documentation/swiftui/uiviewrepresentable?changes=_7)：Apple 将该协议定义为向 SwiftUI 集成、创建和更新 UIKit UIView 的正式桥接机制。
- [iOS 27 SDK SwiftUI.swiftinterface — UIViewRepresentable / MagnifyGesture / ScrollView](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：核对 28806 行 makeUIView/updateUIView；12094 行 MagnifyGesture 的缩放值和起点，27.0 新增 inputKinds 初始化参数仍是手势；18995 行 ScrollView 声明。
- [iOS 27 SDK UIScrollView.h — native zoom API](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/UIKit.framework/Headers/UIScrollView.h)：243–247 行提供 minimumZoomScale、maximumZoomScale、setZoomScale；331 行 viewForZooming 委托指定被缩放的原生子视图。

专属分析 agent：`/root/audit_group_b/c062`。

<a id="c063"></a>

### C063 · OrgZoomableImage.ImageScrollView

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Images/OrgPreviewImageView.swift:211)　置信度：high

当前实现：UIScrollView 子类承载 UIImageView，利用系统缩放代理实现捏合和平移；补充适应视口的缩放范围、居中 inset、双击切换缩放与减少动态效果设置。

系统候选：UIScrollView + UIImageView 已是适合的系统实现；SwiftUI MagnifyGesture 仅提供手势值，不是具备缩放、滚动和居中策略的图片浏览控件。

判断：当前直接使用系统滚动与缩放机制，自定义部分只负责图片适配、居中和双击策略。iOS 27 SDK 的 MagnifyGesture（含新增输入类型参数）仍是手势输入，不能直接接管内容尺寸、边界和平移。改为 SwiftUI 手势组合会重新实现这些行为，未发现能删除此封装且保持现有体验的等价控件。

预期收益：保留短小的原生控件封装；没有已证实能减少复杂度的系统替换。

必须保留：首次布局及视口尺寸变化时按 min(宽比, 高比, 1) 适配，避免初始放大小图。；最大缩放为 max(1, 适配比例 × 5)，图片不足视口时保持双轴居中。；双击在最小缩放与最多其 2.5 倍之间切换，并尊重 Reduce Motion。；保留系统捏合、平移、图片无障碍标签以及 org.preview.image.zoom 标识。

验证要求：OrgendaUITests/UIUXPolishUITests.swift:188 testPreviewLoadsRelativeAndAttachmentImagesAndOpensZoom 已断言打开浏览器、图片标签和捏合后宽度增大；本次仅阅读，未运行。；如后续改动，需交互核对横竖屏或分屏尺寸变化后的重新适配、极端宽高比图片居中、缩放边界和平移、连续双击及 Reduce Motion；现有测试没有覆盖这些行为。

代码依据：

- [Orgenda/Features/Files/Preview/Images/OrgPreviewImageView.swift:196](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Images/OrgPreviewImageView.swift:196) — UIViewRepresentable 实际创建此类，更新图片后重置 fittedSize，并设置图片无障碍标签。
- [Orgenda/Features/Files/Preview/Images/OrgPreviewImageView.swift:211](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Images/OrgPreviewImageView.swift:211) — UIScrollView/UIImageView、布局适配、缩放代理、居中及双击策略均在此类型内。
- [OrgendaUITests/UIUXPolishUITests.swift:188](/Users/roifewu/.config/orgenda/OrgendaUITests/UIUXPolishUITests.swift:188) — 图片预览 UI 测试找到原生 scrollView，并断言捏合使图片显示宽度增加。

API 依据：

- [iOS 27 UIKit UIScrollView.h](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/UIKit.framework/Headers/UIScrollView.h)：已核对 contentInset、minimumZoomScale、maximumZoomScale、setZoomScale:animated:、viewForZoomingInScrollView: 和 scrollViewDidZoom:；当前使用这些系统能力。
- [iOS 27 SwiftUI MagnifyGesture 声明](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：12094–12138 行声明 magnification、velocity、startAnchor、startLocation，以及 iOS 27 inputKinds 初始化参数；这是 Gesture，未提供图片滚动容器或适配策略。
- [iOS 27 UIKit UIAccessibility.h](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/UIKit.framework/Headers/UIAccessibility.h)：566 行确认 UIAccessibilityIsReduceMotionEnabled 系统设置查询，当前双击动画已采用。

专属分析 agent：`/root/audit_group_b/c063`。

<a id="c064"></a>

### C064 · InteractiveOrgPreview

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/InteractiveOrgPreview.swift:5)　置信度：high

当前实现：以 ScrollViewReader、ScrollView、ScrollPosition、sheet、alert 和 ContentUnavailableView 组合 Org 交互预览，协调语法树渲染、精确源码编辑、折叠连续性、标题移动及模式切换阅读位置。

系统候选：无可实质替代整个组件的系统控件；现有滚动、弹层、反馈和空态已原生。OutlineGroup 只能提供树形展示，不能接管 Org 源码交互协调。

判断：当前职责主要是连接解析文档与原生视图：修改按 UTF-8 范围校验并回滚乐观状态，重解析后映射折叠标题身份，拖动前验证源码快照，切换编辑模式保留阅读位置。SDK 的 OutlineGroup 接收树形数据及内容构造闭包，不提供这些 Org 语义；改用它仍须保留协调层并重接混合内容。未发现能删除实质自定义实现且保持行为的系统替代。

预期收益：保留可维持原生滚动与呈现；换成通用树或文本控件没有确定的复杂度收益，领域状态与保护逻辑仍不可省略。

必须保留：TODO、复选框、日期修改的精确源码范围及失败回滚、撤销同步；配置工作流要求备注时进入条目编辑器，规划写入遵循工作区或 Emacs 配置；标题子树移动、陈旧源码拒绝、移动后折叠身份与目标祖先展开；跨模式保留阅读偏移，定位标题先展开祖先再滚动；减少动态效果、辅助字号弹层高度、原生触感及不可用内容提示

验证要求：OrgendaUITests/MotionFlowUITests.swift:497 — testDocumentModesPreserveCollapseAndShareUndo 覆盖折叠、TODO 与跨模式撤销。；OrgendaUITests/MotionFlowUITests.swift:622、677 — testPreviewDragOntoHeadingNestsReparentsAndOutdentsWholeSubtree、testCancelledPreviewHeadingDragDoesNotChangeSource 覆盖子树移动与取消。；OrgendaUITests/MotionFlowUITests.swift:784 — testDocumentModeSwitchPreservesPreviewScrollPosition 要求切回预览时标题位置误差不超过 2 点。；OrgendaTests/Domain/Org/OrgHeadingMoveTests.swift:239 — testHeadingContinuityPreservesSelectionsAcrossOutlineReparenting 验证重挂接后的身份映射。；仅阅读当前源码与现有测试，未运行；任何滚动 API 统一原型需补验折叠后定位时序、LazyVStack 未实现行定位及跨模式偏移恢复。

代码依据：

- [Orgenda/Features/Files/Preview/InteractiveOrgPreview.swift:48](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/InteractiveOrgPreview.swift:48) — 原生滚动及展示组合，onChange 同步文档、折叠和乐观替换；150 起实现拖动快照与标题定位，287 起源码替换回滚。
- [Orgenda/Features/Files/Document/OrgDocumentView.swift:28](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Document/OrgDocumentView.swift:28) — 生产调用持续保留预览实例，以 isActive、opacity 与命中测试切换编辑模式。
- [Orgenda/Services/Workspace/WorkspaceStore+Editing.swift:318](/Users/roifewu/.config/orgenda/Orgenda/Services/Workspace/WorkspaceStore+Editing.swift:318) — applySourceReplacement 逐字节比较 expectedText 后才更新文档并刷新索引。

API 依据：

- [iOS 27 SDK — SwiftUI OutlineGroup、ScrollViewReader 与滚动定位声明](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对 4151 起 OutlineGroup 的 children KeyPath 与内容闭包、24907 起 ScrollViewReader/ScrollViewProxy.scrollTo、17538 onScrollGeometryChange 及 28951 scrollPosition；现用 API 均覆盖 iOS 27 目标，通用树 API 不承担 Org 字节编辑与工作流。

专属分析 agent：`/root/audit_group_b/c064`。

<a id="c065"></a>

### C065 · OrgPlanningEditorSheet

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/OrgPlanningEditorSheet.swift:3)　置信度：high

当前实现：以 NavigationStack、Form、Section、Picker、ToolbarItem、Button 和 alert 组合 Org 计划/时间戳编辑表单；维护独立草稿、修改判定、保存失败状态与弃改保护，并嵌入时间戳编辑子组件。

系统候选：无实质替代；系统 Form、Picker、alert 与 interactiveDismissDisabled 已使用。

判断：当前声明没有自绘表单或自制导航控件，类型选择已按辅助功能字号切换系统菜单/分段样式。其余代码承载 Org 草稿、重复规则有效性、源文档变更后保存失败和未保存退出保护；原生日期选择器不能包办这些应用语义，保留此封装可维持提交边界，未发现能等价删除它的单一系统编辑器。

预期收益：不建议替换；目前已复用原生表单和呈现能力，进一步移除封装只会把状态及保存保护分散到调用方，缺少复杂度收益。

必须保留：普通时间戳隐藏计划类型；时间戳范围分别编辑起点与终点；保存前校验每个重复规则；onSave 返回失败时保留草稿并显示错误；已修改草稿禁用手势关闭，取消需确认弃改；辅助功能字号下使用菜单式计划类型选择；通过原有草稿模型保留提醒偏移、时间范围与 Org 源文本语义

验证要求：OrgendaUITests/MotionFlowUITests.swift:1200 testPlanningPreviewEditsTypeAndDateBackToOrgSource 已覆盖打开表单、切换计划类型、修改日期和保存回源文档。；OrgendaUITests/MotionFlowUITests.swift:1254 testPlanningPreviewAddsYearlyRecurrence 已覆盖表单添加重复规则并保存。；OrgendaTests/Domain/Org/OrgSourceMutationTests.swift:160 testRecurrenceEditingPreservesWarningTimeRangeAndWhitespace 覆盖草稿改规则时保留提醒、时间范围及空白。；本次仅静态审查，未运行测试；如将来改动容器，需验证辅助功能字号、修改后交互关闭、取消弃改及源文档冲突时继续编辑。

代码依据：

- [Orgenda/Features/Files/Preview/OrgPlanningEditorSheet.swift:22](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/OrgPlanningEditorSheet.swift:22) — 原生表单/类型 Picker；第58–87行集中处理取消、保存、错误和未保存关闭保护。
- [Orgenda/Features/Files/Preview/InteractiveOrgPreview.swift:104](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/InteractiveOrgPreview.swift:104) — 生产调用通过 sheet 呈现，注入 updatePlanning，按字号及重复规则选择系统 detents。
- [Orgenda/Services/Workspace/WorkspaceStore+Editing.swift:280](/Users/roifewu/.config/orgenda/Orgenda/Services/Workspace/WorkspaceStore+Editing.swift:280) — applyPlanningDraft 校验节点源字节未变化，失败返回 false，成功路径保留工作流日志语义。

API 依据：

- [iOS 27 SDK SwiftUI Form、MenuPickerStyle、SegmentedPickerStyle、NavigationStack 与 interactiveDismissDisabled 声明](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对 Form:17167、SegmentedPickerStyle:16201、NavigationStack:19183、MenuPickerStyle:30536 和 interactiveDismissDisabled:30151；现有原生容器、选择器样式及退出保护 API 均在目标 SDK 中，Form 自 iOS 13、菜单样式自 iOS 14、交互关闭禁用自 iOS 15 可用。

专属分析 agent：`/root/audit_group_b/c065`。

<a id="c066"></a>

### C066 · OrgPlanningTimestampEditor

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/OrgPlanningEditorSheet.swift:104)　置信度：high

当前实现：在原生 Section 中组合两个 compact DatePicker、Include time Toggle、前后一天 Button 与 OrgRecurrenceEditor；绑定单个 Org 时间戳草稿，首次从午夜启用时间时设为 09:00，并适配辅助功能字号。

系统候选：日期和时间已使用 SwiftUI DatePicker，无实质系统替代。Stepper(onIncrement:onDecrement:) 可承载前后一天动作，但仅改变现有原生双按钮的呈现，仍需保留 Calendar 日运算及业务绑定。

判断：当前没有自绘日期或时间选择器，两个 DatePicker 分别编辑同一 Date 的日期和时分。独立 includesTime、午夜启用时默认九点、逐日快捷操作及 Org 重复规则属于业务配置，合并为一个日期时间控件不能消除这些责任。Stepper 虽能承载增减动作，却不能替代整段编辑器，也不能由声明证明保持现有左右按钮语义和布局；保留这个短原生组合最合理。

预期收益：没有值得替换的自定义控件实现；保留封装可让起止时间戳复用相同原生编辑配置。更换样式或改为 Stepper 的收益仅限少量布局代码，不能消除业务逻辑。

必须保留：日期与时分共享 timestamp.date，时间是否写入 Org 由独立 includesTime 控制。；从未包含时间切换为包含时间时，仅将午夜默认改为 09:00，保留已有非午夜时间。；前后一天通过 Calendar 的 day 分量计算，保留直接逐日调整入口与可访问名称。；Start/End 独立绑定与标识、辅助功能字号下的纵向时间标签布局。；重复规则保持 Org 语义，序列化继续保留提醒偏移、时间范围和源文本格式。

验证要求：OrgendaUITests/MotionFlowUITests.swift:1199 — testPlanningPreviewEditsTypeAndDateBackToOrgSource 覆盖 nextDay 操作及写回日期。；OrgendaTests/Domain/Org/OrgSourceMutationTests.swift:260 — testPlanningTimeCanBeAddedAndRemovedWithoutTouchingRepeater 覆盖时间开关与重复规则保存。；OrgendaTests/Domain/Org/OrgSourceMutationTests.swift:160、233 — testRecurrenceEditingPreservesWarningTimeRangeAndWhitespace、testPlanningRangePreservesEachTimestampDelimiterWhenMarkedClosed 覆盖后缀及范围持久化。；静态审查未运行测试；若调整控件，需原型验证辅助功能字号、VoiceOver、跨夏令时逐日调整，以及午夜开关默认九点与非午夜时间保留。

代码依据：

- [Orgenda/Features/Files/Preview/OrgPlanningEditorSheet.swift:35](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/OrgPlanningEditorSheet.swift:35) — 对 draft.timestamps 的每个元素创建编辑器，范围使用 Start/End 标题与各自 Binding。
- [Orgenda/Features/Files/Preview/OrgPlanningEditorSheet.swift:112](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/OrgPlanningEditorSheet.swift:112) — Section、原生 DatePicker/Toggle/Button 组合；onChange 控制九点默认值，辅助功能字号改变时间布局，逐日按钮调用 Calendar。
- [Orgenda/Domain/Org/Planning/OrgPlanningDrafts.swift:224](/Users/roifewu/.config/orgenda/Orgenda/Domain/Org/Planning/OrgPlanningDrafts.swift:224) — timestampSource 根据 includesTime 写出时分，并在关闭时间时移除同日时间范围，其他 Org 后缀由草稿保留。

API 依据：

- [iOS 27 SDK — SwiftUI DatePicker、DatePickerComponents 与 CompactDatePickerStyle](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：25374–25445 声明 Date Binding、displayedComponents 及 date/hourAndMinute；25691 起确认 compact 是可用于 iOS 的原生日期选择器样式。
- [iOS 27 SDK — SwiftUI Stepper 回调构造器](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：26354–26372 确认 onIncrement/onDecrement 构造器可用于 iOS；其 API 接受动作但不包含 Org 语义，也不保证当前双按钮布局。
- [iOS 27 SDK — Foundation Calendar 日期运算](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/Foundation.framework/Modules/Foundation.swiftmodule/arm64e-apple-ios.swiftinterface)：2056 确认按 Calendar.Component 加减日期，2135 确认 bySettingHour 设置时分并返回可选 Date；现有业务逻辑已采用系统日历 API。

专属分析 agent：`/root/audit_group_b/c066`。

<a id="c067"></a>

### C067 · OrgPreviewContent

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/OrgPreviewContent.swift:8)　置信度：high

当前实现：用 LazyVStack、ForEach、原生形状和 accessibilityActions 组合 Org 文档预览；按祖先折叠状态筛选扁平行，转发编辑操作，并显示整段标题子树拖放反馈。

系统候选：无可直接替代的整体组件。OutlineGroup、DisclosureGroup 可表达普通树形折叠；List + onMove 可表达索引重排，但不是现有行为的等价替换。

判断：布局已使用系统惰性容器。OutlineGroup 接收 children 树，却未提供外部展开 ID 集合；改用递归 DisclosureGroup 仍须保留 Org 行树转换、折叠连续性及滚动 ID。onMove 只给索引与目标位置，不能直接表达 before/after/child 与整子树移动。替换会迁移业务代码，未发现实质可删除的自绘控件。

预期收益：保留现有组合最有利；换为树形控件会新增数据适配和状态映射，没有已证实的复杂度收益。

必须保留：折叠隐藏全部后代而保留标题，支持程序展开祖先和按行 ID 定位；异构 Org 内容的展示顺序、实际标题级别缩进与行间距；整子树淡化、before/after/child 放置指示及排除拖动子树的目标尾部定位；同级上下移动、缩进和反缩进的无障碍操作；待写回内容与编辑回调继续关联原始 ParsedOrgNode

验证要求：OrgendaUITests/MotionFlowUITests.swift:497 — testDocumentModesPreserveCollapseAndShareUndo 覆盖折叠状态、模式切换和撤销；本次仅阅读，未运行。；OrgendaUITests/MotionFlowUITests.swift:622 — testPreviewDragOntoHeadingNestsReparentsAndOutdentsWholeSubtree 覆盖折叠子树嵌套、重新归属和反缩进；本次未运行。；OrgendaTests/Domain/Org/OrgSourceMutationTests.swift:722 — testBodyAlignmentUsesActualParentLevelIncludingSkippedLevels 验证跳级标题下正文对齐；本次未运行。；若日后尝试树形控件，需原型验证滚动定位、外部展开集合恢复、跨父级整子树放置及 VoiceOver 四种移动动作；不能由 SDK 声明推定交互等价。

代码依据：

- [Orgenda/Features/Files/Preview/OrgPreviewContent.swift:24](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/OrgPreviewContent.swift:24) — 过滤祖先折叠状态，LazyVStack/ForEach 承载行，按目标子树末尾绘制放置线，并提供无障碍移动动作。
- [Orgenda/Features/Files/Preview/InteractiveOrgPreview.swift:52](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/InteractiveOrgPreview.swift:52) — 生产调用传入折叠、乐观替换和拖放状态；114、165、183 行分别负责折叠连续性、源文件移动及展开后定位。
- [Orgenda/Features/Files/Preview/OrgPreviewOutline.swift:11](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/OrgPreviewOutline.swift:11) — 缩进依实际标题级别计算；35 行将解析节点组织为保留祖先关系的扁平展示行。

API 依据：

- [iOS 27 SDK — OutlineGroup、DisclosureGroup 与 DynamicViewContent.onMove](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对 4162 起 OutlineGroup 的 children 初始化器，无展开 ID 集合参数；18041 起 DisclosureGroup 提供 Binding<Bool>；13692 的 onMove 回调为 IndexSet、Int，未提供 Org 层级放置语义。均可用于 iOS 27。
- [iOS 27 SDK — LazyVStack](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUICore.framework/Modules/SwiftUICore.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对 10748 起 LazyVStack 的 alignment、spacing、pinnedViews 和 content 系统初始化器；现有容器正使用该原生组件。

专属分析 agent：`/root/audit_group_b/c067`。

<a id="c068"></a>

### C068 · OrgPreviewRowView

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/OrgPreviewContent.swift:124)　置信度：high

当前实现：以 @ViewBuilder 按 Org 节点类型分派到预览视图，传递待写回覆盖值及编辑回调；横线和兜底文本使用 Divider、Text。customBlock 以 VStack、ForEach、Text 和系统填充背景递归呈现子行。

系统候选：无可等价替换整体的系统组件；GroupBox(content:label:) 可表达 customBlock 的标题与容器外观，但只是可选样式调整。

判断：此层的工作是把 Org 语法节点映射到不同交互视图，并按原节点 ID 传递待写回状态；系统容器不会替代这些业务分派。自定义块也已使用系统布局，改用 GroupBox 仍须保留子节点预处理、递归及回调，且默认留白和外观未证明等价，因此没有实质替换收益。

预期收益：保留集中分派可避免在调用处重复节点判断；换用 GroupBox 仅可能减少少量外观修饰，不能减少主要逻辑。

必须保留：标题折叠、编辑、TODO 更新与拖动回调的逐节点传递；待写回 TODO、checkbox 与 planning 状态按原节点 ID 显示；自定义块内递归、公式分组、空行过滤、子行间距和可访问性容器标识；未知节点与不可解析数学块的可选取文本回退

验证要求：OrgendaUITests/UIUXPolishUITests.swift:127 — testCustomBlockPreviewPreservesContentAndCheckboxEditing 覆盖嵌套块显示与勾选后源文本写回；本次仅读取，未运行。；OrgendaTests/Features/Files/OrgPreviewCustomBlockTests.swift:121 — testInteractiveContentRetainsOriginalNodeIDsAndByteRanges 覆盖块内 checkbox、link、planning 的身份与源范围。；若另行采用 GroupBox，需原型比较嵌套块留白、长标题换行、文本选取及 VoiceOver 子元素顺序；现有源码与 SDK 声明不足以证明外观等价。

代码依据：

- [Orgenda/Features/Files/Preview/OrgPreviewContent.swift:40](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/OrgPreviewContent.swift:40) — OrgPreviewContent 实际为每个可见行创建此组件，传入编辑和拖动回调。
- [Orgenda/Features/Files/Preview/OrgPreviewContent.swift:141](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/OrgPreviewContent.swift:141) — switch 分派各类 Org 节点，TODO/checkbox 使用原子节点 ID 查找 pendingReplacements。
- [Orgenda/Features/Files/Preview/OrgPreviewContent.swift:215](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/OrgPreviewContent.swift:215) — customBlock 预处理子行后递归使用自身，保留系统布局、文本选取和可访问性容器。

API 依据：

- [iOS 27 SDK — SwiftUI GroupBox(content:label:)](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：15948–16016 行确认 iOS 14 起提供标签与内容构造器；API 提供分组容器，不承担 Org 节点分派和源文本交互。
- [iOS 27 SDK — SwiftUICore ViewBuilder 与 VStack](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUICore.framework/Modules/SwiftUICore.swiftmodule/arm64e-apple-ios.swiftinterface)：1311 行起的 VStack 与 5557 行起的 ViewBuilder 声明确认现有布局及条件组合属于系统能力，保留的代码是业务映射。

专属分析 agent：`/root/audit_group_b/c068`。

<a id="c069"></a>

### C069 · OrgPreviewDrawer

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/OrgPreviewDrawer.swift:3)　置信度：high

当前实现：以系统 DisclosureGroup 展示默认收起的 Org drawer/property_drawer，Text 标题去除冒号；展开后交给只读内容组件，附加主题样式及按字节位置生成的辅助功能标识。

系统候选：已采用 SwiftUI.DisclosureGroup；无需另换系统控件。无外部控制需求时可考虑其内部管理展开状态的初始化器，但不是实质组件替代。

判断：当前折叠、展开及标签呈现已经使用系统 DisclosureGroup，独立状态仅驱动其标准绑定。剩余逻辑负责 Org 抽屉名清理、只读内容分派和定位标识，系统控件不会替代这些语义。改为内联或其他容器不消除业务逻辑，保留薄封装最清晰。

预期收益：无实质替代收益；若选用无绑定 DisclosureGroup 初始化器，仅可省去私有展开状态及绑定。

必须保留：默认收起且可重复展开、收起；保留 drawer/property_drawer 标题、定制名称和缺失名称回退；抽屉历史只读，过滤结构分隔节点且不修改源文本；org.preview.drawer.<startByte> 辅助功能标识

验证要求：OrgendaUITests/MotionFlowUITests.swift:799 testOrgMarkupPreviewAndEditorPreserveSource：已有 LOGBOOK 展开、收起、再次展开和切回编辑后源码不变断言；本次仅静态核对，未运行。；若简化状态管理，应复用上述 UI 用例确认初始收起及内容重现行为。

代码依据：

- [Orgenda/Features/Files/Preview/OrgPreviewDrawer.swift:3](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/OrgPreviewDrawer.swift:3) — 原生 DisclosureGroup、私有状态、标题清理及样式组成薄封装。
- [Orgenda/Features/Files/Preview/OrgPreviewContent.swift:197](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/OrgPreviewContent.swift:197) — property_drawer 和 drawer 的实际生产渲染入口。
- [OrgendaUITests/MotionFlowUITests.swift:838](/Users/roifewu/.config/orgenda/OrgendaUITests/MotionFlowUITests.swift:838) — LOGBOOK 反复折叠后时长内容出现/消失断言。

API 依据：

- [SwiftUI.DisclosureGroup SDK 声明](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：第 18037–18058 行：iOS 14+ 提供带 Binding<Bool> 与不带展开绑定的 content/label 初始化器；当前 iOS 27 SDK 已包含。

专属分析 agent：`/root/audit_group_b/c069`。

<a id="c070"></a>

### C070 · OrgPreviewClock

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/OrgPreviewDrawer.swift:32)　置信度：high

当前实现：用原生 HStack、VStack、Image、Text 和 Spacer 展示 Org CLOCK 日志：左侧图标与运行状态、可选本地化时间区间，右侧记录时长；支持文本选择和合并无障碍朗读。

系统候选：无实质等价替换。Label 与 LabeledContent 可表达图文和标签值关系，但仍需现有布局及 OrgPreviewClockValue；Text 的日期区间或 timerInterval 初始化器不能接管 Org 日志语义。

判断：当前没有自绘控件，主要复杂度来自 Org CLOCK 的解析及时间呈现。记录时长取自源码的 clock_duration，而非起止时间相减；缺少时长时显示 Running。换成 Label/LabeledContent 仍需双行标题、尾部时长和样式，收益很小；系统计时文本也不能替代既有日志状态及同日合并、当年省略年份规则。

预期收益：保留短小原生组合，无需新增桥接或样式抽象；仅改用 Label/LabeledContent 无明显复杂度收益。

必须保留：源码记录时长与 Running 状态，不改为实时推算；同日时间区间去重、跨日区间及本地化日期规则；独立尾部时长、等宽数字和时间区间换行；文本选择、合并无障碍元素和基于 startByte 的标识

验证要求：OrgendaTests/Components/Editor/OrgSyntaxTextEditorTests.swift:554 — testClockPresentationSupportsRunningAndCompletedEntries 覆盖完成/运行/仅时长条目、同日合并及省略当年年份；本次仅静态阅读，未运行。；若未来更换布局，应实机验证窄宽度及大字号下区间换行、尾部时长和 VoiceOver 合并朗读；现有测试不证明这些交互。

代码依据：

- [Orgenda/Features/Files/Preview/OrgPreviewDrawer.swift:32](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/OrgPreviewDrawer.swift:32) — 原生布局及文本选择、无障碍配置；:79 在抽屉只读内容中调用。
- [Orgenda/Features/Files/Preview/OrgPreviewContent.swift:174](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/OrgPreviewContent.swift:174) — 顶层 clock 行实际调用该组件。
- [Orgenda/Features/Files/Preview/Markup/OrgPreviewClockValue.swift:8](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Markup/OrgPreviewClockValue.swift:8) — 从 clock_duration 解析分钟；:24 的 interval 保留 Org 日期区间规则。

API 依据：

- [iOS 27 SDK SwiftUI.Label / LabeledContent](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：核对 30896 行 Label(title:icon:) 与 5017 行 LabeledContent(content:label:)；均支持原生组合，但不提供 Org 日志数据解析。
- [iOS 27 SDK SwiftUICore.Text 日期与计时初始化器](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUICore.framework/Modules/SwiftUICore.swiftmodule/arm64e-apple-ios.swiftinterface)：核对 9688–9703 行 DateStyle.timer、DateInterval 与 timerInterval 初始化器；输入为日期/日期区间，不能直接保留源码 clock_duration 和 Running 分支。

专属分析 agent：`/root/audit_group_b/c070`。

<a id="c071"></a>

### C071 · OrgPreviewReadOnlyContent

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/OrgPreviewDrawer.swift:71)　置信度：high

当前实现：用 VStack、ForEach、HStack、Text、Image、Divider 组合只读 Org 节点；分派时钟、属性、表格和各类块，显示工作流变更图标与备注，并按 locale 格式化历史时间戳。

系统候选：无可直接替代的系统组件。属性名和值可表达为 LabeledContent，但仍需保留 Org 富文本、现有纵向排版及整个节点分派，不能带来实质简化。

判断：这是抽取给抽屉与动态块共用的只读业务渲染器，布局和文字已使用系统组件。核心工作是按 Org 语义选择子视图、解析状态变更并保留备注，避免把历史时间戳和复选框变成编辑控件。LabeledContent 只能包装属性一支，不能替代这些语义；改用通用列表或纯文本仍需相同分派或损失块内表现，故保留。

预期收益：保留现有轻量分派层；未发现能减少业务解析或布局复杂度的等价系统替换。

必须保留：抽屉和动态块复用相同的只读节点渲染。；状态变更保留前后状态、箭头及富文本备注；历史复选框和时间戳保持展示用途。；属性、表格、源码、引用、注释等块使用各自布局，普通文本支持选择。；历史时间戳按 locale 显示并省略当年年份，不改写 Org 源码。

验证要求：OrgendaTests/Components/Editor/OrgSyntaxTextEditorTests.swift:46 testWorkflowLogIconsPreserveTransitionAndNoteDetails 覆盖状态解析及备注保留。；OrgendaTests/Components/Editor/OrgSyntaxTextEditorTests.swift:570 testDrawerTimestampPresentationOmitsCurrentYearAndKeepsOtherYears 覆盖历史时间戳年份和时间展示。；仅完成源码与 SDK 静态核对，未运行测试；若调整容器，需原型检查长备注换行、VoiceOver 合并顺序、选择文字，以及历史时间戳和复选框没有编辑入口。

代码依据：

- [Orgenda/Features/Files/Preview/OrgPreviewDrawer.swift:71](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/OrgPreviewDrawer.swift:71) — VStack/ForEach 根据节点类型分派；列表中的历史复选框使用 Text，状态变更使用系统 HStack/Image 和只读富文本。
- [Orgenda/Features/Files/Preview/OrgPreviewDrawer.swift:9](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/OrgPreviewDrawer.swift:9) — OrgPreviewDrawer 调用该渲染器；同文件 :241 的动态块分支再次调用，证明生产复用。
- [Orgenda/Features/Files/Preview/Markup/OrgPreviewMarkup.swift:39](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Markup/OrgPreviewMarkup.swift:39) — readableDrawerFragments 按 locale 和日期生成时间戳展示片段，不改原始节点。

API 依据：

- [iOS 27 SDK — SwiftUICore.VStack](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUICore.framework/Modules/SwiftUICore.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对 :1311 的 VStack 及 alignment、spacing、ContentBuilder 初始化声明；现有容器使用原生布局。
- [iOS 27 SDK — SwiftUI.LabeledContent / View.textSelection](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对 :5030 起 LabeledContent(content:label:) 泛型接口及 :2336 textSelection；前者可容纳属性标签和值，但没有 Org 节点分派或工作流日志语义。

专属分析 agent：`/root/audit_group_b/c071`。

<a id="c072"></a>

### C072 · OrgPreviewComment

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/OrgPreviewDrawer.swift:218)　置信度：high

当前实现：以系统 DisclosureGroup 折叠显示 Org 单行或块注释；系统 Label 提供标题和图标，Text 呈现可选择的斜体次要色正文，并保留标题最小 44 点高度。

系统候选：现有 SwiftUI DisclosureGroup、Label、Text 已是相应系统组件；无进一步实质替代。

判断：该组件没有自绘展开控件或手势，展开状态交给 DisclosureGroup 管理。剩余逻辑只把两类 Org 注释节点映射成字面文本，并统一显示样式；主预览及抽屉内容均复用它。改成标题字符串重载会丢失图标和标签高度配置，内联现有组合只会重复业务映射，不能减少控件实现。

预期收益：保留短业务包装即可；未发现可删除的自定义交互实现或有意义的复杂度收益。

必须保留：单行注释读取 comment_text，块注释去除起止标记后按字面文本显示；原生展开收起及可选择正文；Comment 本地化标题、text.bubble 图标和至少 44 点的标签高度

验证要求：OrgendaTests/Features/Files/OrgPreviewCustomBlockTests.swift:66 — testStandardBlocksRemainOpaqueEvenWhenTheyContainCustomDelimiters 覆盖 comment 标准块保持不被自定义块重组；不直接覆盖本视图。；rg 检索 OrgendaTests/Features/Files 与 OrgendaUITests 未发现 OrgPreviewComment 的专门交互测试；如后续调整组合，应验证主预览和抽屉内两类注释展开、收起及正文选择。本次仅静态审查，未构建或运行测试。

代码依据：

- [Orgenda/Features/Files/Preview/OrgPreviewDrawer.swift:218](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/OrgPreviewDrawer.swift:218) — 完整实现仅组合 DisclosureGroup、Text、Label 与系统修饰器。
- [Orgenda/Features/Files/Preview/OrgPreviewContent.swift:199](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/OrgPreviewContent.swift:199)；Orgenda/Features/Files/Preview/OrgPreviewDrawer.swift:98 — 主预览和只读抽屉都为 comment/comment_block 调用此组件。
- [Orgenda/Features/Files/Preview/Markup/OrgPreviewMarkup.swift:56](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Markup/OrgPreviewMarkup.swift:56) — literalText 通过 contents 排除块起止节点、拼接文本并仅裁掉首尾换行。

API 依据：

- [iOS 27 SDK SwiftUI.DisclosureGroup 声明](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：18036–18058 行核对无 isExpanded 参数的 content/label 初始化器与可选 Binding 初始化器，iOS 14 起可用，当前代码直接使用前者。
- [iOS 27 SDK SwiftUI.View.textSelection 声明](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：2331–2336 行核对 textSelection 为 iOS 15 起的系统 View API；目标 iOS 27 可直接使用，无需 UIKit 桥接。

专属分析 agent：`/root/audit_group_b/c072`。

<a id="c073"></a>

### C073 · OrgPreviewTextBlock

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/OrgPreviewDrawer.swift:234)　置信度：high

当前实现：按 Org 块类型路由：dynamic_block 组合 VStack 与只读内容渲染；verse/center 使用既有数学富文本流，配置系统字体、对齐、自适应高度及文字选择。

系统候选：继续使用现有 VStack、Text(AttributedString)、multilineTextAlignment 与 textSelection；未发现可整体替换此语义包装的等价系统控件。

判断：该组件是很薄的 Org 语义路由与系统布局组合，正文及抽屉均实际使用。Text(AttributedString) 可显示普通富文本，但不能独立承担块类型分派、动态块的嵌套只读内容及行内/独立公式分段；现有渲染链已使用 Text。改用单一 Text 会损失内容，改用 UIKit 桥接不会减少此层复杂度。

预期收益：没有实质性系统替代收益；保留短包装可集中块类型判断和对齐配置。dynamic 分支单子项 VStack 的精简属于一般清理，不构成系统组件替代。

必须保留：dynamic_block 内的表格、列表和其他嵌套块保持只读呈现；verse 保留缩进，center 同时保持段落和容器居中；块定界符不出现在正文中，行内及独立公式维持原顺序；正文自然增高、富文本链接及文字选择

验证要求：OrgendaTests/Features/Files/OrgPreviewContainerMathTests.swift:130 testVerseAndCenterPreserveIndentationAndSeparateDisplayExpressions 覆盖缩进与公式分段。；OrgendaTests/Features/Files/OrgPreviewContainerMathTests.swift:156 testEmptyBodyDoesNotExposeBlockDelimiters 覆盖空块不泄漏定界符。；本次仅静态审查，未运行测试；文字选择跨公式片段、center 图片宽度及 Dynamic Type 布局仍需运行态检查，现有片段测试不能证明这些交互。

代码依据：

- [Orgenda/Features/Files/Preview/OrgPreviewDrawer.swift:234](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/OrgPreviewDrawer.swift:234) — 完整组件仅进行 dynamic 与 verse/center 分派及原生布局配置；同文件:97 为抽屉内调用。
- [Orgenda/Features/Files/Preview/OrgPreviewContent.swift:170](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/OrgPreviewContent.swift:170) — 正文对 verse_block、center_block、dynamic_block 使用该组件。
- [Orgenda/Features/Files/Preview/Markup/OrgPreviewContainerMath.swift:11](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Markup/OrgPreviewContainerMath.swift:11) — 从正文 UTF-8 范围生成片段并剔除块定界符；:25 将独立公式与行内内容分组。

API 依据：

- [iOS 27 SDK SwiftUICore: VStack、Text(AttributedString)、multilineTextAlignment](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUICore.framework/Modules/SwiftUICore.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对:1311 VStack 原生布局、:9832 AttributedString 文本初始化、:10895 多行对齐；这些是当前组合的基础，未提供 Org AST 分派行为。
- [iOS 27 SDK SwiftUI: View.textSelection(_:)](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对:2332–2336，textSelection 自 iOS 15 可用；当前组件已经启用系统文字选择。

专属分析 agent：`/root/audit_group_b/c073`。

<a id="c074"></a>

### C074 · OrgPreviewHeading

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/OrgPreviewHeading.swift:3)　置信度：high

当前实现：用 HStack/VStack、Button、Image、Text、ViewThatFits 和上下文菜单中的 Picker 组合 Org 标题行；关联独立折叠、任务状态切换、富文本编辑入口、优先级/标签和标题拖动。

系统候选：不建议替换。DisclosureGroup 是折叠容器候选，但这里仅渲染标题，后代由外层扁平 LazyVStack 过滤；TODO 已使用原生 Button 与 Picker，Bool 绑定的 Toggle 不能表达完整多状态选择。

判断：现有交互已建立在系统控件上，封装保留 Org 节点、异步写入覆盖值与禁用状态。DisclosureGroup 要求提供折叠内容，而当前后代在外层按祖先集合过滤，并参与同一拖放布局；只换标题箭头不能移除这套逻辑。任务按钮同时支持快捷切换与完整状态选择，Toggle 无等价语义；无实质简化收益。

预期收益：保留当前业务封装；抽换为 DisclosureGroup 需调整外层内容结构，无法证明减少维护复杂度。

必须保留：折叠按钮、任务状态按钮、标题编辑三者独立命中，折叠跨编辑/预览模式保留；工作流多状态、待写入覆盖值和更新期间禁用，状态标题及颜色联动；标题内图片可打开预览；含图片标题不抢占普通点击和拖动手势；标题拖动使用节点身份与首行位置，保留子树移动及撤销路径；44 点折叠触区、首行对齐、动态元数据换行和无障碍标题/状态描述

验证要求：OrgendaUITests/MotionFlowUITests.swift:497 testDocumentModesPreserveCollapseAndShareUndo 覆盖折叠与 TODO 独立、跨模式折叠和撤销；本审查仅静态阅读，未执行。；OrgendaUITests/MotionFlowUITests.swift:622 testPreviewDragOntoHeadingNestsReparentsAndOutdentsWholeSubtree 及 :677 testCancelledPreviewHeadingDragDoesNotChangeSource 覆盖拖动子树、保留折叠和取消后的状态操作。；OrgendaUITests/UIUXPolishUITests.swift:188 testPreviewLoadsRelativeAndAttachmentImagesAndOpensZoom 在 :219 验证标题内图片可进入缩放。；若未来尝试 DisclosureGroup，需原型验证内嵌 TODO/图片/标题点击互不触发折叠，以及首行命中区域和拖放位置计算；静态 API 声明不能证明这些交互等价。

代码依据：

- [Orgenda/Features/Files/Preview/OrgPreviewHeading.swift:20](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/OrgPreviewHeading.swift:20) — 原生布局、富文本首行对齐、独立编辑/拖动入口及 ViewThatFits；:110 折叠 Button，:137 TODO Button + 原生 Picker。
- [Orgenda/Features/Files/Preview/OrgPreviewContent.swift:24](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/OrgPreviewContent.swift:24) — 外层按 collapsedHeadingIDs 过滤扁平行并在 LazyVStack 中处理拖放；:141 实际生产调用传入 pendingReplacements 与节点回调。
- [OrgendaUITests/MotionFlowUITests.swift:497](/Users/roifewu/.config/orgenda/OrgendaUITests/MotionFlowUITests.swift:497) — 明确断言折叠不改任务状态、任务状态不折叠标题，并覆盖跨模式保留和撤销。

API 依据：

- [iOS 27 SDK — DisclosureGroup<Label, Content>](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对 :18036–18044：iOS 14 起可用，初始化接收 isExpanded: Binding<Bool>、content 和 label；该接口是内容容器，并非替换独立箭头后即可删除外层过滤逻辑。
- [iOS 27 SDK — Toggle 与 ViewThatFits](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对 :6170–6172 的 Toggle(isOn:) 为 Binding<Bool>；:14277–14283 的 ViewThatFits(in:) 为 iOS 16 起系统 API，当前元数据自适应布局已使用。

专属分析 agent：`/root/audit_group_b/c074`。

<a id="c075"></a>

### C075 · OrgPreviewListItem

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/OrgPreviewHeading.swift:247)　置信度：high

当前实现：以原生 HStack、Text、Button 和 SF Symbols 组合 Org 列表行，接入富文本片段；解析编号及缩进，复选框支持完成划线、待保存覆盖值、更新中禁用及减少动态效果。

系统候选：保留原生 Button 组合。Toggle(isOn:label:) 可表达开关语义，但 iOS 27 SDK 的 CheckboxToggleStyle 明确不可用于 iOS；Toggle 的 .button 或 .switch 不是现有复选框布局的等价替换。

判断：当前点击已由系统 Button 承担，定制部分是 Org 标记、缩进、富文本与保存状态映射。iOS 27 SDK 明确禁止 CheckboxToggleStyle；换成 Toggle 仍需绑定源节点回调、更新锁及同样的外观代码。系统 List 也不解析 Org 编号和内容。没有能实质减少实现且保持现有行为的系统替换，保留此业务组合更合适。

预期收益：保留现有轻量包装，避免引入自定义 ToggleStyle 或 UIKit 桥接；暂无可删除的实质性自绘控件实现。

必须保留：普通项目显示 Org 列表标记或显式计数器，并保留受限源码缩进和首行基线对齐。；复选框仅由独立 44 点 Button 触发；内容继续使用 OrgPreviewRichText 的片段呈现。；已完成状态识别 [X]/[x]，显示次要色和划线；[-] 的点击交由源文本变更逻辑转为 [X]。；保留 pendingReplacements 的即时显示、更新中禁用、失败回退及源文本空白保护。；保留包含内容的无障碍动作标签、Checked/Unchecked/Updating 状态、稳定测试标识及减少动态效果分支。

验证要求：OrgendaUITests/UIUXPolishUITests.swift:127 — testCustomBlockPreviewPreservesContentAndCheckboxEditing，现有测试验证嵌套块中的按钮切换、无障碍动作标签及回写源码。；OrgendaTests/Domain/Org/OrgSourceMutationTests.swift:318 — testCheckboxToggleSupportsUncheckedCheckedAndIndeterminateTokens，现有测试覆盖三种令牌转换及空格、制表符保留。；本次仅静态读取，未运行测试；若改用 Toggle，需原型验证富文本链接/图像与独立控件的触摸区域、VoiceOver 更新状态、减少动态效果及保存失败恢复。

代码依据：

- [Orgenda/Features/Files/Preview/OrgPreviewHeading.swift:255](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/OrgPreviewHeading.swift:255) — 系统 HStack/Button/Text 组合；279 起为复选框动作、44 点目标、禁用与无障碍状态；309 起为片段、缩进和完成状态映射。
- [Orgenda/Features/Files/Preview/OrgPreviewContent.swift:155](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/OrgPreviewContent.swift:155) — list_item 的生产调用传入 pendingReplacements 覆盖值、isCheckboxUpdating 与 onToggleCheckbox。
- [Orgenda/Features/Files/Preview/InteractiveOrgPreview.swift:258](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/InteractiveOrgPreview.swift:258) — 切换通过 OrgSourceMutation.checkboxToggle 构造局部替换；286 起保存前发布覆盖值、失败恢复，随后与解析节点协调。

API 依据：

- [iOS 27 SDK — Toggle / ButtonToggleStyle / CheckboxToggleStyle](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：核对 6170 行 Toggle 接受 Binding<Bool>；1250 行起 .button 可用于 iOS 15+；15771–15813 行 .checkbox 及 CheckboxToggleStyle 均明确 @available(iOS, unavailable)。
- [iOS 27 SDK — SwiftUI Button](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：核对 29179 行 Button<Label> 与 action/label 初始化器；当前复选框交互已使用系统按钮，并非自行实现事件分发。

专属分析 agent：`/root/audit_group_b/c075`。

<a id="c076"></a>

### C076 · OrgPreviewPlanning

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/OrgPreviewPlanning.swift:3)　置信度：high

当前实现：以 VStack、ForEach 展示 planning_entry 子节点；优先解析待写回源码并交给规划条目按钮，解析失败时用可选择文本的原生 Label 回退，任一条目更新中时禁用同组可编辑条目。

系统候选：保留现有 VStack + ForEach + Label；未发现能替代 Org 数据适配和更新保护的单一系统组件。

判断：当前布局、迭代、错误回退和无障碍分组均已使用系统 API；剩余代码负责按节点身份选择待写回源码、解析 Org 规划并汇总整组更新状态。生产预览明确调用此容器，替换布局仍须保留全部语义分支，不能带来实质复杂度收益。

预期收益：无有意义的系统替代收益；保留短容器可集中维护预览回退与更新保护。

必须保留：planning_entry 原始顺序和稳定节点身份；待写回源码优先显示；同组任一条目更新时禁用所有可编辑条目；解析失败仍显示可选择的原始内容；将原节点与解析草稿传入编辑回调；无障碍子元素容器及基于 startByte 的标识

验证要求：已静态阅读 OrgendaTests/Domain/Org/OrgSourceMutationTests.swift:741 的 testPreviewPlacesPlanningBelowHeadingDrawers，覆盖规划节点在预览中的排列。；已静态阅读 OrgendaUITests/MotionFlowUITests.swift:480 的 testPlanningPreviewCanToggleRawTimestamp 与 :1200 的 testPlanningPreviewEditsTypeAndDateBackToOrgSource；未运行。；现有检索未见直接覆盖此容器的解析失败回退、同组多条目更新禁用测试；若未来重构，应验证失败文本可选择、更新期间禁止重复编辑及 VoiceOver 子元素导航。

代码依据：

- [Orgenda/Features/Files/Preview/OrgPreviewPlanning.swift:8](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/OrgPreviewPlanning.swift:8) — 原生 VStack/ForEach 承载解析分支，Label 回退提供文本选择和无障碍分组；39–44 行筛选条目并汇总待写回状态。
- [Orgenda/Features/Files/Preview/OrgPreviewContent.swift:176](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/OrgPreviewContent.swift:176) — planning 分支在生产预览中构造此容器，传递节点、待写回映射和编辑回调。
- [Orgenda/Features/Files/Preview/InteractiveOrgPreview.swift:285](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/InteractiveOrgPreview.swift:285) — replace 记录待写回源码，失败恢复旧状态；reconcilePendingReplacements 在解析结果更新后清理记录。

API 依据：

- [iOS 27 SDK SwiftUICore：VStack 与 ForEach](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUICore.framework/Modules/SwiftUICore.swiftmodule/arm64e-apple-ios.swiftinterface)：核对 1311、21778、21810 附近声明：原生垂直布局及 Identifiable 数据迭代均可用于目标系统，现有实现已采用。
- [iOS 27 SDK SwiftUI：Label、textSelection、accessibilityElement](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：核对 30896 起 Label 的 systemImage 初始化器、2336 的 textSelection、30312 的 accessibilityElement(children:) 及 contain；现有回退与分组均为系统能力。

专属分析 agent：`/root/audit_group_b/c076`。

<a id="c077"></a>

### C077 · OrgPreviewPlanningEntryControl

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/OrgPreviewPlanning.swift:48)　置信度：high

当前实现：以系统 Button、Text、Image、HStack/VStack 和 contextMenu 展示可编辑 Org 日期摘要；支持原文切换、规划类型配色、更新期间禁用及辅助功能值。

系统候选：继续使用现有 Button 与 contextMenu；DatePicker 只适合编辑器内的日期选择，不是此预览入口的等价替代。没有能实质删除该业务封装的系统组件。

判断：当前点击和长按菜单已由系统控件实现，定制部分是 Org 摘要、原文切换与更新保护。该封装同时用于规划条目和独立时间戳。DatePicker 绑定单个日期，不能代替包含类型、区间、重复与警告信息的编辑入口；改用标准 Label 也仍须保留这些业务逻辑，收益有限。

预期收益：保留现有轻量系统组合可避免引入日期绑定或 UIKit 桥接；未发现有实际复杂度收益的替换。

必须保留：点击将当前节点及草稿交给既有规划编辑流程；可读日期与精确 Org 原文切换，保留区间、重复规则及未知注记；isUpdating 禁用编辑及辅助功能 Updating 状态；规划条目与无关键字时间戳的不同标签、颜色及稳定标识；44 点点击区域、可换行摘要与装饰图标的辅助功能隐藏

验证要求：已静态检查 OrgendaUITests/MotionFlowUITests.swift:480 testPlanningPreviewCanToggleRawTimestamp，覆盖长按菜单和辅助功能值的原文往返切换。；已静态检查 OrgendaUITests/MotionFlowUITests.swift:1200 testPlanningPreviewEditsTypeAndDateBackToOrgSource、:1254 testPlanningPreviewAddsYearlyRecurrence、:1277 testPlainRecurringTimestampPreviewUsesControlsAndRemovesRule，覆盖两类入口和保存后摘要。；已静态检查 OrgendaTests/Domain/Org/OrgSourceMutationTests.swift:676 testReadableDateKeepsTimeRangeRepeatModesWarningsAndSource、:690 testReadableRangeKeepsDifferentYearsAndAllDayDates、:704 testReadableDateKeepsGregorianYearsWithNonGregorianLocale。；本次未运行测试；若后续改变布局或按钮样式，需要在 iOS 27 验证大字号换行、VoiceOver 朗读、更新期间禁止重复编辑及长按菜单行为。

代码依据：

- [Orgenda/Features/Files/Preview/OrgPreviewPlanning.swift:59](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/OrgPreviewPlanning.swift:59) — 原生 Button 承担编辑，:92 禁用更新中的条目，:93 使用系统 contextMenu，:103 设置业务辅助功能信息；同文件 :14 为规划条目生产调用。
- [Orgenda/Features/Files/Preview/Blocks/OrgPreviewParagraph.swift:14](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Blocks/OrgPreviewParagraph.swift:14) — 独立时间戳复用本控件，并传入 pendingReplacements 对应的更新状态及草稿。
- [Orgenda/Features/Files/Preview/Markup/OrgPreviewDateText.swift:27](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/Preview/Markup/OrgPreviewDateText.swift:27) — Foundation Date.FormatStyle 负责日期本地化，:50 的 details 保留重复、警告和陌生扩展语义。

API 依据：

- [iOS 27 SDK：SwiftUI.Button.init(action:label:) 与 View.contextMenu(menuItems:)](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对 29179 行 Button 的任意 View 标签和 action 初始化器，以及 12142 行系统 contextMenu 声明；当前组件正使用这些系统能力。
- [iOS 27 SDK：SwiftUI.DatePicker 与 DatePickerComponents](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对 25373 行起 DatePicker 初始化器使用 Binding<Date>，25431 行起 iOS 显示组件为 date、hourAndMinute；这些接口不承载此入口的 Org 类型、重复规则和原文切换。

专属分析 agent：`/root/audit_group_b/c077`。

<a id="c078"></a>

### C078 · WorkspaceFolderView

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/WorkspaceBrowser.swift:3)　置信度：high

当前实现：用原生 List、navigationDestination、ContentUnavailableView、refreshable 和 iOS 27 dragContainer 组合文件夹浏览页；按工作区路径计算可见子项，并支持上层导航回调或独立递归导航。

系统候选：无实质替代：列表、导航、空态和拖放容器已采用对应 SwiftUI 系统组件，保留业务封装。

判断：该视图没有自行实现列表或导航控件，主要工作是过滤工作区子项、连接行操作与文件同步，并在 Files 和搜索入口之间协调导航。显式子文件夹应独占后代，隐式目录中的文件仍须可达；拖动还需按当前路径生成带工作区身份与快照的载荷。系统控件已承担呈现与交互，再替换不能消除这些业务规则，故没有可实质精简的等价组件。

预期收益：保留短小原生组合，避免引入新的导航或文档浏览适配层；当前未发现有行为等价且能降低复杂度的替换。

必须保留：显式子文件夹不重复展示后代，隐式目录文件保持可达并排除配置文件；Files 的上层路径回调与搜索入口的本地递归导航；按路径从当前工作区解析拖动载荷，保留工作区身份和子树快照；原生行上下文菜单、移动删除入口、空态、下拉同步及辅助功能标识

验证要求：OrgendaTests/Services/Workspace/WorkspaceStoreTests.swift:137 — testFolderRowsDoNotDuplicateFilesInsideExplicitSubfolders 覆盖显式子目录去重与隐式目录文件可达。；OrgendaUITests/MotionFlowUITests.swift:104 — testFileBrowserFolderDragMovesSubtreeAndPickerMovesItBack 覆盖移动后嵌套目录导航及移回。；OrgendaUITests/MotionFlowUITests.swift:256 — testGestureEdgeBackInPreviewEditorFolderAndSettings 覆盖文件夹边缘返回；未运行测试。若未来更改导航，另需验证搜索入口递归及上下文菜单打开。

代码依据：

- [Orgenda/Features/Files/WorkspaceBrowser.swift:13](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/WorkspaceBrowser.swift:13) — 原生导航、List、空态、刷新及 dragContainer 组合；同文件第 106 行实现工作区可见子项规则。
- [Orgenda/Features/Files/FilesView.swift:218](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/FilesView.swift:218) — 显式与隐式目录均进入此组件，并通过回调追加上层导航路径。
- [Orgenda/Features/Search/SearchResultRow.swift:63](/Users/roifewu/.config/orgenda/Orgenda/Features/Search/SearchResultRow.swift:63) — 搜索结果以无回调方式进入此组件，使用其内部导航目标。

API 依据：

- [iOS 27 SDK SwiftUI View.navigationDestination(for:) / navigationDestination(item:)](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对第 1972–1979 行：基于类型与可选 Hashable 绑定的导航均是系统 API，分别自 iOS 16/17 可用。
- [iOS 27 SDK SwiftUI dragContainer 与 draggable(containerItemID:)](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对第 32080–32102 行：iOS 27 支持按容器条目身份延迟解析 Transferable 载荷，当前组件已经使用对应系统能力。

专属分析 agent：`/root/audit_group_b/c078`。

<a id="c079"></a>

### C079 · WorkspaceFileRow

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/WorkspaceBrowser.swift:63)　置信度：high

当前实现：以原生 HStack、VStack、Image 与 Text 组成文件行，显示可选文件/文件夹图标、标题及路径/文件夹说明/标题数量；合并辅助功能子元素。

系统候选：SwiftUI Label 可容纳 VStack 标题和自定义图标；没有能同时取代本行布局与 Org 标题数量逻辑的等价系统控件。

判断：当前实现没有自绘或自定义交互，生产调用将其作为 NavigationLink 标签，并传入解析索引的标题数。Label 虽支持自定义标题与图标，仍需保留双行文字、条件图标、顶部对齐和详情选择逻辑，改写收益有限；LabeledContent 的标签/值抽象也不能消除这些业务配置，因此不建议为替换名称增加样式代码。

预期收益：保留短小的原生业务视图；换成 Label 仍需近似布局与详情计算，没有实质复杂度收益。

必须保留：showsPath 优先显示完整路径；文件夹显示本地化说明，其余显示本地化标题数量。；优先使用 parsedDocuments 标题数量，缺失时保留源码按行扫描回退。；可隐藏图标、文件夹/文件配色区别、文字多行自然高度及图标顶部对齐。；装饰图标不被朗读，标题和详情合并为辅助功能元素。

验证要求：OrgendaUITests/MotionFlowUITests.swift:18 testHapticTouchFilePreviewOpenAndMove 覆盖生产文件行入口、预览和打开；本次仅阅读，未运行。；rg 搜索 OrgendaTests 与 OrgendaUITests 未发现 WorkspaceFileRow 或 headingCount 的直接断言；若以后改用 Label，需补查路径/计数显示、长标题与大字体顶部对齐及 VoiceOver 合并朗读。

代码依据：

- [Orgenda/Features/Files/WorkspaceBrowser.swift:71](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/WorkspaceBrowser.swift:71) — 原生堆栈布局、可选 SF Symbol、两段 Text 与辅助功能合并。
- [Orgenda/Features/Files/WorkspaceBrowser.swift:95](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/WorkspaceBrowser.swift:95) — detail 按路径、文件夹、索引标题数与扫描回退选择内容。
- [Orgenda/Features/Files/WorkspaceFileActions.swift:16](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/WorkspaceFileActions.swift:16) — WorkspaceBrowserRow 在 NavigationLink 中使用 WorkspaceFileRow，并传入 parsedDocuments 的 headings.count。

API 依据：

- [iOS 27 SDK SwiftUI Label 与 LabeledContent 声明](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对 30894 起 Label(title:icon:) 的任意 View 构造器（iOS 14+）、labelReservedIconWidth/labelIconToTitleSpacing（iOS 26+），以及 5016 起 LabeledContent(content:label:)（iOS 16+）；它们提供原生标签组合能力，未代管文件详情业务。30312 起声明 accessibilityElement(children:) 与 .combine。

专属分析 agent：`/root/audit_group_b/c079`。

<a id="c080"></a>

### C080 · WorkspaceDocumentContextPreview

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/WorkspaceDocumentContextPreview.swift:3)　置信度：high

当前实现：为文件行原生 contextMenu 提供只读摘要；复用 OrgContextPreview，以 Text、Label、ForEach 展示目录可见子项或文件内存内容，并限制预览大小。

系统候选：保留现有 SwiftUI contextMenu(menuItems:preview:) 内容组合；Quick Look 的 quickLookPreview / QLPreviewController 是文件 URL 预览候选，但不等价于这里的目录摘要和限长内存快照。

判断：菜单与预览呈现已由系统 contextMenu 承担，此层只配置业务内容。目录使用与浏览器一致的显隐规则，最多显示五项；文本截取已有内存内容，无文件加载或导航动作。Quick Look 需要文件 URL，不能直接表达这些摘要规则；迁移还需增加数据桥接，无实质简化收益。

预期收益：保留短小业务封装即可复用系统预览；未发现能减少自定义实现且保持行为的实质替换。

必须保留：只读展示已有 WorkspaceDocument 内容，长按预览不打开编辑器、不导航、不加载文件；沿用 visibleFolderDocuments 的配置文件排除、显式子目录归属及隐式路径可达规则；目录最多五项，超过五项显示省略号，空目录显示说明；文件内容最多 1200 个字符、10 行等宽字体；保留标题、路径及 files.contextPreview 标识

验证要求：OrgendaUITests/MotionFlowUITests.swift:18 testHapticTouchFilePreviewOpenAndMove 已断言预览包含文件正文且尚未进入文档；本次只读检查，未运行。；OrgendaUITests/MotionFlowUITests.swift:43 testHapticTouchFolderDeleteRequiresConfirmationAndCanUndo 已断言目录预览显示 Child；本次未运行。；OrgendaTests/Services/Workspace/WorkspaceStoreTests.swift:137 testFolderRowsDoNotDuplicateFilesInsideExplicitSubfolders 覆盖共用目录筛选规则；本次未运行。；若调整预览，需补查空目录、六个子项、长 Unicode 文本及大字体时的限长与可读性；当前静态检查不证明这些运行时布局表现。

代码依据：

- [Orgenda/Features/Files/WorkspaceDocumentContextPreview.swift:8](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/WorkspaceDocumentContextPreview.swift:8) — 通过原生 Text、Label、ForEach 实现目录五项和正文 1200 字符／10 行摘要。
- [Orgenda/Features/Files/WorkspaceFileActions.swift:23](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/WorkspaceFileActions.swift:23) — 生产 WorkspaceBrowserRow 在原生 contextMenu 的 preview 闭包调用此组件。
- [Orgenda/Features/Files/WorkspaceBrowser.swift:106](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/WorkspaceBrowser.swift:106) — visibleFolderDocuments 排除 configuration，并避免重复展示显式子目录拥有的后代。

API 依据：

- [iOS 27 SDK — SwiftUI View.contextMenu(menuItems:preview:)](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对第 12145–12148 行：iOS 16 起提供接受任意 View 预览内容的系统 API；当前调用正使用该形式。
- [iOS 27 SDK — Quick Look SwiftUI quickLookPreview](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/_QuickLook_SwiftUI.framework/Modules/_QuickLook_SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对第 11–17 行：iOS 14 起提供 Binding<URL?> 或 URL 集合选择接口，并非 String／目录摘要 View 接口。
- [iOS 27 SDK — QLPreviewItem.previewItemURL](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/QuickLook.framework/Headers/QLPreviewItem.h)：已核对第 19–24 行：previewItemURL 文档明确要求 file URL；不能直接替代当前内存 String 摘要。

专属分析 agent：`/root/audit_group_b/c080`。

<a id="c081"></a>

### C081 · WorkspaceBrowserRow

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/WorkspaceFileActions.swift:6)　置信度：high

当前实现：以 NavigationLink 包装文件行，组合系统 contextMenu 预览、Button、swipeActions、alert、sheet、无障碍操作及 iOS 27 容器拖拽；文件夹叠加 UIKit 放置目标与高亮。

系统候选：无可实质减少本组件的等价替代；NavigationLink、contextMenu、swipeActions、draggable(containerItemID:) 已采用。文件夹 SwiftUI dropDestination 仅是依赖桥接的原型候选，不能据 API 存在认定可直接替换。

判断：根目录与子目录列表共同使用该行，主要代码把系统交互接到工作区移动、回收站及导航语义。当前已用原生侧滑和 iOS 27 拖拽身份，无自制手势层可再删除。保留行封装可集中确认与操作入口；文件夹放置桥接虽可尝试原生 dropDestination，但 SDK 声明不足以证明它在 List 中能接收行内放置，不能按等价替代删除。

预期收益：保留可避免根目录与子目录重复配置操作；继续替换现有原生包装无明显复杂度收益。只有证实 List 行级放置等价后，才可能减少文件夹桥接依赖。

必须保留：普通点击与菜单 Open 的路径导航、子目录和 iPad 选择行为；菜单预览不打开编辑器，菜单、侧滑及无障碍入口均提供 Move/Delete；禁用全幅侧滑提交；删除先确认且经 store 进入 Recently Deleted 并支持撤销；document.path 拖拽身份、同应用移动且禁止外部复制、文件夹目标高亮；WorkspaceFileTransfer 的工作区会话、快照及子树验证，避免陈旧操作或无效目的地

验证要求：OrgendaUITests/MotionFlowUITests.swift:18 testHapticTouchFilePreviewOpenAndMove；:43 testHapticTouchFolderDeleteRequiresConfirmationAndCanUndo，覆盖预览、打开、移动、确认和撤销。；OrgendaUITests/MotionFlowUITests.swift:104 testFileBrowserFolderDragMovesSubtreeAndPickerMovesItBack；:140 testFileBrowserSwipeDeleteCancelUndoAndRecentlyDeletedRestore；:177 testFileBrowserMovePickerAndCancelledDrag。；OrgendaUITests/MotionFlowUITests.swift:362 testNativeFileSwipeCoordinatesRowsAndScrollDismissal 覆盖系统侧滑的行间互斥与滚动收起。；OrgendaTests/Services/Workspace/WorkspaceConnectionTests.swift:366 testFileGestureRejectsExternalEditAndDifferentWorkspace 验证转移快照与工作区身份保护。；若实验移除文件夹放置桥接，应在 iOS 27 的根目录/嵌套 List 验证行内放置命中、取消、高亮清除及导航手势；本次仅静态读取，未运行现有测试。

代码依据：

- [Orgenda/Features/Files/WorkspaceFileActions.swift:15](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/WorkspaceFileActions.swift:15) — NavigationLink 加 contextMenu、容器 draggable、原生 swipeActions、删除 alert 和移动 sheet；:55 保留文件夹放置桥接。
- [Orgenda/Features/Files/FilesView.swift:119](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/FilesView.swift:119)；Orgenda/Features/Files/WorkspaceBrowser.swift:30 — 根目录与子目录生产调用均由 List 承载，父级 dragContainer 按路径生成传输快照。
- [Orgenda/Services/Workspace/WorkspaceFileOperations.swift:4](/Users/roifewu/.config/orgenda/Orgenda/Services/Workspace/WorkspaceFileOperations.swift:4) — fileTransfer 捕获会话与子树快照，canMoveFile 校验工作区及目的地；:73 deleteFile 经存储回收站处理。

API 依据：

- [iOS 27 SwiftUI SDK：swipeActions 与容器拖拽](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：核对 20889 的 swipeActions(edge:allowsFullSwipe:content:)、32084 的 draggable(containerItemID:)、32114 的 dragConfiguration；后两项标记 iOS 27，当前实现已采用。19462 起的 DragConfiguration 声明支持应用内 allowMove 与应用外 allowCopy。
- [iOS 27 SwiftUI SDK：contextMenu 与 dropDestination](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：核对 12148 的 contextMenu(menuItems:preview:) 以及 2574/2581 的 View.dropDestination 重载；声明确认系统预览与放置 API 存在，不证明 List 内文件夹行级放置等价。
- [UIKit SDK：UIDropInteractionDelegate](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/UIKit.framework/Headers/UIDropInteraction.h)：核对 initWithDelegate、sessionDidUpdate 和 performDrop 的公开声明；当前文件夹依赖使用的是公开系统放置交互，并非自行仿制系统拖放控件。

专属分析 agent：`/root/audit_group_b/c081`。

<a id="c082"></a>

### C082 · WorkspaceMoveSheet

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/WorkspaceFileActions.swift:93)　置信度：high

当前实现：文件移动目标 sheet，使用 NavigationStack、List/Section、Button/Label、系统工具栏、ProgressView 与 alert；枚举工作区根目录和文件夹，禁用非法目标及移动中的交互，成功后关闭。

系统候选：核对 SwiftUI fileMover、UIDocumentPickerViewController 和 Picker；前两者执行 URL 文件移动，Picker 仅管理选中值，均无可直接减少当前实现的等价替代。

判断：fileMover 会直接移动 URL 文件，不能接管工作区快照校验、索引重映射及撤销事务；UIKit 目录 URL 仅建议初始位置，不能保证只选工作区内目标。局部目标行已经是系统按钮，换 Picker 反增选中状态与异步提交处理；进度和错误也已使用系统控件，未发现有实质收益的局部替换。

预期收益：保留现有薄业务封装；系统替代未能减少事务与状态处理，改用系统文件选择器反而增加 URL 与工作区路径映射及权限处理。

必须保留：根目录及完整相对路径目标；同父目录、自身、子孙目录及不同工作区禁选；仍经 store.moveFile 校验快照和名称冲突，保存移动期间编辑、索引身份及撤销信息；移动期间禁用列表和交互关闭；成功关闭，失败保持界面并显示错误；目标 accessibilityIdentifier 与结果触觉反馈

验证要求：OrgendaUITests/MotionFlowUITests.swift:18 testHapticTouchFilePreviewOpenAndMove；:104 testFileBrowserFolderDragMovesSubtreeAndPickerMovesItBack；:177 testFileBrowserMovePickerAndCancelledDrag 已覆盖入口、子目录、根目录、撤销流程（仅静态阅读，未执行）；OrgendaTests/Services/Workspace/WorkspaceConnectionTests.swift:338 testFileGesturesMoveDeleteRestoreAndReindexConnectedFolder；:366 testFileGestureRejectsExternalEditAndDifferentWorkspace 验证身份、撤销和陈旧数据保护（未执行）；OrgendaTests/Services/Workspace/WorkspaceStorageConcurrencyTests.swift:7 testMoveKeepsUIEditArrivingDuringRemoteAwaitAtDestination 验证移动等待期间编辑保留（未执行）；尚需运行时验证：慢速远端移动时 Cancel/下拉关闭不可用，失败警报后目标列表仍可重试；静态源码不能证明所有系统交互表现。

代码依据：

- [Orgenda/Features/Files/WorkspaceFileActions.swift:86](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/WorkspaceFileActions.swift:86) — 文件行 sheet 实际调用；:93–137 组合系统导航、目标列表、禁用、进度、警报和异步移动。
- [Orgenda/Services/Workspace/WorkspaceFileOperations.swift:9](/Users/roifewu/.config/orgenda/Orgenda/Services/Workspace/WorkspaceFileOperations.swift:9) — canMoveFile 限制工作区及目标；:18–67 在移动事务中更新索引、草稿路径与撤销信息。
- [OrgendaUITests/MotionFlowUITests.swift:177](/Users/roifewu/.config/orgenda/OrgendaUITests/MotionFlowUITests.swift:177) — 滑动打开移动面板，选择 projects/child，随后撤销并验证文件内容可访问。

API 依据：

- [Apple SwiftUI fileMover(isPresented:file:onCompletion:)](https://developer.apple.com/documentation/swiftui/view/filemover%28ispresented%3Afile%3Aoncompletion%3A%29)：核对其职责为系统对话框移动现有 URL 文件，完成回调返回安全作用域 URL；不是只返回业务目标供应用执行事务的控件。
- [iOS 27 SDK UIDocumentPickerViewController.h](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/UIKit.framework/Headers/UIDocumentPickerViewController.h)：第 58–63 行导出初始化器可直接移动原文件；第 72–73 行说明 directoryURL 仅尝试显示该 URL，并非限定目录范围。
- [iOS 27 SDK SwiftUI.swiftinterface](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：第 18128–18165 行 Picker 依赖 SelectionValue 绑定；第 28758–28773 行 fileMover 在 iOS 27 可用且接受文件 URL；第 30151 行提供 interactiveDismissDisabled。

专属分析 agent：`/root/audit_group_b/c082`。

<a id="c083"></a>

### C083 · WorkspaceRecentlyDeleted

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/WorkspaceFileActions.swift:140)　置信度：high

当前实现：使用 NavigationStack、List/ForEach、HStack/VStack、Button、ContentUnavailableView、ToolbarItem 与原生 alert 展示工作区回收站；加载删除记录，按条恢复，显示错误及触觉反馈，并在文件操作期间禁用操作和交互关闭。

系统候选：保留现有系统控件组合。局部可把行的 HStack 换为 LabeledContent(content:label:)，但仍需双行标题/原路径、独立 Restore 按钮和同样的异步状态，未发现实质复杂度收益。

判断：当前代码没有自绘列表、弹窗或空态，页面价值是把工作区删除记录接入原生控件。恢复必须走 store 的重名检查、持久化和索引更新，不能由通用文件选择器承担。已评估 LabeledContent：它只改变行布局，既不能去掉双行标签和按钮，也不减少错误与忙碌状态管理；为这层薄组合另做 UIKit 桥接没有收益。

预期收益：维持现有薄封装即可；局部换用 LabeledContent 仅替换原生布局表达，业务状态和按钮代码仍存在，没有足够收益支持专门重构。

必须保留：显示条目标题及原始路径，恢复按钮保留 44 点最小高度和 files.restore 路径标识；恢复使用 store.restoreFile，保留重名拒绝、磁盘/演示数据恢复与索引更新；恢复成功后移除条目；失败提示错误并反馈触觉；空列表显示系统空态；打开时重新加载回收站，文件操作期间禁用内容和交互关闭

验证要求：已静态阅读 OrgendaUITests/MotionFlowUITests.swift:140 testFileBrowserSwipeDeleteCancelUndoAndRecentlyDeletedRestore，覆盖删除、撤销、恢复按钮消失和嵌套内容恢复；未运行。；已静态阅读 OrgendaTests/Services/Workspace/WorkspaceConnectionTests.swift:338 testFileGesturesMoveDeleteRestoreAndReindexConnectedFolder，覆盖跨 Store 重新加载删除记录及恢复后索引；未运行。；若尝试 LabeledContent，需对比长原路径、大字号及 VoiceOver 下两行标签和独立恢复按钮的布局/焦点，并补查恢复失败提示与忙碌时禁止关闭；目前无运行证据证明布局替换等价。

代码依据：

- [Orgenda/Features/Files/WorkspaceFileActions.swift:140](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/WorkspaceFileActions.swift:140) — 原生列表、双行条目、Restore 异步操作、系统空态、错误提示及交互关闭保护均位于该组件。
- [Orgenda/Features/Files/FilesView.swift:110](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/FilesView.swift:110) — Recently Deleted sheet 实际实例化该组件，属于生产入口。
- [Orgenda/Services/Workspace/WorkspaceFileOperations.swift:103](/Users/roifewu/.config/orgenda/Orgenda/Services/Workspace/WorkspaceFileOperations.swift:103) — restoreFile 校验记录存在和路径冲突，恢复存储、移除删除记录并更新文档/索引；144 行加载记录并检查工作区会话。

API 依据：

- [iOS 27 SDK — LabeledContent 声明（5016–5031 行）](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：核对 iOS 16 起支持任意 content/label 构造；可承载按钮与自定义标签，但不会取代恢复业务与两行标签。
- [iOS 27 SDK — ContentUnavailableView 与 interactiveDismissDisabled](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：核对 ContentUnavailableView 的标题、systemImage、description 初始化（22636–22683 行，iOS 17 起）及 interactiveDismissDisabled(Bool)（30149–30151 行，iOS 15 起）；当前实现已直接采用。

专属分析 agent：`/root/audit_group_b/c083`。

<a id="c084"></a>

### C084 · WorkspaceFileFeedback

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/WorkspaceFileActions.swift:193)　置信度：high

当前实现：以 ViewModifier 统一 FilesView 的反馈：safeAreaInset 中显示移动/删除消息及原生 Undo、Dismiss 按钮，原生 ProgressView 显示文件操作进度，原生 alert 展示错误；撤销异步调用 WorkspaceStore 并给出触觉反馈。

系统候选：保留现有 SwiftUI Button、ProgressView、alert 组合。局部可考虑 iOS 26+ safeAreaBar(edge: .bottom) 接管滚动边缘效果；Foundation UndoManager 仅是撤销操作注册机制，不是当前消息条的等价控件。

判断：现有封装已使用系统控件，主要价值是连接文件操作状态与共享反馈。safeAreaBar 能统一安全区域及滚动边缘效果，但仍需消息、两个按钮和异步错误处理；目前并无手写边缘效果可删除，收益仅是视觉风格变化。UndoManager 不能自动保存当前移动/回收站撤销语义与失败时保留入口的逻辑，接入反而增加适配。未发现可实质减少实现且等价的替代。

预期收益：保留现有抽象可避免重复状态绑定。safeAreaBar 的潜在收益限于系统滚动边缘外观，不会删除撤销业务逻辑或显著减少视图代码，暂不建议仅为替换而改动。

必须保留：移动和删除的本地化结果消息，持续显示至下一次操作、成功撤销或主动关闭；Undo 异步执行原有校验、同步与恢复流程，失败展示错误并保留仍有效的撤销状态；文件操作期间进度反馈、完成触觉及 files.action.undo 可访问性标识；iPhone 导航栈和 iPad 分栏均由外层 FilesView 统一承载反馈

验证要求：静态阅读 OrgendaUITests/MotionFlowUITests.swift:17 testHapticTouchFilePreviewOpenAndMove、:43 testHapticTouchFolderDeleteRequiresConfirmationAndCanUndo 与 :140 testFileBrowserSwipeDeleteCancelUndoAndRecentlyDeletedRestore，均实际点击 files.action.undo；未执行测试。；静态阅读 OrgendaTests/Services/Workspace/WorkspaceStoreTests.swift:43 testFileGestureUndoRestoresImplicitDemoParent 和 WorkspaceConnectionTests.swift:338 testFileGesturesMoveDeleteRestoreAndReindexConnectedFolder，覆盖撤销后的路径与内容恢复；未执行测试。；若试用 safeAreaBar，需原型核对底部 TabView、iPad 分栏、滚动内容、键盘出现及大字体下的安全区与按钮可达性；其视觉等价性尚未运行验证。

代码依据：

- [Orgenda/Features/Files/WorkspaceFileActions.swift:193](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/WorkspaceFileActions.swift:193) — 组件仅组合 safeAreaInset、HStack、Button、ProgressView 与 alert；Undo 通过 Task 调用 store。
- [Orgenda/Features/Files/FilesView.swift:67](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/FilesView.swift:67) — 同一个 modifier 应用于 iPhone NavigationStack 与 iPad NavigationSplitView 外层。
- [Orgenda/Services/Workspace/WorkspaceFileOperations.swift:134](/Users/roifewu/.config/orgenda/Orgenda/Services/Workspace/WorkspaceFileOperations.swift:134) — undoFileAction 分派 moveFile/restoreFile，成功才清空撤销；:162 的 performFileAction 管理互斥、同步及错误。

API 依据：

- [SwiftUI iOS 27 SDK — safeAreaBar 与 EnvironmentValues.undoManager](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：核对 22280 行 vertical-edge safeAreaBar 签名，iOS 26.0 起可用；21668 行 undoManager 为 Foundation.UndoManager? 环境值。
- [Apple safeAreaBar(edge:alignment:spacing:content:)](https://developer.apple.com/documentation/swiftui/view/safeareabar(edge:alignment:spacing:content:))：官方 Markdown 说明该 API 调整安全区并扩展受影响 ScrollView 的边缘效果，仍由调用方提供自定义栏内容；不是成套撤销反馈 UI。
- [Foundation iOS 27 SDK — NSUndoManager.h](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/Foundation.framework/Headers/NSUndoManager.h)：核对通用 undo/redo 操作注册机制与 registerUndoWithTarget:handler: 回调，未提供文件状态消息条或应用异步恢复逻辑。

专属分析 agent：`/root/audit_group_b/c084`。

<a id="c085"></a>

### C085 · WorkspaceFolderDropTarget

**需原型或产品取舍 · P2**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/WorkspaceFileActions.swift:229)　置信度：medium

当前实现：文件夹行上的 UIViewRepresentable，已组合公开 UIDropInteraction 与 UITapGestureRecognizer。仅接收本应用单个工作区文件类型；进入、退出及结束更新高亮，提议 move，投放后解码原始 WorkspaceFileTransfer，经 store 校验和异步移动，再反馈触感；覆盖层点击转发 onOpen。

系统候选：iOS 27 SwiftUI .dropDestination(for: WorkspaceFileTransfer.self) + .dropConfiguration + .onDropSessionUpdated；用 DropSession.localSession、itemsCount 和 suggestedOperations 表达本地单项 move，保留收到的完整 Transferable。若 List 行内投放路由成立，可移除 UIKit 覆盖层并恢复已有 NavigationLink 点击。

判断：SDK 已具备类型解码、会话阶段及移动提议，局部可省去 provider.loadTransferable 和三个高亮委托回调。但当前注释明确以独立 UIKit 目标绕过 List 的行内投放拦截；官方 API 声明不能证明 iOS 27 已解决此路由，现有 UI 测试也只覆盖当前实现。不能仅按路径重建传输对象，否则会丢失拖动时的工作区身份和子树快照；store 的防过期、冲突及持久化校验必须保留。需原型验证后才可删除桥接。

预期收益：原型成功后可删除 UIViewRepresentable、Coordinator、手工 NSItemProvider 解码和点击转发；具体收益集中在交互适配层，业务文件操作仍需保留。若 List 路由仍受限，现有短小公开 UIKit 封装已属系统组件组合，没有已证实可安全单独替换的部分。

必须保留：本地单项拖放、orgendaWorkspaceFile 类型限定，以及 move 操作；不变成外部导入或列表重排。；实际传输对象中的 workspaceID、document.path/kind 和 snapshot 原样传入 store；拖放期间切换工作区或修改子树应拒绝。；目标文件夹语义：拒绝同父目录、自身/后代、无效目标、同名冲突；移动完整子树并保留隐藏附件、编辑状态、索引和撤销。；文件夹行进入/退出/结束清理高亮；点击仍执行相应导航，侧滑与上下文菜单保持可用。；通过 store.moveFile 统一执行异步持久化、错误反馈与完成触感；不得由 SwiftUI 拖动结束事件再次删除源。

验证要求：静态阅读，未构建或运行：OrgendaUITests/MotionFlowUITests.swift:104 testFileBrowserFolderDragMovesSubtreeAndPickerMovesItBack 验证文件夹投放、子树内容和后续导航；:177 testFileBrowserMovePickerAndCancelledDrag 覆盖取消拖动不产生移动。；静态阅读，未运行：OrgendaTests/Services/Workspace/WorkspaceConnectionTests.swift:367 testFileGestureRejectsExternalEditAndDifferentWorkspace；OrgendaTests/Services/Workspace/WorkspaceFileStoreTests.swift:20 testFileMoveRejectsCollisionDescendantsAndStaleChildren；同文件 :5 验证隐藏附件与精确字节。；所需 iOS 27 原型：在根 List 的 plain/sidebar 以及嵌套 List 内，将真实 dragContainer 的文件和文件夹投到文件夹行，确认目的路径是行对应文件夹，不被父级 root dropDestination 接管。；所需原型：用完整原始 payload 覆盖拖动中切换工作区、修改子树、相同路径的其他工作区、多项及外部拖放、无效目标和取消；确认不复制、不双重删除，结束后无残留高亮。；所需原型：移除 UIKit 覆盖层后核对 NavigationLink 在分栏/紧凑布局中的打开回调、侧滑、上下文菜单及辅助功能；不能以 SDK 编译可用当成交互等价证明。

代码依据：

- [Orgenda/Features/Files/WorkspaceFileActions.swift:229](/Users/roifewu/.config/orgenda/Orgenda/Features/Files/WorkspaceFileActions.swift:229) — 当前公开 UIKit 拖放桥接；:54 由文件夹行实际安装；:253 只以本地、单项和 UTI 初筛，:278 解码真实传输并校验后移动。
- [Orgenda/Domain/Workspace/WorkspaceFileTransfer.swift:9](/Users/roifewu/.config/orgenda/Orgenda/Domain/Workspace/WorkspaceFileTransfer.swift:9) — CodableRepresentation 承载 workspaceID、document 和子树 snapshot，身份不只是路径。
- [Orgenda/Services/Workspace/WorkspaceFileOperations.swift:9](/Users/roifewu/.config/orgenda/Orgenda/Services/Workspace/WorkspaceFileOperations.swift:9) — canMoveFile 校验工作区/目标层级；moveFile 与 :153 validateFileTransfer 继续校验快照和冲突，统一持久化与撤销。

API 依据：

- [Apple SwiftUI dropDestination(for:isEnabled:action:)](https://developer.apple.com/documentation/swiftui/view/dropdestination(for:isenabled:action:))：已读取官方 Markdown：iOS 26 起提供 [Transferable] 与 DropSession，目标与视图同大小位置；未承诺解决 List 内行级路由。
- [Apple SwiftUI dropConfiguration(_:)](https://developer.apple.com/documentation/swiftui/view/dropconfiguration(_:))：已读取官方 Markdown：iOS 27 可按 suggestedOperations 选择 move 等操作；配置闭包频繁调用，不应在此加载文件或执行持久化。
- [iOS 27 SDK SwiftUI DropSession / DropConfiguration / onDropSessionUpdated](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：核对 :2585 的 iOS 27 onDropSessionUpdated/dropConfiguration；:10778 的 phase/localSession/itemsCount/suggestedOperations；:14624 的 DropConfiguration(operation:)。acceptedItemCount 在 iOS 不可用，单项限制须自行判断 itemsCount；draggedItemIDs 不能替代原始快照。
- [iOS 27 SDK UIDropInteraction / UIDropProposal](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/UIKit.framework/Headers/UIDropInteraction.h)：当前实现已是公开系统交互；核对 canHandle、enter/update/exit/end、performDrop 生命周期，以及 move 要求会话允许移动且数据实际移动仍由应用负责。

专属分析 agent：`/root/audit_group_b/c085`。

<a id="c086"></a>

### C086 · ConfiguredCaptureView

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/ItemEditor/ConfiguredCaptureView.swift:3)　置信度：high

当前实现：由 NavigationStack、Form、分组 Picker、Menu、DatePicker、原生纵向 TextField、Toggle 与工具栏组成的配置化 Org 捕获表单；根据模板动态生成输入，先预览再写入，并校验配置版本、工作区会话和目标文件基线。生产捕获入口与模板编辑器的只预览入口均使用此视图。

系统候选：保留现有系统控件组合。逐项评估后，纵向 TextField 已提供多行输入与占位；iOS 27 SDK 的 textInputSuggestions/textInputCompletion 仍标记 unavailable，不能替换 Suggestions Menu。可探索将 Quick template selection 合并入分组 Picker 的选项快捷键，但分组菜单、快捷键作用域及输入时单键行为尚需原型，没有已证实的实质替换收益。

判断：这里的自定义部分是模板展开和写入保护，而不是自绘控件。多行输入已经直接使用系统 TextField，无占位覆盖层可删；建议菜单允许既选预设又自由填写，普通 Picker 会限制输入，系统文本建议 API 又不支持 iOS。模板 Picker 与快捷菜单存在小量枚举重复，但合并前须证明分组和单键快捷操作等价。预览失效、配置与会话校验、文件基线不能随表单简化删除。

预期收益：当前主要复杂度属于业务状态和持久化保护，没有可由系统控件消除的大块 UI 实现。合并两个模板选择入口至多减少一处枚举与入口，收益有限，且需验证快捷键行为；引入 UIKit 编辑桥接反而增加维护面。

必须保留：模板分组、默认模板、单键快速选择及切换模板后清空答案；提示字段的默认值与建议选项，同时允许任意多行文本；保留长文本、中文 IME 和连续编辑；Org 时间戳的活动/非活动与是否包含时间语义，以及日期树和缺失标题创建选择；输入变化后废弃预览，预览模式禁止提交；配置、工作区会话或目标文件变化时阻止旧内容写入；生成 Org 的可选择复制文本与错误反馈

验证要求：OrgendaTests/Domain/Org/WorkspaceConfigurationTests.swift:227 testCapturePromptExpansionDoesNotInterpretAnswers 验证答案不会再次解释为占位符；仅阅读，未运行。；OrgendaTests/Domain/Org/WorkspaceConfigurationTests.swift:130 testCapturePrependPreservesTargetMetadata 验证目标元数据保留与缺失目标报错；仅阅读，未运行。；OrgendaUITests/ConfigurationUITests.swift:233 testConfiguredCaptureInvalidatesPreviewAndSavesLatestTitle 直接覆盖本视图：未预览时禁止 Capture，输入标题后预览启用提交，修改标题使旧预览消失并禁用提交，重新预览后保存最新标题且可搜索、旧标题不存在；仅阅读，未运行。；已核对附近的 testConfigurationAndTemplateAtAccessibilitySize（ConfigurationUITests.swift:215）、testTemplateValidationKeepsDraftAndCancelRequiresDiscard（:487）及 testNativeTemplateFileSelectionSearchAndReselect（:602）；这些覆盖模板配置编辑界面，不等同于捕获表单的长文本、快捷键或只预览模式覆盖。若合并选择入口，仍须原型验证分组展示、菜单关闭时快捷键、文本输入焦点下的单键冲突及选择后预览失效。；任何编辑控件调整均须检查长段落粘贴、换行、中日韩 IME 未提交文本、光标与焦点连续性，并覆盖预览后切换工作区/配置及目标文件并发修改；本次未构建或运行。

代码依据：

- [Orgenda/Features/ItemEditor/ConfiguredCaptureView.swift:43](/Users/roifewu/.config/orgenda/Orgenda/Features/ItemEditor/ConfiguredCaptureView.swift:43) — 表单已由系统控件组成；47–83 的模板选择、建议菜单与纵向 TextField 是实际局部替换评估对象。
- [Orgenda/Features/ItemEditor/ConfiguredCaptureView.swift:106](/Users/roifewu/.config/orgenda/Orgenda/Features/ItemEditor/ConfiguredCaptureView.swift:106) — 输入变化清除预览；116–138 保存并核验配置版本、会话与目标基线，再调用 store.capture。
- [Orgenda/Features/ItemEditor/OrgItemEditorSupport.swift:68](/Users/roifewu/.config/orgenda/Orgenda/Features/ItemEditor/OrgItemEditorSupport.swift:68) — 配置化捕获的生产调用；Orgenda/Features/Settings/ConfigurationEditors.swift:296 另以 initialTemplate 与 previewOnly 使用该表单。

API 依据：

- [iOS 27 SwiftUI SDK：TextField 与文本建议 API](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对 6556–6584 的 TextField(text:prompt:axis:)；9672 附近 textInputSuggestions 与 18095 附近 textInputCompletion 的声明均标记 iOS unavailable。3890 附近 TextEditor 初始化器没有 prompt 参数。
- [Apple SwiftUI keyboardShortcut(_:modifiers:)](https://developer.apple.com/documentation/swiftui/view/keyboardshortcut(_:modifiers:))：已读取官方 Markdown 正文：快捷键触发控件主要动作，解析作用域为活动 scene，冲突时取首个匹配项；文档未保证在这里将带分组的 Picker 选项替代独立快捷菜单的全部交互。

专属分析 agent：`/root/audit_group_b/c086`。

<a id="c087"></a>

### C087 · ConfigurationCaptureDateField

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/ItemEditor/ConfiguredCaptureView.swift:146)　置信度：high

当前实现：短小的原生 DatePicker 适配器：本地 Date 状态以当前时间初始化，根据模板后缀选择日期或日期加时间，并在初次显示及日期变更时写回 Org 时间戳字符串。

系统候选：已使用 SwiftUI.DatePicker、DatePickerComponents 和 onChange(initial:)；未识别出能进一步移除 Org 字符串适配的系统控件。

判断：实际交互全部由系统 DatePicker 提供，自定义部分仅将 Date 转为捕获答案所需的字符串。SDK 的 selection 要求 Binding<Date>，不能直接接收现有 Binding<String>；t/T/u/U 的活动括号和时间选项仍须由应用处理。内联控件只是迁移状态和转换逻辑，改用 UIDatePicker 还会增加桥接；没有值得实施的局部系统替代收益。

预期收益：保留现有封装即可继续获得原生日期输入、布局及辅助功能；没有可量化的额外系统替代简化。若未来统一为 Date 类型答案，可重新审视适配边界，但属于数据模型调整。

必须保留：t/T 输出活动时间戳尖括号，u/U 输出非活动时间戳方括号。；T/U 显示并输出时分，t/u 仅输出日期。；初次显示即生成答案，后续选择写回对应 prompt.id；保留 Gregorian、英文星期与当前时区的 Org 格式。

验证要求：OrgendaTests/Domain/Date/OrgCalendarDatesTests.swift:16 testOrgTimestampSourceUsesGregorianDatesAndPreservesTimestampOptions 覆盖活动/非活动括号与时间输出。；OrgendaTests/Domain/Org/WorkspaceConfigurationTests.swift:227 testCapturePromptExpansionDoesNotInterpretAnswers 覆盖答案原样进入模板；不覆盖此私有 View 的交互。；若调整绑定或状态归属，需检查四种后缀初次显示即生成答案、变更日期后预览失效、切换模板后答案与显示日期一致；本次仅静态核对，未运行测试。

代码依据：

- [Orgenda/Features/ItemEditor/ConfiguredCaptureView.swift:66](/Users/roifewu/.config/orgenda/Orgenda/Features/ItemEditor/ConfiguredCaptureView.swift:66) — 生产调用按 t/T/u/U 后缀传入 active/includesTime，答案绑定 input.answers[prompt.id]。
- [Orgenda/Features/ItemEditor/ConfiguredCaptureView.swift:146](/Users/roifewu/.config/orgenda/Orgenda/Features/ItemEditor/ConfiguredCaptureView.swift:146) — 组件只有 DatePicker、本地 Date 状态和 onChange(initial: true) 的序列化回写。
- [Orgenda/Domain/Date/Date+Orgenda.swift:28](/Users/roifewu/.config/orgenda/Orgenda/Domain/Date/Date+Orgenda.swift:28) — orgTimestamp 使用尖/方括号；orgDateText 固定 Gregorian、en_US_POSIX 和当前时区。

API 依据：

- [iOS 27 SDK SwiftUI.DatePicker 与 DatePickerComponents](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对 25373、25424、25431–25435：selection 为 Binding<Foundation.Date>；支持 .date 与 .hourAndMinute，当前组件已直接采用。
- [iOS 27 SDK SwiftUICore.View.onChange(of:initial:_:)](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUICore.framework/Modules/SwiftUICore.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对 17359 双参数回调重载及 initial 参数；初次回写使用系统生命周期 API。

专属分析 agent：`/root/audit_group_b/c087`。

<a id="c088"></a>

### C088 · OrgItemDetailsSection

**需原型或产品取舍 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/ItemEditor/OrgItemDetailsSection.swift:3)　置信度：high

当前实现：编辑器 Form 内的 Details 分区，以系统 Section、Picker 和可增高至四行的 TextField 编辑状态、类型、优先级、标签及 Emacs 上下文；Tags 使用单独标题与纵向 VStack。

系统候选：局部候选为 LabeledContent("Tags") { 现有 TextField }，让系统负责标签与输入内容的关联及 Form 布局；其余 Picker、Section 及业务封装保留。

判断：主体已经是系统控件组合；可进一步简化的是 Tags 的标题与输入框布局。LabeledContent 支持可编辑内容并适配 Form，但不保证维持当前标签在上、输入框占满宽度的布局。应先确认长标签和大字体下的输入宽度；若必须保持当前纵向布局，额外自定义样式会抵消收益，保留现状更合理。

预期收益：最多省去 Tags 的手工标题排版并获得系统表单标签布局；收益很小，不涉及标签解析、状态配置或编辑器状态管理的减少。

必须保留：标签输入的 1...4 行增长、逗号分隔、禁用自动大写与纠错；共享 FocusState、Done 收起键盘和现有无障碍标识/提示；笔记及事件隐藏状态、捕获模板隐藏类型、Emacs 配置才显示 Context；Context 与自由标签字段共享 tagsText，切换 @home/@work 时保留其他标签；按当前文件配置传入 workflow.states

验证要求：已检索 OrgendaTests 与 OrgendaUITests，未找到 item.editor.tags 或 item.editor.priority 的直接 UI 覆盖；本次未运行测试。；OrgendaUITests/DatePresentationUITests.swift:300、305 的 testSimplifiedChinese/testTraditionalChinese 经 verifyChinese 检查编辑器状态菜单，可作为既有相关回归依据。；需要原型确认 iPhone 窄屏、iPad、辅助功能最大字号下 LabeledContent 包含 1 至 4 行 TextField 时的可用输入宽度、VoiceOver 标签、焦点及 Done 行为；再决定是否接受布局变化。

代码依据：

- [Orgenda/Features/ItemEditor/OrgItemDetailsSection.swift:13](/Users/roifewu/.config/orgenda/Orgenda/Features/ItemEditor/OrgItemDetailsSection.swift:13) — Section 内条件显示原生 Picker，状态选择封装也基于系统 Picker。
- [Orgenda/Features/ItemEditor/OrgItemDetailsSection.swift:50](/Users/roifewu/.config/orgenda/Orgenda/Features/ItemEditor/OrgItemDetailsSection.swift:50) — Tags 自定义部分仅是纵向标题排版；实际编辑、焦点和提交均由 TextField 修饰符实现。
- [Orgenda/Features/ItemEditor/OrgItemEditor.swift:194](/Users/roifewu/.config/orgenda/Orgenda/Features/ItemEditor/OrgItemEditor.swift:194) — 生产 Form 使用此分区；同文件 415 行 Context Binding 更新 tagsText，489 行负责逗号拆分及清理。

API 依据：

- [Apple LabeledContent](https://developer.apple.com/documentation/swiftui/labeledcontent)：通过官方 Markdown 内容核实支持只读/可编辑值、自动适配 Form，以及可定制样式；没有保证本组件既有纵向布局。
- [iOS 27 SwiftUI SDK：LabeledContent 与 TextField](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：5016 起确认 LabeledContent 及 content/label 初始化器可用；6557 起确认现用 TextField(text:axis:) 为系统 API；5531、30422 附近核实 automatic 样式及自定义样式协议。

专属分析 agent：`/root/audit_group_b/c088`。

<a id="c089"></a>

### C089 · OrgItemEditor

**可局部替代 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/ItemEditor/OrgItemEditor.swift:4)　置信度：medium

当前实现：新增/编辑 Org 条目的业务表单；已使用 NavigationStack、Form、Section、Picker、纵向 TextField、TextEditor、Stepper、系统警告与确认框。维护捕获模板、焦点、状态日志、草稿基线、源文本预览、冲突恢复及移动/归档保护。Source 的 Line 已为 LabeledContent，File 仍是可选取、可换行的纵向标签值组合。

系统候选：仅 Source 的 File 信息对可改为 LabeledContent("File") { Text(draft.source.file)… }，保留 Text 的 textSelection(.enabled)、fixedSize(horizontal:false, vertical:true) 和字体设置。Line 已使用此控件，无剩余替换收益。Notes 保留 TextEditor 与不接收点击、不进入辅助功能树的占位文本；TextField(prompt:axis:.vertical) 仅是需要另行原型的替代候选，不纳入直接替换建议。

判断：File 是标准只读标签值，LabeledContent 能表达现有语义并交由 Form 统一布局；使用 content 闭包保留完整路径的换行与选取，不能简化成会截断长路径的单行值。默认布局可能由纵向变为横向，窄屏与最大字体仍须检查。iOS 27 SDK 的 TextEditor 没有 prompt 初始化器；纵向 TextField 虽有 prompt，但不能仅为省占位层就认定长正文滚动、换行、IME 组合和编辑连续性等价。表单业务状态及冲突保护仍需保留。

预期收益：局部收益只在一个 Source 元数据行：减少标签和值的手工容器与语义组合维护，跟随系统表单布局。没有可删除整个编辑器或 Notes 占位层的已证明等价方案；不应为此增加 UIKit 桥接或自定义 LabeledContentStyle。

必须保留：File 显示完整深层路径、允许选择复制，并有明确 File 标签；保持大字体和窄屏可读性。；Notes 长正文的多行输入与滚动、IME 组合、焦点和选区连续性；占位提示不拦截点击、不重复朗读。；标题及必填首步/状态原因校验，模板切换保留用户内容和规划，Org 标签、重复与事件语义。；未保存草稿禁止误关闭，失败时保留草稿并可复制、查看最新版本及复制后重载。；源预览返回后草稿保持，未保存时不能移动/归档，异步移动期间锁定交互。

验证要求：已静态阅读 OrgendaUITests/MotionFlowUITests.swift:866 testCaptureKeepsUnsavedDraftAndSavesSearchableTask，以及 :891 testCaptureSourcePreviewUsesBackNavigationAndPreservesDraft；分别覆盖取消保留草稿、保存和源预览返回，后者明确绕过 Notes 的内部滚动区。未运行。；已静态阅读 OrgendaUITests/ConfigurationUITests.swift:525 testWorkflowKeyboardShortcutsRespectTextEditing，要求输入时不触发工作流快捷键；未运行。；已静态阅读 OrgendaTests/Services/Workspace/WorkspaceStoreTests.swift:469 testStaleEditorBaselineRejectsNewerSourceNotesBeforeAndAfterReindex，以及 OrgendaTests/Domain/Org/OrgCaptureTemplateTests.swift:5 testSwitchingTemplatesPreservesPlanningAndMapsEventTimestamp；保护草稿基线和模板规划语义，未运行。；File 局部替换须在窄 iPhone、iPad 分栏、最大 Dynamic Type、RTL 和 VoiceOver 下验证深层长路径不截断、复制完整且标签值关联清楚；若默认 LabeledContent 无法满足，保留当前纵向组合，而非再造样式。；若后续尝试以纵向 TextField 替换 Notes，先原型验证长文本粘贴、换行/滚动、中文日文 IME 未提交组合、撤销、选区、预览往返及键盘交互关闭；现有测试不能证明此等价性。

代码依据：

- [Orgenda/Features/ItemEditor/OrgItemEditor.swift:306](/Users/roifewu/.config/orgenda/Orgenda/Features/ItemEditor/OrgItemEditor.swift:306) — Notes 使用持续存在的 TextEditor，空内容时额外显示禁用命中和辅助功能的占位 Text。
- [Orgenda/Features/ItemEditor/OrgItemEditor.swift:347](/Users/roifewu/.config/orgenda/Orgenda/Features/ItemEditor/OrgItemEditor.swift:347) — Source 的 File 是 VStack 标签值且显式允许选择/垂直扩展，Line 已经使用 LabeledContent；这是唯一明确的小范围标准信息对替换点。
- [Orgenda/Features/Agenda/AgendaView.swift:98](/Users/roifewu/.config/orgenda/Orgenda/Features/Agenda/AgendaView.swift:98) — 编辑条目时实际通过 sheet 呈现 OrgItemEditor；另在 SearchView.swift:57 和 OrgItemEditorSupport.swift:70 用于搜索编辑与新建捕获，属于在用业务组件。

API 依据：

- [Apple SwiftUI LabeledContent](https://developer.apple.com/documentation/swiftui/labeledcontent/?v=1.1.1)：官方文档明确标签值容器会随 Form 等容器适配布局，content 闭包可放置自定义值视图，文本值在可能时支持选择；未承诺与当前纵向排列完全一致。
- [iOS 27 SwiftUI SDK: TextEditor / LabeledContent / TextField declarations](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：核对 TextEditor 3889 行起的 String、带 selection 与 AttributedString 初始化器均无 prompt；LabeledContent 5017 行起支持自定义 content，iOS 16 起可用；TextField 6567 行起有 prompt+axis 初始化器。
- [Apple SwiftUI TextEditor](https://developer.apple.com/documentation/swiftui/texteditor?changes=_7)：官方将 TextEditor 定义为长文本、多行可滚动编辑控件，支持保留当前 Notes 选择。
- [Apple TextField init(text:prompt:axis:label:)](https://developer.apple.com/documentation/swiftui/textfield/init%28text%3Aprompt%3Aaxis%3Alabel%3A%29)：官方确认 prompt 与滚动首选轴 API，但说明 axis 是否遵守取决于样式；不能由该声明推断其与 TextEditor 的全部长文编辑交互等价。

专属分析 agent：`/root/audit_group_b/c089`。

<a id="c090"></a>

### C090 · OrgSourceView

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/ItemEditor/OrgItemEditorSupport.swift:3)　置信度：high

当前实现：通过 HighlightedOrgEditor 的只读模式显示原始 Org 源码或草稿序列化结果，底层已使用可选择、可滚动的 UITextView；标题与导航样式由 SwiftUI 提供。附带的 source(for:stateNote:) 同时服务草稿复制及冲突恢复。

系统候选：只读展示局部可尝试 ScrollView + Text(AttributedString).textSelection(.enabled)，仍需现有 Org 高亮解析和属性转换；当前 UITextView(isEditable: false, isSelectable: true) 已是对应系统控件，无明确净简化。

判断：当前视图仅包装已原生化的只读文本显示和导航；源码生成包含 Org 时间范围、工作流及恢复注释语义，系统文本控件不能代替。局部改用可选择的富文本 Text 有 API 基础，但仍需高亮转换，并须验证长文滚动、跨行选择及主题切换后选择保持，且共享编辑器仍被其他页面使用，不能据此删除。此处无输入会话，替换不应扩展到需 IME 连续性的编辑路径。

预期收益：保留现状无需新增只读渲染器。改用 Text 最多更换这一处显示组合，不能移除其他页面依赖的共享编辑器，也不能删除承担恢复语义的序列化代码；未见足以抵消适配及验证成本的局部收益。

必须保留：有 originalSource 时逐字展示原始内容；草稿变化或捕获模板预览遵循调用方提供的源码；只读且可选择复制，保留 Org 高亮、Unicode 内容、长文滚动及动态字体；序列化保留工作流、优先级、标签、属性、重复规则、跨日时间范围和 CLOSED 时间；草稿状态说明按行写为安全注释，支持复制草稿及冲突恢复

验证要求：OrgendaTests/Domain/Org/OrgCaptureTemplateTests.swift:144 — OrgDraftRecoveryTests.testRecoveryPreservesEventWithoutAddingWorkflowAndItsOvernightDuration，及同类测试覆盖计划、期限、全天范围与安全注释；OrgendaTests/Components/Editor/OrgSyntaxTextEditorTests.swift:660 — testPresentationAttributesPreserveSelectionAndSemanticTraits 覆盖主题变化后的源码、选区及语义样式保持；如试验 Text 展示，需原型验证大篇幅源码首屏与滚动表现、中文及双向文本的跨段选择复制、动态字体/深色模式下选区保持，以及 VoiceOver；现有测试未直接覆盖只读 OrgSourceView 的交互。此次只读审查未运行测试。

代码依据：

- [Orgenda/Features/ItemEditor/OrgItemEditorSupport.swift:8](/Users/roifewu/.config/orgenda/Orgenda/Features/ItemEditor/OrgItemEditorSupport.swift:8) — 只读 HighlightedOrgEditor 包装；同文件 :13–58 包含草稿 Org 序列化逻辑
- [Orgenda/Features/ItemEditor/OrgItemEditor.swift:147](/Users/roifewu/.config/orgenda/Orgenda/Features/ItemEditor/OrgItemEditor.swift:147) — 最新版本弹层调用；:173 选择模板/精确源码/草稿预览，:461 将序列化结果用于复制和恢复
- [Orgenda/Components/Editor/OrgSyntaxTextEditor.swift:44](/Users/roifewu/.config/orgenda/Orgenda/Components/Editor/OrgSyntaxTextEditor.swift:44) — 无会话时直接创建原生 UITextView；:101–109 独立设置只读、可选择和辅助功能标签

API 依据：

- [iOS 27 UIKit UITextView.h](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/UIKit.framework/Headers/UITextView.h)：核对 editable、selectable 与 attributedText；selectable 明确控制文本选择及内容交互，支持当前只读可选文本实现。
- [iOS 27 SwiftUI swiftinterface — textSelection / TextEditor](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：核对 textSelection 自 iOS 15 可用，TextEditor 有字符串和 iOS 26 起的 AttributedString 绑定构造；这些声明本身不能证明只读长文展示交互与现有 TextKit 路径等价。
- [iOS 27 SwiftUICore swiftinterface — Text.init(AttributedString)](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUICore.framework/Modules/SwiftUICore.swiftmodule/arm64e-apple-ios.swiftinterface)：核对 Text 的 AttributedString 构造自 iOS 15 可用，支持局部只读富文本候选；不提供 Org 语法解析或草稿序列化。

专属分析 agent：`/root/audit_group_b/c090`。

<a id="c091"></a>

### C091 · OrgItemCaptureSheet

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/ItemEditor/OrgItemEditorSupport.swift:62)　置信度：high

当前实现：根据工作区配置与日期选择模板捕获或条目编辑器，并初始化新 OrgItem 的工作流状态、计划日期及收件箱路径；外层已由 SwiftUI sheet(item:) 呈现。

系统候选：继续使用现有 SwiftUI 条件 ViewBuilder 与 sheet(item:)；本组件没有可由系统控件替换的局部绘制、布局或交互实现。

判断：它是捕获入口的业务路由：有配置且未指定日期时进入模板捕获，其他情况创建带正确日期、状态及文件目标的草稿。条件分支与弹窗呈现已经使用系统机制；局部只剩 Org 数据默认值及路径选择，系统组件不能提供这些语义。将分支内联到根视图仅搬移代码，不能减少实际复杂度。

预期收益：无实质系统替换收益；保留短包装可集中入口判断和草稿默认值，避免根视图混入 Org 业务初始化。

必须保留：配置工作区无指定日期时进入 ConfiguredCaptureView；日历捕获保留所选日期并进入 OrgItemEditor；配置工作流初始状态及配置、Emacs、普通收件箱三种目标规则；由目标编辑器维护草稿、预览及保存行为

验证要求：已静态阅读 OrgendaUITests/MotionFlowUITests.swift:866 testCaptureKeepsUnsavedDraftAndSavesSearchableTask，覆盖普通入口及草稿保留。；已静态阅读 OrgendaUITests/MotionFlowUITests.swift:1139 testCalendarCaptureUsesSelectedDate，检查捕获保存后的 SCHEDULED 日期。；已静态阅读 OrgendaUITests/ConfigurationUITests.swift:233 testConfiguredCaptureInvalidatesPreviewAndSavesLatestTitle，覆盖配置捕获入口。；未运行构建或测试；配置工作区指定日期以及 Emacs 收件箱分支的完整组合仍需专门运行验证，当前结论来自源码。

代码依据：

- [Orgenda/Features/ItemEditor/OrgItemEditorSupport.swift:62](/Users/roifewu/.config/orgenda/Orgenda/Features/ItemEditor/OrgItemEditorSupport.swift:62) — 组件全部实现仅含条件选择、OrgItem 默认值及 inboxPath 规则。
- [Orgenda/Features/Root/OrgendaRootView.swift:54](/Users/roifewu/.config/orgenda/Orgenda/Features/Root/OrgendaRootView.swift:54) — 唯一生产调用位于系统 sheet(item:) 内，配置 large detent 和可见拖动指示器。
- [Orgenda/Features/ItemEditor/OrgItemEditor.swift:33](/Users/roifewu/.config/orgenda/Orgenda/Features/ItemEditor/OrgItemEditor.swift:33) — 接收新草稿并初始化 State，保留 Emacs 模板默认值及按目标文件选择工作流的逻辑。

API 依据：

- [iOS 27 SDK — SwiftUI View.sheet(item:onDismiss:content:)](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：核对 9143 行声明：系统以 Binding<Item?> 与 Identifiable 数据呈现任意 View 内容；现有调用已经采用该能力。
- [iOS 27 SDK — SwiftUICore ViewBuilder.buildEither](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUICore.framework/Modules/SwiftUICore.swiftmodule/arm64e-apple-ios.swiftinterface)：核对 5618–5631 行条件构建 API，if/else 内容切换由原生 ViewBuilder 处理，无需自行实现容器。

专属分析 agent：`/root/audit_group_b/c091`。

<a id="c092"></a>

### C092 · OrgItemRefileDestinations

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/ItemEditor/OrgItemEditorSupport.swift:91)　置信度：high

当前实现：以系统 List、Button、Text 和布局栈显示 Org 移动目标；展示标题路径、工作流图标与颜色，移动中禁用操作，空列表使用 ContentUnavailableView。

系统候选：继续使用现有 List + Button + ContentUnavailableView；无可实质减少实现的等价替代。Picker 需要选择绑定，不能直接替代执行移动的动作列表。

判断：该视图已将列表、点击和空态交给 SwiftUI，剩余代码是 Org 目标与条目匹配及业务展示。点击行立即回调执行异步移动，调用方负责防止未保存修改、重复移动并在成功后退出；改用 Picker 会引入额外选择状态，仍须保留同样的目标展示与操作流程，不能降低复杂度。

预期收益：保留短小业务视图即可；替换原生控件组合无明确复杂度收益。

必须保留：显示完整 outline，缺省时使用 title，并显示来源文件路径；按文件路径及 headingStartByte 匹配工作流图标和标题颜色；移动过程中禁止重复触发，保留空目标说明；保留调用方的未保存修改限制、异步移动失败处理和成功退出

验证要求：OrgendaTests/Domain/Org/OrgWorkflowOperationsTests.swift:192 testRefileTargetsUseOnlyConfiguredFilesAndFirstThreeLevels 覆盖目标范围与 outline。；OrgendaTests/Domain/Org/OrgWorkflowOperationsTests.swift:222 testRefileRejectsSelfDescendantAndStaleTarget 覆盖非法及过期目标保护。；搜索 OrgendaTests 与 OrgendaUITests 未发现该视图专门交互测试；若后续修改，需验证空态、工作流标题、移动禁用与失败后重试。本次仅静态审查，未运行测试。

代码依据：

- [Orgenda/Features/ItemEditor/OrgItemEditorSupport.swift:91](/Users/roifewu/.config/orgenda/Orgenda/Features/ItemEditor/OrgItemEditorSupport.swift:91) — List 中每行 Button 即时回调，保留 outline/path、工作流展示与系统空态。
- [Orgenda/Features/ItemEditor/OrgItemEditor.swift:368](/Users/roifewu/.config/orgenda/Orgenda/Features/ItemEditor/OrgItemEditor.swift:368) — 生产调用由 NavigationLink 推入；hasChanges 或 isMoving 时禁用移动区，moveItem 在第 433 行处理异步状态及结果。
- [Orgenda/Services/Workspace/WorkspaceMoves.swift:70](/Users/roifewu/.config/orgenda/Orgenda/Services/Workspace/WorkspaceMoves.swift:70) — 目标来自配置文件与层级过滤；performMove 校验原条目及源/目标状态。

API 依据：

- [SwiftUI Button、Picker 与 ContentUnavailableView 的本地 iOS SDK 声明](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：核对 Button(action:label:)（29179 行）、Picker(selection:content:label:)（18150 行附近）与 ContentUnavailableView(_:systemImage:description:)（22660 行附近）；前者直接执行动作，Picker 使用 Binding<SelectionValue>，空态为 iOS 17+ 系统组件。

专属分析 agent：`/root/audit_group_c/c092`。

<a id="c093"></a>

### C093 · OrgItemScheduleSection

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/ItemEditor/OrgItemScheduleSection.swift:3)　置信度：high

当前实现：以原生 Section、Toggle、DatePicker、Stepper、Button 和 AnyLayout 编辑 Org 计划日、截止日、事件日期及时间；封装可选日期绑定、首次启用时间和辅助功能字号布局。

系统候选：继续使用现有 SwiftUI DatePicker、Toggle、Stepper；未发现能实质删去业务封装的等价系统组件。

判断：日期、开关与时长输入已经交给系统控件；剩余代码处理 Org 三类时间戳、可选日期、模板要求计划日及首次开启时间的默认值。DatePicker 接收非可选 Date 绑定，不能替代这些状态转换。辅助功能字号下的纵向排列及快捷日期保留时分也属于必要配置，换成另一套原生控件没有明确简化收益。

预期收益：保留现有短业务封装；没有可量化的系统替换收益，避免重复实现已有原生输入控件。

必须保留：事件时间戳与 scheduled/deadline 的不同语义及可选值开关；要求计划日的模板禁用 Scheduled 开关；首次开启时间仅初始化午夜日期；后续开关保留已配置时间；Today/Tomorrow 保留选定时分并收起键盘；辅助功能字号纵向排列与 44 点快捷按钮；时长范围 5–480 分钟、步长 5

验证要求：已读 OrgendaTests/Domain/Org/OrgCaptureTemplateTests.swift:5 testSwitchingTemplatesPreservesPlanningAndMapsEventTimestamp，覆盖模板切换时计划、截止和事件日期语义，非本节直接交互测试。；未运行测试；尚需交互验证首次/再次启用 Set a time、Today/Tomorrow 保留时分、模板锁定计划日及最大辅助功能字号下 DatePicker 标签与可操作性。

代码依据：

- [Orgenda/Features/ItemEditor/OrgItemScheduleSection.swift:12](/Users/roifewu/.config/orgenda/Orgenda/Features/ItemEditor/OrgItemScheduleSection.swift:12) — 原生 Section、DatePicker、Toggle、Stepper 与动态布局组合。
- [Orgenda/Features/ItemEditor/OrgItemScheduleSection.swift:60](/Users/roifewu/.config/orgenda/Orgenda/Features/ItemEditor/OrgItemScheduleSection.swift:60) — 自定义 Binding 保留首次启用时间状态；107 行快捷按钮保留时分并收起键盘。
- [Orgenda/Features/ItemEditor/OrgItemEditor.swift:188](/Users/roifewu/.config/orgenda/Orgenda/Features/ItemEditor/OrgItemEditor.swift:188) — 在 Form 中绑定真实草稿、时间配置状态及模板所需计划标记。

API 依据：

- [SwiftUI DatePicker / Stepper SDK declarations](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：核实 DatePicker 的 Binding<Date> 与 displayedComponents 初始化器，以及 Stepper 的数值绑定、范围和步长；当前实现已直接使用系统 API。
- [SwiftUICore AnyLayout / DynamicTypeSize SDK declarations](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/SwiftUICore.framework/Modules/SwiftUICore.swiftmodule/arm64e-apple-ios.swiftinterface)：核实 AnyLayout 与 isAccessibilitySize 为原生布局及环境能力；自适应路径无需另写 UIKit 桥接。

专属分析 agent：`/root/audit_group_c/c093`。

<a id="c094"></a>

### C094 · JournalComposer

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Journal/JournalComposer.swift:3)　置信度：high

当前实现：使用 NavigationStack、Form、TextField、TextEditor、LabeledContent、工具栏和系统 alert 组合日记录入表单；补充正文占位、焦点切换、丢弃保护和日期保存逻辑。

系统候选：无实质替代；维持现有系统 Form / TextEditor / alert 组合。

判断：实际界面已由原生表单与编辑控件构成。SDK 的 TextEditor 没有 prompt 初始化参数，空正文提示层有实际用途，换成多行 TextField 也不能证明编辑行为等价。所选日期与当前时分秒合成、默认标题、空正文校验和丢弃保护均属业务流程，系统组件不能自动承担，保留封装更直接。

预期收益：没有可证明的系统替代简化收益；保留短小原生组合可集中编辑状态与保存规则。

必须保留：日历选中日期作为保存日期，时分秒取当前时间；空标题使用本地化默认值；正文仅含空白时禁用添加；原始正文交给 WorkspaceStore 的 Org 日记写入流程；默认聚焦正文、标题提交切换正文、交互式收起键盘；有内容时禁止滑动关闭，取消先确认丢弃；占位文案不阻挡触摸或重复无障碍朗读

验证要求：OrgendaUITests/DatePresentationUITests.swift:107 — testCalendarJournalPagingKeepsDateAndCapturesOnSelectedDay 覆盖选中日期进入表单、输入和保存后归属日期。；OrgendaTests/Services/Workspace/WorkspaceConnectionTests.swift:557 — testNewJournalFilePersistsAndRestoresInSelectedYear 覆盖下游日记文件持久化及恢复日期、正文。；静态检查未见专门覆盖取消/滑动丢弃保护、空白正文禁用与初始焦点的测试；如调整交互需补充相应 UI 验证，本次未运行测试。

代码依据：

- [Orgenda/Features/Journal/JournalComposer.swift:16](/Users/roifewu/.config/orgenda/Orgenda/Features/Journal/JournalComposer.swift:16) — 原生 Form 与 TextEditor、提示层、焦点、工具栏、alert 和 interactiveDismissDisabled 已完整实现录入交互。
- [Orgenda/Features/Agenda/AgendaCalendarView.swift:55](/Users/roifewu/.config/orgenda/Orgenda/Features/Agenda/AgendaCalendarView.swift:55) — 日历通过 sheet(item:) 传入捕获日期，以大尺寸 sheet 展示 JournalComposer。
- [Orgenda/Features/Journal/JournalComposer.swift:85](/Users/roifewu/.config/orgenda/Orgenda/Features/Journal/JournalComposer.swift:85) — saveEntry 合成所选日期与当前时间，调用 WorkspaceStore.addJournalEntry 后关闭。

API 依据：

- [SwiftUI.TextEditor 本地 SDK 声明](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：3885–3926 行确认纯文本和富文本 TextEditor 初始化器，未提供 prompt；30148–30153 行确认 interactiveDismissDisabled 为系统 View API（iOS 15+）。

专属分析 agent：`/root/audit_group_c/c094`。

<a id="c095"></a>

### C095 · JournalDayContent

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Journal/JournalDayContent.swift:3)　置信度：high

当前实现：以 LazyVStack 显示当日日记；空状态已用 ContentUnavailableView、Label 和 Button，有条目时用 ForEach 传入条目及末项标志。

系统候选：继续使用现有 ContentUnavailableView 与 LazyVStack/ForEach；没有能消除这层业务分支的实质系统替代。

判断：主体仅把日记空态、创建回调和有序条目组合起来，空态已经直接使用系统专用组件。调用方负责选日筛选及 ScrollView 的分页、居中和滚动复位；本层保持无状态并传递末项标志。移入调用方只是搬代码，换成 List 仍须保留同样分支且会改变现有滚动结构，不能获得实质简化。

预期收益：保留简短原生组合即可；无值得引入替代控件的复杂度收益。

必须保留：空态创建按钮触发调用方按当前选中日期创建日记；按传入顺序及稳定条目身份展示，并准确传递末项标志；保留 journal.empty 标识及调用方控制的空态居中、日期切换滚动复位

验证要求：OrgendaUITests/DatePresentationUITests.swift:107 testCalendarJournalPagingKeepsDateAndCapturesOnSelectedDay 覆盖选日日记显示、分页与创建后呈现（本次仅读取，未运行）；OrgendaTests/Services/Indexing/JournalFileIndexTests.swift:6 testSelectedDayTimelineSortsByTimeAndThenBySourcePosition 覆盖选日及传入顺序（本次仅读取，未运行）；现有相关测试未直接点击空态 Write an Entry；若调整空态布局，应验证按钮按选中日期进入编辑器

代码依据：

- [Orgenda/Features/Journal/JournalDayContent.swift:7](/Users/roifewu/.config/orgenda/Orgenda/Features/Journal/JournalDayContent.swift:7) — 原生 LazyVStack 内仅包含空态条件、系统 ContentUnavailableView 和条目 ForEach
- [Orgenda/Features/Agenda/AgendaCalendarView.swift:142](/Users/roifewu/.config/orgenda/Orgenda/Features/Agenda/AgendaCalendarView.swift:142) — 唯一生产调用取得选日日记，外层 ScrollView 负责空态居中与日期切换复位
- [Orgenda/Services/Workspace/WorkspaceStore+Queries.swift:35](/Users/roifewu/.config/orgenda/Orgenda/Services/Workspace/WorkspaceStore+Queries.swift:35) — 日记筛选及确定性降序排列由数据层完成

API 依据：

- [SwiftUI ContentUnavailableView SDK declaration](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：22637–22649：iOS 17 起提供 label/description/actions 构造器，现实现已直接使用。
- [SwiftUI LazyVStack and ForEach SDK declarations](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/SwiftUICore.framework/Modules/SwiftUICore.swiftmodule/arm64e-apple-ios.swiftinterface)：10748–10761 核对 LazyVStack alignment/spacing/content 参数；21778–21790 核对 ForEach 数据与内容构造的原生类型。

专属分析 agent：`/root/audit_group_c/c095`。

<a id="c096"></a>

### C096 · JournalTimelineEntry

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Journal/JournalDayContent.swift:27)　置信度：high

当前实现：使用 VStack、Text、Rectangle、Circle 和背景布局显示日记时间、标题、可选择正文及左侧时间线；末条不绘制延伸线，装饰对辅助功能隐藏。

系统候选：无有意义的直接替代；LabeledContent 仅提供标签与值结构，TimelineView 提供按计划刷新内容，并非日记事件时间线。

判断：组件没有自绘控件或 UIKit 桥接，文字选择、字体和可访问性均由 SwiftUI 提供。其少量组合代码表达时间、标题、正文的层级以及末条断线规则。LabeledContent 仍需保留这些布局和装饰；TimelineView 接受刷新计划而非条目序列，不能取代此行。没有可消除实质复杂度的系统替换。

预期收益：保留短小的原生组合封装；替换只会移动现有布局代码，未识别出实质复杂度收益。

必须保留：时间采用本地化短时间格式与等宽数字；标题和正文完整换行，空正文隐藏，正文可选择；末条不延伸时间线，装饰不进入辅助功能树；日记条目及标题稳定的辅助功能标识

验证要求：OrgendaUITests/DatePresentationUITests.swift:107 testCalendarJournalPagingKeepsDateAndCapturesOnSelectedDay 验证选中日期对应条目和新建后标题出现；仅静态阅读，未执行。；OrgendaTests/Services/Indexing/JournalFileIndexTests.swift:6 testSelectedDayTimelineSortsByTimeAndThenBySourcePosition 覆盖上游顺序，影响末条断线判定。；现有测试未直接覆盖正文选择、动态字体完整显示和末条装饰；若调整布局，应运行时核对这些行为及 VoiceOver 子元素顺序。

代码依据：

- [Orgenda/Features/Journal/JournalDayContent.swift:21](/Users/roifewu/.config/orgenda/Orgenda/Features/Journal/JournalDayContent.swift:21) — ForEach 为每条创建组件，并以末条 ID 计算 isLast。
- [Orgenda/Features/Journal/JournalDayContent.swift:32](/Users/roifewu/.config/orgenda/Orgenda/Features/Journal/JournalDayContent.swift:32) — 原生文字堆叠、正文选择和背景几何图形构成完整实现。
- [OrgendaUITests/DatePresentationUITests.swift:107](/Users/roifewu/.config/orgenda/OrgendaUITests/DatePresentationUITests.swift:107) — 日历日记分页用例验证条目展示与选中日期、新建记录关联。

API 依据：

- [SwiftUI SDK：textSelection、LabeledContent 与 TimelineView](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：核对 2336 行 textSelection 原生选择修饰器；5017–5050 行 LabeledContent 的 label/content 结构；29049–29108 行 TimelineView 的 TimelineSchedule、date/cadence 与 schedule 初始化参数，确认它不是事件列表控件。

专属分析 agent：`/root/audit_group_c/c096`。

<a id="c097"></a>

### C097 · OrgendaRootView

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Root/OrgendaRootView.swift:11)　置信度：high

当前实现：应用根容器已使用 TabView、Tab、TabSection、sidebarAdaptable、ContentUnavailableView 与 sheet；负责工作区启动、同步生命周期、分栏选择映射、搜索状态、快速操作及草稿保护。

系统候选：无实质替代；原生 TabView(.sidebarAdaptable)、搜索角色 Tab 与 ContentUnavailableView 均已采用。

判断：真实入口直接创建此视图，导航外观与侧栏已交给系统。剩余代码绑定 Org 视角、设备尺寸、工作区就绪状态与快速操作；选项卡控件不能替代这些业务协调。改用 NavigationSplitView 仍需保留状态逻辑，并重新实现当前标签栏与侧栏切换，不能证明能简化。应保留此组合。

预期收益：无可确认的系统替代收益；保留现有原生容器，避免新增导航桥接或重复状态管理。

必须保留：iPad 侧栏视角分组、主标签唯一性及尺寸变化后的选择映射；搜索查询与文件定位请求，以及快速操作重置目的页导航；已有模态草稿未关闭前延迟执行快速操作；启动及文件操作期间交互保护、前后台同步和网络恢复同步

验证要求：OrgendaUITests/IPadLayoutUITests.swift:15 testSidebarGroupsDashboardViewsAndPreservesSelection；:62 testNativeSidebarDismissesAfterSelectionInPortrait；:76 testTopTabsStayUniqueAcrossSidebarSelections。；OrgendaUITests/IPadLayoutUITests.swift:307 testRootNavigationAndSearchRemainUsableAcrossRotation；OrgendaUITests/WorkspaceSyncUITests.swift:34 testStartupSkeletonKeepsFirstScreenChromeUntilIndexIsReady。；OrgendaTests/App/OrgendaQuickActionsTests.swift:7 testEveryInstalledShortcutCanBeRouted 仅验证请求接收；模态草稿等待及导航重置需运行时专项验证。本审查未运行测试。

代码依据：

- [Orgenda/App/OrgendaApp.swift:23](/Users/roifewu/.config/orgenda/Orgenda/App/OrgendaApp.swift:23) — 正式构建的 WindowGroup 创建 OrgendaRootView。
- [Orgenda/Features/Root/OrgendaRootView.swift:149](/Users/roifewu/.config/orgenda/Orgenda/Features/Root/OrgendaRootView.swift:149) — iPad 采用 sidebarAdaptable，后续原生 TabSection/Tab 完成分组与搜索；:74 的任务等待模态关闭。
- [OrgendaUITests/IPadLayoutUITests.swift:15](/Users/roifewu/.config/orgenda/OrgendaUITests/IPadLayoutUITests.swift:15) — 已有侧栏分组、视角保留、标签唯一性及旋转后的搜索状态用例。

API 依据：

- [SwiftUI SDK：SidebarAdaptableTabViewStyle、TabSection、tabViewSearchActivation](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：核对 9258 起 sidebarAdaptable、20435 起 TabSection 为 iOS 18+，14311 起 tabViewSearchActivation 为 iOS 26+；项目目标 iOS 27，现实现已采用这些原生 API。

专属分析 agent：`/root/audit_group_c/c097`。

<a id="c098"></a>

### C098 · OrgendaCaptureToolbar

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Root/OrgendaRootView.swift:275)　置信度：high

当前实现：用原生 ToolbarItem(.topBarTrailing) 和 Button 提供新建任务入口，配置加号图标、Command-N、主题前景色及无障碍标识。

系统候选：现有 SwiftUI ToolbarItem + Button 已是对应系统实现；无实质替代。

判断：组件没有自绘工具栏、手势或尺寸逻辑，材质与布局均交给系统。AgendaView 仅在议程模式调用它并传入 onCapture(nil)，根视图负责展示捕获表单。移入调用处只能消除命名封装，仍需保留同样的按钮配置，不能减少系统之外的交互实现。

预期收益：保留即可；没有值得替换的自定义控件实现，内联仅改变代码组织。

必须保留：议程模式右上角的新建任务入口与 onCapture(nil) 回调；Command-N 快捷键、可本地化的 New task 标签和 orgenda.capture 标识；继承工作区启动及文件操作期间的禁用状态

验证要求：OrgendaUITests/ConfigurationUITests.swift:233 testConfiguredCaptureInvalidatesPreviewAndSavesLatestTitle：从 Dashboard 点击该入口打开捕获表单。；OrgendaUITests/WorkspaceSyncUITests.swift:33 testStartupSkeletonKeepsFirstScreenChromeUntilIndexIsReady 及 :37 testStartupSkeletonAtAccessibilitySize：验证启动期间入口存在但禁用，启动后恢复且纵向位置稳定。；本次仅静态阅读，未运行测试；如改动快捷键配置，需实机或模拟器验证 Command-N 及禁用期间行为。

代码依据：

- [Orgenda/Features/Root/OrgendaRootView.swift:275](/Users/roifewu/.config/orgenda/Orgenda/Features/Root/OrgendaRootView.swift:275) — 完整实现仅为系统工具栏项与按钮修饰符。
- [Orgenda/Features/Agenda/AgendaView.swift:80](/Users/roifewu/.config/orgenda/Orgenda/Features/Agenda/AgendaView.swift:80) — mode == .agenda 分支使用组件并调用 onCapture(nil)。
- [OrgendaUITests/WorkspaceSyncUITests.swift:57](/Users/roifewu/.config/orgenda/OrgendaUITests/WorkspaceSyncUITests.swift:57) — 查询 orgenda.capture 并验证启动阶段禁用、恢复和位置稳定。

API 依据：

- [本地 iPhoneOS SDK：ToolbarItem、ToolbarItemPlacement.topBarTrailing、Button 与 keyboardShortcut](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对 :7582 顶栏尾侧 placement、:8471 ToolbarItem、:26821 keyboardShortcut、:29209 带 systemImage 的 Button 构造；均为项目现用的原生 API。

专属分析 agent：`/root/audit_group_c/c098`。

<a id="c099"></a>

### C099 · SearchJournalDetail

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Search/SearchJournalDetail.swift:3)　置信度：high

当前实现：搜索结果的只读日记详情页，使用 ScrollView、VStack、Label、Text 展示日期、标题及全文，并开启系统文本选择和柔和滚动边缘效果。

系统候选：无需替换；现有 ScrollView + Label + Text 即系统方案。

判断：组件没有自绘控件、桥接或自定义交互，只有日记内容与系统视图的业务绑定。生产调用由搜索结果的 NavigationLink 推入，日期沿用统一的相对日期及本地化时间规则；替换为其他容器仍需保留这些布局与导航配置，无法实质减少实现。

预期收益：保留这个短小的原生页面封装；未发现有实际复杂度收益的系统替代。

必须保留：日期、标题与完整正文的只读展示；可滚动长文和系统文本选择；统一日期显示规则及内联导航标题

验证要求：OrgendaTests/DesignSystem/MotionPolicyTests.swift:42 testDatePresentationUsesTheSuppliedCalendarWithADifferentLocale 覆盖日期格式所用日历与时区。；OrgendaTests/Services/Indexing/JournalFileIndexTests.swift:52 testUnicodeOffsetsAndNestedSourceBlocksRemainIntact 覆盖正文中的 Unicode 与 Org 内容保留。；rg 检索 OrgendaTests 和 OrgendaUITests 未发现 SearchJournalDetail 专属交互测试；长正文滚动、文本选择及导航返回需运行时检查，本次未运行。

代码依据：

- [Orgenda/Features/Search/SearchJournalDetail.swift:7](/Users/roifewu/.config/orgenda/Orgenda/Features/Search/SearchJournalDetail.swift:7) — 全部界面由系统滚动、布局、标签、文本及修饰符组成。
- [Orgenda/Features/Search/SearchResultRow.swift:48](/Users/roifewu/.config/orgenda/Orgenda/Features/Search/SearchResultRow.swift:48) — journalLink 通过 NavigationLink 实际创建本页面。
- [Orgenda/DesignSystem/Formatting/OrgendaDatePresentation.swift:73](/Users/roifewu/.config/orgenda/Orgenda/DesignSystem/Formatting/OrgendaDatePresentation.swift:73) — dateTime 合并业务相对日期与 Foundation 本地化时分。

API 依据：

- [SwiftUI ScrollView、textSelection(_:)、scrollEdgeEffectStyle(_:for:) SDK 声明](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：核对 ScrollView 原生容器，textSelection 自 iOS 15 可用，scrollEdgeEffectStyle 自 iOS 26 可用；本组件已直接使用这些系统能力。

专属分析 agent：`/root/audit_group_c/c099`。

<a id="c100"></a>

### C100 · View.searchListSurface

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Search/SearchListSurface.swift:4)　置信度：high

当前实现：将原生 List 的 plain 样式、隐藏滚动内容背景、透明背景、交互式收键盘及上下 soft 滚动边缘效果集中为共享修饰方法。

系统候选：当前已使用 SwiftUI List 的系统修饰器，无实质替代方案；展开到两个调用点只会重复配置。

判断：该方法没有自绘、桥接或手势实现，只封装五个原生修饰器。搜索结果与搜索建议的 List 均调用它，统一外观及收键盘行为；不存在一个系统预设同时取代这些配置且减少复杂度。保留短小共享封装即可，删除会将相同配置分散到两个调用点。

预期收益：保留现有封装已避免重复；改成更大的系统桥接或内联配置没有复杂度收益。

必须保留：搜索结果和建议列表采用一致的 plain 样式与透明内容背景；滚动时交互式收起键盘；上下边缘使用系统 soft 效果

验证要求：已静态阅读 OrgendaUITests/UIUXPolishUITests.swift:86 的 testReplacingSearchQueryAndChangingScopeShowsCurrentResults，覆盖结果列表查询与范围切换。；已静态阅读 OrgendaUITests/WorkspaceSyncUITests.swift:4 的 testSearchDocumentOpensPreviewAndKeepsResults，覆盖结果进入文档后返回。；现有上述测试未直接断言该修饰器的背景、soft 边缘与交互式收键盘；如后续调整配置，应在结果与建议两种 List 上人工核验。此次未运行测试。

代码依据：

- [Orgenda/Features/Search/SearchListSurface.swift:4](/Users/roifewu/.config/orgenda/Orgenda/Features/Search/SearchListSurface.swift:4) — 实现全部由原生 SwiftUI 修饰器组成。
- [Orgenda/Features/Search/SearchView.swift:175](/Users/roifewu/.config/orgenda/Orgenda/Features/Search/SearchView.swift:175) — 搜索结果 List 使用共享修饰方法。
- [Orgenda/Features/Search/SearchSuggestionsView.swift:80](/Users/roifewu/.config/orgenda/Orgenda/Features/Search/SearchSuggestionsView.swift:80) — 搜索建议 List 使用同一方法。

API 依据：

- [iPhoneOS 27.0 SDK SwiftUI interface](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：核对 PlainListStyle（14607）、scrollContentBackground（13730，iOS 16+）、scrollDismissesKeyboard 及 interactively（15583/15595，iOS 16+）、scrollEdgeEffectStyle 及 soft（15497/15485，iOS 26+）均为现有系统 API。

专属分析 agent：`/root/audit_group_c/c100`。

<a id="c101"></a>

### C101 · SearchResultLabel

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Search/SearchResultLabel.swift:3)　置信度：high

当前实现：以 HStack、VStack、SF Symbol Image 和 AttributedString Text 组合搜索结果标签，显示标题、摘要、可选详情与工作流状态；按动态字体缩放图标和摘要行数。

系统候选：SwiftUI Label(title:icon:) 可承载相同内容，但仍需保留内部文本层级、工作流图标、高亮和布局配置；没有实质替代收益。

判断：当前是多个搜索入口复用的原生视图组合，未重造交互控件。Label 支持自定义标题和图标，但不会替代摘要、详情、工作流颜色、首个匹配高亮或大字模式规则；保持现有顶端对齐与间距也仍需布局配置。直接更换只改变外层容器，不能减少有意义的业务实现。

预期收益：保留现有短封装可集中维护搜索展示规则；更换 Label 不会消除内部业务代码。

必须保留：标题及摘要中首个不区分大小写和变音符号匹配的加粗高亮；工作流标题颜色覆盖匹配颜色并保留加粗、可选状态图标与详情；摘要普通字号最多三行、无障碍字号不限行，图标随正文缩放并对辅助功能隐藏；作为原生 Button 和 NavigationLink 的可复用标签

验证要求：已读 OrgendaUITests/ConfigurationUITests.swift:194 的 testSettingsSearchOpensWorkflowWithoutCategoryHub，覆盖设置搜索结果打开及返回。；已读 OrgendaUITests/WorkspaceSyncUITests.swift:4 的 testSearchDocumentOpensPreviewAndKeepsResults，覆盖文档搜索结果导航；现有测试未直接断言标签高亮及大字换行，若调整布局需补充运行时检查；本次未运行。

代码依据：

- [Orgenda/Features/Search/SearchResultLabel.swift:14](/Users/roifewu/.config/orgenda/Orgenda/Features/Search/SearchResultLabel.swift:14) — 原生栈布局及可选摘要、详情、状态，摘要按动态字体设置行数。
- [Orgenda/Features/Search/SearchResultLabel.swift:49](/Users/roifewu/.config/orgenda/Orgenda/Features/Search/SearchResultLabel.swift:49) — AttributedString 执行首个匹配高亮，工作流标题统一着色。
- [Orgenda/Features/Search/SearchResultRow.swift:14](/Users/roifewu/.config/orgenda/Orgenda/Features/Search/SearchResultRow.swift:14) — 条目、设置、日志、文档结果将该视图用于 Button 或 NavigationLink 标签；SearchSuggestionsView.swift:68 另有设置入口调用。

API 依据：

- [SwiftUI Label<Title, Icon> SDK 声明](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：30895–30913 行确认 iOS 14 起提供 title/icon 内容构造器；该接口仍要求调用方提供自定义内容。
- [SwiftUICore Text(AttributedString) 与 DynamicTypeSize SDK 声明](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/SwiftUICore.framework/Modules/SwiftUICore.swiftmodule/arm64e-apple-ios.swiftinterface)：9826–9833 行确认 Text 原生接受 AttributedString；14746 行确认 isAccessibilitySize，现有实现已使用这些系统能力。

专属分析 agent：`/root/audit_group_c/c101`。

<a id="c102"></a>

### C102 · SearchResultRow

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Search/SearchResultRow.swift:3)　置信度：high

当前实现：按搜索结果类型组合原生 Button、NavigationLink 与 SearchResultLabel；项目/设置交给上层弹出 sheet，日志/文件推入导航，并生成匹配标签或正文摘要。

系统候选：继续使用现有 SwiftUI Button(action:label:) 和 NavigationLink(destination:label:)；没有能替代结果类型映射与业务路由的单一系统组件。

判断：交互已由原生 Button 与 NavigationLink 承担，剩余代码是四类搜索结果的内容和目的地映射。项目及设置使用上层 sheet，日志及文件使用导航栈；文档还把查询传给预览/编辑页。换成统一链接会改变展示方式，改用 UIKit 列表不会消除业务分支，暂无实质替代收益。

预期收益：保留封装可让搜索结果与空查询建议共用路由和内容配置；没有值得另建系统桥接的复杂度收益。

必须保留：项目和设置的 sheet 展示，以及设置直接打开匹配分类；日志、文件夹和文档的各自导航目的地；文件查询向详情传递，空查询显示路径而不传搜索参数；标签优先、忽略大小写和变音符的匹配摘要，以及工作流状态和来源信息；设置与文件的可访问性标识及操作提示

验证要求：OrgendaUITests/WorkspaceSyncUITests.swift:4 — testSearchDocumentOpensPreviewAndKeepsResults 覆盖文档预览、进入编辑时选择匹配及返回后查询保留；本次仅阅读，未运行。；OrgendaUITests/ConfigurationUITests.swift:194 — testSettingsSearchOpensWorkflowWithoutCategoryHub 覆盖设置深链和关闭后结果保留；本次仅阅读，未运行。；OrgendaUITests/IPadLayoutUITests.swift:307 — testRootNavigationAndSearchRemainUsableAcrossRotation 覆盖返回与旋转时搜索状态；本次仅阅读，未运行。

代码依据：

- [Orgenda/Features/Search/SearchResultRow.swift:10](/Users/roifewu/.config/orgenda/Orgenda/Features/Search/SearchResultRow.swift:10) — 四类结果分别使用 Button/NavigationLink；38 行选择标签摘要，63 行区分文件夹和文档。
- [Orgenda/Features/Search/SearchView.swift:54](/Users/roifewu/.config/orgenda/Orgenda/Features/Search/SearchView.swift:54) — onPresent 的值由 sheet 分派到 OrgItemEditor 或 SettingsView；153 行真实结果列表调用此行。
- [Orgenda/Features/Search/SearchSuggestionsView.swift:40](/Users/roifewu/.config/orgenda/Orgenda/Features/Search/SearchSuggestionsView.swift:40) — 最近日志与 54 行浏览文件复用此组件，空查询仍有生产调用。

API 依据：

- [SwiftUI SDK — Button 与 NavigationLink 的自定义 label 初始化器](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：核对 14229–14250 行 NavigationLink(destination:label:) 与 29179–29196 行 Button(action:label:)；两者均原生接受 View 内容，现实现已经直接使用。

专属分析 agent：`/root/audit_group_c/c102`。

<a id="c103"></a>

### C103 · SearchSuggestionsView

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Search/SearchSuggestionsView.swift:3)　置信度：high

当前实现：以原生 List、Section、横向 ScrollView 和胶囊 Button 构成空查询浏览页，按 scope 展示标签、最近三篇日记、前四个非文件夹文档或设置入口；复用结果行导航。

系统候选：无等价整页替代；SwiftUI searchSuggestions { … } 配合 searchCompletion(_:) 仅是标签补全交互的候选，迁移需改变建议的展示时机与布局。

判断：调用方在空查询且有可用内容时直接展示此页，不依赖搜索焦点；它同时提供内容导航和设置入口。系统 searchSuggestions 在搜索激活时展示建议，searchCompletion 能回填标签，但不消除分类、排序及导航逻辑，并会改变常驻浏览页与横向标签布局。现有实现已由系统控件组成，保留该业务组合更简单。

预期收益：直接替代没有实质复杂度收益；迁移标签到系统补全可能省去按钮赋值，但仍需保留数据筛选与浏览页，且引入两种展示路径。

必须保留：空查询下按分类显示可浏览内容，不额外要求搜索框获得焦点；标签受 scope 过滤、按频次排序，点击原样写入 query；日记倒序最多三条，文档排除文件夹最多四条；日记和文档导航、设置弹窗以及无障碍标签

验证要求：rg 检索 OrgendaTests、OrgendaUITests 未发现 SearchSuggestions 或 search.suggestions 的直接测试。；已阅读 OrgendaUITests/WorkspaceSyncUITests.swift:4 testSearchDocumentOpensPreviewAndKeepsResults，仅覆盖有查询结果导航，不证明空查询建议等价。；已阅读 OrgendaUITests/UIUXPolishUITests.swift:86 testReplacingSearchQueryAndChangingScopeShowsCurrentResults，覆盖 query 与 scope 切换；如尝试系统建议，需原型验证 iPhone/iPad 搜索激活前后可见性、标签回填、键盘关闭与返回导航。

代码依据：

- [Orgenda/Features/Search/SearchSuggestionsView.swift:11](/Users/roifewu/.config/orgenda/Orgenda/Features/Search/SearchSuggestionsView.swift:11) — 原生列表承载标签按钮、日记/文档结果行和设置入口；第 18 行直接设置 query。
- [Orgenda/Features/Search/SearchView.swift:132](/Users/roifewu/.config/orgenda/Orgenda/Features/Search/SearchView.swift:132) — searchContent 仅依据空查询及 suggestions.isAvailable 选择此页，没有 isSearchFocused 条件。
- [Orgenda/Features/Search/SearchSuggestions.swift:25](/Users/roifewu/.config/orgenda/Orgenda/Features/Search/SearchSuggestions.swift:25) — 标签按 scope 筛选、频次及本地化名称排序后最多八个，属于应用业务规则。

API 依据：

- [SwiftUI iOS 27 SDK — searchSuggestions and searchCompletion](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对第 13569 行 searchSuggestions builder（iOS 16+）及第 18763 行字符串 searchCompletion（iOS 15+）；均满足最低 iOS 27。
- [Apple — Suggesting search terms](https://developer.apple.com/documentation/SwiftUI/Suggesting-search-terms)：文档说明激活搜索界面后呈现建议列表，选择 searchCompletion 将替换搜索文本；该生命周期不同于当前空查询浏览页。

专属分析 agent：`/root/audit_group_c/c103`。

<a id="c104"></a>

### C104 · SearchView

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Search/SearchView.swift:3)　置信度：high

当前实现：以 NavigationStack、searchable、searchFocused、Menu 内 Picker、List 和 sheet 组合跨类别搜索页；负责 200ms 防抖、取消过期搜索、空态、结果与编辑导航。

系统候选：无整体等价系统组件；现有搜索输入已经原生。searchScopes 可作为分类栏的另一种产品呈现，但并非已证实等价的替换。

判断：真正的控件已由 SwiftUI 提供，剩余代码将工作区搜索、六类范围、建议、异步状态与多种详情入口连接起来。searchScopes 不会承担这些业务职责；其激活配置也不足以证明能保持当前分类栏在搜索聚焦和空查询时的稳定呈现。没有可无损移除此页面封装的系统替代。

预期收益：保留原生控件与业务编排边界；整体替换无明确复杂度收益。若产品选择 searchScopes，仅可能减少分类栏布局，仍须保留搜索状态和导航。

必须保留：查询由根页面绑定，返回详情和旋转后保留查询及结果；查询、范围及索引数据变化触发搜索；取消过期请求并显示当前请求加载态；六类范围、扩大到全部范围、清空查询及分类相关建议；紧凑宽度搜索标签与常规宽度导航栏搜索框、程序化聚焦；任务和设置 sheet、文档和日记导航及文件内匹配传递

验证要求：OrgendaUITests/UIUXPolishUITests.swift:86 — testReplacingSearchQueryAndChangingScopeShowsCurrentResults 覆盖快速改查询、分类切换与扩大范围；OrgendaUITests/WorkspaceSyncUITests.swift:4 — testSearchDocumentOpensPreviewAndKeepsResults 覆盖详情返回及查询保留；OrgendaUITests/ConfigurationUITests.swift:194 — testSettingsSearchOpensWorkflowWithoutCategoryHub 覆盖设置结果入口；OrgendaUITests/IPadLayoutUITests.swift:307 — testRootNavigationAndSearchRemainUsableAcrossRotation 覆盖 iPad 旋转后查询与结果；本次只读检查，未运行测试；若尝试 searchScopes，需原型核对六类范围在空查询、键盘聚焦、紧凑/常规宽度及辅助功能字号下的可达性与栏位稳定性

代码依据：

- [Orgenda/Features/Search/SearchView.swift:42](/Users/roifewu/.config/orgenda/Orgenda/Features/Search/SearchView.swift:42) — 已使用系统 NavigationStack、searchable、searchFocused、Menu/Picker、List；task 按查询和索引输入重启并取消旧搜索
- [Orgenda/Features/Root/OrgendaRootView.swift:204](/Users/roifewu/.config/orgenda/Orgenda/Features/Root/OrgendaRootView.swift:204) — 系统 search 角色 Tab 实际创建 SearchView 并传递根级查询和聚焦请求
- [Orgenda/Services/Workspace/WorkspaceStore+Queries.swift:46](/Users/roifewu/.config/orgenda/Orgenda/Services/Workspace/WorkspaceStore+Queries.swift:46) — 搜索具有 Org 类型范围、正文/标签/文件与设置目的地语义，系统搜索框不提供这些数据处理

API 依据：

- [iOS 27 SDK SwiftUI View.searchable / searchFocused](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对 7089–7093 与 7312–7321 行：searchable 自 iOS 15、searchFocused 自 iOS 18 可用；当前页面使用的均为正式原生 API。
- [iOS 27 SDK SwiftUI searchScopes / SearchScopeActivation](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对 3087–3127 行：存在绑定范围的 searchScopes 与 automatic、onTextEntry、onSearchPresentation 激活选项；声明不保证等同当前常驻菜单栏布局。

专属分析 agent：`/root/audit_group_c/c104`。

<a id="c105"></a>

### C105 · SearchEmptyState

**需原型或产品取舍 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Search/SearchView.swift:234)　置信度：high

当前实现：以 VStack、Image、Text 和调用方按钮组成搜索引导／无结果页，借 orgendaEmptyState 的 ScrollView 居中并在小窗口或大字体下保持内容可达。

系统候选：ContentUnavailableView(label:description:actions:)；其通用构造器可容纳现有文案和恢复按钮。

判断：系统 ContentUnavailableView 已支持标题、说明与动作槽，可减少手动图标和文字样式；但源码明确记载其在搜索激活及键盘调整时曾产生二次位移，当前统一 VStack 正为规避此问题。SDK 声明只能证明 API 存在，不能证明 iOS 27 已消除位移；需验证动画和滚动可达性后再替换。

预期收益：若原型证明等价，可删去手动图标字号、间距及文本样式；分类文案、恢复动作和适配滚动容器仍需保留。

必须保留：引导与无结果两种本地化标题、分类说明及查询词；按类别提供 Search All，并保留 Clear Search 恢复操作和 accessibilityIdentifier；装饰图标对辅助功能隐藏、标题具备 header trait；键盘出现／收起时整体位置稳定，大字体或短窗口下按钮可滚动到达

验证要求：OrgendaUITests/UIUXPolishUITests.swift:86 — testReplacingSearchQueryAndChangingScopeShowsCurrentResults 覆盖无结果、Search All 可点击及保留查询词。；OrgendaUITests/DatePresentationUITests.swift:300、305 — testSimplifiedChinese / testTraditionalChinese 经 verifyChinese 检查本地化无结果标题与查询说明。；需要 iOS 27 原型验证搜索激活、键盘显示／交互收起时是否二次位移，并检查横屏短窗口及辅助功能大字体下两个恢复按钮可达；本次未运行。

代码依据：

- [Orgenda/Features/Search/SearchView.swift:181](/Users/roifewu/.config/orgenda/Orgenda/Features/Search/SearchView.swift:181) — 引导和无结果调用分别提供分类说明、Search All 与 Clear Search，保持业务内容。
- [Orgenda/Features/Search/SearchView.swift:231](/Users/roifewu/.config/orgenda/Orgenda/Features/Search/SearchView.swift:231) — 注释记录 ContentUnavailableView 二次位移；当前单一 VStack 包含隐藏装饰图标及标题辅助功能 trait。
- [Orgenda/DesignSystem/Layout/OrgendaEmptyState.swift:6](/Users/roifewu/.config/orgenda/Orgenda/DesignSystem/Layout/OrgendaEmptyState.swift:6) — ScrollView 配合居中对齐锚点与按尺寸回弹，保障空态可达性。

API 依据：

- [iOS 27 SwiftUI ContentUnavailableView 声明](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：22636–22687：iOS 17 起提供 label/description/actions 构造器及 search(text:)；自定义分类说明和动作应使用前者。接口未承诺键盘过渡布局与当前实现一致。

专属分析 agent：`/root/audit_group_c/c105`。

<a id="c106"></a>

### C106 · AppearanceSettingsView

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/AppearanceSettingsView.swift:3)　置信度：high

当前实现：以系统 List、Section 和 inline Picker 显示 System／Light／Dark 三选项，用 AppStorage("appearance") 持久化选择，并配置导航标题、主题色与无障碍标识。

系统候选：无需替代；当前已采用 SwiftUI Picker(.inline)、List(.insetGrouped) 与 AppStorage。

判断：此页没有自绘选中态或手工点击处理，选择和持久化均由系统 API 完成；SettingsView 的 appearance 导航目的地仍实例化它，并支持搜索带初始目的地打开。主设置页虽已有同值 menu Picker，但删除独立页属于导航产品调整，不能据此视为未使用；改用其他容器没有实质替代收益。

预期收益：保持短小的原生设置页封装；没有可移除的自定义控件逻辑，也无需引入 UIKit 桥接。

必须保留：System／Light／Dark 的既有存储值及 appearance 键；搜索进入 appearance 独立目的地与系统返回导航；选项无障碍标识和本地化文本；修改偏好后现有窗口及已显示 sheet 立即更新

验证要求：OrgendaUITests/ConfigurationUITests.swift:5 testSettingsPanelNavigationAndAppearance 覆盖主设置页菜单切换、浅深色实际像素和恢复 System；它并未直接覆盖此独立目的地。；如调整导航，需补充从搜索进入 Appearance 独立页、三项选择持久化、返回及已展示 sheet 即时更新的交互验证；本审查未运行测试。

代码依据：

- [Orgenda/Features/Settings/AppearanceSettingsView.swift:4](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/AppearanceSettingsView.swift:4) — AppStorage 绑定原生 inline Picker；List/Section 与导航配置构成整页。
- [Orgenda/Features/Settings/SettingsView.swift:69](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/SettingsView.swift:69) — appearance 目的地实例化 AppearanceSettingsView；SearchView.swift:59 将搜索目的地传入 SettingsView。
- [Orgenda/Features/Root/OrgendaRootView.swift:102](/Users/roifewu/.config/orgenda/Orgenda/Features/Root/OrgendaRootView.swift:102) — 监听 appearance 更新；Orgenda/App/OrgendaQuickActions.swift:42 将 Light/Dark/System 映射窗口 overrideUserInterfaceStyle。

API 依据：

- [iOS 27 SDK SwiftUI：InlinePickerStyle 与 AppStorage](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对第 8886–8906 行 inline PickerStyle 为系统样式（iOS 14 起）；第 9163–9192 行 AppStorage 提供 Binding 投影及 String/UserDefaults 初始化，满足 iOS 27 部署要求。

专属分析 agent：`/root/audit_group_c/c106`。

<a id="c107"></a>

### C107 · ConfigurationKeywordEditor

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/ConfigurationEditors.swift:3)　置信度：high

当前实现：使用 NavigationStack、Form、LabeledContent、TextField、原生 navigationLink Picker 和 alert 编辑工作流状态，并负责实时预览、输入校验及异步保存草稿保护。

系统候选：无实质替代；现有 Form 与 Picker 已是系统组件。ColorPicker 不等价于包含 default 的固定 ConfigurationColor 枚举。

判断：界面交互已由原生表单和导航式选择器提供，剩余逻辑负责 Org 关键字及快捷键唯一性、工作流完整性、失败后保留草稿和保存期间防重复提交。颜色使用可序列化枚举且具有默认值语义，ColorPicker 的 Color/CGColor 绑定不能直接代替；没有可移除这些业务职责的等价系统控件。

预期收益：保留当前业务封装；更换底层控件不会减少必要逻辑，改用自由颜色选择反而增加映射与校验。

必须保留：现有关键字只读，新关键字校验格式与重名；快捷键单字符且不得与其他状态重复；默认图标及颜色语义与即时预览；取消变更需确认，修改中或保存中禁止交互关闭；异步保存失败保留草稿，成功后关闭

验证要求：OrgendaUITests/ConfigurationUITests.swift:115 testWorkflowStateSheetAndContextActionsPersist 覆盖外观与快捷键持久化、取消草稿、重复关键字失败后保留输入；本次仅静态阅读，未运行。；OrgendaTests/Domain/Org/WorkspaceConfigurationTests.swift:86 testSparseKeywordOverridesPreserveDefaultAppearance 与 :103 testExplicitStateStyleSurvivesSaveAndDoesNotAffectOtherStates 覆盖默认外观及显式配色语义；未运行。；如后续改动交互，需补验保存失败、保存中重复点击和下拉关闭保护。

代码依据：

- [Orgenda/Features/Settings/ConfigurationEditors.swift:27](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/ConfigurationEditors.swift:27) — 原生 Form、TextField 与 navigationLink Picker 组成编辑界面，保留枚举选项及预览。
- [Orgenda/Features/Settings/ConfigurationEditors.swift:160](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/ConfigurationEditors.swift:160) — confirm 校验 Org token、快捷键与候选配置，等待保存成功才 dismiss；错误留在当前草稿。
- [Orgenda/Features/Settings/ConfigurationSettingsView.swift:94](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/ConfigurationSettingsView.swift:94) — 生产 sheet 调用编辑器，将状态加入序列后交给 persist 保存。

API 依据：

- [SwiftUI NavigationLinkPickerStyle / interactiveDismissDisabled（iOS 27 SDK）](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：24950–24975 声明 navigationLink 原生 Picker 样式，30149–30152 声明交互关闭禁用 API；均适用于最低部署 iOS 27。
- [SwiftUI ColorPicker（iOS 27 SDK）](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：31262–31309 的初始化器绑定 Color 或 CGColor，没有直接绑定业务 ConfigurationColor 枚举及 default 语义的 API。

专属分析 agent：`/root/audit_group_c/c107`。

<a id="c108"></a>

### C108 · ConfigurationTemplateEditor

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/ConfigurationEditors.swift:205)　置信度：high

当前实现：捕获模板编辑页，以 NavigationStack、Form、Picker、TextEditor、LabeledContent/TextField、DisclosureGroup、Toggle、Stepper 和系统 sheet/alert 组成，管理模板草稿、验证、预览及异步保存。

系统候选：继续使用现有 SwiftUI 原生表单与输入控件；未发现可整体替换此业务编辑器的系统组件。

判断：界面控件与多行输入已采用系统实现；剩余逻辑负责工作区相对路径、Org 占位符、标题目标及快捷键校验，并在保存失败时保留草稿、取消时确认丢弃。系统表单不提供这些模板语义或配置持久化契约。预览通过现有捕获页的只预览模式复用，替换整体不能实质减少必要复杂度。

预期收益：保留现有封装；未发现通过更换系统控件可获得的实质简化，业务校验和编辑状态仍需存在。

必须保留：模板类型、目标类型、相对 .org 路径与逐行标题路径；Org 源码、占位符验证及不保存的模板试用；快捷键唯一性、分组、前插与空行设置；保存中禁用交互、失败保留草稿、未保存关闭确认；通过父页保存闭包保留配置修订与工作区会话检查

验证要求：OrgendaUITests/ConfigurationUITests.swift:487 — testTemplateValidationKeepsDraftAndCancelRequiresDiscard 覆盖非法路径、草稿保留、继续编辑、修正保存和丢弃。；OrgendaUITests/ConfigurationUITests.swift:602 — testNativeTemplateFileSelectionSearchAndReselect 覆盖文件选择、搜索、重选返回和保存路径。；OrgendaTests/Domain/Org/WorkspaceConfigurationTests.swift:227 — testCapturePromptExpansionDoesNotInterpretAnswers 覆盖占位符展开与不支持语法。；本次仅静态审查，未执行测试；预览弹窗返回后的输入连续性及保存失败交互需运行时验证。

代码依据：

- [Orgenda/Features/Settings/ConfigurationEditors.swift:230](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/ConfigurationEditors.swift:230) — 原生表单控件、预览 sheet、关闭保护及后续 validateFields/confirm 实现。
- [Orgenda/Features/Settings/ConfigurationSettingsView.swift:87](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/ConfigurationSettingsView.swift:87) — 实际 sheet 调用把编辑结果交由 persist 保存；同文件:522 的 persistSnapshot 检查工作区会话与配置修订。
- [Orgenda/Features/ItemEditor/ConfiguredCaptureView.swift:95](/Users/roifewu/.config/orgenda/Orgenda/Features/ItemEditor/ConfiguredCaptureView.swift:95) — previewOnly 使用模板预览标题并隐藏 Capture 操作，复用 render 生成 Org。

API 依据：

- [iOS 27 SwiftUI SDK：TextEditor、TextField、Form、DisclosureGroup、interactiveDismissDisabled](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对 TextEditor(text:)（3889）、TextField 的 prompt/axis 初始化（6567）、Form（17167）、DisclosureGroup（18041）和 interactiveDismissDisabled（30151）；现有多行输入与关闭保护均是最低 iOS 27 可用的系统 API。

专属分析 agent：`/root/audit_group_c/c108`。

<a id="c109"></a>

### C109 · ConfigurationEditorErrorSection

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/ConfigurationEditors.swift:436)　置信度：high

当前实现：在关键词与捕获模板编辑表单中，使用系统 Section 和 Label 显示红色错误图标与完整换行消息，并提供统一可访问性标识。

系统候选：无实质替代；现有 SwiftUI Section + Label 已是对应原生组合。

判断：实现没有自绘布局或交互，仅统一两个表单的错误展示。Section、Label 和 fixedSize 均为系统 API，直接内联只会重复样式与标识。两处调用方已同时使用原生 alert；用弹窗替掉表单错误行会改变展示位置与时机，不能视为等价简化。

预期收益：保留可复用的短封装；没有值得替换的自定义控件复杂度。

必须保留：错误存在时在表单顶部显示消息与警告图标；长消息可按可用宽度换行并保留纵向内容；统一 configuration.editor.error 标识；错误状态由编辑器管理

验证要求：OrgendaUITests/ConfigurationUITests.swift:487 testTemplateValidationKeepsDraftAndCancelRequiresDiscard 覆盖校验弹窗及草稿保留；未直接断言 configuration.editor.error。；仅静态审查，未运行测试；若调整展示方式，应检查长消息、动态字体以及弹窗关闭后错误行随 error 清除的行为。

代码依据：

- [Orgenda/Features/Settings/ConfigurationEditors.swift:436](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/ConfigurationEditors.swift:436) — Section 内仅组合 Label、红色样式、fixedSize 与可访问性标识。
- [Orgenda/Features/Settings/ConfigurationEditors.swift:30](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/ConfigurationEditors.swift:30) — 关键词表单按 error 条件调用；233 行模板表单复用同一组件。
- [OrgendaUITests/ConfigurationUITests.swift:487](/Users/roifewu/.config/orgenda/OrgendaUITests/ConfigurationUITests.swift:487) — 校验失败后确认弹窗、保留模板草稿并允许修正保存。

API 依据：

- [iOS 27 SDK SwiftUI Section 与 Label](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：14090 行 Section(content:)；30928 行 Label(StringProtocol, systemImage:)。现有用法属于系统组件，最低 iOS 27 可用。
- [iOS 27 SDK SwiftUICore View.fixedSize(horizontal:vertical:)](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUICore.framework/Modules/SwiftUICore.swiftmodule/arm64e-apple-ios.swiftinterface)：1594 行提供现用的横纵向尺寸约束修饰器。

专属分析 agent：`/root/audit_group_c/c109`。

<a id="c110"></a>

### C110 · ConfigurationTemplateFilePicker

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/ConfigurationEditors.swift:449)　置信度：high

当前实现：以原生 List(selection:) 展示工作区 Org 文档，使用 searchable、Label 与 ContentUnavailableView；按相对路径搜索和自然排序，选中后写回模板草稿并返回。

系统候选：保留 List(selection:) + searchable + ContentUnavailableView；fileImporter 返回文件 URL，并非现有工作区文档的相对路径选择器，无实质等价替代。

判断：当前已把单选、搜索入口及空态交给系统控件；剩余代码负责工作区文档范围、相对路径排序过滤和草稿写回后退出。调用方只传入 Org 文档，并保留手输新路径。fileImporter 的 URL 导入接口不能直接取代此数据选择语义；继续包装其他原生控件没有明确复杂度收益。

预期收益：没有可确认的替代收益；保留短小业务组合即可继续获得原生列表、搜索和空态行为。

必须保留：仅展示调用方提供的工作区 Org 文档，以相对路径为身份和写回值；路径大小写不敏感搜索、自然排序及两类空态；选中当前或其他路径均返回编辑页，之后由父编辑器保存草稿；父编辑器仍可手输尚不存在的新文件路径

验证要求：OrgendaUITests/ConfigurationUITests.swift:602 — testNativeTemplateFileSelectionSearchAndReselect 已覆盖当前项重选返回、搜索过滤、另选路径与保存持久化；本次只读取，未运行。；若后续调整选择机制，应在 iOS 27 验证同一路径重选仍返回，并补充无文档、搜索无结果及自然排序的交互检查。

代码依据：

- [Orgenda/Features/Settings/ConfigurationEditors.swift:316](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/ConfigurationEditors.swift:316) — 手输路径与导航入口并存，传入 kind == .org 文档并绑定模板 target.path。
- [Orgenda/Features/Settings/ConfigurationEditors.swift:455](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/ConfigurationEditors.swift:455) — 路径过滤排序、可选单选绑定写回并 dismiss，原生 List/searchable/ContentUnavailableView 构成完整页面。
- [OrgendaUITests/ConfigurationUITests.swift:602](/Users/roifewu/.config/orgenda/OrgendaUITests/ConfigurationUITests.swift:602) — 专项 UI 测试明确要求当前路径重选返回及路径保存。

API 依据：

- [SwiftUI List.init(selection:content:)](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：8155–8161 行确认 iOS 可用的 Binding<SelectionValue?> 单选初始化器；现组件已经使用该原生能力。
- [SwiftUI searchable 与 ContentUnavailableView.search(text:)](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：7089–7093 行及 22682–22687 行确认分别自 iOS 15 和 iOS 17 可用，满足 iOS 27 部署要求。
- [SwiftUI fileImporter(isPresented:allowedContentTypes:onCompletion:)](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：9048–9055 行确认导入接口按 UTType 过滤并返回 URL/URL 数组，不接收工作区文档数据集或相对路径绑定。

专属分析 agent：`/root/audit_group_c/c110`。

<a id="c111"></a>

### C111 · ConfigurationFieldError

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/ConfigurationFieldSupport.swift:93)　置信度：high

当前实现：以原生 Label 显示传入的校验文本与感叹号图标，统一 footnote、红色和纵向完整展开；没有自定义绘制、状态或交互。

系统候选：现有 SwiftUI Label(_:systemImage:) 已是合适的系统组件；无实质替代项。

判断：此组件只是原生 Label 与三个系统修饰符的共享封装，已被路径、归档规则和整数输入复用。直接在调用处展开仍需相同样式与换行配置，反而复制代码；错误是否出现由业务校验决定，弹窗也不等价于不中断输入的行内提示。保留封装即可。

预期收益：保留当前轻量封装统一多处错误样式；更换系统控件没有可辨识的复杂度收益。

必须保留：保留传入的本地化错误文本；错误图标与文字共同表达状态；长错误文本可换行并纵向完整显示；提示保持行内呈现，不打断草稿编辑

验证要求：OrgendaUITests/ConfigurationUITests.swift:440 testSettingsDraftSurvivesValidationAndProtectsNavigation 已覆盖无效路径出现行内文本、无保存弹窗且保留草稿；本次仅读取，未运行。；若调整排版，需检查窄屏及大字号下长错误文字的完整可见性。

代码依据：

- [Orgenda/Features/Settings/ConfigurationFieldSupport.swift:93](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/ConfigurationFieldSupport.swift:93) — 实现仅含 Label、font、foregroundStyle、fixedSize；同文件156行用于整数范围错误。
- [Orgenda/Features/Settings/ConfigurationFilesSections.swift:144](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/ConfigurationFilesSections.swift:144) — 路径校验消息使用本组件；105、170、238行另用于归档、路径列表及新增路径。
- [OrgendaUITests/ConfigurationUITests.swift:440](/Users/roifewu/.config/orgenda/OrgendaUITests/ConfigurationUITests.swift:440) — 编辑无效路径时断言行内消息与草稿保留，并断言不出现保存错误弹窗。

API 依据：

- [iOS 27 SDK SwiftUI.Label](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：30895–30928行确认 Label 及 StringProtocol 标题与 systemImage 初始化器为原生 API，iOS 14 起可用。
- [iOS 27 SDK SwiftUI View.fixedSize(horizontal:vertical:)](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUICore.framework/Modules/SwiftUICore.swiftmodule/arm64e-apple-ios.swiftinterface)：1589–1596行确认尺寸修饰符为系统 API，iOS 13 起可用；9772和15165行存在 Color.red 与 Font.footnote。

专属分析 agent：`/root/audit_group_c/c111`。

<a id="c112"></a>

### C112 · ConfigurationLogRulePicker

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/ConfigurationFieldSupport.swift:103)　置信度：high

当前实现：使用系统 Picker、Text 和 tag，将可本地化标题与 LogRule 双向绑定封装为不记录、时间戳、询问备注三个选项。

系统候选：已采用 SwiftUI Picker；没有可进一步替换并减少实质复杂度的系统组件。

判断：组件没有自绘、手势或自定义选择状态，交互已经由系统 Picker 提供。五个生产调用共享三个业务枚举值和文案，关键词编辑页还通过父级应用 navigationLink 样式。展开为各处 Picker 只会复制映射，无法省去领域配置和绑定，因此保留这一短封装。

预期收益：保留可集中维护五处选择器的业务文案；改写或引入 UIKit 桥接没有实质简化收益。

必须保留：none、time、note 三个枚举值与对应本地化文案的映射；调用者提供的标题、双向绑定及父级 Picker 样式；工作区设置经 submit 自动保存，关键词编辑维持草稿绑定

验证要求：OrgendaTests/Domain/Org/WorkspaceConfigurationTests.swift:6 — testClassicWorkflowPresetPreservesEveryOtherWorkspaceSetting 覆盖已有日志配置保留。；OrgendaTests/Domain/Org/OrgWorkflowOperationsTests.swift:16 — testOpenStatesFollowConfiguredLoggingWithoutClosingTimestamp 覆盖配置日志行为。；检索 OrgendaTests 与 OrgendaUITests 未发现该 Picker 三选项的直接交互测试；若后续调整样式，需验证五处选中值回写及 navigationLink 返回行为。本次仅静态审查，未运行测试。

代码依据：

- [Orgenda/Features/Settings/ConfigurationFieldSupport.swift:103](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/ConfigurationFieldSupport.swift:103) — 实现仅为原生 Picker 和三个带 LogRule 标签的 Text。
- [Orgenda/Features/Settings/ConfigurationSettingsView.swift:453](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/ConfigurationSettingsView.swift:453) — 完成、改期、修改截止日期三处复用；489 行 binding 写入 submit 并安排自动保存。
- [Orgenda/Features/Settings/ConfigurationEditors.swift:92](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/ConfigurationEditors.swift:92) — 进入与离开状态两处复用，父级 Section 设置 navigationLink 样式。

API 依据：

- [SwiftUI Picker 与 NavigationLinkPickerStyle — iOS 27 SDK 声明](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：18128、18155 行确认 Picker 接受 Hashable 选择值及 LocalizedStringKey/Binding 初始化；24949 行确认 navigationLink 样式自 iOS 16 可用，符合最低 iOS 27。

专属分析 agent：`/root/audit_group_c/c112`。

<a id="c113"></a>

### C113 · ConfigurationIntegerField

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/ConfigurationFieldSupport.swift:118)　置信度：high

当前实现：组合 LabeledContent、数字键盘 TextField、菜单 Picker 与错误 Label；保存原始文本，以 Int.min 标记无法解析的编辑，支持范围校验、常用值及外部数值同步。

系统候选：现有控件均为 SwiftUI 系统组件。TextField(value:format:) 可管理数值转换；Stepper(value:in:) 可限制范围，但没有能完整移除本封装的等价替代。

判断：唯一生产调用编辑重归档标题层级。关键逻辑是无效文本立即污染草稿，使保存校验拒绝旧值。Apple 明确非可选数值 TextField 解析失败会保留旧值，不等价；可选数值版本仍需适配、校验及原文保留。Stepper 会改变直接输入与预设交互。现有代码已是短小系统控件组合，保留更合理。

预期收益：没有已证明的实质替换收益；保留可避免为无效编辑与预设展示重新增加状态桥接。

必须保留：无法解析、清空和越界输入立即显示错误并阻止持久化；保留编辑中的原始文本及不在预设中的当前选择；菜单选择预设后同步文本，外部有效值更新同步字段；1...99 范围、数字键盘、无障碍标识及带字段名的预设菜单标签

验证要求：已检索 OrgendaTests 与 OrgendaUITests 的 ConfigurationIntegerField、refileMaxLevel 及对应标识，未发现该字段的直接测试；未运行构建或测试。；若尝试数值 TextField，需原型验证清空、非数字粘贴、溢出、0/100、前导零、预设切换以及无效编辑立即离开页面时不会保存旧数值。

代码依据：

- [Orgenda/Features/Settings/ConfigurationFieldSupport.swift:118](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/ConfigurationFieldSupport.swift:118) — 字符串状态、Int.min 哨兵、双向同步、预设 Picker 和范围错误组成该字段。
- [Orgenda/Features/Settings/ConfigurationFilesSections.swift:53](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/ConfigurationFilesSections.swift:53) — 唯一生产调用绑定 refileMaxLevel，范围 1...99，预设 1/2/3/5/10。
- [Orgenda/Features/Settings/ConfigurationSettingsView.swift:527](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/ConfigurationSettingsView.swift:527) — persistSnapshot 先调用 ConfigurationSettingsFieldValidation.message；后者在 ConfigurationFieldSupport.swift:45 拒绝非法层级。

API 依据：

- [iOS 27 SDK：TextField、LabeledContent、Stepper](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：确认 TextField 字符串绑定与可选/非可选 ParseableFormatStyle 初始化器；Stepper 支持 ClosedRange；均可用于最低 iOS 27。
- [Apple TextField init(_:value:format:prompt:) 非可选数值](https://developer.apple.com/documentation/swiftui/textfield/init(_:value:format:prompt:)-7flsn)：官方文档搜索摘要明确：解析失败不更新绑定，结束编辑时恢复最近有效值。
- [Apple TextField init(_:value:format:prompt:) 可选数值](https://developer.apple.com/documentation/swiftui/textfield/init(_:value:format:prompt:)-6ug7k)：官方文档搜索摘要明确：解析失败设为 nil；此 API 存在，但不能直接承担当前原始文本、哨兵模型及预设展示约定。

专属分析 agent：`/root/audit_group_c/c113`。

<a id="c114"></a>

### C114 · ConfigurationFilesSections

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/ConfigurationFilesSections.swift:3)　置信度：high

当前实现：用原生 Section、DisclosureGroup、Picker、LabeledContent、TextField 和 Button 组织日程来源、默认路径、归档规则及 refile 设置，实时展示匹配文件和归档目的地。

系统候选：无实质替代；保留现有 SwiftUI Section 与原生表单控件组合。

判断：该组件没有自行实现表单控件，主要责任是将工作区文件、配置绑定和真实 Org 规则预览组合成设置分组。归档示例选择、无文件时回退、恢复默认规则及字段校验均属业务逻辑；系统 Section、Picker 或文件导入器不能整体接管这些语义，继续替换只会移动代码。

预期收益：保留薄业务组合，避免重复封装原生控件；没有可确认的进一步替换收益。

必须保留：配置变更通过父视图 submit 进入自动保存流程；来源与排除规则的实时匹配预览；归档来源选择、空工作区回退、文件路径及标题预览；恢复默认归档规则、相对路径与 Org 规则校验；允许选择或输入工作区内的未来路径

验证要求：OrgendaTests/Domain/Org/WorkspaceConfigurationTests.swift:23 — testSettingsPreviewUsesRealAgendaAndArchiveRules 覆盖实际日程过滤、归档预览及无效规则。；OrgendaUITests/ConfigurationUITests.swift:563 — testNativePathSelectionPreservesOrderAndUnloadedPaths 覆盖默认位置选择与配置持久化；本次只读审查未运行。；归档区域尚需交互验证：无 Org 文件时的来源回退、切换示例文件、恢复默认规则、无效规则错误展示；未发现该区域专用 UI 测试。

代码依据：

- [Orgenda/Features/Settings/ConfigurationFilesSections.swift:16](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/ConfigurationFilesSections.swift:16) — 四类设置以原生 Section 组合；归档区使用原生选择、披露和文本输入控件。
- [Orgenda/Features/Settings/ConfigurationSettingsView.swift:443](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/ConfigurationSettingsView.swift:443) — filesPage 在 List 内调用本组件，Binding setter 使用 submit，后者触发自动保存。
- [Orgenda/Features/Settings/ConfigurationFieldSupport.swift:64](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/ConfigurationFieldSupport.swift:64) — 目录、日程及归档预览复用真实数据与 OrgWorkflowOperations；归档规则先经共享校验。

API 依据：

- [iOS 27 SDK SwiftUI：LabeledContent、DisclosureGroup、Picker、TextField(axis:)](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：核对 LabeledContent（5017 行，iOS 16）、DisclosureGroup（18041 行，iOS 14）、Picker（18128 行）及多行 TextField（6556 行，iOS 16）声明，均已用于此组件且满足最低 iOS 27；fileImporter（9053 行）返回 URL，不提供工作区规则配置语义。

专属分析 agent：`/root/audit_group_c/c114`。

<a id="c115"></a>

### C115 · ConfigurationPathField

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/ConfigurationFilesSections.swift:113)　置信度：high

当前实现：以 LabeledContent、纵向 TextField、菜单样式 Picker 和错误提示组合配置路径输入；支持自由输入及已加载位置选择。

系统候选：继续使用现有 SwiftUI TextField、LabeledContent、Picker(.menu)；无实质替代项。

判断：组件已经使用系统输入与选择控件，自定义部分仅统一相对路径配置、候选值和错误反馈。菜单为不在候选中的当前路径保留 tag，允许尚未创建或未加载的位置；单独 Picker 会丢失自由输入，单独 TextField 会丢失现有位置选择。该封装用于三个默认位置，保留可避免重复业务配置。

预期收益：没有值得实施的系统替换；保留短封装，避免在 Inbox、附件目录和日志目录重复配置。

必须保留：任意相对路径输入及未加载/未创建位置的当前值；Inbox 必须为 .org 文件，目录字段使用相对路径校验；无候选时隐藏选择器；不在候选中的当前值仍有匹配 tag；输入期间保留无效草稿、就地显示错误及可访问性标识/值

验证要求：OrgendaUITests/ConfigurationUITests.swift:440 testSettingsDraftSurvivesValidationAndProtectsNavigation 覆盖无效 Inbox 草稿及就地错误保留。；OrgendaUITests/ConfigurationUITests.swift:564 testNativePathSelectionPreservesOrderAndUnloadedPaths 覆盖 Inbox 原生菜单选择、字段同步及保存。；本次仅静态阅读上述测试，未运行；若调整控件组合，应补查空候选及当前路径不在候选时的菜单/VoiceOver 表现。

代码依据：

- [Orgenda/Features/Settings/ConfigurationFilesSections.swift:37](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/ConfigurationFilesSections.swift:37) — 三个默认位置复用该字段，Inbox 单独开启 Org 文件后缀要求。
- [Orgenda/Features/Settings/ConfigurationFilesSections.swift:121](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/ConfigurationFilesSections.swift:121) — 原生文本输入、菜单选择、自定义路径 tag 与错误反馈组成完整字段。
- [Orgenda/Features/Settings/ConfigurationFieldSupport.swift:5](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/ConfigurationFieldSupport.swift:5) — 校验工作区相对路径，禁止越界路径并按需校验 .org 后缀。

API 依据：

- [SwiftUI LabeledContent / TextField / MenuPickerStyle SDK declarations](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对 LabeledContent（5016 起，iOS 16）、TextField(_:text:axis:)（6554 起，iOS 16）及 PickerStyle.menu（30526 起，iOS 14），最低 iOS 27 可直接使用，当前实现已采用。

专属分析 agent：`/root/audit_group_c/c115`。

<a id="c116"></a>

### C116 · ConfigurationPathSelectionRow

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/ConfigurationFilesSections.swift:150)　置信度：high

当前实现：以原生 NavigationLink 打开路径选择页；标签由 VStack、LabeledContent 和 Text 组成，显示空值说明或两行路径摘要，并附首个路径校验错误。

系统候选：继续使用现有 NavigationLink 与 LabeledContent；没有可删除此业务封装且保留摘要、错误及参数传递的独立系统控件。

判断：该行已直接使用系统导航和键值展示控件，三个生产调用分别绑定议程包含、排除及归档重定位目标。剩余逻辑是空选项文案、路径摘要、校验信息和选择页参数转交。改成单一标题 NavigationLink 会丢失摘要与错误，拆回各调用点则只是复制原生组合，不能减少实质自定义行为。

预期收益：保留短小复用封装；进一步替换没有明显复杂度收益。

必须保留：路径数组绑定及候选路径、目录集合、requiresOrgFile 参数传递；各场景独立的空选择文案与最多两行路径摘要；首个相对路径校验错误及稳定 accessibilityIdentifier

验证要求：OrgendaUITests/ConfigurationUITests.swift:564 testNativePathSelectionPreservesOrderAndUnloadedPaths：通过该行进入选择页，覆盖未加载路径、顺序及新增路径持久化；本次仅阅读，未执行。；现有测试未专门断言该行的空值文案、两行摘要与错误标签；若改动标签组合，应检查这三类状态及辅助功能朗读。

代码依据：

- [Orgenda/Features/Settings/ConfigurationFilesSections.swift:159](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/ConfigurationFilesSections.swift:159) — 原生 NavigationLink 目标与自定义标签组合，随后附固定标识符。
- [Orgenda/Features/Settings/ConfigurationFilesSections.swift:19](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/ConfigurationFilesSections.swift:19) — 包含、排除路径及第 50 行 refile 调用共用此封装，传入不同绑定和空值说明。
- [OrgendaUITests/ConfigurationUITests.swift:576](/Users/roifewu/.config/orgenda/OrgendaUITests/ConfigurationUITests.swift:576) — 用 configuration.agenda.sources 点击此导航行，随后验证选择状态返回并持久化。

API 依据：

- [SwiftUI NavigationLink.init(destination:label:)](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：第 14228–14243 行确认支持 destination 与 label 内容闭包，iOS 13 起可用；当前导航已采用该系统 API。
- [SwiftUI LabeledContent.init(_:content:)](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：第 5016–5037 行确认 LabeledContent 及本地化标题、自定义内容初始化，iOS 16 起可用，满足 iOS 27 最低部署。

专属分析 agent：`/root/audit_group_c/c116`。

<a id="c117"></a>

### C117 · ConfigurationPathSelectionView

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/ConfigurationFilesSections.swift:178)　置信度：high

当前实现：以原生 List(selection:) 多选列表、Section、Label、TextField 和 Button 编辑路径数组；将集合选择映射回有序配置，支持未加载路径、新路径校验、添加及清空。

系统候选：继续使用现有 SwiftUI List(selection:) 与 selectionDisabled；未发现能同时接管有序路径配置、手动输入及校验的更简系统替代。

判断：多选指示与选择行为已交给系统 List，操作行通过 selectionDisabled 排除。自定义部分负责把无序选择集合写回有序数组、合并未加载路径，并校验及追加用户输入；这些是业务语义。现有原生组合已覆盖所需交互，删除包装或改用其他选择控件不能消除这些逻辑。

预期收益：维持系统多选实现和小型业务适配层即可；当前无明确可削减的自定义控件复杂度。

必须保留：保留已选路径的原有顺序，新选项按展示顺序追加；候选集合包含配置中仍未加载的路径，并区分文件与目录图标；允许输入尚不存在的工作区相对路径；refile 新路径须以 .org 结尾；清空选择、空值说明、操作行不可选择，以及现有可访问性标识

验证要求：OrgendaUITests/ConfigurationUITests.swift:564 testNativePathSelectionPreservesOrderAndUnloadedPaths 已覆盖移除/新增选择、保留未加载路径、手动新增及持久化顺序；本次仅阅读，未执行。；若后续调整选择结构，需在 iOS 27 验证原生范围选择写回顺序及新增路径输入区不被编辑模式拦截，并覆盖非法相对路径与 refile 非 .org 输入。

代码依据：

- [Orgenda/Features/Settings/ConfigurationFilesSections.swift:19](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/ConfigurationFilesSections.swift:19) — 生产入口用于 agenda 包含/排除路径，:50 用于 refile；:161 导航到该组件。
- [Orgenda/Features/Settings/ConfigurationFilesSections.swift:188](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/ConfigurationFilesSections.swift:188) — allChoices 合并配置与候选，selectedPaths 保留既有顺序；:201 使用系统多选 List，:224 起提供校验后新增。
- [OrgendaUITests/ConfigurationUITests.swift:564](/Users/roifewu/.config/orgenda/OrgendaUITests/ConfigurationUITests.swift:564) — 现有 UI 测试断言未加载路径保留和最终有序数组。

API 依据：

- [SwiftUI List(selection:content:)、selectionDisabled(_:) 与 EditMode 本地 SDK 声明](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：核对 :8154 起 List 接受 Binding<Set<SelectionValue>>；:3245 selectionDisabled 在 iOS 17 起可用；:21861 起 EditMode.active 与 EnvironmentValues.editMode 可用，均满足 iOS 27 部署目标。

专属分析 agent：`/root/audit_group_c/c117`。

<a id="c118"></a>

### C118 · ConfigurationImportEditor

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/ConfigurationImportEditor.swift:3)　置信度：high

当前实现：粘贴配置 JSON 的原生表单页，以 NavigationStack、Form、TextEditor、Button、Label 和 confirmationDialog 组合，负责本地文本、校验错误及放弃编辑保护。

系统候选：继续使用现有 SwiftUI TextEditor 与 confirmationDialog；未发现能消除业务状态而等价替换整页的系统组件。

判断：编辑器已经采用原生多行输入和系统导航、确认弹层。其额外状态仅承载空白输入禁用、导入异常留在编辑页、非空内容取消确认及阻止交互关闭。父级另有文件导入入口，无法替代可修改的粘贴文本流程；JSON 解析、字段校验和自动保存仍须由业务层完成，没有实质可替换部分。

预期收益：现状已是短小的系统控件业务封装；更换控件不会明显减少复杂度，可能把状态处理转移到父级。

必须保留：保留粘贴原文与失败后的可修改文本，并呈现针对配置错误的说明；纯空白内容不得提交，成功调用导入闭包后才关闭；非空输入取消须确认放弃，并禁止交互关闭；维持 JSON 等宽输入、关闭自动大写和纠错及可访问性标识

验证要求：OrgendaTests/Domain/Org/WorkspaceConfigurationTests.swift:184 testInvalidConfigCannotBeAccepted 覆盖不合法配置拒绝；未运行。；OrgendaTests/Services/Workspace/WorkspaceConnectionTests.swift:72 testImportedConfigurationPreservesExtensionsAndCanRestorePreviousDocument 覆盖扩展字段保留和还原；未运行。；搜索 OrgendaTests 与 OrgendaUITests 未发现 importSource/reviewImport/pasteJSON 的直接 UI 覆盖；若调整此页，应验证错误后文本保留、非空取消确认、空白禁用和下滑关闭保护。

代码依据：

- [Orgenda/Features/Settings/ConfigurationImportEditor.swift:10](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/ConfigurationImportEditor.swift:10) — 原生编辑表单、错误展示、工具栏操作和放弃保护均在此组合。
- [Orgenda/Features/Settings/ConfigurationSettingsView.swift:108](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/ConfigurationSettingsView.swift:108) — pastedImport sheet 实际调用此组件并转交 stageImport；另有文件导入入口。
- [Orgenda/Features/Settings/ConfigurationSettingsView.swift:615](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/ConfigurationSettingsView.swift:615) — stageImport 解析 ConfigurationDocument、执行业务校验并安排自动保存。

API 依据：

- [iOS 27 SDK SwiftUI.TextEditor](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：3889–3892 声明 TextEditor.init(text: Binding<String>)，自 iOS 14 可用；现有页面已经使用该系统多行输入。
- [iOS 27 SDK confirmationDialog / interactiveDismissDisabled](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：22465–22467 与 30149–30151 声明系统确认弹层及布尔关闭保护 API，自 iOS 15 可用；最低 iOS 27 可直接使用，且当前已采用。

专属分析 agent：`/root/audit_group_c/c118`。

<a id="c119"></a>

### C119 · ConfigurationPromptSection

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/ConfigurationPromptView.swift:62)　置信度：high

当前实现：用 Section、DisclosureGroup、可选取的等宽 Text 和 Button 展示按当前配置生成的转换提示词；通过 UIPasteboard 复制，并提供标签、触觉和辅助功能反馈。

系统候选：无有实质收益的替代；展开、文本选择、按钮和剪贴板写入均已采用系统 API。

判断：此组件没有自绘控件或自制交互，实际调用方将当前 draft 传入配置文件页。系统 DisclosureGroup 已负责折叠，Text 已启用选择，复制按钮直接写入 UIPasteboard。剩余状态用于复制反馈及配置变化后重置；提示词生成承载 Org 配置语义，不能由通用系统控件取代。

预期收益：保留此短业务组合可集中管理提示词与复制反馈；更换系统控件没有明确的复杂度收益。

必须保留：预览默认折叠并允许选取完整提示词；预览与复制使用当前配置生成的同一内容；复制后更新本地化标签、触觉及辅助功能播报；配置变更时清除已复制状态

验证要求：OrgendaUITests/ConfigurationUITests.swift:58 testSettingsShowsWorkflowAndCopiesEmacsPrompt 覆盖复制反馈标签、默认折叠及展开后出现提示词；本次仅阅读，未运行。；OrgendaTests/Services/Workspace/WorkspaceStoreTests.swift:178 testEmacsPromptSearchOpensConfigurationPage 覆盖提示词入口搜索。；如未来调整交互，需补验复制内容跟随配置变更、copied 状态重置、文字选择及 VoiceOver 播报；现有上述 UI 测试未直接验证剪贴板内容。

代码依据：

- [Orgenda/Features/Settings/ConfigurationPromptView.swift:62](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/ConfigurationPromptView.swift:62) — 系统控件组合、UIPasteboard 写入、反馈及 onChange 重置。
- [Orgenda/Features/Settings/ConfigurationSettingsView.swift:213](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/ConfigurationSettingsView.swift:213) — configurationFilePage 的 List 将 draft 传给本组件。
- [OrgendaUITests/ConfigurationUITests.swift:103](/Users/roifewu/.config/orgenda/OrgendaUITests/ConfigurationUITests.swift:103) — 点击复制后校验标签，并验证展开前后提示词可见性。

API 依据：

- [iOS 27 SDK SwiftUI DisclosureGroup 与 textSelection 声明](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：核对 DisclosureGroup 的标题与 isExpanded Binding 初始化器（18041–18095）及 textSelection（2336）；分别自 iOS 14、15 提供，当前直接使用系统能力。
- [iOS 27 SDK UIPasteboard.string](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/UIKit.framework/Headers/UIPasteboard.h)：第 108 行声明可写 string 属性，现有复制实现直接采用 UIKit 剪贴板接口。
- [iOS 27 SDK UIAccessibilityPostNotification](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/UIKit.framework/Headers/UIAccessibility.h)：第 521 行声明辅助功能通知函数；现有复制成功播报已接入系统辅助功能。

专属分析 agent：`/root/audit_group_c/c119`。

<a id="c120"></a>

### C120 · ConfigurationSettingsView

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/ConfigurationSettingsView.swift:5)　置信度：high

当前实现：按目的地显示工作流、捕获、文件、提醒和配置页；使用原生 List、Section、Picker、TextField、DisclosureGroup、sheet、alert、fileImporter 与 onMove，集中管理草稿自动保存、导入和退出保护。

系统候选：无实质系统控件替代；现有 List/Section、原生排序及 fileImporter 已覆盖呈现与交互。Form 仅可改变容器语义，不能移除业务保存状态机。

判断：SettingsView 实际复用此页处理五类设置，界面已由原生列表、表单控件、弹窗与文件导入组成。主要复杂度来自自动保存串行化、版本和工作区会话校验、无效草稿保留、默认动作修复确认及替换撤销；系统容器不提供这些业务语义。当前仅在草稿需保护时覆盖返回按钮，保存成功后恢复系统返回，直接删除保护会破坏已有编辑行为。

预期收益：保留现有原生组合；没有已证明可删去主要复杂度的系统替代。业务状态可独立整理，但不属于系统组件替换收益。

必须保留：300 毫秒自动保存及保存期间新草稿继续持久化；无效或失败草稿保留、重试与退出前保存/丢弃选择；配置版本及工作区会话校验，拒绝过期写入；原生状态/模板排序及默认动作修复确认；导入文档扩展字段与最近替换撤销；无未保存修改时恢复系统返回和边缘手势

验证要求：OrgendaUITests/ConfigurationUITests.swift:421 testSettingsDetailPagesSupportEdgeSwipeBack；覆盖各设置目的地原生边缘返回。；OrgendaUITests/ConfigurationUITests.swift:440 testSettingsDraftSurvivesValidationAndProtectsNavigation；覆盖非法输入保留、退出保护、丢弃和纠正后自动保存。；OrgendaTests/Services/Workspace/WorkspaceConnectionTests.swift:72 testImportedConfigurationPreservesExtensionsAndCanRestorePreviousDocument；:92 testFailedConfigurationSaveDoesNotChangeEffectiveSettings；:102 testGUIConfigurationSaveCreatesRootFileAndRejectsStaleRevision。；本次仅阅读源码和既有测试，未运行；任何导航保护改动仍需实机或模拟器验证交互。

代码依据：

- [Orgenda/Features/Settings/SettingsView.swift:72](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/SettingsView.swift:72) — 五类配置目的地实例化本组件，并提供打开工作区的导航回调。
- [Orgenda/Features/Settings/ConfigurationSettingsView.swift:113](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/ConfigurationSettingsView.swift:113) — 仅需保护草稿时隐藏系统返回，使用原生禁用交互关闭、按钮和警告处理退出；列表排序使用 onMove。
- [Orgenda/Features/Settings/ConfigurationSettingsView.swift:498](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/ConfigurationSettingsView.swift:498) — 自动保存、persistSnapshot 的校验与版本保护、saveDraft 的串行循环构成业务复杂度。

API 依据：

- [iOS 27 SwiftUI SDK：fileImporter / DynamicViewContent.onMove](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：9053–9062 行声明系统文件导入；13692 行声明原生排序回调，均满足最低 iOS 27。
- [iOS 27 SwiftUI SDK：navigationBarBackButtonHidden / interactiveDismissDisabled](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：9647、30151 行核对当前使用的系统返回按钮隐藏和交互关闭控制；这些呈现控制仍需应用决定何时保护草稿。

专属分析 agent：`/root/audit_group_c/c120`。

<a id="c121"></a>

### C121 · WorkspaceReminderTimingSections

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/ReminderSettingsView.swift:4)　置信度：high

当前实现：用 Group、Section、Text 组织工作区提前提醒、重复间隔和截止预警设置，通过原生控件行接收绑定并打开编辑器；按实际提醒偏移生成最多六项的文本预览。

系统候选：无有实质收益的替代；Section、Text 已承担系统分组与预览呈现。

判断：该类型没有自绘布局或自制交互，只有原生分组、配置绑定和提醒预览业务规则。调用方已在 List 中使用它，并通过统一绑定进入校验与自动保存流程。系统 Section 和 Text 已覆盖展示职责，但不会计算提醒偏移、截断长序列或连接三项工作区配置；将组合内联只是搬移代码，不能消除这层业务职责。

预期收益：保留现有小型原生组合即可；没有可移除的自定义控件基础设施，改为其他容器没有明确复杂度收益。

必须保留：三项配置继续通过调用方绑定进入统一校验与自动保存流程；提前量和重复间隔变化同步刷新预览，包含开始时刻并对超过六项的序列显示省略号及末尾开始时刻；编辑请求携带正确 ReminderTimingKind，工作区未就绪时由调用方禁用；本地化时间文案、纵向完整显示和 settings.reminders.preview 无障碍标识

验证要求：OrgendaTests/Domain/Org/WorkspaceConfigurationTests.swift:40 — testReminderPreviewMatchesSchedulerIncludingStartAndUnevenIntervals 覆盖整除、不整除、零提前量及无效间隔；本次仅阅读，未运行；OrgendaUITests/ConfigurationUITests.swift:323 — testReminderTimingPresetsCustomValuesAndInvalidDraftPersistence 覆盖预设、自定义、取消无效值及持久化；本次未运行；若修改预览呈现，补查超过六项序列的省略规则、最终 At start 与辅助功能字号下的换行；现有偏移单测未覆盖该显示分支

代码依据：

- [Orgenda/Features/Settings/ReminderSettingsView.swift:10](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/ReminderSettingsView.swift:10) — Group 包含三个原生 Section，预览由偏移数组生成 Text 并保留无障碍标识
- [Orgenda/Features/Settings/ConfigurationSettingsView.swift:463](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/ConfigurationSettingsView.swift:463) — remindersPage 的 List 提供三项配置绑定与编辑回调；489 行绑定经 submit 调度自动保存
- [Orgenda/Features/Settings/ConfigurationFieldSupport.swift:87](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/ConfigurationFieldSupport.swift:87) — reminderOffsets 校验分钟范围、按重复间隔生成偏移并确保包含零

API 依据：

- [iOS 27 SDK — SwiftUI.Section](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：核对 14032 行起 Section 声明及标题、content/header 初始化器；当前分组使用系统 API，最低 iOS 27 可用。
- [iOS 27 SDK — SwiftUICore.Group 与 View.fixedSize](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUICore.framework/Modules/SwiftUICore.swiftmodule/arm64e-apple-ios.swiftinterface)：核对 3241 行起 Group 和 1594 行 fixedSize(horizontal:vertical:) 声明，确认现有组合及文本尺寸行为使用原生能力。

专属分析 agent：`/root/audit_group_c/c121`。

<a id="c122"></a>

### C122 · ReminderTimingRow

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/ReminderSettingsView.swift:96)　置信度：high

当前实现：使用 LabeledContent、Label、带边框 Button 和原生 Picker 展示提醒时长；预设采用分段样式，大字体或非预设值采用菜单样式，并保留自定义编辑入口。

系统候选：无实质替代；现有 Picker(.segmented/.menu)、LabeledContent 与 Button 已是对应系统组件。

判断：该行没有自绘控件，抽象集中承载三类提醒的标签、预设、绑定和可访问性语义。单独使用 Picker 仍需保留自定义编辑按钮、当前非预设值选项及大字体菜单分支，无法减少这些行为代码；现有系统组件组合已直接表达需求，保留更合适。

预期收益：没有有意义的替换收益；保留此薄封装可复用三种提醒设置，避免重复原生控件配置。

必须保留：三类时长的预设、单位及零值专用文案；预设选择通过原绑定更新配置；自定义按钮进入独立编辑器；非预设值始终有匹配 tag，且大字体和非预设状态使用菜单；预设与自定义入口各自清晰的可访问性标签、值及标识符

验证要求：OrgendaUITests/ConfigurationUITests.swift:323 testReminderTimingPresetsCustomValuesAndInvalidDraftPersistence 覆盖预设选择、自定义 37、无效值取消及持久化；仅阅读，未运行。；OrgendaUITests/ConfigurationUITests.swift:547 testReminderNativeMenuAtAccessibilitySize 覆盖辅助功能字号菜单选择与两个入口的不同朗读标签；仅阅读，未运行。

代码依据：

- [Orgenda/Features/Settings/ReminderSettingsView.swift:35](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/ReminderSettingsView.swift:35) — WorkspaceReminderTimingSections 实际创建此行并转发 edit(kind)。
- [Orgenda/Features/Settings/ReminderSettingsView.swift:104](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/ReminderSettingsView.swift:104) — 原生 LabeledContent/Button/Label；115 起按字号与当前值切换 Picker 样式，130 起补入非预设值。
- [Orgenda/Features/Settings/ConfigurationSettingsView.swift:467](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/ConfigurationSettingsView.swift:467) — 三种配置绑定进入调用方，编辑回调打开 ReminderTimingEditor，并继承工作区不可用时禁用行为。

API 依据：

- [iOS 27 SDK SwiftUI LabeledContent、Picker 与 PickerStyle 声明](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：核对 5017/5030 的 LabeledContent 构造器、18128/18160 的绑定 Picker，以及 16201 的 SegmentedPickerStyle、30536 的 MenuPickerStyle；均为 iOS 27 可用系统 API。
- [iOS 27 SDK SwiftUICore DynamicTypeSize](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUICore.framework/Modules/SwiftUICore.swiftmodule/arm64e-apple-ios.swiftinterface)：核对 14733 起的辅助功能字号枚举及 14746 isAccessibilitySize、14767 EnvironmentValues.dynamicTypeSize，支持当前显式适配条件。

专属分析 agent：`/root/audit_group_c/c122`。

<a id="c123"></a>

### C123 · ReminderTimingEditor

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/ReminderSettingsView.swift:139)　置信度：high

当前实现：以 NavigationStack、Form、LabeledContent、数字键盘 TextField 和工具栏按钮组成自定义提醒时长编辑页；字符串草稿独立于配置，校验整数及种类范围后才允许 Apply。

系统候选：无实质替代。TextField(value:format:) 可承担数字解析，但仍需草稿、范围校验与提交事务；Stepper(value:in:) 改变直接输入任意整数的交互。

判断：实现没有自绘或重造系统输入控件，独立字符串草稿保留空值及非法输入以显示错误，并保证 Cancel 不写入配置。Apply 才通过父视图 Binding 触发自动保存。格式化 TextField 不能消除各提醒种类的范围规则、错误提示和提交边界；Stepper 也不能等价保留当前直接输入体验，替换收益不足。

预期收益：保留现有短小的原生组合与业务边界；更换输入 API 至多减少简单解析，无法显著减少整体复杂度。

必须保留：提前提醒 0...1440 分钟、重复间隔 1...1440 分钟、截止预览 0...365 天；保留原始输入草稿，去除首尾空白后仅接受有效整数；非法草稿提示范围并禁用 Apply；Cancel 丢弃草稿；Apply 更新配置 Binding 后关闭，沿用父级验证和自动保存流程；本地化标题和单位、数字键盘、无障碍标签及测试标识

验证要求：OrgendaUITests/ConfigurationUITests.swift:323 testReminderTimingPresetsCustomValuesAndInvalidDraftPersistence 已覆盖 37 分钟提交、重复间隔 0 禁止提交、取消保留 5 分钟及持久化；本次只读审查未运行测试。；若改用格式化 TextField，需原型核对清空、粘贴非整数、首尾空白、三类边界值和错误提示的即时性，确认 Cancel 从不写入父级。

代码依据：

- [Orgenda/Features/Settings/ReminderSettingsView.swift:139](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/ReminderSettingsView.swift:139) — 原生表单和 TextField；独立 input、validValue 与 Cancel/Apply 提交边界。
- [Orgenda/Features/Settings/ConfigurationSettingsView.swift:106](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/ConfigurationSettingsView.swift:106) — sheet 接入配置 key path Binding；:489 的 setter 经 submit 调度自动保存。
- [OrgendaUITests/ConfigurationUITests.swift:323](/Users/roifewu/.config/orgenda/OrgendaUITests/ConfigurationUITests.swift:323) — 现有 UI 测试验证自定义值、非法重复间隔、取消及持久化。

API 依据：

- [iOS 27 SDK — SwiftUI TextField、Stepper 与 ButtonRole 声明](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：核对 TextField(value:format:) 可选及非可选 ParseableFormatStyle 绑定（:98 起）、TextField(text:)（:6587 起）、Stepper(value:in:step:)（:26344）与 ButtonRole.confirm（:11768，iOS 26 起）；这些 API 在最低 iOS 27 可用，但不替代业务范围校验及提交边界。

专属分析 agent：`/root/audit_group_c/c123`。

<a id="c124"></a>

### C124 · ReminderSettingsSections

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/ReminderSettingsView.swift:200)　置信度：high

当前实现：以原生 Section、Toggle、Label、Text、Button 组成设备提醒设置；AppStorage 保存开关，结合工作区状态禁用控件、显示权限拒绝提示，并在进入页面和回到前台时刷新提醒。

系统候选：无实质替代；已有 SwiftUI Toggle、Section 与 AppStorage 即适当系统构件。

判断：当前组件并未重造开关或列表分组，仅将原生控件绑定到应用业务状态。用户提醒偏好与系统通知授权刻意分离，缺少工作区时禁用并提供连接入口；首次显示、开关变更及回到前台均需刷新调度。系统控件不会代办这些业务条件，改成单个 Toggle 或跳转系统设置会丢失现有行为。

预期收益：保留薄业务封装；当前不存在能减少有效复杂度且保持行为的系统组件替换。

必须保留：orgRemindersEnabled 的设备级持久化及默认关闭；用户偏好与通知授权分离，拒绝授权仍显示状态；无 Emacs 或工作区配置时禁用并提供连接入口；启用时请求权限；初次显示及回到 active 时刷新；现有可访问性标识与多行状态说明

验证要求：OrgendaUITests/ConfigurationUITests.swift:testSettingsPanelNavigationAndAppearance 验证提醒开关可达。；OrgendaUITests/ConfigurationUITests.swift:testFilesRemindersAndConfigAreDirectDestinations 验证设备开关与工作区时间设置同页。；现有测试未覆盖授权拒绝、前台刷新和无配置禁用分支；如调整，应补充这些交互验证。本次仅静态审查，未运行测试。

代码依据：

- [Orgenda/Features/Settings/ReminderSettingsView.swift:200](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/ReminderSettingsView.swift:200) — 原生开关、权限提示、配置门控、连接按钮及生命周期刷新。
- [Orgenda/Features/Settings/ConfigurationSettingsView.swift:466](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/ConfigurationSettingsView.swift:466) — 嵌入提醒设置 List，连接回调使用 requestExit(.workspace)。
- [Orgenda/Services/Workspace/WorkspaceStore+Reminders.swift:4](/Users/roifewu/.config/orgenda/Orgenda/Services/Workspace/WorkspaceStore+Reminders.swift:4) — 授权状态刷新、配置保护、按需请求权限并读取独立的用户偏好。

API 依据：

- [iOS 27 SDK SwiftUI Toggle、Section、AppStorage 声明](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：核对 Toggle(isOn:label:)（6170行）、Section 内容及标题构造器（14043行）和 AppStorage Bool 与投影 Binding（9163行起）；现用 API 均为系统能力且支持 iOS 27。

专属分析 agent：`/root/audit_group_c/c124`。

<a id="c125"></a>

### C125 · SettingsRow

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/SettingsRow.swift:3)　置信度：high

当前实现：以原生 Label、Image、Text 和 VStack/HStack 组合设置行，支持图标颜色、可选副标题及状态图标，并合并无障碍子元素。

系统候选：继续使用现有 SwiftUI Label(title:icon:)；未发现能实质简化且保持全部行为的单一替代控件。

判断：当前已由系统 Label 负责图文布局；包装主要统一可选副标题、状态图标和无障碍语义。设置主页实际传入同步状态图标，工作区页实际展示连接摘要。简单 Label(title:systemImage:) 不能表达这些内容，展开到调用处只会重复原生视图组合，改用 UIKit 桥接也无复杂度收益。

预期收益：保留短包装可避免多个调用点重复布局和无障碍配置；没有实质替换收益。

必须保留：可选副标题及其同步状态图标；标题与副标题层级、长文本纵向展开；装饰图标不朗读，标题与副标题合并朗读；作为 NavigationLink、Button 和静态列表行内容复用

验证要求：OrgendaUITests/ConfigurationUITests.swift:5 testSettingsPanelNavigationAndAppearance 检查 settings.workspace 标签和进入工作区页；仅静态读取，未运行。；OrgendaUITests/WorkspaceSyncUITests.swift:95 testFolderPickerCanOpenAndCancel 覆盖两个服务提供方行；161 testChangingStorageWithPendingEditsRequiresKeepingCopies 读取连接行标签。；如调整布局，需补验大字号下长副标题换行及 VoiceOver 合并朗读；现有测试未证明这些交互表现。

代码依据：

- [Orgenda/Features/Settings/SettingsRow.swift:10](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/SettingsRow.swift:10) — 实现为 Label 与原生文本栈，使用 titleAndIcon 样式和合并无障碍元素。
- [Orgenda/Features/Settings/SettingsView.swift:19](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/SettingsView.swift:19) — 工作区导航行传入副标题与同步状态图标。
- [Orgenda/Features/Settings/WorkspaceSettingsView.swift:29](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/WorkspaceSettingsView.swift:29) — 连接摘要作为副标题展示，行附加无障碍值及标识。

API 依据：

- [iOS 27 SDK SwiftUI.Label 与 TitleAndIconLabelStyle](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：30896 行提供泛型 title/icon 内容构造器；30916 行附近的字符串构造器仅提供标题与图标；18919 行声明原生 titleAndIcon 样式，均早于 iOS 27 可用。
- [iOS 27 SDK accessibilityElement(children:) 与 AccessibilityChildBehavior.combine](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：30312、30319 行核对现有合并无障碍元素 API，当前组件直接使用系统能力。

专属分析 agent：`/root/audit_group_c/c125`。

<a id="c126"></a>

### C126 · SettingsValueRow

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/SettingsValueRow.swift:4)　置信度：high

当前实现：以系统 LabeledContent 和 Text 显示标题及值，为长地址、账号配置不限行数、纵向理想尺寸，并合并辅助功能子元素。

系统候选：现有实现已使用 LabeledContent；其 title/value 便捷初始化不能单独替代值文本上的换行尺寸配置，无实质替代项。

判断：组件没有自行绘制或模拟系统信息行，已采用 LabeledContent。工作区设置及更新密码表单共四处复用，集中保留长服务器地址、账号的换行与辅助功能配置有实际价值。改用便捷初始化仍需确认并保留值文本的纵向尺寸行为，内联现有组合只会重复配置，不减少实现复杂度。

预期收益：保留短封装可集中维护四处调用的展示策略；没有值得迁移的自定义控件实现。

必须保留：长地址及账号值允许多行显示，纵向不截断；标题和值的系统信息行布局；标题和值合并为辅助功能元素；调用方传入的已本地化标题和原始值

验证要求：已读 OrgendaUITests/WorkspaceSyncUITests.swift:161 的 testChangingStorageWithPendingEditsRequiresKeepingCopies；覆盖设置入口与连接流程，未验证本行长文本布局。；rg 检索 OrgendaTests 与 OrgendaUITests 未发现 SettingsValueRow 专项测试；若调整尺寸或辅助功能修饰符，应在 List/Form 中验证长 URL、长账号、辅助功能大字号及 VoiceOver 合并朗读。本次仅静态审查，未运行测试。

代码依据：

- [Orgenda/Features/Settings/SettingsValueRow.swift:9](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/SettingsValueRow.swift:9) — 直接使用 LabeledContent、Text、lineLimit、fixedSize 和 accessibilityElement。
- [Orgenda/Features/Settings/WorkspaceSettingsView.swift:34](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/WorkspaceSettingsView.swift:34) — Account 与 Server Address 两处实际调用。
- [Orgenda/Features/Settings/StorageReconnectAction.swift:35](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/StorageReconnectAction.swift:35) — 更新密码 Form 中展示服务器地址及用户名。

API 依据：

- [iOS 27 SDK — SwiftUI.LabeledContent 与 accessibilityElement](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：5017–5061 行确认 LabeledContent、content/label 与 title/value 初始化自 iOS 16 可用；30312–30321 行确认 accessibilityElement(children:) 与 .combine。最低 iOS 27 满足可用性。
- [iOS 27 SDK — SwiftUICore.View.fixedSize 与 lineLimit](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUICore.framework/Modules/SwiftUICore.swiftmodule/arm64e-apple-ios.swiftinterface)：1594 行确认 fixedSize(horizontal:vertical:)；11167 行确认 lineLimit(Int?)，均为系统 View 修饰符。声明不证明便捷初始化具有相同实际换行结果。

专属分析 agent：`/root/audit_group_c/c126`。

<a id="c127"></a>

### C127 · SettingsView

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/SettingsView.swift:3)　置信度：high

当前实现：设置入口页，以 NavigationStack、分组 List/Section、NavigationLink、菜单 Picker 和关闭角色 Button 组合工作区与业务配置入口；AppStorage 持久化外观，支持初始深链路径并刷新提醒状态。

系统候选：保留现有系统控件组合。Form 是可选容器，但不能消除目的地路由、存储状态和退出策略，没有实质替代收益。

判断：界面没有自绘导航或选择控件，路径绑定、菜单选择和关闭按钮均已使用系统 API。剩余代码承担搜索深链、工作区同步摘要、外观持久化和提醒刷新等业务职责；配置页不注入直接关闭按钮，保留其编辑退出保护。改成 Form 只能更换容器，无法减少这些必要逻辑，未发现值得替换的实现。

预期收益：当前抽象集中多个入口共享的设置路由与展示策略；继续使用系统组合即可，替换容器预计不会降低维护复杂度。

必须保留：搜索和故障恢复入口通过 initialDestination 直接进入对应设置，并可返回设置首页；外观在本设备持久化，菜单切换后即时更新已展示的设置页；工作区提供者、同步状态和辅助功能值；首页、工作区和外观页的关闭动作，以及配置页自行处理的编辑退出保护；展示时刷新提醒权限与调度状态

验证要求：OrgendaUITests/ConfigurationUITests.swift:5 testSettingsPanelNavigationAndAppearance 覆盖菜单外观即时变化、返回导航及不同页面的关闭按钮；仅读取，未运行。；OrgendaUITests/ConfigurationUITests.swift:194 testSettingsSearchOpensWorkflowWithoutCategoryHub 覆盖搜索直达、返回设置及退出后保留搜索内容；仅读取，未运行。；OrgendaTests/Services/Workspace/WorkspaceStoreTests.swift:156 testSettingsSearchOnlyReturnsExistingDestinations 覆盖设置目的地清单；仅读取，未运行。

代码依据：

- [Orgenda/Features/Settings/SettingsView.swift:14](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/SettingsView.swift:14) — NavigationStack 内使用分组 List 和菜单 Picker，65 行分派路由，76 行按路径限制关闭工具栏。
- [Orgenda/Features/Search/SearchView.swift:59](/Users/roifewu/.config/orgenda/Orgenda/Features/Search/SearchView.swift:59) — 搜索结果以 initialDestination 展示设置页；文件入口使用同一组件。
- [OrgendaUITests/ConfigurationUITests.swift:5](/Users/roifewu/.config/orgenda/OrgendaUITests/ConfigurationUITests.swift:5) — 现有测试明确要求外观原地切换、配置页没有直接关闭按钮，以及工作区页可关闭。

API 依据：

- [iOS 27 SwiftUI SDK：NavigationStack、Picker、AppStorage、ButtonRole.close 与 presentationSizing](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对 19183 行路径绑定 NavigationStack、18128 行 Picker、9163 行 AppStorage 与 String 初始化器；11770 行 close 自 iOS 26 可用，13911 行 presentationSizing 自 iOS 18 可用，均满足最低 iOS 27。

专属分析 agent：`/root/audit_group_c/c127`。

<a id="c128"></a>

### C128 · StorageConflictsView

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/StorageConflictView.swift:3)　置信度：high

当前实现：以系统 List、Section、ForEach、NavigationLink 展示同步冲突，使用双行 Text 区分远端删除与双方修改，并以 ContentUnavailableView 呈现无冲突状态。

系统候选：无需实质替换；现有 List、NavigationLink 与 ContentUnavailableView 已承担对应系统交互。

判断：实现没有自绘列表、手势导航或自制占位控件；自定义部分仅把可观察的冲突数据映射为路径、状态文案和详情路由。系统控件已经覆盖列表、导航与空状态，改成 UIKit 或进一步内联不能消除业务映射，反而降低边界清晰度，因此没有可带来实质收益的替代。

预期收益：保留薄业务组合；没有值得引入新桥接或迁移的自定义 UI 实现。

必须保留：随 WorkspaceStore.syncConflicts 变化刷新列表及空状态；按冲突路径保持行身份并导航到对应详情；区分远端删除与本机及远端同时修改的本地化说明；保留 storage.conflict.<path> 无障碍标识及空状态大字号可滚动布局

验证要求：OrgendaUITests/WorkspaceSyncUITests.swift:146 testConflictPreviewAndReplacementConfirmation 已覆盖设置入口、路径行出现和进入详情；本次未运行。；如后续调整布局，需检查最后一项冲突消失后空状态更新，以及长路径和大字号下的文案可读性。

代码依据：

- [Orgenda/Features/Settings/StorageConflictView.swift:7](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/StorageConflictView.swift:7) — List、NavigationLink、双行状态文案及 ContentUnavailableView 已为原生组合。
- [Orgenda/Features/Settings/WorkspaceSettingsView.swift:16](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/WorkspaceSettingsView.swift:16) — 有冲突时通过 NavigationLink 进入该列表，存在生产调用。
- [OrgendaUITests/WorkspaceSyncUITests.swift:146](/Users/roifewu/.config/orgenda/OrgendaUITests/WorkspaceSyncUITests.swift:146) — 测试点击 storage.conflict.notes.org 并验证详情预览。

API 依据：

- [iOS 27 SDK SwiftUI List、NavigationLink 与 ContentUnavailableView 声明](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对 List（8156）、NavigationLink(destination:label:)（14229）及 ContentUnavailableView(_:systemImage:description:)（22669）；分别自 iOS 13、13、17 可用，满足最低 iOS 27。

专属分析 agent：`/root/audit_group_c/c128`。

<a id="c129"></a>

### C129 · StorageConflictView

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/StorageConflictView.swift:39)　置信度：high

当前实现：冲突详情页通过原生 List、Section、Button、ProgressView、ContentUnavailableView 和 confirmationDialog 展示本地/存储版本，提供保留两份或确认覆盖，并执行异步解决。

系统候选：无有实质收益的替代；页面及确认流程已采用 SwiftUI 系统组件。

判断：此视图由系统列表、按钮、进度和确认对话框组成，剩余状态用于保存用户实际确认的冲突快照、避免重复操作及完成后返回。服务层会拒绝过期快照并保留恢复副本，不能用通用弹窗替换这些业务约束。iOS 27 SDK 已包含当前使用的 item 绑定确认接口，没有需要自制的呈现层或可明显删减的替代控件。

预期收益：保留现有业务封装；改用另一种原生容器不会减少冲突保护逻辑，未发现实质复杂度收益。

必须保留：本地与存储版本预览及远端删除提示；保留两份、使用本地和使用存储三个选择；覆盖前确认、恢复副本文案和 expectedConflict 快照校验；解决或同步期间禁用操作、错误展示及成功后关闭

验证要求：OrgendaUITests/WorkspaceSyncUITests.swift:146 testConflictPreviewAndReplacementConfirmation 覆盖预览及取消确认。；OrgendaTests/Services/Workspace/WorkspaceStorageIntegrationTests.swift:121 testStaleConflictConfirmationDoesNotDiscardUpdatedDraft 覆盖旧确认不得丢弃新编辑。；OrgendaTests/Services/Storage/WorkspaceSessionTests.swift:366 testUseLocalRefusesAnUnseenNewRemoteRevision 覆盖远端新修订保护。仅阅读测试，未执行。

代码依据：

- [Orgenda/Features/Settings/StorageConflictView.swift:12](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/StorageConflictView.swift:12) — 冲突列表 NavigationLink 实际创建本详情页。
- [Orgenda/Features/Settings/StorageConflictView.swift:53](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/StorageConflictView.swift:53) — 系统列表和操作组成详情，113 行直接使用系统 confirmationDialog，137 行携带快照异步解决。
- [Orgenda/Services/Workspace/WorkspaceStore+Storage.swift:439](/Users/roifewu/.config/orgenda/Orgenda/Services/Workspace/WorkspaceStore+Storage.swift:439) — resolveSyncConflict 持久化编辑后校验 expectedConflict，失败保留冲突并报告错误。

API 依据：

- [iOS 27 SwiftUI SDK：confirmationDialog(item:actions:message:) 与 ContentUnavailableView](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：22581 行公开 item 绑定确认接口，22638 行为 iOS 17+ ContentUnavailableView；两者均适用于最低部署 iOS 27。

专属分析 agent：`/root/audit_group_c/c129`。

<a id="c130"></a>

### C130 · StorageVersionPreview

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/StorageConflictView.swift:148)　置信度：high

当前实现：用 VStack、Text、双向 ScrollView 和 Label 展示冲突版本；包含可选修改时间、可选择的等宽全文、空文件提示及远端删除状态。

系统候选：无实质替代；当前 ScrollView + Text.textSelection(.enabled) 已使用系统滚动与文本选择能力。

判断：两个生产调用分别呈现本机与存储端版本。组件只组合系统控件，并封装空字符串与 nil 的不同业务含义、时间及无障碍标识；无自绘滚动或选择逻辑可移除。保留现有抽象即可共享这组展示规则，单一系统控件不能消除这些条件分支。

预期收益：保持短小的原生组合即可；改用其他容器不能减少核心展示逻辑，新增桥接反而增加维护成本。

必须保留：nil 显示远端已删除，空字符串显示空文件，二者不可合并；130 点高的双向滚动预览与保持原行宽的等宽全文；文本选择、可选修改时间、本机与远端独立无障碍标识

验证要求：OrgendaUITests/WorkspaceSyncUITests.swift:146 testConflictPreviewAndReplacementConfirmation 验证两个带标识的 ScrollView 均存在；本次只读未运行。；OrgendaTests/Services/Workspace/WorkspaceStorageConcurrencyTests.swift:44 testDeleteKeepsUIEditArrivingDuringRemoteAwaitAsDurableDeletionConflict 验证删除冲突保留本地内容、remoteContents 为 nil。；如后续改动布局，需实机验证长行横向滚动、多行纵向滚动、选择复制及空文件/删除分支；现有 UI 测试不覆盖这些交互。

代码依据：

- [Orgenda/Features/Settings/StorageConflictView.swift:61](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/StorageConflictView.swift:61) — 本机与远端版本分别调用组件，远端传入可选内容和修改时间。
- [Orgenda/Features/Settings/StorageConflictView.swift:155](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/StorageConflictView.swift:155) — 系统 VStack/Text/ScrollView/Label 组合，明确区分有内容、空文件及 nil。
- [OrgendaUITests/WorkspaceSyncUITests.swift:146](/Users/roifewu/.config/orgenda/OrgendaUITests/WorkspaceSyncUITests.swift:146) — 冲突预览测试直接使用 storage.conflict.local 与 storage.conflict.remote 标识。

API 依据：

- [iOS 27 SDK：SwiftUI ScrollView 与 View.textSelection](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对 18994–19046 的 ScrollView Axis.Set 初始化器及 2332–2336 的 textSelection；分别自 iOS 13、15 可用，符合最低 iOS 27。

专属分析 agent：`/root/audit_group_c/c130`。

<a id="c131"></a>

### C131 · StorageProviderPicker

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/StorageProviderPicker.swift:4)　置信度：high

当前实现：以 NavigationStack、List、Button、NavigationLink 选择 Files 或 WebDAV；系统 fileImporter 选文件夹，confirmationDialog(item:) 确认切换，并处理连接进度、错误和未同步编辑保护。

系统候选：继续使用现有 SwiftUI fileImporter 与 confirmationDialog(item:)；没有能合并提供者选择、WebDAV 连接入口及工作区切换保护的等价系统控件。

判断：当前源码已直接使用 SDK 的 item 绑定确认对话框，无需再包装布尔展示状态。其余逻辑负责区分同目录重连与跨目录切换、传递保留未同步编辑选项、等待连接结果及禁用退出，属于工作区语义。改成单一 Picker 或直接文件导入器会丢失 WebDAV 导航与切换保护，不能移除必要业务封装。

预期收益：无实质系统替换收益；保留当前原生组合，避免引入更大的 UIKit 桥接或将业务保护分散到调用方。

必须保留：Files 与 WebDAV 两种入口及无障碍标识；同目录重连直接执行、切换目录先确认；动态检测待保存变更并传递 preservePending；连接期间禁用操作与退出，失败保留界面并显示可选取错误文本；文件选择取消不显示错误，成功连接后关闭

验证要求：OrgendaUITests/WorkspaceSyncUITests.swift:95 testFolderPickerCanOpenAndCancel 覆盖两个提供者入口、系统选择器取消和无错误回退。；OrgendaUITests/WorkspaceSyncUITests.swift:161 testChangingStorageWithPendingEditsRequiresKeepingCopies 覆盖经本组件进入 WebDAV 后的保留副本提示及取消不改连接。；OrgendaTests/Services/Workspace/WorkspaceStorageIntegrationTests.swift:96 testChangingLocationRequiresPreservingConflictAndDoesNotUploadItToNewFolder 覆盖底层保留编辑语义；:54 testFailedNewConnectionLeavesCurrentWorkspaceAndDescriptor 覆盖失败不替换工作区。；以上为静态阅读，未运行测试；若以后调整流程，补查本地文件夹切换确认、同目录重连及连接期间退出禁用。

代码依据：

- [Orgenda/Features/Settings/StorageProviderPicker.swift:15](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/StorageProviderPicker.swift:15) — 原生列表、文件导入与 item 确认；:87 起区分目录并驱动带保护的异步连接。
- [Orgenda/Features/Settings/WorkspaceSettingsView.swift:78](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/WorkspaceSettingsView.swift:78) — 选择入口保存待编辑状态，:102 的 sheet 实际创建本组件。
- [Orgenda/Services/Workspace/WorkspaceStore+Storage.swift:77](/Users/roifewu/.config/orgenda/Orgenda/Services/Workspace/WorkspaceStore+Storage.swift:77) — connectFolder 处理安全作用域、同根重连和 preservePending 会话替换，说明选择器承载真实业务边界。

API 依据：

- [SwiftUI View.fileImporter / confirmationDialog(item:) — iOS 27 SDK](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：核对 9053 行单 URL fileImporter，以及 22581 行带 Binding<T?>、actions 和 message 的 confirmationDialog；当前实现均直接调用系统 API。

专属分析 agent：`/root/audit_group_c/c131`。

<a id="c132"></a>

### C132 · StorageReconnectAction

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/StorageReconnectAction.swift:3)　置信度：high

当前实现：用原生 Button、Label 和 sheet(item:) 封装 WebDAV 更新密码入口；保存当前连接作为弹层数据，并在同步期间禁用入口。

系统候选：继续使用现有 SwiftUI Button 与 sheet(item:)；Button("Update Password", systemImage: "key.fill", action:) 仅能缩写标签构造，无实质替代收益。

判断：该组件没有自绘或自定义交互，已由原生按钮及数据驱动弹层组成。调用方仅在 WebDAV 认证失效时显示它；本地状态负责把当前连接传给密码表单，同步禁用和可访问性标识也仍需保留。系统按钮便利初始化器只能缩短语法，不能取代此业务入口和呈现状态。

预期收益：保留短小业务封装；改用按钮便利初始化器只减少标签样板，不减少状态或业务复杂度。

必须保留：仅对 WebDAV 且 authenticationRequired 状态显示入口；点击时捕获当前 StorageConnection，并以 sheet(item:) 传入密码界面；同步期间禁用按钮及 storage.reauthenticate 可访问性标识；继续调用既有凭据更新流程，保持原账户、根目录和待上传数据归属

验证要求：OrgendaTests/Services/Storage/WebDAVBackendTests.swift:64 testReconnectWithEmptyPasswordLeavesSavedCredentialsIntact 验证下游凭据保护，未运行。；全库 Swift 搜索仅发现 WorkspaceSettingsView:69 的生产调用；未发现直接覆盖 storage.reauthenticate 入口的 UI 测试。若调整按钮写法，需检查禁用状态、VoiceOver 标签及点击后连接信息仍一致。

代码依据：

- [Orgenda/Features/Settings/StorageReconnectAction.swift:3](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/StorageReconnectAction.swift:3) — Button/Label、同步禁用、accessibilityIdentifier 与 sheet(item:) 构成完整入口。
- [Orgenda/Features/Settings/WorkspaceSettingsView.swift:68](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/WorkspaceSettingsView.swift:68) — 仅 WebDAV 认证失效时实例化此组件。
- [Orgenda/Services/Workspace/WorkspaceStore+Storage.swift:132](/Users/roifewu/.config/orgenda/Orgenda/Services/Workspace/WorkspaceStore+Storage.swift:132) — 重连校验会话与连接 identity，替换远端后端后同步，保留既有工作区归属。

API 依据：

- [iOS 27 SwiftUI SDK：Button 与 View.sheet(item:onDismiss:content:)](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：核对 9143 行 sheet 的 Identifiable 可选绑定与内容参数、29179 行 Button 定义及 29209 行 systemImage 便利初始化器；现有组成均为系统 API。

专属分析 agent：`/root/audit_group_c/c132`。

<a id="c133"></a>

### C133 · StorageWebDAVCredentialsView

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/StorageReconnectAction.swift:22)　置信度：high

当前实现：以 NavigationStack、Form、Section、SecureField、Button 和 ProgressView 组合 WebDAV 密码更新页；显示原服务器与账号，异步重连并呈现错误。

系统候选：无实质替代；现用 SecureField 与 Form 已是系统控件，服务器和账号行也通过 SettingsValueRow 使用 LabeledContent。

判断：该视图没有自绘输入控件或自定义布局，主要承担重连状态与业务调用。系统 SecureField 已处理密码输入，Form 承载信息、操作与可选择的错误文字。重连期间禁用表单、取消及交互关闭，成功后才退出；这些状态编排仍需应用负责，替换容器不能消除其必要逻辑。

预期收益：没有明确的组件替换收益；保留简短原生组合可避免引入额外桥接和重新实现业务状态。

必须保留：只更新现有服务器与账号的密码，不改变工作区身份或待上传编辑归属；空密码禁止提交，密码输入采用系统安全文本框及 password 内容类型；重连期间显示进度并禁止重复提交、取消和交互关闭；成功关闭页面；失败留在表单并显示可选择的错误文字

验证要求：OrgendaTests/Services/Storage/WebDAVBackendTests.swift:64 testReconnectWithEmptyPasswordLeavesSavedCredentialsIntact 覆盖空密码不损坏已存凭据；本次只读未执行。；rg 检索 OrgendaTests 与 OrgendaUITests 未发现此页面的专门交互测试；若后续调整，需验证重连中的取消/下滑关闭被阻止、失败保留页面及成功关闭。

代码依据：

- [Orgenda/Features/Settings/StorageReconnectAction.swift:30](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/StorageReconnectAction.swift:30) — 原生表单、密码输入、进度、错误展示及关闭保护均在本页组合。
- [Orgenda/Features/Settings/WorkspaceSettingsView.swift:68](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/WorkspaceSettingsView.swift:68) — 仅 WebDAV 且 authenticationRequired 时提供生产重连入口，由 sheet 展示本页。
- [Orgenda/Services/Workspace/WorkspaceStore+Storage.swift:132](/Users/roifewu/.config/orgenda/Orgenda/Services/Workspace/WorkspaceStore+Storage.swift:132) — 重连验证原连接身份，持久化待编辑内容后替换后端并同步。

API 依据：

- [iOS 27 SDK SwiftUI SecureField 与 Form 声明](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：核对 SecureField(_:text:)（约 21438 行）和 Form(content:)（17167 行）均为公开系统组件，满足最低 iOS 27。
- [iOS 27 SDK SwiftUI interactiveDismissDisabled(_:)](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：30151 行提供系统交互关闭禁用 API；当前实现已直接使用该能力，无需自定义手势拦截。

专属分析 agent：`/root/audit_group_c/c133`。

<a id="c134"></a>

### C134 · StorageSyncSummary

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/StorageSyncView.swift:3)　置信度：high

当前实现：以 VStack/HStack、系统 Image、ProgressView 和 LabeledContent 展示同步状态、检查时间、Org 文件数及待上传数；通过 ScaledMetric 和隐藏符号叠层稳定状态行基线。

系统候选：现有 ProgressView、LabeledContent 已是合适系统组件；Label 可表达状态标题与图标，但没有已证实的实质简化。

判断：主体已由系统控件组成，包装层集中同步状态及条件字段。Label 支持自定义图标，却不能仅凭 API 声明保证进度指示器切换时基线与行高不变；若保留现有占位叠层，替换 HStack 几乎不减少复杂度。没有等价单一系统控件可消除该业务组合，建议保留。

预期收益：保留短小原生组合即可；改用 Label 仍需状态分支、基线处理和业务字段，预期没有实质复杂度收益。

必须保留：保存/同步时显示不定进度，其余状态显示对应符号与颜色；状态切换时保持符号基线与行高；图标尺寸随正文缩放；检查时间仅非空显示，待上传数仅大于零显示，Org 文件数始终显示；状态标题支持换行，图标不重复朗读，并保留 workspace.syncStatus 标识

验证要求：OrgendaUITests/WorkspaceSyncUITests.swift:146 testConflictPreviewAndReplacementConfirmation 与 :161 testChangingStorageWithPendingEditsRequiresKeepingCopies 使用同步冲突 fixture，但未直接断言状态摘要。；源码检索未发现 workspace.syncStatus 的测试断言；如试用 Label，需验证保存/同步/完成切换时行高、辅助功能大字体换行和 VoiceOver 合并朗读。；StorageSyncView.swift:53 的 Sync summaries 预览覆盖空文件、同步中和冲突状态；本次仅静态审查，未运行。

代码依据：

- [Orgenda/Features/Settings/StorageSyncView.swift:10](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/StorageSyncView.swift:10) — 原生布局、进度/图标叠层、LabeledContent 与可访问性配置均在此组合。
- [Orgenda/Features/Settings/WorkspaceSettingsView.swift:44](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/WorkspaceSettingsView.swift:44) — 生产设置页传入真实同步状态、最后同步时间、Org 文件计数与上传计数。
- [Orgenda/Domain/Workspace/StorageConnection.swift:38](/Users/roifewu/.config/orgenda/Orgenda/Domain/Workspace/StorageConnection.swift:38) — WorkspaceSyncState 定义本地保存、同步、离线、认证和冲突等业务状态及标题。

API 依据：

- [iOS 27 SDK SwiftUI ProgressView、LabeledContent 与 Label 声明](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：核对 4963–5059 的 ProgressView()、LabeledContent(_:value:) 与 30896 的 Label(title:icon:)；均可用于最低 iOS 27，未提供自定义状态切换基线稳定性的等价保证。
- [iOS 27 SDK SwiftUICore ScaledMetric 与 VerticalAlignment](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUICore.framework/Modules/SwiftUICore.swiftmodule/arm64e-apple-ios.swiftinterface)：核对 15019 的 ScaledMetric(wrappedValue:relativeTo:) 及 14183 的 firstTextBaseline；现有缩放和对齐均使用系统 API。

专属分析 agent：`/root/audit_group_c/c134`。

<a id="c135"></a>

### C135 · StorageWebDAVView

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/StorageWebDAVView.swift:3)　置信度：high

当前实现：使用 Form、Section、LabeledContent、TextField、SecureField、Button、ProgressView 和 confirmationDialog 构成 WebDAV 连接页；管理输入校验、焦点顺序、异步连接及切换工作区确认。

系统候选：继续使用现有 SwiftUI 原生表单和确认对话框；未发现能消除业务实现的等价系统连接组件。

判断：当前输入、布局、加载指示和确认弹窗均已采用系统组件；剩余逻辑负责 HTTPS 与目录校验、连接状态及未同步编辑的保留确认。系统表单不会代办这些工作区语义，改用其他容器或 UIKit 桥接无法实质减少复杂度。iOS 27 SDK 已提供当前使用的 item 绑定确认弹窗，无需另造适配层。

预期收益：没有实质性的系统组件替换收益；保留该原生业务组合可集中管理连接流程和状态。

必须保留：限制 HTTPS 地址并拒绝 URL 内凭据、查询、片段及不安全目录；用户名和密码输入语义、密码遮蔽及按提交键逐字段推进；连接期间禁用表单并阻止返回和交互关闭；切换前展示当前及目标位置，并保留未同步编辑副本；连接成功后关闭，失败时显示可选择的错误文本

验证要求：OrgendaUITests/WorkspaceSyncUITests.swift:122 — testWebDAVFormRejectsInsecureAddressWithoutConnecting 覆盖字段输入、提交与不安全地址错误。；OrgendaUITests/WorkspaceSyncUITests.swift:161 — testChangingStorageWithPendingEditsRequiresKeepingCopies 覆盖切换确认、目标说明和保留副本提示。；OrgendaTests/Services/Storage/WebDAVBackendTests.swift:45 — testSetupRejectsUnsafeServerAddressesAndDirectories 覆盖后端配置拒绝；本次仅阅读测试，未执行。

代码依据：

- [Orgenda/Features/Settings/StorageWebDAVView.swift:18](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/StorageWebDAVView.swift:18) — 原生表单与控件组合；第 87 行使用 item 绑定 confirmationDialog，第 113 行起执行输入与连接业务逻辑。
- [Orgenda/Features/Settings/StorageProviderPicker.swift:31](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/StorageProviderPicker.swift:31) — NavigationLink 生产调用，并传入需要保留未同步修改的状态。
- [Orgenda/Services/Workspace/WorkspaceStore+Storage.swift:125](/Users/roifewu/.config/orgenda/Orgenda/Services/Workspace/WorkspaceStore+Storage.swift:125) — connectWebDAV 通过工厂准备连接，replaceStorageSession 在激活新会话前准备并验证存储替换。

API 依据：

- [iOS 27 SwiftUI SDK：Form、LabeledContent 与 SecureField](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：已核对 LabeledContent 5017 行、Form 17167 行和 SecureField 21395 行声明；这些都是现有页面使用的系统控件。
- [iOS 27 SwiftUI SDK：confirmationDialog(_:item:titleVisibility:actions:message:)](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：22581 行明确提供 Binding<T?> 的 item 重载并转交系统确认对话框；当前调用无需自定义桥接。

专属分析 agent：`/root/audit_group_c/c135`。

<a id="c136"></a>

### C136 · WorkspaceSettingsView

**保留：已是系统组件组合 · P3**　[源码](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/WorkspaceSettingsView.swift:3)　置信度：high

当前实现：以原生 List、Section、NavigationLink、Button、sheet 和 confirmationDialog 组合工作区设置页，显示连接、同步与错误状态，并协调重连、换位置、断开和采用文件夹版本。

系统候选：继续使用现有 SwiftUI 原生列表与呈现 API；没有能移除该业务页面的等价单一系统组件。Form 仅改变容器形式，不能消除状态及操作编排。

判断：页面已由系统控件组成，没有自行实现列表、弹窗或导航。其自定义部分负责依据连接类型、冲突和未同步编辑显示操作，并在切换、断开及重载前传递保留副本策略；这些业务约束无法由 Form 或文件选择器代替。保留页面抽象能够集中维护防止数据丢失的交互。

预期收益：整体替换没有实质复杂度收益；现有原生控件已经承担布局、导航和确认呈现，剩余代码主要是必要的工作区业务协调。

必须保留：未同步编辑在切换或断开前保留到 Unsaved Edits，避免上传至新位置。；同步或断开期间禁用连接操作，保留错误与冲突入口。；WebDAV 认证失效时提供重连，并按连接类型显示账号和服务器信息。；采用文件夹版本前明确告知保留副本，并保持原文件不被该操作覆盖。；保留 sheet 的独立呈现身份、原生取消语义及现有无障碍标识。

验证要求：OrgendaUITests/WorkspaceSyncUITests.swift:95 — testFolderPickerCanOpenAndCancel 覆盖从该页开启、取消存储选择器。；OrgendaUITests/WorkspaceSyncUITests.swift:161 — testChangingStorageWithPendingEditsRequiresKeepingCopies 覆盖保留副本说明、取消后连接和冲突不变。；OrgendaTests/Services/Workspace/WorkspaceConnectionTests.swift:475 — testAdoptFolderVersionsArchivesLocalDraftAndAllowsNextSave；:540 — testFailedAdoptionKeepsPendingDraft 验证采用版本时副本与失败保护。；未构建或运行测试；断开确认、操作禁用及 iPad 原生弹窗交互仍需运行时验证，静态检索未找到直接覆盖断开确认的 UI 测试。

代码依据：

- [Orgenda/Features/Settings/WorkspaceSettingsView.swift:14](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/WorkspaceSettingsView.swift:14) — 原生分组 List 按冲突、连接和错误状态组织内容及操作。
- [Orgenda/Features/Settings/WorkspaceSettingsView.swift:102](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/WorkspaceSettingsView.swift:102) — sheet(item:) 传递保留策略，两个 confirmationDialog 调用断开和采用版本业务方法。
- [Orgenda/Features/Settings/SettingsView.swift:68](/Users/roifewu/.config/orgenda/Orgenda/Features/Settings/SettingsView.swift:68) — workspace 导航目标实际构造该页面并注入完成工具栏。

API 依据：

- [iOS 27 SDK — SwiftUI List、Form 与原生呈现声明](/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface)：核对 List（8156）、Form（17167）、sheet(item:)（9143）、confirmationDialog 的 actions/message 重载（22483）及 presentationSizing（13911）；均可用于最低 iOS 27，现有界面已经使用对应系统能力。

专属分析 agent：`/root/audit_group_c/c136`。
