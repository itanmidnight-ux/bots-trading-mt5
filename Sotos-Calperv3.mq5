//+------------------------------------------------------------------+
//|                                              Sotos-Calper.mq5    |
//|                        RSI Ultra-Short Scalping Bot  v2.21 FINAL  |
//|                                     Timeframe: M1 | Any Market  |
//+------------------------------------------------------------------+
#property copyright   "Sotos-Calper"
#property version     "2.21"
#property description "RSI Ultra-Short Scalping - M1 | Fixed RSI extremes TP"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\AccountInfo.mqh>

//+------------------------------------------------------------------+
//|  INPUTS                                                          |
//+------------------------------------------------------------------+

input group "===== RSI ====="
// WARNING: Period=1 is ultra-reactive. Consider 2-3 to reduce noise.
input int    inp_RSI_Period = 1;
input double inp_RSI_Buy   = 8.9;
input double inp_RSI_Sell  = 91.0;

input group "===== TP Levels (RSI — strictly descending: TP1>TP2>TP3>TP4>TP5) ====="
input double inp_TP1 = 78.0;
input double inp_TP2 = 63.0;
input double inp_TP3 = 50.0;
input double inp_TP4 = 36.0;
input double inp_TP5 = 23.0;

input group "===== Bollinger Bands — Indicator Window (HLCC/4) ====="
// WARNING: Dev=0.111 produces very tight bands; filter fires on almost every bar.
// Increase to 0.5-1.0 for stronger filtering.
input int    inp_BB_Period = 14;
input double inp_BB_Dev    = 0.111;

input group "===== MACD (HLCC/4) ====="
// MACD(12,26,9) lags 26 bars on M1. Can conflict with RSI(1).
// Disable inp_UseMACDFilter if too few trades are generated.
input bool inp_UseMACDFilter = true;  // Enable MACD as entry filter
input int  inp_MACD_Fast     = 12;
input int  inp_MACD_Slow     = 26;
input int  inp_MACD_Sig      = 9;

input group "===== Parabolic SAR ====="
input double inp_SAR_Step = 0.02;
input double inp_SAR_Max  = 0.2;

input group "===== Stochastic Oscillator (Always Active) ====="
// BUY : %K crosses %D upward   from below 20
// SELL: %K crosses %D downward from above 80
input int inp_Stoch_K    = 5;
input int inp_Stoch_D    = 3;
input int inp_Stoch_Slow = 3;
input int inp_Stoch_Scan = 5;

input group "===== MA Cross Mode (Default: OFF) ====="
input bool inp_UseMACross  = false;
input int  inp_MA_Fast     = 5;
input int  inp_MA_Slow     = 20;
input int  inp_CrossExpiry = 20;

input group "===== ZigZag Direction Filter ====="
input bool inp_UseZigZag = true;
input int  inp_ZZ_Depth  = 5;
input int  inp_ZZ_Dev    = 5;
input int  inp_ZZ_Back   = 3;

input group "===== Stop Loss ====="
input double inp_SL_Points    = 0;      // Fixed SL in points (0=disabled)
input bool   inp_UseATR_SL    = false;  // ATR-based dynamic SL (overrides fixed)
input int    inp_ATR_Period    = 14;     // ATR period
input double inp_ATR_Multi     = 1.5;   // ATR multiplier

input group "===== Trade Management ====="
input double inp_LotSize             = 0.01;
input int    inp_Deviation           = 20;
input double inp_MaxSpread           = 0;      // Max spread points (0=disabled)
input int    inp_MinBarsBetweenTrades= 3;      // Anti-overtrading cooldown (0=disabled)
input int    inp_WarmupBars          = 50;
input bool   inp_DebugLog            = false;
input ulong  inp_Magic               = 202501;
input bool   inp_CloseAtRSIExtremes  = true;   // Fixed TP: BUY closes at RSI_Sell, SELL closes at RSI_Buy

//+------------------------------------------------------------------+
//|  GLOBALS                                                         |
//+------------------------------------------------------------------+

