# Portfolio Context

What Bittern's terms mean to the user and the decisions behind its behavior: only what the code can't say, such as choices that would otherwise look like bugs. Terms defined only in code take their meaning from there.

## Language

### Prices & Sessions

**Regular-Market Valuation**:
Holding and portfolio values based on the latest regular-session price. Pre-market, post-market, and overnight prices do not change portfolio totals, holding values, allocation, returns, or holding order.

**Pre-Market Holding Change**:
The estimated change in a holding's value derived from its quantity and Pre-Market Quote, accompanied by the quote's percentage change from the most recent regular close. During an Active Pre-Market Session with no observed trade yet, both changes are zero.

**Post-Market Holding Change**:
The estimated change in a holding's value derived from its quantity and Post-Market Quote, accompanied by the quote's percentage change from the immediately preceding regular close. During an Active Post-Market Session with no observed trade yet, both changes are zero.

**Overnight Quote**:
The latest available price from the current overnight session, the provider-scheduled interval between one trading day's post-market and the next trading day's pre-market (for US stocks 20:00–04:00 ET, Sunday evening into Monday included), measured relative to the most recent regular close and shown only as supplemental context, marked with a moon. It never moves a chart: the 1D Display Cycle ends with post-market.

**Overnight Holding Change**:
The estimated change in a holding's value derived from its quantity and Overnight Quote, accompanied by the quote's percentage change from the most recent regular close. During an Active Overnight Session with no observed trade yet, both changes are zero.

### Portfolio Valuation

**Complete Snapshot**:
A portfolio snapshot in which every holding has a current price. Only a Complete Snapshot records when its prices were known and is kept for the next launch, overwriting the one before; one with missing prices is shown with those holdings and all totals as N/A. The kept snapshot never expires by age: Stale Figures say how old it is.

### Freshness

**Launch**:
The time from having no portfolio in memory for the saved credentials until data or an error shows: a cold start, including after iOS ended the app in the background, or changed credentials. A Launch always shows the skeleton, unless data arrives within moments; with a kept Complete Snapshot it waits only for that snapshot's prices, then starts a Holdings Refresh. Returning from the background is not a Launch: the data stays, and new prices replace it.

**In-Session Holding**:
A holding whose price can move now: crypto always; anything else from the start of its exchange's pre-market to the end of its post-market, and through the overnight session that follows. A holding whose trading day isn't known yet counts as closed until a quote says more.

**Live Refresh**:
New prices for every In-Session Holding, fetched on a fixed interval while the app is in the foreground with a network path, and stopped in the background. New prices replace the figures in place, without animation. Regular-Market Valuation still holds: extended-hours quotes never change totals, allocation or order.

**Holdings Refresh**:
Accounts and holdings fetched again from SnapTrade behind the data on screen, when new prices arrive: once after a Launch with a kept Complete Snapshot, then whenever an hour has passed since holdings were last asked for, and on returning from SnapTrade's brokerage connection page. It shows no skeleton or spinner; a failure is silent and never turns figures gray, except SnapTrade refusing the credentials, which shows a banner. Nothing is refreshed by pulling.

**Stale Figure**:
A price-derived figure shown from the last data because current prices can't be had, or haven't arrived yet: there is no network path, the Market Data Connection is lost while prices may have moved since they were last known, or Live Refresh keeps failing. It is shown in gray, and VoiceOver adds when every price was last known. Names, logos, allocation bands and the legend aren't Stale Figures and keep their colors. A closed market's close is its current price, so it is not a Stale Figure; but prices may have moved unless every holding's market is known to have stayed closed since they were last known, which needs its next trading day to be known.

**Market Data Connection**:
The one WebSocket market data comes through, to TradingView or through the user's own server. It is live while the server has sent something, a heartbeat at least, within two missed heartbeats and five seconds (25 seconds with TradingView's 10-second heartbeat). A closed socket, or one silent for longer, is lost; after time in the background that is usually the case, so returning reopens it. A network path on the device doesn't make it live: only the server's heartbeat says the whole way to it works.

