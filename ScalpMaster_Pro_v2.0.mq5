//+------------------------------------------------------------------+
//|                  ScalpMaster Pro v2.0                            |
//|     ATR-Based Intelligent Scalper — Optimized for Micro Accounts |
//|          XAUUSD | EURUSD | GBPUSD | USDJPY — M5/H1              |
//|     Leverage: 1:500-1:1000 | Capital: $5-$100                  |
//+------------------------------------------------------------------+
#property copyright "ScalpMaster Pro v2.0"
#property version   "2.00"
#property strict
#property description "ATR-based scalper with dynamic risk, session filters, and breakeven trailing"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//+------------------------------------------------------------------+
//| ENUMS & STRUCTURES                                               |
//+------------------------------------------------------------------+
enum ENUM_BOT_TF
{
   BTF_M1  = 1,
   BTF_M5  = 5,
   BTF_M15 = 15,
   BTF_M30 = 30,
   BTF_H1  = 60,
   BTF_H4  = 240
};

enum ENUM_BOT_STATE
{
   STATE_IDLE,
   STATE_MA_CROSS,
   STATE_IN_TRADE,
   STATE_WAIT_CONFIRM
};

enum ENUM_SYMBOL_TYPE
{
   SYM_GOLD,    // XAUUSD, XAGUSD
   SYM_FOREX,   // Majors
   SYM_OTHER
};

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+
sinput string          _S0_ = "═══════ ACCOUNT & RISK ═══════";
input  double          InpRiskPercent   = 2.0;           // Risk % per trade
input  double          InpMaxDailyLoss  = 5.0;           // Max Daily Loss % (stop trading)
input  double          InpMinLot        = 0.01;          // Min Lot
input  double          InpMaxLot        = 2.0;           // Max Lot
input  bool            InpUseCentLot    = true;          // Cent Account Mode (0.01 = 0.0001)

sinput string          _S1_ = "═══════ TIMEFRAME & SESSION ═══════";
input  ENUM_BOT_TF     InpTimeframe     = BTF_M5;        // Entry Timeframe
input  ENUM_BOT_TF     InpTrendTF       = BTF_H1;        // Trend Confirmation TF
input  bool            InpUseSession    = true;          // Use Session Filter
input  int             InpLondonStart   = 8;             // London Start (GMT)
input  int             InpLondonEnd     = 16;            // London End (GMT)
input  int             InpNYStart       = 13;            // NY Start (GMT)
input  int             InpNYEnd         = 21;            // NY End (GMT)

sinput string          _S2_ = "═══════ INDICATOR SETTINGS ═══════";
input  int             InpEMAFast       = 9;             // EMA Fast Period
input  int             InpEMASlow       = 21;            // EMA Slow Period
input  int             InpRSIPeriod     = 14;            // RSI Period
input  double          InpRSIOB         = 70.0;          // RSI Overbought
input  double          InpRSIOS         = 30.0;          // RSI Oversold
input  int             InpATRPeriod     = 14;            // ATR Period
input  double          InpATRSLMult     = 1.5;           // ATR SL Multiplier
input  double          InpATRTPMult     = 2.0;           // ATR TP Multiplier

sinput string          _S3_ = "═══════ FILTERS & PROTECTION ═══════";
input  bool            InpUseSpreadFilter = true;        // Enable Spread Filter
input  double          InpMaxSpreadFX   = 2.0;           // Max Spread FX (pips)
input  double          InpMaxSpreadGold = 35.0;          // Max Spread Gold (pips)
input  bool            InpUseNewsFilter = true;          // Enable News Filter
input  int             InpNewsMinutes   = 30;            // News Block Minutes
input  bool            InpUseTrendConfirm = true;        // H1 Trend Confirmation

sinput string          _S4_ = "═══════ TRAILING & BREAKEVEN ═══════";
input  bool            InpUseTrailing   = true;          // Enable ATR Trailing
input  double          InpTrailStartR   = 1.0;           // Start Trailing at R:R
input  double          InpTrailATRMult  = 1.0;           // Trailing ATR Multiplier
input  bool            InpUseBreakeven  = true;          // Move to Breakeven
input  double          InpBEProfitR     = 1.0;           // BE at R:R (1.0 = 1R)

sinput string          _S5_ = "═══════ PANEL ═══════";
input  bool            InpShowPanel     = true;
input  int             InpPanelX        = 15;
input  int             InpPanelY        = 30;

//+------------------------------------------------------------------+
//| GLOBALS                                                          |
//+------------------------------------------------------------------+
CTrade          Trade;
CPositionInfo   PosInfo;
CAccountInfo    AcctInfo;
CSymbolInfo     SymInfo;

