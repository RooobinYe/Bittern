#!/usr/bin/env python3
"""Regenerates the Yahoo chart fixtures. Shapes match real v8 chart responses;
the sessions and prices are synthetic so each test can assert exact values.

Usage: python3 -I scripts/generate_yahoo_fixtures.py
"""
import json
import os
from datetime import datetime, timedelta, timezone

EST = timezone(timedelta(hours=-5))
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "BitternTests", "Fixtures")


def ts(day, hour, minute=0):
    return int(datetime(2026, 11, day, hour, minute, tzinfo=EST).timestamp())


def period(start, end):
    return {"timezone": "EST", "start": start, "end": end, "gmtoffset": -18000}


def sessions(day):
    return {
        "pre": period(ts(day, 4), ts(day, 9, 30)),
        "regular": period(ts(day, 9, 30), ts(day, 16)),
        "post": period(ts(day, 16), ts(day, 20)),
    }


# Thursday 5 Nov and Friday 6 Nov 2026. The bar stamped 16:00 holds post-market
# trades (an earnings gap), exactly the case that once replaced the real close.
BARS = [
    (ts(5, 9, 30), 100.0), (ts(5, 12), 101.0), (ts(5, 15, 55), 102.0),
    (ts(5, 16), 150.0), (ts(5, 17), 103.0),
    (ts(6, 7), 104.0), (ts(6, 9), None), (ts(6, 9, 25), 105.0),
    (ts(6, 9, 30), 106.0), (ts(6, 10, 30), 107.0), (ts(6, 15, 55), 108.0),
    (ts(6, 16), 160.0), (ts(6, 17), 109.0),
]
THU_CLOSE = 102.5
FRI_CLOSE = 108.5
PREVIOUS_CLOSE = 99.0


def chart(meta, timestamps=None, closes=None):
    result = {"meta": meta}
    if timestamps is not None:
        result["timestamp"] = timestamps
        quote = {"close": closes, "open": closes, "high": closes, "low": closes, "volume": [0] * len(closes)}
        result["indicators"] = {"quote": [quote]}
    return {"chart": {"result": [result], "error": None}}


def base_meta(price, previous_close, current_day):
    return {
        "currency": "USD",
        "symbol": "TEST",
        "exchangeTimezoneName": "America/New_York",
        "regularMarketPrice": price,
        "chartPreviousClose": previous_close,
        "previousClose": previous_close,
        "longName": "Test Inc.",
        "shortName": "Test Inc.",
        "hasPrePostMarketData": True,
        "currentTradingPeriod": sessions(current_day),
    }


def history(now, price, previous_close, current_day):
    bars = [bar for bar in BARS if bar[0] <= now]
    meta = base_meta(price, previous_close, current_day)
    meta.update({
        "dataGranularity": "5m",
        "range": "5d",
        "tradingPeriods": {
            "pre": [[{"start": ts(d, 4), "end": ts(d, 9, 30)}] for d in (5, 6)],
            "regular": [[{"start": ts(d, 9, 30), "end": ts(d, 16)}] for d in (5, 6)],
            "post": [[{"start": ts(d, 16), "end": ts(d, 20)}] for d in (5, 6)],
        },
    })
    return chart(meta, [b[0] for b in bars], [b[1] for b in bars])


def quote(price, previous_close, current_day):
    meta = base_meta(price, previous_close, current_day)
    meta.update({"dataGranularity": "1d", "range": "1d"})
    return chart(meta)


def intraday(price, previous_close, current_day, points):
    meta = base_meta(price, previous_close, current_day)
    meta.update({"dataGranularity": "1m", "range": "1d"})
    return chart(meta, [p[0] for p in points], [p[1] for p in points])


def crypto():
    day_start = int(datetime(2026, 11, 6, tzinfo=timezone.utc).timestamp())
    previous_day = day_start - 86_400
    timestamps = [previous_day + 3_600, day_start, day_start + 3_600, day_start + 7_200]
    meta = {
        "currency": "USD",
        "symbol": "BTC-USD",
        "exchangeTimezoneName": "UTC",
        "regularMarketPrice": 70_300.0,
        "chartPreviousClose": 69_000.0,
        "previousClose": 69_000.0,
        "hasPrePostMarketData": False,
        "dataGranularity": "5m",
        "range": "5d",
        "currentTradingPeriod": {
            "pre": period(day_start, day_start),
            "regular": period(day_start, day_start + 86_400),
            "post": period(day_start + 86_400, day_start + 86_400),
        },
        "tradingPeriods": [[{"start": previous_day, "end": day_start}], [{"start": day_start, "end": day_start + 86_400}]],
    }
    return chart(meta, timestamps, [68_000.0, 70_000.0, 70_100.0, 70_300.0])


def year_to_date(previous_close):
    """Daily closes since the year began. chartPreviousClose is the last
    close of 2025, which the first bar (2 January) doesn't show."""
    closes = [
        (datetime(2026, 1, 2, 16, tzinfo=EST), 82.0),
        (datetime(2026, 1, 5, 16, tzinfo=EST), 84.0),
        (datetime(2026, 11, 6, 16, tzinfo=EST), FRI_CLOSE),
    ]
    meta = base_meta(FRI_CLOSE, previous_close, 6)
    meta.update({"dataGranularity": "1d", "range": "ytd"})
    return chart(meta, [int(d.timestamp()) for d, _ in closes], [c for _, c in closes])


FILES = {
    "history-premarket": history(ts(6, 8), THU_CLOSE, PREVIOUS_CLOSE, 6),
    "history-regular": history(ts(6, 11), 107.0, THU_CLOSE, 6),
    "history-postmarket": history(ts(6, 17, 30), FRI_CLOSE, THU_CLOSE, 6),
    "history-closed": history(ts(6, 22), FRI_CLOSE, THU_CLOSE, 6),
    "history-crypto": crypto(),
    "history-ytd": year_to_date(80.0),
    "quote-extended-hours": quote(FRI_CLOSE, THU_CLOSE, 6),
    "intraday-postmarket-trades": intraday(FRI_CLOSE, THU_CLOSE, 6, [(ts(6, 15, 59), 108.4), (ts(6, 16, 30), None), (ts(6, 17), 109.0)]),
    "intraday-postmarket-no-trades": intraday(FRI_CLOSE, THU_CLOSE, 6, [(ts(6, 15, 59), 108.4)]),
    "intraday-premarket-trades": intraday(FRI_CLOSE, THU_CLOSE, 6, [(ts(6, 7), 104.0)]),
}

for name, payload in FILES.items():
    with open(os.path.join(OUT, f"yahoo-{name}.json"), "w") as handle:
        json.dump(payload, handle, indent=1)
        handle.write("\n")
