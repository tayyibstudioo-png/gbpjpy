//+------------------------------------------------------------------+
//|                                       GBPJPY_PerfectEntry.mq5    |
//|                  v2.0 - High-Confluence Signal Indicator         |
//|                                                                  |
//|  Designed for GBPJPY prop-firm / personal challenges.            |
//|                                                                  |
//|  v2 changes:                                                     |
//|   - ADX trend-strength filter (kills choppy-market losers)       |
//|   - Pullback can occur in last N bars (not just current bar)     |
//|   - Multiple confirmation triggers: engulfing OR hammer OR RSI   |
//|     bullish cross OR MACD bullish cross (any ONE is enough)      |
//|   - Falls back gracefully if HTF data not yet loaded             |
//|   - Session filter OFF by default for clean backtests            |
//|   - Diagnostic counters printed after full recalc                |
//|                                                                  |
//|  THIS IS NOT A "NEVER LOSE" SYSTEM. No such thing exists.        |
//|  Use 1-2% fixed risk per trade. Do NOT martingale.               |
//+------------------------------------------------------------------+
#property copyright "GBPJPY Perfect Entry v2"
#property version   "2.00"
#property indicator_chart_window
#property indicator_buffers 4
#property indicator_plots   2

#property indicator_label1  "Buy"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrLime
#property indicator_width1  3

#property indicator_label2  "Sell"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrRed
#property indicator_width2  3

//--- Inputs ---------------------------------------------------------
input group "=== Trend Filter ==="
input ENUM_TIMEFRAMES InpTrendTF        = PERIOD_H1; // Higher TF for trend
input int             InpTrendEMA       = 200;       // HTF trend EMA
input int             InpPullbackEMA    = 50;        // Pullback EMA (current TF)
input bool            InpRequireHTF     = true;      // Require HTF trend agreement

input group "=== Trend Strength (ADX) ==="
input bool            InpUseADX         = true;      // Use ADX filter
input int             InpADXPeriod      = 14;
input double          InpADXMin         = 20.0;      // Min ADX value (>20 = trending)

input group "=== Pullback Window ==="
input int             InpPullbackBars   = 8;         // Look back N bars for pullback touch
input double          InpPullbackATRMult= 0.5;       // Touch zone = ATR * this around 50EMA

input group "=== Momentum Confirmations (any ONE triggers) ==="
input bool            InpUseEngulfing   = true;      // Bullish/bearish engulfing
input bool            InpUseHammer      = true;      // Hammer / shooting star
input bool            InpUseRSICross    = true;      // RSI cross of mid-level
input bool            InpUseMACDCross   = true;      // MACD signal-line cross
input int             InpRSIPeriod      = 14;
input double          InpRSIBuyLevel    = 50.0;
input double          InpRSISellLevel   = 50.0;
input int             InpMACDFast       = 12;
input int             InpMACDSlow       = 26;
input int             InpMACDSignal     = 9;

input group "=== Volatility Filter ==="
input int             InpATRPeriod      = 14;
input double          InpATRMinPips     = 5.0;
input double          InpATRMaxPips     = 50.0;

input group "=== Risk / Targets ==="
input double          InpSL_ATR_Mult    = 1.5;
input double          InpTP_RR          = 1.5;

input group "=== Session Filter ==="
input bool            InpUseSession     = false;     // Off by default for backtest
input int             InpLondonOpen     = 8;
input int             InpNYClose        = 21;

input group "=== Anti-Overtrade ==="
input int             InpMinBarsGap     = 6;         // Min bars between signals

input group "=== Alerts ==="
input bool            InpPopupAlert     = true;
input bool            InpPushAlert      = false;
input bool            InpEmailAlert     = false;

input group "=== Debug ==="
input bool            InpPrintDiag      = true;      // Print signal/filter stats

//--- Buffers
double BufBuy[];
double BufSell[];
double BufSL[];
double BufTP[];

//--- Handles
int hTrendEMA = INVALID_HANDLE;
int hPullEMA  = INVALID_HANDLE;
int hRSI      = INVALID_HANDLE;
int hATR      = INVALID_HANDLE;
int hADX      = INVALID_HANDLE;
int hMACD     = INVALID_HANDLE;