int    hEMAFast, hEMASlow, hRSI, hATR, hTrendEMA;
ENUM_TIMEFRAMES botTF, trendTF;
ENUM_BOT_STATE  botState = STATE_IDLE;
ENUM_SYMBOL_TYPE symType = SYM_OTHER;

datetime        lastBarTime  = 0;
datetime        lastTrendBar = 0;
int             barCounter   = 0;

int             crossBar     = -1;
bool            crossDir     = false;  // true=bullish
int             entryBar     = -1;

bool            isBuy        = false;
double          entryPrice   = 0;
double          openLot      = 0;
double          posSL        = 0;
double          posTP        = 0;
double          atrAtEntry   = 0;
ulong           posTicket    = 0;

double          startEquity  = 0;
double          dailyHighEquity = 0;
bool            tradingEnabled = true;

int             statTotal    = 0;
int             statWins     = 0;
double          statProfit   = 0;
string          lastSignal   = "—";
string          botStatus    = "IDLE";
color           statusClr    = C'100,110,130';

// Panel
const color CLR_BG     = C'12,16,28';
const color CLR_HDR    = C'18,24,42';
const color CLR_BORDER = C'40,55,90';
const color CLR_TITLE  = C'0,200,255';
const color CLR_GREEN  = C'30,215,110';
const color CLR_RED    = C'255,70,70';
const color CLR_YELLOW = C'255,210,0';
const color CLR_WHITE  = C'210,218,232';
const color CLR_GRAY   = C'100,112,135';
const color CLR_ACCENT = C'130,100,255';
const string PFX       = "SMPv2_";
const long   MAGIC     = 202506;

//+------------------------------------------------------------------+
//| SYMBOL TYPE DETECTION                                            |
//+------------------------------------------------------------------+
void DetectSymbolType()
{
   string s = StringLower(_Symbol);
   if(StringFind(s, "xau") != -1 || StringFind(s, "xag") != -1 || 
      StringFind(s, "gold") != -1 || StringFind(s, "silver") != -1)
      symType = SYM_GOLD;
   else if(StringFind(s, "eur") != -1 || StringFind(s, "gbp") != -1 || 
           StringFind(s, "usd") != -1 || StringFind(s, "jpy") != -1 ||
           StringFind(s, "aud") != -1 || StringFind(s, "chf") != -1 ||
           StringFind(s, "cad") != -1 || StringFind(s, "nzd") != -1)
      symType = SYM_FOREX;
   else
      symType = SYM_OTHER;
}

string StringLower(string str)
{
   string res = "";
   for(int i = 0; i < StringLen(str); i++)
   {
      ushort c = StringGetCharacter(str, i);
      if(c >= 'A' && c <= 'Z') c += 32;
      res += ShortToString(c);
   }
   return res;
}

//+------------------------------------------------------------------+
//| TIMEFRAME CONVERSION                                             |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES BotTFtoPeriod(ENUM_BOT_TF tf)
{
   switch(tf)
   {
      case BTF_M1:  return PERIOD_M1;
      case BTF_M5:  return PERIOD_M5;
      case BTF_M15: return PERIOD_M15;
      case BTF_M30: return PERIOD_M30;
      case BTF_H1:  return PERIOD_H1;
      case BTF_H4:  return PERIOD_H4;
      default:      return PERIOD_M5;
   }
}

string TFName(ENUM_BOT_TF tf)
{
   switch(tf)
   {
      case BTF_M1:  return "M1";
      case BTF_M5:  return "M5";
      case BTF_M15: return "M15";
      case BTF_M30: return "M30";
      case BTF_H1:  return "H1";
      case BTF_H4:  return "H4";
      default:      return "??";
   }
}

//+------------------------------------------------------------------+
//| SESSION FILTER                                                   |
//+------------------------------------------------------------------+
bool IsTradeSession()
{
   if(!InpUseSession) return true;

   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   int hour = dt.hour;

   bool london = (hour >= InpLondonStart && hour < InpLondonEnd);
   bool ny     = (hour >= InpNYStart && hour < InpNYEnd);

   return (london || ny);
}

//+------------------------------------------------------------------+
//| SPREAD FILTER                                                    |
//+------------------------------------------------------------------+
bool SpreadOK()
{
   if(!InpUseSpreadFilter) return true;

   double spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   double maxSpread = (symType == SYM_GOLD) ? InpMaxSpreadGold : InpMaxSpreadFX;

   // Convert to pips (points/10 for 5-digit brokers)
   double spreadPips = spread / 10.0;
   if(symType == SYM_GOLD) spreadPips = spread; // Gold usually 2-3 digits

   return spreadPips <= maxSpread;
}

