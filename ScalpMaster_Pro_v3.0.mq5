//+------------------------------------------------------------------+
//|                  ScalpMaster Pro v3.0                            |
//|  MA Cross + SuperTrend + ADX + Market Structure + Volume Scalper |
//|     Optimized for Micro Accounts <$20 | Leverage 1:500-1:1000    |
//|           XAUUSD | EURUSD | GBPUSD | USDJPY | US30               |
//+------------------------------------------------------------------+
#property copyright "ScalpMaster Pro v3.0"
#property version   "3.00"
#property strict
#property description "Professional scalper: MA+SuperTrend+ADX+Structure+Volume. 8H directional bias."

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//+------------------------------------------------------------------+
//| ENUMERATIONS                                                     |
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
   STATE_MA_CROSS_WAIT,
   STATE_IN_TRADE
};

enum ENUM_SYMBOL_TYPE
{
   SYM_GOLD,
   SYM_FOREX,
   SYM_INDICES,
   SYM_OTHER
};

enum ENUM_MARKET_STRUCTURE
{
   STRUCT_BULLISH,   // Higher Highs + Higher Lows
   STRUCT_BEARISH,   // Lower Highs + Lower Lows
   STRUCT_NEUTRAL    // Consolidation / Ranging
};

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+
//--- Account & Risk
input group "═══════ ACCOUNT & RISK MANAGEMENT ═══════"
input double InpRiskPercent    = 1.5;     // Risk % per trade (1.0-2.0 recommended)
input double InpMaxDailyLoss   = 3.0;     // Max Daily Loss % (halt trading)
input double InpMaxDailyTrades = 8;       // Max trades per day
input double InpMinLot       = 0.01;     // Minimum Lot Size
input double InpMaxLot       = 1.0;      // Maximum Lot Size
input bool   InpUseCentMode  = true;     // Cent Account (0.01 = $0.01/pip)

//--- Timeframe & Session
input group "═══════ TIMEFRAME & SESSION ═══════"
input ENUM_BOT_TF InpEntryTF     = BTF_M5;   // Entry Timeframe
input ENUM_BOT_TF InpStructureTF = BTF_H1;   // Market Structure TF (8H lookback)
input bool        InpUseSession  = true;    // Enable Session Filter
input int         InpSessionStart = 8;       // Trading Start (GMT)
input int         InpSessionEnd   = 20;      // Trading End (GMT)
input bool        InpUseFridayFilter = true;  // No new trades after Friday 18:00 GMT

//--- Moving Averages
input group "═══════ MA CROSSOVER SETTINGS ═══════"
input int    InpMAFastPeriod  = 7;        // MA Fast Period
input int    InpMASlowPeriod  = 21;       // MA Slow Period
input int    InpMAMethod      = MODE_SMA; // MA Method (SMA/EMA)

//--- SuperTrend Confirmation
input group "═══════ SUPERTREND CONFIRMATION ═══════"
input int    InpSTPeriod      = 10;       // SuperTrend ATR Period
input double InpSTMultiplier  = 1.5;      // SuperTrend Multiplier
input bool   InpUseSuperTrend = true;     // Enable SuperTrend Filter

//--- ADX Strength Filter
input group "═══════ ADX STRENGTH FILTER ═══════"
input int    InpADXPeriod     = 14;       // ADX Period
input double InpADXMin        = 25.0;     // Min ADX for Trend Strength
input bool   InpUseADX        = true;     // Enable ADX Filter

//--- RSI Filter
input group "═══════ RSI FILTER ═══════"
input int    InpRSIPeriod     = 7;        // RSI Period (7 for M5 scalping)
input double InpRSIOB         = 70.0;     // RSI Overbought
input double InpRSIOS         = 30.0;     // RSI Oversold
input bool   InpUseRSI        = true;     // Enable RSI Filter

//--- Volume Confirmation
input group "═══════ VOLUME CONFIRMATION ═══════"
input bool   InpUseVolume     = true;     // Enable Volume Filter
input double InpVolMinMult    = 1.2;      // Min Volume vs Avg (1.2 = 20% above avg)

//--- Market Structure (8H Directional Bias)
input group "═══════ MARKET STRUCTURE (8H BIAS) ═══════"
input bool   InpUseStructure  = true;     // Enable 8H Structure Filter
input int    InpStructureLookback = 96;   // Bars for structure (96 bars = 8H on M5)
input int    InpSwingBars     = 3;        // Swing detection bars

//--- ATR-Based Stops
input group "═══════ ATR STOP MANAGEMENT ═══════"
input int    InpATRPeriod     = 14;       // ATR Period
input double InpATRSLMult     = 1.0;      // ATR SL Multiplier
input double InpATRTPMult     = 1.5;      // ATR TP Multiplier
input bool   InpUseTrailing   = true;     // Enable ATR Trailing Stop
input double InpTrailStartR   = 0.8;      // Start Trailing at R:R
input double InpTrailATRMult  = 0.8;      // Trailing ATR Multiplier
input bool   InpUseBreakeven  = true;     // Move to Breakeven
input double InpBEAtR         = 0.6;        // BE at R:R

//--- Spread & Slippage Protection
input group "═══════ SPREAD & SLIPPAGE ═══════"
input bool   InpUseSpreadFilter = true;   // Enable Spread Filter
input double InpMaxSpreadFX   = 1.5;      // Max Spread FX (pips)
input double InpMaxSpreadGold = 25.0;     // Max Spread Gold (points)
input double InpMaxSpreadIdx  = 3.0;      // Max Spread Indices (points)
input int    InpMaxSlippage   = 20;       // Max Slippage (points)

