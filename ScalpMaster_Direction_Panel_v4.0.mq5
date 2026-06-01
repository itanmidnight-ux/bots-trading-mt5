//+------------------------------------------------------------------+
//|              ScalpMaster Direction Panel v4.0                    |
//|     M1 Scalping Indicator with H1 Confirmation + Volatility      |
//|           For Manual Trading - High Confluence Signals           |
//|     Strategy: EMA 8/13/21 Ribbon + H1 Trend + RSI + ATR          |
//+------------------------------------------------------------------+
#property copyright "ScalpMaster Direction Panel v4.0"
#property version   "4.00"
#property strict
#property indicator_chart_window
#property indicator_buffers 8
#property indicator_plots   8

//--- Plot 0: Buy Arrows
#property indicator_label1   "Buy Signal"
#property indicator_type1    DRAW_ARROW
#property indicator_color1   clrLime
#property indicator_style1   STYLE_SOLID
#property indicator_width1   2

//--- Plot 1: Sell Arrows
#property indicator_label2   "Sell Signal"
#property indicator_type2    DRAW_ARROW
#property indicator_color2   clrRed
#property indicator_style2   STYLE_SOLID
#property indicator_width2   2

//--- Plot 2: Fast EMA
#property indicator_label3   "EMA Fast"
#property indicator_type3    DRAW_LINE
#property indicator_color3   clrDodgerBlue
#property indicator_style3   STYLE_SOLID
#property indicator_width3   1

//--- Plot 3: Mid EMA
#property indicator_label4   "EMA Mid"
#property indicator_type4    DRAW_LINE
#property indicator_color4   clrOrange
#property indicator_style4   STYLE_SOLID
#property indicator_width4   1

//--- Plot 4: Slow EMA
#property indicator_label5   "EMA Slow"
#property indicator_type5    DRAW_LINE
#property indicator_color5   clrMagenta
#property indicator_style5   STYLE_SOLID
#property indicator_width5   1

//--- Plot 5: Trend Strength (for calculations)
#property indicator_label6   "Trend Strength"
#property indicator_type6    DRAW_NONE
#property indicator_color6   clrGray

//--- Plot 6: H1 Bullish Level
#property indicator_label7   "H1 Bull Level"
#property indicator_type7    DRAW_LINE
#property indicator_color7   clrGreen
#property indicator_style7   STYLE_DOT
#property indicator_width7   1

//--- Plot 7: H1 Bearish Level
#property indicator_label8   "H1 Bear Level"
#property indicator_type8    DRAW_LINE
#property indicator_color8   clrRed
#property indicator_style8   STYLE_DOT
#property indicator_width8   1

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+
input group "═══════ M1 EMA RIBBON ═══════"
input int    InpEMAFast   = 8;        // Fast EMA (M1)
input int    InpEMAMid    = 13;       // Mid EMA (M1)
input int    InpEMASlow   = 21;       // Slow EMA (M1)

input group "═══════ H1 TREND CONFIRMATION ═══════"
input int    InpH1EMAFast = 8;        // H1 Fast EMA
input int    InpH1EMASlow = 21;       // H1 Slow EMA
input bool   InpUseH1Confirm = true;  // Enable H1 Filter

input group "═══════ RSI MOMENTUM (M1) ═══════"
input int    InpRSIPeriod = 7;        // RSI Period
input double InpRSIOB     = 70;       // Overbought
input double InpRSIOS     = 30;       // Oversold
input bool   InpUseRSI    = true;     // Enable RSI

input group "═══════ ATR VOLATILITY FILTER ═══════"
input int    InpATRPeriod = 14;       // ATR Period
input double InpATRMin    = 0.5;      // Min ATR (pips)
input double InpATRMax    = 5.0;      // Max ATR (pips)
input bool   InpUseATR    = true;     // Enable ATR Filter

input group "═══════ SESSION FILTER ═══════"
input bool   InpUseSession = true;    // Enable Session
input int    InpSessionStart = 8;     // London Open GMT
input int    InpSessionEnd   = 20;    // NY Close GMT