CTrade       g_trade;
CAccountInfo g_account;

int g_rsiH    = INVALID_HANDLE;
int g_bbIndH  = INVALID_HANDLE;
int g_macdH   = INVALID_HANDLE;
int g_sarH    = INVALID_HANDLE;
int g_stochH  = INVALID_HANDLE;
int g_atrH    = INVALID_HANDLE;
int g_maFastH = INVALID_HANDLE;
int g_maSlowH = INVALID_HANDLE;
int g_zzH     = INVALID_HANDLE;

double g_tpSell[5];
double g_tpBuy[5];

struct PositionTrack { ulong ticket; int dir; int tpLevel; };
PositionTrack g_pos[];

int    g_pendingCross    = 0;
int    g_pendingCrossBar = 0;
bool   g_inTP            = false;
double g_cachedEquity    = 0.0;
int    g_lastTradeBars   = 0;    // Bar count when last trade was opened

//+------------------------------------------------------------------+
//|  HELPER: Release handle and reset to INVALID_HANDLE              |
//+------------------------------------------------------------------+
void ReleaseH(int &h) {
   if(h != INVALID_HANDLE) { IndicatorRelease(h); h = INVALID_HANDLE; }
}

//+------------------------------------------------------------------+
//|  HELPER: Optional-filter gate                                    |
//|  If filter disabled, gate passes automatically (returns true)    |
//+------------------------------------------------------------------+
bool FilterOK(int val, int expected, bool filterEnabled) {
   return (!filterEnabled || val == expected);
}

//+------------------------------------------------------------------+
//|  HELPER: Auto-detect broker filling mode                         |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_FILLING FillingMode() {
   uint m = (uint)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if(m & SYMBOL_FILLING_FOK) return ORDER_FILLING_FOK;
   if(m & SYMBOL_FILLING_IOC) return ORDER_FILLING_IOC;
   return ORDER_FILLING_RETURN;
}