//--- News Filter
input group "═══════ NEWS FILTER ═══════"
input bool   InpUseNewsFilter = true;     // Enable News Filter
input int    InpNewsBlockMin  = 15;       // Minutes before/after news to block

//--- Panel
input group "═══════ DASHBOARD PANEL ═══════"
input bool   InpShowPanel     = true;
input int    InpPanelX        = 15;
input int    InpPanelY        = 30;

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                 |
//+------------------------------------------------------------------+
CTrade          Trade;
CPositionInfo   PosInfo;
CAccountInfo    AcctInfo;
CSymbolInfo     SymInfo;

// Indicator handles
int    hMAFast, hMASlow;
int    hSuperTrend;
int    hADX;
int    hRSI;
int    hATR;
int    hVolume;

// Timeframes
ENUM_TIMEFRAMES entryTF;
ENUM_TIMEFRAMES structureTF;

// State
ENUM_BOT_STATE  botState = STATE_IDLE;
ENUM_SYMBOL_TYPE symType = SYM_OTHER;
ENUM_MARKET_STRUCTURE marketStructure = STRUCT_NEUTRAL;

// Bar tracking
datetime lastBarTime  = 0;
int      barCounter   = 0;

// Signal tracking
int      crossBar     = -1;
bool     crossDir     = false;  // true = bullish cross
int      entryBar     = -1;

// Position tracking
bool     isBuy        = false;
double   entryPrice   = 0;
double   openLot      = 0;
double   posSL        = 0;
double   posTP        = 0;
double   atrAtEntry   = 0;
ulong    posTicket    = 0;

// Risk management
double   startEquity     = 0;
double   dailyHighEquity = 0;
bool     tradingEnabled  = true;
int      dailyTradeCount = 0;
int      lastTradeDay    = -1;

// Statistics
int      statTotal    = 0;
int      statWins     = 0;
double   statProfit   = 0;
string   lastSignal   = "—";
string   botStatus    = "IDLE";
color    statusClr    = C'100,110,130';

// Panel colors
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
const color CLR_ORANGE = C'255,155,30';
const string PFX       = "SMPv3_";
const long   MAGIC     = 20250630;

//+------------------------------------------------------------------+
//| SYMBOL TYPE DETECTION                                            |
//+------------------------------------------------------------------+
void DetectSymbolType()
{
   string s = StringLower(_Symbol);

   if(StringFind(s, "xau") != -1 || StringFind(s, "xag") != -1 || 
      StringFind(s, "gold") != -1 || StringFind(s, "silver") != -1)
      symType = SYM_GOLD;
   else if(StringFind(s, "us30") != -1 || StringFind(s, "nas100") != -1 || 
           StringFind(s, "spx500") != -1 || StringFind(s, "ger30") != -1 ||
           StringFind(s, "uk100") != -1)
      symType = SYM_INDICES;
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

string StructureName(ENUM_MARKET_STRUCTURE s)
{
   switch(s)
   {
      case STRUCT_BULLISH: return "BULLISH";
      case STRUCT_BEARISH: return "BEARISH";
      default:             return "NEUTRAL";
   }
}

//+------------------------------------------------------------------+
//| SESSION & TIME FILTERS                                           |
//+------------------------------------------------------------------+
bool IsTradeSession()
{
   if(!InpUseSession) return true;

   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   int hour = dt.hour;

   // Friday filter
   if(InpUseFridayFilter && dt.day_of_week == 5 && hour >= 18)
      return false;

   return (hour >= InpSessionStart && hour < InpSessionEnd);
}

bool IsWeekend()
{
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   return (dt.day_of_week == 0 || dt.day_of_week == 6);
}

//+------------------------------------------------------------------+
//| SPREAD FILTER                                                    |
//+------------------------------------------------------------------+
bool SpreadOK()
{
   if(!InpUseSpreadFilter) return true;

   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   double maxSpread;

   switch(symType)
   {
      case SYM_GOLD:    maxSpread = InpMaxSpreadGold; break;
      case SYM_INDICES: maxSpread = InpMaxSpreadIdx;  break;
      default:          maxSpread = InpMaxSpreadFX;   break;
   }

   // For FX: convert points to pips (5-digit brokers)
   double spreadPips = (symType == SYM_FOREX) ? (double)spread / 10.0 : (double)spread;

   return spreadPips <= maxSpread;
}

//+------------------------------------------------------------------+
//| NEWS FILTER (Simplified)                                         |
//+------------------------------------------------------------------+
bool NewsOK()
{
   if(!InpUseNewsFilter) return true;

   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);

   // Block :00-:03 and :30-:33 (common news times)
   if((dt.min >= 0 && dt.min < InpNewsBlockMin/5) || 
      (dt.min >= 30 && dt.min < 30 + InpNewsBlockMin/5))
      return false;

   // Block major news hours (NFP, FOMC typically 12:30-14:00 GMT)
   if(dt.hour == 12 && dt.min >= 15) return false;
   if(dt.hour == 13 && dt.min <= 30) return false;

   return true;
}

