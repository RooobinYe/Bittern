# Portfolio Context

This context defines the user-facing meaning of asset prices, portfolio valuation, and chart ranges across assets with different trading schedules, how current the figures on screen are, plus the contribution-planning language built on those valuations.

## Language

### Prices & Sessions

**Full-Day 1D Window**:
A provider-defined regular period that covers an entire day. Its observed prices occupy the full chart width rather than reserving space for the remainder of the day.
_Avoid_: Crypto session, rolling 24 hours

**Bounded 1D Session**:
A provider-defined regular period shorter than a full day, with explicit opening and closing boundaries. Price observations retain their true positions within those boundaries.
_Avoid_: Today, first-to-last-point range

**1D Display Cycle**:
The latest relevant Bounded 1D Session together with its following post-market observations and, before the next regular open, the next pre-market observations.
_Avoid_: Calendar day, rolling 24 hours

**Extended-Hours Continuation**:
Pre-market or post-market observations attached to a 1D Display Cycle as a neutral-colored continuation of the regular-session trace. A no-trade gap between post-market and the next pre-market is not part of the continuation.
_Avoid_: Second chart, gain/loss trace

**Session Transition Segment**:
The chart segment joining the final regular-session observation to the first following extended-hours observation. It belongs to neither session exclusively and does not introduce an additional price observation.
_Avoid_: Boundary point, overlap point, session divider

**Regular-Market Valuation**:
Holding and portfolio values based on the latest regular-session price. Pre-market, post-market, and overnight prices do not change portfolio totals, holding values, allocation, returns, or holding order.
_Avoid_: Live valuation, extended-hours valuation

**Pre-Market Quote**:
The latest available price from the current pre-market session, measured relative to the most recent regular close and shown only as supplemental context.
_Avoid_: Current price, portfolio value, overnight quote

**Active Pre-Market Session**:
The provider-scheduled interval before the current regular session, while the current instant falls within its start and end boundaries. Historical pre-market observations alone do not make the session active.
_Avoid_: Device-local evening, latest extended-hours data

**Pre-Market Holding Change**:
The estimated change in a holding's value derived from its quantity and Pre-Market Quote, accompanied by the quote's percentage change from the most recent regular close. During an Active Pre-Market Session with no observed trade yet, both changes are zero.
_Avoid_: Pre-market market value, current holding gain

**Post-Market Quote**:
The latest available price from the current post-market session, measured relative to the regular close that immediately precedes it and shown only as supplemental context.
_Avoid_: Current price, portfolio value, next-day quote

**Active Post-Market Session**:
The provider-scheduled interval after the current regular session, while the current instant falls within its start and end boundaries. Historical post-market observations alone do not make the session active.
_Avoid_: Device-local night, latest extended-hours data

**Post-Market Holding Change**:
The estimated change in a holding's value derived from its quantity and Post-Market Quote, accompanied by the quote's percentage change from the immediately preceding regular close. During an Active Post-Market Session with no observed trade yet, both changes are zero.
_Avoid_: Post-market market value, current holding gain

**Overnight Quote**:
The latest available price from the current overnight session, the provider-scheduled interval between one trading day's post-market and the next trading day's pre-market (for US stocks 20:00–04:00 ET, Sunday evening into Monday included), measured relative to the most recent regular close and shown only as supplemental context, marked with a moon. It never moves a chart: the 1D Display Cycle ends with post-market.
_Avoid_: Night quote, next-day quote, 24-hour price

**Active Overnight Session**:
The overnight session that follows the latest trading day, while the current instant falls within its start and end boundaries. Historical overnight observations alone do not make the session active.
_Avoid_: Device-local night, closed market

**Overnight Holding Change**:
The estimated change in a holding's value derived from its quantity and Overnight Quote, accompanied by the quote's percentage change from the most recent regular close. During an Active Overnight Session with no observed trade yet, both changes are zero.
_Avoid_: Overnight market value, current holding gain

**Regular-Session Holding Change**:
The change in a holding's value across the most recently completed regular session, measured from the preceding regular close to the latest regular close. It remains distinct from any subsequent Pre-Market or Post-Market Holding Change.
_Avoid_: Current change, pre-market change, after-hours change

### Portfolio Valuation

**Portfolio Currency**:
The single currency every holding in a sum shares. Bittern never converts between currencies, so holdings in more than one currency are all still shown, each in its own currency, but have no total.
_Avoid_: Base currency, reporting currency, converted value

**Complete Snapshot**:
A portfolio snapshot in which every holding has a current price. Only a Complete Snapshot records when its prices were known and is kept for the next launch, overwriting the one before; one with missing prices is shown with those holdings and all totals as N/A. The kept snapshot never expires by age: Stale Figures say how old it is.
_Avoid_: Fresh data, successful refresh

### Freshness

