//+------------------------------------------------------------------+
//|                     ScalpMaster Pro v3.4                        |
//|  GMMA + SAR + ADX + Pivot Points + H1 SAR/MACD — M1/M15/H1    |
//|      Metals (XAUUSD, XPTUSD) + Forex — MT5                     |
//+------------------------------------------------------------------+
#property copyright "ScalpMaster Pro"
#property version   "3.40"
#property description "M1 Scalper | M15 Grid | H1 SAR+MACD — multi-TF intelligent bot"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//+------------------------------------------------------------------+
//| ENUMS                                                            |
//+------------------------------------------------------------------+
enum ENUM_BOT_TF
{
   BTF_M1  = 1,   // 1 Minute  (Scalper)
   BTF_M15 = 15,  // 15 Minutes (Grid)
   BTF_H1  = 60   // 1 Hour (SAR+MACD strategy)
};

enum ENUM_BOT_STATE
{
   STATE_IDLE,
   STATE_MA_CROSS,    // SMA cross detected (M1/M15 path)
   STATE_MACD_CROSS,  // MACD(Open)+H1SAR cross detected (all TFs)
   STATE_IN_TRADE,
   STATE_WAIT_EMA
};

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+
sinput string          _S0_ = "─────── TIMEFRAME ───────";
input  ENUM_BOT_TF     InpTimeframe   = BTF_M1;        // Operating Timeframe

sinput string          _S1_ = "─────── MA SETTINGS ───────";
input  int             InpMAFast      = 9;             // MA Fast Period (SMA)
input  int             InpMASlow      = 26;            // MA Slow Period (SMA)

sinput string          _S2_ = "─────── EMA SETTINGS ───────";
input  int             InpEMAFast     = 9;             // EMA Fast Period
input  int             InpEMASlow     = 26;            // EMA Slow Period

sinput string          _S3_ = "─────── RSI SETTINGS ───────";
input  bool            InpRSIAuto     = true;          // Auto RSI Period by TF
input  int             InpRSIPeriod   = 14;            // RSI Period (manual)
input  double          InpRSIOB       = 65.0;          // RSI Max for BUY
input  double          InpRSIOS       = 35.0;          // RSI Min for SELL
input  double          InpRSIMinBuy   = 40.0;          // RSI Minimum for BUY
input  double          InpRSIMaxSell  = 60.0;          // RSI Maximum for SELL

sinput string          _S4_ = "─────── MACD FILTER ───────";
input  bool            InpUseMACDFilter = true;        // Enable MACD confirmation
input  int             InpMACDFast      = 12;          // MACD Fast EMA
input  int             InpMACDSlow      = 26;          // MACD Slow EMA
input  int             InpMACDSignal    = 9;           // MACD Signal period

sinput string          _S4B_ = "─────── VOLUME FILTER ───────";
input  bool            InpUseVolFilter  = true;        // Enable volume confirmation
input  int             InpVolPeriod     = 20;          // Volume MA period
input  double          InpVolMult       = 1.2;         // Min ratio current/avg volume

sinput string          _SGMMA_ = "─────── GMMA FILTER ───────";
input  bool            InpUseGMMA        = true;       // Enable GMMA validation
input  int             InpGMMACrossCount = 3;          // Min long EMAs crossed by short (1-6)

sinput string          _SSAR_ = "─────── SAR PARABÓLICO ───────";
input  bool            InpUseSAR         = true;       // Enable SAR direction filter
input  double          InpSARStep        = 0.02;       // SAR Step
input  double          InpSARMax         = 0.2;        // SAR Maximum

sinput string          _SADX_ = "─────── ADX FUERZA TENDENCIA ───────";
input  bool            InpUseADXFilter   = true;       // ADX entry filter (trend exists)
input  int             InpADXPeriod      = 14;         // ADX Period
input  double          InpADXMinLevel    = 20.0;       // Min ADX to enter (>20 = trend)
input  double          InpADXExitLevel   = 28.0;       // ADX level to watch for peak exit

sinput string          _SH1STR_ = "─────── H1 SAR+MACD STRATEGY ───────";
input  bool            InpUseH1Strategy  = true;       // Enable H1 SAR+MACD strategy (all TFs)
input  double          InpH1SARStep      = 0.01;       // H1 SAR Step (slow & reliable)
input  double          InpH1SARMax       = 0.1;        // H1 SAR Maximum
input  int             InpH1WaitBars     = 2;          // Extra bars to wait before H1 entry
input  double          InpH1MinProfit    = 0.50;       // Min USD profit for H1 breakeven

sinput string          _S5_ = "─────── RISK MANAGEMENT ───────";
input  bool            InpAutoLot        = true;       // Auto Lot by Balance
input  double          InpScaleBase      = 15.0;       // Balance ($) where lot scaling starts (<base → 0.01)
input  double          InpScaleStep      = 20.0;       // USD balance per +0.01 lot increment
input  double          InpMinLot         = 0.01;       // Min / Fixed Lot (when AutoLot=false)
input  double          InpMaxLot         = 5.0;        // Max Lot cap (safety)
input  bool            InpUseSL          = true;       // Enable Stop Loss
input  double          InpPivotSLBuffer  = 3.0;        // Buffer pips beyond Pivot level
input  double          InpSLHardCapPips  = 50.0;       // Hard cap SL distance (pips)

sinput string          _S5B_ = "─────── SCALPER (M1) ───────";
input  double          InpScalpTPPips    = 0.0;        // Safety TP pips M1 — 0=off (indicators manage exit)
input  double          InpScalpMinProfit = 0.10;       // USD to trigger breakeven move

sinput string          _S6_ = "─────── GRID TP (M15) ───────";
input  double          InpGridPts     = 15.0;          // Grid Step (points ×10)
input  int             InpGridLevels  = 6;             // Grid Levels
input  double          InpMinProfit   = 0.10;          // Min USD Profit to close
input  int             InpBuyExtra    = 3;             // Extra Wait Bars (BUY)

sinput string          _S7_ = "─────── PANEL ───────";
input  bool            InpShowPanel   = true;          // Show Dashboard
input  int             InpPanelX      = 15;            // Panel X
input  int             InpPanelY      = 30;            // Panel Y

//+------------------------------------------------------------------+
//| GLOBALS                                                          |
//+------------------------------------------------------------------+
CTrade          Trade;
CPositionInfo   PosInfo;
CAccountInfo    AcctInfo;
CSymbolInfo     SymInfo;

int    hMAFast, hMASlow, hEMAFast, hEMASlow, hRSI;
int    hMACD;                  // MACD(Close) on botTF — existing strategy
int    hSAR;                   // Parabolic SAR on botTF
int    hADX;                   // ADX (trend strength)
int    hGMMAShort[6];          // GMMA short group EMAs: 3,5,8,10,12,15
int    hGMMALong[6];           // GMMA long  group EMAs: 30,35,40,45,50,60
int    hSAR_H1     = INVALID_HANDLE; // SAR(0.01,0.1) on H1 — H1 direction for all TFs
int    hMACD_Open  = INVALID_HANDLE; // MACD(Open) on botTF — H1 strategy cross detection
// hM15Fast/hM15Slow kept as INVALID_HANDLE (replaced by SAR)
int    hM15Fast = INVALID_HANDLE, hM15Slow = INVALID_HANDLE;

// Standard Guppy Multiple Moving Average periods (not configurable — industry standard)
const int GMMA_SHORT[6] = {3, 5, 8, 10, 12, 15};
const int GMMA_LONG[6]  = {30, 35, 40, 45, 50, 60};

ENUM_TIMEFRAMES botTF;
ENUM_BOT_STATE  botState     = STATE_IDLE;

datetime        lastBarTime  = 0;
int             barCounter   = 0;

int             maCrossBar   = -1;
bool            maDir        = false;    // true=bullish
int             emaCrossBar  = -1;
int             macdCrossBar = -1;       // bar when MACD(Open)+H1SAR cross was detected
bool            macdCrossDir = false;    // true=bullish MACD cross
bool            emaArrived   = false;
int             entryBar     = -1;
int             tpStartBar   = -1;

bool            isBuy        = false;
double          entryPrice   = 0;
double          openLot      = 0;
double          tpGrid[];
int             gridLevel    = 0;
double          trailSL      = 0;
ulong           posTicket    = 0;
bool            beMoveDone   = false;  // breakeven applied (M1 scalper)

int             statTotal    = 0;
int             statWins     = 0;
double          statProfit   = 0;
string          lastSignal   = "—";
string          botStatus    = "IDLE";
color           statusClr    = C'100,110,130';

// Panel color palette
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
const string PFX       = "SMP_";
const long   MAGIC     = 202501;