//+------------------------------------------------------------------+
//| DAILY RISK MANAGEMENT                                            |
//+------------------------------------------------------------------+
void CheckDailyRisk()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);

   // Reset daily counters
   if(dt.day != lastTradeDay)
   {
      lastTradeDay = dt.day;
      dailyTradeCount = 0;
      startEquity = AcctInfo.Equity();
      dailyHighEquity = startEquity;
      tradingEnabled = true;
      Print("New trading day. Equity: ", startEquity, " Date: ", dt.day, "/", dt.mon);
   }

   if(startEquity <= 0) startEquity = AcctInfo.Equity();

   double currentEquity = AcctInfo.Equity();
   if(currentEquity > dailyHighEquity) dailyHighEquity = currentEquity;

   double lossPercent = (startEquity - currentEquity) / startEquity * 100.0;

   if(lossPercent >= InpMaxDailyLoss && tradingEnabled)
   {
      tradingEnabled = false;
      botStatus = "DAILY STOP";
      statusClr = CLR_RED;
      Print("DAILY STOP: Loss limit ", InpMaxDailyLoss, "% reached. Trading halted.");

      if(HasPosition()) CloseTrade();
   }
}

//+------------------------------------------------------------------+
//| LOT SIZING - Risk-Based with Cent Account Support                |
//+------------------------------------------------------------------+
double CalcLot(double slDistance)
{
   if(slDistance <= 0) return InpMinLot;

   double balance = AcctInfo.Balance();
   if(balance <= 0) return InpMinLot;

   double riskAmount = balance * InpRiskPercent / 100.0;

   double tickSize   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double point      = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double contract   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);

   if(tickSize <= 0 || tickValue <= 0 || point <= 0) return InpMinLot;

   // Calculate SL value in account currency
   double slPoints = slDistance / point;
   double slValuePerLot = slPoints * tickValue;

   if(slValuePerLot <= 0) return InpMinLot;

   double lot = riskAmount / slValuePerLot;

   // Cent account: if balance < $1000, treat as cent (divide by 100 for real lot)
   if(InpUseCentMode && balance < 1000.0)
   {
      // In cent accounts, 0.01 lot = 0.0001 standard lot
      // But we display 0.01 as minimum
      lot = MathMax(0.01, lot);
   }

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
   entryTF = BotTFtoPeriod(InpEntryTF);
   structureTF = BotTFtoPeriod(InpStructureTF);

   // MA Crossover
   hMAFast = iMA(_Symbol, entryTF, InpMAFastPeriod, 0, InpMAMethod, PRICE_CLOSE);
   hMASlow = iMA(_Symbol, entryTF, InpMASlowPeriod, 0, InpMAMethod, PRICE_CLOSE);

   // SuperTrend (ATR-based)
   hSuperTrend = iCustom(_Symbol, entryTF, "Supertrend", InpSTPeriod, InpSTMultiplier);
   if(hSuperTrend == INVALID_HANDLE)
   {
      // Fallback: create ATR-based SuperTrend manually if indicator not found
      Print("SuperTrend indicator not found, using internal calculation");
      hSuperTrend = INVALID_HANDLE;
   }

   // ADX
   hADX = iADX(_Symbol, entryTF, InpADXPeriod);

   // RSI
   hRSI = iRSI(_Symbol, entryTF, InpRSIPeriod, PRICE_CLOSE);

   // ATR
   hATR = iATR(_Symbol, entryTF, InpATRPeriod);

   // Volume (built-in)
   hVolume = INVALID_HANDLE; // Will use tick volume directly

   if(hMAFast == INVALID_HANDLE || hMASlow == INVALID_HANDLE || 
      hADX == INVALID_HANDLE || hRSI == INVALID_HANDLE || hATR == INVALID_HANDLE)
   {
      Alert("ScalpMaster v3: Failed to create indicator handles!");
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| GET INDICATOR DATA                                               |
//+------------------------------------------------------------------+
bool GetMAValues(double &fast0, double &fast1, double &fast2, 
                 double &slow0, double &slow1, double &slow2)
{
   double bufFast[];
   double bufSlow[];
   ArraySetAsSeries(bufFast, true);
   ArraySetAsSeries(bufSlow, true);

   if(CopyBuffer(hMAFast, 0, 0, 4, bufFast) < 4) return false;
   if(CopyBuffer(hMASlow, 0, 0, 4, bufSlow) < 4) return false;

   fast0 = bufFast[0]; fast1 = bufFast[1]; fast2 = bufFast[2];
   slow0 = bufSlow[0]; slow1 = bufSlow[1]; slow2 = bufSlow[2];
   return true;
}

bool GetSuperTrend(bool &bullish)
{
   if(!InpUseSuperTrend) { bullish = true; return true; }

   // If custom indicator available, use it
   if(hSuperTrend != INVALID_HANDLE)
   {
      double bufTrend[];
      ArraySetAsSeries(bufTrend, true);
      if(CopyBuffer(hSuperTrend, 0, 0, 2, bufTrend) < 2) return false;
      // Buffer 0 usually contains trend direction or line value
      // We'll use internal calculation as fallback for reliability
   }

   // Internal SuperTrend calculation
   double atr = GetATR(1);
   if(atr <= 0) { bullish = true; return true; }

   double close[];
   double high[];
   double low[];
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);

   if(CopyClose(_Symbol, entryTF, 0, 3, close) < 3) return false;
   if(CopyHigh(_Symbol, entryTF, 0, 3, high) < 3) return false;
   if(CopyLow(_Symbol, entryTF, 0, 3, low) < 3) return false;

   double hl2_1 = (high[1] + low[1]) / 2.0;
   double upperBand = hl2_1 + InpSTMultiplier * atr;
   double lowerBand = hl2_1 - InpSTMultiplier * atr;

   // Simple trend detection based on close vs bands
   bullish = (close[1] > lowerBand);

   return true;
}

