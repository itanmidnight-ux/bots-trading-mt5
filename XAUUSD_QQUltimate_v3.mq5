//+------------------------------------------------------------------+
//|  QUANTUM QUEEN INSPIRED — XAUUSD Adaptive Multi-Strategy EA      |
//|  v10.0 — Full regime-based rewrite                                |
//|                                                                   |
//|  Arquitectura 7 capas:                                            |
//|    L0  MTF Data Cache    (M1,M5,M6,M12,M15,M20,H1,D1)             |
//|    L1  Regime Detector   (TRENDING/RANGING/VOLATILE/MOMENTUM)     |
//|    L2  Strategy Activator (12 strats ON/OFF por regimen)          |
//|    L3  Entry Engine      (structure + candle confirmation)        |
//|    L4  Grid Manager      (ATR-spacing, trend strategies)          |
//|    L5  Exit Engine       (trailing / fixed TP / basket)           |
//|    L6  Risk & Protection (DD escalation, recovery, news)          |
//|    L7  Panel             (12 strats, regime, info account)        |
//|                                                                   |
//|  12 Estrategias adaptativas (sistema cerrado, sin parámetros):    |
//|    S1  Trend Follow M5      [TRENDING fuerte]                     |
//|    S2  Pullback EMA H1      [TRENDING]                            |
//|    S3  London ORB           [VOLATILE + 07-10 GMT]                |
//|    S4  NY Session           [VOLATILE + 13:30-17 GMT]             |
//|    S5  Asian Range          [RANGING + 22-04 GMT]                 |
//|    S6  Mean Reversion BB    [RANGING]                             |
//|    S7  Structure Break H1   [TRENDING->VOLATILE]                  |
//|    S8  PDH/PDL Breakout     [cualquier regimen, 07-15 GMT]        |
//|    S9  Momentum M15         [VOLATILE]                            |
//|    S10 Compression Break    [RANGING->VOLATILE]                   |
//|    S11 H1 Continuation      [TRENDING moderado]                   |
//|    S12 Volume Impulse       [MOMENTUM]                            |
//+------------------------------------------------------------------+
#property copyright "Quantum Queen Inspired v10.0"
#property version   "10.00"
#property strict

#include <Trade/Trade.mqh>
CTrade trade;

//====================================================================
//  ENUMS — Sistema cerrado
//====================================================================
enum ENUM_LOT_METHOD
{
   LOT_AUTOMATIC      = 0,   // Automatic (capital-mode driven)
   LOT_FIXED          = 1,   // Fixed lot
   LOT_FIXED_PER_BAL  = 2    // Fixed lot per X balance
};

enum ENUM_RISK_LEVEL
{
   RISK_VLOW   = 0,   // Very Low
   RISK_LOW    = 1,   // Low
   RISK_MED    = 2,   // Medium
   RISK_HIGH   = 3,   // High
   RISK_VHIGH  = 4    // Very High
};

enum ENUM_DD_MODE
{
   DD_OFF          = 0,   // OFF
   DD_PCT_CLOSE    = 1,   // [Pct.] Close all & CONTINUE
   DD_MONEY_ALERT  = 2    // [Money] Alert on Terminal
};

enum ENUM_BROKER_SET
{
   BSET_IC_MED   = 0,  // IC Markets/VT Markets (RAW) - MEDIUM RISK
   BSET_IC_LOW   = 1,  // IC Markets/VT Markets (RAW) - LOW RISK
   BSET_ROBO     = 2,  // RoboForex (ECN)
   BSET_FUSION   = 3   // Fusion Markets (Zero)
};

enum ENUM_REGIME
{
   REG_NEUTRAL    = 0,
   REG_TRENDING   = 1,
   REG_RANGING    = 2,
   REG_VOLATILE   = 3,
   REG_MOMENTUM   = 4
};

enum ENUM_STRAT_STATUS
{
   SSTAT_OFF       = 0,   // Strategy inactive (regime mismatch)
   SSTAT_AWAIT     = 1,   // Awaiting signals
   SSTAT_ANALYZING = 2,   // Analyzing structure
   SSTAT_ARMED     = 3,   // Confirmation imminent
   SSTAT_IN_TRADE  = 4    // Position open
};

enum ENUM_CAP_MODE
{
   CAP_MICRO      = 0,  // <$50
   CAP_SMALL      = 1,  // $50-$299
   CAP_MEDIUM     = 2,  // $300-$1499
   CAP_UPPER      = 3,  // $1500-$9999
   CAP_STANDARD   = 4   // $10000+
};

enum ENUM_OP_MODE
{
   OPMODE_GROWTH   = 0,  // <500 USD — alta precisión, compounding conservador
   OPMODE_STANDARD = 1   // >=500 USD — operación profesional normal
};

//====================================================================
//  INPUTS — Sistema cerrado (idéntico estructura panel real QQ)
//====================================================================
input group "==== GENERAL SETTINGS ===="
input bool              InpStartPaused      = false;     // Start EA Paused
input ENUM_LOT_METHOD   InpLotMethod        = LOT_AUTOMATIC; // Lot Calculation Method
input ENUM_RISK_LEVEL   InpRiskLevel        = RISK_MED;   // Auto Lots Risk Level
input double            InpFixedLot         = 0.01;       // Fixed
input double            InpFixedPerBal      = 500.0;      // Fixed per Balance
input ENUM_DD_MODE      InpDDMode           = DD_OFF;     // DD. Control Mode
input double            InpDDValue          = 0.0;        // DD. Value
input bool              InpPushNotif        = true;       // MQID Push Notif. [DD/TP/SL]
input int               InpMagic            = 1234;       // Magic Number
input int               InpMaxSpread        = 100;        // Max. Spread (Points)
input int               InpMaxSlippage      = 100;        // Max. Slippage (Points)
input bool              InpHolidayOff       = false;      // Holiday Trading Off (Dec 15-Jan 15)

input group "==== SETS & STRATEGIES ===="
input ENUM_BROKER_SET   InpBrokerSet        = BSET_IC_MED;// Sets

input group "==== PANEL & VISUAL SETTINGS ===="
input bool              InpShowPanel        = true;       // Show Panel
input string            InpPanelFont        = "Consolas"; // Panel Font
input int               InpPanelFontSize    = 8;          // Panel Font Size
input string            InpPanelComment     = "Quantum Queen MT5"; // Panel Comment
input ENUM_LINE_STYLE   InpLineStyle        = STYLE_DASHDOT; // Line Style
input int               InpLineWidth        = 2;          // Line Width
input color             InpTPColor          = clrLime;    // TP Line Color
input color             InpBEColor          = clrWhite;   // BE Line Color
input color             InpGridColor        = clrYellow;  // Grid Line Color

//====================================================================
//  CONSTANTES — Timeframes reales QQ
//====================================================================
#define NUM_TFS 8
const ENUM_TIMEFRAMES gTFs[NUM_TFS] = {
   PERIOD_M1, PERIOD_M5, PERIOD_M6, PERIOD_M12,
   PERIOD_M15, PERIOD_M20, PERIOD_H1, PERIOD_D1
};
const string gTFNames[NUM_TFS] = {
   "M1","M5","M6","M12","M15","M20","H1","D1"
};

#define NUM_STRATS 12
#define MAX_GRID_LAYERS 3
#define MAX_OPEN_POS 50

//====================================================================
//  INDICATOR HANDLES — 8 TFs, set completo por TF principal
//====================================================================
// EMAs por TF (fast=9, slow=21, trend=50, struct=200)
int hEMA9[NUM_TFS],  hEMA21[NUM_TFS], hEMA50[NUM_TFS], hEMA200[NUM_TFS];
int hRSI[NUM_TFS],   hATR[NUM_TFS],   hBB[NUM_TFS],    hMFI[NUM_TFS];
int hADX_H1, hADX_M15;
int hW1EMA10 = INVALID_HANDLE;   // Weekly bias handle (BUG-3 fix)


//====================================================================
//  MTF DATA CACHE — refrescada en cada tick si nueva barra
//====================================================================
struct TFData
{
   double ema9, ema21, ema50, ema200;
   double rsi, atr, mfi;
   double bbUp, bbMid, bbDn, bbWidth;
   double closeNow, openNow, highNow, lowNow;
   double close1, open1, high1, low1;       // barra cerrada [1]
   double close2, open2, high2, low2;       // barra [2]
   double swingH10, swingL10;               // swing high/low 10-bar (cacheado)
   datetime barTime;
   datetime prevBarTime;                    // detecta cambio de barra
   bool valid;
};
TFData g_tf[NUM_TFS];

double g_adxH1 = 0, g_adxM15 = 0;
double g_pdiH1 = 0, g_mdiH1 = 0;

// Cache ADX — solo refrescar en nuevo bar H1/M15
datetime g_adxH1LastBar  = 0;
datetime g_adxM15LastBar = 0;

// Flag de reconstrucción de posiciones
bool g_posTrackDirty = true;

// Throttle ManagePositions en tester — solo nuevo bar M1
datetime g_managePosLastBar = 0;

//====================================================================
//  REGIME STATE
//====================================================================
ENUM_REGIME g_regime         = REG_NEUTRAL;
ENUM_REGIME g_regimePrev     = REG_NEUTRAL;
datetime    g_regimeSince    = 0;
double      g_atrAvgM5       = 0;
double      g_bbWidthAvgM5   = 0;
bool        g_d1TrendUp      = false;
bool        g_d1TrendDn      = false;
bool        g_h1TrendUp      = false;
bool        g_h1TrendDn      = false;

//====================================================================
//  STRATEGY STATE — 12 estrategias
//====================================================================
struct StratState
{
   ENUM_STRAT_STATUS status;
   bool   activeRegime;        // habilitada por régimen actual
   string name;
   int    sigCode;             // 0=none,+1=long,-1=short
   ENUM_TIMEFRAMES entryTF;    // TF principal para bar-close gate
   datetime lastEntryTime;
   datetime lastBarFired;      // bar-time última entrada (evita re-fire mismo bar)
   int    winsToday, lossesToday;
   double pnlToday;
   int    posCount;            // posiciones abiertas de esta estrategia
   ulong  posTickets[MAX_GRID_LAYERS];
   int    gridLayers;          // capas grid actuales (0..MAX-1)
   bool   gridEnabled;         // strategy permite añadir capas via re-fire
   double avgEntry;
   double basketTPPct;         // % balance objetivo basket close (0=disabled)
   double rrRatio;             // RR ratio configurado (TP/SL)
   double slAtrMult;           // SL = ATR × este multiplicador
   // ── Entry quality fields (added for duplicate/quality fix) ────
   datetime lastSLTime;        // timestamp del último SL hit → cooldown
   int      lastSLDir;         // dirección del SL (+1=long, -1=short)
   int      sameDirectStreak;  // consecutivas en misma dirección hoy
};
StratState g_str[NUM_STRATS];

//====================================================================
//  POSITION TRACKING — un magic global, sub-magics codificados en comment
//====================================================================
struct PosTrack
{
   ulong  ticket;
   int    stratId;             // 0..11
   int    gridIdx;             // 0=base, 1..2=grid layers
   datetime openTime;
   double openPrice;
   double initialSL;
   bool   beMoved;
   bool   partial1Done;
   bool   partial2Done;
   double peakProfit;
};
PosTrack g_pos[MAX_OPEN_POS];
int      g_posCount = 0;

//====================================================================
//  GLOBAL STATE
//====================================================================
ENUM_CAP_MODE g_capMode      = CAP_MICRO;
double        g_riskPct      = 0.50;
double        g_dailyLossUSD = 0;
double        g_dailyProfitUSD = 0;
int           g_maxTradesDay = 6;
int           g_maxConcurrent = 2;
double        g_lotMultDD     = 1.0;
double        g_lotMultRecov  = 1.0;
int           g_ddLevel       = 0;
int           g_recovLevel    = 0;
int           g_consecLosses  = 0;
datetime      g_recovPauseUntil = 0;
double        g_peakBalance   = 0;
double        g_dayStartBal   = 0;
double        g_sessionStartEquity = 0;
int           g_tradesToday   = 0;
int           g_winsToday     = 0;
int           g_lossesToday   = 0;
datetime      g_lastDay       = 0;
bool          g_isTesting     = false;
bool          g_paused        = false;
bool          g_dayInvalid    = false;

// ── Capital Adaptive Operating Mode ──────────────────────────
ENUM_OP_MODE g_opMode           = OPMODE_GROWTH;
ENUM_OP_MODE g_opModePrev       = OPMODE_GROWTH;
double       g_growthCompound      = 0.0;    // compounding bonus (0..0.25)
bool         g_growthHarvested     = false;  // hard harvest (5%) — para entradas
bool         g_growthSoftHarvested = false;  // soft harvest (~3%) — reduce concurrent
double       g_growthHarvestUSD   = 0.0;   // daily harvest threshold USD (5%)

// ── Recovery Engine State ─────────────────────────────────────
bool     g_recovActive       = false;
int      g_recovStratId      = -1;
bool     g_recovIsLong       = false;
double   g_recovBaseLot      = 0.0;
double   g_recovAvgEntry     = 0.0;
double   g_recovBasketPeak   = 0.0;
int      g_recovLayerCount   = 0;
datetime g_recovLastLossTime = 0;
ulong    g_recovTickets[MAX_GRID_LAYERS];
bool     g_recovBEDone       = false;
bool     g_recovPartialDone  = false;

#define LOG(m)  if(!g_isTesting) Print(m)