//+------------------------------------------------------------------+
//| RSI PERIOD BY TIMEFRAME                                          |
//+------------------------------------------------------------------+
int GetRSIPeriod()
{
   if(!InpRSIAuto) return InpRSIPeriod;
   switch(botTF)
   {
      case PERIOD_M1:  return 7;
      case PERIOD_M15: return 14;
      case PERIOD_H1:  return 14;
      default:         return 14;
   }
}

//+------------------------------------------------------------------+
//| TF ENUM → PERIOD ENUM                                           |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES BotTFtoPeriod(ENUM_BOT_TF tf)
{
   switch(tf)
   {
      case BTF_M1:  return PERIOD_M1;
      case BTF_M15: return PERIOD_M15;
      case BTF_H1:  return PERIOD_H1;
      default:      return PERIOD_M1;
   }
}

string TFName(ENUM_BOT_TF tf)
{
   switch(tf)
   {
      case BTF_M1:  return "M1 (Scalper)";
      case BTF_M15: return "M15 (Grid)";
      case BTF_H1:  return "H1 (SAR+MACD)";
      default:      return "??";
   }
}

//+------------------------------------------------------------------+
//| LOT SIZING                                                       |
//+------------------------------------------------------------------+
double CalcLot()
{
   if(!InpAutoLot) return NormLot(InpMinLot);
   double balance = AcctInfo.Balance();
   if(balance <= 0) return InpMinLot;
   double lot;
   if(balance < InpScaleBase)
      lot = 0.01;                                              // below threshold → minimum lot
   else
      lot = 0.02 + MathFloor((balance - InpScaleBase) / InpScaleStep) * 0.01;  // 0.02 at $15, +0.01 per $20
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
//| PIVOT POINTS — standard pivot from previous D1 candle           |
//+------------------------------------------------------------------+
struct PivotLevels { double P, R1, R2, S1, S2; bool valid; };

PivotLevels GetDailyPivots()
{
   PivotLevels pv;
   pv.valid = false;
   MqlRates daily[];
   ArraySetAsSeries(daily, true);
   if(CopyRates(_Symbol, PERIOD_D1, 1, 1, daily) < 1) return pv;
   double H = daily[0].high;
   double L = daily[0].low;
   double C = daily[0].close;
   pv.P  = (H + L + C) / 3.0;
   pv.R1 = 2*pv.P - L;
   pv.S1 = 2*pv.P - H;
   pv.R2 = pv.P + (H - L);
   pv.S2 = pv.P - (H - L);
   pv.valid = true;
   return pv;
}

//+------------------------------------------------------------------+
//| STOP LOSS — Pivot Point based (S1/S2 for BUY, R1/R2 for SELL)  |
//+------------------------------------------------------------------+
double CalcSL(bool buy, double entry)
{
   if(!InpUseSL) return 0;
   double pt        = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double pip       = pt * 10.0;
   double bufDist   = InpPivotSLBuffer * pip;
   double capDist   = InpSLHardCapPips * pip;
   long   stopsLvl  = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double brokerMin = (stopsLvl + 2) * pt;

   double sl = 0;
   PivotLevels pv = GetDailyPivots();

   if(pv.valid)
   {
      if(buy)
      {
         double slS1 = pv.S1 - bufDist;
         double slS2 = pv.S2 - bufDist;
         // Use S1 if it gives enough distance; otherwise S2; otherwise broker min
         if(entry - slS1 >= brokerMin) sl = slS1;
         else if(entry - slS2 >= brokerMin) sl = slS2;
         else sl = entry - brokerMin - bufDist;
         sl = MathMax(sl, entry - capDist);  // hard cap
      }
      else
      {
         double slR1 = pv.R1 + bufDist;
         double slR2 = pv.R2 + bufDist;
         if(slR1 - entry >= brokerMin) sl = slR1;
         else if(slR2 - entry >= brokerMin) sl = slR2;
         else sl = entry + brokerMin + bufDist;
         sl = MathMin(sl, entry + capDist);  // hard cap
      }
   }
   else
   {
      // Fallback: broker minimum + buffer
      sl = buy ? entry - capDist : entry + capDist;
   }

   return NormalizeDouble(sl, _Digits);
}

//+------------------------------------------------------------------+
//| INIT INDICATORS                                                  |
//+------------------------------------------------------------------+
bool InitIndicators()
{
   // Core MA / EMA / RSI / MACD
   hMAFast  = iMA  (_Symbol, botTF, InpMAFast,  0, MODE_SMA, PRICE_CLOSE);
   hMASlow  = iMA  (_Symbol, botTF, InpMASlow,  0, MODE_SMA, PRICE_CLOSE);
   hEMAFast = iMA  (_Symbol, botTF, InpEMAFast, 0, MODE_EMA, PRICE_CLOSE);
   hEMASlow = iMA  (_Symbol, botTF, InpEMASlow, 0, MODE_EMA, PRICE_CLOSE);
   hRSI     = iRSI (_Symbol, botTF, GetRSIPeriod(), PRICE_CLOSE);
   hMACD    = iMACD(_Symbol, botTF, InpMACDFast, InpMACDSlow, InpMACDSignal, PRICE_CLOSE);

   // SAR — adapts automatically to botTF
   hSAR = iSAR(_Symbol, botTF, InpSARStep, InpSARMax);

   // ADX
   hADX = iADX(_Symbol, botTF, InpADXPeriod);

   // GMMA — 12 EMA handles (6 short group + 6 long group)
   for(int i = 0; i < 6; i++)
   {
      hGMMAShort[i] = iMA(_Symbol, botTF, GMMA_SHORT[i], 0, MODE_EMA, PRICE_CLOSE);
      hGMMALong[i]  = iMA(_Symbol, botTF, GMMA_LONG[i],  0, MODE_EMA, PRICE_CLOSE);
      if(hGMMAShort[i] == INVALID_HANDLE || hGMMALong[i] == INVALID_HANDLE)
      { Alert("ScalpMaster: GMMA handle failed for index ", i); return false; }
   }

   // hM15Fast/hM15Slow are no longer used (replaced by SAR)
   hM15Fast = INVALID_HANDLE;
   hM15Slow = INVALID_HANDLE;

   // H1 SAR — slow params (0.01, 0.1) for H1 direction on all TFs
   hSAR_H1 = iSAR(_Symbol, PERIOD_H1, InpH1SARStep, InpH1SARMax);

   // MACD(Open) on botTF — H1 strategy cross signal
   hMACD_Open = iMACD(_Symbol, botTF, InpMACDFast, InpMACDSlow, InpMACDSignal, PRICE_OPEN);

   if(hMAFast == INVALID_HANDLE || hMASlow  == INVALID_HANDLE ||
      hEMAFast== INVALID_HANDLE || hEMASlow == INVALID_HANDLE ||
      hRSI    == INVALID_HANDLE || hMACD    == INVALID_HANDLE ||
      hSAR    == INVALID_HANDLE || hADX     == INVALID_HANDLE ||
      hSAR_H1 == INVALID_HANDLE || hMACD_Open == INVALID_HANDLE)
   {
      Alert("ScalpMaster: Critical indicator handle creation failed!");
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| GET INDICATOR BUFFERS                                            |
//+------------------------------------------------------------------+
bool GetMA(double &f0, double &f1, double &s0, double &s1)
{
   double fa[], sa[];
   ArraySetAsSeries(fa, true); ArraySetAsSeries(sa, true);
   if(CopyBuffer(hMAFast, 0, 0, 3, fa) < 3) return false;
   if(CopyBuffer(hMASlow, 0, 0, 3, sa) < 3) return false;
   f0=fa[0]; f1=fa[1]; s0=sa[0]; s1=sa[1];
   return true;
}

bool GetEMA(double &f0, double &f1, double &s0, double &s1)
{
   double fa[], sa[];
   ArraySetAsSeries(fa, true); ArraySetAsSeries(sa, true);
   if(CopyBuffer(hEMAFast, 0, 0, 3, fa) < 3) return false;
   if(CopyBuffer(hEMASlow, 0, 0, 3, sa) < 3) return false;
   f0=fa[0]; f1=fa[1]; s0=sa[0]; s1=sa[1];
   return true;
}

double GetRSI(int shift=1)
{
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(hRSI, 0, 0, shift+2, buf) < shift+2) return 50.0;
   return buf[shift];
}

//+------------------------------------------------------------------+
//| NEW BAR DETECTION + BAR INDEX                                    |
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
bool RSIOKBuy()  { double r=GetRSI(1); return r >= InpRSIMinBuy  && r <= InpRSIOB; }
bool RSIOKSell() { double r=GetRSI(1); return r <= InpRSIMaxSell && r >= InpRSIOS; }

// RSI reached an extreme and is turning back → trend peak (exit signal when in trade)
bool RSITurningAgainst()
{
   if(!HasPosition()) return false;
   double r1 = GetRSI(1);   // last confirmed bar
   double r2 = GetRSI(2);   // two bars ago
   if(isBuy  && r2 >= 68.0 && r1 < r2) return true;   // was overbought, now falling
   if(!isBuy && r2 <= 32.0 && r1 > r2) return true;   // was oversold, now rising
   return false;
}

//+------------------------------------------------------------------+
//| MACD FILTER — histogram must confirm direction                   |
//+------------------------------------------------------------------+
bool MACDOKBuy()
{
   if(!InpUseMACDFilter) return true;
   double macd[], signal[];
   ArraySetAsSeries(macd, true); ArraySetAsSeries(signal, true);
   if(CopyBuffer(hMACD, 0, 0, 3, macd)   < 3) return true;
   if(CopyBuffer(hMACD, 1, 0, 3, signal) < 3) return true;
   return (macd[1] - signal[1]) > 0;
}

bool MACDOKSell()
{
   if(!InpUseMACDFilter) return true;
   double macd[], signal[];
   ArraySetAsSeries(macd, true); ArraySetAsSeries(signal, true);
   if(CopyBuffer(hMACD, 0, 0, 3, macd)   < 3) return true;
   if(CopyBuffer(hMACD, 1, 0, 3, signal) < 3) return true;
   return (macd[1] - signal[1]) < 0;
}

//+------------------------------------------------------------------+
//| VOLUME FILTER — current volume > average × multiplier           |
//+------------------------------------------------------------------+
bool VolumeOK()
{
   if(!InpUseVolFilter) return true;
   long vols[];
   ArraySetAsSeries(vols, true);
   int n = InpVolPeriod + 1;
   if(CopyTickVolume(_Symbol, botTF, 0, n, vols) < n) return true;
   long cur = vols[1];
   long sum = 0;
   for(int i = 1; i <= InpVolPeriod; i++) sum += vols[i];
   double avg = (double)sum / InpVolPeriod;
   return cur >= avg * InpVolMult;
}

//+------------------------------------------------------------------+
//| GMMA — Guppy Multiple Moving Average filters                    |
//+------------------------------------------------------------------+
// Returns how many long-group EMAs have been crossed by EMA15 (short group slowest)
int GMMACrossCount(bool buy)
{
   double ema15buf[];
   ArraySetAsSeries(ema15buf, true);
   if(CopyBuffer(hGMMAShort[5], 0, 0, 2, ema15buf) < 2) return 0;
   double ema15 = ema15buf[1];  // confirmed bar
   int count = 0;
   for(int i = 0; i < 6; i++)
   {
      double lb[];
      ArraySetAsSeries(lb, true);
      if(CopyBuffer(hGMMALong[i], 0, 0, 2, lb) < 2) continue;
      if(buy  && ema15 > lb[1]) count++;
      if(!buy && ema15 < lb[1]) count++;
   }
   return count;
}

bool GMMAHalfCrossedBuy()
{
   if(!InpUseGMMA) return true;
   return GMMACrossCount(true) >= InpGMMACrossCount;
}

bool GMMAHalfCrossedSell()
{
   if(!InpUseGMMA) return true;
   return GMMACrossCount(false) >= InpGMMACrossCount;
}

// Returns true if GMMA long group is still expanding (trend valid, not retracting)
bool GMMALongExpanding(bool buy)
{
   double ema30[], ema60[];
   ArraySetAsSeries(ema30, true); ArraySetAsSeries(ema60, true);
   if(CopyBuffer(hGMMALong[0], 0, 0, 3, ema30) < 3) return true;  // EMA30 = index 0
   if(CopyBuffer(hGMMALong[5], 0, 0, 3, ema60) < 3) return true;  // EMA60 = index 5
   double spread1 = MathAbs(ema30[1] - ema60[1]);
   double spread2 = MathAbs(ema30[2] - ema60[2]);
   return spread1 >= spread2 * 0.95;  // expanding or stable (5% tolerance)
}

// GMMA group average comparison — short-group avg vs long-group avg.
// Responds immediately at trend start (used for M1 entry, no cross-count delay).
bool GMMATrendingBuy()
{
   if(!InpUseGMMA) return true;
   double shortAvg = 0, longAvg = 0;
   for(int i = 0; i < 6; i++)
   {
      double sb[], lb[];
      ArraySetAsSeries(sb, true); ArraySetAsSeries(lb, true);
      if(CopyBuffer(hGMMAShort[i], 0, 0, 2, sb) < 2) return true;
      if(CopyBuffer(hGMMALong[i],  0, 0, 2, lb) < 2) return true;
      shortAvg += sb[1];
      longAvg  += lb[1];
   }
   return shortAvg > longAvg;
}

bool GMMATrendingSell()
{
   if(!InpUseGMMA) return true;
   double shortAvg = 0, longAvg = 0;
   for(int i = 0; i < 6; i++)
   {
      double sb[], lb[];
      ArraySetAsSeries(sb, true); ArraySetAsSeries(lb, true);
      if(CopyBuffer(hGMMAShort[i], 0, 0, 2, sb) < 2) return true;
      if(CopyBuffer(hGMMALong[i],  0, 0, 2, lb) < 2) return true;
      shortAvg += sb[1];
      longAvg  += lb[1];
   }
   return shortAvg < longAvg;
}

//+------------------------------------------------------------------+
//| SAR PARABÓLICO — direction + flip detection                     |
//+------------------------------------------------------------------+
bool SARDirectionBuy()
{
   if(!InpUseSAR) return true;
   double sarBuf[]; MqlRates bars[];
   ArraySetAsSeries(sarBuf, true); ArraySetAsSeries(bars, true);
   if(CopyBuffer(hSAR, 0, 0, 2, sarBuf) < 2) return true;
   if(CopyRates(_Symbol, botTF, 0, 2, bars) < 2) return true;
   return sarBuf[1] < bars[1].close;  // SAR below close = bullish
}

bool SARDirectionSell()
{
   if(!InpUseSAR) return true;
   double sarBuf[]; MqlRates bars[];
   ArraySetAsSeries(sarBuf, true); ArraySetAsSeries(bars, true);
   if(CopyBuffer(hSAR, 0, 0, 2, sarBuf) < 2) return true;
   if(CopyRates(_Symbol, botTF, 0, 2, bars) < 2) return true;
   return sarBuf[1] > bars[1].close;  // SAR above close = bearish
}

// Returns true if SAR just flipped AGAINST our open position
bool SARFlippedAgainst()
{
   if(!InpUseSAR || !HasPosition()) return false;
   double sarBuf[]; MqlRates bars[];
   ArraySetAsSeries(sarBuf, true); ArraySetAsSeries(bars, true);
   if(CopyBuffer(hSAR, 0, 0, 3, sarBuf) < 3) return false;
   if(CopyRates(_Symbol, botTF, 0, 3, bars) < 3) return false;
   bool prevBullish = sarBuf[2] < bars[2].close;
   bool currBearish = sarBuf[1] > bars[1].close;
   bool prevBearish = sarBuf[2] > bars[2].close;
   bool currBullish = sarBuf[1] < bars[1].close;
   if(isBuy  && prevBullish && currBearish) return true;
   if(!isBuy && prevBearish && currBullish) return true;
   return false;
}

//+------------------------------------------------------------------+
//| ADX — Fuerza de Tendencia (entry + exhaustion exit)             |
//+------------------------------------------------------------------+
bool ADXStrong()
{
   if(!InpUseADXFilter) return true;
   double adxBuf[];
   ArraySetAsSeries(adxBuf, true);
   if(CopyBuffer(hADX, 0, 0, 2, adxBuf) < 2) return true;
   return adxBuf[1] >= InpADXMinLevel;
}

// Returns true when ADX just peaked (was rising, now falling from high level)
bool ADXExhausting()
{
   double adxBuf[];
   ArraySetAsSeries(adxBuf, true);
   if(CopyBuffer(hADX, 0, 0, 4, adxBuf) < 4) return false;
   bool wasRising  = adxBuf[2] > adxBuf[3];
   bool nowFalling = adxBuf[1] < adxBuf[2];
   bool wasHigh    = adxBuf[2] >= InpADXExitLevel;
   return wasRising && nowFalling && wasHigh;
}

//+------------------------------------------------------------------+
//| H1 SAR DIRECTION — uses slow params (0.01, 0.1)                 |
//+------------------------------------------------------------------+
bool SARH1Bull()
{
   double sarBuf[]; MqlRates bars[];
   ArraySetAsSeries(sarBuf, true); ArraySetAsSeries(bars, true);
   if(CopyBuffer(hSAR_H1, 0, 0, 2, sarBuf) < 2) return true;
   if(CopyRates(_Symbol, PERIOD_H1, 0, 2, bars) < 2) return true;
   return sarBuf[1] < bars[1].close;   // SAR below close = H1 bullish
}

bool SARH1Bear()
{
   double sarBuf[]; MqlRates bars[];
   ArraySetAsSeries(sarBuf, true); ArraySetAsSeries(bars, true);
   if(CopyBuffer(hSAR_H1, 0, 0, 2, sarBuf) < 2) return true;
   if(CopyRates(_Symbol, PERIOD_H1, 0, 2, bars) < 2) return true;
   return sarBuf[1] > bars[1].close;   // SAR above close = H1 bearish
}

// Returns true when H1 SAR just flipped against the open position
bool SARH1FlippedAgainst()
{
   if(!HasPosition()) return false;
   double sarBuf[]; MqlRates bars[];
   ArraySetAsSeries(sarBuf, true); ArraySetAsSeries(bars, true);
   if(CopyBuffer(hSAR_H1, 0, 0, 3, sarBuf) < 3) return false;
   if(CopyRates(_Symbol, PERIOD_H1, 0, 3, bars) < 3) return false;
   bool prevBull = sarBuf[2] < bars[2].close;
   bool currBear = sarBuf[1] > bars[1].close;
   bool prevBear = sarBuf[2] > bars[2].close;
   bool currBull = sarBuf[1] < bars[1].close;
   if(isBuy  && prevBull && currBear) return true;
   if(!isBuy && prevBear && currBull) return true;
   return false;
}

//+------------------------------------------------------------------+
//| MACD(OPEN) CROSS — H1 strategy entry + exit signals             |
//+------------------------------------------------------------------+
// Bullish cross: MACD line crossed above signal on bar[1]
bool MACDOpenCrossBull()
{
   double macd[], signal[];
   ArraySetAsSeries(macd, true); ArraySetAsSeries(signal, true);
   if(CopyBuffer(hMACD_Open, 0, 0, 3, macd)   < 3) return false;
   if(CopyBuffer(hMACD_Open, 1, 0, 3, signal) < 3) return false;
   return (macd[2]-signal[2]) < 0 && (macd[1]-signal[1]) > 0;
}

// Bearish cross: MACD line crossed below signal on bar[1]
bool MACDOpenCrossBear()
{
   double macd[], signal[];
   ArraySetAsSeries(macd, true); ArraySetAsSeries(signal, true);
   if(CopyBuffer(hMACD_Open, 0, 0, 3, macd)   < 3) return false;
   if(CopyBuffer(hMACD_Open, 1, 0, 3, signal) < 3) return false;
   return (macd[2]-signal[2]) > 0 && (macd[1]-signal[1]) < 0;
}

// Returns true when MACD crossed AGAINST the open position (exit signal)
bool MACDOpenCrossAgainst()
{
   if(!HasPosition()) return false;
   double macd[], signal[];
   ArraySetAsSeries(macd, true); ArraySetAsSeries(signal, true);
   if(CopyBuffer(hMACD_Open, 0, 0, 3, macd)   < 3) return false;
   if(CopyBuffer(hMACD_Open, 1, 0, 3, signal) < 3) return false;
   if(isBuy)  return (macd[2]-signal[2]) > 0 && (macd[1]-signal[1]) < 0;
   if(!isBuy) return (macd[2]-signal[2]) < 0 && (macd[1]-signal[1]) > 0;
   return false;
}

// Current MACD direction (above/below signal = bull/bear) — used as filter
bool MACDOpenBull()
{
   double macd[], signal[];
   ArraySetAsSeries(macd, true); ArraySetAsSeries(signal, true);
   if(CopyBuffer(hMACD_Open, 0, 0, 2, macd)   < 2) return true;
   if(CopyBuffer(hMACD_Open, 1, 0, 2, signal) < 2) return true;
   return (macd[1]-signal[1]) > 0;
}

bool MACDOpenBear()
{
   double macd[], signal[];
   ArraySetAsSeries(macd, true); ArraySetAsSeries(signal, true);
   if(CopyBuffer(hMACD_Open, 0, 0, 2, macd)   < 2) return true;
   if(CopyBuffer(hMACD_Open, 1, 0, 2, signal) < 2) return true;
   return (macd[1]-signal[1]) < 0;
}

//+------------------------------------------------------------------+
//| BUILD GRID LEVELS                                                |
//+------------------------------------------------------------------+
void BuildGrid(double entry, bool buy)
{
   ArrayResize(tpGrid, InpGridLevels);
   double pt   = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double step = InpGridPts * pt * 10.0;
   for(int i = 0; i < InpGridLevels; i++)
      tpGrid[i] = buy ? entry + step*(i+1) : entry - step*(i+1);
   gridLevel = 0;
   trailSL   = 0;
}

//+------------------------------------------------------------------+
//| FIND OPEN POSITION BY MAGIC                                      |
//+------------------------------------------------------------------+
bool FindPosition(ulong &ticket)
{
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      if(PosInfo.SelectByIndex(i))
         if(PosInfo.Symbol()==_Symbol && PosInfo.Magic()==MAGIC)
         { ticket = PosInfo.Ticket(); return true; }
   }
   return false;
}

bool HasPosition()
{
   ulong t;
   return FindPosition(t);
}

double GetProfit()
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
   double lot       = CalcLot();
   double askPrice  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bidPrice  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double openPrice = buy ? askPrice : bidPrice;
   double sl        = CalcSL(buy, openPrice);
   double pt        = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   // M1: hard TP only if InpScalpTPPips > 0 (safety net); 0 = indicators manage exit
   double tp = 0;
   if(botTF == PERIOD_M1 && InpScalpTPPips > 0)
   {
      double tpDist = InpScalpTPPips * pt * 10.0;
      tp = buy ? openPrice + tpDist : openPrice - tpDist;
      tp = NormalizeDouble(tp, _Digits);
   }

   bool ok = buy ? Trade.Buy(lot,  _Symbol, 0, sl, tp, "SMP_BUY")
                 : Trade.Sell(lot, _Symbol, 0, sl, tp, "SMP_SELL");
   if(!ok)
   { Print("OpenTrade failed: ", GetLastError()); return false; }

   Sleep(200);
   ulong t;
   if(!FindPosition(t))
   { Print("OpenTrade: position not found after open"); return false; }

   posTicket  = t;
   entryPrice = buy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                    : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   openLot    = lot;
   isBuy      = buy;
   beMoveDone = false;
   BuildGrid(entryPrice, buy);
   statTotal++;
   botStatus  = buy ? "LONG OPEN" : "SHORT OPEN";
   statusClr  = buy ? CLR_GREEN : CLR_RED;
   Print("Trade opened: ", buy?"BUY":"SELL", " Lot=", lot,
         " Entry=", entryPrice, " SL=", DoubleToString(sl,_Digits),
         " TP=", tp > 0 ? DoubleToString(tp,_Digits) : "GRID");
   return true;
}