//+------------------------------------------------------------------+
//|  OnInit                                                          |
//+------------------------------------------------------------------+
int OnInit() {
   if(Period() != PERIOD_M1) {
      Print("Sotos-Calper: Must run on M1."); return INIT_PARAMETERS_INCORRECT;
   }
   if(inp_RSI_Buy >= inp_RSI_Sell) {
      Print("Sotos-Calper: RSI_Buy must be < RSI_Sell."); return INIT_PARAMETERS_INCORRECT;
   }
   if(inp_UseMACross && inp_MA_Fast >= inp_MA_Slow) {
      Print("Sotos-Calper: MA_Fast must be < MA_Slow."); return INIT_PARAMETERS_INCORRECT;
   }
   double lotMin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double lotMax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(inp_LotSize < lotMin || inp_LotSize > lotMax) {
      PrintFormat("Sotos-Calper: LotSize %.3f outside [%.3f,%.3f].",inp_LotSize,lotMin,lotMax);
      return INIT_PARAMETERS_INCORRECT;
   }

   //--- TP order validation
   double tp[5] = {inp_TP1,inp_TP2,inp_TP3,inp_TP4,inp_TP5};
   for(int i = 0; i < 4; i++) {
      if(tp[i] <= tp[i+1]) {
         PrintFormat("Sotos-Calper: TP%d(%.1f) must be > TP%d(%.1f).",i+1,tp[i],i+2,tp[i+1]);
         return INIT_PARAMETERS_INCORRECT;
      }
   }

   //--- Risk warnings (non-blocking)
   if(inp_RSI_Period == 1)
      Print("Sotos-Calper WARN: RSI Period=1 is ultra-reactive. High false-signal risk on M1.");
   if(inp_BB_Dev < 0.3)
      PrintFormat("Sotos-Calper WARN: BB Dev=%.3f is very tight. Filter will pass on almost every bar.", inp_BB_Dev);
   if(!inp_UseMACDFilter)
      Print("Sotos-Calper INFO: MACD filter disabled. RSI(1)/MACD(26) conflict bypassed.");
   if(inp_SL_Points == 0 && !inp_UseATR_SL)
      Print("Sotos-Calper WARN: No Stop Loss configured. High drawdown risk.");

   g_trade.SetExpertMagicNumber(inp_Magic);
   g_trade.SetDeviationInPoints(inp_Deviation);
   g_trade.SetTypeFilling(FillingMode());

   g_tpSell[0]=inp_TP1; g_tpSell[1]=inp_TP2; g_tpSell[2]=inp_TP3;
   g_tpSell[3]=inp_TP4; g_tpSell[4]=inp_TP5;
   g_tpBuy[0] =inp_TP5; g_tpBuy[1] =inp_TP4; g_tpBuy[2] =inp_TP3;
   g_tpBuy[3] =inp_TP2; g_tpBuy[4] =inp_TP1;

   g_rsiH   = iRSI(_Symbol, PERIOD_M1, inp_RSI_Period, PRICE_WEIGHTED);
   g_bbIndH = iBands(_Symbol, PERIOD_M1, inp_BB_Period, 0, inp_BB_Dev, PRICE_WEIGHTED);
   g_macdH  = iMACD(_Symbol, PERIOD_M1, inp_MACD_Fast, inp_MACD_Slow, inp_MACD_Sig, PRICE_WEIGHTED);
   g_sarH   = iSAR(_Symbol, PERIOD_M1, inp_SAR_Step, inp_SAR_Max);
   g_stochH = iStochastic(_Symbol, PERIOD_M1, inp_Stoch_K, inp_Stoch_D,
                           inp_Stoch_Slow, MODE_SMA, STO_LOWHIGH);
   g_atrH   = iATR(_Symbol, PERIOD_M1, inp_ATR_Period);

   if(g_rsiH  ==INVALID_HANDLE || g_bbIndH==INVALID_HANDLE ||
      g_macdH ==INVALID_HANDLE || g_sarH  ==INVALID_HANDLE ||
      g_stochH==INVALID_HANDLE || g_atrH  ==INVALID_HANDLE) {
      PrintFormat("Sotos-Calper: Core handle failed. Err:%d", GetLastError());
      return INIT_FAILED;
   }

   if(inp_UseMACross) {
      g_maFastH = iMA(_Symbol, PERIOD_M1, inp_MA_Fast, 0, MODE_EMA, PRICE_CLOSE);
      g_maSlowH = iMA(_Symbol, PERIOD_M1, inp_MA_Slow, 0, MODE_EMA, PRICE_CLOSE);
      if(g_maFastH==INVALID_HANDLE || g_maSlowH==INVALID_HANDLE) {
         PrintFormat("Sotos-Calper: MA handle failed. Err:%d", GetLastError()); return INIT_FAILED;
      }
   }

   if(inp_UseZigZag) {
      g_zzH = iCustom(_Symbol, PERIOD_M1, "Examples\\ZigZag", inp_ZZ_Depth, inp_ZZ_Dev, inp_ZZ_Back);
      if(g_zzH == INVALID_HANDLE) {
         PrintFormat("Sotos-Calper: ZigZag failed. Err:%d | Compile Examples\\ZigZag.mq5.", GetLastError());
         return INIT_FAILED;
      }
   }

   g_cachedEquity = g_account.Equity();

   PrintFormat("Sotos-Calper v2.21 | %s | Mode:%s | MACD:%s | ZZ:%s | ATR_SL:%s | ExtremeTP:%s | Lot:%.2f",
               _Symbol,
               inp_UseMACross    ? "MACross" : "Default",
               inp_UseMACDFilter ? "ON"      : "OFF",
               inp_UseZigZag     ? "ON"      : "OFF",
               inp_UseATR_SL     ? "ON"      : "OFF",
               inp_CloseAtRSIExtremes ? "ON" : "OFF",
               inp_LotSize);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//|  OnDeinit                                                        |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   ReleaseH(g_rsiH);   ReleaseH(g_bbIndH); ReleaseH(g_macdH);
   ReleaseH(g_sarH);   ReleaseH(g_stochH); ReleaseH(g_atrH);
   ReleaseH(g_maFastH);ReleaseH(g_maSlowH);ReleaseH(g_zzH);
   ArrayFree(g_pos);
}