bool GetADX(double &adxValue, double &plusDI, double &minusDI)
{
   if(!InpUseADX) { adxValue = 50.0; plusDI = 30; minusDI = 20; return true; }

   double bufADX[], bufPlus[], bufMinus[];
   ArraySetAsSeries(bufADX, true);
   ArraySetAsSeries(bufPlus, true);
   ArraySetAsSeries(bufMinus, true);

   if(CopyBuffer(hADX, 0, 0, 2, bufADX) < 2) return false;
   if(CopyBuffer(hADX, 1, 0, 2, bufPlus) < 2) return false;
   if(CopyBuffer(hADX, 2, 0, 2, bufMinus) < 2) return false;

   adxValue = bufADX[1];
   plusDI = bufPlus[1];
   minusDI = bufMinus[1];
   return true;
}

double GetRSI(int shift)
{
   if(!InpUseRSI) return 50.0;

   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(hRSI, 0, 0, shift + 2, buf) < shift + 2) return 50.0;
   return buf[shift];
}

double GetATR(int shift)
{
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(hATR, 0, 0, shift + 2, buf) < shift + 2) return 0.0;
   return buf[shift];
}

bool VolumeOK()
{
   if(!InpUseVolume) return true;

   long vol[];
   ArraySetAsSeries(vol, true);
   if(CopyTickVolume(_Symbol, entryTF, 0, 20, vol) < 20) return true;

   double avgVol = 0;
   for(int i = 1; i < 20; i++)
      avgVol += (double)vol[i];
   avgVol /= 19.0;

   double currentVol = (double)vol[0];

   return (currentVol >= avgVol * InpVolMinMult);
}

//+------------------------------------------------------------------+
//| MARKET STRUCTURE DETECTION (8H Directional Bias)                 |
//+------------------------------------------------------------------+
void UpdateMarketStructure()
{
   if(!InpUseStructure) 
   { 
      marketStructure = STRUCT_NEUTRAL; 
      return; 
   }

   double high[];
   double low[];
   double close[];
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);

   int barsNeeded = InpStructureLookback;
   if(CopyHigh(_Symbol, structureTF, 0, barsNeeded, high) < barsNeeded) return;
   if(CopyLow(_Symbol, structureTF, 0, barsNeeded, low) < barsNeeded) return;
   if(CopyClose(_Symbol, structureTF, 0, barsNeeded, close) < barsNeeded) return;

   // Find swing highs and lows
   double lastHigh = 0, prevHigh = 0;
   double lastLow = DBL_MAX, prevLow = DBL_MAX;
   int lastHighIdx = -1, prevHighIdx = -1;
   int lastLowIdx = -1, prevLowIdx = -1;

   for(int i = InpSwingBars; i < barsNeeded - InpSwingBars; i++)
   {
      // Swing High
      bool isSwingHigh = true;
      for(int j = 1; j <= InpSwingBars; j++)
      {
         if(high[i] <= high[i+j] || high[i] <= high[i-j]) 
         { isSwingHigh = false; break; }
      }

      if(isSwingHigh)
      {
         if(lastHighIdx == -1 || i < lastHighIdx)
         {
            prevHigh = lastHigh;
            prevHighIdx = lastHighIdx;
            lastHigh = high[i];
            lastHighIdx = i;
         }
         else if(prevHighIdx == -1 || i < prevHighIdx)
         {
            prevHigh = high[i];
            prevHighIdx = i;
         }
      }

      // Swing Low
      bool isSwingLow = true;
      for(int j = 1; j <= InpSwingBars; j++)
      {
         if(low[i] >= low[i+j] || low[i] >= low[i-j]) 
         { isSwingLow = false; break; }
      }

      if(isSwingLow)
      {
         if(lastLowIdx == -1 || i < lastLowIdx)
         {
            prevLow = lastLow;
            prevLowIdx = lastLowIdx;
            lastLow = low[i];
            lastLowIdx = i;
         }
         else if(prevLowIdx == -1 || i < prevLowIdx)
         {
            prevLow = low[i];
            prevLowIdx = i;
         }
      }
   }

   // Determine structure
   if(lastHigh > prevHigh && lastLow > prevLow && prevHigh > 0 && prevLow < DBL_MAX)
      marketStructure = STRUCT_BULLISH;
   else if(lastHigh < prevHigh && lastLow < prevLow && prevHigh > 0 && prevLow < DBL_MAX)
      marketStructure = STRUCT_BEARISH;
   else
      marketStructure = STRUCT_NEUTRAL;
}

bool StructureAllowsBuy()
{
   if(!InpUseStructure) return true;
   return (marketStructure == STRUCT_BULLISH || marketStructure == STRUCT_NEUTRAL);
}

bool StructureAllowsSell()
{
   if(!InpUseStructure) return true;
   return (marketStructure == STRUCT_BEARISH || marketStructure == STRUCT_NEUTRAL);
}