//+------------------------------------------------------------------+
//| CLOSE TRADE — with retry logic and real profit capture          |
//+------------------------------------------------------------------+
bool CloseTrade()
{
   ulong t;
   if(!FindPosition(t)) { openLot=0; posTicket=0; return true; }
   ulong savedTicket = t;

   bool closed = false;
   for(int attempt = 1; attempt <= 3 && !closed; attempt++)
   {
      int slip = 50 * attempt;   // 50, 100, 150 pts — covers XAUUSD volatility spikes
      if(Trade.PositionClose(t, slip))
         closed = true;
      else
      {
         Print("CloseTrade attempt ", attempt, "/3 failed. Err=", GetLastError(),
               " Slip=", slip, " Ticket=", t);
         if(attempt < 3) Sleep(300 * attempt);
      }
   }

   if(!closed)
   {
      Print("CloseTrade FAILED after 3 attempts. Resetting state. Ticket=", t);
      posTicket=0; openLot=0; gridLevel=0; trailSL=0; beMoveDone=false;
      botStatus="ERR-CLOSE"; statusClr=CLR_RED;
      return false;
   }

   // Capture actual realized profit from deal history (includes spread + commission)
   double realProfit = GetProfit();
   if(HistorySelectByPosition(savedTicket))
   {
      int deals = HistoryDealsTotal();
      for(int i = deals - 1; i >= 0; i--)
      {
         ulong dk = HistoryDealGetTicket(i);
         if(HistoryDealGetInteger(dk, DEAL_ENTRY) == DEAL_ENTRY_OUT)
         {
            realProfit = HistoryDealGetDouble(dk, DEAL_PROFIT)
                       + HistoryDealGetDouble(dk, DEAL_SWAP)
                       + HistoryDealGetDouble(dk, DEAL_COMMISSION);
            break;
         }
      }
   }

   statProfit += realProfit;
   if(realProfit > 0) statWins++;
   posTicket=0; openLot=0; gridLevel=0; trailSL=0; beMoveDone=false;
   botStatus="IDLE"; statusClr=CLR_GRAY;
   Print("Trade closed. Profit=", DoubleToString(realProfit,2));
   return true;
}