//+------------------------------------------------------------------+
//|  HELPER: Safe CopyBuffer                                         |
//+------------------------------------------------------------------+
bool SafeCopy(int handle, int buf, int count, double &arr[]) {
   ArraySetAsSeries(arr, true);
   return (CopyBuffer(handle, buf, 0, count, arr) == count);
}

//+------------------------------------------------------------------+
//|  HELPER: HLCC/4                                                  |
//+------------------------------------------------------------------+
double HLCC4(int shift) {
   double c = iClose(_Symbol, PERIOD_M1, shift);
   return (iHigh(_Symbol,PERIOD_M1,shift) + iLow(_Symbol,PERIOD_M1,shift) + c + c) / 4.0;
}

//+------------------------------------------------------------------+
//|  HELPER: Max trades by equity tier                               |
//+------------------------------------------------------------------+
int GetMaxTrades() {
   if(g_cachedEquity <  40.0) return 1;
   if(g_cachedEquity <  70.0) return 2;
   if(g_cachedEquity < 130.0) return 3;
   return 4;
}

//+------------------------------------------------------------------+
//|  HELPER: Single-pass buy/sell count                              |
//+------------------------------------------------------------------+
void CountBuySell(int &nBuy, int &nSell) {
   nBuy = nSell = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--) {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != inp_Magic) continue;
      ENUM_POSITION_TYPE pt = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if(pt == POSITION_TYPE_BUY)  nBuy++;
      if(pt == POSITION_TYPE_SELL) nSell++;
   }
}

//+------------------------------------------------------------------+
//|  HELPER: Calculate already-reached RSI TP level                  |
//|  Used when positions are restored/opened so no reached TP is lost |
//+------------------------------------------------------------------+
int ReachedTPLevel(int dir, double rsiLive) {
   int level = 0;
   if(dir == -1) {
      for(int t = 0; t < 5; t++) {
         if(rsiLive < g_tpSell[t]) level = t + 1; else break;
      }
   } else if(dir == 1) {
      for(int t = 0; t < 5; t++) {
         if(rsiLive > g_tpBuy[t]) level = t + 1; else break;
      }
   }
   return level;
}

//+------------------------------------------------------------------+
//|  HELPER: Sync tracking array (blocked during RunTPSystem)        |
//+------------------------------------------------------------------+
void SyncPositionArray() {
   if(g_inTP || ArraySize(g_pos) == 0) return;
   PositionTrack tmp[];
   int sz = ArraySize(g_pos), newSz = 0;
   ArrayResize(tmp, sz);
   for(int i = 0; i < sz; i++)
      if(PositionSelectByTicket(g_pos[i].ticket))
         tmp[newSz++] = g_pos[i];
   ArrayResize(g_pos, newSz);
   for(int i = 0; i < newSz; i++) g_pos[i] = tmp[i];
}

//+------------------------------------------------------------------+
//|  HELPER: Register position — duplicate-safe                      |
//+------------------------------------------------------------------+
void RegisterPosition(ulong ticket, int dir, double rsiLive) {
   for(int i = 0; i < ArraySize(g_pos); i++) {
      if(g_pos[i].ticket == ticket) {
         int reached = ReachedTPLevel(dir, rsiLive);
         g_pos[i].dir = dir;
         if(reached > g_pos[i].tpLevel) g_pos[i].tpLevel = reached;
         return;
      }
   }
   int sz = ArraySize(g_pos);
   ArrayResize(g_pos, sz+1);
   g_pos[sz].ticket  = ticket;
   g_pos[sz].dir     = dir;
   g_pos[sz].tpLevel = ReachedTPLevel(dir, rsiLive);
}