//+------------------------------------------------------------------+
//| NEW BAR DETECTION                                                |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime arr[];
   ArraySetAsSeries(arr, true);
   if(CopyTime(_Symbol, entryTF, 0, 1, arr) < 1) return false;
   if(arr[0] != lastBarTime)
   {
      lastBarTime = arr[0];
      barCounter++;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| POSITION HELPERS                                                 |
//+------------------------------------------------------------------+
bool FindPosition(ulong &ticket)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
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

//+------------------------------------------------------------------+
//| OPEN TRADE                                                       |
//+------------------------------------------------------------------+
bool OpenTrade(bool buy)
{
   // Pre-trade checks
   if(!tradingEnabled)
   { Print("Trading disabled - daily loss limit reached"); return false; }

   if(dailyTradeCount >= InpMaxDailyTrades)
   { Print("Daily trade limit reached: ", dailyTradeCount); return false; }

   if(IsWeekend())
   { Print("Weekend - no trading"); return false; }

   if(!IsTradeSession())
   { Print("Outside trading session"); return false; }

   if(!SpreadOK())
   { Print("Spread too high: ", SymbolInfoInteger(_Symbol, SYMBOL_SPREAD)); return false; }

   if(!NewsOK())
   { Print("News filter active"); return false; }

   // Calculate ATR-based SL/TP
   double atr = GetATR(1);
   if(atr <= 0) { Print("ATR invalid"); return false; }

   double slDistance = atr * InpATRSLMult;
   double tpDistance = atr * InpATRTPMult;

   double lot = CalcLot(slDistance);
   if(lot <= 0) { Print("Lot calculation failed"); return false; }

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

   // Verify stop level
   int stopLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDist = stopLevel * _Point;

   if(buy && (ask - sl) < minDist) sl = NormalizeDouble(ask - minDist - _Point, _Digits);
   if(!buy && (sl - bid) < minDist) sl = NormalizeDouble(bid + minDist + _Point, _Digits);

   // Execute trade
   bool ok;
   if(buy)
      ok = Trade.Buy(lot, _Symbol, 0, sl, tp, "SMPv3_BUY");
   else
      ok = Trade.Sell(lot, _Symbol, 0, sl, tp, "SMPv3_SELL");

   if(!ok)
   { Print("Trade execution failed: ", GetLastError()); return false; }

   Sleep(300);

   ulong t;
   if(!FindPosition(t))
   { Print("Position not found after open"); return false; }

   // Update tracking
   posTicket  = t;
   entryPrice = buy ? ask : bid;
   openLot    = lot;
   isBuy      = buy;
   posSL      = sl;
   posTP      = tp;
   atrAtEntry = atr;
   dailyTradeCount++;
   statTotal++;

   botStatus = buy ? "LONG OPEN" : "SHORT OPEN";
   statusClr = buy ? CLR_GREEN : CLR_RED;

   Print("=== TRADE OPENED ===");
   Print("Direction: ", buy ? "BUY" : "SELL");
   Print("Lot: ", DoubleToString(lot, 2));
   Print("Entry: ", DoubleToString(entryPrice, _Digits));
   Print("SL: ", DoubleToString(sl, _Digits), " (", DoubleToString(slDistance/_Point, 0), " pts)");
   Print("TP: ", DoubleToString(tp, _Digits), " (", DoubleToString(tpDistance/_Point, 0), " pts)");
   Print("ATR: ", DoubleToString(atr, _Digits));
   Print("Structure: ", StructureName(marketStructure));
   Print("Daily Trade: ", dailyTradeCount, "/", InpMaxDailyTrades);

   return true;
}

//+------------------------------------------------------------------+
//| CLOSE TRADE                                                      |
//+------------------------------------------------------------------+
bool CloseTrade()
{
   ulong t;
   if(!FindPosition(t)) 
   { 
      openLot = 0; posTicket = 0; 
      return true; 
   }

   double profit = GetPositionProfit();

   if(!Trade.PositionClose(t, InpMaxSlippage))
   { 
      Print("CloseTrade failed: ", GetLastError()); 
      return false; 
   }

   statProfit += profit;
   if(profit > 0) statWins++;

   posTicket = 0; openLot = 0; atrAtEntry = 0;
   botStatus = "IDLE"; 
   statusClr = CLR_GRAY;

   Print("=== TRADE CLOSED === Profit: ", DoubleToString(profit, 2));
   return true;
}

//+------------------------------------------------------------------+
//| TRAILING STOP & BREAKEVEN                                        |
//+------------------------------------------------------------------+
void ManageTrailingStop()
{
   if(!HasPosition()) return;

   ulong t;
   if(!FindPosition(t)) return;
   if(!PosInfo.SelectByTicket(t)) return;

   double openPrice = PosInfo.PriceOpen();
   double currentSL = PosInfo.StopLoss();
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double currentPrice = isBuy ? bid : ask;

   // Calculate current R:R
   double profitR = 0;
   if(isBuy) 
      profitR = (currentPrice - openPrice) / (openPrice - posSL);
   else 
      profitR = (openPrice - currentPrice) / (posSL - openPrice);

   // Breakeven
   if(InpUseBreakeven && profitR >= InpBEAtR && MathAbs(currentSL - posSL) < _Point * 10)
   {
      double beSL = isBuy ? NormalizeDouble(openPrice + 5 * _Point, _Digits)
                          : NormalizeDouble(openPrice - 5 * _Point, _Digits);

      // Verify BE is better than current SL
      if((isBuy && beSL > currentSL) || (!isBuy && beSL < currentSL))
      {
         Trade.PositionModify(t, beSL, posTP);
         Print("Breakeven activated @ ", DoubleToString(beSL, _Digits));
      }
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
         {
            Trade.PositionModify(t, newSL, posTP);
            Print("Trailing SL updated: ", DoubleToString(newSL, _Digits));
         }
      }
      else
      {
         newSL = NormalizeDouble(ask + trailDist, _Digits);
         if(newSL < currentSL && newSL < openPrice)
         {
            Trade.PositionModify(t, newSL, posTP);
            Print("Trailing SL updated: ", DoubleToString(newSL, _Digits));
         }
      }
   }
}