//+------------------------------------------------------------------+
//| NEWS FILTER (Simplified - checks for high volatility periods)    |
//+------------------------------------------------------------------+
bool NewsOK()
{
   if(!InpUseNewsFilter) return true;

   // Simplified: Block first 5 minutes of each hour and known news times
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);

   // Block :00-:05 and :30-:35 (common news release times)
   if((dt.min >= 0 && dt.min < 5) || (dt.min >= 30 && dt.min < 35))
      return false;

   return true;
}

//+------------------------------------------------------------------+
//| DAILY LOSS PROTECTION                                            |
//+------------------------------------------------------------------+
void CheckDailyLoss()
{
   if(startEquity == 0) startEquity = AcctInfo.Equity();

   double currentEquity = AcctInfo.Equity();
   if(currentEquity > dailyHighEquity) dailyHighEquity = currentEquity;

   double lossPercent = (startEquity - currentEquity) / startEquity * 100.0;

   if(lossPercent >= InpMaxDailyLoss && tradingEnabled)
   {
      tradingEnabled = false;
      botStatus = "DAILY STOP";
      statusClr = CLR_RED;
      Print("DAILY STOP: Loss limit reached. Trading halted.");

      // Close any open position
      if(HasPosition()) CloseTrade();
   }

   // Reset at new day
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   static int lastDay = -1;
   if(dt.day != lastDay)
   {
      lastDay = dt.day;
      startEquity = currentEquity;
      dailyHighEquity = currentEquity;
      tradingEnabled = true;
      Print("New trading day. Equity reset to: ", startEquity);
   }
}

//+------------------------------------------------------------------+
//| LOT SIZING - Risk-Based                                          |
//+------------------------------------------------------------------+
double CalcLot(double slDistance)
{
   if(slDistance <= 0) return InpMinLot;

   double balance = AcctInfo.Balance();
   if(balance <= 0) return InpMinLot;

   double riskAmount = balance * InpRiskPercent / 100.0;
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   if(tickSize <= 0 || tickValue <= 0 || point <= 0) return InpMinLot;

   double slPoints = slDistance / point;
   double slValue = slPoints * tickValue * (tickSize / point);

   if(slValue <= 0) return InpMinLot;

   double lot = riskAmount / slValue;

   // Cent account adjustment
   if(InpUseCentLot && balance < 1000)
      lot = MathMax(0.01, lot); // Ensure minimum visible lot

   lot = MathMax(InpMinLot, MathMin(InpMaxLot, lot));
   return NormLot(lot);
}

double NormLot(double lot)
{
   SymInfo.Refresh();
   double step = SymInfo.LotsStep();
   if(step <= 0) step = 0.01;
   lot = MathRound(lot / step) * step;
   return MathMax(SymInfo.LotsMin(), MathMin(SymInfo.LotsMax(), lot));
}

//+------------------------------------------------------------------+
//| INIT INDICATORS                                                  |
//+------------------------------------------------------------------+
bool InitIndicators()
{
   botTF = BotTFtoPeriod(InpTimeframe);
   trendTF = BotTFtoPeriod(InpTrendTF);

   hEMAFast  = iMA(_Symbol, botTF, InpEMAFast, 0, MODE_EMA, PRICE_CLOSE);
   hEMASlow  = iMA(_Symbol, botTF, InpEMASlow, 0, MODE_EMA, PRICE_CLOSE);
   hRSI      = iRSI(_Symbol, botTF, InpRSIPeriod, PRICE_CLOSE);
   hATR      = iATR(_Symbol, botTF, InpATRPeriod);
   hTrendEMA = iMA(_Symbol, trendTF, 50, 0, MODE_EMA, PRICE_CLOSE);

   if(hEMAFast == INVALID_HANDLE || hEMASlow == INVALID_HANDLE || 
      hRSI == INVALID_HANDLE || hATR == INVALID_HANDLE ||
      (InpUseTrendConfirm && hTrendEMA == INVALID_HANDLE))
   {
      Alert("ScalpMaster v2: Failed to create indicator handles!");
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| GET INDICATOR DATA                                               |
//+------------------------------------------------------------------+
bool GetEMA(double &f0, double &f1, double &f2, double &s0, double &s1, double &s2)
{
   double fa[], sa[];
   ArraySetAsSeries(fa, true); ArraySetAsSeries(sa, true);
   if(CopyBuffer(hEMAFast, 0, 0, 4, fa) < 4) return false;
   if(CopyBuffer(hEMASlow, 0, 0, 4, sa) < 4) return false;
   f0=fa[0]; f1=fa[1]; f2=fa[2]; s0=sa[0]; s1=sa[1]; s2=sa[2];
   return true;
}

double GetRSI(int shift=1)
{
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(hRSI, 0, 0, shift+2, buf) < shift+2) return 50.0;
   return buf[shift];
}

double GetATR(int shift=1)
{
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(hATR, 0, 0, shift+2, buf) < shift+2) return 0.0;
   return buf[shift];
}

