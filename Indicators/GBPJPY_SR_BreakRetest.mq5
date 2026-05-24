//+------------------------------------------------------------------+
//|                                    GBPJPY_SR_BreakRetest.mq5     |
//|             v1.0 - SUPPORT/RESISTANCE + BREAK & RETEST INDICATOR |
//|                                                                  |
//|  Auto-detects support / resistance zones from swing pivots,      |
//|  clusters nearby pivots into "rejection areas", then watches for |
//|  the classic break-and-retest pattern:                           |
//|                                                                  |
//|     1. Price closes decisively beyond a zone (BREAK).            |
//|     2. Price returns to the broken zone within N bars (RETEST).  |
//|     3. Retest candle prints a rejection (pin / engulf) and       |
//|        closes back in the breakout direction (CONFIRMATION).     |
//|                                                                  |
//|  On confirmation: arrow + alert + suggested SL/TP based on ATR.  |
//|                                                                  |
//|  Designed to stack on top of GBPJPY_PerfectEntry as a            |
//|  structure / context layer. Use 1% fixed risk per trade.         |
//+------------------------------------------------------------------+
#property copyright "GBPJPY S/R Break & Retest v1.0"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots   2

#property indicator_label1  "LongRetest"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrLime
#property indicator_width1  3

#property indicator_label2  "ShortRetest"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrRed
#property indicator_width2  3

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input group "=== Pivot detection ==="
input int    InpLookbackBars     = 600;   // bars of history to scan
input int    InpPivotLeft        = 4;     // bars to the left of a swing
input int    InpPivotRight       = 4;     // bars to the right of a swing
input int    InpMaxZones         = 12;    // keep top-N strongest zones (by touches)

input group "=== Zone clustering ==="
input int    InpATRPeriod        = 14;
input double InpClusterATRMult   = 0.45;  // pivots within this many ATR merge into one zone
input int    InpMinTouches       = 2;     // min touches for a zone to qualify

input group "=== Break & retest ==="
input double InpBreakATRMult     = 0.40;  // close beyond zone by >= this many ATR confirms break
input int    InpMaxRetestBars    = 60;    // zone is "live for retest" for this many bars after break
input double InpRetestATRMult    = 0.35;  // wick within this many ATR of zone counts as retest touch
input bool   InpRequireRejection = true;  // require pin bar / engulfing on the retest bar

input group "=== Risk / Targets ==="
input double InpSL_ATR_Mult      = 1.5;
input double InpTP_RR            = 1.5;

input group "=== Visuals ==="
input color  InpResColor         = clrFireBrick;     // active resistance
input color  InpSupColor         = clrForestGreen;   // active support
input color  InpBrokenUpColor    = clrDodgerBlue;    // resistance broken up -> new support
input color  InpBrokenDnColor    = clrDarkOrange;    // support broken down -> new resistance
input bool   InpFillZones        = true;
input bool   InpExtendZones      = true;
input bool   InpShowLabels       = true;
input bool   InpShowDashboard    = true;
input int    InpArrowOffsetPts   = 80;     // points offset for retest arrows

input group "=== Alerts ==="
input bool   InpPopupAlert       = true;
input bool   InpPushAlert        = false;
input bool   InpEmailAlert       = false;

input group "=== Debug ==="
input bool   InpPrintDiag        = true;

//+------------------------------------------------------------------+
//| Constants & buffers                                              |
//+------------------------------------------------------------------+
#define OBJ_PREFIX     "SRBR_"
#define DASH_PREFIX    "SRBR_DASH_"
#define MAX_ZONES_HARD 64

double BufLong[];
double BufShort[];

int    hATR = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Zone struct                                                      |
//+------------------------------------------------------------------+
struct SZone
{
   double   top;            // upper bound of the zone (price)
   double   bottom;         // lower bound of the zone
   int      touches;        // number of pivots that contributed
   bool     bornAsResistance; // true if first pivot was a swing high
   datetime firstTouchTime;
   datetime lastTouchTime;
   // Break state
   int      brokenDir;      // 0 = intact, +1 = broken UP, -1 = broken DOWN
   datetime brokenTime;
   int      brokenBar;      // series index at break (0 = current)
   // Retest state
   bool     retestFired;
   datetime retestTime;
   double   retestPrice;
};

