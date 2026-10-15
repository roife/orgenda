# 系统组件替换实施记录（2026-10-15）

本次承接 [136 项组件审查](NativeComponentReview-2026-10-15.md) 中的 3 项局部替代和 4 项原型候选。在当前 `main` 分支修改，没有运行格式化工具；保留了开始本次工作前已有的未提交改动。

## 实施结果

| 编号 | 组件 | 结果 | 实现与保留的行为 |
| --- | --- | --- | --- |
| C001 | `OrgendaCalendar` 周分页 | 已替换 | 使用原生 `ScrollView`、`LazyVStack`、`scrollPosition` 与分页目标；与月分页共享容器。删除手工拖动阈值、位移、方向及页面 transition 状态，保留日格、选日、密度伸缩和业务联动。 |
| C013 | `OrgEditorTextView` 初始化 | 已替换 | 由 `UITextView(frame:textContainer:nil)` 创建 TextKit 2 对象链。保留子类、文档级撤销管理器、文本容器宽度与容量设置。 |
| C089 | `OrgItemEditor` 的 Source / File 行 | 已替换 | 使用 `LabeledContent`。文件路径仍可换行、选择文字，沿用原有字体与次要颜色。 |
| C041 | `AgendaView` 标题入口 | 原型通过，已采用 | 使用 `navigationTitle` 和 `toolbarTitleMenu`，保留原有 `Picker` 与视图切换逻辑。侧栏显示或工作区忙碌时提供静态标题，避免开放不可用的切换动作。 |
| C088 | `OrgItemDetailsSection` 的 Tags 行 | 原型通过，已采用 | 使用 `LabeledContent`，保留原有多行 `TextField`、1–4 行高度、焦点、提交行为与输入提示。 |
| C105 | `SearchEmptyState` | 原型通过，已采用 | 使用 `ContentUnavailableView` 的 label / description / actions 构造器，保留现有文案、扩大范围和清空操作，以及可滚动的空状态容器。 |
| C085 | `WorkspaceFolderDropTarget` | 两个原型未通过，保留原实现 | SwiftUI 行内目标和独立透明覆盖层都未完成现有文件夹子树移动测试；恢复公开 UIKit `UIDropInteraction` 适配层后同一测试通过。该文件与本次开始时完全一致。 |

六项采用的改造合计减少 **53 行应用 Swift 代码**；这个数字不包含此前重构、测试、文案及记录文件。

## 原型发现与处理

### 周分页

`.viewAligned(limitBehavior: .alwaysByOne)` 无法保留现有“快速拖动也只移动一周”的行为：周页面很短，手指释放前已跨过多页。最终使用系统 `PagingScrollTargetBehavior`，增加一个很小的 `ScrollTargetBehavior`，将最终目标限制在手势起点前后一周。系统仍负责手势识别、滚动和减速。

周选择只在用户滚动结束时提交。初版在 `scrollPosition` 每次变化时提交，会把初始化、时间线联动或跨月选日触发的程序滚动误当作选日；与旧实现对照后已修正，相关回归通过。锚点到达分页范围边界时重新居中，避免引入固定的最早或最晚可翻周。

### 日程标题菜单与 iPad 测试

系统标题按钮的辅助功能标签直接使用当前标题，没有原先自定义的 `agenda.viewMenu` 值。测试改为读取系统导航按钮及实际选择结果。启动期间使用静态标题，继续验证加载前后导航栏位置稳定。

iPad 测试还需处理系统恢复的侧栏折叠状态，并用导航单元格选择条目，避免误点同名标题。顶栏唯一性按同一行的实际渲染位置统计，排除系统标题菜单及 UIKit 对同一位置暴露的重复辅助功能节点。返回 Dashboard 时使用顶栏标签，避免把可折叠侧栏分组当成目的地；旧实现也复现了这一测试定位问题。

### 搜索空状态

保留 `.orgendaEmptyState()` 的滚动适配。普通字号和最大辅助字号均检查空白引导、无结果、清空及扩大搜索范围。切换范围菜单后重新点击输入框再输入，以覆盖 iPad 的正常焦点切换。

