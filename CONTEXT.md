# Market Price Context

This context defines the user-facing meaning of asset prices, portfolio valuation, and chart ranges across assets with different trading schedules.

## Language

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

**Regular-Session Holding Change**:
The change in a holding's value across the most recently completed regular session, measured from the preceding regular close to the latest regular close. It remains distinct from any subsequent Pre-Market or Post-Market Holding Change.
_Avoid_: Current change, pre-market change, after-hours change
