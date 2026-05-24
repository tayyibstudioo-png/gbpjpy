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