//+------------------------------------------------------------------+
//| UPDATE SL ON POSITION — with broker stop level guard           |
//+------------------------------------------------------------------+
void UpdateSL(double sl)
{
   ulong t;
   if(!FindPosition(t)) return;
   PosInfo.SelectByTicket(t);
   double curSL   = PosInfo.StopLoss();
   sl = NormalizeDouble(sl, _Digits);

   double pt      = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   long   slvl    = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDist = (slvl + 2) * pt;
   double bid     = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask     = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   if(isBuy  && (bid - sl) < minDist) return;   // too close to market, skip
   if(!isBuy && (sl - ask) < minDist) return;

   if(isBuy  && sl > curSL)
   { if(!Trade.PositionModify(t, sl, 0)) Print("UpdateSL BUY failed: ", GetLastError()); }
   if(!isBuy && sl < curSL)
   { if(!Trade.PositionModify(t, sl, 0)) Print("UpdateSL SELL failed: ", GetLastError()); }
}

//+------------------------------------------------------------------+
//| MANAGE SCALPER EXIT (M1) — trailing SL + multi-signal peak exit|
//+------------------------------------------------------------------+
void ManageScalperExit(int bar)
{
   ulong t;
   if(!FindPosition(t))
   {
      // Auto-closed by MT5 (TP or SL hit) — recover actual profit by position ID
      if(posTicket > 0 && HistorySelectByPosition(posTicket))
      {
         int deals = HistoryDealsTotal();
         for(int i = deals - 1; i >= 0; i--)
         {
            ulong dk = HistoryDealGetTicket(i);
            if(HistoryDealGetInteger(dk, DEAL_ENTRY) == DEAL_ENTRY_OUT)
            {
               double dp = HistoryDealGetDouble(dk, DEAL_PROFIT)
                         + HistoryDealGetDouble(dk, DEAL_SWAP)
                         + HistoryDealGetDouble(dk, DEAL_COMMISSION);
               statProfit += dp;
               if(dp > 0) statWins++;
               break;
            }
         }
      }
      posTicket=0; openLot=0; beMoveDone=false; gridLevel=0; trailSL=0;
      botStatus="IDLE"; statusClr=CLR_GRAY;
      botState=STATE_IDLE; emaArrived=false;
      return;
   }

   double profit = GetProfit();
   double pt     = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   // ── PHASE 1: Breakeven — lock entry once minimum profit reached ───
   if(!beMoveDone && profit >= InpScalpMinProfit)
   {
      double beSL = NormalizeDouble(entryPrice + (isBuy ? pt*2 : -pt*2), _Digits);
      UpdateSL(beSL);
      beMoveDone = true;
      Print("Scalper: BE locked. Profit=", DoubleToString(profit,2));
   }

   // ── PHASE 2: SAR trailing SL — grows with the trend ──────────────
   // After breakeven, trail the SL to the SAR level so gains compound
   // as long as the trend continues.  SAR naturally rises in bull trends.
   if(beMoveDone)
   {
      double sarBuf[];
      ArraySetAsSeries(sarBuf, true);
      if(CopyBuffer(hSAR, 0, 0, 2, sarBuf) >= 2)
      {
         long   slvl    = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
         double minDist = (slvl + 2) * pt;
         double sar     = sarBuf[1];
         double bid     = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double ask     = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         if(isBuy  && sar > entryPrice && sar < bid - minDist)
            UpdateSL(NormalizeDouble(sar, _Digits));
         if(!isBuy && sar < entryPrice && sar > ask + minDist)
            UpdateSL(NormalizeDouble(sar, _Digits));
      }
   }

   // ── REVERSAL SCORING ─────────────────────────────────────────────
   // SAR weighted ×2: single most reliable M1 reversal signal.
   // Other indicators weighted ×1 each — consensus exits at peak.
   bool sarFlip     = SARFlippedAgainst();
   bool adxPeak     = ADXExhausting();
   bool gmmaCon     = !GMMALongExpanding(isBuy);
   bool macdAgainst = isBuy ? !MACDOKBuy() : !MACDOKSell();
   bool rsiTurning  = RSITurningAgainst();
   int  score = (sarFlip ? 2 : 0) + (int)adxPeak + (int)gmmaCon
              + (int)macdAgainst + (int)rsiTurning;

   // ── EXIT A: SAR flip — close only when not at a loss ─────────────
   // Prevents giving back gains; Pivot SL guards the downside when in loss.
   if(sarFlip && profit >= 0)
   {
      Print("Scalper: SAR flip exit. Profit=", DoubleToString(profit,2));
      CloseTrade(); botState=STATE_IDLE; emaArrived=false;
      return;
   }

   // ── EXIT B: Peak consensus (score ≥ 3) — close at max momentum ───
   // 3 pts = any combination: ADX+GMMA+MACD, ADX+GMMA+RSI, etc.
   if(score >= 3 && profit >= InpScalpMinProfit)
   {
      Print("Scalper: Peak exit score=", score, " ADX=", adxPeak,
            " GMMA=", gmmaCon, " MACD=", macdAgainst, " RSI=", rsiTurning,
            ". Profit=", DoubleToString(profit,2));
      CloseTrade(); botState=STATE_IDLE; emaArrived=false;
      return;
   }

   // ── EXIT C: 2 signals + meaningful profit locked in ───────────────
   if(score >= 2 && profit >= InpScalpMinProfit * 2)
   {
      Print("Scalper: 2-signal exit score=", score,
            ". Profit=", DoubleToString(profit,2));
      CloseTrade(); botState=STATE_IDLE; emaArrived=false;
      return;
   }
   // SAR trailing SL handles the rest; InpScalpTPPips (if >0) is hard safety net
}