//====================================================================
//  OnInit
//====================================================================
int OnInit()
{
   g_isTesting = (bool)MQLInfoInteger(MQL_TESTER);
   g_paused    = InpStartPaused;

   // Modo inicial basado en balance de inicio (sin histéresis — evita quedarse en GROWTH con $500)
   g_opMode = (AccountInfoDouble(ACCOUNT_BALANCE) >= 500.0) ? OPMODE_STANDARD : OPMODE_GROWTH;
   Print("[OpMode] Inicial: ", g_opMode == OPMODE_STANDARD ? "STANDARD" : "GROWTH",
         " | Balance: $", DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2));

   // Crear handles para todos los TFs
   for(int i=0; i<NUM_TFS; i++)
   {
      ENUM_TIMEFRAMES tf = gTFs[i];
      hEMA9[i]   = iMA(_Symbol, tf, 9,   0, MODE_EMA, PRICE_CLOSE);
      hEMA21[i]  = iMA(_Symbol, tf, 21,  0, MODE_EMA, PRICE_CLOSE);
      hEMA50[i]  = iMA(_Symbol, tf, 50,  0, MODE_EMA, PRICE_CLOSE);
      hEMA200[i] = iMA(_Symbol, tf, 200, 0, MODE_EMA, PRICE_CLOSE);
      hRSI[i]    = iRSI(_Symbol, tf, 14, PRICE_CLOSE);
      hATR[i]    = iATR(_Symbol, tf, 14);
      hBB[i]     = iBands(_Symbol, tf, 20, 0, 2.0, PRICE_CLOSE);
      hMFI[i]    = iMFI(_Symbol, tf, 14, VOLUME_TICK);

      if(hEMA9[i]==INVALID_HANDLE || hEMA21[i]==INVALID_HANDLE ||
         hEMA50[i]==INVALID_HANDLE || hEMA200[i]==INVALID_HANDLE ||
         hRSI[i]==INVALID_HANDLE || hATR[i]==INVALID_HANDLE ||
         hBB[i]==INVALID_HANDLE || hMFI[i]==INVALID_HANDLE)
      {
         Alert("QQ v10: Handle inválido TF=", gTFNames[i]);
         return INIT_FAILED;
      }
   }
   hADX_H1   = iADX(_Symbol, PERIOD_H1, 14);
   hADX_M15  = iADX(_Symbol, PERIOD_M15, 14);
   hW1EMA10  = iMA(_Symbol, PERIOD_W1, 10, 0, MODE_EMA, PRICE_CLOSE);
   if(hADX_H1==INVALID_HANDLE || hADX_M15==INVALID_HANDLE)
   {
      Alert("QQ v10: Handle ADX inválido");
      return INIT_FAILED;
   }
   // W1 EMA10 — no critico, fallo no detiene EA (BUG-3 fix)
   if(hW1EMA10 == INVALID_HANDLE)
      Print("[Warning] W1 EMA10 handle inválido — weekly bias filter desactivado");

   // Init strategy states — perfiles derivados de logs reales QQ:
   //   RR 0.67 (TP<SL) para mean-reversion / scalp tight  → alta WR
   //   RR 1.5  para session breakouts                     → balanceado
   //   RR 2.0+ para trend continuation                    → catch runners
   string names[NUM_STRATS] = {
      "Trend Follow M5", "Pullback EMA H1", "London ORB", "NY Session",
      "Asian Range", "Mean Reversion BB", "Structure Break H1", "PDH/PDL Breakout",
      "Momentum M15", "Compression Break", "H1 Continuation", "Volume Impulse"
   };
   ENUM_TIMEFRAMES entryTFs[NUM_STRATS] = {
      PERIOD_M5,  PERIOD_H1, PERIOD_M5,  PERIOD_M5,
      PERIOD_M5,  PERIOD_M5, PERIOD_H1,  PERIOD_M15,
      PERIOD_M15, PERIOD_M15,PERIOD_H1,  PERIOD_M6
   };
   // Grid stacking solo en estrategias trend-continuation
   // (replican el "trend-following grid" del QQ real, añaden capa
   //  cuando el movimiento confirma continuación).
   bool gridEnabled[NUM_STRATS] = {
      true,  true,  false, false,   // S1✓ S2✓ S3 S4 — ORB son one-shot
      false, false, true,  false,   // S5 S6 S7✓ S8  — mean rev y PDH no
      false, false, true,  false    // S9 S10 S11✓ S12 — spikes son one-shot
   };
   double rrRatios[NUM_STRATS] = {
      2.0, 2.0, 1.5, 1.5,
      0.67, 0.67, 2.2, 1.5,
      1.5, 1.8, 2.0, 1.5
   };
   double slMults[NUM_STRATS] = {
      1.5, 1.5, 1.3, 1.4,
      1.3, 1.2, 1.6, 1.5,
      1.5, 1.3, 1.5, 1.4
   };
   // basketTPPct: si la suma de capas alcanza X% del balance → cerrar todo
   // 0.0 = sin basket close (cada posición cierra en su TP/SL)
   double basketTPs[NUM_STRATS] = {
      1.5, 1.5, 0.0, 0.0,
      0.0, 0.0, 1.8, 0.0,
      0.0, 0.0, 1.8, 0.0
   };
   for(int s=0; s<NUM_STRATS; s++)
   {
      g_str[s].name        = names[s];
      g_str[s].status      = SSTAT_OFF;
      g_str[s].activeRegime= false;
      g_str[s].sigCode     = 0;
      g_str[s].entryTF     = entryTFs[s];
      g_str[s].lastEntryTime = 0;
      g_str[s].lastBarFired= 0;
      g_str[s].winsToday   = 0;
      g_str[s].lossesToday = 0;
      g_str[s].pnlToday    = 0;
      g_str[s].posCount    = 0;
      g_str[s].gridLayers  = 0;
      g_str[s].gridEnabled = gridEnabled[s];
      g_str[s].avgEntry         = 0;
      g_str[s].basketTPPct      = basketTPs[s];
      g_str[s].rrRatio          = rrRatios[s];
      g_str[s].slAtrMult        = slMults[s];
      g_str[s].lastSLTime       = 0;
      g_str[s].lastSLDir        = 0;
      g_str[s].sameDirectStreak = 0;
      for(int k=0; k<MAX_GRID_LAYERS; k++) g_str[s].posTickets[k] = 0;
   }

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpMaxSlippage);
   trade.SetTypeFilling(ORDER_FILLING_FOK);

   g_dayStartBal        = AccountInfoDouble(ACCOUNT_BALANCE);
   g_peakBalance        = g_dayStartBal;
   g_sessionStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   ApplyBrokerSet();
   DetectCapitalMode();
   DailyReset();

   LOG(StringFormat("QQ v10.0 init OK | Bal: $%.2f | Mode: %s | Magic: %d",
                    g_dayStartBal, CapModeStr(), InpMagic));
   return INIT_SUCCEEDED;
}

//====================================================================
//  OnDeinit
//====================================================================
void OnDeinit(const int reason)
{
   for(int i=0; i<NUM_TFS; i++)
   {
      if(hEMA9[i]   != INVALID_HANDLE) IndicatorRelease(hEMA9[i]);
      if(hEMA21[i]  != INVALID_HANDLE) IndicatorRelease(hEMA21[i]);
      if(hEMA50[i]  != INVALID_HANDLE) IndicatorRelease(hEMA50[i]);
      if(hEMA200[i] != INVALID_HANDLE) IndicatorRelease(hEMA200[i]);
      if(hRSI[i]    != INVALID_HANDLE) IndicatorRelease(hRSI[i]);
      if(hATR[i]    != INVALID_HANDLE) IndicatorRelease(hATR[i]);
      if(hBB[i]     != INVALID_HANDLE) IndicatorRelease(hBB[i]);
      if(hMFI[i]    != INVALID_HANDLE) IndicatorRelease(hMFI[i]);
   }
   if(hADX_H1   != INVALID_HANDLE) IndicatorRelease(hADX_H1);
   if(hADX_M15  != INVALID_HANDLE) IndicatorRelease(hADX_M15);
   if(hW1EMA10  != INVALID_HANDLE) IndicatorRelease(hW1EMA10);
   PanelClear();
   Comment("");
}

//====================================================================
//  OnTick — Orquestador 7 capas
//====================================================================
void OnTick()
{
   if(g_paused) { if(InpShowPanel) DrawPanel(); return; }
   if(IsHolidayTime() && InpHolidayOff)
   {
      if(InpShowPanel) DrawPanel();
      return;
   }

   CheckDayReset();
   DetectCapitalMode();
   DetectOpMode();
   RefreshPositionTracking();

   // L0 — MTF Data
   UpdateMTFData();

   // L1 — Regime
   UpdateRegime();
   UpdateNYRange();   // siempre construir rango NY hora 12, sin depender de régimen

   // L6 — Protección (DD/recovery antes de cualquier entrada)
   CheckDDEscalation();
   UpdateRecoveryEngine();
   CheckEquityCircuit();
   CheckGrowthHarvest();

   bool canTrade = !g_dayInvalid && g_recovLevel < 3 && !IsRecoveryPaused()
                   && !IsNewsTime() && !g_growthHarvested;

   // L2 — Activar estrategias por régimen
   ActivateStrategies();

   // L3 — Ejecutar estrategias activas
   if(canTrade) RunActiveStrategies();

   // Recovery grid layers (separate from normal entry)
   if(g_recovActive) RunRecoveryEngine();

   // L4 — Grid management (siempre, sea cual sea estado)
   ManageGrids();

   // L5 — Exit engine
   ManagePositions();
   if(g_recovActive) { RecovL4_ManageBasket(); RecovL5_ManageExits(); }
   CheckPreNewsExit();

   TrackClosedTrades();

   // L7 — Panel
   if(InpShowPanel) DrawPanel();
}

//====================================================================
//  OnTradeTransaction — log + invalidar caches al cerrar
//====================================================================
void OnTradeTransaction(const MqlTradeTransaction&  trans,
                        const MqlTradeRequest&      req,
                        const MqlTradeResult&       res)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(trans.deal == 0) return;
   if(!HistoryDealSelect(trans.deal)) return;
   g_posTrackDirty = true;   // fuerza reconstrucción en siguiente tick
   long deal_magic = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
   if(deal_magic != InpMagic) return;
   ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY)
   {
      double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
                    + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
                    + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
      string cmt = HistoryDealGetString(trans.deal, DEAL_COMMENT);
      int sId = ExtractStratId(cmt);
      if(sId >= 0 && sId < NUM_STRATS)
      {
         g_str[sId].pnlToday += profit;
         if(profit > 0) g_str[sId].winsToday++;
         else if(profit < 0) g_str[sId].lossesToday++;
      }
      if(profit > 0)
      {
         g_winsToday++; g_consecLosses = 0;
         if(sId >= 0 && sId < NUM_STRATS)
         {
            int dir = (HistoryDealGetInteger(trans.deal, DEAL_TYPE) == DEAL_TYPE_SELL) ? -1 : +1;
            if(g_str[sId].lastSLDir == dir) g_str[sId].sameDirectStreak++;
            else                            g_str[sId].sameDirectStreak = 1;
            g_str[sId].lastSLDir = dir;
         }
         if(g_recovActive && sId == g_recovStratId) ResetRecovery();
      }
      else if(profit < 0)
      {
         g_lossesToday++; g_consecLosses++;
         bool isLong = (HistoryDealGetInteger(trans.deal, DEAL_TYPE) == DEAL_TYPE_SELL);
         double dealLot = HistoryDealGetDouble(trans.deal, DEAL_VOLUME);
         // Registrar SL hit para cooldown por estrategia
         if(sId >= 0 && sId < NUM_STRATS)
         {
            g_str[sId].lastSLTime  = TimeCurrent();
            g_str[sId].lastSLDir   = isLong ? +1 : -1;  // dirección que perdió
            g_str[sId].sameDirectStreak = 0;
         }
         InitiateRecovery(sId, !isLong, dealLot);
      }
   }
}

//====================================================================
//  ============= LAYER 0 — MTF DATA CACHE =============
//  Optimización tester: CopyBuffer + iHigh/iLow solo en nuevo bar por TF.
//  En tester "Every tick" esto reduce ~5000x las llamadas a indicadores.
//====================================================================
void UpdateMTFData()
{
   double bU[],bM[],bD[],e9[],e21[],e50[],e200[],r[],a[],mf[];
   for(int i=0; i<NUM_TFS; i++)
   {
      ENUM_TIMEFRAMES tf = gTFs[i];
      // ── Detección de nuevo bar por TF ──────────────────────────
      datetime curBarTime = iTime(_Symbol, tf, 0);
      if(curBarTime == 0) { g_tf[i].valid = false; continue; }

      // Si el bar no cambió y ya tenemos datos válidos → saltar
      if(curBarTime == g_tf[i].prevBarTime && g_tf[i].valid) continue;

      // Nuevo bar — refrescar todo para este TF
      if(CopyBuffer(hEMA9[i],  0,0,1,e9)  <= 0) { g_tf[i].valid = false; continue; }
      if(CopyBuffer(hEMA21[i], 0,0,1,e21) <= 0) { g_tf[i].valid = false; continue; }
      if(CopyBuffer(hEMA50[i], 0,0,1,e50) <= 0) { g_tf[i].valid = false; continue; }
      if(CopyBuffer(hEMA200[i],0,0,1,e200)<= 0) { g_tf[i].valid = false; continue; }
      if(CopyBuffer(hRSI[i],   0,0,1,r)   <= 0) { g_tf[i].valid = false; continue; }
      if(CopyBuffer(hATR[i],   0,0,1,a)   <= 0) { g_tf[i].valid = false; continue; }
      if(CopyBuffer(hMFI[i],   0,0,1,mf)  <= 0) { g_tf[i].valid = false; continue; }
      if(CopyBuffer(hBB[i],    1,0,1,bU)  <= 0) { g_tf[i].valid = false; continue; }
      if(CopyBuffer(hBB[i],    0,0,1,bM)  <= 0) { g_tf[i].valid = false; continue; }
      if(CopyBuffer(hBB[i],    2,0,1,bD)  <= 0) { g_tf[i].valid = false; continue; }

      g_tf[i].ema9   = e9[0];
      g_tf[i].ema21  = e21[0];
      g_tf[i].ema50  = e50[0];
      g_tf[i].ema200 = e200[0];
      g_tf[i].rsi    = r[0];
      g_tf[i].atr    = a[0];
      g_tf[i].mfi    = mf[0];
      g_tf[i].bbUp   = bU[0];
      g_tf[i].bbMid  = bM[0];
      g_tf[i].bbDn   = bD[0];
      g_tf[i].bbWidth= bU[0] - bD[0];
      g_tf[i].closeNow = iClose(_Symbol, tf, 0);
      g_tf[i].openNow  = iOpen(_Symbol,  tf, 0);
      g_tf[i].highNow  = iHigh(_Symbol,  tf, 0);
      g_tf[i].lowNow   = iLow(_Symbol,   tf, 0);
      g_tf[i].close1   = iClose(_Symbol, tf, 1);
      g_tf[i].open1    = iOpen(_Symbol,  tf, 1);
      g_tf[i].high1    = iHigh(_Symbol,  tf, 1);
      g_tf[i].low1     = iLow(_Symbol,   tf, 1);
      g_tf[i].close2   = iClose(_Symbol, tf, 2);
      g_tf[i].open2    = iOpen(_Symbol,  tf, 2);
      g_tf[i].high2    = iHigh(_Symbol,  tf, 2);
      g_tf[i].low2     = iLow(_Symbol,   tf, 2);
      g_tf[i].barTime  = curBarTime;
      g_tf[i].prevBarTime = curBarTime;

      // Swing high/low 10 bars — cacheado aquí, no recalculado en estrategias
      double swH = 0, swL = DBL_MAX;
      for(int k=2; k<=11; k++)
      {
         double hi = iHigh(_Symbol, tf, k);
         double lo = iLow(_Symbol,  tf, k);
         if(hi > swH) swH = hi;
         if(lo < swL) swL = lo;
      }
      g_tf[i].swingH10 = swH;
      g_tf[i].swingL10 = (swL == DBL_MAX) ? 0 : swL;
      g_tf[i].valid    = true;
   }

   // ADX — solo refrescar en nuevo bar del TF correspondiente
   datetime h1Bar  = (TFIdx(PERIOD_H1) >= 0) ? g_tf[TFIdx(PERIOD_H1)].barTime : 0;
   datetime m15Bar = (TFIdx(PERIOD_M15) >= 0) ? g_tf[TFIdx(PERIOD_M15)].barTime : 0;
   double adxBuf[], pdiBuf[], mdiBuf[];
   if(h1Bar != g_adxH1LastBar && h1Bar != 0)
   {
      if(CopyBuffer(hADX_H1, 0,0,1,adxBuf) > 0) g_adxH1 = adxBuf[0];
      if(CopyBuffer(hADX_H1, 1,0,1,pdiBuf) > 0) g_pdiH1 = pdiBuf[0];
      if(CopyBuffer(hADX_H1, 2,0,1,mdiBuf) > 0) g_mdiH1 = mdiBuf[0];
      g_adxH1LastBar = h1Bar;
   }
   if(m15Bar != g_adxM15LastBar && m15Bar != 0)
   {
      if(CopyBuffer(hADX_M15,0,0,1,adxBuf) > 0) g_adxM15 = adxBuf[0];
      g_adxM15LastBar = m15Bar;
   }

   // Averages (EMA suavizada) — ATR M5 + BB Width M5
   int idxM5 = 1;
   if(g_tf[idxM5].valid)
   {
      double alpha = 2.0 / 21.0;
      if(g_atrAvgM5 <= 0) g_atrAvgM5 = g_tf[idxM5].atr;
      g_atrAvgM5 = g_atrAvgM5 + alpha * (g_tf[idxM5].atr - g_atrAvgM5);
      if(g_bbWidthAvgM5 <= 0) g_bbWidthAvgM5 = g_tf[idxM5].bbWidth;
      g_bbWidthAvgM5 = g_bbWidthAvgM5 + alpha * (g_tf[idxM5].bbWidth - g_bbWidthAvgM5);

   }
}

int TFIdx(ENUM_TIMEFRAMES tf)
{
   for(int i=0; i<NUM_TFS; i++) if(gTFs[i]==tf) return i;
   return -1;
}