bool GetTrendDirection(bool &bullish)
{
   if(!InpUseTrendConfirm) { bullish = true; return true; }

   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(hTrendEMA, 0, 0, 2, buf) < 2) return false;

   double close[];
   ArraySetAsSeries(close, true);
   if(CopyClose(_Symbol, trendTF, 0, 2, close) < 2) return false;

   bullish = (close[1] > buf[1]);
   return true;
}

//+------------------------------------------------------------------+
//| NEW BAR DETECTION                                                |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime arr[];
   ArraySetAsSeries(arr, true);
   if(CopyTime(_Symbol, botTF, 0, 1, arr) < 1) return false;
   if(arr[0] != lastBarTime)
   {
      lastBarTime = arr[0];
      barCounter++;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| RSI FILTERS                                                      |
//+------------------------------------------------------------------+
bool RSIOKBuy()  
{ 
   double rsi = GetRSI(1);
   return rsi < InpRSIOB && rsi > 40; // Avoid buying in overbought, but allow pullbacks
}

bool RSIOKSell() 
{ 
   double rsi = GetRSI(1);
   return rsi > InpRSIOS && rsi < 60; // Avoid selling in oversold, but allow bounces
}

//+------------------------------------------------------------------+
//| POSITION HELPERS                                                 |
//+------------------------------------------------------------------+
bool FindPosition(ulong &ticket)
{
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      if(PosInfo.SelectByIndex(i))
         if(PosInfo.Symbol() == _Symbol && PosInfo.Magic() == MAGIC)
         { ticket = PosInfo.Ticket(); return true; }
   }
   return false;
}

bool HasPosition()
{
   ulong t;
   return FindPosition(t);
}

double GetPositionProfit()
{
   ulong t;
   if(!FindPosition(t)) return 0;
   if(!PosInfo.SelectByTicket(t)) return 0;
   return PosInfo.Profit() + PosInfo.Swap() + PosInfo.Commission();
}

double GetPositionOpenPrice()
{
   ulong t;
   if(!FindPosition(t)) return 0;
   if(!PosInfo.SelectByTicket(t)) return 0;
   return PosInfo.PriceOpen();
}

//+------------------------------------------------------------------+
//| OPEN TRADE WITH REAL SL/TP                                       |
//+------------------------------------------------------------------+
bool OpenTrade(bool buy)
{
   if(!tradingEnabled) 
   {
      Print("Trading disabled due to daily loss limit.");
      return false;
   }

   if(!IsTradeSession())
   {
      Print("Outside trading session.");
      return false;
   }

   if(!SpreadOK())
   {
      Print("Spread too high. Current: ", SymbolInfoInteger(_Symbol, SYMBOL_SPREAD));
      return false;
   }

   if(!NewsOK())
   {
      Print("News filter active.");
      return false;
   }

   // Calculate ATR-based SL/TP
   double atr = GetATR(1);
   if(atr <= 0) 
   {
      Print("ATR invalid");
      return false;
   }

   double slDistance = atr * InpATRSLMult;
   double tpDistance = atr * InpATRTPMult;

   double lot = CalcLot(slDistance);
   if(lot <= 0) 
   {
      Print("Lot calculation failed");
      return false;
   }

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl, tp;

   if(buy)
   {
      sl = NormalizeDouble(ask - slDistance, _Digits);
      tp = NormalizeDouble(ask + tpDistance, _Digits);
   }
   else
   {
      sl = NormalizeDouble(bid + slDistance, _Digits);
      tp = NormalizeDouble(bid - tpDistance, _Digits);
   }

   // Check stop level
   int stopLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDistance = stopLevel * _Point;

   if(buy && (ask - sl) < minDistance) sl = NormalizeDouble(ask - minDistance - _Point, _Digits);
   if(!buy && (sl - bid) < minDistance) sl = NormalizeDouble(bid + minDistance + _Point, _Digits);

   bool ok = buy ? Trade.Buy(lot, _Symbol, 0, sl, tp, "SMPv2_BUY")
                 : Trade.Sell(lot, _Symbol, 0, sl, tp, "SMPv2_SELL");

   if(!ok)
   { 
      Print("OpenTrade failed: ", GetLastError()); 
      return false; 
   }

   Sleep(200);

   ulong t;
   if(!FindPosition(t))
   { 
      Print("OpenTrade: position not found after open"); 
      return false; 
   }

   posTicket  = t;
   entryPrice = buy ? ask : bid;
   openLot    = lot;
   isBuy      = buy;
   posSL      = sl;
   posTP      = tp;
   atrAtEntry = atr;
   statTotal++;

   botStatus  = buy ? "LONG OPEN" : "SHORT OPEN";
   statusClr  = buy ? CLR_GREEN : CLR_RED;

   Print("Trade opened: ", buy?"BUY":"SELL", " Lot=", lot, 
         " Entry=", entryPrice, " SL=", sl, " TP=", tp, " ATR=", atr);
   return true;
}

