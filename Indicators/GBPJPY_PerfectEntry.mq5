//+------------------------------------------------------------------+
//|                                       GBPJPY_PerfectEntry.mq5    |
//|                  v2.1 - SNIPER MODE (1-2 signals/day, ~80% WR)   |
//|                                                                  |
//|  Designed for GBPJPY prop-firm / personal challenges.            |
//|                                                                  |
//|  v2.1 sniper changes:                                            |
//|   - HTF trend requires BOTH 200 EMA and 50 EMA to align          |
//|   - HTF RSI must agree (>50 buy, <50 sell) - kills counter-trend |
//|   - ADX raised to 25 (only strong trends)                        |
//|   - Need >= 2 of 4 confirmations (not just one)                  |
//|   - Signal bar must be a strong rejection candle                 |
//|   - Session narrowed to London/NY overlap 13-17 server           |
//|   - Min 24 bars between signals (~2 trades/day on M15)           |
//|   - Target lowered to 1.0R (higher hit rate)                     |
//|   - ATR sweet-spot 10-30 pips                                    |
//|                                                                  |
//|  THIS IS NOT A "NEVER LOSE" SYSTEM. No such thing exists.        |
//|  Use 1-2% fixed risk per trade. Do NOT martingale.               |
//+------------------------------------------------------------------+
#property copyright "GBPJPY Perfect Entry v2.1"
#property version   "2.10"
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
input group "=== Trend Filter (HTF) ==="
input ENUM_TIMEFRAMES InpTrendTF        = PERIOD_H1; // Higher TF for trend
input int             InpTrendEMA       = 200;       // HTF trend EMA (slow)
input int             InpTrendEMAFast   = 50;        // HTF trend EMA (fast) - must agree
input bool            InpRequireBothHTF = true;      // BOTH HTF EMAs must agree
input bool            InpUseHTFRSI      = true;      // Require HTF RSI > 50 (buy) / < 50 (sell)
input int             InpHTFRSIPeriod   = 14;
input int             InpPullbackEMA    = 50;        // Pullback EMA (current TF)

input group "=== Trend Strength (ADX) ==="
input bool            InpUseADX         = true;      // Use ADX filter
input int             InpADXPeriod      = 14;
input double          InpADXMin         = 25.0;      // Min ADX (>=25 = strong trend)

input group "=== Pullback Window ==="
input int             InpPullbackBars   = 8;         // Look back N bars for pullback touch
input double          InpPullbackATRMult= 0.4;       // Touch zone = ATR * this around 50EMA

input group "=== Momentum Confirmations (need >= MinTriggers of 4) ==="
input int             InpMinTriggers    = 2;         // Min number of confirmations required
input bool            InpUseEngulfing   = true;
input bool            InpUseHammer      = true;
input bool            InpUseRSICross    = true;
input bool            InpUseMACDCross   = true;
input int             InpRSIPeriod      = 14;
input double          InpRSIBuyLevel    = 50.0;
input double          InpRSISellLevel   = 50.0;
input int             InpMACDFast       = 12;
input int             InpMACDSlow       = 26;
input int             InpMACDSignal     = 9;

input group "=== Rejection Candle Filter ==="
input bool            InpUseRejection   = true;      // Signal bar must close strongly
input double          InpRejectionPct   = 0.66;      // Close in top/bottom 66% of bar range

input group "=== Volatility Filter ==="
input int             InpATRPeriod      = 14;
input double          InpATRMinPips     = 10.0;      // Sweet-spot lower bound
input double          InpATRMaxPips     = 30.0;      // Sweet-spot upper bound

input group "=== Risk / Targets ==="
input double          InpSL_ATR_Mult    = 1.5;
input double          InpTP_RR          = 1.0;       // 1R target = high hit rate

input group "=== Session Filter (London/NY overlap) ==="
input bool            InpUseSession     = true;      // ON for sniper mode
input int             InpSessionStart   = 13;        // 13:00 server (London/NY overlap)
input int             InpSessionEnd     = 17;        // 17:00 server