//====================================================================
//  ============= LAYER 1 — REGIME DETECTOR =============
//====================================================================
void UpdateRegime()
{
   g_regimePrev = g_regime;
   int iM5  = TFIdx(PERIOD_M5);
   int iH1  = TFIdx(PERIOD_H1);
   int iD1  = TFIdx(PERIOD_D1);
   int iM15 = TFIdx(PERIOD_M15);
   if(iM5<0 || iH1<0 || iD1<0 || !g_tf[iM5].valid || !g_tf[iH1].valid || !g_tf[iD1].valid)
      return;

   // Bias D1/H1
   g_d1TrendUp = (g_tf[iD1].ema50 > g_tf[iD1].ema200);
   g_d1TrendDn = (g_tf[iD1].ema50 < g_tf[iD1].ema200);
   g_h1TrendUp = (g_tf[iH1].ema50 > g_tf[iH1].ema200) && (g_tf[iH1].rsi > 50);
   g_h1TrendDn = (g_tf[iH1].ema50 < g_tf[iH1].ema200) && (g_tf[iH1].rsi < 50);

   // Componentes régimen
   bool adxStrong   = (g_adxH1 > 25.0);
   bool adxWeak     = (g_adxH1 < 18.0);
   bool bbNarrow    = (g_bbWidthAvgM5 > 0 && g_tf[iM5].bbWidth < g_bbWidthAvgM5 * 0.70);
   bool atrSpike    = (g_atrAvgM5 > 0 && g_tf[iM5].atr > g_atrAvgM5 * 1.50);
   bool emaAligned  = (g_tf[iH1].ema9 > g_tf[iH1].ema21 && g_tf[iH1].ema21 > g_tf[iH1].ema50) ||
                      (g_tf[iH1].ema9 < g_tf[iH1].ema21 && g_tf[iH1].ema21 < g_tf[iH1].ema50);
   bool fastMomentum = (g_adxM15 > 28.0) && atrSpike;

   ENUM_REGIME newReg = REG_NEUTRAL;
   if(fastMomentum)                       newReg = REG_MOMENTUM;
   else if(atrSpike)                      newReg = REG_VOLATILE;
   else if(adxStrong && emaAligned)       newReg = REG_TRENDING;
   else if(adxWeak && bbNarrow)           newReg = REG_RANGING;
   else if(adxStrong)                     newReg = REG_TRENDING;
   else if(bbNarrow)                      newReg = REG_RANGING;
   else                                   newReg = REG_NEUTRAL;

   if(newReg != g_regime)
   {
      g_regime      = newReg;
      g_regimeSince = TimeCurrent();
   }
}


string RegimeStr()
{
   switch(g_regime)
   {
      case REG_TRENDING: return "TRENDING";
      case REG_RANGING:  return "RANGING";
      case REG_VOLATILE: return "VOLATILE";
      case REG_MOMENTUM: return "MOMENTUM";
   }
   return "NEUTRAL";
}

//====================================================================
//  ============= LAYER 2 — STRATEGY ACTIVATOR =============
//  Cada estrategia ON/OFF según régimen + sesión
//====================================================================
void ActivateStrategies()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   int hour = dt.hour;
   int hm   = hour*60 + dt.min;

   bool inLondon   = (hour >= 7  && hour < 12);
   bool inLonRange = (hour == 7);
   bool inLonTrade = (hour >= 8  && hour < 11);
   bool inNYRange  = (hour == 12);
   bool inNYTrade  = (hm >= 13*60+30 && hm < 17*60);
   bool inAsiaRng  = (hour >= 22 || hour < 1);
   bool inAsiaTrd  = (hour >= 1  && hour < 5);
   bool inPDHWind  = (hour >= 7  && hour < 15);

   // Régimen base
   ENUM_REGIME r = g_regime;

   // S1 Trend Follow — TRENDING fuerte
   g_str[0].activeRegime = (r == REG_TRENDING && g_adxH1 > 25);

   // S2 Pullback EMA — TRENDING
   g_str[1].activeRegime = (r == REG_TRENDING);

   // S3 London ORB — VOLATILE/TRENDING + sesión Londres
   g_str[2].activeRegime = ((r == REG_VOLATILE || r == REG_TRENDING || r == REG_MOMENTUM)
                            && (inLonRange || inLonTrade));

   // S4 NY Session — VOLATILE + sesión NY
   g_str[3].activeRegime = ((r == REG_VOLATILE || r == REG_TRENDING || r == REG_MOMENTUM)
                            && (inNYRange || inNYTrade));

   // S5 Asian Range — RANGING + sesión Asia
   g_str[4].activeRegime = ((r == REG_RANGING || r == REG_NEUTRAL)
                            && (inAsiaRng || inAsiaTrd));

   // S6 Mean Reversion BB — RANGING
   g_str[5].activeRegime = (r == REG_RANGING);

   // S7 Structure Break — TRENDING o transición
   g_str[6].activeRegime = (r == REG_TRENDING || r == REG_VOLATILE);

   // S8 PDH/PDL Breakout — siempre activo en ventana, incluyendo RANGING
   // BUG-4 FIX: PDH/PDL es más relevante en mercados ranging (niveles del día anterior
   // actúan como soporte/resistencia clave). Bloquear en RANGING era incorrecto.
   g_str[7].activeRegime = inPDHWind;

   // S9 Momentum M15 — VOLATILE/MOMENTUM
   g_str[8].activeRegime = (r == REG_VOLATILE || r == REG_MOMENTUM);

   // S10 Compression Break — transición RANGING->VOLATILE
   g_str[9].activeRegime = (r == REG_VOLATILE || r == REG_MOMENTUM
                            || (r == REG_RANGING && g_bbWidthAvgM5 > 0
                                && g_tf[TFIdx(PERIOD_M5)].bbWidth < g_bbWidthAvgM5 * 0.55));

   // S11 H1 Continuation — TRENDING moderado
   g_str[10].activeRegime = (r == REG_TRENDING && g_adxH1 >= 20 && g_adxH1 <= 32);

   // S12 Volume Impulse — MOMENTUM
   g_str[11].activeRegime = (r == REG_MOMENTUM
                             || (r == REG_VOLATILE && g_tf[TFIdx(PERIOD_M15)].mfi > 65));

   // Set status display
   for(int s=0; s<NUM_STRATS; s++)
   {
      if(!g_str[s].activeRegime)
      {
         if(g_str[s].posCount == 0) g_str[s].status = SSTAT_OFF;
         else                       g_str[s].status = SSTAT_IN_TRADE;
      }
      else
      {
         if(g_str[s].posCount > 0)      g_str[s].status = SSTAT_IN_TRADE;
         else                           g_str[s].status = SSTAT_AWAIT;
      }
   }
}

//====================================================================
//  =====  STRUCTURAL CONFIRMATION UTILITIES  =====
//  El bot NO entra en tick; espera:
//    1. Bar-close del TF de la estrategia
//    2. Confirmación estructural (swing break + candle close direccional)
//    3. "Strike confirmation" — segunda vela o break del extremo previo
//  Patrón derivado de logs reales QQ: entradas marcan xx:00, xx:05,
//  xx:15, xx:30, xx:45 → bar-close M5/M15 confirmado.
//====================================================================

// Bar-close gate por estrategia. Retorna true si hay NUEVO bar cerrado
// para la TF de la estrategia desde la última evaluación.
bool IsNewBarForStrat(int sId)
{
   int idx = TFIdx(g_str[sId].entryTF);
   if(idx < 0 || !g_tf[idx].valid) return false;
   datetime curBar = g_tf[idx].barTime;
   if(g_str[sId].lastBarFired == 0)
   {
      g_str[sId].lastBarFired = curBar;
      return false;   // primera vez, esperamos al siguiente bar
   }
   if(curBar != g_str[sId].lastBarFired)
      return true;
   return false;
}

// Marca la estrategia como evaluada en el bar actual.
void MarkStratBarConsumed(int sId)
{
   int idx = TFIdx(g_str[sId].entryTF);
   if(idx >= 0 && g_tf[idx].valid) g_str[sId].lastBarFired = g_tf[idx].barTime;
}

// Swing high/low — retorna valor cacheado en TFData.swingH10/swingL10.
// Calculado en UpdateMTFData solo cuando cambia el bar (no por tick).
double GetSwingHigh(ENUM_TIMEFRAMES tf, int lookback)
{
   int idx = TFIdx(tf);
   if(idx >= 0 && g_tf[idx].valid && g_tf[idx].swingH10 > 0)
      return g_tf[idx].swingH10;
   // Fallback: calculo directo si cache no disponible
   double hi = 0;
   for(int k=2; k<=MathMin(lookback,10)+1; k++)
      hi = MathMax(hi, iHigh(_Symbol, tf, k));
   return hi;
}
double GetSwingLow(ENUM_TIMEFRAMES tf, int lookback)
{
   int idx = TFIdx(tf);
   if(idx >= 0 && g_tf[idx].valid && g_tf[idx].swingL10 > 0)
      return g_tf[idx].swingL10;
   double lo = DBL_MAX;
   for(int k=2; k<=MathMin(lookback,10)+1; k++)
      lo = MathMin(lo, iLow(_Symbol, tf, k));
   return lo;
}

// Candle confirmation: la vela [1] cerró en dirección con cuerpo >= bodyMin del rango
// y >= atrMin del ATR. Growth Mode exige umbrales más altos para mayor winrate.
bool HasCandleConfirmation(ENUM_TIMEFRAMES tf, bool isBuy)
{
   int idx = TFIdx(tf);
   if(idx < 0 || !g_tf[idx].valid) return false;
   double o = g_tf[idx].open1, c = g_tf[idx].close1;
   double h = g_tf[idx].high1, l = g_tf[idx].low1;
   double range = h - l;
   if(range <= 0) return false;
   double body      = MathAbs(c - o);
   double bodyRatio = body / range;
   double atrRatio  = (g_tf[idx].atr > 0) ? (body / g_tf[idx].atr) : 0;
   // Growth Mode: 40% body ratio + 35% ATR — filtra señales débiles
   double minBody = (g_opMode == OPMODE_GROWTH) ? 0.40 : 0.30;
   double minATR  = (g_opMode == OPMODE_GROWTH) ? 0.35 : 0.25;
   if(bodyRatio < minBody || atrRatio < minATR) return false;
   return isBuy ? (c > o) : (c < o);
}

// Strike confirmation: la vela actual [0] está rompiendo el extremo
// de la vela [1] en dirección — confirma que el movimiento continúa.
// Esta es la "segunda confirmación" antes de disparar entrada.
bool HasStrikeConfirmation(ENUM_TIMEFRAMES tf, bool isBuy)
{
   int idx = TFIdx(tf);
   if(idx < 0 || !g_tf[idx].valid) return false;
   double cur = (isBuy)
                ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double buf = g_tf[idx].atr * 0.05;
   return isBuy ? (cur > g_tf[idx].high1 + buf)
                : (cur < g_tf[idx].low1  - buf);
}

// Structural break: el close [1] rompió swing extremo de últimas N barras.
bool HasStructuralBreak(ENUM_TIMEFRAMES tf, bool isBuy, int swingLookback=10)
{
   int idx = TFIdx(tf);
   if(idx < 0 || !g_tf[idx].valid) return false;
   if(isBuy)
   {
      double swH = GetSwingHigh(tf, swingLookback);
      return g_tf[idx].close1 > swH;
   }
   else
   {
      double swL = GetSwingLow(tf, swingLookback);
      return g_tf[idx].close1 < swL;
   }
}

// Weekly Bias — W1 EMA10 dirección para filtrar entradas contra tendencia semanal.
// Aplica en GROWTH non-MICRO y STANDARD. MICRO omite este filtro para maximizar entradas.
// Calcula EMA10 W1 dinámicamente: compara close W1[1] vs EMA10 W1[1].
// Retorna true si el trade está a favor del sesgo semanal (o si no hay sesgo claro).
bool WeeklyBiasOk(bool isBuy)
{
   // MICRO necesita máxima oportunidad — omitir filtro W1
   if(g_opMode == OPMODE_GROWTH && g_capMode == CAP_MICRO) return true;
   double wEMA10[1];
   if(hW1EMA10 == INVALID_HANDLE) return true;  // handle no disponible — no bloquear
   if(CopyBuffer(hW1EMA10, 0, 1, 1, wEMA10) <= 0) return true;
   double wClose = iClose(_Symbol, PERIOD_W1, 1);
   if(wClose <= 0 || wEMA10[0] <= 0) return true;
   bool weeklyUp = (wClose > wEMA10[0]);
   bool weeklyDn = (wClose < wEMA10[0]);
   // Sesgo neutro (dentro del 0.1% del EMA): ambas direcciones OK
   double pct = MathAbs(wClose - wEMA10[0]) / wEMA10[0];
   if(pct < 0.001) return true;
   if(isBuy  && weeklyDn) return false;   // long contra sesgo bajista semanal
   if(!isBuy && weeklyUp) return false;   // short contra sesgo alcista semanal
   return true;
}

// Pipeline maestro: combina los 3 filtros estructurales.
// GROWTH non-MICRO: exige D1 alignment + strike.
// MICRO en GROWTH: omite strike Y D1 — capital <$50 necesita máxima oportunidad de entrada.
bool ConfirmEntry(ENUM_TIMEFRAMES tf, bool isBuy, bool strikeRequired=true)
{
   if(!HasCandleConfirmation(tf, isBuy)) return false;
   bool microGrowth = (g_opMode == OPMODE_GROWTH && g_capMode == CAP_MICRO);
   // Strike: MICRO lo omite, no-MICRO GROWTH lo exige siempre
   bool needStrike  = strikeRequired || (g_opMode == OPMODE_GROWTH && !microGrowth);
   if(needStrike && !HasStrikeConfirmation(tf, isBuy)) return false;
   // D1 alignment: GROWTH non-MICRO lo exige; MICRO lo omite (prioridad: obtener trades)
   if(g_opMode == OPMODE_GROWTH && !microGrowth)
   {
      if(isBuy  && !g_d1TrendUp) return false;
      if(!isBuy && !g_d1TrendDn) return false;
   }
   // Weekly bias filter — bloquea trades contra W1 EMA10
   if(!WeeklyBiasOk(isBuy)) return false;
   return true;
}

// ─────────────────────────────────────────────────────────────────────
//  CheckEntryQuality — Filtro de calidad ADICIONAL antes de abrir posición.
//  Verifica 3 condiciones derivadas del análisis de trades perdedores:
//
//  1. COOLDOWN POST-SL: estrategia perdió en esta dirección recientemente
//     → esperar que el precio se aleje al menos 1 ATR (mercado "lavó" la stop)
//
//  2. MOMENTUM M5 ALIGNMENT: al menos 2 de las últimas 3 velas M5 deben
//     cerrar en la dirección del trade. Previene entradas contra micro-impulso.
//     (Fix para entradas "contra-tendencia" observadas en May-11: SELL con precio
//     subiendo de 4665→4688 — regimen decía SELL pero M5 mostraba rebote.)
//
//  3. STREAK BLOCK: si esta estrategia acumula 3+ trades seguidos en misma
//     dirección SIN ganar, necesita una vela H1 de confirmación adicional.
//     (Fix para May-15: 7 sells consecutivos — mercado claramente no cooperaba.)
// ─────────────────────────────────────────────────────────────────────
bool CheckEntryQuality(int sId, bool isBuy)
{
   int iM5 = TFIdx(PERIOD_M5);
   if(iM5 < 0 || !g_tf[iM5].valid) return true;  // sin datos → no bloquear
   double atr = g_tf[iM5].atr;

   // ── 1. Cooldown post-SL ──────────────────────────────────────────
   if(g_str[sId].lastSLTime > 0 && g_str[sId].lastSLDir != 0)
   {
      int slDir    = g_str[sId].lastSLDir;   // dirección que perdió: +1=long, -1=short
      int entryDir = isBuy ? +1 : -1;
      if(slDir == entryDir)                   // intentando re-entrar en misma dirección
      {
         // Calcular cuánto se ha movido el precio desde el SL
         double curPx = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                               : SymbolInfoDouble(_Symbol, SYMBOL_BID);
         // Necesitamos que el precio se haya alejado al menos 1 ATR
         // La "distancia" correcta depende de la dirección del trade original:
         // Si perdimos LONG: precio debió subir 1 ATR antes de re-intentar LONG
         // Si perdimos SHORT: precio debió bajar 1 ATR antes de re-intentar SHORT
         // (Precio "lavado" significa el mercado dio una oportunidad real nueva)
         datetime elapsed = TimeCurrent() - g_str[sId].lastSLTime;
         int minCooldownMin = 30;  // mínimo 30 min de cooldown absoluto
         if(elapsed < (datetime)(minCooldownMin * 60)) return false;
         // Después de 30 min: validar que precio se alejó 1 ATR (nueva oportunidad)
         // Proxy: verificar que el precio está "más lejos" del SL time
         // Si no podemos medir distancia exacta → usar ventana temporal fija de 2 H1 bars
         if(elapsed < (datetime)(120 * 60)) // < 2 horas: requiere también momentum claro
         {
            // Requiere que las últimas 2 velas M5 sean consistentes con la dirección
            bool c1ok = isBuy ? (g_tf[iM5].close1 > g_tf[iM5].open1)
                               : (g_tf[iM5].close1 < g_tf[iM5].open1);
            bool c2ok = isBuy ? (g_tf[iM5].close2 > g_tf[iM5].open2)
                               : (g_tf[iM5].close2 < g_tf[iM5].open2);
            if(!c1ok && !c2ok) return false;  // 2 velas M5 contrarias → no entrar
         }
      }
   }

   // ── 2. Momentum M5 alignment — mínimo 2 de 3 velas M5 en dirección ──
   {
      bool c1 = isBuy ? (g_tf[iM5].close1 > g_tf[iM5].open1)
                       : (g_tf[iM5].close1 < g_tf[iM5].open1);
      bool c2 = isBuy ? (g_tf[iM5].close2 > g_tf[iM5].open2)
                       : (g_tf[iM5].close2 < g_tf[iM5].open2);
      // c3: vela actual (en formación)
      bool c3 = isBuy ? (g_tf[iM5].closeNow > g_tf[iM5].openNow)
                       : (g_tf[iM5].closeNow < g_tf[iM5].openNow);
      int agree = (c1?1:0) + (c2?1:0) + (c3?1:0);
      // GROWTH non-MICRO: exige 2/3 velas M5 (mayor win rate)
      // MICRO o STANDARD: basta 1/3 — MICRO necesita máxima oportunidad de entrada
      bool isMicroGrowth = (g_opMode == OPMODE_GROWTH && g_capMode == CAP_MICRO);
      int minAgree = (g_opMode == OPMODE_GROWTH && !isMicroGrowth) ? 2 : 1;
      if(agree < minAgree) return false;
   }

   // ── 3. Streak block — 3+ consecutivos sin win en misma dir ────────
   if(g_str[sId].sameDirectStreak >= 3)
   {
      // Requiere vela H1 en dirección para continuar el streak
      int iH1 = TFIdx(PERIOD_H1);
      if(iH1 >= 0 && g_tf[iH1].valid)
      {
         bool h1ok = isBuy ? (g_tf[iH1].close1 > g_tf[iH1].open1 &&
                               g_tf[iH1].close1 > g_tf[iH1].ema21)
                            : (g_tf[iH1].close1 < g_tf[iH1].open1 &&
                               g_tf[iH1].close1 < g_tf[iH1].ema21);
         if(!h1ok) return false;
      }
   }

   return true;
}