//+------------------------------------------------------------------+
//| CLOSE TRADE                                                      |
//+------------------------------------------------------------------+
bool CloseTrade()
{
   ulong t;
   if(!FindPosition(t)) { openLot = 0; posTicket = 0; return true; }

   double profit = GetPositionProfit();

   if(!Trade.PositionClose(t, 20))
   { 
      Print("CloseTrade failed: ", GetLastError()); 
      return false; 
   }

   statProfit += profit;
   if(profit > 0) statWins++;

   posTicket = 0; openLot = 0; atrAtEntry = 0;
   botStatus = "IDLE"; 
   statusClr = CLR_GRAY;

   Print("Trade closed. Profit=", DoubleToString(profit, 2));
   return true;
}

//+------------------------------------------------------------------+
//| ATR TRAILING STOP & BREAKEVEN                                    |
//+------------------------------------------------------------------+
void ManageTrailingStop()
{
   if(!InpUseTrailing && !InpUseBreakeven) return;
   if(!HasPosition()) return;

   ulong t;
   if(!FindPosition(t)) return;
   if(!PosInfo.SelectByTicket(t)) return;

   double openPrice = PosInfo.PriceOpen();
   double currentSL = PosInfo.StopLoss();
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double currentPrice = isBuy ? bid : ask;

   double profitR = 0;
   if(isBuy) profitR = (currentPrice - openPrice) / (openPrice - posSL);
   else profitR = (openPrice - currentPrice) / (posSL - openPrice);

   // Breakeven
   if(InpUseBreakeven && profitR >= InpBEProfitR && currentSL == posSL)
   {
      double beSL = isBuy ? NormalizeDouble(openPrice + 10 * _Point, _Digits)
                          : NormalizeDouble(openPrice - 10 * _Point, _Digits);

      Trade.PositionModify(t, beSL, posTP);
      Print("Breakeven activated. New SL: ", beSL);
      return;
   }

   // ATR Trailing
   if(InpUseTrailing && profitR >= InpTrailStartR)
   {
      double atr = GetATR(0);
      double trailDist = atr * InpTrailATRMult;

      double newSL;
      if(isBuy)
      {
         newSL = NormalizeDouble(bid - trailDist, _Digits);
         if(newSL > currentSL && newSL > openPrice)
            Trade.PositionModify(t, newSL, posTP);
      }
      else
      {
         newSL = NormalizeDouble(ask + trailDist, _Digits);
         if(newSL < currentSL && newSL < openPrice)
            Trade.PositionModify(t, newSL, posTP);
      }
   }
}

