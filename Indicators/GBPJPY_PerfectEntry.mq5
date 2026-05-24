//+------------------------------------------------------------------+
//|                                       GBPJPY_PerfectEntry.mq5    |
//|                            High-Confluence Signal Indicator      |
//|                                                                  |
//|  Designed for GBPJPY prop-firm / personal challenges.            |
//|  Filters out low-probability trades by requiring agreement       |
//|  between trend, momentum, volatility, and session context.      |
//|                                                                  |
//|  THIS IS NOT A "NEVER LOSE" SYSTEM. No such thing exists.        |
//|  Use 1-2% fixed risk per trade. Do NOT martingale.               |
//+------------------------------------------------------------------+
#property copyright "GBPJPY Perfect Entry"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 4
#property indicator_plots   2

//--- Buy arrow
#property indicator_label1  "Buy"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrLime
#property indicator_width1  2

//--- Sell arrow
#property indicator_label2  "Sell"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrRed
#property indicator_width2  2

//--- Inputs ---------------------------------------------------------
input group "=== Trend Filter ==="
input ENUM_TIMEFRAMES InpTrendTF      = PERIOD_H1;   // Higher TF for trend
input int             InpTrendEMA     = 200;         // HTF trend EMA
input int             InpPullbackEMA  = 50;          // Pullback EMA (current TF)

input group "=== Momentum ==="
input int             InpRSIPeriod    = 14;
input double          InpRSIBuyLevel  = 50.0;        // RSI must cross above this for buy
input double          InpRSISellLevel = 50.0;        // RSI must cross below this for sell

input group "=== Volatility ==="
input int             InpATRPeriod    = 14;
input double          InpATRMinPips   = 8.0;         // skip if ATR < this (dead market)
input double          InpATRMaxPips   = 35.0;        // skip if ATR > this (insane spike)

input group "=== Risk / Targets ==="
input double          InpSL_ATR_Mult  = 1.5;         // SL = ATR * mult
input double          InpTP_RR        = 1.5;         // TP = SL distance * RR

input group "=== Session Filter (server time, 24h) ==="
input bool            InpUseSession   = true;
input int             InpLondonOpen   = 8;           // 08:00
input int             InpNYClose      = 21;          // 21:00

input group "=== Anti-Overtrade ==="
input int             InpMinBarsGap   = 10;          // min bars between signals

input group "=== Alerts ==="
input bool            InpPopupAlert   = true;
input bool            InpPushAlert    = false;
input bool            InpEmailAlert   = false;

//--- Buffers
double BufBuy[];
double BufSell[];
double BufSL[];   // not plotted, used to keep last SL price
double BufTP[];   // not plotted, used to keep last TP price

//--- Handles
int hTrendEMA = INVALID_HANDLE;
int hPullEMA  = INVALID_HANDLE;
int hRSI      = INVALID_HANDLE;
int hATR      = INVALID_HANDLE;

//--- State
datetime lastSignalBar = 0;
int      lastSignalIdx = -9999;