**Bar in Progress**:
The last point of a holding's chart range: the bar whose interval includes now (1D 5 minutes, 5D 15 minutes, 1M an hour, 3M, YTD and 1Y a day, 5Y a week, MAX a month), whose close follows the live price. A point is added only when the next interval begins. Pre- and post-market quotes move only the 1D Extended-Hours Continuation, and Overnight Quotes no chart; 5D and longer follow the regular session.

**Attention**:
A problem only the user can fix, such as SnapTrade refusing the credentials or a disabled brokerage connection. Over data it is a banner, kept until the problem is gone; with no data, the error page. Problems that may pass on their own are retried and never become Attention.

### Contribution Planning

**Contribution Plan**:
The single persisted set of holding elections and Target Percentages that carries across sessions, never including the Contribution Amount.

## Flagged ambiguities

- "定投目标" could read as symbol-level (one target per ticker) — resolved: targets are **account-level**, because the calculator's output must be executable buy amounts per account.
- "勾选" (election) was conflated with "购买" (purchase) — resolved: an **Elected Holding** may legitimately end the session with a **Buy Amount** of zero.
- Targets summing below or above 100% — resolved: no auto-normalization and no implicit cash remainder; results exist only at exactly 100%.
- Whether **Residual Cash** belongs in the **Post-Contribution Percentage** denominator — resolved: excluded, matching the app-wide holdings-only allocation semantics (the app has no cash concept).
- Whether leftover cash should be greedily re-deployed into extra whole shares — first resolved as never (mental verifiability), revised 2026-08-11 after real use left ~20% of a contribution unspent: Greedy Top-Up re-deployed it, but a zero-Buy-Amount holding is still never bought.
- How "closest to target" trades off against "least cash left over" — resolved 2026-08-11, superseding Greedy Top-Up: the user accepted trading mental verifiability for optimality and delegated the weighing; both failure modes are priced in dollars at 1:1 as **Misallocation**, which a completed **Optimal Share Search** minimizes exactly (ties break toward less Residual Cash), still never buying a zero-Buy-Amount holding. Reaching the safety node limit instead surfaces the incumbent as an **Estimated Result**.
- Holdings with no current price pass the minimum-value filter but have no Regular-Market Valuation — resolved: they are never electable; a Contribution Pool containing an unpriced holding is undefined.
- Whether Bittern should support several currencies — resolved 2026-11-06: no. The portfolio is entirely in US dollars, so conversion and per-currency subtotals would be unused machinery. What stays is a guard against ever summing unlike amounts.
- What a `cost_basis` of zero means — resolved: the broker doesn't know the cost, not that the position was free. It is treated as unknown.
- Whether a position's `cost_basis` is a total or a per-unit price — resolved 2026-11-06: per unit. SnapTrade documents it as the "book price or average purchase price", and real holdings show it at the scale of the share price, not of price × quantity.
- Degenerate inputs (Contribution Amount of zero, or zero Elected Holdings) — resolved: no results are shown; there is no zero-money allocation.
- How the app says data is loading, live or out of date — resolved 2026-11-08: with no status text at all, TradingView-style. The skeleton says data is on its way, figures that move say they are live, and gray says they aren't current; only Attention gets words. "Updated" is no longer shown, on screen or in the shared image.
- Whether "Today" should change when figures are Stale — resolved 2026-11-08: no. It names the return mode (the most recent session's change, paired with All time), not the calendar day, just as it shows Friday's change on a Sunday.
- Whether the kept Complete Snapshot should expire — resolved 2026-11-08: no. Old isn't wrong; gray and VoiceOver's date say how old it is. It is deleted when credentials are cleared or changed.
- When figures turn gray on returning from the background — resolved 2026-11-09: as in TradingView's app, gray at once when the **Market Data Connection** is lost and prices may have moved, and in color again with the first new prices. Until then the figures are the ones from before the background, not current ones. Failures with the connection live, such as quotes not arriving, still turn figures gray only after Live Refresh fails three times in a row.
- Whether to keep pull to refresh — resolved 2026-11-12: no, on no screen. Prices refresh themselves through Live Refresh, holdings through Holdings Refresh, and charts follow live prices; holdings change only when the user trades or connects a brokerage, so an hour is soon enough.