//+------------------------------------------------------------------+
//| MAIN SIGNAL LOGIC                                                |
//+------------------------------------------------------------------+
void ProcessBar(int bar)
{
   double ef0,ef1,ef2,es0,es1,es2;
   if(!GetEMA(ef0,ef1,ef2,es0,es1,es2)) return;

   // Detect cross on LAST CLOSED BAR (index 1 vs 2)
   bool emaCrossUp  = ef2 < es2 && ef1 > es1;
   bool emaCrossDn  = ef2 > es2 && ef1 < es1;

   // Trend confirmation
   bool trendBullish;
   if(!GetTrendDirection(trendBullish)) return;

   // RSI filter
   double rsi = GetRSI(1);

   switch(botState)
   {
      case STATE_IDLE:
      {
         if(emaCrossUp || emaCrossDn)
         {
            // Only take trades in trend direction
            if(emaCrossUp && !trendBullish) 
            {
               Print("Bullish cross but H1 trend bearish. Ignored.");
               break;
            }
            if(emaCrossDn && trendBullish)
            {
               Print("Bearish cross but H1 trend bullish. Ignored.");
               break;
            }

            crossBar = bar - 1;
            crossDir = emaCrossUp;
            botState = STATE_MA_CROSS;
            lastSignal = emaCrossUp ? "EMA CROSS ▲" : "EMA CROSS ▼";
            Print("EMA Cross @ bar", crossBar, " ", crossDir?"UP":"DOWN");
         }
         break;
      }

      case STATE_MA_CROSS:
      {
         // Wait 1 bar for confirmation, enter on bar 2
         if(bar >= crossBar + 2)
         {
            bool rsiOk = crossDir ? RSIOKBuy() : RSIOKSell();
            if(!rsiOk)
            {
               Print("RSI blocked entry. Reset.");
               botState = STATE_IDLE;
               break;
            }

            // Additional ATR filter - avoid low volatility
            double atr = GetATR(1);
            double atrPrev = GetATR(2);
            if(atr < atrPrev * 0.5)
            {
               Print("ATR too low. Volatility contraction. Skip.");
               botState = STATE_IDLE;
               break;
            }

            bool opened = OpenTrade(crossDir);
            if(opened)
            {
               entryBar = bar;
               botState = STATE_IN_TRADE;
            }
            else
            {
               botState = STATE_IDLE;
            }
         }
         break;
      }

      case STATE_IN_TRADE:
      {
         ManageTrailingStop();

         // Check if position still exists (hit SL/TP manually)
         if(!HasPosition()) 
         { 
            botState = STATE_IDLE; 
            // Update stats if closed by broker
            if(posTicket != 0)
            {
               statProfit += (isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID) - entryPrice 
                                    : entryPrice - SymbolInfoDouble(_Symbol, SYMBOL_ASK)) * openLot * 100000;
               posTicket = 0;
            }
         }
         break;
      }
   }
}

