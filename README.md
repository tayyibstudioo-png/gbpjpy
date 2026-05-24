# GBPJPY Perfect Entry — MQL5 Indicator (v3.0)

**Score-based confluence indicator.** Each filter contributes points; a
signal fires when the total score reaches your chosen threshold. This is
much more practical than the v2.x all-hard-gates design, which was so
strict it produced almost no signals.

## How it works

Every closed bar gets a **buy score** and a **sell score** from these
components (max ≈ 14 points):

| Component | Points |
|---|---|
| Price above/below HTF 200 EMA | 2 |
| HTF EMA50 vs EMA200 alignment | 1 |
| HTF RSI direction | 1 |
| ADX strong (≥25) / medium (≥18) | 2 / 1 |
| Pullback to local 50 EMA in last 8 bars | 2 |
| Bullish/bearish engulfing | 1 |
| Hammer / shooting star | 1 |
| RSI cross of 50 | 1 |
| RSI on right side of 50 (>55 / <45) | 1 |
| MACD signal-line cross | 1 |
| Strong rejection-candle close | 1 |

A **BUY** prints when `buyScore >= minScore` and price is above the local
50 EMA. **SELL** is the mirror. Hard gates (always required): ATR in
range, session window if enabled, anti-overtrade gap.

## Mode presets

Pick one input — `InpMode`:

| Mode | Min Score | Signals/day on M15 | Expected WR |
|------|-----------|--------------------|-------------|
| RELAXED | 4 | ~10 | ~60% |
| **BALANCED (default)** | **6** | **~3–5** | **~70%** |
| STRICT | 8 | ~1–2 | ~75% |
| SNIPER | 10 | ~0–1 | ~80%+ |
| CUSTOM | your own value via `InpMinScoreCustom` | — | — |

Start with **BALANCED**, run a backtest, then ratchet up if you want
higher win rate (fewer trades), or down if you want more activity.

## Honest expectations

- **No indicator gives 100% wins.** This is a high-confluence tool, not magic.
- **Do not use the martingale lot ladder.** Use **fixed 1% risk per trade**.
- News (BOE, BOJ, US CPI, NFP) overrides everything. Skip the hour around
  red-folder news.

## Install

1. MT5 → **File → Open Data Folder**.
2. Copy `Indicators/GBPJPY_PerfectEntry.mq5` into `MQL5/Indicators/`.
3. MT5 → **Navigator → Indicators → Refresh**.
4. Open a **GBPJPY M15** chart, drag the indicator on. Press OK.
5. (Optional) Press **F4** for MetaEditor and **F7** to compile.

## Recommended setup

| Style | Chart TF | `InpTrendTF` | `InpMode` |
|-------|----------|--------------|-----------|
| Scalp | M5  | M30 | RELAXED |
| Intraday (default) | **M15** | **H1** | **BALANCED** |
| Sniper | M15 | H1 | STRICT or SNIPER |
| Swing | H1 | H4 | BALANCED |

## Backtest checklist

1. Strategy Tester → indicator only → GBPJPY M15 → last **3 months**
   → **Visual mode**.
2. Run it.
3. Open the **Journal** tab. You should see a line like:
   ```
   GJPE v3 diag: mode=2 minScore=6 barsScanned=8000 => BUY=120 SELL=130 (total=250)
   ```
4. ~250 signals over 3 months on M15 = roughly **3–4 per day** in BALANCED.
   That's the right zone.

## Visual settings

If arrows still look invisible, tweak:

- `InpArrowOffsetPts` — distance of the arrow from the bar high/low (default 80 = 8 pips on GBPJPY)
- `InpDrawSLTPLines` — toggle the dotted entry/SL/TP lines

## Position sizing for 1% risk

```
SL_pips ≈ 1.5 × ATR_pips
risk_$  = account_$ × 0.01
lots    = risk_$ / (SL_pips × pip_value_per_lot)
```

For a $200 account with SL = 20 pips on GBPJPY (≈ $0.65 per pip per 0.01 lot),
that's about **0.15 lots**. The lot scales with the account.

## Want more?

- Matching **Expert Advisor** that auto-trades these signals with 1% sizing,
  break-even at 0.5R, partial close at 0.7R, trailing stop.