**Launch**:
The time from having no portfolio in memory for the saved credentials until data or an error shows: a cold start, including after iOS ended the app in the background, or changed credentials. A Launch always shows the skeleton, unless data arrives within moments; with a kept Complete Snapshot it waits only for that snapshot's prices, then re-fetches holdings behind the data. Returning from the background is not a Launch: the data stays, and new prices replace it.
_Avoid_: Startup, reload, first load

**In-Session Holding**:
A holding whose price can move now: crypto always; anything else from the start of its exchange's pre-market to the end of its post-market, and through the overnight session that follows. A holding whose trading day isn't known yet counts as closed until a quote says more.
_Avoid_: Open market, live holding

**Live Refresh**:
New prices for every In-Session Holding, fetched on a fixed interval while the app is in the foreground with a network path, and stopped in the background. New prices replace the figures in place, without animation. Regular-Market Valuation still holds: extended-hours quotes never change totals, allocation or order.
_Avoid_: Polling, auto-refresh, streaming

**Stale Figure**:
A price-derived figure shown from the last data because current prices can't be had, or haven't arrived yet: there is no network path, the Market Data Connection is lost while prices may have moved since they were last known, or Live Refresh keeps failing. It is shown in gray, and VoiceOver adds when every price was last known. Names, logos, allocation bands and the legend aren't Stale Figures and keep their colors. A closed market's close is its current price, so it is not a Stale Figure; but prices may have moved unless every holding's market is known to have stayed closed since they were last known, which needs its next trading day to be known.
_Avoid_: Offline mode, cached value, outdated price

**Market Data Connection**:
The one WebSocket market data comes through, to TradingView or through the user's own server. It is live while the server has sent something, a heartbeat at least, within two missed heartbeats and five seconds (25 seconds with TradingView's 10-second heartbeat). A closed socket, or one silent for longer, is lost; after time in the background that is usually the case, so returning reopens it. A network path on the device doesn't make it live: only the server's heartbeat says the whole way to it works.
_Avoid_: Network, online

**Bar in Progress**:
The last point of a holding's chart range: the bar whose interval includes now (1D 5 minutes, 5D 15 minutes, 1M an hour, 3M, YTD and 1Y a day, 5Y a week, MAX a month), whose close follows the live price. A point is added only when the next interval begins. Pre- and post-market quotes move only the 1D Extended-Hours Continuation, and Overnight Quotes no chart; 5D and longer follow the regular session.
_Avoid_: Live point, tick

**Attention**:
A problem only the user can fix, such as SnapTrade refusing the credentials or a disabled brokerage connection. Over data it is a banner, kept until the problem is gone; with no data, the error page. Problems that may pass on their own are retried and never become Attention.
_Avoid_: Error banner, warning

### Contribution Planning

**Contribution Amount**:
The cash committed to a single contribution session — the ceiling on what Optimal Share Search may spend across Elected Holdings; any part it cannot place is Residual Cash.
_Avoid_: Deposit, budget, cash reserve

**Elected Holding**:
An account-level holding included in the current contribution's target set; election does not by itself imply a purchase.
_Avoid_: Selected holding, merged symbol position

**Contribution Pool**:
The sum of every Elected Holding's Regular-Market Valuation plus the Contribution Amount — the denominator of every Target Percentage.
_Avoid_: Portfolio total, net worth

**Target Percentage**:
The share of the Contribution Pool an Elected Holding should hold after buying, meaningful only when all targets sum to exactly 100%.
_Avoid_: Weight, normalized ratio

**Buy Amount**:
The non-negative cash to spend on an Elected Holding this session; an over-target holding's Buy Amount is zero.
_Avoid_: Rebalance delta, sell amount

**Gap Allocation**:
The fallback that distributes the whole Contribution Amount across under-target Elected Holdings in proportion to their positive value gaps, used when any exact target would require selling.
_Avoid_: Rebalancing, normalization

**Share Order**:
The executable purchase for a shares-denominated Elected Holding — the whole-share count Optimal Share Search settles on; token-denominated holdings instead spend their Buy Amount exactly.
_Avoid_: Fractional order, ideal buy

**Misallocation**:
The dollar distance between actual spends and Buy Amounts, summed across Elected Holdings; a shortfall dollar and an overshoot dollar cost the same, and cash the plan cannot place surfaces as shortfall.
_Avoid_: Tracking error, percentage deviation

**Optimal Share Search**:
The branch-and-bound search across whole-share combinations that, when completed, proves which Share Orders have the least Misallocation, breaking ties toward less Residual Cash; a holding with a zero Buy Amount is never bought.
_Avoid_: Greedy Top-Up, flooring pass

**Estimated Result**:
The best contribution result found when Optimal Share Search reaches its safety node limit before proving optimality, explicitly identified as Estimated in the UI.
_Avoid_: Optimal result, exact result

**Residual Cash**:
The part of the Contribution Amount that Optimal Share Search leaves unspent because every placeable share would add more Misallocation than it removes, shown as-is.
_Avoid_: Dust, rounding error

**Post-Contribution Percentage**:
An Elected Holding's share of the elected holdings' combined value after actual purchases; Residual Cash is excluded from the denominator.
_Avoid_: Achieved target, final weight