//+------------------------------------------------------------------+
//| MANAGE GRID TP (M15) — with SAR/ADX intelligent exits          |
//+------------------------------------------------------------------+
void ManageGridTP(int bar)
{
   if(!HasPosition())
   {
      // Auto-closed by MT5 (SL or TP hit) — recover actual profit by position ID
      if(posTicket > 0 && HistorySelectByPosition(posTicket))
      {
         int deals = HistoryDealsTotal();
         for(int i = deals - 1; i >= 0; i--)
         {
            ulong dk = HistoryDealGetTicket(i);
            if(HistoryDealGetInteger(dk, DEAL_ENTRY) == DEAL_ENTRY_OUT)
            {
               double dp = HistoryDealGetDouble(dk, DEAL_PROFIT)
                         + HistoryDealGetDouble(dk, DEAL_SWAP)
                         + HistoryDealGetDouble(dk, DEAL_COMMISSION);
               statProfit += dp;
               if(dp > 0) statWins++;
               break;
            }
         }
      }
      posTicket=0; openLot=0; beMoveDone=false; gridLevel=0; trailSL=0;
      botStatus="IDLE"; statusClr=CLR_GRAY;
      return;
   }

   double profit   = GetProfit();

   // INTELLIGENT EXIT M15: SAR flipped + ≥2 grid levels captured + profit > 0
   // Requires 2 levels before firing to let the grid develop (avoids early exits)
   if(SARFlippedAgainst() && gridLevel >= 2 && profit > 0)
   {
      Print("Grid: SAR flip exit @ level ", gridLevel, ". Profit=", DoubleToString(profit,2));
      CloseTrade(); botState=STATE_IDLE; emaArrived=false;
      return;
   }

   // INTELLIGENT EXIT M15: ADX peak + ≥2 levels + profit >= minimum
   if(ADXExhausting() && gridLevel >= 2 && profit >= InpMinProfit)
   {
      Print("Grid: ADX exhaustion exit @ level ", gridLevel, ". Profit=", DoubleToString(profit,2));
      CloseTrade(); botState=STATE_IDLE; emaArrived=false;
      return;
   }

   double bid      = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask      = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double curPrice = isBuy ? bid : ask;
   double pt       = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   // Advance grid levels
   while(gridLevel < InpGridLevels)
   {
      bool hit = isBuy ? curPrice >= tpGrid[gridLevel]
                       : curPrice <= tpGrid[gridLevel];
      if(!hit) break;
      gridLevel++;
      // Set trailing SL to previous grid or entry
      double newSL = (gridLevel > 1) ? tpGrid[gridLevel-2] : entryPrice;
      trailSL = newSL;
      UpdateSL(trailSL);
      Print("Grid level ", gridLevel, " hit. TrailSL=", DoubleToString(trailSL,_Digits));
   }

   // Trailing SL check
   if(trailSL > 0 && profit >= 0)
   {
      bool hit = isBuy ? curPrice <= trailSL : curPrice >= trailSL;
      if(hit)
      {
         Print("Trailing SL triggered. Closing.");
         CloseTrade(); botState = STATE_IDLE; emaArrived=false;
         return;
      }
   }

   // Max grid: close with profit
   if(gridLevel >= InpGridLevels && profit >= InpMinProfit)
   {
      Print("Max grid reached. Profit=", DoubleToString(profit,2));
      CloseTrade(); botState = STATE_IDLE; emaArrived=false;
      return;
   }

   // Time-based exit
   if(tpStartBar >= 0 && bar >= tpStartBar)
   {
      int waitBars = isBuy ? InpBuyExtra : 0;
      if(bar >= tpStartBar + waitBars && profit >= InpMinProfit)
      {
         Print("Time-TP exit. Bars waited=", bar-tpStartBar, " Profit=", DoubleToString(profit,2));
         CloseTrade(); botState = STATE_IDLE; emaArrived=false;
      }
   }
}

