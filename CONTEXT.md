# Market Chart Context

This context defines the user-facing meaning of asset price chart ranges across assets with different trading schedules.

## Language

**Full-Day 1D Window**:
A provider-defined regular period that covers an entire day. Its observed prices occupy the full chart width rather than reserving space for the remainder of the day.
_Avoid_: Crypto session, rolling 24 hours

**Bounded 1D Session**:
A provider-defined regular period shorter than a full day, with explicit opening and closing boundaries. Price observations retain their true positions within those boundaries.
_Avoid_: Today, first-to-last-point range
