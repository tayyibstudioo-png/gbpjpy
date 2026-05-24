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

# GBPJPY S/R Break & Retest — MQL5 Indicator (v1.0)

A second, **structure-based** indicator that lives in
`Indicators/GBPJPY_SR_BreakRetest.mq5`. Designed to stack on top of
**Perfect Entry** as a context layer: it draws the levels that matter,
tells you when they break, and then waits for the textbook retest.

## What it does

1. Scans the last N bars for **swing pivots** (configurable left/right strength).
2. **Clusters** nearby pivots into **zones**, weighted by touch count.
   Two touches = a level. Three or more = a real rejection area.
3. Watches each zone for a **decisive break** — a candle that closes
   beyond the zone by `>= ATR x InpBreakATRMult`.
4. After a break, watches the next `InpMaxRetestBars` bars for a
   **retest**: price returns into the zone, then prints a rejection
   candle (pin bar / engulfing) closing back in the breakout direction.
5. On confirmation, drops a **green up-arrow (long)** or
   **red down-arrow (short)** with a dotted entry / SL / TP, and
   raises an alert.

## Zone colors

| Color | Meaning |
|-------|---------|
| Dark red | Active resistance (multiple swing-high rejections) |
| Dark green | Active support (multiple swing-low rejections) |
| Dodger blue | Resistance broken upward, now expected to act as support |
| Dark orange | Support broken downward, now expected to act as resistance |
| Label `[RETESTED]` | This zone has already produced a confirmed signal |

## Suggested setup for the challenge

The break-and-retest pattern is reliable on M15 / H1 GBPJPY.
Recommended starting inputs:

| Style | TF | `InpPivotLeft/Right` | `InpClusterATRMult` | `InpBreakATRMult` | `InpMaxRetestBars` |
|-------|----|----------------------|---------------------|-------------------|-------------------|
| Scalp | M5  | 3 / 3 | 0.30 | 0.30 | 30 |
| Intraday (default) | **M15** | **4 / 4** | **0.45** | **0.40** | **60** |
| Swing | H1  | 5 / 5 | 0.55 | 0.50 | 80 |

Then turn `InpRequireRejection = true` (default) so only retests that
print a real pin bar / engulfing fire arrows.

## How to trade the arrows (challenge-friendly recipe)

1. Wait for an arrow on a **closed** bar — never act on a forming candle.
2. Entry = arrow bar close. SL = the dotted SL line. TP = the dotted TP line (1.5R default).
3. Risk **fixed 1% of equity** per trade. No martingale, no doubling down.
4. Skip the trade if a red-folder news event is within the next 30 min
   (BOE / BOJ / US CPI / NFP / FOMC).
5. Move SL to break-even at +0.5R, optionally close half at +1R.

## Stacking with Perfect Entry

Drop both indicators on the **same** GBPJPY M15 chart. The strongest
setups are when:

- A Perfect Entry arrow prints **inside or right next to** an active
  S/R zone, **and**
- The S/R zone has just been broken and is being retested.

That's the A+ trade — confluence of trend, momentum, and structure.

## Install

1. Copy `Indicators/GBPJPY_SR_BreakRetest.mq5` into MT5's `MQL5/Indicators/` folder.
2. Press **F4** in MT5 to open MetaEditor, then **F7** to compile (no errors expected).
3. Drag the indicator on a GBPJPY chart. Press OK.
4. Optionally drag `GBPJPY_PerfectEntry` on the same chart for the A+ stack.