//+------------------------------------------------------------------+
//| MAIN SIGNAL LOGIC                                                |
//+------------------------------------------------------------------+
void ProcessBar(int bar)
{
   // Update market structure on every bar
   UpdateMarketStructure();

   // Get MA values
   double f0, f1, f2, s0, s1, s2;
   if(!GetMAValues(f0, f1, f2, s0, s1, s2)) return;

   // Detect MA cross on confirmed bar [1] vs [2]
   bool maCrossUp  = (f2 < s2) && (f1 > s1);
   bool maCrossDn  = (f2 > s2) && (f1 < s1);

   // Get SuperTrend direction
   bool stBullish;
   if(!GetSuperTrend(stBullish)) return;

   // Get ADX
   double adxVal, plusDI, minusDI;
   if(!GetADX(adxVal, plusDI, minusDI)) return;
   bool adxStrong = (adxVal >= InpADXMin);
   bool adxBullish = (plusDI > minusDI);

   // Get RSI
   double rsi = GetRSI(1);

   // Volume check
   bool volOK = VolumeOK();

   switch(botState)
   {
      case STATE_IDLE:
      {
         if(maCrossUp || maCrossDn)
         {
            bool isBullish = maCrossUp;

            // Log all filters for debugging
            string filterLog = "Signal detected: " + (isBullish ? "BULLISH" : "BEARISH");
            filterLog += " | ST: " + (stBullish ? "UP" : "DOWN");
            filterLog += " | ADX: " + DoubleToString(adxVal, 1) + (adxStrong ? "(STRONG)" : "(WEAK)");
            filterLog += " | RSI: " + DoubleToString(rsi, 1);
            filterLog += " | VOL: " + (volOK ? "OK" : "LOW");
            filterLog += " | STRUCT: " + StructureName(marketStructure);
            Print(filterLog);

            // Filter 1: SuperTrend alignment
            if(InpUseSuperTrend)
            {
               if(isBullish && !stBullish) 
               { Print("FILTERED: SuperTrend bearish on bullish signal"); break; }
               if(!isBullish && stBullish) 
               { Print("FILTERED: SuperTrend bullish on bearish signal"); break; }
            }

            // Filter 2: ADX strength
            if(InpUseADX && !adxStrong)
            { Print("FILTERED: ADX too weak (", DoubleToString(adxVal, 1), " < ", InpADXMin, ")"); break; }

            // Filter 3: ADX direction alignment
            if(InpUseADX)
            {
               if(isBullish && !adxBullish) 
               { Print("FILTERED: ADX -DI > +DI on bullish signal"); break; }
               if(!isBullish && adxBullish) 
               { Print("FILTERED: ADX +DI > -DI on bearish signal"); break; }
            }

            // Filter 4: RSI
            if(InpUseRSI)
            {
               if(isBullish && rsi > InpRSIOB) 
               { Print("FILTERED: RSI overbought (", DoubleToString(rsi, 1), ")"); break; }
               if(!isBullish && rsi < InpRSIOS) 
               { Print("FILTERED: RSI oversold (", DoubleToString(rsi, 1), ")"); break; }
            }

            // Filter 5: Volume
            if(InpUseVolume && !volOK)
            { Print("FILTERED: Volume below threshold"); break; }

            // Filter 6: Market Structure (8H bias)
            if(InpUseStructure)
            {
               if(isBullish && !StructureAllowsBuy())
               { Print("FILTERED: Structure BEARISH, no BUY allowed"); break; }
               if(!isBullish && !StructureAllowsSell())
               { Print("FILTERED: Structure BULLISH, no SELL allowed"); break; }
            }

            // All filters passed - wait for confirmation bar
            crossBar = bar - 1;
            crossDir = isBullish;
            botState = STATE_MA_CROSS_WAIT;
            lastSignal = isBullish ? "MA▲ ST▲ ADX▲" : "MA▼ ST▼ ADX▼";
            Print("=== ALL FILTERS PASSED === Waiting confirmation @ bar", crossBar);
         }
         break;
      }

      case STATE_MA_CROSS_WAIT:
      {
         // Wait 1 bar for confirmation, enter on bar 2 after cross
         if(bar >= crossBar + 2)
         {
            // Re-verify conditions haven't changed
            double rf0, rf1, rf2, rs0, rs1, rs2;
            if(!GetMAValues(rf0, rf1, rf2, rs0, rs1, rs2)) 
            { botState = STATE_IDLE; break; }

            // Ensure MA is still aligned
            bool stillBullish = (rf1 > rs1);
            bool stillBearish = (rf1 < rs1);

            if(crossDir && !stillBullish) 
            { Print("MA cross invalidated - bullish signal lost"); botState = STATE_IDLE; break; }
            if(!crossDir && !stillBearish) 
            { Print("MA cross invalidated - bearish signal lost"); botState = STATE_IDLE; break; }

            // Re-verify SuperTrend
            bool currentST;
            if(!GetSuperTrend(currentST)) { botState = STATE_IDLE; break; }
            if(crossDir && !currentST) { Print("SuperTrend flipped bearish"); botState = STATE_IDLE; break; }
            if(!crossDir && currentST) { Print("SuperTrend flipped bullish"); botState = STATE_IDLE; break; }

            // Open trade
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

         // Check if position closed externally (SL/TP hit)
         if(!HasPosition()) 
         { 
            botState = STATE_IDLE;
            if(posTicket != 0)
            {
               // Position closed by broker
               Print("Position closed by broker (SL/TP)");
               posTicket = 0;
            }
         }
         break;
      }
   }
}

//+------------------------------------------------------------------+
//| PANEL FUNCTIONS                                                  |
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
   if(ObjectFind(0, PFX+name) < 0) return;
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
   int w = 260, h = 460;

   // Main background
   ObjRect("bg",     x,   y,   w,   h,   CLR_BG,    CLR_BORDER);

   // Header
   ObjRect("hdr",    x+1, y+1, w-2, 30, CLR_HDR,   CLR_BORDER);
   ObjLabel("title", x+10, y+8, "⚡ ScalpMaster Pro v3.0", CLR_TITLE, 10, "Consolas Bold");

   // Account Section
   int sy = y + 38;
   ObjRect("sg_acct",  x+1,  sy, w-2, 20, C'22,28,50');
   ObjLabel("sg_acct_t",x+8, sy+3, "ACCOUNT", CLR_GRAY, 7);

   sy += 24;
   ObjLabel("lbl_bal", x+8,  sy, "Balance:",  CLR_GRAY, 8);
   ObjLabel("val_bal", x+135,sy, "---",       CLR_WHITE, 8);
   sy += 16;
   ObjLabel("lbl_eq",  x+8,  sy, "Equity:",   CLR_GRAY, 8);
   ObjLabel("val_eq",  x+135,sy, "---",       CLR_WHITE, 8);
   sy += 16;
   ObjLabel("lbl_dd",  x+8,  sy, "Daily DD:", CLR_GRAY, 8);
   ObjLabel("val_dd",  x+135,sy, "---",       CLR_WHITE, 8);
   sy += 16;
   ObjLabel("lbl_trd", x+8,  sy, "Trades:",   CLR_GRAY, 8);
   ObjLabel("val_trd", x+135,sy, "0/8",       CLR_WHITE, 8);

   // Market Structure Section
   sy += 24;
   ObjRect("sg_str",   x+1,  sy, w-2, 20, C'22,28,50');
   ObjLabel("sg_str_t",x+8, sy+3, "8H MARKET STRUCTURE", CLR_GRAY, 7);

   sy += 24;
   ObjLabel("lbl_struct", x+8,  sy, "Direction:",  CLR_GRAY, 8);
   ObjLabel("val_struct", x+135,sy, "NEUTRAL",     CLR_YELLOW, 8);
   sy += 16;
   ObjLabel("lbl_adx",    x+8,  sy, "ADX:",        CLR_GRAY, 8);
   ObjLabel("val_adx",    x+135,sy, "--",          CLR_WHITE, 8);
   sy += 16;
   ObjLabel("lbl_rsi",    x+8,  sy, "RSI(7):",     CLR_GRAY, 8);
   ObjLabel("val_rsi",    x+135,sy, "--",          CLR_WHITE, 8);
   sy += 16;
   ObjLabel("lbl_vol",    x+8,  sy, "Volume:",     CLR_GRAY, 8);
   ObjLabel("val_vol",    x+135,sy, "--",          CLR_WHITE, 8);

   // Trade Status Section
   sy += 24;
   ObjRect("sg_trd",   x+1,  sy, w-2, 20, C'22,28,50');
   ObjLabel("sg_trd_t",x+8, sy+3, "TRADE STATUS", CLR_GRAY, 7);

   sy += 24;
   ObjLabel("lbl_stat", x+8,  sy, "Status:",   CLR_GRAY, 8);
   ObjLabel("val_stat", x+135,sy, "IDLE",        CLR_GRAY, 8);
   sy += 16;
   ObjLabel("lbl_sig",  x+8,  sy, "Signal:",    CLR_GRAY, 8);
   ObjLabel("val_sig",  x+135,sy, "—",          CLR_WHITE, 8);
   sy += 16;
   ObjLabel("lbl_pnl",  x+8,  sy, "P/L:",       CLR_GRAY, 8);
   ObjLabel("val_pnl",  x+135,sy, "---",        CLR_WHITE, 8);
   sy += 16;
   ObjLabel("lbl_spr",  x+8,  sy, "Spread:",    CLR_GRAY, 8);
   ObjLabel("val_spr",  x+135,sy, "---",        CLR_WHITE, 8);

   // Statistics Section
   sy += 24;
   ObjRect("sg_sts",   x+1,  sy, w-2, 20, C'22,28,50');
   ObjLabel("sg_sts_t",x+8, sy+3, "STATISTICS", CLR_GRAY, 7);

   sy += 24;
   ObjLabel("lbl_tot",  x+8,  sy, "Total Trades:", CLR_GRAY, 8);
   ObjLabel("val_tot",  x+135,sy, "0",            CLR_WHITE, 8);
   sy += 16;
   ObjLabel("lbl_wr",   x+8,  sy, "Win Rate:",     CLR_GRAY, 8);
   ObjLabel("val_wr",   x+135,sy, "--",           CLR_WHITE, 8);
   sy += 16;
   ObjLabel("lbl_pl",   x+8,  sy, "Total P/L:",    CLR_GRAY, 8);
   ObjLabel("val_pl",   x+135,sy, "$0.00",         CLR_WHITE, 8);

   // Risk Bar
   sy += 20;
   ObjRect("risk_bg", x+10, sy, w-20, 8, C'40,30,30');
   ObjRect("risk_fg", x+10, sy, 0,    8, CLR_GREEN);

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
   UpdateLabel("val_dd",  DoubleToString(dd,1)+"%", dd > InpMaxDailyLoss*0.7 ? CLR_RED : CLR_YELLOW);
   UpdateLabel("val_trd", IntegerToString(dailyTradeCount)+"/"+IntegerToString((int)InpMaxDailyTrades), 
               dailyTradeCount >= InpMaxDailyTrades ? CLR_RED : CLR_WHITE);

   // Structure
   color structClr = (marketStructure == STRUCT_BULLISH) ? CLR_GREEN : 
                     (marketStructure == STRUCT_BEARISH) ? CLR_RED : CLR_YELLOW;
   UpdateLabel("val_struct", StructureName(marketStructure), structClr);

   double adxVal, plusDI, minusDI;
   GetADX(adxVal, plusDI, minusDI);
   UpdateLabel("val_adx", DoubleToString(adxVal,1) + (adxVal >= InpADXMin ? " ✓" : " ✗"), 
               adxVal >= InpADXMin ? CLR_GREEN : CLR_RED);

   double rsi = GetRSI(1);
   UpdateLabel("val_rsi", DoubleToString(rsi,1), 
               (rsi > InpRSIOB || rsi < InpRSIOS) ? CLR_RED : CLR_GREEN);

   bool volOK = VolumeOK();
   UpdateLabel("val_vol", volOK ? "OK ✓" : "LOW ✗", volOK ? CLR_GREEN : CLR_RED);

   // Trade Status
   UpdateLabel("val_stat", botStatus, statusClr);
   UpdateLabel("val_sig",  lastSignal, CLR_WHITE);

   double pnl = GetPositionProfit();
   color pnlClr = pnl > 0 ? CLR_GREEN : (pnl < 0 ? CLR_RED : CLR_GRAY);
   UpdateLabel("val_pnl", DoubleToString(pnl,2)+" "+cur, pnlClr);

   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   double spreadDisp = (symType == SYM_FOREX) ? (double)spread/10.0 : (double)spread;
   bool spreadOK = SpreadOK();
   UpdateLabel("val_spr", DoubleToString(spreadDisp,1) + (spreadOK ? " ✓" : " ✗"), 
               spreadOK ? CLR_GREEN : CLR_RED);

   // Statistics
   double wr = statTotal > 0 ? (double)statWins/statTotal*100.0 : 0;
   UpdateLabel("val_tot", IntegerToString(statTotal), CLR_WHITE);
   UpdateLabel("val_wr",  DoubleToString(wr,1)+"%", wr>=55?CLR_GREEN:CLR_RED);
   UpdateLabel("val_pl",  DoubleToString(statProfit,2)+" "+cur, statProfit>=0?CLR_GREEN:CLR_RED);

   // Risk bar
   double riskPct = MathMin(dd / InpMaxDailyLoss * 100.0, 100.0);
   int barW = (int)((260-20) * riskPct / 100.0);
   color barClr = riskPct < 50 ? CLR_GREEN : (riskPct < 80 ? CLR_YELLOW : CLR_RED);

   if(ObjectFind(0, PFX+"risk_fg") >= 0)
   {
      ObjectSetInteger(0, PFX+"risk_fg", OBJPROP_XSIZE, barW);
      ObjectSetInteger(0, PFX+"risk_fg", OBJPROP_BGCOLOR, barClr);
   }

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
   entryTF = BotTFtoPeriod(InpEntryTF);
   structureTF = BotTFtoPeriod(InpStructureTF);
   SymInfo.Name(_Symbol);

   // Configure trade object
   Trade.SetExpertMagicNumber(MAGIC);
   Trade.SetDeviationInPoints(InpMaxSlippage);
   Trade.SetTypeFilling(ORDER_FILLING_IOC);
   Trade.SetAsyncMode(false);

   if(!InitIndicators()) 
   {
      Alert("Failed to initialize indicators!");
      return INIT_FAILED;
   }

   // Initialize risk tracking
   startEquity = AcctInfo.Equity();
   dailyHighEquity = startEquity;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   lastTradeDay = dt.day;

   // Initial structure analysis
   UpdateMarketStructure();

   Print("═══════════════════════════════════════");
   Print("  ScalpMaster Pro v3.0 Initialized");
   Print("═══════════════════════════════════════");
   Print("Symbol: ", _Symbol, " [", symType==SYM_GOLD?"GOLD":(symType==SYM_FOREX?"FOREX":(symType==SYM_INDICES?"INDICES":"OTHER")), "]");
   Print("Entry TF: ", TFName(InpEntryTF), " | Structure TF: ", TFName(InpStructureTF));
   Print("MA: ", InpMAFastPeriod, "/", InpMASlowPeriod, " | ATR: ", InpATRPeriod);
   Print("SuperTrend: ", InpSTPeriod, "x", InpSTMultiplier);
   Print("ADX: ", InpADXPeriod, " (min: ", InpADXMin, ")");
   Print("RSI: ", InpRSIPeriod, " | Volume: ", InpUseVolume?"ON":"OFF");
   Print("Structure Lookback: ", InpStructureLookback, " bars (", InpStructureLookback * PeriodSeconds(structureTF) / 3600.0, " hours)");
   Print("Risk/Trade: ", InpRiskPercent, "% | Max Daily Loss: ", InpMaxDailyLoss, "%");
   Print("Max Daily Trades: ", InpMaxDailyTrades);
   Print("═══════════════════════════════════════");

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
   IndicatorRelease(hMAFast);
   IndicatorRelease(hMASlow);
   if(hSuperTrend != INVALID_HANDLE) IndicatorRelease(hSuperTrend);
   IndicatorRelease(hADX);
   IndicatorRelease(hRSI);
   IndicatorRelease(hATR);
   DestroyPanel();

   Print("ScalpMaster Pro v3.0 terminated. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick()
{
   // Daily risk check
   CheckDailyRisk();

   // Panel update
   if(InpShowPanel) UpdatePanel();

   // Trailing stop management (every tick for precision)
   if(botState == STATE_IN_TRADE)
      ManageTrailingStop();

   // Main logic on new bar only
   if(!IsNewBar()) return;

   ProcessBar(barCounter);
}
//+------------------------------------------------------------------+
