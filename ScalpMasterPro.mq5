//+------------------------------------------------------------------+
//|                     ScalpMaster Pro v2.0                        |
//|       M1 Scalper + M15 Grid — MACD/Volume/TF Filtered          |
//|      Metals (XAUUSD, XPTUSD) + Forex — MT5                     |
//+------------------------------------------------------------------+
#property copyright "ScalpMaster Pro"
#property version   "2.00"
#property description "Professional M1 scalper + M15 grid with MACD, volume and TF filters"

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
   BTF_M15 = 15   // 15 Minutes (Grid)
};

enum ENUM_BOT_STATE
{
   STATE_IDLE,
   STATE_MA_CROSS,
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

sinput string          _S4C_ = "─────── TF TREND FILTER (M1) ───────";
input  bool            InpUseTFFilter   = true;        // Use M15 trend filter (M1 only)

sinput string          _S5_ = "─────── RISK MANAGEMENT ───────";
input  bool            InpAutoLot     = true;          // Auto Lot by Balance
input  double          InpLotPer100   = 0.01;          // Lot per $100 balance
input  double          InpMinLot      = 0.01;          // Min Lot
input  double          InpMaxLot      = 5.0;           // Max Lot
input  bool            InpUseSL       = true;          // Enable Stop Loss
input  double          InpSLProtectUSD = 1.35;         // Max loss per trade (USD)
input  double          InpSLMinPips    = 5.0;          // Min SL distance (pips, floor)

sinput string          _S5B_ = "─────── SCALPER (M1) ───────";
input  double          InpScalpTPPips    = 5.0;        // Scalper TP in pips (M1)
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
int    hMACD;                  // MACD on botTF
int    hM15Fast, hM15Slow;    // SMA on M15 for trend filter (M1 mode only)

ENUM_TIMEFRAMES botTF;
ENUM_BOT_STATE  botState     = STATE_IDLE;

datetime        lastBarTime  = 0;
int             barCounter   = 0;

int             maCrossBar   = -1;
bool            maDir        = false;    // true=bullish
int             emaCrossBar  = -1;
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
      default:      return PERIOD_M1;
   }
}

string TFName(ENUM_BOT_TF tf)
{
   switch(tf)
   {
      case BTF_M1:  return "M1 (Scalper)";
      case BTF_M15: return "M15 (Grid)";
      default:      return "??";
   }
}

