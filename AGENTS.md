# 命令

- 编译（暂无测试 target，这是目前唯一的检查）：`xcodebuild -project Bittern.xcodeproj -scheme Bittern -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`

# 约定

- 金融数据 quick to fail：不用 0、默认值或估算代替缺失数据，不静默丢弃持仓，不跨币种相加
- 现有代码里还有违反上一条的写法（见 ROADMAP.md 阶段 1），不要照抄
- 术语和业务含义以 CONTEXT.md 为准，与代码不一致时先指出来

# 注意

- 工程默认隔离是 `MainActor`，要在后台运行的代码需显式标 `nonisolated`
- 仓库是公开的，凭据只放在不入库的 `Bittern Local` scheme 里