另在手机模拟器实际显示软件键盘，通过屏幕键输入并清空搜索，录制键盘出现过程。逐帧检查显示内容随键盘连续调整，稳定后未观察到原注释提到的二次位置跳动；这只是本次 iOS 27 模拟器场景的验证结论。

手机最大字号加软件键盘的复测最初失败：XCTest 默认 `swipeUp` 起点落在键盘覆盖区域，没有滚动内容。改成在范围菜单与搜索框之间的可见内容区拖动后，清空及扩大范围均通过；应用实现无需额外适配。旧空状态在相同条件下也通过，滚动到操作区时的搜索栏覆盖呈现相同。

### 文件夹拖放

两次 SwiftUI 原型均保留完整 `WorkspaceFileTransfer`、本地单项 move 约束和现有 `canMoveFile` 校验，但文件夹目标没有完成移动，无法出现预期的撤销入口。证据与 `List` 行内投放路由未到达目标相符；没有声称系统内部原因已被证明。

保留现有 UIKit 适配层，避免以简化代码为代价损失拖放。失败原型未留在生产代码中。

## 验证

- 环境：Xcode / iOS 27，iPhone 18 Pro 模拟器及 iPad Pro 13-inch (M5) 模拟器。
- **391 项单元测试通过**，包含 TextKit 2、组合输入保护、撤销、源位置以及日历尺寸测试。
- **20 项不同的 iPhone UI 用例最终通过**：周/月/年分页、快速手势、跨月选日、返回今天、时间线联动、辅助字号、标签保存重开、源码撤销与模式切换、搜索恢复、日程标题切换、启动状态，以及恢复后的文件夹拖放。
- **7 项 iPad UI 用例最终通过**：日历与日记横竖屏切换、搜索往返、侧栏选择与隐藏后标题恢复、竖屏侧栏自动关闭、顶栏条目唯一性、辅助字号标签编辑及搜索恢复。
- 已检查代码差异空白错误、文案 JSON，以及文件夹拖放实现与起始版本的一致性。
- 所有旧实现对照完成后，已恢复最终代码并再次构建、启动成功。

测试分批执行；初版原型发现的失败已修正并针对性复测，未把失败轮次包装成一次全绿执行。验证不包含真机手感或所有辅助技术组合。

## 本机证据

所有测试结果及原型备份位于 `/tmp/orgenda-system-refactor/`，临时文件可能被系统清理。

| 文件 | 内容 |
| --- | --- |
| `regression-iphone.xcresult` | 391 项单元测试及主交互回归；其中初版的三项 UI 失败在后续结果中修正。 |
| `regression-fixes.xcresult` | 时间线联动、跨月选日、周分页、搜索与启动状态，5/5 通过。 |
| `native-controls-third.xcresult` | 普通 / 最大辅助字号标签、周分页与搜索，5/5 通过。 |
| `native-controls.xcresult` | 系统标题菜单，以及恢复 UIKit 后的文件夹移动测试通过。 |
| `first-prototypes.xcresult`、`folder-overlay-prototype.xcresult` | 两种 SwiftUI 文件夹投放原型失败的记录。 |
| `regression-ipad.xcresult`、`ipad-baseline.xcresult`、`ipad-fixes.xcresult` | iPad 原型、旧实现对照和定位修正后的回归。 |
| `ipad-tabs-final.xcresult` | 系统顶栏与侧栏反复切换，1/1 通过。 |
| `phone-software-keyboard-final.xcresult`、`phone-ax-search-final.xcresult` | 手机软件键盘条件下的搜索与最终周分页；最大字号搜索修正测试手势定位后通过。 |
| `search-keyboard-baseline.xcresult` | 旧搜索空状态在同一最大字号、软件键盘场景下的对照，1/1 通过。 |
| `search-software-keyboard.mp4`、`software-keyboard-transition.png` | 实际软件键盘录像及键盘出现过程的逐帧联系表。 |
| `iphone-final-test-index.json`、`ipad-final-test-index.json` | 按用例去重的最后通过结果及其结果包。 |