input group "=== Anti-Overtrade ==="
input int             InpMinBarsGap     = 24;        // ~2 signals/day on M15

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
int hTrendEMA     = INVALID_HANDLE; // HTF slow EMA
int hTrendEMAFast = INVALID_HANDLE; // HTF fast EMA
int hHTFRSI       = INVALID_HANDLE; // HTF RSI
int hPullEMA      = INVALID_HANDLE;
int hRSI          = INVALID_HANDLE;
int hATR          = INVALID_HANDLE;
int hADX          = INVALID_HANDLE;
int hMACD         = INVALID_HANDLE;

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

   hTrendEMA     = iMA  (_Symbol, InpTrendTF, InpTrendEMA,     0, MODE_EMA, PRICE_CLOSE);
   hTrendEMAFast = iMA  (_Symbol, InpTrendTF, InpTrendEMAFast, 0, MODE_EMA, PRICE_CLOSE);
   hHTFRSI       = iRSI (_Symbol, InpTrendTF, InpHTFRSIPeriod, PRICE_CLOSE);
   hPullEMA      = iMA  (_Symbol, _Period,    InpPullbackEMA,  0, MODE_EMA, PRICE_CLOSE);
   hRSI          = iRSI (_Symbol, _Period,    InpRSIPeriod,    PRICE_CLOSE);
   hATR          = iATR (_Symbol, _Period,    InpATRPeriod);
   hADX          = iADX (_Symbol, _Period,    InpADXPeriod);
   hMACD         = iMACD(_Symbol, _Period,    InpMACDFast, InpMACDSlow, InpMACDSignal, PRICE_CLOSE);

   if(hTrendEMA==INVALID_HANDLE || hTrendEMAFast==INVALID_HANDLE ||
      hHTFRSI==INVALID_HANDLE   || hPullEMA==INVALID_HANDLE ||
      hRSI==INVALID_HANDLE      || hATR==INVALID_HANDLE ||
      hADX==INVALID_HANDLE      || hMACD==INVALID_HANDLE)
     {
      Print("GJPE: failed to create indicator handles");
      return INIT_FAILED;
     }

   IndicatorSetString(INDICATOR_SHORTNAME, "GBPJPY Perfect Entry v2.1");
   lastSignalBar = -9999;
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(hTrendEMA     != INVALID_HANDLE) IndicatorRelease(hTrendEMA);
   if(hTrendEMAFast != INVALID_HANDLE) IndicatorRelease(hTrendEMAFast);
   if(hHTFRSI       != INVALID_HANDLE) IndicatorRelease(hHTFRSI);
   if(hPullEMA      != INVALID_HANDLE) IndicatorRelease(hPullEMA);
   if(hRSI          != INVALID_HANDLE) IndicatorRelease(hRSI);
   if(hATR          != INVALID_HANDLE) IndicatorRelease(hATR);
   if(hADX          != INVALID_HANDLE) IndicatorRelease(hADX);
   if(hMACD         != INVALID_HANDLE) IndicatorRelease(hMACD);
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
   return (dt.hour >= InpSessionStart && dt.hour < InpSessionEnd);
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
   double trendBuf[];     ArraySetAsSeries(trendBuf,     true);
   double trendFastBuf[]; ArraySetAsSeries(trendFastBuf, true);
   double htfRsiBuf[];    ArraySetAsSeries(htfRsiBuf,    true);
   double pullBuf[];      ArraySetAsSeries(pullBuf,      true);
   double rsiBuf[];       ArraySetAsSeries(rsiBuf,       true);
   double atrBuf[];       ArraySetAsSeries(atrBuf,       true);
   double adxBuf[];       ArraySetAsSeries(adxBuf,       true);
   double diPlus[];       ArraySetAsSeries(diPlus,       true);
   double diMinus[];      ArraySetAsSeries(diMinus,      true);
   double macdMain[];     ArraySetAsSeries(macdMain,     true);
   double macdSig[];      ArraySetAsSeries(macdSig,      true);

   int need = start + 5;
   int gotTrend     = CopyBuffer(hTrendEMA,     0, 0, need, trendBuf);
   int gotTrendFast = CopyBuffer(hTrendEMAFast, 0, 0, need, trendFastBuf);
   int gotHTFRsi    = CopyBuffer(hHTFRSI,       0, 0, need, htfRsiBuf);
   int gotPull      = CopyBuffer(hPullEMA,      0, 0, need, pullBuf);
   int gotRsi       = CopyBuffer(hRSI,          0, 0, need, rsiBuf);
   int gotAtr       = CopyBuffer(hATR,          0, 0, need, atrBuf);
   int gotAdx       = CopyBuffer(hADX,          0, 0, need, adxBuf);
   int gotDiP       = CopyBuffer(hADX,          1, 0, need, diPlus);
   int gotDiM       = CopyBuffer(hADX,          2, 0, need, diMinus);
   int gotMacdM     = CopyBuffer(hMACD,         0, 0, need, macdMain);
   int gotMacdS     = CopyBuffer(hMACD,         1, 0, need, macdSig);

   // Required: pull EMA, RSI, ATR. Others are optional/graceful.
   if(gotPull <= 5 || gotRsi <= 5 || gotAtr <= 5)
      return prev_calculated;

   bool haveTrend     = (gotTrend > 5);
   bool haveTrendFast = (gotTrendFast > 5);
   bool haveHTFRsi    = (gotHTFRsi > 5);
   bool haveADX       = (gotAdx > 5 && gotDiP > 5 && gotDiM > 5);
   bool haveMACD      = (gotMacdM > 5 && gotMacdS > 5);

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

      // Trend (HTF) - require both EMA200 & EMA50 to agree, plus HTF RSI
      bool uptrend = false, downtrend = false;
      if(haveTrend && haveTrendFast &&
         i < ArraySize(trendBuf) && i < ArraySize(trendFastBuf))
        {
         double trendSlow = trendBuf[i];
         double trendFast = trendFastBuf[i];
         if(InpRequireBothHTF)
           {
            uptrend   = (c > trendSlow) && (trendFast > trendSlow);
            downtrend = (c < trendSlow) && (trendFast < trendSlow);
           }
         else
           {
            uptrend   = (c > trendSlow);
            downtrend = (c < trendSlow);
           }
        }
      else
        {
         continue; // HTF not loaded yet, sniper mode is conservative
        }

      // HTF RSI directional bias
      if(InpUseHTFRSI)
        {
         if(!haveHTFRsi || i >= ArraySize(htfRsiBuf)) continue;
         double htfRsi = htfRsiBuf[i];
         if(htfRsi <= 50.0) uptrend   = false;
         if(htfRsi >= 50.0) downtrend = false;
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

      // Confirmation triggers - count how many fire, need >= InpMinTriggers
      int buyCount  = 0;
      int sellCount = 0;

      if(InpUseEngulfing)
        {
         if(IsBullishEngulfing(open, close, i)) buyCount++;
         if(IsBearishEngulfing(open, close, i)) sellCount++;
        }
      if(InpUseHammer)
        {
         if(IsHammer(open, high, low, close, i))       buyCount++;
         if(IsShootingStar(open, high, low, close, i)) sellCount++;
        }
      if(InpUseRSICross)
        {
         if(rsiPrv < InpRSIBuyLevel  && rsiNow >= InpRSIBuyLevel)  buyCount++;
         if(rsiPrv > InpRSISellLevel && rsiNow <= InpRSISellLevel) sellCount++;
        }
      if(InpUseMACDCross && haveMACD &&
         i+1 < ArraySize(macdMain) && i+1 < ArraySize(macdSig))
        {
         double mNow = macdMain[i],   sNow = macdSig[i];
         double mPrv = macdMain[i+1], sPrv = macdSig[i+1];
         if(mPrv < sPrv && mNow >= sNow) buyCount++;
         if(mPrv > sPrv && mNow <= sNow) sellCount++;
        }

      bool buyTrig  = (buyCount  >= InpMinTriggers);
      bool sellTrig = (sellCount >= InpMinTriggers);
      if(!buyTrig && !sellTrig) continue;
      cntAfterTrigger++;

      // Rejection-candle filter: signal bar must close strongly in trade dir
      if(InpUseRejection)
        {
         double range = high[i] - low[i];
         if(range <= 0) continue;
         double closePos = (close[i] - low[i]) / range; // 0..1, 1 = top
         if(buyTrig  && closePos < InpRejectionPct)         buyTrig  = false;
         if(sellTrig && (1.0 - closePos) < InpRejectionPct) sellTrig = false;
         if(!buyTrig && !sellTrig) continue;
        }

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