SZone gZones[];
int   gZoneCount = 0;

datetime gLastBarSeen = 0;

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
double PipSize()
{
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   if(digits == 3 || digits == 5) return _Point * 10.0;
   return _Point;
}

bool IsBullEng(const double &o[], const double &c[], int i, int total)
{
   if(i + 1 >= total) return false;
   return (c[i+1] < o[i+1]) && (c[i] > o[i]) &&
          (o[i] <= c[i+1]) && (c[i] >= o[i+1]);
}

bool IsBearEng(const double &o[], const double &c[], int i, int total)
{
   if(i + 1 >= total) return false;
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

bool BullishRejection(const double &o[], const double &h[], const double &l[], const double &c[], int i, int total)
{
   return IsHammer(o,h,l,c,i) || IsBullEng(o,c,i,total);
}

bool BearishRejection(const double &o[], const double &h[], const double &l[], const double &c[], int i, int total)
{
   return IsShootingStar(o,h,l,c,i) || IsBearEng(o,c,i,total);
}

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, BufLong,  INDICATOR_DATA);
   SetIndexBuffer(1, BufShort, INDICATOR_DATA);

   PlotIndexSetInteger(0, PLOT_ARROW, 233); // up
   PlotIndexSetInteger(1, PLOT_ARROW, 234); // down
   PlotIndexSetDouble (0, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetDouble (1, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetInteger(0, PLOT_ARROW_SHIFT, 12);
   PlotIndexSetInteger(1, PLOT_ARROW_SHIFT, -12);

   ArraySetAsSeries(BufLong,  true);
   ArraySetAsSeries(BufShort, true);

   hATR = iATR(_Symbol, _Period, InpATRPeriod);
   if(hATR == INVALID_HANDLE)
   {
      Print("SRBR: failed to create ATR handle");
      return INIT_FAILED;
   }

   ArrayResize(gZones, MAX_ZONES_HARD);
   gZoneCount = 0;

   IndicatorSetString(INDICATOR_SHORTNAME,
      StringFormat("S/R Break&Retest [LB=%d, pivot=%d/%d]",
                   InpLookbackBars, InpPivotLeft, InpPivotRight));
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(hATR != INVALID_HANDLE) IndicatorRelease(hATR);
   ObjectsDeleteAll(0, OBJ_PREFIX);
}

//+------------------------------------------------------------------+
//| Zone management                                                  |
//+------------------------------------------------------------------+
void ResetZones()
{
   gZoneCount = 0;
   for(int i = 0; i < MAX_ZONES_HARD; i++)
   {
      gZones[i].top = 0; gZones[i].bottom = 0;
      gZones[i].touches = 0;
      gZones[i].bornAsResistance = false;
      gZones[i].firstTouchTime = 0; gZones[i].lastTouchTime = 0;
      gZones[i].brokenDir = 0; gZones[i].brokenTime = 0; gZones[i].brokenBar = -1;
      gZones[i].retestFired = false; gZones[i].retestTime = 0; gZones[i].retestPrice = 0;
   }
}

// Add a pivot (price + time + isHigh) to the zone list, clustering as needed.
void AddPivot(double price, datetime t, bool isHigh, double tol)
{
   // Try to merge with an existing zone
   for(int z = 0; z < gZoneCount; z++)
   {
      double mid = 0.5 * (gZones[z].top + gZones[z].bottom);
      if(MathAbs(price - mid) <= tol)
      {
         // Extend bounds
         if(price > gZones[z].top)    gZones[z].top    = price;
         if(price < gZones[z].bottom) gZones[z].bottom = price;
         gZones[z].touches++;
         if(t > gZones[z].lastTouchTime) gZones[z].lastTouchTime = t;
         if(gZones[z].firstTouchTime == 0 || t < gZones[z].firstTouchTime)
            gZones[z].firstTouchTime = t;
         return;
      }
   }
   // Create new zone
   if(gZoneCount >= MAX_ZONES_HARD) return;
   int idx = gZoneCount++;
   double half = tol * 0.5;
   gZones[idx].top              = price + half;
   gZones[idx].bottom           = price - half;
   gZones[idx].touches          = 1;
   gZones[idx].bornAsResistance = isHigh;
   gZones[idx].firstTouchTime   = t;
   gZones[idx].lastTouchTime    = t;
   gZones[idx].brokenDir        = 0;
   gZones[idx].brokenTime       = 0;
   gZones[idx].brokenBar        = -1;
   gZones[idx].retestFired      = false;
}

// Sort zones by touches desc, then keep top-N
void TrimToStrongest()
{
   // simple selection-style sort, n is tiny
   for(int i = 0; i < gZoneCount - 1; i++)
   {
      int best = i;
      for(int j = i+1; j < gZoneCount; j++)
         if(gZones[j].touches > gZones[best].touches) best = j;
      if(best != i)
      {
         SZone tmp = gZones[i]; gZones[i] = gZones[best]; gZones[best] = tmp;
      }
   }
   if(gZoneCount > InpMaxZones) gZoneCount = InpMaxZones;
}

// Drop zones below min-touch threshold (run AFTER all pivots added)
void DropWeakZones()
{
   int w = 0;
   for(int r = 0; r < gZoneCount; r++)
   {
      if(gZones[r].touches >= InpMinTouches)
      {
         if(w != r) gZones[w] = gZones[r];
         w++;
      }
   }
   gZoneCount = w;
}

//+------------------------------------------------------------------+
//| Build zones from pivots                                          |
//+------------------------------------------------------------------+
void BuildZones(const datetime &time[],
                const double   &high[],
                const double   &low[],
                const double   &atrBuf[],
                int rates_total)
{
   ResetZones();

   int scanFrom = MathMin(InpLookbackBars, rates_total - InpPivotLeft - InpPivotRight - 2);
   if(scanFrom < InpPivotRight + InpPivotLeft + 2) return;

   double atrAvg = 0; int atrN = 0;
   for(int k = 0; k < MathMin(50, ArraySize(atrBuf)); k++)
   {
      if(atrBuf[k] > 0) { atrAvg += atrBuf[k]; atrN++; }
   }
   if(atrN > 0) atrAvg /= atrN; else atrAvg = atrBuf[0];

   double cluster = atrAvg * InpClusterATRMult;
   if(cluster <= 0) cluster = 10 * _Point;

   // Walk from oldest to newest so first-touch times are correct
   for(int i = scanFrom; i >= InpPivotRight; i--)
   {
      // Swing high?
      bool isHigh = true;
      for(int k = 1; k <= InpPivotLeft && isHigh;  k++) if(high[i] <= high[i+k]) isHigh = false;
      for(int k = 1; k <= InpPivotRight && isHigh; k++) if(high[i] <= high[i-k]) isHigh = false;
      if(isHigh) AddPivot(high[i], time[i], true, cluster);

      // Swing low?
      bool isLow = true;
      for(int k = 1; k <= InpPivotLeft && isLow;  k++) if(low[i] >= low[i+k]) isLow = false;
      for(int k = 1; k <= InpPivotRight && isLow; k++) if(low[i] >= low[i-k]) isLow = false;
      if(isLow) AddPivot(low[i], time[i], false, cluster);
   }

   DropWeakZones();
   TrimToStrongest();
}

//+------------------------------------------------------------------+
//| Detect break + retest for each zone                              |
//+------------------------------------------------------------------+
void DetectBreaksAndRetests(const datetime &time[],
                            const double   &open[],
                            const double   &high[],
                            const double   &low[],
                            const double   &close[],
                            const double   &atrBuf[],
                            int rates_total)
{
   int scanFrom = MathMin(InpLookbackBars, rates_total - 2);
   if(scanFrom < 2) return;

   for(int z = 0; z < gZoneCount; z++)
   {
      // ----- Step 1: find the FIRST decisive break -----
      int brokenAt = -1;
      int brokenDir = 0;
      // walk oldest -> newest; at each bar, if no break yet, test for one
      for(int i = scanFrom; i >= 1; i--)
      {
         if(i >= ArraySize(atrBuf)) continue;
         double atr = atrBuf[i];
         double buf = atr * InpBreakATRMult;
         if(brokenDir == 0)
         {
            if(close[i] > gZones[z].top + buf)    { brokenDir = +1; brokenAt = i; break; }
            if(close[i] < gZones[z].bottom - buf) { brokenDir = -1; brokenAt = i; break; }
         }
      }

      if(brokenDir == 0) continue; // zone is still intact
      gZones[z].brokenDir  = brokenDir;
      gZones[z].brokenBar  = brokenAt;
      gZones[z].brokenTime = time[brokenAt];

      // ----- Step 2: walk forward from break, look for retest within window -----
      int windowEnd = MathMax(1, brokenAt - InpMaxRetestBars);
      bool touched = false;
      for(int i = brokenAt - 1; i >= windowEnd; i--)
      {
         if(i >= ArraySize(atrBuf)) continue;
         double atr = atrBuf[i];
         double tol = atr * InpRetestATRMult;

         // Has price re-entered the zone?
         if(brokenDir == +1)
         {
            // up-broken: zone now acts as support; need LOW to dip into zone
            if(low[i] <= gZones[z].top + tol && low[i] >= gZones[z].bottom - tol * 2)
               touched = true;
         }
         else
         {
            // down-broken: zone now acts as resistance; need HIGH to push into zone
            if(high[i] >= gZones[z].bottom - tol && high[i] <= gZones[z].top + tol * 2)
               touched = true;
         }

         if(!touched) continue;

         // Once we've touched, this same bar (or any subsequent bar within window)
         // can be the confirmation bar.
         bool confirm = false;
         if(brokenDir == +1)
         {
            // need close back ABOVE the zone with bullish character
            if(close[i] > gZones[z].top + 0.10 * atr && close[i] > open[i])
            {
               if(!InpRequireRejection || BullishRejection(open, high, low, close, i, rates_total))
                  confirm = true;
            }
         }
         else
         {
            // need close back BELOW the zone with bearish character
            if(close[i] < gZones[z].bottom - 0.10 * atr && close[i] < open[i])
            {
               if(!InpRequireRejection || BearishRejection(open, high, low, close, i, rates_total))
                  confirm = true;
            }
         }

         // Decisive failure? close on the wrong side of the zone -> invalidate
         if(brokenDir == +1 && close[i] < gZones[z].bottom - 0.5 * atr) break;
         if(brokenDir == -1 && close[i] > gZones[z].top    + 0.5 * atr) break;

         if(confirm)
         {
            gZones[z].retestFired = true;
            gZones[z].retestTime  = time[i];
            gZones[z].retestPrice = close[i];

            double offset = InpArrowOffsetPts * _Point;
            if(brokenDir == +1)
               BufLong[i]  = low[i]  - offset;
            else
               BufShort[i] = high[i] + offset;

            // SL/TP suggestion (drawn dotted)
            DrawTradeLevels(z, i, time[i], high, low, close, atrBuf, brokenDir);

            // Alert only for the most recent retest (bar 1 = just-closed)
            if(i == 1)
               RaiseAlert(brokenDir, time[i], close[i], gZones[z]);

            break;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Drawing                                                          |
//+------------------------------------------------------------------+
void DrawZones(const datetime &time[], int rates_total)
{
   ObjectsDeleteAll(0, OBJ_PREFIX);

   datetime tNow = time[0];
   datetime tFuture = tNow + PeriodSeconds(_Period) * 30;

   for(int z = 0; z < gZoneCount; z++)
   {
      string name = StringFormat("%sZ%d", OBJ_PREFIX, z);
      datetime t1 = gZones[z].firstTouchTime;
      datetime t2 = InpExtendZones ? tFuture : gZones[z].lastTouchTime;
      if(t1 == 0) t1 = tNow - PeriodSeconds(_Period) * 50;

      color c;
      if(gZones[z].brokenDir == +1)      c = InpBrokenUpColor;
      else if(gZones[z].brokenDir == -1) c = InpBrokenDnColor;
      else if(gZones[z].bornAsResistance) c = InpResColor;
      else                                c = InpSupColor;

      if(ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, gZones[z].top, t2, gZones[z].bottom))
      {
         ObjectSetInteger(0, name, OBJPROP_COLOR, c);
         ObjectSetInteger(0, name, OBJPROP_BACK,  InpFillZones);
         ObjectSetInteger(0, name, OBJPROP_FILL,  InpFillZones);
         ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      }

      if(InpShowLabels)
      {
         string lblName = StringFormat("%sL%d", OBJ_PREFIX, z);
         double mid = 0.5 * (gZones[z].top + gZones[z].bottom);
         string txt;
         if(gZones[z].brokenDir == +1)      txt = StringFormat("BROKEN UP x%d", gZones[z].touches);
         else if(gZones[z].brokenDir == -1) txt = StringFormat("BROKEN DN x%d", gZones[z].touches);
         else                               txt = StringFormat("%s x%d", gZones[z].bornAsResistance ? "RES" : "SUP", gZones[z].touches);
         if(gZones[z].retestFired) txt += " [RETESTED]";

         if(ObjectCreate(0, lblName, OBJ_TEXT, 0, t2, mid))
         {
            ObjectSetString (0, lblName, OBJPROP_TEXT,  txt);
            ObjectSetInteger(0, lblName, OBJPROP_COLOR, c);
            ObjectSetInteger(0, lblName, OBJPROP_FONTSIZE, 8);
            ObjectSetInteger(0, lblName, OBJPROP_ANCHOR, ANCHOR_RIGHT);
            ObjectSetInteger(0, lblName, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(0, lblName, OBJPROP_HIDDEN, true);
         }
      }
   }
}

void DrawTradeLevels(int z, int i, datetime t,
                     const double &high[],
                     const double &low[],   const double &close[],
                     const double &atrBuf[], int dir)
{
   if(i >= ArraySize(atrBuf)) return;
   double atr   = atrBuf[i];
   double entry = close[i];
   double sl, tp;
   if(dir == +1)
   {
      sl = low[i]  - 0.2 * atr;
      double risk = entry - sl;
      if(risk <= 0) risk = atr * InpSL_ATR_Mult;
      tp = entry + risk * InpTP_RR;
   }
   else
   {
      sl = high[i] + 0.2 * atr;
      double risk = sl - entry;
      if(risk <= 0) risk = atr * InpSL_ATR_Mult;
      tp = entry - risk * InpTP_RR;
   }

   string base = StringFormat("%sT_%d_%s", OBJ_PREFIX, z, TimeToString(t, TIME_DATE|TIME_MINUTES));
   datetime t2 = t + PeriodSeconds(_Period) * 25;

   string nE = base + "_E", nS = base + "_SL", nT = base + "_TP";

   if(ObjectCreate(0, nE, OBJ_TREND, 0, t, entry, t2, entry))
   {
      ObjectSetInteger(0, nE, OBJPROP_COLOR, dir == +1 ? clrLime : clrRed);
      ObjectSetInteger(0, nE, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, nE, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, nE, OBJPROP_BACK, false);
      ObjectSetInteger(0, nE, OBJPROP_HIDDEN, true);
   }
   if(ObjectCreate(0, nS, OBJ_TREND, 0, t, sl, t2, sl))
   {
      ObjectSetInteger(0, nS, OBJPROP_COLOR, clrTomato);
      ObjectSetInteger(0, nS, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, nS, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, nS, OBJPROP_HIDDEN, true);
   }
   if(ObjectCreate(0, nT, OBJ_TREND, 0, t, tp, t2, tp))
   {
      ObjectSetInteger(0, nT, OBJPROP_COLOR, clrAqua);
      ObjectSetInteger(0, nT, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, nT, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, nT, OBJPROP_HIDDEN, true);
   }
}

//+------------------------------------------------------------------+
//| Dashboard                                                        |
//+------------------------------------------------------------------+
void UpdateDashboard()
{
   int active = 0, broken = 0, retested = 0;
   for(int z = 0; z < gZoneCount; z++)
   {
      if(gZones[z].brokenDir == 0) active++;
      else                         broken++;
      if(gZones[z].retestFired)    retested++;
   }

   string lines[5];
   lines[0] = StringFormat("S/R Break & Retest  [%s %s]",
                           _Symbol, EnumToString((ENUM_TIMEFRAMES)_Period));
   lines[1] = StringFormat("Zones tracked: %d  (top %d kept)", gZoneCount, InpMaxZones);
   lines[2] = StringFormat("Intact: %d   Broken: %d   Retested: %d", active, broken, retested);
   lines[3] = StringFormat("Pivot %d/%d  Cluster %.2fxATR  Break %.2fxATR",
                           InpPivotLeft, InpPivotRight, InpClusterATRMult, InpBreakATRMult);
   lines[4] = "Wait for arrow before entering. Risk 1% fixed.";

   for(int k = 0; k < 5; k++)
   {
      string nm = StringFormat("%sLINE%d", DASH_PREFIX, k);
      if(ObjectFind(0, nm) < 0)
      {
         ObjectCreate(0, nm, OBJ_LABEL, 0, 0, 0);
         ObjectSetInteger(0, nm, OBJPROP_CORNER,    CORNER_LEFT_UPPER);
         ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, 12);
         ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, 18 + k * 16);
         ObjectSetInteger(0, nm, OBJPROP_FONTSIZE,  9);
         ObjectSetInteger(0, nm, OBJPROP_SELECTABLE,false);
         ObjectSetInteger(0, nm, OBJPROP_HIDDEN,    true);
      }
      ObjectSetString (0, nm, OBJPROP_TEXT,  lines[k]);
      ObjectSetInteger(0, nm, OBJPROP_COLOR, k == 0 ? clrGold : clrSilver);
   }
}

//+------------------------------------------------------------------+
//| Alerts                                                           |
//+------------------------------------------------------------------+
void RaiseAlert(int dir, datetime t, double price, const SZone &z)
{
   string side = (dir == +1) ? "LONG retest" : "SHORT retest";
   string msg  = StringFormat("%s %s @ %.3f  Zone[%.3f - %.3f] x%d touches",
                              _Symbol, side, price, z.bottom, z.top, z.touches);
   if(InpPopupAlert) Alert(msg);
   if(InpPushAlert)  SendNotification(msg);
   if(InpEmailAlert) SendMail("GBPJPY S/R Break & Retest", msg);
}

//+------------------------------------------------------------------+
//| OnCalculate                                                      |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double   &open[],
                const double   &high[],
                const double   &low[],
                const double   &close[],
                const long     &tick_volume[],
                const long     &volume[],
                const int      &spread[])
{
   if(rates_total < InpLookbackBars + 10) return 0;

   ArraySetAsSeries(time,  true);
   ArraySetAsSeries(open,  true);
   ArraySetAsSeries(high,  true);
   ArraySetAsSeries(low,   true);
   ArraySetAsSeries(close, true);

   // Run on new-bar only (not every tick) for performance.
   bool firstRun = (prev_calculated == 0);
   bool newBar   = (time[0] != gLastBarSeen);
   if(!firstRun && !newBar) return rates_total;
   gLastBarSeen = time[0];

   // Reset arrow buffers
   ArrayInitialize(BufLong,  0.0);
   ArrayInitialize(BufShort, 0.0);

   // ATR buffer
   double atrBuf[];
   ArraySetAsSeries(atrBuf, true);
   int copied = CopyBuffer(hATR, 0, 0, InpLookbackBars + 5, atrBuf);
   if(copied < 50) return prev_calculated;

   BuildZones(time, high, low, atrBuf, rates_total);
   DetectBreaksAndRetests(time, open, high, low, close, atrBuf, rates_total);
   DrawZones(time, rates_total);
   if(InpShowDashboard) UpdateDashboard();

   if(InpPrintDiag && firstRun)
   {
      int active = 0, broken = 0, retested = 0;
      for(int z = 0; z < gZoneCount; z++)
      {
         if(gZones[z].brokenDir == 0) active++; else broken++;
         if(gZones[z].retestFired)    retested++;
      }
      PrintFormat("SRBR v1: zones=%d (intact=%d broken=%d retested=%d) on %s %s",
                  gZoneCount, active, broken, retested,
                  _Symbol, EnumToString((ENUM_TIMEFRAMES)_Period));
   }

   ChartRedraw(0);
   return rates_total;
}
//+------------------------------------------------------------------+