// Decide si la estrategia puede añadir capa de grid (re-fire en mismo trade).
// Requisitos: grid enabled + misma dirección + base en profit (trend-following)
// + price movido al menos ATR×0.4 desde última capa (spacing dinámico).
bool CanAddGridLayer(int sId, bool isBuy)
{
   if(!g_str[sId].gridEnabled) return false;
   if(g_str[sId].posCount == 0) return false;
   if(g_str[sId].gridLayers >= MAX_GRID_LAYERS - 1) return false;
   if(isBuy && g_str[sId].sigCode <= 0) return false;
   if(!isBuy && g_str[sId].sigCode >= 0) return false;

   // Base trade en profit (trend-confirming layer)
   ulong baseT = g_str[sId].posTickets[0];
   if(!PositionSelectByTicket(baseT)) return false;
   double prof = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   if(prof <= 0) return false;

   // Spacing dinámico: precio actual debe estar a >= ATR×0.4 de la última capa
   int idx = TFIdx(g_str[sId].entryTF);
   if(idx < 0 || !g_tf[idx].valid) return false;
   double atr = g_tf[idx].atr;
   double lastPx = PositionGetDouble(POSITION_PRICE_OPEN);
   for(int k=1; k<=g_str[sId].gridLayers && k<MAX_GRID_LAYERS; k++)
   {
      if(PositionSelectByTicket(g_str[sId].posTickets[k]))
         lastPx = PositionGetDouble(POSITION_PRICE_OPEN);
   }
   double curPx = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                        : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double moveFav = isBuy ? (curPx - lastPx) : (lastPx - curPx);
   return moveFav >= atr * 0.4;
}

// Helper unificado: abre base o añade grid layer según estado.
// Sustituye llamadas directas a OpenTrade / AddGridLayer en cada estrategia.
bool EnterOrStackPosition(int sId, bool isBuy)
{
   if(g_str[sId].posCount == 0)
   {
      // Filtro calidad entrada — solo para posiciones base (no grid layers)
      if(!CheckEntryQuality(sId, isBuy)) return false;
      // Apertura base — usa RR y SL configurados en state struct
      double slMult = g_str[sId].slAtrMult;
      double tpMult = slMult * g_str[sId].rrRatio;
      return OpenTrade(sId, isBuy, g_str[sId].entryTF, slMult, tpMult);
   }
   else
   {
      if(!CanAddGridLayer(sId, isBuy)) return false;
      AddGridLayer(sId, isBuy);
      return true;
   }
}

//====================================================================
//  ============= LAYER 3 — 12 STRATEGY ENTRY ENGINE =============
//====================================================================
void RunActiveStrategies()
{
   // Daily/concurrent limits
   if(g_tradesToday >= g_maxTradesDay) return;
   if(CountAllOpen() >= g_maxConcurrent) return;
   if(!FilterSpread()) return;

   // FIX DUPLICADOS: Contador local de posiciones abiertas EN ESTE PASE.
   // Soluciona el bug donde CountAllOpen() no detecta la posición recién abierta
   // en el mismo tick (PositionsTotal() puede tener latencia de 1 tick en tester).
   // Combinamos CountAllOpen() REAL + openedThisPass para evitar doble entrada.
   int openedThisPass = 0;

   // Diseño régimen-dedicado: TODAS las estrategias activas por régimen
   // evalúan entrada SOLO en nuevo bar de su TF (no en cada tick) y
   // requieren confirmación estructural antes de abrir.
   // Si ya tienen posición abierta + grid habilitado: re-evalúan para
   // añadir capa (trend-following grid stacking observado en QQ real).
   for(int s=0; s<NUM_STRATS; s++)
   {
      if(!g_str[s].activeRegime) continue;
      if(CountAllOpen() + openedThisPass >= g_maxConcurrent) break;  // FIX DUPLICADOS
      // Bar-close gate por TF de la estrategia
      if(!IsNewBarForStrat(s)) continue;

      // Growth Mode: filtros adicionales de calidad
      if(g_opMode == OPMODE_GROWTH)
      {
         // ADX≥28 para estrategias trend (no MICRO — MICRO necesita máxima oportunidad)
         bool isTrendStrat = (s==0||s==1||s==6||s==10);
         if(isTrendStrat && g_capMode != CAP_MICRO && g_adxH1 < 28) { MarkStratBarConsumed(s); continue; }

         // Filtro de sesión alta probabilidad (solo non-MICRO):
         // HIGH: London 08-11 GMT + NY 13:30-17 GMT → todas las estrategias elegibles
         // LOW (resto): solo estrategias con gate de sesión propio (S3,S4,S5,S8)
         // MICRO omite este filtro — prioridad es obtener trades, no calidad de sesión
         if(g_capMode != CAP_MICRO)
         {
            MqlDateTime dtG; TimeToStruct(TimeCurrent(), dtG);
            int hG = dtG.hour, hmG = hG*60 + dtG.min;
            bool highSession = (hG >= 8 && hG < 11) || (hmG >= 13*60+30 && hmG < 17*60);
            bool isSessionGated = (s==2||s==3||s==4||s==7); // S3,S4,S5,S8 gestionan su sesión
            if(!highSession && !isSessionGated) { MarkStratBarConsumed(s); continue; }
         }
      }

      // Si tiene posición base, solo entra como grid layer
      bool isGridMode = (g_str[s].posCount > 0);
      if(isGridMode && !g_str[s].gridEnabled) { MarkStratBarConsumed(s); continue; }
      if(isGridMode && g_str[s].gridLayers >= MAX_GRID_LAYERS - 1) { MarkStratBarConsumed(s); continue; }

      bool opened = false;
      switch(s)
      {
         case 0:  opened = TryS1_TrendFollow();       break;
         case 1:  opened = TryS2_PullbackEMA();       break;
         case 2:  opened = TryS3_LondonORB();         break;
         case 3:  opened = TryS4_NYSession();         break;
         case 4:  opened = TryS5_AsianRange();        break;
         case 5:  opened = TryS6_MeanReversion();     break;
         case 6:  opened = TryS7_StructureBreak();    break;
         case 7:  opened = TryS8_PDHPDLBreak();       break;
         case 8:  opened = TryS9_MomentumM15();       break;
         case 9:  opened = TryS10_CompressionBreak(); break;
         case 10: opened = TryS11_H1Continuation();   break;
         case 11: opened = TryS12_VolumeImpulse();    break;
      }
      if(opened) openedThisPass++;   // FIX DUPLICADOS: contabilizar inmediatamente
      MarkStratBarConsumed(s);
   }
}

// ===================== S1 Trend Follow M5 =====================
bool TryS1_TrendFollow()
{
   int iM5 = TFIdx(PERIOD_M5); int iH1 = TFIdx(PERIOD_H1);
   if(iM5<0 || iH1<0 || !g_tf[iM5].valid || !g_tf[iH1].valid) return false;

   bool upH1   = (g_tf[iH1].ema9 > g_tf[iH1].ema21 && g_tf[iH1].ema21 > g_tf[iH1].ema50);
   bool dnH1   = (g_tf[iH1].ema9 < g_tf[iH1].ema21 && g_tf[iH1].ema21 < g_tf[iH1].ema50);
   bool upM5   = (g_tf[iM5].ema9 > g_tf[iM5].ema21 && g_tf[iM5].ema21 > g_tf[iM5].ema50);
   bool dnM5   = (g_tf[iM5].ema9 < g_tf[iM5].ema21 && g_tf[iM5].ema21 < g_tf[iM5].ema50);

   double cl1 = g_tf[iM5].close1;
   double op1 = g_tf[iM5].open1;
   bool bullCandle = (cl1 > op1) && MathAbs(cl1-op1) >= g_tf[iM5].atr * 0.30;
   bool bearCandle = (cl1 < op1) && MathAbs(cl1-op1) >= g_tf[iM5].atr * 0.30;

   // Pullback structure: low1 toca EMA21 M5 sin perforar EMA50
   bool buyPull  = upM5 && upH1 && bullCandle
                   && g_tf[iM5].low1  <= g_tf[iM5].ema21 + g_tf[iM5].atr*0.2
                   && cl1 > g_tf[iM5].ema21
                   && g_tf[iM5].rsi   > 45 && g_tf[iM5].rsi < 70;
   bool sellPull = dnM5 && dnH1 && bearCandle
                   && g_tf[iM5].high1 >= g_tf[iM5].ema21 - g_tf[iM5].atr*0.2
                   && cl1 < g_tf[iM5].ema21
                   && g_tf[iM5].rsi   < 55 && g_tf[iM5].rsi > 30;

   if(buyPull && ConfirmEntry(PERIOD_M5, true, false))
      return EnterOrStackPosition(0, true);
   if(sellPull && ConfirmEntry(PERIOD_M5, false, false))
      return EnterOrStackPosition(0, false);
   return false;
}

// ===================== S2 Pullback EMA H1 =====================
bool TryS2_PullbackEMA()
{
   int iH1 = TFIdx(PERIOD_H1); int iM15 = TFIdx(PERIOD_M15);
   if(iH1<0 || iM15<0 || !g_tf[iH1].valid || !g_tf[iM15].valid) return false;

   double cl1H = g_tf[iH1].close1;
   double op1H = g_tf[iH1].open1;
   double e20H = g_tf[iH1].ema21;

   bool inUp = g_h1TrendUp && (cl1H > g_tf[iH1].ema50);
   bool inDn = g_h1TrendDn && (cl1H < g_tf[iH1].ema50);

   bool touchUp = inUp && g_tf[iH1].low1  <= e20H && cl1H > e20H && cl1H > op1H
                  && g_tf[iM15].rsi > 50 && g_tf[iM15].close1 > g_tf[iM15].ema21;
   bool touchDn = inDn && g_tf[iH1].high1 >= e20H && cl1H < e20H && cl1H < op1H
                  && g_tf[iM15].rsi < 50 && g_tf[iM15].close1 < g_tf[iM15].ema21;

   if(touchUp && ConfirmEntry(PERIOD_H1, true, false))
      return EnterOrStackPosition(1, true);
   if(touchDn && ConfirmEntry(PERIOD_H1, false, false))
      return EnterOrStackPosition(1, false);
   return false;
}

// ===================== S3 London ORB =====================
double g_orbHi = 0, g_orbLo = DBL_MAX;
bool   g_orbBuilt = false;
datetime g_orbLastReset = 0;
bool   g_orbFiredLong = false, g_orbFiredShort = false;

bool TryS3_LondonORB()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   datetime today = g_lastDay;   // usa cache de CheckDayReset, evita iTime por tick
   if(today != g_orbLastReset)
   {
      g_orbLastReset = today;
      g_orbHi = 0; g_orbLo = DBL_MAX; g_orbBuilt = false;
      g_orbFiredLong = false; g_orbFiredShort = false;
   }

   int iM5 = TFIdx(PERIOD_M5); if(iM5<0 || !g_tf[iM5].valid) return false;

   // Build range 07:00-08:00
   if(dt.hour == 7)
   {
      g_orbHi = (g_orbHi == 0) ? g_tf[iM5].highNow : MathMax(g_orbHi, g_tf[iM5].highNow);
      g_orbLo = (g_orbLo == DBL_MAX) ? g_tf[iM5].lowNow : MathMin(g_orbLo, g_tf[iM5].lowNow);
      return false;
   }
   if(dt.hour == 8 && !g_orbBuilt)
   {
      double sz = (g_orbHi - g_orbLo) / _Point;
      if(sz >= 200 && sz <= 1200) g_orbBuilt = true;
   }
   if(!g_orbBuilt) return false;
   if(dt.hour > 10) return false;

   double buf = g_tf[iM5].atr * 0.15;
   double cl1 = g_tf[iM5].close1;
   bool breakUp = !g_orbFiredLong  && cl1 > g_orbHi + buf
                  && g_tf[iM5].close1 > g_tf[iM5].open1
                  && g_tf[iM5].ema9 > g_tf[iM5].ema21;
   bool breakDn = !g_orbFiredShort && cl1 < g_orbLo - buf
                  && g_tf[iM5].close1 < g_tf[iM5].open1
                  && g_tf[iM5].ema9 < g_tf[iM5].ema21;

   if(breakUp && ConfirmEntry(PERIOD_M5, true, false))
      { g_orbFiredLong  = true; return EnterOrStackPosition(2, true);  }
   if(breakDn && ConfirmEntry(PERIOD_M5, false, false))
      { g_orbFiredShort = true; return EnterOrStackPosition(2, false); }
   return false;
}

// ===================== S4 NY Session =====================
double g_nyHi = 0, g_nyLo = DBL_MAX;
bool   g_nyBuilt = false;
datetime g_nyLastReset = 0;
bool   g_nyFiredLong = false, g_nyFiredShort = false;

// Construye rango NY durante hora 12 — siempre, independiente de régimen activo
void UpdateNYRange()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   datetime today = g_lastDay;
   if(today != g_nyLastReset)
   {
      g_nyLastReset = today;
      g_nyHi = 0; g_nyLo = DBL_MAX; g_nyBuilt = false;
      g_nyFiredLong = false; g_nyFiredShort = false;
   }
   if(dt.hour != 12 && !(dt.hour == 13 && dt.min < 30)) return;
   int iM5 = TFIdx(PERIOD_M5);
   if(iM5 < 0 || !g_tf[iM5].valid) return;
   if(dt.hour == 12)
   {
      g_nyHi = (g_nyHi == 0) ? g_tf[iM5].highNow : MathMax(g_nyHi, g_tf[iM5].highNow);
      g_nyLo = (g_nyLo == DBL_MAX) ? g_tf[iM5].lowNow : MathMin(g_nyLo, g_tf[iM5].lowNow);
   }
   else if(dt.hour == 13 && dt.min < 30 && !g_nyBuilt)
   {
      double sz = (g_nyHi - g_nyLo) / _Point;
      if(sz >= 200 && sz <= 1500) g_nyBuilt = true;
   }
}

