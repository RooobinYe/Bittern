# Roadmap

Bittern 接下来的修改计划，按建议顺序排列。

- 术语以 [CONTEXT.md](CONTEXT.md) 为准。
- 这里只写还没做的事，完成后勾选，整个阶段完成后可以删除。
- 最后更新：2026-11-07

## 阶段 4：设计与 HIG

**目标：** 少自定义，多用系统组件。以 Contributions 页的克制为基准，推广到全局。

**有意保留的偏离：** 分配卡片的透镜和图例胶囊、图表游标继续用玻璃效果，这是 Bittern 的视觉特色，不按 HIG 改成实色。

**标注“先试”的条目：** 先做出来，再截图给用户对比，由用户决定是否采用；效果变差就按条目里写的退路处理。

**信息架构**

- [x] 用 TabView 分成 Portfolio、History、Contribute，History 和 Contribute 从 Settings 里移出（Contribute 常用，History 不常用但也不属于设置）
- [x] Portfolio 的工具栏只用右侧：隐私开关、Share、`gearshape`，左侧留空；Settings 改成 sheet 打开
- [x] 账户筛选改用 `toolbarTitleMenu`，点标题切换账户（标题菜单只挂在 inline 标题上，Portfolio 因此改用 inline 标题；只有一个券商时不显示菜单）
- [x] 删除 App 内的 Appearance 设置（HIG 建议跟随系统）
- [x] Minimum Market Value 挪到 Holdings 的菜单，并提示已隐藏几个持仓（阶段 4.2 又移回 Settings，见下）
- [x] 合并 Portfolio Accounts 和 Credentials 的凭据部分，用一个 Form
- [x] 凭据默认显示为遮盖，点眼睛图标直接显示，不做 Face ID（个人使用，只防截图和录屏）
- [x] 清除凭据前加确认（userSecret 只生成一次，删掉后 App 内无法找回）
- [x] 空状态改用 `ContentUnavailableView`，并提供“连接券商”按钮

**字体**

- [x] 全部改用 SF Pro，和系统 App 一致（对比过“全圆体”“全 SF Pro”“折中”三版）；关键数字仍用 `Font.keyFigure(_:)`，只保留等宽数字
- [x] 收敛字重：正文和次要信息回到 Regular，去掉 `.headline.bold()`
- [x] 重排 Detail 页层级：只有价格用大号粗体，Section 标题用 Title 3，数据行用 Body（导航标题已是股票代码，全名留在页面顶部，用 Title 3 和主文字色，灰色在分组背景上不到 4.5:1）
- [x] 减少 `minimumScaleFactor` 和写死的高度，图标尺寸用 `@ScaledMetric`，并在最大无障碍字号下检查

**颜色与材质**

- [x] 解决持仓气泡重叠：按气泡宽度算出最小角度间隔，沿圆周把挤在一起的气泡推开，放不下时改成内外两圈交错；气泡包进 `GlassEffectContainer`，保留 `.glassEffect`
- [x] 重做图表游标：数据点用实色小圆点加背景色描边，往上画细竖线，顶端浮一个玻璃胶囊显示日期（对比过“日期 + 数值”和“贯穿整图的竖线”，选了只显示日期，数值看页面顶部）
- [x] 涨跌色在 asset catalog 里定义：浅色模式用更深的红绿，红 `#D70015`，绿以 `#248A3D` 为基础再压暗到白底 4.5:1 以上；深色模式保留 `systemGreen` 和 `systemRed`
- [x] 图表基线标签去掉额外的 `.opacity(0.62)`，直接用 `.secondary`
- [x] 无 logo 时按底色亮度选黑字或白字，不写死白色（混灰后的橙、黄配白字只有约 2.7:1）
- [x] 错误 toast 保留液态玻璃（属于控件层），去掉多余的 `.shadow`，出现时发 VoiceOver 通知
- [x] 统一卡片样式，用系统分组样式替代 8pt 圆角加描边的 `bitternPanel`

**控件**