input group "═══════ PANEL SETTINGS ═══════"
input int    InpPanelX = 10;
input int    InpPanelY = 30;
input bool   InpShowArrows = true;    // Show buy/sell arrows

//+------------------------------------------------------------------+
//| INDICATOR BUFFERS                                                |
//+------------------------------------------------------------------+
double BuyArrow[];
double SellArrow[];
double FastEMA[];
double MidEMA[];
double SlowEMA[];
double TrendStrength[];
double H1BullLevel[];
double H1BearLevel[];

//+------------------------------------------------------------------+
//| GLOBALS                                                          |
//+------------------------------------------------------------------+
int    hH1Fast, hH1Slow, hRSI, hATR;
double lastATR = 0;
double lastRSI = 50;
bool   h1Bullish = false;
bool   h1Bearish = false;
string lastStatus = "WAIT";
color  lastStatusColor = clrYellow;
int    lastBarCounted = 0;

const string PFX = "SMPanel_";
const ushort ARROW_BUY = 233;
const ushort ARROW_SELL = 234;

//+------------------------------------------------------------------+
//| INIT                                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   // Set indicator buffers
   SetIndexBuffer(0, BuyArrow, INDICATOR_DATA);
   SetIndexBuffer(1, SellArrow, INDICATOR_DATA);
   SetIndexBuffer(2, FastEMA, INDICATOR_DATA);
   SetIndexBuffer(3, MidEMA, INDICATOR_DATA);
   SetIndexBuffer(4, SlowEMA, INDICATOR_DATA);
   SetIndexBuffer(5, TrendStrength, INDICATOR_DATA);
   SetIndexBuffer(6, H1BullLevel, INDICATOR_DATA);
   SetIndexBuffer(7, H1BearLevel, INDICATOR_DATA);

   // Set arrays as timeseries
   ArraySetAsSeries(BuyArrow, true);
   ArraySetAsSeries(SellArrow, true);
   ArraySetAsSeries(FastEMA, true);
   ArraySetAsSeries(MidEMA, true);
   ArraySetAsSeries(SlowEMA, true);
   ArraySetAsSeries(TrendStrength, true);
   ArraySetAsSeries(H1BullLevel, true);
   ArraySetAsSeries(H1BearLevel, true);

   // Arrow settings
   PlotIndexSetInteger(0, PLOT_ARROW, ARROW_BUY);
   PlotIndexSetInteger(0, PLOT_ARROW_SHIFT, -15);
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   PlotIndexSetInteger(1, PLOT_ARROW, ARROW_SELL);
   PlotIndexSetInteger(1, PLOT_ARROW_SHIFT, 15);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   // Create higher timeframe indicators
   hH1Fast = iMA(_Symbol, PERIOD_H1, InpH1EMAFast, 0, MODE_EMA, PRICE_CLOSE);
   hH1Slow = iMA(_Symbol, PERIOD_H1, InpH1EMASlow, 0, MODE_EMA, PRICE_CLOSE);
   hRSI = iRSI(_Symbol, PERIOD_M1, InpRSIPeriod, PRICE_CLOSE);
   hATR = iATR(_Symbol, PERIOD_M1, InpATRPeriod);

   if(hH1Fast == INVALID_HANDLE || hH1Slow == INVALID_HANDLE || 
      hRSI == INVALID_HANDLE || hATR == INVALID_HANDLE)
   {
      Alert("Failed to create indicator handles! Check symbol and timeframe.");
      return INIT_FAILED;
   }

   // Check if enough data
   int h1Bars = iBars(_Symbol, PERIOD_H1);
   int m1Bars = iBars(_Symbol, PERIOD_M1);
   if(h1Bars < InpH1EMASlow + 10 || m1Bars < InpEMASlow + 10)
   {
      Alert("Not enough historical data. Wait for data download.");
      return INIT_FAILED;
   }

   CreatePanel();
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| DEINIT                                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(hH1Fast);
   IndicatorRelease(hH1Slow);
   IndicatorRelease(hRSI);
   IndicatorRelease(hATR);
   ObjectsDeleteAll(0, PFX);
}