bool TryS4_NYSession()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   int iM5 = TFIdx(PERIOD_M5); if(iM5<0 || !g_tf[iM5].valid) return false;
   int hm  = dt.hour*60 + dt.min;

   if(!g_nyBuilt) return false;
   if(hm < 13*60+30 || hm >= 17*60) return false;

   double buf = g_tf[iM5].atr * 0.20;
   double cl1 = g_tf[iM5].close1;
   bool breakUp = !g_nyFiredLong  && cl1 > g_nyHi + buf
                  && g_tf[iM5].mfi > 55
                  && g_tf[iM5].rsi > 50;
   bool breakDn = !g_nyFiredShort && cl1 < g_nyLo - buf
                  && g_tf[iM5].mfi < 45
                  && g_tf[iM5].rsi < 50;

   if(breakUp && ConfirmEntry(PERIOD_M5, true, false))
      { g_nyFiredLong  = true; return EnterOrStackPosition(3, true);  }
   if(breakDn && ConfirmEntry(PERIOD_M5, false, false))
      { g_nyFiredShort = true; return EnterOrStackPosition(3, false); }
   return false;
}

// ===================== S5 Asian Range =====================
double g_asHi = 0, g_asLo = DBL_MAX;
bool   g_asBuilt = false;
datetime g_asLastReset = 0;
bool   g_asFiredLong = false, g_asFiredShort = false;

bool TryS5_AsianRange()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   datetime today = g_lastDay;
   if(today != g_asLastReset)
   {
      g_asLastReset = today;
      g_asHi = 0; g_asLo = DBL_MAX; g_asBuilt = false;
      g_asFiredLong = false; g_asFiredShort = false;
   }
   int iM5 = TFIdx(PERIOD_M5); if(iM5<0 || !g_tf[iM5].valid) return false;

   bool inRange = (dt.hour >= 22 || dt.hour < 1);
   bool inTrade = (dt.hour >= 1  && dt.hour < 5);

   if(inRange)
   {
      g_asHi = (g_asHi == 0) ? g_tf[iM5].highNow : MathMax(g_asHi, g_tf[iM5].highNow);
      g_asLo = (g_asLo == DBL_MAX) ? g_tf[iM5].lowNow : MathMin(g_asLo, g_tf[iM5].lowNow);
      return false;
   }
   if(inTrade && !g_asBuilt)
   {
      double sz = (g_asHi - g_asLo) / _Point;
      if(sz >= 200 && sz <= 1800) g_asBuilt = true;
   }
   if(!g_asBuilt || !inTrade) return false;

   double mid = (g_asHi + g_asLo) / 2.0;
   double cl1 = g_tf[iM5].close1;
   double buf = g_tf[iM5].atr * 0.18;
   bool breakUp = !g_asFiredLong  && cl1 > g_asHi + buf;
   bool breakDn = !g_asFiredShort && cl1 < g_asLo - buf;

   if(breakUp && ConfirmEntry(PERIOD_M5, true, false))
      { g_asFiredLong  = true; return EnterOrStackPosition(4, true);  }
   if(breakDn && ConfirmEntry(PERIOD_M5, false, false))
      { g_asFiredShort = true; return EnterOrStackPosition(4, false); }
   return false;
}

// ===================== S6 Mean Reversion BB =====================
bool TryS6_MeanReversion()
{
   int iM5 = TFIdx(PERIOD_M5); int iM15 = TFIdx(PERIOD_M15);
   if(iM5<0 || iM15<0 || !g_tf[iM5].valid || !g_tf[iM15].valid) return false;

   double cl1 = g_tf[iM5].close1;
   double hi1 = g_tf[iM5].high1;
   double lo1 = g_tf[iM5].low1;

   // Bounce from lower BB
   bool bounceUp = lo1 <= g_tf[iM5].bbDn && cl1 > g_tf[iM5].bbDn && cl1 > g_tf[iM5].open1
                   && g_tf[iM5].rsi < 35 && g_tf[iM15].rsi < 45;
   bool bounceDn = hi1 >= g_tf[iM5].bbUp && cl1 < g_tf[iM5].bbUp && cl1 < g_tf[iM5].open1
                   && g_tf[iM5].rsi > 65 && g_tf[iM15].rsi > 55;

   // Mean reversion: no requiere strike (no buscamos break), solo candle reversal
   if(bounceUp && ConfirmEntry(PERIOD_M5, true, false))   return EnterOrStackPosition(5, true);
   if(bounceDn && ConfirmEntry(PERIOD_M5, false, false))  return EnterOrStackPosition(5, false);
   return false;
}

// ===================== S7 Structure Break H1 =====================
bool TryS7_StructureBreak()
{
   int iH1 = TFIdx(PERIOD_H1); if(iH1<0 || !g_tf[iH1].valid) return false;
   // Detectar swing high/low últimas 20 barras H1
   double swingH = 0, swingL = DBL_MAX;
   for(int k=2; k<22; k++)
   {
      swingH = MathMax(swingH, iHigh(_Symbol, PERIOD_H1, k));
      swingL = MathMin(swingL, iLow(_Symbol,  PERIOD_H1, k));
   }
   double cl1 = g_tf[iH1].close1;
   double buf = g_tf[iH1].atr * 0.10;
   bool brkUp = cl1 > swingH + buf && g_h1TrendUp && g_tf[iH1].ema9 > g_tf[iH1].ema21;
   bool brkDn = cl1 < swingL - buf && g_h1TrendDn && g_tf[iH1].ema9 < g_tf[iH1].ema21;

   if(brkUp && ConfirmEntry(PERIOD_H1, true, false))
      return EnterOrStackPosition(6, true);
   if(brkDn && ConfirmEntry(PERIOD_H1, false, false))
      return EnterOrStackPosition(6, false);
   return false;
}

// ===================== S8 PDH/PDL Breakout =====================
bool TryS8_PDHPDLBreak()
{
   double pdh = iHigh(_Symbol, PERIOD_D1, 1);
   double pdl = iLow(_Symbol,  PERIOD_D1, 1);
   int iM15 = TFIdx(PERIOD_M15); if(iM15<0 || !g_tf[iM15].valid) return false;

   double cl1 = g_tf[iM15].close1;
   double buf = g_tf[iM15].atr * 0.15;
   bool brkUp = cl1 > pdh + buf && g_tf[iM15].close1 > g_tf[iM15].open1 && g_tf[iM15].rsi > 50;
   bool brkDn = cl1 < pdl - buf && g_tf[iM15].close1 < g_tf[iM15].open1 && g_tf[iM15].rsi < 50;

   if(brkUp && ConfirmEntry(PERIOD_M15, true, false))   return EnterOrStackPosition(7, true);
   if(brkDn && ConfirmEntry(PERIOD_M15, false, false))  return EnterOrStackPosition(7, false);
   return false;
}

// ===================== S9 Momentum M15 =====================
bool TryS9_MomentumM15()
{
   int iM15 = TFIdx(PERIOD_M15); int iH1 = TFIdx(PERIOD_H1);
   if(iM15<0 || iH1<0 || !g_tf[iM15].valid || !g_tf[iH1].valid) return false;

   double range = g_tf[iM15].high1 - g_tf[iM15].low1;
   double body  = MathAbs(g_tf[iM15].close1 - g_tf[iM15].open1);
   bool bigBody = (g_tf[iM15].atr > 0) && (range > g_tf[iM15].atr * 1.2) && (body / MathMax(range,_Point) > 0.55);

   bool spikeUp = bigBody && g_tf[iM15].close1 > g_tf[iM15].open1
                  && g_tf[iM15].rsi > 60 && g_tf[iH1].rsi > 50;
   bool spikeDn = bigBody && g_tf[iM15].close1 < g_tf[iM15].open1
                  && g_tf[iM15].rsi < 40 && g_tf[iH1].rsi < 50;

   // Momentum spike: la vela [1] ya es bigBody, no requiere strike adicional
   if(spikeUp && ConfirmEntry(PERIOD_M15, true, false))   return EnterOrStackPosition(8, true);
   if(spikeDn && ConfirmEntry(PERIOD_M15, false, false))  return EnterOrStackPosition(8, false);
   return false;
}

// ===================== S10 Compression Break =====================
bool TryS10_CompressionBreak()
{
   int iM15 = TFIdx(PERIOD_M15); if(iM15<0 || !g_tf[iM15].valid) return false;
   // BB squeeze previo: width actual mucho menor que media
   if(g_bbWidthAvgM5 <= 0) return false;
   double curW = g_tf[iM15].bbWidth;
   bool squeezed = (curW < g_bbWidthAvgM5 * 0.55);
   // No queremos seguir en squeeze — necesitamos expansión
   if(squeezed) return false;

   double cl1 = g_tf[iM15].close1;
   bool brkUp = cl1 > g_tf[iM15].bbUp && g_tf[iM15].rsi > 55;
   bool brkDn = cl1 < g_tf[iM15].bbDn && g_tf[iM15].rsi < 45;

   if(brkUp && ConfirmEntry(PERIOD_M15, true, false))   return EnterOrStackPosition(9, true);
   if(brkDn && ConfirmEntry(PERIOD_M15, false, false))  return EnterOrStackPosition(9, false);
   return false;
}

// ===================== S11 H1 Continuation =====================
bool TryS11_H1Continuation()
{
   int iH1 = TFIdx(PERIOD_H1); int iM12 = TFIdx(PERIOD_M12);
   if(iH1<0 || iM12<0 || !g_tf[iH1].valid || !g_tf[iM12].valid) return false;

   bool inUp  = g_h1TrendUp && g_tf[iH1].close1 > g_tf[iH1].ema21;
   bool inDn  = g_h1TrendDn && g_tf[iH1].close1 < g_tf[iH1].ema21;

   // Continuación: 2 velas H1 cerrando en dirección + M12 confirmando
   double cl1 = g_tf[iH1].close1;
   double cl2 = g_tf[iH1].close2;
   bool contUp = inUp && cl1 > cl2 && g_tf[iH1].close1 > g_tf[iH1].open1
                 && g_tf[iM12].close1 > g_tf[iM12].ema21
                 && g_tf[iM12].rsi > 50;
   bool contDn = inDn && cl1 < cl2 && g_tf[iH1].close1 < g_tf[iH1].open1
                 && g_tf[iM12].close1 < g_tf[iM12].ema21
                 && g_tf[iM12].rsi < 50;

   if(contUp && ConfirmEntry(PERIOD_H1, true, false))
      return EnterOrStackPosition(10, true);
   if(contDn && ConfirmEntry(PERIOD_H1, false, false))
      return EnterOrStackPosition(10, false);
   return false;
}

// ===================== S12 Volume Impulse =====================
bool TryS12_VolumeImpulse()
{
   int iM6 = TFIdx(PERIOD_M6); int iM20 = TFIdx(PERIOD_M20);
   if(iM6<0 || iM20<0 || !g_tf[iM6].valid || !g_tf[iM20].valid) return false;

   bool mfiSpikeUp = g_tf[iM6].mfi > 75 && g_tf[iM20].mfi > 55;
   bool mfiSpikeDn = g_tf[iM6].mfi < 25 && g_tf[iM20].mfi < 45;

   bool impUp = mfiSpikeUp && g_tf[iM6].close1 > g_tf[iM6].open1
                && g_tf[iM6].ema9 > g_tf[iM6].ema21;
   bool impDn = mfiSpikeDn && g_tf[iM6].close1 < g_tf[iM6].open1
                && g_tf[iM6].ema9 < g_tf[iM6].ema21;

   if(impUp && ConfirmEntry(PERIOD_M6, true, false))   return EnterOrStackPosition(11, true);
   if(impDn && ConfirmEntry(PERIOD_M6, false, false))  return EnterOrStackPosition(11, false);
   return false;
}


//====================================================================
//  ============= LAYER 4 — GRID MANAGER =============
//  Diseño QQ-real:
//   - Capas se añaden via bar-close re-fire en RunActiveStrategies()
//     (no aquí — esto evita inconsistencia de timing entre detección
//     y apertura).
//   - Este módulo SOLO gestiona basket close cuando el conjunto de
//     posiciones alcanza objetivo combinado (% balance).
//   - SL individuales por capa siguen activos como protección.
//====================================================================
void ManageGrids()
{
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   for(int s=0; s<NUM_STRATS; s++)
   {
      if(g_str[s].basketTPPct <= 0) continue;
      if(g_str[s].posCount < 2)     continue;   // 1 pos = no es basket
      double basketPL = BasketPnL(s);
      double basketTgt = bal * g_str[s].basketTPPct / 100.0;
      if(basketPL >= basketTgt) CloseStratPositions(s);
   }
}

// Añadir capa de grid — ATR-based, mismo lote, comment-encoded.
// Llamado desde EnterOrStackPosition() cuando posCount > 0.
void AddGridLayer(int sId, bool isLong)
{
   double price = isLong ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                         : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   int idx = TFIdx(g_str[sId].entryTF);
   if(idx < 0 || !g_tf[idx].valid) return;
   double atr  = g_tf[idx].atr;
   double slM  = g_str[sId].slAtrMult;
   double tpM  = slM * g_str[sId].rrRatio;
   double sl   = isLong ? price - atr*slM : price + atr*slM;
   double tp   = isLong ? price + atr*tpM : price - atr*tpM;
   double lot  = CalcLot(MathAbs(price - sl));   // mismo lote que base, no martingale
   if(lot <= 0) return;

   string cmt = StringFormat("S%d-G%d", sId+1, g_str[sId].gridLayers+1);
   bool ok = isLong ? trade.Buy(lot, _Symbol, price, sl, tp, cmt)
                    : trade.Sell(lot, _Symbol, price, sl, tp, cmt);
   if(ok)
   {
      ulong newT = trade.ResultOrder();
      int layer  = g_str[sId].gridLayers + 1;
      if(layer < MAX_GRID_LAYERS) g_str[sId].posTickets[layer] = newT;
      g_str[sId].gridLayers = layer;
      g_str[sId].posCount   = g_str[sId].gridLayers + 1;
   }
}

//====================================================================
//  ============= LAYER 5 — EXIT ENGINE =============
//====================================================================
void ManagePositions()
{
   if(g_isTesting)
   {
      datetime m1Bar = iTime(_Symbol, PERIOD_M1, 0);
      if(m1Bar == g_managePosLastBar) return;
      g_managePosLastBar = m1Bar;
   }
   int total = PositionsTotal();
   for(int i=total-1; i>=0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      int sId = ExtractStratId(PositionGetString(POSITION_COMMENT));
      bool isLong = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double opPx = PositionGetDouble(POSITION_PRICE_OPEN);
      double slPx = PositionGetDouble(POSITION_SL);
      double curPx= isLong ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                           : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double slDist= MathAbs(opPx - slPx);
      if(slDist <= 0) continue;
      double rMove = isLong ? (curPx - opPx) / slDist : (opPx - curPx) / slDist;

      // 1. Break-even at 0.8R
      if(rMove >= 0.8)
      {
         double newSL = isLong ? opPx + slDist*0.05 : opPx - slDist*0.05;
         if(isLong  && (slPx < opPx || slPx == 0)) trade.PositionModify(t, newSL, PositionGetDouble(POSITION_TP));
         if(!isLong && (slPx > opPx || slPx == 0)) trade.PositionModify(t, newSL, PositionGetDouble(POSITION_TP));
      }

      // 2. Partial close 50% at 1R
      bool isGridLayer = StringFind(PositionGetString(POSITION_COMMENT), "-G") >= 0;
      if(!isGridLayer && rMove >= 1.0 && !IsPartialDone(t, 1))
      {
         double vol = PositionGetDouble(POSITION_VOLUME);
         double half = NormalizeLot(vol * 0.50);
         if(half > 0 && half < vol) { trade.PositionClosePartial(t, half); MarkPartial(t, 1); }
      }

      // 3. Trailing ATR a partir de 1.2R (trend strategies)
      bool isTrendStrat = (sId == 0 || sId == 1 || sId == 6 || sId == 10);
      if(isTrendStrat && rMove >= 1.2)
      {
         int iM5 = TFIdx(PERIOD_M5);
         double atr = g_tf[iM5].atr;
         double newSL = isLong ? curPx - atr*1.5 : curPx + atr*1.5;
         double curSL = PositionGetDouble(POSITION_SL);
         if(isLong  && (newSL > curSL)) trade.PositionModify(t, newSL, PositionGetDouble(POSITION_TP));
         if(!isLong && (newSL < curSL || curSL == 0)) trade.PositionModify(t, newSL, PositionGetDouble(POSITION_TP));
      }

      // 4. Time-based exit (max barras según TF estrategia)
      datetime oTime = (datetime)PositionGetInteger(POSITION_TIME);
      int barsOpen = (int)((TimeCurrent() - oTime) / 60); // minutos
      int maxMin = StratMaxMinutes(sId);
      if(barsOpen > maxMin && rMove < 0.5)
      {
         trade.PositionClose(t);
      }
   }

   // Basket close se hace en ManageGrids() — usa g_str[s].basketTPPct
}

