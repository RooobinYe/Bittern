# Bittern

一个自用的 iOS 投资组合 App：通过 SnapTrade 读取各券商账户的持仓，用 TradingView 的行情实时计算市值、收益和配置比例，并帮助把一笔定投资金分配成可以直接下单的整股数量。

## 功能

- 汇总多个券商账户的持仓、收益和配置比例，盘前、盘后和夜盘报价单独显示
- 持仓走势图和组合历史
- 定投计算：按目标比例把一笔资金分到各账户的持仓上，算出每个账户要买多少

只支持单一币种（美元），不做汇率换算。

## 运行

- 用 Xcode 27 构建，App 最低支持 iOS 26.5
- 打开 `Bittern.xcodeproj`，运行 `Bittern` scheme
- 在 Settings 里填入 SnapTrade API Key，再从 App 里连接券商
- 行情默认直连 TradingView，也可以在 Settings 里改成自己的转发服务器

不想连真实账户时，用 Debug 构建并设环境变量 `BITTERN_DEMO=1` 启动，会显示示例组合，不读 Keychain、缓存和网络。

SnapTrade 的 Consumer Key 存在设备上，所以 Bittern 只适合个人使用，分发给别人需要先有后端。

## 文档

- [AGENTS.md](AGENTS.md)：编译、测试命令和开发约定
- [CONTEXT.md](CONTEXT.md)：术语的含义和已做的决定
- [ROADMAP.md](ROADMAP.md)：还没做的事
