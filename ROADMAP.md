# Roadmap

Bittern 接下来的修改计划，按建议顺序排列。

- 术语以 [CONTEXT.md](CONTEXT.md) 为准。
- 这里只写还没做的事，完成后勾选，整个阶段完成后可以删除。
- 最后更新：2026-11-06

## 阶段 3：架构整理

**目标：** 依赖方向清晰，领域逻辑可以脱离 UI 和网络单独测试。

目标结构：

```text
Bittern/
├── App/           入口与依赖组装
├── Domain/        纯逻辑，不依赖 SwiftUI 和网络
├── Data/          SnapTrade、Yahoo、Brandfetch、Repository、Cache
├── Features/      Dashboard、HoldingDetail、History、Contributions、Settings
└── DesignSystem/
BitternTests/
```

**分层**

- [ ] 按目标结构调整目录
- [ ] 把 1D 时段逻辑从 `YahooFinanceClient` 抽成纯函数，阶段 1 的 fixture 测试作为安全网
- [ ] 把服务商细节移出领域模型：`HoldingChartRange` 的 `yahooRange`、`yahooInterval`，`PortfolioInstrumentKind.init(snapTradeValue:)`
- [ ] 把排序逻辑移出主题：`BitternTheme.sortedAllocationHoldings`
- [ ] 把 View 里的业务逻辑收进 Repository：历史聚合、SnapTrade 注册与连接门户、价格历史
- [ ] 让 `LivePortfolioRepository` 的 client 可注入，不再在内部创建（`URLSession` 和时钟已可注入）

**网络与错误**

- [ ] 合并 `YahooFinanceClient` 里三处重复的请求、解码和错误检查
- [ ] 错误类型不再用 `httpStatus(-1, …)` 表示非 HTTP 错误
- [ ] 部分成功改用返回值表达：去掉 `PortfolioExtendedHoursRefreshError`，并入 `PortfolioLoadResult`

**状态**

- [ ] 简化 `DashboardViewModel` 的刷新状态（包括多余的 `hasPortfolioBaseline`），并把 `UserDefaults` 改成可注入
- [ ] 补 `DashboardViewModel` 刷新测试：加入进行中的刷新、被新请求替代、丢弃过期结果
- [ ] `ObservableObject` 换成 `@Observable`，用 `.task(id:)` 取代 `CancelableTaskRunner`
- [ ] `minPriceThreshold` 只保留一个数据来源（现在 `@AppStorage` 和 ViewModel 各存一份）
- [ ] `ContributionCalculatorView` 每次渲染只计算一次结果（现在是持仓数 + 4 次）
- [ ] 导航按 `holding.id` 传值并查最新数据，避免详情页拿到刷新前的旧持仓

**视图拆分**

- [ ] 拆分大文件：`DashboardView.swift`、`YahooFinanceClient.swift`，把 `SnapTradeClient.swift` 的 DTO 分开
- [ ] 截图模式和视图解耦：叶子视图不再判断 `isRenderingScreenshot`，交互控件在外层包裹，去掉 `AccountTabLabel` 和 `AccountTabButton` 的重复

**完成标准：** `Domain/` 不依赖 SwiftUI 和网络，View 不直接创建 client，没有超过 500 行的文件。

## 阶段 4：设计与 HIG

**目标：** 少自定义，多用系统组件。以 Contributions 页的克制为基准，推广到全局。

**信息架构**

- [ ] 用 TabView 分成 Portfolio、History、Contribute
- [ ] 设置改成 sheet 打开，入口换成 `gearshape`
- [ ] 删除 App 内的 Appearance 设置（HIG 建议跟随系统）
- [ ] Minimum Market Value 挪到 Holdings 的菜单，并提示已隐藏几个持仓
- [ ] 合并 Portfolio Accounts 和 Credentials 的凭据部分，用一个 Form
- [ ] 凭据默认遮盖，查看时走 Face ID
- [ ] 清除凭据前加确认（userSecret 只生成一次，删掉后 App 内无法找回）
- [ ] 空状态改用 `ContentUnavailableView`，并提供“连接券商”按钮

**字体**

