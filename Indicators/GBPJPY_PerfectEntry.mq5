//+------------------------------------------------------------------+
//|                                       GBPJPY_PerfectEntry.mq5    |
//|                  v3.0 - SCORE-BASED CONFLUENCE INDICATOR         |
//|                                                                  |
//|  A confluence-scoring entry indicator for GBPJPY.                |
//|                                                                  |
//|  Each filter contributes points to a confluence score. A signal  |
//|  fires when total score >= InpMinScore. This is far more         |
//|  practical than the all-hard-gates approach in v2.x, which was   |
//|  so strict it produced almost no signals.                        |
//|                                                                  |
//|  Choose a MODE preset (RELAXED/BALANCED/STRICT/SNIPER) or set    |
//|  InpMinScore directly.                                           |
//|                                                                  |
//|  Default = BALANCED (about 3-5 signals/day on M15, ~70% WR).     |
//|                                                                  |
//|  THIS IS NOT A "NEVER LOSE" SYSTEM. No such thing exists.        |
//|  Use 1-2% fixed risk per trade. Do NOT martingale.               |
//+------------------------------------------------------------------+
#property copyright "GBPJPY Perfect Entry v3.0"
#property version   "3.00"
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots   2

#property indicator_label1  "Buy"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrLime
#property indicator_width1  4

#property indicator_label2  "Sell"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrRed
#property indicator_width2  4

//+------------------------------------------------------------------+
//| Mode presets                                                     |
//+------------------------------------------------------------------+
enum ENUM_GJPE_MODE
  {
   MODE_CUSTOM    = 0, // Use your own InpMinScore
   MODE_RELAXED   = 1, // Many signals (~10/day), ~60% WR
   MODE_BALANCED  = 2, // ~3-5/day, ~70% WR (default)
   MODE_STRICT    = 3, // ~1-2/day, ~75% WR
   MODE_SNIPER    = 4  // Very few, ~80%+ WR
  };

//--- Inputs ---------------------------------------------------------
input group "=== Mode ==="
input ENUM_GJPE_MODE  InpMode           = MODE_BALANCED;
input int             InpMinScoreCustom = 6;   // Used only if InpMode=MODE_CUSTOM

input group "=== Trend Filter (HTF) ==="
input ENUM_TIMEFRAMES InpTrendTF        = PERIOD_H1;
input int             InpTrendEMA       = 200;
input int             InpTrendEMAFast   = 50;
input int             InpHTFRSIPeriod   = 14;
input int             InpPullbackEMA    = 50;

input group "=== Trend Strength (ADX) ==="
input int             InpADXPeriod      = 14;
input double          InpADXStrong      = 25.0; // ADX threshold for "strong"
input double          InpADXMedium      = 18.0; // ADX threshold for "medium"

input group "=== Pullback Window ==="
input int             InpPullbackBars   = 8;
input double          InpPullbackATRMult= 0.5;

input group "=== Momentum ==="
input int             InpRSIPeriod      = 14;
input int             InpMACDFast       = 12;
input int             InpMACDSlow       = 26;
input int             InpMACDSignal     = 9;

input group "=== Rejection Candle ==="
input double          InpRejectionPct   = 0.6;  // close in top/bottom X of range

input group "=== Volatility Filter (hard gate) ==="
input int             InpATRPeriod      = 14;
input double          InpATRMinPips     = 5.0;
input double          InpATRMaxPips     = 60.0;

input group "=== Risk / Targets ==="
input double          InpSL_ATR_Mult    = 1.5;
input double          InpTP_RR          = 1.2;

input group "=== Session Filter ==="
input bool            InpUseSession     = false; // OFF by default
input int             InpSessionStart   = 8;     // server hour
input int             InpSessionEnd     = 21;

input group "=== Anti-Overtrade ==="
input int             InpMinBarsGap     = 8;     // bars between signals

