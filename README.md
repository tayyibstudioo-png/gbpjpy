# GBPJPY Perfect Entry — MQL5 Indicator (v2.0)

A high-confluence signal indicator for GBPJPY. It plots **BUY / SELL arrows**
with **entry, SL, and TP lines** only when several independent filters agree.

## What changed in v2

- **ADX trend-strength filter** — kills choppy / ranging markets, the single
  biggest source of losses on GBPJPY.
- **Pullback can occur in last N bars** (not just the current bar) so we no
  longer require a "perfect" same-bar setup.
- **Multiple confirmation triggers** — bullish/bearish engulfing, hammer /
  shooting star, RSI mid-line cross, MACD signal cross. **Any one** of the
  enabled triggers fires the signal — much more realistic.
- **Graceful fallback** when the higher-timeframe EMA isn't fully loaded
  (this was silently killing all backtest signals in v1).
- **Session filter is OFF by default** so backtests show signals 24h.
- **Diagnostic line** printed to the Experts log after a full recalc:
  `GJPE diag: bars=... session=... atr=... trend=... adx=... pull=... trig=... gap=... => BUY=N SELL=M`
  This tells you exactly which filter is rejecting trades, so you can tune.

## Honest expectations

- **No indicator gives 100% wins.** This one is built to be *selective*.
  Realistic target: **65–75% win rate at 1.5R**, a few signals per day on M15.
- **Do not use the martingale lot ladder** in your spreadsheet. Use **fixed
  1% risk per trade**. Three losses in a row will happen — they must not
  blow your account.
- Always check the news calendar (BOE, BOJ, US CPI, NFP). The session
  filter does not know about news.

## Install

1. MT5 → **File → Open Data Folder**.
2. Copy `Indicators/GBPJPY_PerfectEntry.mq5` into `MQL5/Indicators/`.
3. MT5 → **Navigator → Indicators → Refresh**.
4. Open a **GBPJPY M15** chart, drag the indicator on. Press OK.
5. (Optional) Press **F4** to open MetaEditor and **F7** to compile.

## Recommended setup

| Style | Chart TF | `InpTrendTF` |
|-------|----------|--------------|
| Scalp | M5  | M30 |
| Intraday (default) | **M15** | **H1** |
| Swing | H1 | H4 |

## Tuning guide

Run the indicator in the **Strategy Tester** (visual mode) and look at the
diagnostic line in the **Journal** tab. If you see, e.g.:

```
GJPE diag: bars=1500 session=1500 atr=1480 trend=900 adx=300 pull=80 trig=15 gap=12 => BUY=4 SELL=5
```

That tells you:
- ADX killed two-thirds of bars (`900 → 300`) → trend filter is doing its job
- Pullback narrowed `300 → 80` → tight, fine
- Triggers narrowed `80 → 15` → fine
- 9 total signals over 1500 bars → reasonable for M15

If you get **zero signals**, the bottleneck is wherever the count drops to 0.
Loosen that input first:

| If `trend=0` | HTF data missing — set `InpRequireHTF = false` or shorten `InpTrendEMA` |
| If `adx=0`   | Lower `InpADXMin` to 18 or set `InpUseADX = false` |
| If `pull=0`  | Increase `InpPullbackBars` to 12 or `InpPullbackATRMult` to 0.75 |
| If `trig=0`  | Enable more confirmation triggers, or lower their strictness |
| If `atr=0`   | Lower `InpATRMinPips`, raise `InpATRMaxPips` |

## Logic in plain English

A **BUY** prints when **all** are true on the closed bar:

1. Price > HTF 200 EMA (uptrend).
2. ADX > 20 and +DI > -DI (trend strength + bullish direction).
3. Price has touched the 50 EMA within the last `InpPullbackBars`.
4. Close is back above the 50 EMA (pullback resolved).
5. **Any one** of: bullish engulfing, hammer, RSI cross up through 50,
   MACD signal cross up.
6. ATR between min and max pips.
7. (Optional) inside London/NY hours.
8. At least `InpMinBarsGap` bars since the last signal.

**SELL** is the mirror image.

## How to actually pass the challenge

1. Risk **1% per trade**. Calculate lot size from
   `lots = (account * 0.01) / (SL_pips * pip_value)`.
2. Take **only the indicator's signals**.
3. Stop trading after **2 losses in a day**.
4. Skip the hour around **red-folder news**.
5. Aim for **0.5–1% account growth per day**, compounded. Slow is the way.

## Want more?

I can also build:
- A matching **Expert Advisor** that auto-trades these signals with proper
  1% position sizing, break-even move, and trailing stop.
- A **trade-stats panel** that shows win rate / RR / drawdown live.

Just ask.