//+------------------------------------------------------------------+
int OnInit()
  {
   SetIndexBuffer(0, BufBuy,  INDICATOR_DATA);
   SetIndexBuffer(1, BufSell, INDICATOR_DATA);
   SetIndexBuffer(2, BufSL,   INDICATOR_CALCULATIONS);
   SetIndexBuffer(3, BufTP,   INDICATOR_CALCULATIONS);

   PlotIndexSetInteger(0, PLOT_ARROW, 233); // up arrow
   PlotIndexSetInteger(1, PLOT_ARROW, 234); // down arrow
   PlotIndexSetDouble (0, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetDouble (1, PLOT_EMPTY_VALUE, 0.0);

   ArraySetAsSeries(BufBuy,  true);
   ArraySetAsSeries(BufSell, true);
   ArraySetAsSeries(BufSL,   true);
   ArraySetAsSeries(BufTP,   true);

   hTrendEMA = iMA(_Symbol, InpTrendTF, InpTrendEMA, 0, MODE_EMA, PRICE_CLOSE);
   hPullEMA  = iMA(_Symbol, _Period,    InpPullbackEMA, 0, MODE_EMA, PRICE_CLOSE);
   hRSI      = iRSI(_Symbol, _Period,   InpRSIPeriod, PRICE_CLOSE);
   hATR      = iATR(_Symbol, _Period,   InpATRPeriod);

   if(hTrendEMA == INVALID_HANDLE || hPullEMA == INVALID_HANDLE ||
      hRSI == INVALID_HANDLE || hATR == INVALID_HANDLE)
     {
      Print("Failed to create indicator handles");
      return INIT_FAILED;
     }

   IndicatorSetString(INDICATOR_SHORTNAME, "GBPJPY Perfect Entry");
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(hTrendEMA != INVALID_HANDLE) IndicatorRelease(hTrendEMA);
   if(hPullEMA  != INVALID_HANDLE) IndicatorRelease(hPullEMA);
   if(hRSI      != INVALID_HANDLE) IndicatorRelease(hRSI);
   if(hATR      != INVALID_HANDLE) IndicatorRelease(hATR);
   ObjectsDeleteAll(0, "GJPE_");
  }

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
double PipSize()
  {
   // GBPJPY: 3-digit broker pip = 0.01, 5-digit = 0.0001 (not for JPY)
   double point = _Point;
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   if(digits == 3 || digits == 5) return point * 10.0;
   return point;
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
   if(rates_total < InpTrendEMA + 50) return 0;

   ArraySetAsSeries(time,  true);
   ArraySetAsSeries(open,  true);
   ArraySetAsSeries(high,  true);
   ArraySetAsSeries(low,   true);
   ArraySetAsSeries(close, true);

   int start;
   if(prev_calculated == 0)
     {
      ArrayInitialize(BufBuy,  0.0);
      ArrayInitialize(BufSell, 0.0);
      ArrayInitialize(BufSL,   0.0);
      ArrayInitialize(BufTP,   0.0);
      start = rates_total - InpTrendEMA - 10;
     }
   else
      start = rates_total - prev_calculated + 1;

   if(start < 2) start = 2;

   double pip = PipSize();

   // Pull arrays (work on closed bars only -> shift = 1+)
   double trendBuf[]; ArraySetAsSeries(trendBuf, true);
   double pullBuf[];  ArraySetAsSeries(pullBuf,  true);
   double rsiBuf[];   ArraySetAsSeries(rsiBuf,   true);
   double atrBuf[];   ArraySetAsSeries(atrBuf,   true);

   int need = start + 5;
   if(CopyBuffer(hTrendEMA, 0, 0, need, trendBuf) <= 0) return prev_calculated;
   if(CopyBuffer(hPullEMA,  0, 0, need, pullBuf)  <= 0) return prev_calculated;
   if(CopyBuffer(hRSI,      0, 0, need, rsiBuf)   <= 0) return prev_calculated;
   if(CopyBuffer(hATR,      0, 0, need, atrBuf)   <= 0) return prev_calculated;

   // Iterate from oldest to newest among the unprocessed bars
   for(int i = start; i >= 1; i--)
     {
      BufBuy[i]  = 0.0;
      BufSell[i] = 0.0;

      // Skip if not enough data
      if(i + 1 >= ArraySize(rsiBuf))   continue;
      if(i + 1 >= ArraySize(pullBuf))  continue;
      if(i     >= ArraySize(trendBuf)) continue;
      if(i     >= ArraySize(atrBuf))   continue;

      // Session filter
      if(!InSession(time[i])) continue;

      // Volatility filter
      if(!ATROK(atrBuf[i], pip)) continue;

      // Anti-overtrade gap
      if(lastSignalIdx > 0 && (rates_total - i) - (rates_total - lastSignalIdx) < InpMinBarsGap)
         if(MathAbs(i - lastSignalIdx) < InpMinBarsGap) continue;

      double trend  = trendBuf[i];
      double pull   = pullBuf[i];
      double rsiNow = rsiBuf[i];
      double rsiPrv = rsiBuf[i+1];
      double c      = close[i];
      double l      = low[i];
      double h      = high[i];
      double atr    = atrBuf[i];

      bool uptrend   = (c > trend) && (pull > trend);
      bool downtrend = (c < trend) && (pull < trend);

      // BUY: in HTF uptrend, price pulled back near pullback EMA, RSI just crossed up through level
      bool pullbackToEMA_buy  = (l <= pull + 0.25 * atr) && (c > pull);
      bool rsiCrossUp         = (rsiPrv < InpRSIBuyLevel) && (rsiNow >= InpRSIBuyLevel);

      // SELL: mirror
      bool pullbackToEMA_sell = (h >= pull - 0.25 * atr) && (c < pull);
      bool rsiCrossDn         = (rsiPrv > InpRSISellLevel) && (rsiNow <= InpRSISellLevel);

      if(uptrend && pullbackToEMA_buy && rsiCrossUp)
        {
         double sl = c - InpSL_ATR_Mult * atr;
         double tp = c + InpSL_ATR_Mult * atr * InpTP_RR;
         BufBuy[i] = l - 0.5 * atr;
         BufSL[i]  = sl;
         BufTP[i]  = tp;
         DrawTradeLevels(time[i], "BUY", c, sl, tp, clrLime);
         RaiseAlert(time[i], "BUY", c, sl, tp);
         lastSignalIdx = i;
        }
      else if(downtrend && pullbackToEMA_sell && rsiCrossDn)
        {
         double sl = c + InpSL_ATR_Mult * atr;
         double tp = c - InpSL_ATR_Mult * atr * InpTP_RR;
         BufSell[i] = h + 0.5 * atr;
         BufSL[i]   = sl;
         BufTP[i]   = tp;
         DrawTradeLevels(time[i], "SELL", c, sl, tp, clrRed);
         RaiseAlert(time[i], "SELL", c, sl, tp);
         lastSignalIdx = i;
        }
     }

   return rates_total;
  }

//+------------------------------------------------------------------+
//| Draw entry / SL / TP horizontal lines for the latest signal      |
//+------------------------------------------------------------------+
void DrawTradeLevels(datetime t, string side, double entry, double sl, double tp, color clr)
  {
   string tag = "GJPE_" + TimeToString(t, TIME_DATE|TIME_MINUTES) + "_" + side;
   string nE  = tag + "_E";
   string nS  = tag + "_SL";
   string nT  = tag + "_TP";

   datetime t2 = t + PeriodSeconds(_Period) * 30;

   // Entry
   ObjectCreate(0, nE, OBJ_TREND, 0, t, entry, t2, entry);
   ObjectSetInteger(0, nE, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, nE, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, nE, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, nE, OBJPROP_RAY_RIGHT, false);

   // SL
   ObjectCreate(0, nS, OBJ_TREND, 0, t, sl, t2, sl);
   ObjectSetInteger(0, nS, OBJPROP_COLOR, clrTomato);
   ObjectSetInteger(0, nS, OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, nS, OBJPROP_RAY_RIGHT, false);

   // TP
   ObjectCreate(0, nT, OBJ_TREND, 0, t, tp, t2, tp);
   ObjectSetInteger(0, nT, OBJPROP_COLOR, clrAqua);
   ObjectSetInteger(0, nT, OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, nT, OBJPROP_RAY_RIGHT, false);
  }

//+------------------------------------------------------------------+
void RaiseAlert(datetime t, string side, double entry, double sl, double tp)
  {
   if(t == lastSignalBar) return;
   lastSignalBar = t;

   string msg = StringFormat("%s %s  Entry=%.3f  SL=%.3f  TP=%.3f",
                             _Symbol, side, entry, sl, tp);
   if(InpPopupAlert) Alert(msg);
   if(InpPushAlert)  SendNotification(msg);
   if(InpEmailAlert) SendMail("GBPJPY Signal", msg);
  }
//+------------------------------------------------------------------+