//+------------------------------------------------------------------+
//| PANEL FUNCTIONS (v2.0 Enhanced)                                  |
//+------------------------------------------------------------------+
void ObjRect(string name, int x, int y, int w, int h, color bg, color border=clrNONE)
{
   ObjectDelete(0, PFX+name);
   ObjectCreate(0, PFX+name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, PFX+name, OBJPROP_XDISTANCE,  x);
   ObjectSetInteger(0, PFX+name, OBJPROP_YDISTANCE,  y);
   ObjectSetInteger(0, PFX+name, OBJPROP_XSIZE,      w);
   ObjectSetInteger(0, PFX+name, OBJPROP_YSIZE,      h);
   ObjectSetInteger(0, PFX+name, OBJPROP_BGCOLOR,    bg);
   ObjectSetInteger(0, PFX+name, OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0, PFX+name, OBJPROP_COLOR,      border==clrNONE ? bg : border);
   ObjectSetInteger(0, PFX+name, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
   ObjectSetInteger(0, PFX+name, OBJPROP_BACK,       false);
   ObjectSetInteger(0, PFX+name, OBJPROP_SELECTABLE, false);
}

void ObjLabel(string name, int x, int y, string txt, color clr, int fs=8, string font="Consolas")
{
   ObjectDelete(0, PFX+name);
   ObjectCreate(0, PFX+name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, PFX+name, OBJPROP_XDISTANCE,  x);
   ObjectSetInteger(0, PFX+name, OBJPROP_YDISTANCE,  y);
   ObjectSetString (0, PFX+name, OBJPROP_TEXT,       txt);
   ObjectSetInteger(0, PFX+name, OBJPROP_COLOR,      clr);
   ObjectSetInteger(0, PFX+name, OBJPROP_FONTSIZE,   fs);
   ObjectSetString (0, PFX+name, OBJPROP_FONT,       font);
   ObjectSetInteger(0, PFX+name, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
   ObjectSetInteger(0, PFX+name, OBJPROP_BACK,       false);
   ObjectSetInteger(0, PFX+name, OBJPROP_SELECTABLE, false);
}

void UpdateLabel(string name, string txt, color clr)
{
   ObjectSetString (0, PFX+name, OBJPROP_TEXT,  txt);
   ObjectSetInteger(0, PFX+name, OBJPROP_COLOR, clr);
}

//+------------------------------------------------------------------+
//| CREATE PANEL                                                     |
//+------------------------------------------------------------------+
void CreatePanel()
{
   if(!InpShowPanel) return;
   int x = InpPanelX, y = InpPanelY;
   int w = 250, h = 420;

   ObjRect("bg",     x,   y,   w,   h,   CLR_BG,    CLR_BORDER);
   ObjRect("hdr",    x+1, y+1, w-2, 28, CLR_HDR,   CLR_BORDER);
   ObjLabel("title", x+10, y+9, "⚡ ScalpMaster Pro v2.0", CLR_TITLE, 9, "Consolas Bold");

   // Account
   ObjRect("sgacct",  x+1,  y+35, w-2, 18, C'22,28,50');
   ObjLabel("sgacct_t",x+8, y+38, "ACCOUNT", CLR_GRAY, 7);
   ObjLabel("lbl_bal", x+8,  y+58, "Balance:",  CLR_GRAY, 8);
   ObjLabel("val_bal", x+130,y+58, "---",       CLR_WHITE, 8);
   ObjLabel("lbl_eq",  x+8,  y+74, "Equity:",   CLR_GRAY, 8);
   ObjLabel("val_eq",  x+130,y+74, "---",       CLR_WHITE, 8);
   ObjLabel("lbl_dd",  x+8,  y+90, "Daily DD:", CLR_GRAY, 8);
   ObjLabel("val_dd",  x+130,y+90, "---",       CLR_WHITE, 8);

   // Config
   ObjRect("sgcfg",   x+1, y+111, w-2, 18, C'22,28,50');
   ObjLabel("sgcfg_t",x+8, y+114, "CONFIG", CLR_GRAY, 7);
   ObjLabel("lbl_sym", x+8, y+134, "Symbol:",   CLR_GRAY, 8);
   ObjLabel("val_sym", x+130,y+134, "---",      CLR_ACCENT, 8);
   ObjLabel("lbl_tf",  x+8, y+150, "Timeframe:",CLR_GRAY, 8);
   ObjLabel("val_tf",  x+130,y+150, "---",      CLR_YELLOW, 8);
   ObjLabel("lbl_rsk", x+8, y+166, "Risk/Trade:",CLR_GRAY, 8);
   ObjLabel("val_rsk", x+130,y+166, "---",      CLR_WHITE, 8);
   ObjLabel("lbl_atr", x+8, y+182, "ATR(14):",  CLR_GRAY, 8);
   ObjLabel("val_atr", x+130,y+182, "---",      CLR_WHITE, 8);

   // Status
   ObjRect("sgtrd",   x+1, y+203, w-2, 18, C'22,28,50');
   ObjLabel("sgtrd_t",x+8, y+206, "TRADE STATUS", CLR_GRAY, 7);
   ObjLabel("lbl_stat",x+8, y+226, "Status:",   CLR_GRAY, 8);
   ObjLabel("val_stat",x+130,y+226, "IDLE",     CLR_GRAY, 8);
   ObjLabel("lbl_sig", x+8, y+242, "Signal:",   CLR_GRAY, 8);
   ObjLabel("val_sig", x+130,y+242, "—",        CLR_WHITE, 8);
   ObjLabel("lbl_pnl", x+8, y+258, "P/L:",      CLR_GRAY, 8);
   ObjLabel("val_pnl", x+130,y+258, "---",      CLR_WHITE, 8);
   ObjLabel("lbl_spr", x+8, y+274, "Spread:",   CLR_GRAY, 8);
   ObjLabel("val_spr", x+130,y+274, "---",      CLR_WHITE, 8);

   // Stats
   ObjRect("sgstat",  x+1, y+295, w-2, 18, C'22,28,50');
   ObjLabel("sgstat_t",x+8,y+298, "STATISTICS", CLR_GRAY, 7);
   ObjLabel("lbl_tot",x+8, y+318, "Trades:",   CLR_GRAY, 8);
   ObjLabel("val_tot",x+130,y+318, "0",        CLR_WHITE, 8);
   ObjLabel("lbl_wr", x+8, y+334, "Win Rate:", CLR_GRAY, 8);
   ObjLabel("val_wr", x+130,y+334, "--",       CLR_WHITE, 8);
   ObjLabel("lbl_pl", x+8, y+350, "Total P/L:",CLR_GRAY, 8);
   ObjLabel("val_pl", x+130,y+350, "0.00",     CLR_WHITE, 8);

   // Risk Bar
   ObjRect("riskbar_bg", x+10, y+370, w-20, 8, C'40,30,30');
   ObjRect("riskbar",    x+10, y+370, 0,    8, CLR_GREEN);

   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| UPDATE PANEL                                                     |
//+------------------------------------------------------------------+
void UpdatePanel()
{
   if(!InpShowPanel) return;

   string cur = AcctInfo.Currency();
   double balance = AcctInfo.Balance();
   double equity = AcctInfo.Equity();
   double dd = (startEquity > 0) ? (startEquity - equity) / startEquity * 100.0 : 0;

   // Account
   UpdateLabel("val_bal", DoubleToString(balance,2)+" "+cur, CLR_WHITE);
   UpdateLabel("val_eq",  DoubleToString(equity,2)+" "+cur, CLR_WHITE);
   UpdateLabel("val_dd",  DoubleToString(dd,1)+"%", dd > InpMaxDailyLoss*0.8 ? CLR_RED : CLR_YELLOW);

   // Config
   UpdateLabel("val_sym", _Symbol, CLR_ACCENT);
   UpdateLabel("val_tf",  TFName(InpTimeframe), CLR_YELLOW);
   UpdateLabel("val_rsk", DoubleToString(InpRiskPercent,1)+"%", CLR_WHITE);
   UpdateLabel("val_atr", DoubleToString(GetATR(1), _Digits), CLR_WHITE);

   // Status
   UpdateLabel("val_stat", botStatus, statusClr);
   UpdateLabel("val_sig",  lastSignal, CLR_WHITE);

   double pnl = GetPositionProfit();
   color pnlClr = pnl > 0 ? CLR_GREEN : (pnl < 0 ? CLR_RED : CLR_GRAY);
   UpdateLabel("val_pnl", DoubleToString(pnl,2)+" "+cur, pnlClr);

   double spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   double spreadPips = (symType == SYM_GOLD) ? spread : spread/10.0;
   color sprClr = SpreadOK() ? CLR_GREEN : CLR_RED;
   UpdateLabel("val_spr", DoubleToString(spreadPips,1), sprClr);

   // Stats
   double wr = statTotal > 0 ? (double)statWins/statTotal*100.0 : 0;
   UpdateLabel("val_tot", IntegerToString(statTotal), CLR_WHITE);
   UpdateLabel("val_wr",  DoubleToString(wr,1)+"%", wr>=50?CLR_GREEN:CLR_RED);
   UpdateLabel("val_pl",  DoubleToString(statProfit,2)+" "+cur, statProfit>=0?CLR_GREEN:CLR_RED);

   // Risk bar
   double riskPct = MathMin(dd / InpMaxDailyLoss * 100.0, 100.0);
   int barW = (int)((250-20) * riskPct / 100.0);
   color barClr = riskPct < 50 ? CLR_GREEN : (riskPct < 80 ? CLR_YELLOW : CLR_RED);
   ObjectSetInteger(0, PFX+"riskbar", OBJPROP_XSIZE, barW);
   ObjectSetInteger(0, PFX+"riskbar", OBJPROP_BGCOLOR, barClr);

   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| REMOVE PANEL                                                     |
//+------------------------------------------------------------------+
void DestroyPanel()
{
   ObjectsDeleteAll(0, PFX);
}

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   DetectSymbolType();
   botTF = BotTFtoPeriod(InpTimeframe);
   trendTF = BotTFtoPeriod(InpTrendTF);
   SymInfo.Name(_Symbol);

   Trade.SetExpertMagicNumber(MAGIC);
   Trade.SetDeviationInPoints(20);
   Trade.SetTypeFilling(ORDER_FILLING_IOC);
   Trade.SetAsyncMode(false);

   if(!InitIndicators()) return INIT_FAILED;

   startEquity = AcctInfo.Equity();
   dailyHighEquity = startEquity;

   Print("ScalpMaster Pro v2.0 initialized.");
   Print("Symbol: ", _Symbol, " Type: ", symType==SYM_GOLD?"GOLD":(symType==SYM_FOREX?"FX":"OTHER"));
   Print("TF: ", TFName(InpTimeframe), " TrendTF: ", TFName(InpTrendTF));
   Print("Session: London ", InpLondonStart, "-", InpLondonEnd, " GMT | NY ", InpNYStart, "-", InpNYEnd, " GMT");

   if(InpShowPanel)
   {
      CreatePanel();
      UpdatePanel();
   }
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(hEMAFast);
   IndicatorRelease(hEMASlow);
   IndicatorRelease(hRSI);
   IndicatorRelease(hATR);
   IndicatorRelease(hTrendEMA);
   DestroyPanel();
}

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick()
{
   // Daily loss check
   CheckDailyLoss();

   // Panel update every tick
   if(InpShowPanel) UpdatePanel();

   // Trailing stop management every tick
   if(botState == STATE_IN_TRADE)
      ManageTrailingStop();

   // Logic on new bar only
   if(!IsNewBar()) return;
   ProcessBar(barCounter);
}
//+------------------------------------------------------------------+
