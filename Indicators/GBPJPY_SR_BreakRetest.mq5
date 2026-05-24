//+------------------------------------------------------------------+
//|                                    GBPJPY_SR_BreakRetest.mq5     |
//|        v2.0 - MAJOR ZONES ONLY - 2 SETUPS / DAY TARGET           |
//|                                                                  |
//|  Philosophy of v2:                                               |
//|  - Pivots are detected on a HIGHER timeframe (H1 by default)     |
//|    so what shows up are MAJOR swing highs and lows, not M15      |
//|    noise.                                                        |
//|  - A zone needs at least 3 separate touches to qualify - this    |
//|    is what makes it a real "rejection area".                     |
//|  - Only the closest 2 zones above and 2 zones below current      |
//|    price are drawn. Total of 4 lines on the chart.               |
//|  - Broken zones are hidden by default once their retest window   |
//|    expires - the chart stays clean.                              |
//|  - Signals require: decisive break + return to zone + STRONG     |
//|    rejection candle. Realistically that prints ~2x per day on    |
//|    GBPJPY M15.                                                   |
//|                                                                  |
//|  Use 1% fixed risk per trade. No martingale.                     |
//+------------------------------------------------------------------+
#property copyright "GBPJPY S/R Break & Retest v2.0"
#property version   "2.00"
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots   2

#property indicator_label1  "LongRetest"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrLime
#property indicator_width1  4

#property indicator_label2  "ShortRetest"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrRed
#property indicator_width2  4

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input group "=== Major-zone source (HTF) ==="
input ENUM_TIMEFRAMES InpZoneTF      = PERIOD_H1; // pivots come from this TF
input int    InpHTFBars              = 400;       // HTF bars to scan
input int    InpPivotStrength        = 5;         // bars left+right (HIGHER = more major)
input int    InpMinTouches           = 3;         // min pivots to qualify a zone
input double InpClusterATRMult       = 0.30;      // tighter = sharper zones
input int    InpATRPeriod            = 14;

input group "=== Selection (kept only) ==="
input int    InpZonesAbovePrice      = 2;         // how many resistance levels to keep
input int    InpZonesBelowPrice      = 2;         // how many support levels to keep
input double InpMaxDistanceATR       = 4.0;       // ignore zones farther than this many ATR
input int    InpRecencyHTFBars       = 250;       // ignore zones not touched in N HTF bars

input group "=== Break & retest (chart TF) ==="
input double InpBreakATRMult         = 0.60;      // close beyond by >= this many ATR = break
input int    InpRetestMaxBars        = 30;        // chart-TF bars allowed for retest
input double InpRetestTouchATRMult   = 0.25;      // wick within this much of zone = touch
input bool   InpRequireStrongReject  = true;      // require pin/engulf with body<35% range
input bool   InpHideExpiredBroken    = true;      // hide broken zones whose window expired

input group "=== Visuals ==="
input color  InpResColor             = C'200,40,40';   // resistance
input color  InpSupColor             = C'40,160,40';   // support
input color  InpFlipColor            = C'255,140,0';   // broken, pending retest
input bool   InpFillZones            = true;
input bool   InpExtendRight          = true;
input bool   InpShowLabels           = true;
input bool   InpShowStatus           = true;           // single-line status
input int    InpArrowOffsetPts       = 80;

input group "=== Alerts ==="
input bool   InpPopupAlert           = true;
input bool   InpPushAlert            = false;
input bool   InpEmailAlert           = false;

input group "=== Debug ==="
input bool   InpPrintDiag            = true;

//+------------------------------------------------------------------+
//| Constants                                                        |
//+------------------------------------------------------------------+
#define OBJ_PREFIX     "SRBR2_"
#define STATUS_OBJ     "SRBR2_STATUS"
#define MAX_ZONES_HARD 32

double BufLong[];
double BufShort[];