int StratMaxMinutes(int sId)
{
   // Estrategias de mayor TF → más tiempo
   switch(sId)
   {
      case 0: return 240;    // S1 M5
      case 1: return 480;    // S2 H1
      case 2: return 180;    // S3 ORB M5
      case 3: return 180;    // S4 NY M5
      case 4: return 240;    // S5 Asia M5
      case 5: return 90;     // S6 BB M5
      case 6: return 600;    // S7 H1
      case 7: return 240;    // S8 PDH M15
      case 8: return 240;    // S9 M15
      case 9: return 180;    // S10 M15
      case 10: return 480;   // S11 H1
      case 11: return 90;    // S12 M6
   }
   return 180;
}

bool IsPartialDone(ulong t, int level)
{
   for(int i=0; i<g_posCount; i++)
   {
      if(g_pos[i].ticket == t)
         return (level == 1) ? g_pos[i].partial1Done : g_pos[i].partial2Done;
   }
   return false;
}

void MarkPartial(ulong t, int level)
{
   for(int i=0; i<g_posCount; i++)
   {
      if(g_pos[i].ticket == t)
      {
         if(level == 1) g_pos[i].partial1Done = true;
         else           g_pos[i].partial2Done = true;
         return;
      }
   }
}

double BasketPnL(int sId)
{
   double pnl = 0;
   for(int k=0; k<MAX_GRID_LAYERS; k++)
   {
      ulong t = g_str[sId].posTickets[k];
      if(t == 0) continue;
      if(PositionSelectByTicket(t))
         pnl += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   }
   return pnl;
}

void CloseStratPositions(int sId)
{
   for(int k=0; k<MAX_GRID_LAYERS; k++)
   {
      ulong t = g_str[sId].posTickets[k];
      if(t == 0) continue;
      if(PositionSelectByTicket(t)) trade.PositionClose(t);
      g_str[sId].posTickets[k] = 0;
   }
   g_str[sId].gridLayers = 0;
   g_str[sId].posCount   = 0;
}

//====================================================================
//  ============= LAYER 6 — RISK & PROTECTION =============
//====================================================================
void DetectCapitalMode()
{
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAdj = RiskLevelMult();
   if(bal < 50.0)
   {
      g_capMode = CAP_MICRO;
      g_riskPct = 0.50 * riskAdj;
      g_maxTradesDay = 5; g_maxConcurrent = 2;
      g_dailyLossUSD = bal * 0.05; g_dailyProfitUSD = bal * 0.15;
   }
   else if(bal < 300.0)
   {
      g_capMode = CAP_SMALL;
      g_riskPct = 0.60 * riskAdj;
      g_maxTradesDay = 7; g_maxConcurrent = 3;
      g_dailyLossUSD = bal * 0.04; g_dailyProfitUSD = bal * 0.14;
   }
   else if(bal < 1500.0)
   {
      g_capMode = CAP_MEDIUM;
      g_riskPct = 0.70 * riskAdj;
      g_maxTradesDay = 10; g_maxConcurrent = 4;
      g_dailyLossUSD = bal * 0.04; g_dailyProfitUSD = bal * 0.12;
   }
   else if(bal < 10000.0)
   {
      g_capMode = CAP_UPPER;
      g_riskPct = 0.80 * riskAdj;
      g_maxTradesDay = 12; g_maxConcurrent = 5;
      g_dailyLossUSD = bal * 0.04; g_dailyProfitUSD = bal * 0.10;
   }
   else
   {
      g_capMode = CAP_STANDARD;
      g_riskPct = 1.00 * riskAdj;
      g_maxTradesDay = 15; g_maxConcurrent = 6;
      g_dailyLossUSD = bal * 0.04; g_dailyProfitUSD = bal * 0.10;
   }

   // ── GROWTH MODE: progresión por hitos de capital ──────────────────
   if(g_opMode == OPMODE_GROWTH)
   {
      // Riesgo y límites escalan con el balance — más capital = más capacidad operativa
      double growthRiskMult; int growthMaxConc; int growthMaxTrades;
      if(bal < 50.0)       { growthRiskMult = 0.65; growthMaxConc = 1; growthMaxTrades = 4; }
      else if(bal < 100.0) { growthRiskMult = 0.68; growthMaxConc = 1; growthMaxTrades = 5; }
      else if(bal < 200.0) { growthRiskMult = 0.72; growthMaxConc = 2; growthMaxTrades = 6; }
      else if(bal < 300.0) { growthRiskMult = 0.76; growthMaxConc = 2; growthMaxTrades = 7; }
      else                 { growthRiskMult = 0.82; growthMaxConc = 2; growthMaxTrades = 8; }
      g_riskPct       *= growthRiskMult;
      g_maxConcurrent  = MathMin(growthMaxConc, g_maxConcurrent);
      g_maxTradesDay   = MathMin(growthMaxTrades, g_maxTradesDay);
      // BUG-6 FIX: dailyLossUSD era 2% = $0.20 en cuenta de $10.
      // El spread de UN solo trade (0.01 lot, 35 pts) cuesta ~$0.35 en floating.
      // Equity circuit se disparaba INSTANTÁNEAMENTE → bot paralizado todo el día.
      // Solución: usar 8% base + floor de 5 spreads mínimos para permitir que
      // los trades tengan tiempo de desarrollarse.
      {
         double tickVal  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
         double tickSz   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
         double minLot   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
         double sp       = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
         // Costo de spread en 1 lote mínimo
         double spreadUSD = (tickSz > 0 && tickVal > 0) ? sp * tickVal * minLot : 0.0;
         double ddFromBal   = bal * 0.080;          // 8% base (era 2%)
         double ddMinSpread = spreadUSD * 5.0;      // floor: 5 trades de spread
         g_dailyLossUSD = MathMax(ddFromBal, ddMinSpread);
         g_dailyLossUSD = MathMin(g_dailyLossUSD, bal * 0.15); // hard cap 15%
      }
      // BUG-5 FIX: Objetivo diario 5% (era 3% → $15 a $500 — demasiado conservador).
      // 5% = $25 a $500 → permite capturar días buenos sin parar prematuramente.
      g_growthHarvestUSD = bal * 0.050;

      // Compounding basado en wins REALIZADOS del día — no en equity flotante
      double winBonus = 0.0;
      if(g_winsToday >= 4)      winBonus = 0.25;
      else if(g_winsToday >= 3) winBonus = 0.18;
      else if(g_winsToday >= 2) winBonus = 0.10;
      else if(g_winsToday >= 1) winBonus = 0.05;
      double losspenalty = g_lossesToday * 0.08;
      g_growthCompound = MathMax(0.0, MathMin(0.25, winBonus - losspenalty));
      g_riskPct       *= (1.0 + g_growthCompound);
   }
   else
   {
      g_growthCompound   = 0.0;
      g_growthHarvestUSD = 0.0;
   }

   // DD control override usuario
   if(InpDDMode == DD_PCT_CLOSE && InpDDValue > 0)
      g_dailyLossUSD = bal * InpDDValue / 100.0;
}

double RiskLevelMult()
{
   switch(InpRiskLevel)
   {
      case RISK_VLOW:  return 0.4;
      case RISK_LOW:   return 0.6;
      case RISK_MED:   return 1.0;
      case RISK_HIGH:  return 1.4;
      case RISK_VHIGH: return 1.8;
   }
   return 1.0;
}

// ── Capital Adaptive Mode Detection ───────────────────────────
// Umbral 500 USD con histéresis ±25 USD para evitar oscilación
void DetectOpMode()
{
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   g_opModePrev = g_opMode;

   if(g_opMode == OPMODE_GROWTH)
      g_opMode = (bal >= 500.0) ? OPMODE_STANDARD : OPMODE_GROWTH;
   else
      g_opMode = (bal < 475.0)  ? OPMODE_GROWTH   : OPMODE_STANDARD;

   if(g_opModePrev != g_opMode)
   {
      LOG(StringFormat("[OpMode] %s → %s | Balance: $%.2f",
          g_opModePrev==OPMODE_GROWTH?"GROWTH":"STANDARD",
          g_opMode==OPMODE_GROWTH?"GROWTH":"STANDARD", bal));
      // Transición suave: no cerrar posiciones abiertas, solo ajustar
      // parámetros en siguiente entrada. Reset harvest flag al subir.
      if(g_opMode == OPMODE_STANDARD) { g_growthHarvested = false; g_growthSoftHarvested = false; }
   }
}

// Cosecha de ganancias diarias en Growth Mode — dos niveles:
// Soft (~3%): reduce concurrent a 1, protege sin cerrar todo.
// Hard (5%):  cierra posiciones rentables y para entradas.
void CheckGrowthHarvest()
{
   if(g_opMode != OPMODE_GROWTH)
   { g_growthHarvested = false; g_growthSoftHarvested = false; return; }
   if(g_growthHarvestUSD <= 0) return;

   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double sessionProfit = eq - g_sessionStartEquity;
   double softThreshUSD = g_growthHarvestUSD * 0.60;   // ~3% del balance

   // Soft harvest (~3%): modo conservador sin parar del todo
   if(!g_growthSoftHarvested && sessionProfit >= softThreshUSD)
   {
      g_growthSoftHarvested = true;
      g_maxConcurrent = 1;
      LOG(StringFormat("[Growth Soft Harvest] ~3%% alcanzado ($%.2f). Modo conservador.", sessionProfit));
   }

   // Hard harvest (5%): cerrar rentables y parar entradas
   if(!g_growthHarvested && sessionProfit >= g_growthHarvestUSD)
   {
      g_growthHarvested = true;
      LOG(StringFormat("[Growth Hard Harvest] 5%% alcanzado ($%.2f). Deteniendo entradas.", sessionProfit));
      int total = PositionsTotal();
      for(int i=total-1; i>=0; i--)
      {
         ulong t = PositionGetTicket(i);
         if(!PositionSelectByTicket(t)) continue;
         if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
         if(PositionGetDouble(POSITION_PROFIT) > 0) trade.PositionClose(t);
      }
   }
}

string CapModeStr()
{
   switch(g_capMode)
   {
      case CAP_MICRO:   return "MICRO";
      case CAP_SMALL:   return "SMALL";
      case CAP_MEDIUM:  return "MEDIUM";
      case CAP_UPPER:   return "UPPER";
      case CAP_STANDARD:return "STANDARD";
   }
   return "?";
}

void CheckDDEscalation()
{
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   if(bal > g_peakBalance) g_peakBalance = bal;
   if(g_peakBalance <= 0) return;
   double ddPct = (g_peakBalance - bal) / g_peakBalance * 100.0;

   if(g_opMode == OPMODE_GROWTH)
   {
      // Growth Mode: 4 niveles granulares — evita reacción prematura a floating normal
      if(ddPct >= 10.0)     { g_ddLevel = 3; g_lotMultDD = 0.0;  CloseAllPositions(); }
      else if(ddPct >= 7.0) { g_ddLevel = 2; g_lotMultDD = 0.50; }
      else if(ddPct >= 4.5) { g_ddLevel = 1; g_lotMultDD = 0.70; }
      else if(ddPct >= 2.5) { g_ddLevel = 0; g_lotMultDD = 0.88; } // aviso suave, no bloqueo
      else                  { g_ddLevel = 0; g_lotMultDD = 1.0;  }
   }
   else
   {
      // Standard Mode: umbrales normales
      if(ddPct >= 15.0)      { g_ddLevel = 3; g_lotMultDD = 0.0; CloseAllPositions(); }
      else if(ddPct >= 10.0) { g_ddLevel = 2; g_lotMultDD = 0.50; }
      else if(ddPct >= 5.0)  { g_ddLevel = 1; g_lotMultDD = 0.75; }
      else                   { g_ddLevel = 0; g_lotMultDD = 1.0;  }
   }
}

//====================================================================
//  ============= MOTOR DE RECUPERACIÓN 6 CAPAS =============
//  Inspirado en QQ real. NO martingale. Lot máximo 1.5× base.
//====================================================================

// L6 — Capital Preservation Gate
bool RecovL6_CapPreservOk()
{
   long sp = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(sp > (long)(InpMaxSpread * 0.7)) return false;

   int iM5 = TFIdx(PERIOD_M5);
   if(iM5 >= 0 && g_tf[iM5].valid && g_atrAvgM5 > 0)
      if(g_tf[iM5].atr > g_atrAvgM5 * 2.0) return false;

   if(IsNewsTime() || IsNewsTimeNear()) return false;
   if(g_ddLevel >= 2)    return false;
   if(g_dayInvalid)      return false;

   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   if(dt.hour < 7 || dt.hour >= 20) return false;

   return true;
}

// L1 — Regime Recovery Validation
bool RecovL1_RegimeValid()
{
   if(!FilterSpread()) return false;
   if(g_adxH1 < 20)   return false;
   if(g_regime != g_regimePrev && g_regimePrev != REG_NEUTRAL) return false;

   if(g_recovIsLong  && !g_d1TrendUp) return false;
   if(!g_recovIsLong && !g_d1TrendDn) return false;

   return true;
}

// L2 — Soft Lot Escalation (never exponential)
double RecovL2_CalcLot(int layer, double slDist)
{
   double scaleFactor = 1.0 + 0.10 * (double)layer;
   if(scaleFactor > 1.5) scaleFactor = 1.5;

   if(g_recovBaseLot > 0)
   {
      double rawLot = g_recovBaseLot * scaleFactor;
      return NormalizeLot(rawLot);
   }
   double baseLot = CalcLot(slDist);
   return NormalizeLot(baseLot * scaleFactor);
}

// L3 — Structured Grid Recovery Conditions
bool RecovL3_CanAddLayer()
{
   if(!g_recovActive) return false;
   // GROWTH: máximo 2 capas (vs 3 en STANDARD) — capital pequeño no soporta más exposición
   int maxLayers = (g_opMode == OPMODE_GROWTH) ? 2 : MAX_GRID_LAYERS;
   if(g_recovLayerCount >= maxLayers) return false;
   if(!RecovL6_CapPreservOk())        return false;
   if(!RecovL1_RegimeValid())         return false;

   double price = g_recovIsLong ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   int iM5 = TFIdx(PERIOD_M5);
   if(iM5 < 0 || !g_tf[iM5].valid) return false;
   double atr = g_tf[iM5].atr;

   // GROWTH: spacing más conservador (0.5× ATR vs 0.4×) — capas más separadas
   double minSpacing = (g_opMode == OPMODE_GROWTH) ? 0.5 : 0.4;
   if(g_recovAvgEntry > 0 && MathAbs(price - g_recovAvgEntry) < atr * minSpacing) return false;

   // Price must be in adverse zone (0.2R–0.9R against us)
   if(g_recovAvgEntry > 0)
   {
      int iSId = (g_recovStratId >= 0) ? g_recovStratId : 0;
      double slMult = (g_recovStratId >= 0) ? g_str[g_recovStratId].slAtrMult : 1.5;
      double slDist = atr * slMult;
      if(slDist > 0)
      {
         double rMove = g_recovIsLong ? (price - g_recovAvgEntry) / slDist
                                      : (g_recovAvgEntry - price) / slDist;
         if(rMove < -0.9 || rMove > 0.0) return false;
      }
   }

   // H1 trend must agree with recovery direction
   if(g_recovIsLong  && !g_h1TrendUp) return false;
   if(!g_recovIsLong && !g_h1TrendDn) return false;

   return true;
}