//+------------------------------------------------------------------+
//|  HELPER: Ensure every EA position is tracked by real position ID |
//|  This protects TP closing after restarts and broker ticket changes|
//+------------------------------------------------------------------+
void EnsureTrackedPositions(double rsiLive) {
   SyncPositionArray();
   for(int i = PositionsTotal()-1; i >= 0; i--) {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != inp_Magic) continue;
      ENUM_POSITION_TYPE pt = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      int dir = (pt == POSITION_TYPE_BUY) ? 1 : (pt == POSITION_TYPE_SELL ? -1 : 0);
      if(dir != 0) RegisterPosition(tk, dir, rsiLive);
   }
}

//+------------------------------------------------------------------+
//|  INDICATOR: BB direction (indicator window, HLCC/4 vs bands)     |
//|  NOTE: Dev=0.111 → bands very tight → nearly always fires.       |
//|  Increase BB_Dev for stronger filtering if needed.               |
//+------------------------------------------------------------------+
int GetBBDir() {
   double upper[], lower[];
   if(!SafeCopy(g_bbIndH, 1, 3, upper)) return 0;
   if(!SafeCopy(g_bbIndH, 2, 3, lower)) return 0;
   double p = HLCC4(1);
   if(p <= 0.0)      return 0;
   if(p >= upper[1]) return -1;
   if(p <= lower[1]) return  1;
   return 0;
}

//+------------------------------------------------------------------+
//|  INDICATOR: MACD direction                                       |
//|  NOTE: With RSI(1) vs MACD(26): 26-bar lag can block entries.    |
//|  Disable inp_UseMACDFilter if trade frequency is too low.        |
//+------------------------------------------------------------------+
int GetMACDDir() {
   double ml[], sl[];
   if(!SafeCopy(g_macdH, 0, 3, ml)) return 0;
   if(!SafeCopy(g_macdH, 1, 3, sl)) return 0;
   if(ml[1] > sl[1]) return  1;
   if(ml[1] < sl[1]) return -1;
   return 0;
}

//+------------------------------------------------------------------+
//|  INDICATOR: Parabolic SAR direction                              |
//+------------------------------------------------------------------+
int GetSARDir() {
   double sar[];
   if(!SafeCopy(g_sarH, 0, 3, sar)) return 0;
   double c = iClose(_Symbol, PERIOD_M1, 1);
   if(c <= 0.0 || sar[1] <= 0.0) return 0;
   if(sar[1] < c) return  1;
   if(sar[1] > c) return -1;
   return 0;
}

//+------------------------------------------------------------------+
//|  INDICATOR: Stochastic — %K cross %D from extreme zone           |
//+------------------------------------------------------------------+
int GetStochSignal() {
   int need = inp_Stoch_Scan + 3;
   double k[], d[];
   if(!SafeCopy(g_stochH, 0, need, k)) return 0;
   if(!SafeCopy(g_stochH, 1, need, d)) return 0;
   for(int i = 1; i <= inp_Stoch_Scan; i++) {
      bool up   = (k[i] > d[i] && k[i+1] <= d[i+1]);
      bool down = (k[i] < d[i] && k[i+1] >= d[i+1]);
      if(up   && k[i+1] < 20.0) return  1;
      if(down && k[i+1] > 80.0) return -1;
   }
   return 0;
}

//+------------------------------------------------------------------+
//|  INDICATOR: ZigZag direction — repaint-safe (buf 1=hi, 2=lo)     |
//+------------------------------------------------------------------+
int GetZZDir() {
   if(!inp_UseZigZag || g_zzH == INVALID_HANDLE) return 0;
   int safeStart = inp_ZZ_Depth + 2;
   int available = Bars(_Symbol, PERIOD_M1) - safeStart;
   if(available <= 0) return 0;
   int scanBars = MathMin(500, available);
   double zzHi[], zzLo[];
   ArraySetAsSeries(zzHi, true);
   ArraySetAsSeries(zzLo, true);
   if(CopyBuffer(g_zzH, 1, safeStart, scanBars, zzHi) < 1) return 0;
   if(CopyBuffer(g_zzH, 2, safeStart, scanBars, zzLo) < 1) return 0;
   if(inp_DebugLog && scanBars < 500)
      PrintFormat("Sotos-Calper | ZZ: limited history, scanning %d bars", scanBars);
   int lastHi = -1, lastLo = -1;
   for(int i = 0; i < scanBars && (lastHi==-1 || lastLo==-1); i++) {
      if(lastHi == -1 && zzHi[i] != 0.0) lastHi = i;
      if(lastLo == -1 && zzLo[i] != 0.0) lastLo = i;
   }
   if(lastHi == -1 && lastLo == -1) return 0;
   if(lastHi == -1) return  1;
   if(lastLo == -1) return -1;
   return (lastHi < lastLo) ? -1 : 1;
}