- [ ] 全局改用 SF Pro，移除 `.fontDesign(.rounded)` 和各处的 `.fontDesign(.default)`
- [ ] 收敛字重：正文和次要信息回到 Regular，去掉 `.headline.bold()`
- [ ] 重排 Detail 页层级：只有价格用大号粗体，Section 标题用 Title 3，数据行用 Body（导航标题已是股票代码，全名留在页面顶部）
- [ ] 减少 `minimumScaleFactor` 和写死的高度，图标尺寸用 `@ScaledMetric`，并在最大无障碍字号下检查

**颜色与材质**

- [ ] 内容层去掉 Liquid Glass：持仓气泡和图表游标改用实色或普通材质，并解决气泡重叠
- [ ] 提高对比度：浅色模式的涨跌文字、图表基线标签、无 logo 时的白字
- [ ] 统一卡片样式，用系统分组样式替代 8pt 圆角加描边的 `bitternPanel`

**控件**

- [ ] 账户筛选改用 `toolbarTitleMenu` 或工具栏 Menu，隐私开关移到工具栏
- [ ] 排序和收益模式菜单改用 `Picker`，显示当前选项
- [ ] 所有控件的点击区域不小于 44×44 pt
- [ ] 持仓列表改用 `List`，恢复按压高亮和系统行为
- [ ] 用 Swift Charts 替换 Canvas 折线图，加上坐标轴，并用 `SectorMark` 重做 donut
- [ ] 为自定义选择控件加 `.isSelected` 无障碍状态

**文案与格式**

- [ ] 界面文案去掉内部术语（Elect 等），修正已过时的 “The full amount is spent…”
- [ ] 统一缺失值（`N/A` 或 `--`）和分隔符（`|` 或 `·`）
- [ ] 用 `FormatStyle` 替代 `NumberFormatter` 和写死的 `en_US_POSIX`，时间跟随系统 12/24 小时制

**完成标准：** VoiceOver 能读出图表和当前选中项，最大无障碍字号下关键数字不被截断，浅色和深色下正文对比度都不低于 4.5:1。

## 阶段 5：新机型适配

- [ ] 适配 iPhone Duo（外屏 5.4 英寸，内屏 7.6 英寸）

## 阶段 6：更换 App 图标

**设计思路：** 背景按黄金比例分成四块，每块一种颜色，上面覆盖一个液态玻璃的圆。

- [ ] 确定四块的划分方式和配色
- [ ] 用 Icon Composer 做分层图标：背景色块和圆分在不同层，圆用系统的液态玻璃材质
- [ ] 检查浅色、深色和染色模式下的效果，替换现有的 `AppIcon`（目前是三张 PNG）

## 待确认

- [ ] 是否继续支持 iPad：如果不用，改成 iPhone-only；删除 split 布局前，先确认 iPhone Duo 的内屏是否用得上它
- [ ] 是否计划分发给别人：Consumer Key 现在存在设备上，只适合个人使用，分发前需要后端
- [ ] 用同一个 userId 重复注册 SnapTrade 时的返回值
- [ ] 运行时验证：图表的 `DragGesture(minimumDistance: 0)` 是否挡住页面滚动
- [ ] 运行时验证：Settings、Portfolio Accounts、Credentials 和 History 的实际渲染效果
- [ ] 运行时验证：真实账户的 `balanceHistory` 符合 OpenAPI（History 页现在缺 `currency` 或含坏数据点时会直接报错）；持仓和分红已在真实账户上验证
- [ ] 把 SnapTrade 测试 fixture 换成脱敏后的真实响应：现在按公开的 OpenAPI 手写

## 暂不做

- 金额从 `Double` 换成 `Decimal`：App 只展示不下单，目前够用
- 多币种支持（汇率换算、分币种小计、`Money` 类型）：持仓只有美元，见 [ADR 0002](docs/adr/0002-single-currency-portfolio.md)
- 把定投搜索移出主线程：在 Mac 上用 Release 构建实测，普通组合每次渲染不到 1ms，极端输入（35 只持仓）约 88ms
- 定投配置对比图：V1 决定只显示行内数字