- [x] 排序和收益模式菜单改用 `Picker`，显示当前选项
- [x] 所有控件的点击区域不小于 44×44 pt
- [x] （真实数据下滚动、按压高亮和跳转正常）先试：整页改成 `List`，恢复按压高亮和系统行为；如果 donut、滚动或横屏分栏变差，保留现在的写法，只补按压高亮和点击区域
- [x] （用户在真实数据下确认）先试：用 Swift Charts 重写折线图，坐标轴从简（不画网格，纵轴放右侧只标 3 个值，横轴只标几个日期），用 `chartXSelection` 处理拖动，游标在 `chartOverlay` 里自己画；盘前盘后的灰线拆成单独的 series；效果不如现在的 Canvas 就截图对比，由用户决定
- [x] donut 保留手绘，不用 `SectorMark`（气泡位置依赖自己算的角度），用 `accessibilityChartDescriptor` 补上无障碍
- [x] 为自定义选择控件加 `.isSelected` 无障碍状态

**文案与格式**

- [x] 界面文案去掉内部术语（Elect 等），修正已过时的 “The full amount is spent…”
- [x] 统一缺失值（`N/A` 或 `--`）和分隔符（`|` 或 `·`）
- [x] 用 `FormatStyle` 替代 `NumberFormatter` 和写死的 `en_US_POSIX`，时间跟随系统 12/24 小时制

**完成标准：** VoiceOver 能读出图表和当前选中项，最大无障碍字号下关键数字不被截断，浅色和深色下正文对比度都不低于 4.5:1。

## 阶段 4.1：重新设计主页圆环

**目标：** 用 Claude Design 重构 Portfolio 页的圆环（环形图、持仓气泡、中心的总额和涨跌），先出方案再实现。

- [x] 用 Claude Design 做几版圆环的重构方案，给用户对比后选定一版（在真实持仓上对比过透镜、串珠、色晕、水滴、玻璃管和色带透镜，选了色带透镜：参考 Paletto 的图标，持仓按占比叠成横向色带，上面压一块厚玻璃透镜）
- [x] 实现选定的方案：色带颜色按排名取一条从深靛蓝到浅黄的渐变；透镜只用高透液态玻璃（试过 Metal 着色器：能把色带弯成碗，但只弯得到卡片，拖出卡片后效果不一致，还要另装 Metal Toolchain；用户选了只用液态玻璃）；透镜可以拖到页面任何地方，松手弹回卡片中间；总额放在卡片上方左对齐（对比过印在卡片正中，透镜一压上去数字就变形），点涨跌那一行切换 Today / All-time；图例用高透玻璃胶囊；没有 logo 的圆标在图例、持仓行、设置、定投和详情页都取所在色带的颜色（小持仓共用“其他”那条，没有市值的用灰色），排名变了颜色跟着变

## 阶段 4.2：细化 UI/UX 细节

条目和用户逐项讨论后补充。

- [x] 删掉 Settings 里透镜液态玻璃的 Debug 开关
- [x] 删掉 Holdings 列表底部的 “3 holdings under US$1.00 hidden”：低于门槛的持仓只有几美分，不值得在首页占一行、吸引注意力；只在全部持仓都被隐藏、列表为空时说明原因
- [x] Minimum Value 从 Holdings 菜单移到 Settings 最上面，显示当前门槛和隐藏了几个：它设一次就很少改，而且作用于整个 App，放在 Holdings 菜单里像只影响这个列表
- [x] 详情页收益等式的三个标题（Price Gain、Dividends、Total Return）改成和上面几行一样的黑色正文，金额和百分比保留涨跌色；等式布局不变（各项分别取整后对不上一两美元属正常）
- [x] 图表基准线的价格胶囊往左移出 5 pt 内边距，胶囊里的数字和纵轴上其他价格对齐（之前在截图上量过，正好偏右 5 pt）
- [x] 详情页图表加上 1M 和 YTD，共 1D 5D 1M 3M YTD 1Y 5Y MAX：1M 用 Yahoo 的小时数据，YTD 从去年最后一个收盘价算涨跌（拿不到就报错，不用今年第一个点代替，否则和外面公布的 YTD 对不上）；YTD 在今年才上市的持仓上等于 MAX，不显示，每年前 7 天点太少也不显示。8 个区间按标签自身宽度排开、间距相等（等宽格子会让 MAX、YTD 两边显得挤），字号大到一行放不下时改成横向滚动，不截断
- [x] 往下滑时 tab 栏缩成左下角只显示当前 tab 的小按钮（`tabBarMinimizeBehavior(.onScrollDown)`），持仓列表多露出几行；点小按钮或回到顶部恢复。代价是小按钮滚过时会短暂盖住行首的 logo，列表中间切 tab 要多点一下，和系统 App 一致