//+------------------------------------------------------------------+
//| LOT SIZING                                                       |
//+------------------------------------------------------------------+
double CalcLot()
{
   if(!InpAutoLot) return NormLot(InpLotPer100);
   double balance = AcctInfo.Balance();
   if(balance <= 0) return InpMinLot;
   double lot = MathFloor(balance / 100.0) * InpLotPer100;
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
//| STOP LOSS — fixed dollar risk (InpSLProtectUSD per trade)       |
//+------------------------------------------------------------------+
double CalcSL(bool buy, double entry)
{
   if(!InpUseSL) return 0;
   double pt       = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double tickVal  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double lot      = CalcLot();

   // Pip value = monetary value of 1 pip for current lot size
   double pipSize  = pt * 10.0;  // 1 pip = 10 points (5-digit brokers)
   double pipValue = (tickSize > 0) ? lot * tickVal * (pipSize / tickSize) : 0;

   // Pips needed to risk exactly InpSLProtectUSD
   double slPips = (pipValue > 0) ? InpSLProtectUSD / pipValue : InpSLMinPips;

   // Apply floor: broker minimum stops level + InpSLMinPips user floor
   long   stopsLvl = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double brokerMinPips = (double)(stopsLvl / 10 + 2);
   double minPips = MathMax(InpSLMinPips, brokerMinPips);
   slPips = MathMax(slPips, minPips);

   double slDist = slPips * pt * 10.0;
   double sl = buy ? entry - slDist : entry + slDist;
   return NormalizeDouble(sl, _Digits);
}

//+------------------------------------------------------------------+
//| INIT INDICATORS                                                  |
//+------------------------------------------------------------------+
bool InitIndicators()
{
   hMAFast  = iMA(_Symbol, botTF, InpMAFast,  0, MODE_SMA, PRICE_CLOSE);
   hMASlow  = iMA(_Symbol, botTF, InpMASlow,  0, MODE_SMA, PRICE_CLOSE);
   hEMAFast = iMA(_Symbol, botTF, InpEMAFast, 0, MODE_EMA, PRICE_CLOSE);
   hEMASlow = iMA(_Symbol, botTF, InpEMASlow, 0, MODE_EMA, PRICE_CLOSE);
   hRSI     = iRSI(_Symbol, botTF, GetRSIPeriod(), PRICE_CLOSE);
   hMACD    = iMACD(_Symbol, botTF, InpMACDFast, InpMACDSlow, InpMACDSignal, PRICE_CLOSE);

   // M15 trend filter handles — only used when running on M1
   if(botTF == PERIOD_M1 && InpUseTFFilter)
   {
      hM15Fast = iMA(_Symbol, PERIOD_M15, InpMAFast, 0, MODE_SMA, PRICE_CLOSE);
      hM15Slow = iMA(_Symbol, PERIOD_M15, InpMASlow, 0, MODE_SMA, PRICE_CLOSE);
      if(hM15Fast == INVALID_HANDLE || hM15Slow == INVALID_HANDLE)
      { Alert("ScalpMaster: Failed to create M15 filter handles!"); return false; }
   }
   else { hM15Fast = INVALID_HANDLE; hM15Slow = INVALID_HANDLE; }

   if(hMAFast  == INVALID_HANDLE ||
      hMASlow  == INVALID_HANDLE ||
      hEMAFast == INVALID_HANDLE ||
      hEMASlow == INVALID_HANDLE ||
      hRSI     == INVALID_HANDLE ||
      hMACD    == INVALID_HANDLE)
   {
      Alert("ScalpMaster: Failed to create indicator handles!");
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
//| M15 TREND FILTER — only active when botTF == M1                 |
//+------------------------------------------------------------------+
bool M15TrendOKBuy()
{
   if(!InpUseTFFilter || botTF != PERIOD_M1 || hM15Fast == INVALID_HANDLE) return true;
   double f[], s[];
   ArraySetAsSeries(f, true); ArraySetAsSeries(s, true);
   if(CopyBuffer(hM15Fast, 0, 0, 2, f) < 2) return true;
   if(CopyBuffer(hM15Slow, 0, 0, 2, s) < 2) return true;
   return f[1] > s[1];
}

bool M15TrendOKSell()
{
   if(!InpUseTFFilter || botTF != PERIOD_M1 || hM15Fast == INVALID_HANDLE) return true;
   double f[], s[];
   ArraySetAsSeries(f, true); ArraySetAsSeries(s, true);
   if(CopyBuffer(hM15Fast, 0, 0, 2, f) < 2) return true;
   if(CopyBuffer(hM15Slow, 0, 0, 2, s) < 2) return true;
   return f[1] < s[1];
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

   // M1 scalper: set hard TP in the order; M15 grid manages TP manually
   double tp = 0;
   if(botTF == PERIOD_M1)
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
//| CLOSE TRADE                                                      |
//+------------------------------------------------------------------+
bool CloseTrade()
{
   ulong t;
   if(!FindPosition(t)) { openLot=0; posTicket=0; return true; }
   double profit = GetProfit();
   if(!Trade.PositionClose(t, 20))
   { Print("CloseTrade failed: ", GetLastError()); return false; }
   statProfit += profit;
   if(profit > 0) statWins++;
   posTicket  = 0; openLot  = 0; gridLevel = 0; trailSL = 0; beMoveDone = false;
   botStatus  = "IDLE"; statusClr = CLR_GRAY;
   Print("Trade closed. Profit=", DoubleToString(profit,2));
   return true;
}

//+------------------------------------------------------------------+
//| UPDATE SL ON POSITION                                            |
//+------------------------------------------------------------------+
void UpdateSL(double sl)
{
   ulong t;
   if(!FindPosition(t)) return;
   PosInfo.SelectByTicket(t);
   double curSL = PosInfo.StopLoss();
   sl = NormalizeDouble(sl, _Digits);
   // Only move SL in favorable direction
   if(isBuy  && sl > curSL) Trade.PositionModify(t, sl, 0);
   if(!isBuy && sl < curSL) Trade.PositionModify(t, sl, 0);
}

//+------------------------------------------------------------------+
//| MANAGE SCALPER TP (M1 only)                                     |
//+------------------------------------------------------------------+
void ManageScalperTP(int bar)
{
   ulong t;
   if(!FindPosition(t))
   {
      // Position was auto-closed by MT5 (TP or SL hit) — recover stats from history
      if(HistorySelect(TimeCurrent() - 600, TimeCurrent()))
      {
         int deals = HistoryDealsTotal();
         for(int i = deals - 1; i >= 0; i--)
         {
            ulong dk = HistoryDealGetTicket(i);
            if(HistoryDealGetInteger(dk, DEAL_MAGIC)  == MAGIC &&
               HistoryDealGetInteger(dk, DEAL_ENTRY)  == DEAL_ENTRY_OUT)
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

   // Once minimum profit reached, move SL to breakeven + small buffer
   if(!beMoveDone && profit >= InpScalpMinProfit)
   {
      double pt  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double beSL = NormalizeDouble(entryPrice + (isBuy ? pt*2 : -pt*2), _Digits);
      UpdateSL(beSL);
      beMoveDone = true;
      Print("Scalper: SL → breakeven. Profit=", DoubleToString(profit,2));
   }
}

//+------------------------------------------------------------------+
//| MANAGE GRID TP (M15 only)                                       |
//+------------------------------------------------------------------+
void ManageGridTP(int bar)
{
   if(!HasPosition()) return;

   double profit   = GetProfit();
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
         //--- IDLE: detect MA cross
         case STATE_IDLE:
         {
            if(maCrossUp || mcDn)
            {
               maCrossBar = bar - 1;
               maDir      = maCrossUp;
               botState   = STATE_MA_CROSS;
               lastSignal = maCrossUp ? "MA CROSS ▲" : "MA CROSS ▼";
               emaArrived = false;
               emaCrossBar= -1;
               Print("MA Cross @ bar", maCrossBar, " ", maDir?"UP":"DOWN");
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
            int  emaMaxWait   = 5;

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
               bool rsiOk  = maDir ? RSIOKBuy()      : RSIOKSell();
               bool macdOk = maDir ? MACDOKBuy()     : MACDOKSell();
               bool tfOk   = maDir ? M15TrendOKBuy() : M15TrendOKSell();
               bool volOk  = VolumeOK();
               if(!rsiOk || !macdOk || !tfOk || !volOk)
               {
                  Print("Entry blocked — RSI:", rsiOk, " MACD:", macdOk,
                        " TF:", tfOk, " Vol:", volOk, ". Reset.");
                  botState = STATE_IDLE;
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

         //--- In trade: M1 uses scalper manager, M15 uses grid
         case STATE_IN_TRADE:
         {
            if(botTF == PERIOD_M1)
               ManageScalperTP(bar);
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
   ObjLabel("title", x+10, y+9, "⚡ ScalpMaster Pro v1.0", CLR_TITLE, 9, "Consolas Bold");

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
   UpdateLabel("val_lot", DoubleToString(CalcLot(),2)+" (auto="+
               (InpAutoLot?"YES":"NO")+")",                                   CLR_WHITE);

   string slMode = InpUseSL
      ? "$"+DoubleToString(InpSLProtectUSD,2)+" risk (min "+DoubleToString(InpSLMinPips,0)+"pip)"
      : "DISABLED";
   UpdateLabel("val_slm", slMode, InpUseSL ? CLR_ORANGE : CLR_RED);

   // Filter status
   bool fMacd = botState==STATE_IDLE ? true : (maDir ? MACDOKBuy() : MACDOKSell());
   bool fVol  = VolumeOK();
   bool fTF   = botState==STATE_IDLE ? true : (maDir ? M15TrendOKBuy() : M15TrendOKSell());
   string flt = string(fMacd?"MACD▲ ":"MACD✗ ") +
                string(fVol ?"VOL▲ " :"VOL✗ ") +
                string(fTF  ?"TF▲"   :"TF✗");
   color fltClr = (fMacd && fVol && fTF) ? CLR_GREEN : CLR_YELLOW;
   UpdateLabel("val_flt", flt, fltClr);

   // Trade status
   UpdateLabel("val_stat", botStatus, statusClr);
   UpdateLabel("val_sig",  lastSignal, CLR_WHITE);

   double pnl    = GetProfit();
   color pnlClr  = pnl > 0 ? CLR_GREEN : (pnl < 0 ? CLR_RED : CLR_GRAY);
   UpdateLabel("val_pnl", DoubleToString(pnl,2)+" "+cur, pnlClr);

   string modeStr = botTF==PERIOD_M1
      ? "SCALPER BE="+(beMoveDone?"SET":"WAIT")
      : "GRID "+IntegerToString(gridLevel)+"/"+IntegerToString(InpGridLevels);
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
   if(hM15Fast != INVALID_HANDLE) IndicatorRelease(hM15Fast);
   if(hM15Slow != INVALID_HANDLE) IndicatorRelease(hM15Slow);
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