//+------------------------------------------------------------------+
//| MANAGE H1 EXIT — H1 SAR trailing + MACD reversal + ADX peak    |
//| H1 trades last hours; wait patiently for full move to develop.  |
//+------------------------------------------------------------------+
void ManageH1Exit(int bar)
{
   ulong t;
   if(!FindPosition(t))
   {
      // Auto-closed by MT5 (SL/TP) — recover actual profit by position ID
      if(posTicket > 0 && HistorySelectByPosition(posTicket))
      {
         int deals = HistoryDealsTotal();
         for(int i = deals - 1; i >= 0; i--)
         {
            ulong dk = HistoryDealGetTicket(i);
            if(HistoryDealGetInteger(dk, DEAL_ENTRY) == DEAL_ENTRY_OUT)
            {
               double dp = HistoryDealGetDouble(dk, DEAL_PROFIT)
                         + HistoryDealGetDouble(dk, DEAL_SWAP)
                         + HistoryDealGetDouble(dk, DEAL_COMMISSION);
               statProfit += dp;
               if(dp > 0) statWins++;
               break;
            }
         }
      }
      posTicket=0; openLot=0; beMoveDone=false; gridLevel=0; trailSL=0;
      botStatus="IDLE"; statusClr=CLR_GRAY;
      botState=STATE_IDLE; emaArrived=false;
      return;
   }

   double profit = GetProfit();
   double pt     = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   // ── PHASE 1: Breakeven once minimum H1 profit reached ─────────────
   if(!beMoveDone && profit >= InpH1MinProfit)
   {
      double beSL = NormalizeDouble(entryPrice + (isBuy ? pt*5 : -pt*5), _Digits);
      UpdateSL(beSL);
      beMoveDone = true;
      Print("H1: BE locked. Profit=", DoubleToString(profit,2));
   }

   // ── PHASE 2: Trail SL using H1 SAR (locks in profit per H1 bar) ──
   if(beMoveDone)
   {
      double sarBuf[];
      ArraySetAsSeries(sarBuf, true);
      if(CopyBuffer(hSAR_H1, 0, 0, 2, sarBuf) >= 2)
      {
         long   slvl    = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
         double minDist = (slvl + 2) * pt;
         double sar     = sarBuf[1];
         double bid     = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double ask     = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         if(isBuy  && sar > entryPrice && sar < bid - minDist)
            UpdateSL(NormalizeDouble(sar, _Digits));
         if(!isBuy && sar < entryPrice && sar > ask + minDist)
            UpdateSL(NormalizeDouble(sar, _Digits));
      }
   }

   // ── EXIT A: H1 SAR flipped — close only when not at a loss ───────
   if(SARH1FlippedAgainst() && profit >= 0)
   {
      Print("H1: SAR flip exit. Profit=", DoubleToString(profit,2));
      CloseTrade(); botState=STATE_IDLE; emaArrived=false;
      return;
   }

   // ── EXIT B: MACD(Open) crossed in reverse — entry signal reversed ─
   if(MACDOpenCrossAgainst() && profit >= 0)
   {
      Print("H1: MACD reverse cross exit. Profit=", DoubleToString(profit,2));
      CloseTrade(); botState=STATE_IDLE; emaArrived=false;
      return;
   }

   // ── EXIT C: ADX exhausted + GMMA converging — trend peak ─────────
   if(ADXExhausting() && !GMMALongExpanding(isBuy) && profit >= InpH1MinProfit)
   {
      Print("H1: ADX peak + GMMA convergence exit. Profit=", DoubleToString(profit,2));
      CloseTrade(); botState=STATE_IDLE; emaArrived=false;
      return;
   }
}