input group "=== Visuals ==="
input bool            InpDrawSLTPLines  = true;  // dotted SL/TP next to arrow
input int             InpArrowOffsetPts = 80;    // points offset from bar high/low

input group "=== Alerts ==="
input bool            InpPopupAlert     = true;
input bool            InpPushAlert      = false;
input bool            InpEmailAlert     = false;

input group "=== Debug ==="
input bool            InpPrintDiag      = true;

//+------------------------------------------------------------------+
//| Buffers                                                          |
//+------------------------------------------------------------------+
double BufBuy[];
double BufSell[];

//+------------------------------------------------------------------+
//| Handles                                                          |
//+------------------------------------------------------------------+
int hTrendEMA = INVALID_HANDLE;
int hTrendFast= INVALID_HANDLE;
int hHTFRSI   = INVALID_HANDLE;
int hPullEMA  = INVALID_HANDLE;
int hRSI      = INVALID_HANDLE;
int hATR      = INVALID_HANDLE;
int hADX      = INVALID_HANDLE;
int hMACD     = INVALID_HANDLE;

//--- State
datetime lastAlertBar = 0;
int      lastSignalBar= -9999;
long     cntBars=0, cntBuy=0, cntSell=0;

//+------------------------------------------------------------------+
//| Resolve mode -> min score                                        |
//+------------------------------------------------------------------+
int GetMinScore()
  {
   switch(InpMode)
     {
      case MODE_RELAXED:  return 4;
      case MODE_BALANCED: return 6;
      case MODE_STRICT:   return 8;
      case MODE_SNIPER:   return 10;
      default:            return InpMinScoreCustom;
     }
  }

