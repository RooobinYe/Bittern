# Logging

Bittern uses Apple Unified Logging through the loggers in
`Bittern/Utilities/AppLog.swift`. Do not add `print`, `NSLog`, or file-local
logger wrappers.

## Categories

- `Portfolio`: portfolio loading, refreshes, and aggregation
- `SnapTrade`: SnapTrade requests and responses
- `MarketData`: quotes, price history, and charts
- `Persistence`: cache reads and writes
- `Credentials`: credential setup and storage workflows
- `Images`: remote logo loading
- `Sharing`: share-sheet outcomes

Add a category to `AppLog` only when it represents a stable area that is useful
as a Console.app filter. Avoid categories named after individual types.

## Levels

- `debug`: successful flow details and high-volume diagnostics
- `info` or `notice`: infrequent, meaningful lifecycle events
- `warning`: a recoverable failure or fallback
- `error`: an operation failed or returned invalid data
- `critical`: the app cannot safely continue the current workflow

Unified Logging controls collection by level, so logging code must not use
`#if DEBUG` as its level policy.

## Privacy

Interpolated values are private by default. Portfolio symbols, prices, URLs,
provider data, response bodies, error text, and identifiers must stay private.
Use `privacy: .public` only for non-identifying diagnostics such as counts,
booleans, status codes, durations, and redacted paths. Never log credentials,
signatures, tokens, or unredacted account IDs.

```swift
import OSLog

AppLog.marketData.debug(
    "Quote completed symbol=\(symbol) status=\(status, privacy: .public)"
)
```

Use `AppLog.describe(_:)`, `AppLog.duration(since:)`, `AppLog.list(_:)`, and
`AppLog.optional(_:)` for consistent diagnostic formatting.

## Viewing logs

Filter Console.app by subsystem `com.robinye.Bittern`, then narrow by one of the
categories above. The same subsystem can be streamed from a connected runtime:

```sh
log stream --level debug --predicate 'subsystem == "com.robinye.Bittern"'
```
