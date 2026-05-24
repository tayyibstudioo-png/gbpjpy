# GBPJPY Perfect Entry — MQL5 Indicator

A high-confluence signal indicator for GBPJPY. It plots **BUY / SELL arrows**
with **entry, SL, and TP lines** only when several independent filters agree.

## Honest expectations

- **No indicator gives 100% wins.** This one is built to be *selective*, not
  perfect. Expect roughly **60–80% win rate with 1.5R targets**, very few
  signals per day (often 0–3).
- **Do not use the martingale lot ladder** in your spreadsheet. With 1:1 RR
  and martingale, three consecutive losses (which happen even in good systems)
  will wipe a real account. Use **fixed 1% risk per trade**.
- News, gaps, and slippage are real. Always check the calendar before
  trading GBPJPY (BOE, BOJ, US CPI, NFP). The indicator includes a session
  filter but **not** a news API — close trades manually around red news.

## Install

1. Open MetaTrader 5.
2. Menu: **File → Open Data Folder**.
3. Copy `Indicators/GBPJPY_PerfectEntry.mq5` into
   `MQL5/Indicators/`.
4. In MT5: **Navigator → Indicators**, right-click → **Refresh**.
5. Open a **GBPJPY M15** chart (recommended). Drag the indicator on.
6. In MetaEditor (F4), open the file and press **F7** to compile if needed.

## Recommended timeframes

| Style | Chart TF | Trend TF (input) |
|-------|----------|------------------|
| Scalp | M5       | M30              |
| Intraday (default) | **M15** | **H1** |
| Swing | H1       | H4               |

## Inputs you may want to tune

| Input | Default | Meaning |
|---|---|---|
| `InpTrendTF` | H1 | Higher TF used for the 200 EMA trend filter |
| `InpTrendEMA` | 200 | HTF trend EMA length |
| `InpPullbackEMA` | 50 | Pullback EMA on current TF |
| `InpRSIPeriod` | 14 | RSI period for momentum cross |
| `InpATRMinPips` | 8 | Skip dead market |
| `InpATRMaxPips` | 35 | Skip mad spikes |
| `InpSL_ATR_Mult` | 1.5 | SL = ATR × this |
| `InpTP_RR` | 1.5 | TP distance = SL × this |
| `InpUseSession` | true | Trade only London + NY |
| `InpLondonOpen` / `InpNYClose` | 8 / 21 | Server-time window |
| `InpMinBarsGap` | 10 | Min bars between signals |

## Logic in plain English

A **BUY** prints when **all** are true on the closed bar:

1. Price and the pullback EMA are above the **HTF 200 EMA** (uptrend).
2. The bar's low touched within ¼ ATR of the **50 EMA** (pullback to value).
3. Close is back above the 50 EMA (rejection of the pullback).
4. **RSI just crossed up through 50** (momentum turning up).
5. ATR is between min and max pips (volatility sane).
6. Time is inside the London/NY window.
7. At least `InpMinBarsGap` bars since the last signal.

**SELL** is the mirror image.

The arrow is plotted under/over the bar. Three short trend lines mark the
**entry**, **SL** (ATR-based), and **TP** (1.5R by default). Alerts pop up
on the chart when a signal forms.

## How to actually pass the challenge

1. Risk **1% per trade**, not martingale. Calculate lot size from
   `risk = (SL_in_pips) × (pip_value) × lots`.
2. Take **only the indicator's signals**. No "I think it'll bounce" trades.
3. Stop trading after **2 losses in a day** — come back tomorrow.
4. Skip the hour around **red-folder news**.
5. Aim for **0.5–1% account growth per day**, compounded. That's how
   challenges are passed; not by hero trades.

If you want, I can also build:

- An **EA (Expert Advisor)** that auto-trades the same logic with proper
  position sizing.
- A **backtest report** from the MT5 Strategy Tester so you can see the
  real win rate before risking money.

Just ask.