// L3 — Add Recovery Grid Layer
void RecovL3_AddLayer()
{
   int iM5 = TFIdx(PERIOD_M5);
   if(iM5 < 0 || !g_tf[iM5].valid) return;

   double price = g_recovIsLong ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double atr   = g_tf[iM5].atr;
   double slM   = (g_recovStratId >= 0) ? g_str[g_recovStratId].slAtrMult : 1.5;
   double tpM   = slM * ((g_recovStratId >= 0) ? g_str[g_recovStratId].rrRatio : 2.0);
   double sl    = g_recovIsLong ? price - atr*slM : price + atr*slM;
   double tp    = g_recovIsLong ? price + atr*tpM : price - atr*tpM;
   double lot   = RecovL2_CalcLot(g_recovLayerCount + 1, MathAbs(price - sl));
   if(lot <= 0) return;

   string cmt = StringFormat("S%d-R%d", g_recovStratId+1, g_recovLayerCount+1);
   bool ok = g_recovIsLong ? trade.Buy(lot, _Symbol, price, sl, tp, cmt)
                           : trade.Sell(lot, _Symbol, price, sl, tp, cmt);
   if(ok)
   {
      ulong newT = trade.ResultOrder();
      if(g_recovLayerCount < MAX_GRID_LAYERS)
         g_recovTickets[g_recovLayerCount] = newT;
      // Update volume-weighted avg entry
      double totalVol = g_recovBaseLot * g_recovLayerCount + lot;
      if(totalVol > 0)
         g_recovAvgEntry = (g_recovAvgEntry * g_recovBaseLot * g_recovLayerCount
                            + price * lot) / totalVol;
      g_recovLayerCount++;
      LOG(StringFormat("Recovery Layer %d added | Price=%.2f Lot=%.2f", g_recovLayerCount, price, lot));
   }
}

// L4 — Basket Recovery Exit
void RecovL4_ManageBasket()
{
   if(!g_recovActive || g_recovLayerCount == 0) return;

   double basketPnL = 0;
   for(int k=0; k<MAX_GRID_LAYERS; k++)
   {
      ulong t = g_recovTickets[k];
      if(t == 0) continue;
      if(PositionSelectByTicket(t))
         basketPnL += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   }

   // Track peak
   if(basketPnL > g_recovBasketPeak) g_recovBasketPeak = basketPnL;

   // Target: recover base loss (1R equivalent of base lot)
   int iM5 = TFIdx(PERIOD_M5);
   if(iM5 < 0 || !g_tf[iM5].valid) return;
   double atr   = g_tf[iM5].atr;
   double slM   = (g_recovStratId >= 0) ? g_str[g_recovStratId].slAtrMult : 1.5;
   double slDist = atr * slM;
   double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSz  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double basketTarget = (tickSz > 0 && tickVal > 0)
                         ? g_recovBaseLot * slDist / tickSz * tickVal
                         : 0;

   // Adaptive: scale slightly with layers
   basketTarget *= (1.0 + 0.15 * (g_recovLayerCount - 1));
   // GROWTH: target reducido a 0.75R — salir antes, preservar capital
   if(g_opMode == OPMODE_GROWTH) basketTarget *= 0.75;

   // Close basket at target
   if(basketTarget > 0 && basketPnL >= basketTarget)
   {
      CloseRecoveryPositions();
      ResetRecovery();
      LOG("Recovery basket target reached — reset");
      return;
   }

   // Basket trailing: if peak > 50% of target, trail at 70% of peak
   if(basketTarget > 0 && g_recovBasketPeak >= basketTarget * 0.5)
   {
      double trailStop = g_recovBasketPeak * 0.70;
      if(basketPnL < trailStop && g_recovBasketPeak > 0)
      {
         CloseRecoveryPositions();
         ResetRecovery();
         LOG("Recovery basket trail stop hit — reset");
      }
   }
}

// L5 — Per-Position Exit Management for Recovery
void RecovL5_ManageExits()
{
   if(!g_recovActive) return;

   for(int k=0; k<MAX_GRID_LAYERS; k++)
   {
      ulong t = g_recovTickets[k];
      if(t == 0) continue;
      if(!PositionSelectByTicket(t)) continue;

      double opPx  = PositionGetDouble(POSITION_PRICE_OPEN);
      double slPx  = PositionGetDouble(POSITION_SL);
      double tpPx  = PositionGetDouble(POSITION_TP);
      double curPx = g_recovIsLong ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                   : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double slDist = MathAbs(opPx - slPx);
      if(slDist <= 0) continue;
      double rMove = g_recovIsLong ? (curPx - opPx) / slDist
                                   : (opPx - curPx) / slDist;

      // BE at 0.5R (tighter than normal 0.8R)
      if(!g_recovBEDone && rMove >= 0.5)
      {
         double newSL = g_recovIsLong ? opPx + slDist*0.03 : opPx - slDist*0.03;
         if(g_recovIsLong  && (slPx < opPx || slPx == 0)) trade.PositionModify(t, newSL, tpPx);
         if(!g_recovIsLong && (slPx > opPx || slPx == 0)) trade.PositionModify(t, newSL, tpPx);
         if(k == 0) g_recovBEDone = true;
      }

      // Partial 30% at 1.0R
      if(!g_recovPartialDone && rMove >= 1.0)
      {
         double vol  = PositionGetDouble(POSITION_VOLUME);
         double part = NormalizeLot(vol * 0.30);
         if(part > 0 && part < vol)
         {
            trade.PositionClosePartial(t, part);
            if(k == 0) g_recovPartialDone = true;
         }
      }

      // Trailing ATR×1.5 from 1.0R (earlier trigger than normal 1.2R)
      if(rMove >= 1.0)
      {
         int iM5 = TFIdx(PERIOD_M5);
         if(iM5 >= 0 && g_tf[iM5].valid)
         {
            double newSL = g_recovIsLong ? curPx - g_tf[iM5].atr*1.5
                                         : curPx + g_tf[iM5].atr*1.5;
            if(g_recovIsLong  && newSL > slPx) trade.PositionModify(t, newSL, tpPx);
            if(!g_recovIsLong && (newSL < slPx || slPx == 0)) trade.PositionModify(t, newSL, tpPx);
         }
      }
   }
}

// Initiate Recovery after confirmed loss
void InitiateRecovery(int sId, bool isLong, double baseLot)
{
   if(g_recovActive)        return;   // no stacking
   if(g_consecLosses > 3)  return;   // 4+ losses = full stop, no recovery
   if(sId < 0)              return;

   g_recovActive        = true;
   g_recovStratId       = sId;
   g_recovIsLong        = isLong;
   g_recovBaseLot       = (baseLot > 0) ? baseLot : 0.01;
   g_recovAvgEntry      = 0.0;
   g_recovBasketPeak    = 0.0;
   g_recovLayerCount    = 0;
   g_recovLastLossTime  = TimeCurrent();
   g_recovBEDone        = false;
   g_recovPartialDone   = false;
   for(int k=0; k<MAX_GRID_LAYERS; k++) g_recovTickets[k] = 0;

   LOG(StringFormat("Recovery armed | S%d %s BaseLot=%.2f ConsecLoss=%d",
       sId+1, isLong?"LONG":"SHORT", g_recovBaseLot, g_consecLosses));
}

// Reset Recovery State
void ResetRecovery()
{
   g_recovActive       = false;
   g_recovStratId      = -1;
   g_recovIsLong       = false;
   g_recovBaseLot      = 0.0;
   g_recovAvgEntry     = 0.0;
   g_recovBasketPeak   = 0.0;
   g_recovLayerCount   = 0;
   g_recovBEDone       = false;
   g_recovPartialDone  = false;
   for(int k=0; k<MAX_GRID_LAYERS; k++) g_recovTickets[k] = 0;
   LOG("Recovery engine reset");
}

// Close all open recovery positions
void CloseRecoveryPositions()
{
   for(int k=0; k<MAX_GRID_LAYERS; k++)
   {
      ulong t = g_recovTickets[k];
      if(t == 0) continue;
      if(PositionSelectByTicket(t)) trade.PositionClose(t);
      g_recovTickets[k] = 0;
   }
}

// UpdateRecoveryEngine — replaces CheckRecoveryLayers()
void UpdateRecoveryEngine()
{
   // BUG-1 FIX: Detectar estado zombie — recovery armado pero todos los tickets muertos.
   // Causa: SL barre todas las capas → g_recovActive queda true indefinidamente.
   // Solución: auto-reset si g_recovLayerCount > 0 pero ningún ticket tiene posición abierta.
   if(g_recovActive && g_recovLayerCount > 0)
   {
      bool anyAlive = false;
      for(int k=0; k<MAX_GRID_LAYERS; k++)
      {
         if(g_recovTickets[k] != 0 && PositionSelectByTicket(g_recovTickets[k]))
         {
            anyAlive = true;
            break;
         }
      }
      if(!anyAlive)
      {
         LOG("[Recovery] Zombie detectado — todos tickets cerrados. Auto-reset.");
         ResetRecovery();
      }
   }

   // Normal lot reduction tiers (when no active recovery)
   if(!g_recovActive)
   {
      if(g_consecLosses >= 4)      { g_recovLevel = 3; g_lotMultRecov = 0.0; g_recovPauseUntil = TimeCurrent()+7200; }
      else if(g_consecLosses >= 3) { g_recovLevel = 2; g_lotMultRecov = 0.50; }
      else if(g_consecLosses >= 2) { g_recovLevel = 1; g_lotMultRecov = 0.75; }
      else if(g_consecLosses >= 1) { g_recovLevel = 0; g_lotMultRecov = 0.90; }
      else                         { g_recovLevel = 0; g_lotMultRecov = 1.0; g_recovPauseUntil = 0; }
   }
}

// RunRecoveryEngine — add new recovery layers (called from OnTick)
void RunRecoveryEngine()
{
   if(!g_recovActive)               return;
   if(!RecovL6_CapPreservOk())      return;
   if(!RecovL1_RegimeValid())       return;
   if(RecovL3_CanAddLayer())        RecovL3_AddLayer();
}

bool IsRecoveryPaused()
{
   return (g_recovLevel >= 3 && g_recovPauseUntil > 0 && TimeCurrent() < g_recovPauseUntil);
}

void CheckEquityCircuit()
{
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double drop = g_sessionStartEquity - eq;
   if(drop > g_dailyLossUSD)
   {
      g_dayInvalid = true;
      CloseAllPositions();
   }
}

void CheckPreNewsExit()
{
   if(!IsNewsTimeNear()) return;
   int total = PositionsTotal();
   for(int i=total-1; i>=0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      double profit = PositionGetDouble(POSITION_PROFIT);
      if(profit > 0) trade.PositionClose(t);
   }
}

bool IsNewsTime()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   int hm = dt.hour*60 + dt.min;
   if(hm >= 13*60+25 && hm < 13*60+45) return true;
   if(hm >= 18*60+55 && hm < 19*60+15) return true;
   return false;
}

bool IsNewsTimeNear()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   int hm = dt.hour*60 + dt.min;
   if(hm >= 13*60+5  && hm < 13*60+25) return true;
   if(hm >= 18*60+35 && hm < 18*60+55) return true;
   return false;
}

bool IsHolidayTime()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   // Dec 15 - Jan 15
   if(dt.mon == 12 && dt.day >= 15) return true;
   if(dt.mon == 1  && dt.day <= 15) return true;
   return false;
}

bool FilterSpread()
{
   long sp = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   return sp <= InpMaxSpread;
}

void CloseAllPositions()
{
   int total = PositionsTotal();
   for(int i=total-1; i>=0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      trade.PositionClose(t);
   }
   for(int s=0; s<NUM_STRATS; s++)
   {
      for(int k=0; k<MAX_GRID_LAYERS; k++) g_str[s].posTickets[k] = 0;
      g_str[s].gridLayers = 0;
      g_str[s].posCount = 0;
   }
}

//====================================================================
//  RESET DIARIO
//====================================================================
void DailyReset()
{
   g_tradesToday = 0;
   g_winsToday = 0; g_lossesToday = 0;
   g_dayInvalid = false;
   g_sessionStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   for(int s=0; s<NUM_STRATS; s++)
   {
      g_str[s].winsToday        = 0;
      g_str[s].lossesToday      = 0;
      g_str[s].pnlToday         = 0;
      g_str[s].sameDirectStreak = 0;
      // lastSLTime NO se resetea — cooldown de SL persiste entre días para proteger
   }
   g_orbBuilt = false; g_orbHi = 0; g_orbLo = DBL_MAX;
   g_orbFiredLong = false; g_orbFiredShort = false;
   g_nyBuilt = false; g_nyHi = 0; g_nyLo = DBL_MAX;
   g_nyFiredLong = false; g_nyFiredShort = false;
   g_asBuilt = false; g_asHi = 0; g_asLo = DBL_MAX;
   g_asFiredLong = false; g_asFiredShort = false;
   g_consecLosses        = 0;
   g_growthHarvested     = false;
   g_growthSoftHarvested = false;
   if(g_recovActive) { CloseRecoveryPositions(); ResetRecovery(); }
}

void CheckDayReset()
{
   datetime today = iTime(_Symbol, PERIOD_D1, 0);
   if(today != g_lastDay)
   {
      g_lastDay = today;
      g_dayStartBal = AccountInfoDouble(ACCOUNT_BALANCE);
      DailyReset();
   }
}

//====================================================================
//  ============= POSITION TRACKING =============
//====================================================================
void RefreshPositionTracking()
{
   // En tester: reconstruir solo cuando hubo cambio (dirty flag).
   // En live: reconstruir siempre para consistencia en tiempo real.
   if(g_isTesting && !g_posTrackDirty) return;
   g_posTrackDirty = false;

   for(int s=0; s<NUM_STRATS; s++) g_str[s].posCount = 0;
   g_posCount = 0;
   int total = PositionsTotal();
   for(int i=0; i<total && i<MAX_OPEN_POS; i++)
   {
      ulong t = PositionGetTicket(i);
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      string cmt = PositionGetString(POSITION_COMMENT);
      int sId = ExtractStratId(cmt);
      if(sId < 0 || sId >= NUM_STRATS) continue;

      // Re-link tickets
      int gIdx = ExtractGridIdx(cmt);
      if(gIdx >= 0 && gIdx < MAX_GRID_LAYERS) g_str[sId].posTickets[gIdx] = t;
      g_str[sId].posCount++;
      if(gIdx == 0) g_str[sId].sigCode = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? +1 : -1;

      g_pos[g_posCount].ticket = t;
      g_pos[g_posCount].stratId = sId;
      g_pos[g_posCount].gridIdx = gIdx;
      g_pos[g_posCount].openTime = (datetime)PositionGetInteger(POSITION_TIME);
      g_pos[g_posCount].openPrice= PositionGetDouble(POSITION_PRICE_OPEN);
      g_posCount++;
   }
   // Recompute gridLayers from posCount (sin contar base)
   for(int s=0; s<NUM_STRATS; s++)
      g_str[s].gridLayers = MathMax(0, g_str[s].posCount - 1);
}

int ExtractStratId(string cmt)
{
   // Formato: "S<n>-B" o "S<n>-G<k>"
   int p1 = StringFind(cmt, "S");
   int p2 = StringFind(cmt, "-");
   if(p1 < 0 || p2 < 0 || p2 <= p1) return -1;
   string num = StringSubstr(cmt, p1+1, p2-p1-1);
   int n = (int)StringToInteger(num) - 1;
   if(n < 0 || n >= NUM_STRATS) return -1;
   return n;
}

int ExtractGridIdx(string cmt)
{
   int pG = StringFind(cmt, "-G");
   if(pG < 0)
   {
      int pB = StringFind(cmt, "-B");
      return (pB >= 0) ? 0 : -1;
   }
   string num = StringSubstr(cmt, pG+2);
   return (int)StringToInteger(num);
}

int CountAllOpen()
{
   // BUG-2 FIX: contar solo posiciones normales (S<n>-B / S<n>-G<k>), NO recovery (S<n>-R<k>).
   // Recovery positions comparten sId con estrategias normales → inflaban posCount
   // → reducían slots disponibles para entradas normales → undertrade.
   int n = 0;
   int total = PositionsTotal();
   for(int i=0; i<total; i++)
   {
      ulong t = PositionGetTicket(i);
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      string cmt = PositionGetString(POSITION_COMMENT);
      // Excluir recovery (contienen "-R")
      if(StringFind(cmt, "-R") >= 0) continue;
      n++;
   }
   return n;
}