**Account Requirement**:
The cash to prepare at one provider for this session — the sum of actual purchases across its Elected Holdings; a provider with nothing to buy has no requirement.
_Avoid_: Account deposit, transfer amount

**Contribution Plan**:
The single persisted set of holding elections and Target Percentages that carries across sessions, never including the Contribution Amount.
_Avoid_: Preset, profile, saved scenario

## Relationships

- **Live Refresh** prices only **In-Session Holdings**; a failing **Live Refresh**, or a lost **Market Data Connection** while prices may have moved, turns the figures into **Stale Figures**, and the next success turns them back
- A holding's chart range follows the live price through its **Bar in Progress**
- The **Contribution Plan** elects zero or more **Elected Holdings**, each carrying exactly one **Target Percentage**
- The **Contribution Pool** is derived from every **Elected Holding**'s **Regular-Market Valuation** plus the **Contribution Amount**
- Every **Elected Holding** resolves to exactly one **Buy Amount** and one **Post-Contribution Percentage**
- **Optimal Share Search** turns every shares-denominated **Elected Holding**'s **Buy Amount** into one **Share Order**, minimizing **Misallocation** across the session when the search completes; an early node-limit exit produces an **Estimated Result** instead
- An **Elected Holding** is account-level: the same symbol held in two accounts is two independently electable holdings

## Example dialogue

> **Dev:** "If a holding's **Target Percentage** is below its current share of the **Contribution Pool**, do we show a sell amount?"
> **Domain expert:** "No — its **Buy Amount** is zero and **Gap Allocation** spreads the whole **Contribution Amount** across the under-target holdings; the row simply shows its **Post-Contribution Percentage**, with no special warning."

## Flagged ambiguities

- "定投目标" could read as symbol-level (one target per ticker) — resolved: targets are **account-level**, because the calculator's output must be executable buy amounts per account.
- "勾选" (election) was conflated with "购买" (purchase) — resolved: an **Elected Holding** may legitimately end the session with a **Buy Amount** of zero.
- Targets summing below or above 100% — resolved: no auto-normalization and no implicit cash remainder; results exist only at exactly 100%.
- Whether **Residual Cash** belongs in the **Post-Contribution Percentage** denominator — resolved: excluded, matching the app-wide holdings-only allocation semantics (the app has no cash concept).
- Whether leftover cash should be greedily re-deployed into extra whole shares — first resolved as never (mental verifiability), revised 2026-08-11 after real use left ~20% of a contribution unspent: Greedy Top-Up re-deployed it, but a zero-Buy-Amount holding is still never bought.
- How "closest to target" trades off against "least cash left over" — resolved 2026-08-11, superseding Greedy Top-Up: the user accepted trading mental verifiability for optimality and delegated the weighing; both failure modes are priced in dollars at 1:1 as **Misallocation**, which a completed **Optimal Share Search** minimizes exactly (ties break toward less Residual Cash), still never buying a zero-Buy-Amount holding. Reaching the safety node limit instead surfaces the incumbent as an **Estimated Result**.
- Holdings with no current price pass the minimum-value filter but have no Regular-Market Valuation — resolved: they are never electable; a Contribution Pool containing an unpriced holding is undefined.
- Whether Bittern should support several currencies — resolved 2026-11-06: no. The portfolio is entirely in US dollars, so conversion and per-currency subtotals would be unused machinery. What stays is a guard against ever summing unlike amounts: see docs/adr/0002-single-currency-portfolio.md.
- What a `cost_basis` of zero means — resolved: the broker doesn't know the cost, not that the position was free. It is treated as unknown.
- Whether a position's `cost_basis` is a total or a per-unit price — resolved 2026-11-06: per unit. SnapTrade documents it as the "book price or average purchase price", and real holdings show it at the scale of the share price, not of price × quantity.
- Degenerate inputs (Contribution Amount of zero, or zero Elected Holdings) — resolved: no results are shown; there is no zero-money allocation.
- How the app says data is loading, live or out of date — resolved 2026-11-08: with no status text at all, TradingView-style. The skeleton says data is on its way, figures that move say they are live, and gray says they aren't current; only Attention gets words. "Updated" is no longer shown, on screen or in the shared image.
- Whether "Today" should change when figures are Stale — resolved 2026-11-08: no. It names the return mode (the most recent session's change, paired with All time), not the calendar day, just as it shows Friday's change on a Sunday.
- Whether the kept Complete Snapshot should expire — resolved 2026-11-08: no. Old isn't wrong; gray and VoiceOver's date say how old it is. It is deleted when credentials are cleared or changed.
- When figures turn gray on returning from the background — resolved 2026-11-09: as in TradingView's app, gray at once when the **Market Data Connection** is lost and prices may have moved, and in color again with the first new prices. Until then the figures are the ones from before the background, not current ones. Failures with the connection live, such as quotes not arriving, still turn figures gray only after Live Refresh fails three times in a row.