//+------------------------------------------------------------------+
//| MAIN SIGNAL LOGIC (on new bar only)                              |
//+------------------------------------------------------------------+
void ProcessBar(int bar)
{
   double maf0,maf1,mas0,mas1, ef0,ef1,es0,es1;
   if(!GetMA(maf0,maf1,mas0,mas1)) return;
   if(!GetEMA(ef0,ef1,es0,es1))    return;

   // Detect cross on LAST CLOSED BAR (index 1)
   bool maCrossUp   = maf1 < mas1 && maf0 > mas0;   // Wait: this checks if bar0 already crossed
   // Actually we need bar[1] vs bar[2] for confirmed cross:
   // Let me use: fast[1]>slow[1] and fast[2]<slow[2]
   double maf2, mas2, ef2, es2;
   {
      double fa[],sa[],efa[],esa[];
      ArraySetAsSeries(fa,true); ArraySetAsSeries(sa,true);
      ArraySetAsSeries(efa,true); ArraySetAsSeries(esa,true);
      if(CopyBuffer(hMAFast,0,0,4,fa)<4 || CopyBuffer(hMASlow,0,0,4,sa)<4) return;
      if(CopyBuffer(hEMAFast,0,0,4,efa)<4|| CopyBuffer(hEMASlow,0,0,4,esa)<4) return;
      maf2=fa[2]; mas2=sa[2]; ef2=efa[2]; es2=esa[2];
      // Recalc bar[1] cross using [1] vs [2]
      maCrossUp  = maf2 < mas2 && maf1 > mas1;
      bool mcDn  = maf2 > mas2 && maf1 < mas1;
      bool emaCUp = ef2 < es2 && ef1 > es1;
      bool emaCDn = ef2 > es2 && ef1 < es1;

      switch(botState)
      {
         //--- IDLE: detect entry signal (PATH A = MA cross for M1/M15; PATH B = MACD+H1SAR)
         case STATE_IDLE:
         {
            // PATH A: MA/EMA cross strategy — M1 and M15 only
            if(botTF != PERIOD_H1 && (maCrossUp || mcDn))
            {
               maCrossBar = bar - 1;
               maDir      = maCrossUp;
               botState   = STATE_MA_CROSS;
               lastSignal = maCrossUp ? "MA CROSS ▲" : "MA CROSS ▼";
               emaArrived = false;
               emaCrossBar= -1;
               Print("MA Cross @ bar", maCrossBar, " ", maDir?"UP":"DOWN");
               break;   // PATH A takes priority; skip PATH B this bar
            }

            // PATH B: MACD(Open) cross + H1 SAR direction — all TFs
            if(InpUseH1Strategy)
            {
               bool macdBull = MACDOpenCrossBull();
               bool macdBear = MACDOpenCrossBear();
               if(macdBull || macdBear)
               {
                  bool sarH1Ok = macdBull ? SARH1Bull() : SARH1Bear();
                  if(sarH1Ok)
                  {
                     macdCrossBar = bar - 1;
                     macdCrossDir = macdBull;
                     botState     = STATE_MACD_CROSS;
                     lastSignal   = macdBull ? "MACD+SAR ▲" : "MACD+SAR ▼";
                     Print("MACD+H1SAR @ bar", macdCrossBar, " ", macdCrossDir?"BUY":"SELL");
                  }
               }
            }
            break;
         }

         //--- MACD cross + H1 SAR: wait for entry bar then check filters
         case STATE_MACD_CROSS:
         {
            // Timeout: H1 gets more wait time (bars = H1 bars)
            int macdMaxWait = (botTF == PERIOD_H1) ? 5 : 3;
            if(bar > macdCrossBar + macdMaxWait)
            {
               Print("MACD cross timeout. Reset to IDLE.");
               botState = STATE_IDLE;
               break;
            }
            // Minimum wait before entry: H1 needs more reaction time
            int waitBars = (botTF == PERIOD_H1) ? InpH1WaitBars : 1;
            if(bar >= macdCrossBar + waitBars)
            {
               // Verify MACD + H1 SAR still aligned (not flipped back)
               bool macdStillOk = macdCrossDir ? MACDOpenBull() : MACDOpenBear();
               bool sarH1StillOk= macdCrossDir ? SARH1Bull()    : SARH1Bear();
               bool rsiOk   = macdCrossDir ? RSIOKBuy()        : RSIOKSell();
               bool adxOk   = ADXStrong();
               bool volOk   = VolumeOK();
               bool gmmaOk  = macdCrossDir ? GMMATrendingBuy() : GMMATrendingSell();
               if(!macdStillOk || !sarH1StillOk || !rsiOk || !adxOk || !volOk || !gmmaOk)
               {
                  Print("MACD entry blocked @ bar ", bar,
                        " MACD:", macdStillOk, " SARH1:", sarH1StillOk,
                        " RSI:", rsiOk, " ADX:", adxOk, " Vol:", volOk, " GMMA:", gmmaOk);
                  if(bar > macdCrossBar + macdMaxWait - 1)
                  { Print("MACD entry timeout. Reset."); botState = STATE_IDLE; }
                  break;
               }
               bool opened = OpenTrade(macdCrossDir);
               if(opened)
               {
                  entryBar   = bar;
                  tpStartBar = bar + 2;
                  emaArrived = true;   // no WAIT_EMA for this path
                  botState   = STATE_IN_TRADE;
                  Print("MACD strategy entry: ", macdCrossDir?"BUY":"SELL",
                        " TF=", TFName(InpTimeframe));
               }
               else botState = STATE_IDLE;
            }
            break;
         }

         //--- MA seen: wait for EMA (M1 required) or open after 2 bars (M15+)
         case STATE_MA_CROSS:
         {
            // EMA confirmation check (always track regardless of TF)
            if((maDir && emaCUp) || (!maDir && emaCDn))
            {
               emaCrossBar = bar - 1;
               emaArrived  = true;
               lastSignal  = maDir ? "EMA CONFIRM ▲" : "EMA CONFIRM ▼";
               Print("EMA cross pre-entry @ bar", emaCrossBar);
            }

            // M1: EMA confirmation is mandatory (max 5-bar wait)
            // M15: enter 2 bars after MA cross (EMA adjusts TP timing only)
            bool m1RequireEMA = (botTF == PERIOD_M1);
            int  emaMaxWait   = (botTF == PERIOD_M1) ? 8 : 5;  // M1 gets extra bars (EMA and SMA cross close together)

            if(m1RequireEMA && bar > maCrossBar + emaMaxWait)
            {
               Print("M1 EMA wait timeout. Reset to IDLE.");
               botState = STATE_IDLE;
               break;
            }

            bool readyToEnter = false;
            if(m1RequireEMA)
               readyToEnter = emaArrived && bar >= emaCrossBar + 1;
            else
               readyToEnter = bar >= maCrossBar + 2;

            if(readyToEnter)
            {
               bool rsiOk  = maDir ? RSIOKBuy()  : RSIOKSell();
               bool macdOk = maDir ? MACDOKBuy() : MACDOKSell();
               bool sarOk  = maDir ? SARDirectionBuy()  : SARDirectionSell();
               // M1 scalper: use GMMA group average comparison — responds at trend start.
               // M15 grid: use cross-count (≥3 long EMAs crossed = stronger confirmation).
               bool gmmaOk = maDir
                  ? (botTF==PERIOD_M1 ? GMMATrendingBuy()  : GMMAHalfCrossedBuy())
                  : (botTF==PERIOD_M1 ? GMMATrendingSell() : GMMAHalfCrossedSell());
               bool adxOk  = ADXStrong();
               bool volOk  = VolumeOK();
               if(!rsiOk || !macdOk || !sarOk || !gmmaOk || !adxOk || !volOk)
               {
                  Print("Entry blocked @ bar ", bar, " — RSI:", rsiOk, " MACD:", macdOk,
                        " SAR:", sarOk, " GMMA:", gmmaOk, " ADX:", adxOk, " Vol:", volOk);
                  // M1: give 2 extra bars after EMA cross to align filters before resetting.
                  // M15: reset immediately (wider candles give full confirmation per bar).
                  bool doReset = (botTF == PERIOD_M1) ? (bar > emaCrossBar + 3) : true;
                  if(doReset) { Print("Entry timeout. Reset to IDLE."); botState = STATE_IDLE; }
                  break;
               }
               bool opened = OpenTrade(maDir);
               if(opened)
               {
                  entryBar = bar;
                  if(emaArrived)
                  {
                     tpStartBar = emaCrossBar + 2;
                     botState   = STATE_IN_TRADE;
                  }
                  else
                  {
                     tpStartBar = entryBar + 2;
                     botState   = STATE_WAIT_EMA;
                  }
               }
            }
            break;
         }

         //--- In trade, watching for EMA confirmation
         case STATE_WAIT_EMA:
         {
            if((isBuy && emaCUp) || (!isBuy && emaCDn))
            {
               emaCrossBar = bar - 1;
               emaArrived  = true;
               tpStartBar  = emaCrossBar + 2;
               lastSignal += " +EMA";
               botState    = STATE_IN_TRADE;
               Print("EMA post-entry @ bar", emaCrossBar, " New TP start=", tpStartBar);
            }
            else if(bar > entryBar + 5)
            {
               botState = STATE_IN_TRADE;   // No EMA arrived, continue with original timing
            }
            ManageGridTP(bar);
            if(!HasPosition()) { botState=STATE_IDLE; emaArrived=false; }
            break;
         }

         //--- In trade: M1=scalper exit, M15=grid TP, H1=H1 SAR+MACD exit
         case STATE_IN_TRADE:
         {
            if(botTF == PERIOD_M1)
               ManageScalperExit(bar);
            else if(botTF == PERIOD_H1)
               ManageH1Exit(bar);
            else
               ManageGridTP(bar);
            // Edge case: position gone but state not reset inside manager
            if(!HasPosition() && botState == STATE_IN_TRADE)
            { botState=STATE_IDLE; emaArrived=false; }
            break;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| PANEL HELPERS                                                    |
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
//| CREATE PANEL (static layout)                                     |
//+------------------------------------------------------------------+
void CreatePanel()
{
   if(!InpShowPanel) return;
   int x = InpPanelX, y = InpPanelY;
   int w = 245, h = 408;

   // Background
   ObjRect("bg",     x,   y,   w,   h,   CLR_BG,    CLR_BORDER);
   // Title bar
   ObjRect("hdr",    x+1, y+1, w-2, 28, CLR_HDR,   CLR_BORDER);
   ObjLabel("title", x+10, y+9, "⚡ ScalpMaster Pro v3.3", CLR_TITLE, 9, "Consolas Bold");

   // Section: Account
   ObjRect("sgacct",  x+1,  y+35, w-2, 18, C'22,28,50');
   ObjLabel("sgacct_t",x+8, y+38, "ACCOUNT", CLR_GRAY, 7);

   ObjLabel("lbl_bal", x+8,  y+58, "Balance:",  CLR_GRAY, 8);
   ObjLabel("val_bal", x+120,y+58, "---",       CLR_WHITE, 8);
   ObjLabel("lbl_eq",  x+8,  y+74, "Equity:",   CLR_GRAY, 8);
   ObjLabel("val_eq",  x+120,y+74, "---",       CLR_WHITE, 8);
   ObjLabel("lbl_fm",  x+8,  y+90, "Free Marg:",CLR_GRAY, 8);
   ObjLabel("val_fm",  x+120,y+90, "---",       CLR_WHITE, 8);
   ObjLabel("lbl_lev", x+8,  y+106,"Leverage:", CLR_GRAY, 8);
   ObjLabel("val_lev", x+120,y+106,"---",       CLR_WHITE, 8);

   // Section: Bot Config
   ObjRect("sgcfg",   x+1, y+127, w-2, 18, C'22,28,50');
   ObjLabel("sgcfg_t",x+8, y+130, "BOT CONFIG", CLR_GRAY, 7);

   ObjLabel("lbl_sym", x+8, y+150, "Symbol:",   CLR_GRAY, 8);
   ObjLabel("val_sym", x+120,y+150, "---",      CLR_ACCENT, 8);
   ObjLabel("lbl_tf",  x+8, y+166, "Timeframe:",CLR_GRAY, 8);
   ObjLabel("val_tf",  x+120,y+166, "---",      CLR_YELLOW, 8);
   ObjLabel("lbl_ma",  x+8, y+182, "MA:",       CLR_GRAY, 8);
   ObjLabel("val_ma",  x+120,y+182, "---",      CLR_WHITE, 8);
   ObjLabel("lbl_rsi", x+8, y+198, "RSI:",      CLR_GRAY, 8);
   ObjLabel("val_rsi", x+120,y+198, "---",      CLR_WHITE, 8);
   ObjLabel("lbl_lot", x+8, y+214, "Lot Size:", CLR_GRAY, 8);
   ObjLabel("val_lot", x+120,y+214, "---",      CLR_WHITE, 8);
   ObjLabel("lbl_slm", x+8, y+230, "SL Risk:",   CLR_GRAY, 8);
   ObjLabel("val_slm", x+120,y+230, "---",       CLR_WHITE, 8);
   ObjLabel("lbl_flt", x+8, y+246, "Filters:",  CLR_GRAY, 8);
   ObjLabel("val_flt", x+120,y+246, "---",       CLR_WHITE, 8);

   // Section: Trade Status
   ObjRect("sgtrd",   x+1, y+267, w-2, 18, C'22,28,50');
   ObjLabel("sgtrd_t",x+8, y+270, "TRADE STATUS", CLR_GRAY, 7);

   ObjLabel("lbl_stat",x+8, y+290, "Status:",   CLR_GRAY, 8);
   ObjLabel("val_stat",x+120,y+290, "IDLE",     CLR_GRAY, 8);
   ObjLabel("lbl_sig", x+8, y+306, "Signal:",   CLR_GRAY, 8);
   ObjLabel("val_sig", x+120,y+306, "—",        CLR_WHITE, 8);
   ObjLabel("lbl_pnl", x+8, y+322, "P/L:",      CLR_GRAY, 8);
   ObjLabel("val_pnl", x+120,y+322, "---",      CLR_WHITE, 8);
   ObjLabel("lbl_grd", x+8, y+338, "Mode/Lvl:", CLR_GRAY, 8);
   ObjLabel("val_grd", x+120,y+338, "---",      CLR_WHITE, 8);

   // Section: Stats
   ObjRect("sgstat",  x+1, y+358, w-2, 18, C'22,28,50');
   ObjLabel("sgstat_t",x+8,y+361, "STATISTICS", CLR_GRAY, 7);

   ObjLabel("lbl_tot",x+8, y+381, "Trades:",   CLR_GRAY, 8);
   ObjLabel("val_tot",x+120,y+381, "0",        CLR_WHITE, 8);
   ObjLabel("lbl_wr", x+8, y+381, "",          CLR_GRAY, 8);
   ObjLabel("val_wr", x+148,y+381, "WR: --",   CLR_WHITE, 8);

   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| UPDATE PANEL (dynamic values)                                    |
//+------------------------------------------------------------------+
void UpdatePanel()
{
   if(!InpShowPanel) return;
   string cur = AcctInfo.Currency();
   // Account
   UpdateLabel("val_bal", DoubleToString(AcctInfo.Balance(),2)+" "+cur,      CLR_WHITE);
   UpdateLabel("val_eq",  DoubleToString(AcctInfo.Equity(),2)+" "+cur,       CLR_WHITE);
   UpdateLabel("val_fm",  DoubleToString(AcctInfo.FreeMargin(),2)+" "+cur,   CLR_WHITE);
   UpdateLabel("val_lev", "1:"+IntegerToString((int)AcctInfo.Leverage()),     CLR_YELLOW);
   // Config
   UpdateLabel("val_sym", _Symbol,               CLR_ACCENT);
   UpdateLabel("val_tf",  TFName(InpTimeframe),  CLR_YELLOW);
   UpdateLabel("val_ma",  IntegerToString(InpMAFast)+"/"+IntegerToString(InpMASlow)+
               "  EMA "+IntegerToString(InpEMAFast)+"/"+IntegerToString(InpEMASlow), CLR_WHITE);
   UpdateLabel("val_rsi", "P="+IntegerToString(GetRSIPeriod())+
               " B:"+DoubleToString(InpRSIMinBuy,0)+"-"+DoubleToString(InpRSIOB,0)+
               " S:"+DoubleToString(InpRSIOS,0)+"-"+DoubleToString(InpRSIMaxSell,0), CLR_WHITE);
   string lotInfo = InpAutoLot
      ? (DoubleToString(CalcLot(),2)+" auto ≥$"+DoubleToString(InpScaleBase,0)+"+$"+DoubleToString(InpScaleStep,0)+"/step")
      : (DoubleToString(InpMinLot,2)+" fixed");
   UpdateLabel("val_lot", lotInfo, CLR_WHITE);

   string slMode = InpUseSL
      ? "PIVOT S/R ±"+DoubleToString(InpPivotSLBuffer,0)+"pip (cap "+DoubleToString(InpSLHardCapPips,0)+"pip)"
      : "DISABLED";
   UpdateLabel("val_slm", slMode, InpUseSL ? CLR_ORANGE : CLR_RED);

   // Filter status — real-time indicator states
   bool fSar  = botState==STATE_IDLE ? true : (isBuy ? SARDirectionBuy()    : SARDirectionSell());
   bool fGmma = botState==STATE_IDLE ? true : (isBuy ? GMMAHalfCrossedBuy() : GMMAHalfCrossedSell());
   bool fAdx  = ADXStrong();
   bool fVol  = VolumeOK();
   string flt = string(fSar ?"SAR▲ ":"SAR✗ ") +
                string(fGmma?"GMP▲ ":"GMP✗ ") +
                string(fAdx ?"ADX▲ ":"ADX✗ ") +
                string(fVol ?"VOL▲" :"VOL✗");
   color fltClr = (fSar && fGmma && fAdx && fVol) ? CLR_GREEN : CLR_YELLOW;
   UpdateLabel("val_flt", flt, fltClr);

   // Trade status
   UpdateLabel("val_stat", botStatus, statusClr);
   UpdateLabel("val_sig",  lastSignal, CLR_WHITE);

   double pnl    = GetProfit();
   color pnlClr  = pnl > 0 ? CLR_GREEN : (pnl < 0 ? CLR_RED : CLR_GRAY);
   UpdateLabel("val_pnl", DoubleToString(pnl,2)+" "+cur, pnlClr);

   string modeStr;
   if(botTF == PERIOD_M1)
      modeStr = "SCALP Trail="+(beMoveDone?"SAR":"WAIT BE");
   else if(botTF == PERIOD_H1)
      modeStr = "H1 SAR+MACD BE="+(beMoveDone?"SET":"WAIT");
   else
      modeStr = "GRID "+IntegerToString(gridLevel)+"/"+IntegerToString(InpGridLevels);
   UpdateLabel("val_grd", modeStr, CLR_WHITE);

   // Stats
   double wr = statTotal > 0 ? (double)statWins/statTotal*100.0 : 0;
   UpdateLabel("val_tot", IntegerToString(statTotal), CLR_WHITE);
   UpdateLabel("val_wr",  "WR: "+DoubleToString(wr,1)+"%  PL: "+
               DoubleToString(statProfit,2)+" "+cur, wr>=50?CLR_GREEN:CLR_RED);

   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| REMOVE PANEL OBJECTS                                             |
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
   botTF = BotTFtoPeriod(InpTimeframe);
   SymInfo.Name(_Symbol);

   Trade.SetExpertMagicNumber(MAGIC);
   Trade.SetDeviationInPoints(20);
   Trade.SetTypeFilling(ORDER_FILLING_IOC);

   if(!InitIndicators()) return INIT_FAILED;

   Print("ScalpMaster Pro initialized. Symbol=", _Symbol,
         " TF=", TFName(InpTimeframe), " RSI=", GetRSIPeriod());

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
   IndicatorRelease(hEMAFast);
   IndicatorRelease(hEMASlow);
   IndicatorRelease(hRSI);
   IndicatorRelease(hMACD);
   if(hSAR      != INVALID_HANDLE) IndicatorRelease(hSAR);
   if(hADX      != INVALID_HANDLE) IndicatorRelease(hADX);
   if(hSAR_H1   != INVALID_HANDLE) IndicatorRelease(hSAR_H1);
   if(hMACD_Open!= INVALID_HANDLE) IndicatorRelease(hMACD_Open);
   for(int i = 0; i < 6; i++)
   {
      if(hGMMAShort[i] != INVALID_HANDLE) IndicatorRelease(hGMMAShort[i]);
      if(hGMMALong[i]  != INVALID_HANDLE) IndicatorRelease(hGMMALong[i]);
   }
   // hM15Fast/hM15Slow are INVALID_HANDLE — no release needed
   DestroyPanel();
}

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick()
{
   // Panel updates every tick
   if(InpShowPanel) UpdatePanel();

   // Logic runs only on new bar
   if(!IsNewBar()) return;
   ProcessBar(barCounter);
}
//+------------------------------------------------------------------+