//+------------------------------------------------------------------+
//|  INDICATOR: MA Cross                                             |
//+------------------------------------------------------------------+
int GetMACross() {
   if(!inp_UseMACross) return 0;
   double fast[], slow[];
   if(!SafeCopy(g_maFastH, 0, 3, fast)) return 0;
   if(!SafeCopy(g_maSlowH, 0, 3, slow)) return 0;
   if(fast[1] > slow[1] && fast[2] <= slow[2]) return  1;
   if(fast[1] < slow[1] && fast[2] >= slow[2]) return -1;
   return 0;
}

//+------------------------------------------------------------------+
//|  HELPER: Compute Stop Loss                                       |
//|  ATR-based (dynamic) takes priority over fixed points            |
//+------------------------------------------------------------------+
double ComputeSL(int dir, double refPrice) {
   if(inp_UseATR_SL) {
      double atr[];
      if(SafeCopy(g_atrH, 0, 2, atr) && atr[1] > 0.0) {
         double dist = atr[1] * inp_ATR_Multi;
         return (dir == 1) ? refPrice - dist : refPrice + dist;
      }
   }
   if(inp_SL_Points > 0)
      return (dir == 1) ? refPrice - inp_SL_Points*_Point
                        : refPrice + inp_SL_Points*_Point;
   return 0.0;
}