//--- State
datetime lastAlertBar  = 0;
int      lastSignalBar = -9999; // bar index (series, decreasing)

// Diagnostic counters (reset on full recalc)
long cntBars=0, cntAfterSession=0, cntAfterATR=0, cntAfterTrend=0,
     cntAfterADX=0, cntAfterPullback=0, cntAfterTrigger=0,
     cntAfterGap=0, cntBuy=0, cntSell=0;

//+------------------------------------------------------------------+
int OnInit()
  {
   SetIndexBuffer(0, BufBuy,  INDICATOR_DATA);
   SetIndexBuffer(1, BufSell, INDICATOR_DATA);
   SetIndexBuffer(2, BufSL,   INDICATOR_CALCULATIONS);
   SetIndexBuffer(3, BufTP,   INDICATOR_CALCULATIONS);

   PlotIndexSetInteger(0, PLOT_ARROW, 233);
   PlotIndexSetInteger(1, PLOT_ARROW, 234);
   PlotIndexSetDouble (0, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetDouble (1, PLOT_EMPTY_VALUE, 0.0);

   ArraySetAsSeries(BufBuy,  true);
   ArraySetAsSeries(BufSell, true);
   ArraySetAsSeries(BufSL,   true);
   ArraySetAsSeries(BufTP,   true);

   hTrendEMA = iMA  (_Symbol, InpTrendTF, InpTrendEMA,    0, MODE_EMA, PRICE_CLOSE);
   hPullEMA  = iMA  (_Symbol, _Period,    InpPullbackEMA, 0, MODE_EMA, PRICE_CLOSE);
   hRSI      = iRSI (_Symbol, _Period,    InpRSIPeriod, PRICE_CLOSE);
   hATR      = iATR (_Symbol, _Period,    InpATRPeriod);
   hADX      = iADX (_Symbol, _Period,    InpADXPeriod);
   hMACD     = iMACD(_Symbol, _Period,    InpMACDFast, InpMACDSlow, InpMACDSignal, PRICE_CLOSE);

   if(hTrendEMA==INVALID_HANDLE || hPullEMA==INVALID_HANDLE ||
      hRSI==INVALID_HANDLE || hATR==INVALID_HANDLE ||
      hADX==INVALID_HANDLE || hMACD==INVALID_HANDLE)
     {
      Print("GJPE: failed to create indicator handles");
      return INIT_FAILED;
     }

   IndicatorSetString(INDICATOR_SHORTNAME, "GBPJPY Perfect Entry v2");
   lastSignalBar = -9999;
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(hTrendEMA != INVALID_HANDLE) IndicatorRelease(hTrendEMA);
   if(hPullEMA  != INVALID_HANDLE) IndicatorRelease(hPullEMA);
   if(hRSI      != INVALID_HANDLE) IndicatorRelease(hRSI);
   if(hATR      != INVALID_HANDLE) IndicatorRelease(hATR);
   if(hADX      != INVALID_HANDLE) IndicatorRelease(hADX);
   if(hMACD     != INVALID_HANDLE) IndicatorRelease(hMACD);
   ObjectsDeleteAll(0, "GJPE_");
  }

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
double PipSize()
  {
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   if(digits == 3 || digits == 5) return _Point * 10.0;
   return _Point;
  }

bool InSession(datetime t)
  {
   if(!InpUseSession) return true;
   MqlDateTime dt; TimeToStruct(t, dt);
   return (dt.hour >= InpLondonOpen && dt.hour < InpNYClose);
  }

bool ATROK(double atr_value, double pip)
  {
   double atr_pips = atr_value / pip;
   return (atr_pips >= InpATRMinPips && atr_pips <= InpATRMaxPips);
  }

// Bullish engulfing: prev red, current green, current body engulfs prev body
bool IsBullishEngulfing(const double &o[], const double &c[], int i)
  {
   if(i + 1 >= ArraySize(o)) return false;
   double po = o[i+1], pc = c[i+1];
   double co = o[i],   cc = c[i];
   bool prevRed   = pc < po;
   bool currGreen = cc > co;
   return prevRed && currGreen && (co <= pc) && (cc >= po);
  }

bool IsBearishEngulfing(const double &o[], const double &c[], int i)
  {
   if(i + 1 >= ArraySize(o)) return false;
   double po = o[i+1], pc = c[i+1];
   double co = o[i],   cc = c[i];
   bool prevGreen = pc > po;
   bool currRed   = cc < co;
   return prevGreen && currRed && (co >= pc) && (cc <= po);
  }

// Hammer: small body in upper half, long lower wick (>= 2x body)
bool IsHammer(const double &o[], const double &h[], const double &l[], const double &c[], int i)
  {
   double body = MathAbs(c[i] - o[i]);
   double range= h[i] - l[i];
   if(range <= 0) return false;
   double lowerWick = MathMin(o[i], c[i]) - l[i];
   double upperWick = h[i] - MathMax(o[i], c[i]);
   return (lowerWick >= 2.0 * body) && (upperWick <= body) && (body / range <= 0.4);
  }

// Shooting star: small body in lower half, long upper wick
bool IsShootingStar(const double &o[], const double &h[], const double &l[], const double &c[], int i)
  {
   double body = MathAbs(c[i] - o[i]);
   double range= h[i] - l[i];
   if(range <= 0) return false;
   double lowerWick = MathMin(o[i], c[i]) - l[i];
   double upperWick = h[i] - MathMax(o[i], c[i]);
   return (upperWick >= 2.0 * body) && (lowerWick <= body) && (body / range <= 0.4);
  }

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {
   if(rates_total < 60) return 0;

   ArraySetAsSeries(time,  true);
   ArraySetAsSeries(open,  true);
   ArraySetAsSeries(high,  true);
   ArraySetAsSeries(low,   true);
   ArraySetAsSeries(close, true);

   bool fullRecalc = (prev_calculated == 0);
   int  start;
   if(fullRecalc)
     {
      ArrayInitialize(BufBuy,  0.0);
      ArrayInitialize(BufSell, 0.0);
      ArrayInitialize(BufSL,   0.0);
      ArrayInitialize(BufTP,   0.0);
      cntBars=cntAfterSession=cntAfterATR=cntAfterTrend=cntAfterADX=
      cntAfterPullback=cntAfterTrigger=cntAfterGap=cntBuy=cntSell=0;
      lastSignalBar = -9999;
      start = MathMin(rates_total - 5, 1500); // limit history scan
     }
   else
      start = rates_total - prev_calculated + 1;

   if(start < 2) start = 2;

   double pip = PipSize();

   // Buffers
   double trendBuf[]; ArraySetAsSeries(trendBuf, true);
   double pullBuf[];  ArraySetAsSeries(pullBuf,  true);
   double rsiBuf[];   ArraySetAsSeries(rsiBuf,   true);
   double atrBuf[];   ArraySetAsSeries(atrBuf,   true);
   double adxBuf[];   ArraySetAsSeries(adxBuf,   true);
   double diPlus[];   ArraySetAsSeries(diPlus,   true);
   double diMinus[];  ArraySetAsSeries(diMinus,  true);
   double macdMain[]; ArraySetAsSeries(macdMain, true);
   double macdSig[];  ArraySetAsSeries(macdSig,  true);

   int need = start + 5;
   int gotTrend = CopyBuffer(hTrendEMA, 0, 0, need, trendBuf);
   int gotPull  = CopyBuffer(hPullEMA,  0, 0, need, pullBuf);
   int gotRsi   = CopyBuffer(hRSI,      0, 0, need, rsiBuf);
   int gotAtr   = CopyBuffer(hATR,      0, 0, need, atrBuf);
   int gotAdx   = CopyBuffer(hADX,      0, 0, need, adxBuf);
   int gotDiP   = CopyBuffer(hADX,      1, 0, need, diPlus);
   int gotDiM   = CopyBuffer(hADX,      2, 0, need, diMinus);
   int gotMacdM = CopyBuffer(hMACD,     0, 0, need, macdMain);
   int gotMacdS = CopyBuffer(hMACD,     1, 0, need, macdSig);

   // Required: pull EMA, RSI, ATR. Others are optional/graceful.
   if(gotPull <= 5 || gotRsi <= 5 || gotAtr <= 5)
      return prev_calculated;

   bool haveTrend = (gotTrend > 5);
   bool haveADX   = (gotAdx > 5 && gotDiP > 5 && gotDiM > 5);
   bool haveMACD  = (gotMacdM > 5 && gotMacdS > 5);

   for(int i = start; i >= 1; i--)
     {
      BufBuy[i]  = 0.0;
      BufSell[i] = 0.0;
      cntBars++;

      // Bounds checks
      if(i + 2 >= ArraySize(rsiBuf))  continue;
      if(i + 2 >= ArraySize(pullBuf)) continue;
      if(i     >= ArraySize(atrBuf))  continue;

      // Session
      if(!InSession(time[i])) continue;
      cntAfterSession++;

      // ATR
      if(!ATROK(atrBuf[i], pip)) continue;
      cntAfterATR++;

      double pull   = pullBuf[i];
      double rsiNow = rsiBuf[i];
      double rsiPrv = rsiBuf[i+1];
      double c      = close[i];
      double atr    = atrBuf[i];

      // Trend (HTF EMA200) - if data missing and InpRequireHTF, skip
      bool uptrend = true, downtrend = true;
      if(haveTrend && i < ArraySize(trendBuf))
        {
         double trend = trendBuf[i];
         uptrend   = (c > trend);
         downtrend = (c < trend);
        }
      else if(InpRequireHTF)
        {
         continue; // HTF not loaded yet, be conservative
        }
      if(!uptrend && !downtrend) continue;
      cntAfterTrend++;

      // ADX trend-strength + direction
      bool adxBullOK = true, adxBearOK = true;
      if(InpUseADX)
        {
         if(!haveADX) continue;
         if(i >= ArraySize(adxBuf) || i >= ArraySize(diPlus) || i >= ArraySize(diMinus))
            continue;
         double adx = adxBuf[i];
         if(adx < InpADXMin) continue;
         adxBullOK = diPlus[i]  > diMinus[i];
         adxBearOK = diMinus[i] > diPlus[i];
        }
      cntAfterADX++;

      // Pullback to 50 EMA in last N bars
      bool pullbackBuy = false, pullbackSell = false;
      double zone = InpPullbackATRMult * atr;
      int N = MathMin(InpPullbackBars, ArraySize(pullBuf) - i - 1);
      for(int k = 0; k <= N; k++)
        {
         if(i+k >= ArraySize(pullBuf)) break;
         double pk = pullBuf[i+k];
         if(low[i+k]  <= pk + zone && low[i+k]  >= pk - zone) pullbackBuy  = true;
         if(high[i+k] >= pk - zone && high[i+k] <= pk + zone) pullbackSell = true;
        }
      // For a buy we also want price now back ABOVE the 50EMA; mirror for sell
      bool buyStructOK  = pullbackBuy  && (c > pull);
      bool sellStructOK = pullbackSell && (c < pull);
      if(!buyStructOK && !sellStructOK) continue;
      cntAfterPullback++;

      // Confirmation triggers (any ONE is enough)
      bool buyTrig  = false;
      bool sellTrig = false;

      if(InpUseEngulfing)
        {
         if(IsBullishEngulfing(open, close, i)) buyTrig  = true;
         if(IsBearishEngulfing(open, close, i)) sellTrig = true;
        }
      if(InpUseHammer)
        {
         if(IsHammer(open, high, low, close, i))      buyTrig  = true;
         if(IsShootingStar(open, high, low, close, i)) sellTrig = true;
        }
      if(InpUseRSICross)
        {
         if(rsiPrv < InpRSIBuyLevel  && rsiNow >= InpRSIBuyLevel)  buyTrig  = true;
         if(rsiPrv > InpRSISellLevel && rsiNow <= InpRSISellLevel) sellTrig = true;
        }
      if(InpUseMACDCross && haveMACD &&
         i+1 < ArraySize(macdMain) && i+1 < ArraySize(macdSig))
        {
         double mNow = macdMain[i],   sNow = macdSig[i];
         double mPrv = macdMain[i+1], sPrv = macdSig[i+1];
         if(mPrv < sPrv && mNow >= sNow) buyTrig  = true;
         if(mPrv > sPrv && mNow <= sNow) sellTrig = true;
        }

      if(!buyTrig && !sellTrig) continue;
      cntAfterTrigger++;

      // Anti-overtrade: bars are series-indexed (smaller i = later bar).
      // lastSignalBar holds the i of the previous signal (larger value).
      // Distance in bars between two signals = lastSignalBar - i (positive).
      if(lastSignalBar > 0)
        {
         int gap = lastSignalBar - i;
         if(gap < InpMinBarsGap) continue;
        }
      cntAfterGap++;

      // Final direction decision
      if(uptrend && adxBullOK && buyStructOK && buyTrig)
        {
         double sl = c - InpSL_ATR_Mult * atr;
         double tp = c + InpSL_ATR_Mult * atr * InpTP_RR;
         BufBuy[i] = low[i] - 0.5 * atr;
         BufSL[i]  = sl;
         BufTP[i]  = tp;
         DrawTradeLevels(time[i], "BUY", c, sl, tp, clrLime);
         RaiseAlert(time[i], "BUY", c, sl, tp);
         lastSignalBar = i;
         cntBuy++;
        }
      else if(downtrend && adxBearOK && sellStructOK && sellTrig)
        {
         double sl = c + InpSL_ATR_Mult * atr;
         double tp = c - InpSL_ATR_Mult * atr * InpTP_RR;
         BufSell[i] = high[i] + 0.5 * atr;
         BufSL[i]   = sl;
         BufTP[i]   = tp;
         DrawTradeLevels(time[i], "SELL", c, sl, tp, clrRed);
         RaiseAlert(time[i], "SELL", c, sl, tp);
         lastSignalBar = i;
         cntSell++;
        }
     }

   if(fullRecalc && InpPrintDiag)
     {
      PrintFormat("GJPE diag: bars=%I64d session=%I64d atr=%I64d trend=%I64d adx=%I64d pull=%I64d trig=%I64d gap=%I64d  =>  BUY=%I64d SELL=%I64d",
                  cntBars, cntAfterSession, cntAfterATR, cntAfterTrend,
                  cntAfterADX, cntAfterPullback, cntAfterTrigger, cntAfterGap,
                  cntBuy, cntSell);
     }

   return rates_total;
  }

//+------------------------------------------------------------------+
void DrawTradeLevels(datetime t, string side, double entry, double sl, double tp, color clr)
  {
   string tag = "GJPE_" + TimeToString(t, TIME_DATE|TIME_MINUTES) + "_" + side;
   datetime t2 = t + PeriodSeconds(_Period) * 30;

   string nE = tag + "_E", nS = tag + "_SL", nT = tag + "_TP";

   if(ObjectFind(0, nE) < 0)
     {
      ObjectCreate(0, nE, OBJ_TREND, 0, t, entry, t2, entry);
      ObjectSetInteger(0, nE, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, nE, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, nE, OBJPROP_RAY_RIGHT, false);
     }
   if(ObjectFind(0, nS) < 0)
     {
      ObjectCreate(0, nS, OBJ_TREND, 0, t, sl, t2, sl);
      ObjectSetInteger(0, nS, OBJPROP_COLOR, clrTomato);
      ObjectSetInteger(0, nS, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, nS, OBJPROP_RAY_RIGHT, false);
     }
   if(ObjectFind(0, nT) < 0)
     {
      ObjectCreate(0, nT, OBJ_TREND, 0, t, tp, t2, tp);
      ObjectSetInteger(0, nT, OBJPROP_COLOR, clrAqua);
      ObjectSetInteger(0, nT, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, nT, OBJPROP_RAY_RIGHT, false);
     }
  }

//+------------------------------------------------------------------+
void RaiseAlert(datetime t, string side, double entry, double sl, double tp)
  {
   if(t == lastAlertBar) return;
   lastAlertBar = t;
   string msg = StringFormat("%s %s  Entry=%.3f  SL=%.3f  TP=%.3f",
                             _Symbol, side, entry, sl, tp);
   if(InpPopupAlert) Alert(msg);
   if(InpPushAlert)  SendNotification(msg);
   if(InpEmailAlert) SendMail("GBPJPY Signal", msg);
  }
//+------------------------------------------------------------------+