//+------------------------------------------------------------------+
//| CALCULATE                                                        |
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
   if(rates_total < InpEMASlow + 10) return 0;

   int start;
   if(prev_calculated == 0)
   {
      start = InpEMASlow;
      // Initialize all buffers
      ArrayInitialize(BuyArrow, EMPTY_VALUE);
      ArrayInitialize(SellArrow, EMPTY_VALUE);
      ArrayInitialize(FastEMA, EMPTY_VALUE);
      ArrayInitialize(MidEMA, EMPTY_VALUE);
      ArrayInitialize(SlowEMA, EMPTY_VALUE);
      ArrayInitialize(TrendStrength, 0);
      ArrayInitialize(H1BullLevel, EMPTY_VALUE);
      ArrayInitialize(H1BearLevel, EMPTY_VALUE);
   }
   else
   {
      start = prev_calculated - 1;
      if(start < InpEMASlow) start = InpEMASlow;
   }

   // Calculate EMAs using built-in MA
   for(int i = start; i < rates_total; i++)
   {
      FastEMA[i] = iMA(NULL, 0, InpEMAFast, 0, MODE_EMA, PRICE_CLOSE, rates_total - 1 - i);
      MidEMA[i] = iMA(NULL, 0, InpEMAMid, 0, MODE_EMA, PRICE_CLOSE, rates_total - 1 - i);
      SlowEMA[i] = iMA(NULL, 0, InpEMASlow, 0, MODE_EMA, PRICE_CLOSE, rates_total - 1 - i);
   }

   // Get H1 trend and indicator values
   UpdateH1Trend();
   UpdateIndicators();

   // Generate signals
   for(int i = start; i < rates_total; i++)
   {
      if(!InpShowArrows)
      {
         BuyArrow[i] = EMPTY_VALUE;
         SellArrow[i] = EMPTY_VALUE;
      }

      TrendStrength[i] = 0;
      H1BullLevel[i] = EMPTY_VALUE;
      H1BearLevel[i] = EMPTY_VALUE;

      if(i < 2) continue;

      // EMA Ribbon alignment
      bool ribbonBull = (FastEMA[i] > MidEMA[i] && MidEMA[i] > SlowEMA[i]);
      bool ribbonBear = (FastEMA[i] < MidEMA[i] && MidEMA[i] < SlowEMA[i]);

      // EMA Cross detection (confirmed on closed bar)
      bool crossUp = (FastEMA[i-1] <= MidEMA[i-1] && FastEMA[i] > MidEMA[i]);
      bool crossDn = (FastEMA[i-1] >= MidEMA[i-1] && FastEMA[i] < MidEMA[i]);

      // Signal quality score (0-100)
      int quality = 0;

      // H1 confirmation (+40 points)
      if(InpUseH1Confirm)
      {
         if(ribbonBull && h1Bullish) quality += 40;
         if(ribbonBear && h1Bearish) quality += 40;
      }
      else quality += 40;

      // RSI confirmation (+20 points)
      if(InpUseRSI)
      {
         if(ribbonBull && lastRSI < InpRSIOB && lastRSI > 40) quality += 20;
         if(ribbonBear && lastRSI > InpRSIOS && lastRSI < 60) quality += 20;
      }
      else quality += 20;

      // ATR volatility (+20 points)
      if(InpUseATR)
      {
         double atrPips = lastATR / _Point / 10.0;
         if(atrPips >= InpATRMin && atrPips <= InpATRMax) quality += 20;
      }
      else quality += 20;

      // Session (+20 points)
      if(InpUseSession)
      {
         if(IsTradeSession()) quality += 20;
      }
      else quality += 20;

      TrendStrength[i] = quality;

      // Set H1 levels for visual reference
      if(h1Bullish) H1BullLevel[i] = SlowEMA[i];
      if(h1Bearish) H1BearLevel[i] = SlowEMA[i];

      // Signal arrows only on cross with high quality
      if(InpShowArrows && quality >= 80)
      {
         if(crossUp && ribbonBull)
         {
            BuyArrow[i] = Low[i] - 3 * _Point;
            SellArrow[i] = EMPTY_VALUE;
         }
         else if(crossDn && ribbonBear)
         {
            SellArrow[i] = High[i] + 3 * _Point;
            BuyArrow[i] = EMPTY_VALUE;
         }
         else
         {
            BuyArrow[i] = EMPTY_VALUE;
            SellArrow[i] = EMPTY_VALUE;
         }
      }
      else
      {
         BuyArrow[i] = EMPTY_VALUE;
         SellArrow[i] = EMPTY_VALUE;
      }
   }

   // Update panel on every calculation
   if(rates_total != lastBarCounted)
   {
      lastBarCounted = rates_total;
      UpdatePanel();
   }

   return rates_total;
}