void TrackClosedTrades() { }   // PnL ya capturado en OnTradeTransaction

//====================================================================
//  ============= OPEN TRADE — utilidad genérica =============
//  sId=0..11, isBuy, slTF (TF para ATR), slAtrMult, tpAtrMult
//====================================================================
bool OpenTrade(int sId, bool isBuy, ENUM_TIMEFRAMES slTF, double slMult, double tpMult)
{
   if(g_tradesToday >= g_maxTradesDay) return false;
   if(CountAllOpen() >= g_maxConcurrent) return false;
   if(!FilterSpread()) return false;
   int idx = TFIdx(slTF);
   if(idx < 0 || !g_tf[idx].valid) return false;
   double atr = g_tf[idx].atr;
   if(atr <= 0) return false;

   double price = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                        : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = isBuy ? price - atr*slMult : price + atr*slMult;
   double tp = isBuy ? price + atr*tpMult : price - atr*tpMult;
   double lot = CalcLot(MathAbs(price - sl));
   if(lot <= 0) return false;

   string cmt = StringFormat("S%d-B", sId+1);
   bool ok = isBuy ? trade.Buy(lot, _Symbol, price, sl, tp, cmt)
                   : trade.Sell(lot, _Symbol, price, sl, tp, cmt);
   if(ok)
   {
      ulong newT = trade.ResultOrder();
      g_str[sId].posTickets[0] = newT;
      g_str[sId].sigCode = isBuy ? +1 : -1;
      g_str[sId].lastEntryTime = TimeCurrent();
      g_str[sId].posCount = 1;
      g_str[sId].gridLayers = 0;
      g_tradesToday++;
      g_str[sId].status = SSTAT_IN_TRADE;
      g_posTrackDirty = true;
   }
   return ok;
}

double CalcLot(double slDistPrice)
{
   double bal  = AccountInfoDouble(ACCOUNT_BALANCE);
   double minL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double lot  = 0;

   if(InpLotMethod == LOT_FIXED)
   {
      lot = InpFixedLot;
   }
   else if(InpLotMethod == LOT_FIXED_PER_BAL)
   {
      if(InpFixedPerBal <= 0) lot = InpFixedLot;
      else lot = InpFixedLot * MathFloor(bal / InpFixedPerBal);
      if(lot < InpFixedLot) lot = InpFixedLot;
   }
   else
   {
      // AUTOMATIC: risk % base
      if(slDistPrice <= 0) return 0;
      double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSz  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      if(tickVal <= 0 || tickSz <= 0) return 0;
      double riskUSD = bal * g_riskPct / 100.0 * g_lotMultDD * g_lotMultRecov;
      lot = riskUSD * tickSz / (tickVal * slDistPrice);

      // Para CAP_MICRO (bal < $50) el cálculo porcentual da lot < minL.
      // MICRO: siempre usar minLot — es la única opción viable, sin guardPct.
      //   Razón: con $10-$49, minLot=0.01 es literalmente el lote más pequeño posible.
      //   Rechazar el trade significa 0 operaciones. Aceptar minLot da oportunidad de crecer.
      // SMALL/MEDIUM+: guardia proporcional para evitar riesgo excesivo accidental.
      if(lot < minL)
      {
         if(g_capMode == CAP_MICRO)
         {
            lot = minL;   // MICRO: siempre minLot sin restricción de guardPct
         }
         else
         {
            double slUSD_minL = slDistPrice * tickVal * minL / tickSz;
            double riskPctReal = (bal > 0) ? slUSD_minL / bal * 100.0 : 999.0;
            double guardPct = (g_capMode == CAP_SMALL) ? 22.0 : 15.0;
            if(riskPctReal > guardPct) return 0;   // demasiado riesgo → no abrir
            lot = minL;
         }
      }
   }

   if(step > 0) lot = MathFloor(lot / step) * step;
   lot = MathMax(minL, MathMin(maxL, lot));
   return NormalizeDouble(lot, 2);
}

double NormalizeLot(double lot)
{
   double minL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step > 0) lot = MathFloor(lot / step) * step;
   return NormalizeDouble(MathMax(minL, MathMin(maxL, lot)), 2);
}


//====================================================================
//  BROKER SETS — preset ajustes según broker
//====================================================================
void ApplyBrokerSet()
{
   // Solo ajustes internos (no inputs) — futuro: ATR multipliers, etc
   // De momento: solo filling type
   switch(InpBrokerSet)
   {
      case BSET_IC_LOW:
      case BSET_IC_MED:
         trade.SetTypeFilling(ORDER_FILLING_FOK);
         break;
      case BSET_ROBO:
         trade.SetTypeFilling(ORDER_FILLING_IOC);
         break;
      case BSET_FUSION:
         trade.SetTypeFilling(ORDER_FILLING_FOK);
         break;
   }
}

//====================================================================
//  ============= LAYER 7 — PANEL DRAWING =============
//  Imita el panel real Quantum Queen
//====================================================================
#define PNL_PREFIX "QQ_PNL_"

void DrawPanel()
{
   if(g_isTesting) return;   // no panel en tester — elimina miles de ObjectSet/Find por tick
   // Background
   PanelBox(PNL_PREFIX+"BG", 8, 25, 620, 510, C'15,20,40');

   // Header buttons (PAUSE / CLOSE ALL)
   PanelLabel(PNL_PREFIX+"H1", 16, 32, "Quantum Queen MT5 v10.0 ["+_Symbol+"]", clrWhite, InpPanelFontSize+1);
   PanelLabel(PNL_PREFIX+"BTN1", 16, 56, g_paused?"  EA PAUSED  ":"   PAUSE EA   ", clrWhite, InpPanelFontSize);
   PanelLabel(PNL_PREFIX+"BTN2", 340, 56, " CLOSE ALL TRADES ", clrWhite, InpPanelFontSize);
   PanelLabel(PNL_PREFIX+"DIV", 16, 80, "================== INFORMATION ==================", clrSilver, InpPanelFontSize);

   // Columna izquierda — Info cuenta
   int y = 100;
   PanelLabel(PNL_PREFIX+"L01", 16, y, "Lot Method: "+LotMethodStr(), clrLightGray, InpPanelFontSize); y+=18;
   PanelLabel(PNL_PREFIX+"L02", 16, y, "Risk Level: "+RiskLvlStr(), clrLightGray, InpPanelFontSize); y+=18;
   PanelLabel(PNL_PREFIX+"L03", 16, y, "Fixed: "+DoubleToString(InpFixedLot,2), clrLightGray, InpPanelFontSize); y+=18;
   PanelLabel(PNL_PREFIX+"L04", 16, y, "Fixed per Balance: "+DoubleToString(InpFixedPerBal,1), clrLightGray, InpPanelFontSize); y+=18;
   PanelLabel(PNL_PREFIX+"L05", 16, y, "DD. Mode: "+DDModeStr(), clrLightGray, InpPanelFontSize); y+=18;
   PanelLabel(PNL_PREFIX+"L06", 16, y, "DD. Value: "+DoubleToString(InpDDValue,1)+" %", clrLightGray, InpPanelFontSize); y+=18;
   PanelLabel(PNL_PREFIX+"L07", 16, y, "Magic: "+IntegerToString(InpMagic), clrLightGray, InpPanelFontSize); y+=18;
   PanelLabel(PNL_PREFIX+"L08", 16, y, "Comment: "+InpPanelComment, clrLightGray, InpPanelFontSize); y+=18;
   PanelLabel(PNL_PREFIX+"L09", 16, y, "Push Notif: "+(InpPushNotif?"ON":"OFF"), clrLightGray, InpPanelFontSize); y+=22;

   PanelLabel(PNL_PREFIX+"L10", 16, y, "Set: "+BrokerSetStr(), clrAqua, InpPanelFontSize); y+=22;

   double totalPL = AccountInfoDouble(ACCOUNT_EQUITY) - AccountInfoDouble(ACCOUNT_BALANCE);
   PanelLabel(PNL_PREFIX+"L11", 16, y, StringFormat("Total P/L: %.2f USD", totalPL),
              totalPL>=0?clrLime:clrRed, InpPanelFontSize); y+=18;
   PanelLabel(PNL_PREFIX+"L12", 16, y, StringFormat("Balance: %.2f USD", AccountInfoDouble(ACCOUNT_BALANCE)), clrLightGray, InpPanelFontSize); y+=18;
   PanelLabel(PNL_PREFIX+"L13", 16, y, StringFormat("Equity: %.2f USD", AccountInfoDouble(ACCOUNT_EQUITY)), clrLightGray, InpPanelFontSize); y+=18;
   double marginPct = 0;
   if(AccountInfoDouble(ACCOUNT_EQUITY) > 0 && AccountInfoDouble(ACCOUNT_MARGIN) > 0)
      marginPct = AccountInfoDouble(ACCOUNT_MARGIN) / AccountInfoDouble(ACCOUNT_EQUITY) * 100.0;
   PanelLabel(PNL_PREFIX+"L14", 16, y, StringFormat("Margin Curr: %.1f %%", marginPct), clrLightGray, InpPanelFontSize); y+=18;
   double mcLvl = AccountInfoDouble(ACCOUNT_MARGIN_SO_CALL);
   double moLvl = AccountInfoDouble(ACCOUNT_MARGIN_SO_SO);
   PanelLabel(PNL_PREFIX+"L15", 16, y, StringFormat("Margin Call: %.0f %%", mcLvl), clrLightGray, InpPanelFontSize); y+=18;
   PanelLabel(PNL_PREFIX+"L16", 16, y, StringFormat("Margin Stop: %.0f %%", moLvl), clrLightGray, InpPanelFontSize); y+=18;
   PanelLabel(PNL_PREFIX+"L17", 16, y, StringFormat("Total Volume: %.2f Lots", TotalOpenVolume()), clrLightGray, InpPanelFontSize); y+=22;

   PanelLabel(PNL_PREFIX+"L18", 16, y, "Regime: "+RegimeStr(), RegimeColor(), InpPanelFontSize); y+=18;
   // Operating mode — destacado con color diferencial + progreso de milestone
   string opModeLabel;
   if(g_opMode == OPMODE_GROWTH)
   {
      double balP = AccountInfoDouble(ACCOUNT_BALANCE);
      double nextMS = (balP < 50)?50:(balP < 100)?100:(balP < 200)?200:(balP < 300)?300:500;
      double pctMS  = (nextMS > 0) ? balP / nextMS * 100.0 : 100.0;
      string harvestTag = g_growthHarvested ? " HARVEST" : (g_growthSoftHarvested ? " SOFT" : "");
      opModeLabel = StringFormat("Mode: GROWTH [x%.2f]%s →$%.0f [%.1f%%]",
                                 1.0+g_growthCompound, harvestTag, nextMS, pctMS);
   }
   else opModeLabel = "Mode: STANDARD";
   color  opModeColor = (g_opMode == OPMODE_GROWTH) ? clrGold : clrLightBlue;
   PanelLabel(PNL_PREFIX+"L18b", 16, y, opModeLabel, opModeColor, InpPanelFontSize); y+=18;
   PanelLabel(PNL_PREFIX+"L19", 16, y, "Cap: "+CapModeStr()+" | Risk: "+DoubleToString(g_riskPct,2)+"%", clrLightGray, InpPanelFontSize); y+=18;
   PanelLabel(PNL_PREFIX+"L20", 16, y, StringFormat("DD:%d | Recov:%s L%d | Loss:%d/%d",
              g_ddLevel, g_recovActive?"ON":"off", g_recovLayerCount,
              g_lossesToday, g_consecLosses), clrLightGray, InpPanelFontSize); y+=18;
   PanelLabel(PNL_PREFIX+"L21", 16, y, StringFormat("Trades: %d/%d | W:%d L:%d",
              g_tradesToday, g_maxTradesDay, g_winsToday, g_lossesToday), clrLightGray, InpPanelFontSize); y+=22;
   PanelLabel(PNL_PREFIX+"L22", 16, y, "Broker: "+AccountInfoString(ACCOUNT_COMPANY), clrLightGray, InpPanelFontSize); y+=18;
   PanelLabel(PNL_PREFIX+"L23", 16, y, StringFormat("Acc: %d | Lev: 1:%d", (int)AccountInfoInteger(ACCOUNT_LOGIN), (int)AccountInfoInteger(ACCOUNT_LEVERAGE)), clrLightGray, InpPanelFontSize);

   // Columna derecha — 12 estrategias
   int x2 = 350;
   y = 100;
   for(int s=0; s<NUM_STRATS; s++)
   {
      string statTxt = StratStatusStr(s);
      color  statClr = StratStatusColor(s);
      string line = StringFormat("[Strategy %2d] %-3s | %s",
                                 s+1,
                                 (g_str[s].activeRegime || g_str[s].posCount>0) ? "ON" : "OFF",
                                 statTxt);
      string id = PNL_PREFIX+"STR"+IntegerToString(s);
      PanelLabel(id, x2, y, line, statClr, InpPanelFontSize);
      y += 22;
   }
}

color RegimeColor()
{
   switch(g_regime)
   {
      case REG_TRENDING: return clrLime;
      case REG_RANGING:  return clrYellow;
      case REG_VOLATILE: return clrOrange;
      case REG_MOMENTUM: return clrMagenta;
   }
   return clrSilver;
}

string StratStatusStr(int s)
{
   if(g_str[s].posCount > 0)        return StringFormat("In trade (%d pos, PnL %.2f)", g_str[s].posCount, g_str[s].pnlToday);
   if(!g_str[s].activeRegime)       return "Awaiting regime...";
   return "Awaiting signals...";
}

color StratStatusColor(int s)
{
   if(g_str[s].posCount > 0) return clrLime;
   if(g_str[s].activeRegime) return clrAqua;
   return clrDimGray;
}

string LotMethodStr()
{
   switch(InpLotMethod)
   {
      case LOT_AUTOMATIC:     return "Automatic";
      case LOT_FIXED:         return "Fixed";
      case LOT_FIXED_PER_BAL: return "Fixed per Balance";
   }
   return "?";
}

string RiskLvlStr()
{
   switch(InpRiskLevel)
   {
      case RISK_VLOW:  return "Very Low";
      case RISK_LOW:   return "Low";
      case RISK_MED:   return "Medium";
      case RISK_HIGH:  return "High";
      case RISK_VHIGH: return "Very High";
   }
   return "?";
}

string DDModeStr()
{
   switch(InpDDMode)
   {
      case DD_OFF:         return "OFF";
      case DD_PCT_CLOSE:   return "[Pct] Close all";
      case DD_MONEY_ALERT: return "[Money] Alert";
   }
   return "?";
}

string BrokerSetStr()
{
   switch(InpBrokerSet)
   {
      case BSET_IC_MED:  return "IC Markets RAW - MEDIUM";
      case BSET_IC_LOW:  return "IC Markets RAW - LOW";
      case BSET_ROBO:    return "RoboForex (ECN)";
      case BSET_FUSION:  return "Fusion Markets (Zero)";
   }
   return "?";
}

double TotalOpenVolume()
{
   double v = 0;
   int total = PositionsTotal();
   for(int i=0; i<total; i++)
   {
      ulong t = PositionGetTicket(i);
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      v += PositionGetDouble(POSITION_VOLUME);
   }
   return v;
}

void PanelLabel(string name, int x, int y, string text, color clr, int fontSize)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
      ObjectSetString(0, name, OBJPROP_FONT, InpPanelFont);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
   }
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
}

void PanelBox(string name, int x, int y, int w, int h, color bg)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrDarkSlateBlue);
   }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
}

void PanelClear()
{
   int total = ObjectsTotal(0, -1, -1);
   for(int i=total-1; i>=0; i--)
   {
      string nm = ObjectName(0, i);
      if(StringFind(nm, PNL_PREFIX) == 0) ObjectDelete(0, nm);
   }
}

//+------------------------------------------------------------------+
//|  EOF — Quantum Queen Inspired v10.0                              |
//+------------------------------------------------------------------+