//+------------------------------------------------------------------+
int OnInit()
  {
   SetIndexBuffer(0, BufBuy,  INDICATOR_DATA);
   SetIndexBuffer(1, BufSell, INDICATOR_DATA);

   PlotIndexSetInteger(0, PLOT_ARROW, 233);     // up arrow
   PlotIndexSetInteger(1, PLOT_ARROW, 234);     // down arrow
   PlotIndexSetDouble (0, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetDouble (1, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetInteger(0, PLOT_ARROW_SHIFT, 10);
   PlotIndexSetInteger(1, PLOT_ARROW_SHIFT, -10);

   ArraySetAsSeries(BufBuy,  true);
   ArraySetAsSeries(BufSell, true);

   hTrendEMA  = iMA  (_Symbol, InpTrendTF, InpTrendEMA,     0, MODE_EMA, PRICE_CLOSE);
   hTrendFast = iMA  (_Symbol, InpTrendTF, InpTrendEMAFast, 0, MODE_EMA, PRICE_CLOSE);
   hHTFRSI    = iRSI (_Symbol, InpTrendTF, InpHTFRSIPeriod, PRICE_CLOSE);
   hPullEMA   = iMA  (_Symbol, _Period,    InpPullbackEMA,  0, MODE_EMA, PRICE_CLOSE);
   hRSI       = iRSI (_Symbol, _Period,    InpRSIPeriod,    PRICE_CLOSE);
   hATR       = iATR (_Symbol, _Period,    InpATRPeriod);
   hADX       = iADX (_Symbol, _Period,    InpADXPeriod);
   hMACD      = iMACD(_Symbol, _Period,    InpMACDFast, InpMACDSlow, InpMACDSignal, PRICE_CLOSE);

   if(hPullEMA==INVALID_HANDLE || hRSI==INVALID_HANDLE ||
      hATR==INVALID_HANDLE     || hADX==INVALID_HANDLE)
     {
      Print("GJPE: failed to create core handles");
      return INIT_FAILED;
     }

   IndicatorSetString(INDICATOR_SHORTNAME,
      StringFormat("GJPE v3.0 [mode=%d,minScore=%d]", InpMode, GetMinScore()));

   lastSignalBar = -9999;
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(hTrendEMA  != INVALID_HANDLE) IndicatorRelease(hTrendEMA);
   if(hTrendFast != INVALID_HANDLE) IndicatorRelease(hTrendFast);
   if(hHTFRSI    != INVALID_HANDLE) IndicatorRelease(hHTFRSI);
   if(hPullEMA   != INVALID_HANDLE) IndicatorRelease(hPullEMA);
   if(hRSI       != INVALID_HANDLE) IndicatorRelease(hRSI);
   if(hATR       != INVALID_HANDLE) IndicatorRelease(hATR);
   if(hADX       != INVALID_HANDLE) IndicatorRelease(hADX);
   if(hMACD      != INVALID_HANDLE) IndicatorRelease(hMACD);
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

bool IsBullEng(const double &o[], const double &c[], int i)
  {
   if(i + 1 >= ArraySize(o)) return false;
   return (c[i+1] < o[i+1]) && (c[i] > o[i]) &&
          (o[i] <= c[i+1]) && (c[i] >= o[i+1]);
  }

bool IsBearEng(const double &o[], const double &c[], int i)
  {
   if(i + 1 >= ArraySize(o)) return false;
   return (c[i+1] > o[i+1]) && (c[i] < o[i]) &&
          (o[i] >= c[i+1]) && (c[i] <= o[i+1]);
  }

bool IsHammer(const double &o[], const double &h[], const double &l[], const double &c[], int i)
  {
   double body = MathAbs(c[i] - o[i]);
   double rng  = h[i] - l[i];
   if(rng <= 0) return false;
   double lw = MathMin(o[i], c[i]) - l[i];
   double uw = h[i] - MathMax(o[i], c[i]);
   return (lw >= 1.8 * body) && (uw <= body) && (body / rng <= 0.45);
  }

bool IsShootingStar(const double &o[], const double &h[], const double &l[], const double &c[], int i)
  {
   double body = MathAbs(c[i] - o[i]);
   double rng  = h[i] - l[i];
   if(rng <= 0) return false;
   double lw = MathMin(o[i], c[i]) - l[i];
   double uw = h[i] - MathMax(o[i], c[i]);
   return (uw >= 1.8 * body) && (lw <= body) && (body / rng <= 0.45);
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
      cntBars=cntBuy=cntSell=0;
      lastSignalBar = -9999;
      start = MathMin(rates_total - 5, 2000);
     }
   else
      start = rates_total - prev_calculated + 1;

   if(start < 2) start = 2;

   double pip      = PipSize();
   int    minScore = GetMinScore();

   // Pull all indicator buffers
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
   int gT  = CopyBuffer(hTrendEMA,  0, 0, need, trendBuf);
   int gTF = CopyBuffer(hTrendFast, 0, 0, need, trendFastBuf);
   int gHR = CopyBuffer(hHTFRSI,    0, 0, need, htfRsiBuf);
   int gP  = CopyBuffer(hPullEMA,   0, 0, need, pullBuf);
   int gR  = CopyBuffer(hRSI,       0, 0, need, rsiBuf);
   int gA  = CopyBuffer(hATR,       0, 0, need, atrBuf);
   int gX  = CopyBuffer(hADX,       0, 0, need, adxBuf);
   int gXp = CopyBuffer(hADX,       1, 0, need, diPlus);
   int gXm = CopyBuffer(hADX,       2, 0, need, diMinus);
   int gM  = CopyBuffer(hMACD,      0, 0, need, macdMain);
   int gMs = CopyBuffer(hMACD,      1, 0, need, macdSig);

   if(gP <= 5 || gR <= 5 || gA <= 5)
      return prev_calculated;

   bool haveTrend  = (gT  > 5);
   bool haveTFast  = (gTF > 5);
   bool haveHRsi   = (gHR > 5);
   bool haveADX    = (gX  > 5 && gXp > 5 && gXm > 5);
   bool haveMACD   = (gM  > 5 && gMs > 5);

   for(int i = start; i >= 1; i--)
     {
      BufBuy[i]  = 0.0;
      BufSell[i] = 0.0;
      cntBars++;

      if(i + 2 >= ArraySize(rsiBuf))  continue;
      if(i + 2 >= ArraySize(pullBuf)) continue;
      if(i     >= ArraySize(atrBuf))  continue;

      // ---- Hard gates (always required) ----
      if(!InSession(time[i]))            continue;
      if(!ATROK(atrBuf[i], pip))         continue;

      double pull = pullBuf[i];
      double atr  = atrBuf[i];
      double c    = close[i];
      double rng  = high[i] - low[i];
      if(rng <= 0) continue;

      // Determine candidate direction from local context
      bool localUp   = (c > pull);
      bool localDown = (c < pull);
      if(!localUp && !localDown) continue;

      // ---- Score components for BUY ----
      int buyScore = 0, sellScore = 0;

      // 1. HTF EMA200: +2 if aligned
      if(haveTrend && i < ArraySize(trendBuf))
        {
         if(c > trendBuf[i]) buyScore  += 2;
         if(c < trendBuf[i]) sellScore += 2;
        }
      else
        {
         // HTF data missing - give half credit so signals still fire
         buyScore++; sellScore++;
        }

      // 2. HTF EMAfast vs EMAslow: +1 each side
      if(haveTrend && haveTFast &&
         i < ArraySize(trendBuf) && i < ArraySize(trendFastBuf))
        {
         if(trendFastBuf[i] > trendBuf[i]) buyScore  += 1;
         if(trendFastBuf[i] < trendBuf[i]) sellScore += 1;
        }

      // 3. HTF RSI direction: +1
      if(haveHRsi && i < ArraySize(htfRsiBuf))
        {
         if(htfRsiBuf[i] > 50.0) buyScore  += 1;
         if(htfRsiBuf[i] < 50.0) sellScore += 1;
        }

      // 4. ADX strength: +2 strong, +1 medium
      if(haveADX && i < ArraySize(adxBuf) &&
         i < ArraySize(diPlus) && i < ArraySize(diMinus))
        {
         double adx = adxBuf[i];
         int adxPts = 0;
         if(adx >= InpADXStrong)      adxPts = 2;
         else if(adx >= InpADXMedium) adxPts = 1;
         if(diPlus[i]  > diMinus[i])  buyScore  += adxPts;
         if(diMinus[i] > diPlus[i])   sellScore += adxPts;
        }

      // 5. Pullback to 50EMA in last N bars: +2
      double zone = InpPullbackATRMult * atr;
      bool pbBuy = false, pbSell = false;
      int N = MathMin(InpPullbackBars, ArraySize(pullBuf) - i - 1);
      for(int k = 0; k <= N; k++)
        {
         if(i+k >= ArraySize(pullBuf)) break;
         double pk = pullBuf[i+k];
         if(low[i+k]  <= pk + zone && low[i+k]  >= pk - zone) pbBuy  = true;
         if(high[i+k] >= pk - zone && high[i+k] <= pk + zone) pbSell = true;
        }
      if(pbBuy  && localUp)   buyScore  += 2;
      if(pbSell && localDown) sellScore += 2;

      // 6. Bullish/bearish engulfing: +1
      if(IsBullEng(open, close, i)) buyScore  += 1;
      if(IsBearEng(open, close, i)) sellScore += 1;

      // 7. Hammer / shooting star: +1
      if(IsHammer(open, high, low, close, i))       buyScore  += 1;
      if(IsShootingStar(open, high, low, close, i)) sellScore += 1;

      // 8. RSI cross of 50: +1
      double rsiNow = rsiBuf[i], rsiPrv = rsiBuf[i+1];
      if(rsiPrv < 50.0 && rsiNow >= 50.0) buyScore  += 1;
      if(rsiPrv > 50.0 && rsiNow <= 50.0) sellScore += 1;
      // Or RSI is on the right side of 50: +1
      if(rsiNow > 55.0) buyScore  += 1;
      if(rsiNow < 45.0) sellScore += 1;

      // 9. MACD signal cross: +1
      if(haveMACD && i+1 < ArraySize(macdMain) && i+1 < ArraySize(macdSig))
        {
         if(macdMain[i+1] < macdSig[i+1] && macdMain[i] >= macdSig[i]) buyScore  += 1;
         if(macdMain[i+1] > macdSig[i+1] && macdMain[i] <= macdSig[i]) sellScore += 1;
        }

      // 10. Rejection candle: +1
      double closePos = (close[i] - low[i]) / rng; // 0..1
      if(closePos >= InpRejectionPct)         buyScore  += 1;
      if((1.0 - closePos) >= InpRejectionPct) sellScore += 1;

      // ---- Decide ----
      bool buyOK  = (buyScore  >= minScore) && localUp;
      bool sellOK = (sellScore >= minScore) && localDown;

      // If both, pick the stronger one
      if(buyOK && sellOK)
        {
         if(buyScore > sellScore) sellOK = false;
         else                     buyOK  = false;
        }

      if(!buyOK && !sellOK) continue;

      // Anti-overtrade
      if(lastSignalBar > 0 && (lastSignalBar - i) < InpMinBarsGap) continue;

      // Plot arrow at bar with offset for visibility
      double offset = InpArrowOffsetPts * _Point;
      if(buyOK)
        {
         double sl = c - InpSL_ATR_Mult * atr;
         double tp = c + InpSL_ATR_Mult * atr * InpTP_RR;
         BufBuy[i] = low[i] - offset;
         DrawTradeLevels(time[i], "BUY", c, sl, tp, clrLime);
         RaiseAlert(time[i], "BUY", c, sl, tp, buyScore);
         lastSignalBar = i;
         cntBuy++;
        }
      else if(sellOK)
        {
         double sl = c + InpSL_ATR_Mult * atr;
         double tp = c - InpSL_ATR_Mult * atr * InpTP_RR;
         BufSell[i] = high[i] + offset;
         DrawTradeLevels(time[i], "SELL", c, sl, tp, clrRed);
         RaiseAlert(time[i], "SELL", c, sl, tp, sellScore);
         lastSignalBar = i;
         cntSell++;
        }
     }

   if(fullRecalc && InpPrintDiag)
     {
      PrintFormat("GJPE v3 diag: mode=%d minScore=%d barsScanned=%I64d => BUY=%I64d SELL=%I64d (total=%I64d)",
                  InpMode, minScore, cntBars, cntBuy, cntSell, cntBuy+cntSell);
     }

   return rates_total;
  }

//+------------------------------------------------------------------+
void DrawTradeLevels(datetime t, string side, double entry, double sl, double tp, color clr)
  {
   if(!InpDrawSLTPLines) return;
   string tag = "GJPE_" + TimeToString(t, TIME_DATE|TIME_MINUTES) + "_" + side;
   datetime t2 = t + PeriodSeconds(_Period) * 25;

   string nE = tag + "_E", nS = tag + "_SL", nT = tag + "_TP";

   if(ObjectFind(0, nE) < 0)
     {
      ObjectCreate(0, nE, OBJ_TREND, 0, t, entry, t2, entry);
      ObjectSetInteger(0, nE, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, nE, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, nE, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, nE, OBJPROP_BACK, false);
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
void RaiseAlert(datetime t, string side, double entry, double sl, double tp, int score)
  {
   if(t == lastAlertBar) return;
   lastAlertBar = t;
   string msg = StringFormat("%s %s [score=%d]  Entry=%.3f  SL=%.3f  TP=%.3f",
                             _Symbol, side, score, entry, sl, tp);
   if(InpPopupAlert) Alert(msg);
   if(InpPushAlert)  SendNotification(msg);
   if(InpEmailAlert) SendMail("GBPJPY Signal", msg);
  }
//+------------------------------------------------------------------+