## 阶段 5：新机型适配

- [ ] 适配 iPhone Duo（外屏 5.4 英寸，内屏 7.6 英寸）

## 阶段 6：更换 App 图标

**设计思路：** 背景按黄金比例分成四块，每块一种颜色，上面覆盖一个液态玻璃的圆。

- [x] 确定四块的划分方式和配色：和分配卡片一样叠成横向色带，从上到下由大到小，每块是下一块的 φ 倍（约 45% / 28% / 17% / 11%），颜色取卡片色带渐变的两端和三等分点（`#413C9B` `#008CBB` `#00CA8D` `#EFE345`），图标就是一张缩小的分配卡片
- [x] 用 Icon Composer 做分层图标：`Bittern/AppIcon.icon`，色带一层不加玻璃，圆一层用液态玻璃并开折射（强度和深度 0.3，色带边界在圆里弯成 Paletto 那样的圆角），圆里压 10% 黑让透镜有厚度（试过白色半透明，会把颜色洗淡）
- [x] 检查浅色、深色和染色模式下的效果，替换现有的 `AppIcon`：用 Icon Composer 自带的 `ictool` 渲染了 Default、Dark、Tinted、Clear 六种，色带亮度单调递增，染色和透明模式下仍分得清四块；已删掉三张 PNG，模拟器主屏幕上显示正常
- [x] 透明和染色图标单独设计：实色色带在透明模式下会让整块图标变成近乎不透明的白板，和系统图标的玻璃质感不一致；这两种模式下隐藏色带，改用 `bands-mono.svg` 在色带交界处画白线，透镜照样把线折弯。对比过“色带改成四档透明度的白色”，在主屏幕上仍然发白，没有采用。浅色和深色的渲染结果和之前完全一样
- [x] 分享面板顶部显示 App 图标：之前没给 `SharePreview` 图标，系统显示空白的网格占位图（换图标前就这样）；App 图标不能用 `UIImage(named:)` 读取，所以用 `scripts/export-share-icon.sh` 从 `AppIcon.icon` 导出 `ShareIcon`（浅色和深色各一套），改了图标后要重新运行；在模拟器的浅色和深色模式下都看过

## 待确认

- [ ] 透镜移到卡片下方时在 HDR 屏幕上发出比白色还亮的光：怀疑是透镜的液态玻璃（也可能是标签栏的）
- [ ] 是否继续支持 iPad：如果不用，改成 iPhone-only；删除 split 布局前，先确认 iPhone Duo 的内屏是否用得上它
- [ ] 是否计划分发给别人：Consumer Key 现在存在设备上，只适合个人使用，分发前需要后端
- [ ] 用同一个 userId 重复注册 SnapTrade 时的返回值
- [ ] 运行时验证：Settings、Portfolio Accounts、Credentials 和 History 的实际渲染效果
- [ ] 运行时验证：真实账户的 `balanceHistory` 符合 OpenAPI（History 页现在缺 `currency` 或含坏数据点时会直接报错）；持仓和分红已在真实账户上验证
- [ ] 把 SnapTrade 测试 fixture 换成脱敏后的真实响应：现在按公开的 OpenAPI 手写

## 暂不做

- 金额从 `Double` 换成 `Decimal`：App 只展示不下单，目前够用
- 多币种支持（汇率换算、分币种小计、`Money` 类型）：持仓只有美元，见 [ADR 0002](docs/adr/0002-single-currency-portfolio.md)
- 把定投搜索移出主线程：在 Mac 上用 Release 构建实测，普通组合每次渲染不到 1ms，极端输入（35 只持仓）约 88ms
- 定投配置对比图：V1 决定只显示行内数字
