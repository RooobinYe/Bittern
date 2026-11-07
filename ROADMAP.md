# Roadmap

Bittern 接下来的修改计划，按建议顺序排列。

- 术语以 [CONTEXT.md](CONTEXT.md) 为准。
- 这里只写还没做的事，完成后勾选，整个阶段完成后可以删除。
- 最后更新：2026-11-08

## 阶段 5：新机型适配

- [ ] 适配 iPhone Duo（外屏 5.4 英寸，内屏 7.6 英寸）

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