//+------------------------------------------------------------------+
//|  TRADE: Open N market orders                                     |
//+------------------------------------------------------------------+
void OpenTrades(int dir, int count, int totalBars) {
   if(count <= 0) return;

   // Spread guard
   if(inp_MaxSpread > 0) {
      double sp = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
      if(sp > inp_MaxSpread) {
         if(inp_DebugLog) PrintFormat("Sotos-Calper | SKIP spread %.1f > %.1f", sp, inp_MaxSpread);
         return;
      }
   }

   double ref = (dir == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                            : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = ComputeSL(dir, ref);

   for(int i = 0; i < count; i++) {
      bool ok = (dir==1) ? g_trade.Buy(inp_LotSize, _Symbol, 0, sl, 0.0, "Sotos-Calper")
                         : g_trade.Sell(inp_LotSize, _Symbol, 0, sl, 0.0, "Sotos-Calper");
      if(ok) {
         double rsiNow[];
         if(SafeCopy(g_rsiH, 0, 2, rsiNow))
            EnsureTrackedPositions(rsiNow[0]);
         g_lastTradeBars = totalBars;   // Record bar of last open for cooldown
         PrintFormat("Sotos-Calper | %s | Order:%llu | Deal:%llu | Fill:%.5f | Lot:%.2f | SL:%.5f",
                     dir==1?"BUY":"SELL", g_trade.ResultOrder(), g_trade.ResultDeal(),
                     g_trade.ResultPrice(), inp_LotSize, sl);
      } else {
         PrintFormat("Sotos-Calper | OPEN FAILED | %s | Err:%d | Ret:%u",
                     dir==1?"BUY":"SELL", GetLastError(), g_trade.ResultRetcode());
      }
   }
}

//+------------------------------------------------------------------+
//|  TP SYSTEM: RSI trailing TP — every tick on live RSI (bar[0])    |
//|  SELL: strict < advance | >= close   BUY: strict > advance | <=  |
//+------------------------------------------------------------------+
void RunTPSystem(double rsiLive) {
   EnsureTrackedPositions(rsiLive);
   g_inTP = true;
   for(int i = 0; i < ArraySize(g_pos); i++) {
      if(!PositionSelectByTicket(g_pos[i].ticket)) continue;
      int  dir   = g_pos[i].dir;
      int &level = g_pos[i].tpLevel;
      double profit = PositionGetDouble(POSITION_PROFIT);

      // Fixed extreme TP requested: if momentum reaches the opposite RSI edge,
      // close immediately instead of waiting for a rebound that can give back profit.
      if(inp_CloseAtRSIExtremes) {
         if(dir == -1 && rsiLive <= inp_RSI_Buy) {
            PrintFormat("Sotos-Calper | SELL FIXED EXTREME TP | RSI:%.2f Target:%.1f Tk:%llu Profit:%.2f",
                        rsiLive, inp_RSI_Buy, g_pos[i].ticket, profit);
            g_trade.PositionClose(g_pos[i].ticket);
            continue;
         }
         if(dir == 1 && rsiLive >= inp_RSI_Sell) {
            PrintFormat("Sotos-Calper | BUY  FIXED EXTREME TP | RSI:%.2f Target:%.1f Tk:%llu Profit:%.2f",
                        rsiLive, inp_RSI_Sell, g_pos[i].ticket, profit);
            g_trade.PositionClose(g_pos[i].ticket);
            continue;
         }
      }

      if(dir == -1) {
         for(int t = level; t < 5; t++) {
            if(rsiLive < g_tpSell[t]) level = t + 1; else break;
         }
         if(level > 0 && rsiLive >= g_tpSell[level-1]) {
            PrintFormat("Sotos-Calper | SELL TP | RSI:%.2f Ref:%.1f Tk:%llu Profit:%.2f",
                        rsiLive, g_tpSell[level-1], g_pos[i].ticket, profit);
            g_trade.PositionClose(g_pos[i].ticket);
         }
      } else if(dir == 1) {
         for(int t = level; t < 5; t++) {
            if(rsiLive > g_tpBuy[t]) level = t + 1; else break;
         }
         if(level > 0 && rsiLive <= g_tpBuy[level-1]) {
            PrintFormat("Sotos-Calper | BUY  TP | RSI:%.2f Ref:%.1f Tk:%llu Profit:%.2f",
                        rsiLive, g_tpBuy[level-1], g_pos[i].ticket, profit);
            g_trade.PositionClose(g_pos[i].ticket);
         }
      }
   }
   g_inTP = false;
}

//+------------------------------------------------------------------+
//|  ENTRY: Default Mode                                             |
//|  FilterOK() makes MACD optional without changing core logic      |
//|  Cooldown: skips entry if too few bars since last trade opened    |
//+------------------------------------------------------------------+
void CheckEntryDefault(double rsi, int bb, int macd, int sar,
                        int stoch, int zz, int nBuy, int nSell, int totalBars) {
   if(nBuy > 0 || nSell > 0) return;
   if(inp_MinBarsBetweenTrades > 0 &&
      (totalBars - g_lastTradeBars) < inp_MinBarsBetweenTrades) return;

   int maxT = GetMaxTrades();

   if(rsi <= inp_RSI_Buy && bb==1 && FilterOK(macd,1,inp_UseMACDFilter) && sar==1 && stoch==1) {
      if(!inp_UseZigZag || zz == 1) OpenTrades(1, maxT, totalBars);
   } else if(rsi >= inp_RSI_Sell && bb==-1 && FilterOK(macd,-1,inp_UseMACDFilter) && sar==-1 && stoch==-1) {
      if(!inp_UseZigZag || zz == -1) OpenTrades(-1, maxT, totalBars);
   }
}

//+------------------------------------------------------------------+
//|  ENTRY: MA Cross Mode                                            |
//+------------------------------------------------------------------+
void CheckEntryMACross(double rsi, int bb, int macd, int sar,
                        int stoch, int zz, int totalBars, int nBuy, int nSell) {
   int crossNow = GetMACross();
   if(crossNow != 0) { g_pendingCross = crossNow; g_pendingCrossBar = totalBars; }
   if(g_pendingCross == 0) return;

   if(inp_CrossExpiry > 0 && (totalBars - g_pendingCrossBar) > inp_CrossExpiry) {
      if(inp_DebugLog) PrintFormat("Sotos-Calper | Cross EXPIRED Dir:%d Age:%d",
                                   g_pendingCross, totalBars-g_pendingCrossBar);
      g_pendingCross = 0; return;
   }

   if(nBuy > 0 || nSell > 0) return;
   if(inp_MinBarsBetweenTrades > 0 &&
      (totalBars - g_lastTradeBars) < inp_MinBarsBetweenTrades) return;

   int maxT = GetMaxTrades();

   if(g_pendingCross==1 && rsi<=inp_RSI_Buy && bb==1 &&
      FilterOK(macd,1,inp_UseMACDFilter) && sar==1 && stoch==1) {
      if(!inp_UseZigZag || zz==1) { OpenTrades(1,maxT,totalBars); g_pendingCross=0; }
   } else if(g_pendingCross==-1 && rsi>=inp_RSI_Sell && bb==-1 &&
             FilterOK(macd,-1,inp_UseMACDFilter) && sar==-1 && stoch==-1) {
      if(!inp_UseZigZag || zz==-1) { OpenTrades(-1,maxT,totalBars); g_pendingCross=0; }
   }
}

//+------------------------------------------------------------------+
//|  OnTick                                                          |
//+------------------------------------------------------------------+
void OnTick() {
   double rsiLive[];
   if(!SafeCopy(g_rsiH, 0, 2, rsiLive)) return;
   RunTPSystem(rsiLive[0]);
   SyncPositionArray();

   static datetime s_lastBar = 0;
   datetime curBar = iTime(_Symbol, PERIOD_M1, 0);
   if(curBar == s_lastBar || curBar == 0) return;
   s_lastBar = curBar;

   g_cachedEquity = g_account.Equity();
   int totalBars  = Bars(_Symbol, PERIOD_M1);
   int minBars    = MathMax(inp_WarmupBars, inp_MACD_Slow + inp_MACD_Sig + 5);
   if(totalBars < minBars) {
      if(inp_DebugLog) PrintFormat("Sotos-Calper | WARMUP %d/%d", totalBars, minBars);
      return;
   }

   double rsiClosed[];
   if(!SafeCopy(g_rsiH, 0, 3, rsiClosed)) return;
   double rsi = rsiClosed[1];

   int bb    = GetBBDir();
   int macd  = GetMACDDir();
   int sar   = GetSARDir();
   int stoch = GetStochSignal();
   int zz    = GetZZDir();

   int nBuy, nSell;
   CountBuySell(nBuy, nSell);

   if(inp_DebugLog)
      PrintFormat("Sotos-Calper | RSI:%.2f BB:%s MACD:%s SAR:%s Stoch:%s ZZ:%s Pos:%d Cooldown:%d",
                  rsi,
                  bb   ==1?"B+":bb   ==-1?"B-":"--",
                  macd ==1?"B+":macd ==-1?"B-":"--",
                  sar  ==1?"B+":sar  ==-1?"B-":"--",
                  stoch==1?"B+":stoch==-1?"B-":"--",
                  zz   ==1?"Up":zz   ==-1?"Dn":"--",
                  nBuy+nSell,
                  MathMax(0, inp_MinBarsBetweenTrades-(totalBars-g_lastTradeBars)));

   if(!inp_UseMACross)
      CheckEntryDefault(rsi, bb, macd, sar, stoch, zz, nBuy, nSell, totalBars);
   else
      CheckEntryMACross(rsi, bb, macd, sar, stoch, zz, totalBars, nBuy, nSell);
}

//+------------------------------------------------------------------+
//|  OnTradeTransaction                                              |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest     &request,
                        const MqlTradeResult      &result) {
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
      SyncPositionArray();
}

//+------------------------------------------------------------------+
//|  END — SOTOS-CALPER v2.21 FINAL                                   |
//+------------------------------------------------------------------+