int    hATR_chart = INVALID_HANDLE;
int    hATR_htf   = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Zone struct                                                      |
//+------------------------------------------------------------------+
struct SZone
{
   double   top;
   double   bottom;
   int      touches;
   bool     bornAsResistance;
   datetime firstTouchTime;
   datetime lastTouchTime;
   double   score;            // touches weighted by recency
   // break / retest state on chart TF
   int      brokenDir;        // 0 = intact, +1 up, -1 down
   datetime brokenTime;
   int      brokenChartBar;
   bool     retestFired;
   datetime retestTime;
   bool     visible;          // whether to draw it
};

SZone gZones[];
int   gZoneCount = 0;

datetime gLastBarSeen = 0;

//+------------------------------------------------------------------+
//| Candle helpers                                                   |
//+------------------------------------------------------------------+
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
   return (lw >= 2.0 * body) && (uw <= 0.7 * body) && (body / rng <= 0.35);
}

bool IsShootingStar(const double &o[], const double &h[], const double &l[], const double &c[], int i)
{
   double body = MathAbs(c[i] - o[i]);
   double rng  = h[i] - l[i];
   if(rng <= 0) return false;
   double lw = MathMin(o[i], c[i]) - l[i];
   double uw = h[i] - MathMax(o[i], c[i]);
   return (uw >= 2.0 * body) && (lw <= 0.7 * body) && (body / rng <= 0.35);
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

   PlotIndexSetInteger(0, PLOT_ARROW, 233);
   PlotIndexSetInteger(1, PLOT_ARROW, 234);
   PlotIndexSetDouble (0, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetDouble (1, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetInteger(0, PLOT_ARROW_SHIFT,  12);
   PlotIndexSetInteger(1, PLOT_ARROW_SHIFT, -12);

   ArraySetAsSeries(BufLong,  true);
   ArraySetAsSeries(BufShort, true);

   hATR_chart = iATR(_Symbol, _Period,     InpATRPeriod);
   hATR_htf   = iATR(_Symbol, InpZoneTF,   InpATRPeriod);
   if(hATR_chart == INVALID_HANDLE || hATR_htf == INVALID_HANDLE)
   {
      Print("SRBR2: failed to create ATR handles");
      return INIT_FAILED;
   }

   ArrayResize(gZones, MAX_ZONES_HARD);
   gZoneCount = 0;

   IndicatorSetString(INDICATOR_SHORTNAME,
      StringFormat("S/R v2 [%s pivots, %dx, ≥%d touches]",
                   EnumToString(InpZoneTF), InpPivotStrength, InpMinTouches));
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(hATR_chart != INVALID_HANDLE) IndicatorRelease(hATR_chart);
   if(hATR_htf   != INVALID_HANDLE) IndicatorRelease(hATR_htf);
   ObjectsDeleteAll(0, OBJ_PREFIX);
   ObjectDelete(0, STATUS_OBJ);
}

//+------------------------------------------------------------------+
//| Zone management                                                  |
//+------------------------------------------------------------------+
void ResetZones()
{
   gZoneCount = 0;
   for(int i = 0; i < MAX_ZONES_HARD; i++)
   {
      gZones[i].top = 0; gZones[i].bottom = 0; gZones[i].touches = 0;
      gZones[i].bornAsResistance = false;
      gZones[i].firstTouchTime = 0; gZones[i].lastTouchTime = 0; gZones[i].score = 0;
      gZones[i].brokenDir = 0; gZones[i].brokenTime = 0; gZones[i].brokenChartBar = -1;
      gZones[i].retestFired = false; gZones[i].retestTime = 0;
      gZones[i].visible = false;
   }
}

void AddPivot(double price, datetime t, bool isHigh, double tol)
{
   for(int z = 0; z < gZoneCount; z++)
   {
      double mid = 0.5 * (gZones[z].top + gZones[z].bottom);
      if(MathAbs(price - mid) <= tol)
      {
         if(price > gZones[z].top)    gZones[z].top    = price;
         if(price < gZones[z].bottom) gZones[z].bottom = price;
         gZones[z].touches++;
         if(t > gZones[z].lastTouchTime) gZones[z].lastTouchTime = t;
         if(gZones[z].firstTouchTime == 0 || t < gZones[z].firstTouchTime)
            gZones[z].firstTouchTime = t;
         return;
      }
   }
   if(gZoneCount >= MAX_ZONES_HARD) return;
   int idx = gZoneCount++;
   double half = tol * 0.5;
   gZones[idx].top              = price + half;
   gZones[idx].bottom           = price - half;
   gZones[idx].touches          = 1;
   gZones[idx].bornAsResistance = isHigh;
   gZones[idx].firstTouchTime   = t;
   gZones[idx].lastTouchTime    = t;
}

//+------------------------------------------------------------------+
//| Build zones from HTF pivots                                      |
//+------------------------------------------------------------------+
bool BuildZonesFromHTF(double currentPrice)
{
   ResetZones();

   int htfBars = MathMin(InpHTFBars, Bars(_Symbol, InpZoneTF));
   if(htfBars < InpPivotStrength * 4) return false;

   datetime htfTime[];
   double   htfHigh[], htfLow[];
   ArraySetAsSeries(htfTime, true);
   ArraySetAsSeries(htfHigh, true);
   ArraySetAsSeries(htfLow,  true);
   if(CopyTime(_Symbol, InpZoneTF, 0, htfBars, htfTime) <= 0) return false;
   if(CopyHigh(_Symbol, InpZoneTF, 0, htfBars, htfHigh) <= 0) return false;
   if(CopyLow (_Symbol, InpZoneTF, 0, htfBars, htfLow ) <= 0) return false;

   double htfATR[];
   ArraySetAsSeries(htfATR, true);
   if(CopyBuffer(hATR_htf, 0, 0, htfBars, htfATR) <= 0) return false;

   double atrSum = 0; int atrN = 0;
   for(int k = 0; k < MathMin(50, htfBars); k++)
      if(htfATR[k] > 0) { atrSum += htfATR[k]; atrN++; }
   double atrAvg = (atrN > 0) ? atrSum / atrN : htfATR[0];
   double cluster = atrAvg * InpClusterATRMult;
   if(cluster <= 0) cluster = 100 * _Point;

   // detect HTF swing pivots, oldest -> newest
   int strength = InpPivotStrength;
   int scanFrom = htfBars - strength - 1;
   for(int i = scanFrom; i >= strength; i--)
   {
      bool isHigh = true;
      for(int k = 1; k <= strength && isHigh; k++)
         if(htfHigh[i] <= htfHigh[i+k] || htfHigh[i] <= htfHigh[i-k]) isHigh = false;
      if(isHigh) AddPivot(htfHigh[i], htfTime[i], true, cluster);

      bool isLow = true;
      for(int k = 1; k <= strength && isLow; k++)
         if(htfLow[i]  >= htfLow[i+k]  || htfLow[i]  >= htfLow[i-k])  isLow = false;
      if(isLow)  AddPivot(htfLow[i],  htfTime[i], false, cluster);
   }

   // ----- score & filter -----
   datetime tNewest = htfTime[0];
   int htfPeriodSec = PeriodSeconds(InpZoneTF);
   double maxDist = atrAvg * InpMaxDistanceATR;

   for(int z = 0; z < gZoneCount; z++)
   {
      // touches threshold
      if(gZones[z].touches < InpMinTouches) { gZones[z].score = -1; continue; }

      // recency: how many HTF bars since last touch?
      int barsAgo = (int)((tNewest - gZones[z].lastTouchTime) / htfPeriodSec);
      if(barsAgo > InpRecencyHTFBars) { gZones[z].score = -1; continue; }

      // distance from current price (use closest edge)
      double mid = 0.5 * (gZones[z].top + gZones[z].bottom);
      double distEdge = (currentPrice >= gZones[z].top)    ? currentPrice - gZones[z].top
                     : (currentPrice <= gZones[z].bottom)  ? gZones[z].bottom - currentPrice
                                                           : 0;
      if(distEdge > maxDist) { gZones[z].score = -1; continue; }

      double recencyFactor = 1.0 - (double)barsAgo / (double)InpRecencyHTFBars;
      gZones[z].score = gZones[z].touches * (1.0 + recencyFactor);
      // clarify side from current price (rebuild bornAsResistance for this snapshot)
      gZones[z].bornAsResistance = (mid >= currentPrice);
   }

   // drop disqualified zones (score < 0)
   int w = 0;
   for(int r = 0; r < gZoneCount; r++)
   {
      if(gZones[r].score >= 0)
      {
         if(w != r) gZones[w] = gZones[r];
         w++;
      }
   }
   gZoneCount = w;

   // ----- pick top-N above and top-N below price -----
   // separate, sort by score desc, then keep
   SZone above[]; ArrayResize(above, gZoneCount);
   SZone below[]; ArrayResize(below, gZoneCount);
   int aN = 0, bN = 0;
   for(int z = 0; z < gZoneCount; z++)
   {
      double mid = 0.5 * (gZones[z].top + gZones[z].bottom);
      if(mid >= currentPrice) above[aN++] = gZones[z];
      else                    below[bN++] = gZones[z];
   }
   SortByScoreDesc(above, aN);
   SortByScoreDesc(below, bN);
   if(aN > InpZonesAbovePrice) aN = InpZonesAbovePrice;
   if(bN > InpZonesBelowPrice) bN = InpZonesBelowPrice;

   gZoneCount = 0;
   for(int i = 0; i < aN; i++) gZones[gZoneCount++] = above[i];
   for(int i = 0; i < bN; i++) gZones[gZoneCount++] = below[i];
   for(int z = 0; z < gZoneCount; z++) gZones[z].visible = true;

   return true;
}

void SortByScoreDesc(SZone &arr[], int n)
{
   for(int i = 0; i < n - 1; i++)
   {
      int best = i;
      for(int j = i + 1; j < n; j++)
         if(arr[j].score > arr[best].score) best = j;
      if(best != i) { SZone tmp = arr[i]; arr[i] = arr[best]; arr[best] = tmp; }
   }
}

//+------------------------------------------------------------------+
//| Detect break + retest on CHART timeframe                         |
//+------------------------------------------------------------------+
void DetectBreaksAndRetests(const datetime &time[],
                            const double   &open[],
                            const double   &high[],
                            const double   &low[],
                            const double   &close[],
                            const double   &chartATR[],
                            int rates_total)
{
   // Limit chart scan window for performance.
   int chartScan = MathMin(800, rates_total - 2);
   if(chartScan < 5) return;

   for(int z = 0; z < gZoneCount; z++)
   {
      // ---- Find the first break (oldest -> newest) ----
      int brokenAt = -1;
      int brokenDir = 0;
      for(int i = chartScan; i >= 1; i--)
      {
         double atr = chartATR[i];
         if(atr <= 0) continue;
         double buf = atr * InpBreakATRMult;
         if(close[i] > gZones[z].top    + buf) { brokenDir = +1; brokenAt = i; break; }
         if(close[i] < gZones[z].bottom - buf) { brokenDir = -1; brokenAt = i; break; }
      }

      if(brokenDir == 0) continue;
      gZones[z].brokenDir       = brokenDir;
      gZones[z].brokenChartBar  = brokenAt;
      gZones[z].brokenTime      = time[brokenAt];

      // ---- Walk forward for the retest window ----
      int windowEnd = MathMax(1, brokenAt - InpRetestMaxBars);
      bool touched = false;
      for(int i = brokenAt - 1; i >= windowEnd; i--)
      {
         double atr = chartATR[i];
         if(atr <= 0) continue;
         double tol = atr * InpRetestTouchATRMult;

         if(brokenDir == +1)
         {
            if(low[i] <= gZones[z].top + tol && low[i] >= gZones[z].bottom - tol * 2)
               touched = true;
         }
         else
         {
            if(high[i] >= gZones[z].bottom - tol && high[i] <= gZones[z].top + tol * 2)
               touched = true;
         }
         if(!touched) continue;

         bool confirm = false;
         if(brokenDir == +1)
         {
            if(close[i] > gZones[z].top + 0.10 * atr && close[i] > open[i])
               confirm = (!InpRequireStrongReject) ||
                         BullishRejection(open, high, low, close, i, rates_total);
         }
         else
         {
            if(close[i] < gZones[z].bottom - 0.10 * atr && close[i] < open[i])
               confirm = (!InpRequireStrongReject) ||
                         BearishRejection(open, high, low, close, i, rates_total);
         }

         // hard invalidation
         if(brokenDir == +1 && close[i] < gZones[z].bottom - 0.5 * atr) break;
         if(brokenDir == -1 && close[i] > gZones[z].top    + 0.5 * atr) break;

         if(confirm)
         {
            gZones[z].retestFired = true;
            gZones[z].retestTime  = time[i];

            double offset = InpArrowOffsetPts * _Point;
            if(brokenDir == +1) BufLong[i]  = low[i]  - offset;
            else                BufShort[i] = high[i] + offset;

            if(i == 1)
               RaiseAlert(brokenDir, time[i], close[i], gZones[z]);
            break;
         }
      }

      // hide expired-broken zones if user wants
      if(InpHideExpiredBroken && gZones[z].brokenDir != 0 && !gZones[z].retestFired)
      {
         int barsSinceBreak = brokenAt; // brokenAt is series index from now
         if(barsSinceBreak > InpRetestMaxBars) gZones[z].visible = false;
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
      if(!gZones[z].visible) continue;

      string name = StringFormat("%sZ%d", OBJ_PREFIX, z);
      datetime t1 = gZones[z].firstTouchTime;
      datetime t2 = InpExtendRight ? tFuture : tNow;
      if(t1 == 0 || t1 > t2) t1 = tNow - PeriodSeconds(_Period) * 50;

      color c;
      if(gZones[z].brokenDir != 0)         c = InpFlipColor;
      else if(gZones[z].bornAsResistance)  c = InpResColor;
      else                                 c = InpSupColor;

      if(ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, gZones[z].top, t2, gZones[z].bottom))
      {
         ObjectSetInteger(0, name, OBJPROP_COLOR, c);
         ObjectSetInteger(0, name, OBJPROP_BACK,  InpFillZones);
         ObjectSetInteger(0, name, OBJPROP_FILL,  InpFillZones);
         ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
         ObjectSetInteger(0, name, OBJPROP_STYLE, gZones[z].brokenDir != 0 ? STYLE_DASH : STYLE_SOLID);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      }

      if(InpShowLabels)
      {
         string lblName = StringFormat("%sL%d", OBJ_PREFIX, z);
         double mid = 0.5 * (gZones[z].top + gZones[z].bottom);
         string tag;
         if(gZones[z].brokenDir != 0 && !gZones[z].retestFired) tag = "RETEST?";
         else if(gZones[z].retestFired)                          tag = "RETESTED";
         else                                                    tag = gZones[z].bornAsResistance ? "RES" : "SUP";
         string txt = StringFormat("%s  %.3f  x%d", tag, mid, gZones[z].touches);

         if(ObjectCreate(0, lblName, OBJ_TEXT, 0, t2, mid))
         {
            ObjectSetString (0, lblName, OBJPROP_TEXT,     txt);
            ObjectSetInteger(0, lblName, OBJPROP_COLOR,    c);
            ObjectSetInteger(0, lblName, OBJPROP_FONTSIZE, 9);
            ObjectSetInteger(0, lblName, OBJPROP_ANCHOR,   ANCHOR_RIGHT);
            ObjectSetInteger(0, lblName, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(0, lblName, OBJPROP_HIDDEN,   true);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| One-line status                                                  |
//+------------------------------------------------------------------+
void UpdateStatus(double currentPrice)
{
   if(!InpShowStatus) { ObjectDelete(0, STATUS_OBJ); return; }

   int up = 0, dn = 0, pending = 0, retd = 0;
   for(int z = 0; z < gZoneCount; z++)
   {
      if(!gZones[z].visible) continue;
      double mid = 0.5 * (gZones[z].top + gZones[z].bottom);
      if(mid >= currentPrice) up++; else dn++;
      if(gZones[z].brokenDir != 0 && !gZones[z].retestFired) pending++;
      if(gZones[z].retestFired) retd++;
   }

   string txt = StringFormat(
      "GBPJPY S/R v2  |  %d zones (%d above %d below)  |  pending retest: %d  |  fired today: %d  |  %s pivots ≥%d touches",
      up + dn, up, dn, pending, retd,
      EnumToString(InpZoneTF), InpMinTouches);

   if(ObjectFind(0, STATUS_OBJ) < 0)
   {
      ObjectCreate(0, STATUS_OBJ, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, STATUS_OBJ, OBJPROP_CORNER,    CORNER_LEFT_UPPER);
      ObjectSetInteger(0, STATUS_OBJ, OBJPROP_XDISTANCE, 12);
      ObjectSetInteger(0, STATUS_OBJ, OBJPROP_YDISTANCE, 18);
      ObjectSetInteger(0, STATUS_OBJ, OBJPROP_FONTSIZE,  9);
      ObjectSetInteger(0, STATUS_OBJ, OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0, STATUS_OBJ, OBJPROP_HIDDEN,    true);
   }
   ObjectSetString (0, STATUS_OBJ, OBJPROP_TEXT,  txt);
   ObjectSetInteger(0, STATUS_OBJ, OBJPROP_COLOR, clrGold);
}

//+------------------------------------------------------------------+
//| Alerts                                                           |
//+------------------------------------------------------------------+
void RaiseAlert(int dir, datetime t, double price, const SZone &z)
{
   string side = (dir == +1) ? "LONG retest" : "SHORT retest";
   string msg  = StringFormat(
      "%s %s @ %.3f  |  Zone %.3f-%.3f x%d touches  |  %s",
      _Symbol, side, price, z.bottom, z.top, z.touches,
      EnumToString(InpZoneTF));
   if(InpPopupAlert) Alert(msg);
   if(InpPushAlert)  SendNotification(msg);
   if(InpEmailAlert) SendMail("GBPJPY S/R Break & Retest v2", msg);
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
   if(rates_total < 100) return 0;

   ArraySetAsSeries(time,  true);
   ArraySetAsSeries(open,  true);
   ArraySetAsSeries(high,  true);
   ArraySetAsSeries(low,   true);
   ArraySetAsSeries(close, true);

   bool firstRun = (prev_calculated == 0);
   bool newBar   = (time[0] != gLastBarSeen);
   if(!firstRun && !newBar) return rates_total;
   gLastBarSeen = time[0];

   ArrayInitialize(BufLong,  0.0);
   ArrayInitialize(BufShort, 0.0);

   double chartATR[];
   ArraySetAsSeries(chartATR, true);
   int needed = MathMin(800, rates_total);
   if(CopyBuffer(hATR_chart, 0, 0, needed + 5, chartATR) < 50) return prev_calculated;

   double currentPrice = close[0];
   if(!BuildZonesFromHTF(currentPrice))
   {
      // not enough HTF data yet
      ObjectsDeleteAll(0, OBJ_PREFIX);
      UpdateStatus(currentPrice);
      return rates_total;
   }
   DetectBreaksAndRetests(time, open, high, low, close, chartATR, rates_total);
   DrawZones(time, rates_total);
   UpdateStatus(currentPrice);

   if(InpPrintDiag && firstRun)
   {
      int up = 0, dn = 0;
      for(int z = 0; z < gZoneCount; z++)
      {
         if(!gZones[z].visible) continue;
         double mid = 0.5 * (gZones[z].top + gZones[z].bottom);
         if(mid >= currentPrice) up++; else dn++;
      }
      PrintFormat("SRBR v2: %d major zones (%d above, %d below) | %s pivots, str=%d, min=%d touches",
                  up + dn, up, dn, EnumToString(InpZoneTF), InpPivotStrength, InpMinTouches);
   }

   ChartRedraw(0);
   return rates_total;
}
//+------------------------------------------------------------------+