//+------------------------------------------------------------------+
//| UPDATE H1 TREND                                                  |
//+------------------------------------------------------------------+
void UpdateH1Trend()
{
   double fast[3];
   double slow[3];
   ArraySetAsSeries(fast, true);
   ArraySetAsSeries(slow, true);

   int copied1 = CopyBuffer(hH1Fast, 0, 0, 3, fast);
   int copied2 = CopyBuffer(hH1Slow, 0, 0, 3, slow);

   if(copied1 < 3 || copied2 < 3) return;

   h1Bullish = (fast[0] > slow[0]);
   h1Bearish = (fast[0] < slow[0]);
}

//+------------------------------------------------------------------+
//| UPDATE INDICATORS                                                |
//+------------------------------------------------------------------+
void UpdateIndicators()
{
   double rsi[3];
   double atr[3];
   ArraySetAsSeries(rsi, true);
   ArraySetAsSeries(atr, true);

   int copied1 = CopyBuffer(hRSI, 0, 0, 3, rsi);
   int copied2 = CopyBuffer(hATR, 0, 0, 3, atr);

   if(copied1 >= 3) lastRSI = rsi[0];
   if(copied2 >= 3) lastATR = atr[0];
}

//+------------------------------------------------------------------+
//| SESSION CHECK                                                    |
//+------------------------------------------------------------------+
bool IsTradeSession()
{
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   int hour = dt.hour;
   return (hour >= InpSessionStart && hour < InpSessionEnd);
}

//+------------------------------------------------------------------+
//| PANEL FUNCTIONS                                                  |
//+------------------------------------------------------------------+
void ObjRect(string name, int x, int y, int w, int h, color bg, color border=clrNONE)
{
   ObjectDelete(0, PFX+name);
   ObjectCreate(0, PFX+name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, PFX+name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, PFX+name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, PFX+name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, PFX+name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, PFX+name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, PFX+name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, PFX+name, OBJPROP_COLOR, border==clrNONE ? bg : border);
   ObjectSetInteger(0, PFX+name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, PFX+name, OBJPROP_BACK, false);
   ObjectSetInteger(0, PFX+name, OBJPROP_SELECTABLE, false);
}

void ObjLabel(string name, int x, int y, string txt, color clr, int fs=8, string font="Consolas")
{
   ObjectDelete(0, PFX+name);
   ObjectCreate(0, PFX+name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, PFX+name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, PFX+name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, PFX+name, OBJPROP_TEXT, txt);
   ObjectSetInteger(0, PFX+name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, PFX+name, OBJPROP_FONTSIZE, fs);
   ObjectSetString(0, PFX+name, OBJPROP_FONT, font);
   ObjectSetInteger(0, PFX+name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, PFX+name, OBJPROP_BACK, false);
   ObjectSetInteger(0, PFX+name, OBJPROP_SELECTABLE, false);
}

void UpdateLabel(string name, string txt, color clr)
{
   if(ObjectFind(0, PFX+name) < 0) return;
   ObjectSetString(0, PFX+name, OBJPROP_TEXT, txt);
   ObjectSetInteger(0, PFX+name, OBJPROP_COLOR, clr);
}