- Live **stats panel** on the chart (today's signals, running win rate, RR).

Just ask.

---

# GBPJPY S/R Break & Retest — MQL5 Indicator (v2.0)

A second, **structure-based** indicator that lives in
`Indicators/GBPJPY_SR_BreakRetest.mq5`. Designed to draw **only the
major support / resistance zones** and target roughly **2 high-quality
break-and-retest setups per day**.

## Why v2 (and what's wrong with v1)

v1 scanned M15 swing pivots with a 2-touch minimum and a loose 0.45×ATR
cluster. On a chop day on GBPJPY that produced 12+ tiny zones that all
got broken — meaningless noise.

**v2 fixes this with four levers:**

1. Pivots are pulled from a **higher timeframe** (H1 by default), so
   only real swings count.
2. A zone needs **at least 3 separate touches** to qualify as a
   rejection area.
3. Cluster tolerance is tighter (**0.30×ATR**) so zones stay sharp.
4. Only the **closest 2 zones above and 2 zones below** the current
   price are kept — total of 4 lines on the chart.

## What it does

1. Pulls the last `InpHTFBars` H1 candles and finds swing highs / lows
   with ≥ `InpPivotStrength` bars on each side.
2. Clusters nearby pivots into zones; drops anything with fewer than
   `InpMinTouches`.
3. Filters out zones not touched recently (`InpRecencyHTFBars`) and
   zones too far from price (`InpMaxDistanceATR`).
4. Keeps only the top-N strongest above and below the current price.
5. On the **chart timeframe**, watches each zone for:
   - a decisive break (close beyond by ≥ `InpBreakATRMult × ATR`), then
   - a return into the zone within `InpRetestMaxBars`, then
   - a **strong** rejection candle (pin or engulfing, body < 35% range)
     closing back in the breakout direction.
6. On confirmation: green up-arrow (long) or red down-arrow (short),
   plus a popup alert.

## Zone colors

| Color | Meaning |
|-------|---------|
| Red rectangle (solid) | Active resistance (≥ 3 touches above price) |
| Green rectangle (solid) | Active support (≥ 3 touches below price) |
| Orange rectangle (dashed) | Recently broken, **pending retest** |
| Hidden | Broken zones whose retest window has expired |

The label on the right of each zone shows: `RES / SUP / RETEST? /
RETESTED`, the zone midpoint price, and the touch count.

## Recommended inputs by trading style

| Style | Chart TF | `InpZoneTF` | `InpPivotStrength` | `InpMinTouches` | Expected signals/day |
|-------|----------|-------------|--------------------|----|----|
| Scalp | M5  | M30 | 4 | 3 | 3–5 |
| **Intraday (default)** | **M15** | **H1** | **5** | **3** | **~2** |
| Swing | H1  | H4  | 5 | 3 | 0–1 |

## How to trade the arrows

1. Wait for an arrow on a **closed bar** — never act on a forming candle.
2. **Entry** = arrow bar close.
3. **SL** = below the swing low (long) / above the swing high (short),
   plus a 0.2 × ATR buffer.
4. **TP** = 1.5R, scaling in is optional.
5. Risk **fixed 1% of equity** per trade. No martingale.
6. Skip the trade if a red-folder news event is within the next 30 min
   (BOE / BOJ / US CPI / NFP / FOMC).
7. Move SL to break-even at +0.7R; close half at +1R if you want.

## Stacking with Perfect Entry

Drop both indicators on the same GBPJPY M15 chart. The A+ trade is when:

- A Perfect Entry arrow prints **inside or right next to** an
  S/R Break-and-Retest arrow, **and**
- That zone is one of the 4 majors drawn by v2.

When both fire on the same bar, that's structure + trend + momentum
all aligned — exactly the kind of trade you want to size up to a full
1% on.

## Install

1. Copy `Indicators/GBPJPY_SR_BreakRetest.mq5` into MT5's
   `MQL5/Indicators/` folder.
2. Press **F4** in MT5 to open MetaEditor, then **F7** to compile
   (no errors expected).
3. Drag the indicator on a GBPJPY M15 chart. Press OK.
4. Optionally drag `GBPJPY_PerfectEntry` on the same chart for the A+
   stack.

## Tuning if you see too few / too many signals

| Symptom | Adjustment |
|---|---|
| Zero arrows for a week | Lower `InpMinTouches` to 2, or `InpPivotStrength` to 4 |
| More than 3 signals per day | Raise `InpMinTouches` to 4, or `InpZoneTF` to H4 |
| Zones look too wide | Reduce `InpClusterATRMult` to 0.20 |
| Zones look too thin / miss obvious levels | Raise `InpClusterATRMult` to 0.40 |
| Chart too cluttered | Reduce `InpZonesAbovePrice` and `InpZonesBelowPrice` to 1 each |
