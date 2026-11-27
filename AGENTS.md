# 命令

- 编译：`xcodebuild -project Bittern.xcodeproj -scheme Bittern -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`
- 测试：`xcodebuild test -project Bittern.xcodeproj -scheme Bittern -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 18 Pro' CODE_SIGNING_ALLOWED=NO`
- 模拟器看真实持仓：不要加 `CODE_SIGNING_ALLOWED=NO`（否则模拟器缺 entitlements 导致 Keychain 报 `-34018`），构建安装后运行 `bash scripts/use-real-holdings.sh [设备名]`

# 约定

- 金融数据 quick to fail：不用 0、默认值或估算代替缺失数据，不静默丢弃持仓，不跨币种相加
- 只支持单一币种，不做换算，理由见 `CONTEXT.md`
- 术语和业务含义以 CONTEXT.md 为准，与代码不一致时先指出来
- 分层：`Domain/` 只依赖 Foundation；client 只在 `App/AppDependencies.swift` 创建，界面从 environment 取 `PortfolioRepository` 和 `LogoSource`

# 注意

- 工程默认隔离是 `MainActor`，要在后台运行的代码需显式标 `nonisolated`
- 测试替换了 Keychain 和缓存文件，不要在测试里用默认的 `CredentialsStore` 或 `PortfolioCache`
- 仓库是公开的，凭据只放在不入库的 `Bittern Local` scheme 里
- 截图或演示用 Debug 构建并设环境变量 `BITTERN_DEMO=1` 启动：显示示例组合，不读 Keychain、缓存和网络（`simctl launch` 时写成 `SIMCTL_CHILD_BITTERN_DEMO=1`）
- 改动代码前在独立分支和 git worktree 中进行，不在主工作区 `main` 直接修改（优先用当前工具内置的 worktree 机制，否则默认建在 `.worktrees/<topic>`；纯问答或调研不建）