//+------------------------------------------------------------------+
//| CREATE PANEL                                                     |
//+------------------------------------------------------------------+
void CreatePanel()
{
   int x = InpPanelX, y = InpPanelY;
   int w = 240, h = 280;

   // Background
   ObjRect("bg", x, y, w, h, C'12,16,28', C'40,55,90');

   // Header
   ObjRect("hdr", x+1, y+1, w-2, 28, C'18,24,42', C'40,55,90');
   ObjLabel("title", x+10, y+7, "ScalpMaster Panel v4.0", C'0,200,255', 9, "Consolas Bold");

   // H1 Trend Section
   int sy = y + 35;
   ObjRect("sg_h1", x+1, sy, w-2, 18, C'22,28,50');
   ObjLabel("sg_h1_t", x+8, sy+2, "H1 TREND DIRECTION", C'100,112,135', 7);

   sy += 22;
   ObjLabel("lbl_h1dir", x+8, sy, "Direction:", C'100,112,135', 8);
   ObjLabel("val_h1dir", x+120, sy, "NEUTRAL", C'255,210,0', 9, "Consolas Bold");
   sy += 16;
   ObjLabel("lbl_h1emas", x+8, sy, "H1 EMAs:", C'100,112,135', 8);
   ObjLabel("val_h1emas", x+120, sy, "-- / --", C'210,218,232', 8);

   // M1 Status Section
   sy += 22;
   ObjRect("sg_m1", x+1, sy, w-2, 18, C'22,28,50');
   ObjLabel("sg_m1_t", x+8, sy+2, "M1 MARKET STATUS", C'100,112,135', 7);

   sy += 22;
   ObjLabel("lbl_ribbon", x+8, sy, "EMA Ribbon:", C'100,112,135', 8);
   ObjLabel("val_ribbon", x+120, sy, "NEUTRAL", C'255,210,0', 8);
   sy += 16;
   ObjLabel("lbl_rsi", x+8, sy, "RSI(7):", C'100,112,135', 8);
   ObjLabel("val_rsi", x+120, sy, "50.0", C'210,218,232', 8);
   sy += 16;
   ObjLabel("lbl_atr", x+8, sy, "ATR (pips):", C'100,112,135', 8);
   ObjLabel("val_atr", x+120, sy, "0.0", C'210,218,232', 8);
   sy += 16;
   ObjLabel("lbl_session", x+8, sy, "Session:", C'100,112,135', 8);
   ObjLabel("val_session", x+120, sy, "CLOSED", C'255,70,70', 8);

   // Signal Section
   sy += 22;
   ObjRect("sg_sig", x+1, sy, w-2, 18, C'22,28,50');
   ObjLabel("sg_sig_t", x+8, sy+2, "TRADING SIGNAL", C'100,112,135', 7);

   sy += 22;
   ObjLabel("lbl_quality", x+8, sy, "Quality Score:", C'100,112,135', 8);
   ObjLabel("val_quality", x+120, sy, "0/100", C'210,218,232', 9, "Consolas Bold");
   sy += 18;
   ObjLabel("lbl_action", x+8, sy, "ACTION:", C'100,112,135', 8);
   ObjLabel("val_action", x+120, sy, "WAIT", C'255,210,0', 10, "Consolas Bold");

   // Quality bar
   sy += 20;
   ObjRect("qual_bg", x+10, sy, w-20, 6, C'40,30,30');
   ObjRect("qual_fg", x+10, sy, 0, 6, C'255,210,0');

   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| UPDATE PANEL                                                     |
//+------------------------------------------------------------------+
void UpdatePanel()
{
   int x = InpPanelX, y = InpPanelY;
   int w = 240;

   // H1 Direction
   string h1Dir = h1Bullish ? "BULLISH UP" : (h1Bearish ? "BEARISH DN" : "NEUTRAL —");
   color h1Clr = h1Bullish ? clrLime : (h1Bearish ? clrRed : clrYellow);
   UpdateLabel("val_h1dir", h1Dir, h1Clr);

   // H1 EMA values
   double fastVal[1], slowVal[1];
   ArraySetAsSeries(fastVal, true);
   ArraySetAsSeries(slowVal, true);
   if(CopyBuffer(hH1Fast, 0, 0, 1, fastVal) == 1 && CopyBuffer(hH1Slow, 0, 0, 1, slowVal) == 1)
   {
      UpdateLabel("val_h1emas", DoubleToString(fastVal[0], _Digits) + " / " + DoubleToString(slowVal[0], _Digits), clrWhite);
   }

   // M1 Ribbon status
   int total = ArraySize(FastEMA);
   if(total > 2)
   {
      bool ribbonBull = (FastEMA[0] > MidEMA[0] && MidEMA[0] > SlowEMA[0]);
      bool ribbonBear = (FastEMA[0] < MidEMA[0] && MidEMA[0] < SlowEMA[0]);
      string ribDir = ribbonBull ? "BULLISH UP" : (ribbonBear ? "BEARISH DN" : "MIXED —");
      color ribClr = ribbonBull ? clrLime : (ribbonBear ? clrRed : clrYellow);
      UpdateLabel("val_ribbon", ribDir, ribClr);
   }

   // RSI
   UpdateLabel("val_rsi", DoubleToString(lastRSI, 1), 
               (lastRSI > InpRSIOB || lastRSI < InpRSIOS) ? clrRed : clrGreen);

   // ATR
   double atrPips = lastATR / _Point / 10.0;
   color atrClr = (atrPips >= InpATRMin && atrPips <= InpATRMax) ? clrGreen : clrRed;
   UpdateLabel("val_atr", DoubleToString(atrPips, 2), atrClr);

   // Session
   bool inSession = IsTradeSession();
   UpdateLabel("val_session", inSession ? "OPEN OK" : "CLOSED", inSession ? clrGreen : clrRed);

   // Calculate current quality score
   int quality = 0;
   int total = ArraySize(FastEMA);
   if(total > 2)
   {
      bool ribbonBull = (FastEMA[0] > MidEMA[0] && MidEMA[0] > SlowEMA[0]);
      bool ribbonBear = (FastEMA[0] < MidEMA[0] && MidEMA[0] < SlowEMA[0]);

      if(InpUseH1Confirm)
      {
         if((h1Bullish && ribbonBull) || (h1Bearish && ribbonBear)) quality += 40;
      }
      else quality += 40;

      if(InpUseRSI)
      {
         if(lastRSI > InpRSIOS && lastRSI < InpRSIOB) quality += 20;
      }
      else quality += 20;

      if(InpUseATR)
      {
         if(atrPips >= InpATRMin && atrPips <= InpATRMax) quality += 20;
      }
      else quality += 20;

      if(InpUseSession && inSession) quality += 20;
      else if(!InpUseSession) quality += 20;
   }

   UpdateLabel("val_quality", IntegerToString(quality) + "/100", 
               quality >= 80 ? clrLime : (quality >= 60 ? clrYellow : clrRed));

   // Action recommendation
   string action = "WAIT";
   color actClr = clrYellow;
   if(quality >= 80)
   {
      bool ribbonBull = (FastEMA[0] > MidEMA[0] && MidEMA[0] > SlowEMA[0]);
      bool ribbonBear = (FastEMA[0] < MidEMA[0] && MidEMA[0] < SlowEMA[0]);

      if(h1Bullish && ribbonBull)
      { action = "BUY NOW"; actClr = clrLime; }
      else if(h1Bearish && ribbonBear)
      { action = "SELL NOW"; actClr = clrRed; }
   }
   else if(quality >= 60)
   {
      action = "PREPARE";
      actClr = clrOrange;
   }

   UpdateLabel("val_action", action, actClr);

   // Quality bar
   int barW = (int)((w-20) * quality / 100.0);
   color barClr = quality >= 80 ? clrLime : (quality >= 60 ? clrYellow : clrRed);
   if(ObjectFind(0, PFX+"qual_fg") >= 0)
   {
      ObjectSetInteger(0, PFX+"qual_fg", OBJPROP_XSIZE, barW);
      ObjectSetInteger(0, PFX+"qual_fg", OBJPROP_BGCOLOR, barClr);
   }

   ChartRedraw(0);
}
//+------------------------------------------------------------------+
