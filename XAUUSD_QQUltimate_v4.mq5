//+------------------------------------------------------------------+
//|  XAUUSD QUANTUM QUEEN ULTIMATE v9.0 – PRO EDITION               |
//|  Sistema de entrada ultra-preciso (candle-close + multi-TF)      |
//|  Multi-Trade profesional: hasta 5 trades simultáneos por capital |
//|  Kelly Criterion calibrado | MFE Dynamic TP | Compound seguro    |
//|  Recovery Anti-Deadlock rediseñado | Capital: $10 – Millones     |
//|  TF Analysis: M5 | M6 | M15 | M20 | H1 | D1                    |
//+------------------------------------------------------------------+
#property copyright "QQ Ultimate v9.0 Pro Edition"
#property version   "9.00"
#property strict

#include <Trade/Trade.mqh>
CTrade trade;

//====================================================================
//  ENUMERACIONES
//====================================================================
enum ENUM_CAP_MODE
{
   CAP_NANO     = 0,  // < $25
   CAP_MICRO    = 1,  // $25 – $49
   CAP_SMALL    = 2,  // $50 – $129
   CAP_MEDIUM   = 3,  // $130 – $249
   CAP_STANDARD = 4,  // $250 – $999
   CAP_LARGE    = 5   // $1000+
};

enum ENUM_MKT_REGIME { REGIME_TREND=0, REGIME_RANGE=1, REGIME_VOLATILE=2 };

enum ENUM_RECOVERY
{
   REC_NONE    = 0,
   REC_CAUTION = 1,
   REC_REDUCE  = 2,
   REC_SMART   = 3,
   REC_PAUSE   = 4
};

enum ENUM_ENTRY_PATTERN
{
   PAT_NONE         = 0,
   PAT_ENGULFING    = 1,
   PAT_PINBAR       = 2,
   PAT_INSIDE_BREAK = 3,
   PAT_MOMENTUM     = 4
};

//====================================================================
//  INPUTS
//====================================================================
input group "=== CAPITAL & RIESGO ==="
input bool   InpAutoCapital       = true;
input double InpRiskPercent       = 1.0;
input int    InpMagic             = 5900;

input group "=== ENTRADA ULTRA-PRECISA ==="
input int    InpMinEntryScore     = 72;    // Score mínimo 0–100 para entrar
input bool   InpRequireCandleClose= true;  // Solo entrada en cierre de vela M5
input double InpMinRR             = 1.8;   // R:R mínimo requerido
input int    InpMinTFAlignment    = 4;     // TFs mínimos alineados (de 6)
input bool   InpRequireVolume     = true;  // Confirmar volumen superior al promedio
input double InpVolumeMult        = 1.15;  // Multiplicador vs promedio 20 velas

input group "=== MULTI-TRADE PROFESIONAL ==="
input bool   InpMultiTradeOn      = true;
// Umbrales automáticos por equity:
//   < $25  → 1 trade
//   >= $25  → 2 trades
//   >= $50  → 3 trades
//   >= $130 → 4 trades
//   >= $250 → 5 trades

input group "=== KELLY CRITERION ==="
input bool   InpKellyOn           = true;
input double InpKellyFraction     = 0.30;
input double InpKellyMinRisk      = 0.20;
input double InpKellyMaxRisk      = 1.80;
input int    InpKellySampleSize   = 15;

input group "=== MFE DYNAMIC TP ==="
input bool   InpMFEOn             = true;
input double InpMFE_ExtendAt      = 0.70;
input double InpMFE_ExtendMult    = 1.80;
input double InpMFE_LockPct       = 0.50;
input int    InpMFE_MaxExtensions = 2;

input group "=== COMPOUND ACCELERATOR ==="
input bool   InpCompoundOn        = true;
input double InpCompound_Trigger  = 5.0;
input double InpCompound_Boost    = 1.25;
input double InpCompound_MaxBoost = 1.80;
input double InpCompound_DDReset  = 1.5;

input group "=== SL / TP PROGRESIVOS ==="
input double InpATR_SL_Mult       = 1.2;
input double InpATR_TP1           = 2.5;
input double InpATR_TP2           = 3.5;
input double InpATR_TP3           = 5.0;
input double InpATR_TP4           = 7.0;
input double InpATR_TP5           = 10.0;

input group "=== RECUPERACIÓN ANTI-DEADLOCK ==="
input bool   InpRecoveryOn        = true;
input int    InpDailyLossLimit    = 3;
input int    InpGlobalLossReset   = 5;
input int    InpRecoveryTimeoutH  = 4;

input group "=== HORARIOS ==="
input int    InpSessionStart      = 7;
input int    InpSessionEnd        = 20;

input group "=== PROTECCIONES ==="
input double InpMaxSpread         = 40.0;

input group "=== INDICADORES ==="
input int    InpBBPeriod          = 20;
input int    InpRSIPeriod         = 14;
input int    InpMFIPeriod         = 14;
input int    InpATRPeriod         = 14;
input int    InpADXPeriod         = 14;
input int    InpStochK            = 5;
input int    InpStochD            = 3;
input int    InpFastEMA           = 9;
input int    InpSlowEMA           = 21;
input int    InpTrendEMA          = 50;
input int    InpLongEMA           = 100;

input bool   InpShowPanel         = true;

//====================================================================
//  HANDLES DE INDICADORES (6 TFs: M5, M6, M15, M20, H1, D1)
//====================================================================
// D1
int hEMA50_D1, hEMA200_D1, hATR_D1, hRSI_D1, hADX_D1;
// H1
int hEMA21_H1, hEMA50_H1, hATR_H1, hRSI_H1, hADX_H1, hBB_H1;
// M20
int hEMA_M20, hATR_M20, hRSI_M20, hADX_M20, hBB_M20;
// M15
int hEMA21_M15, hATR_M15, hRSI_M15, hADX_M15, hBB_M15;
// M6
int hFastEMA_M6, hSlowEMA_M6, hATR_M6, hRSI_M6, hADX_M6;
// M5
int hFastEMA_M5, hSlowEMA_M5, hTrendEMA_M5, hLongEMA_M5;
int hATR_M5, hRSI_M5, hMFI_M5, hBB_M5, hStoch_M5, hADX_M5;

//====================================================================
//  ESTRUCTURAS
//====================================================================
struct MFETracker
{
   ulong  ticket;
   double entryPrice;
   double originalTP;
   double originalSL;
   double peakFav;
   double peakPrice;
   int    extensions;
   bool   isBuy;
   double lockedProfit;
};

struct TradeInfo
{
   ulong    ticket;
   datetime openTime;
   double   entryPrice;
   bool     isBuy;
};

struct MultiTradeSet
{
   datetime openTime;
   int      count;
   ulong    tickets[5];
   bool     isBuy;
   double   entryPrice;
   double   sl;
};

//====================================================================
//  ARRAYS GLOBALES
//====================================================================
MFETracker    g_mfeTrades[100];
int           g_mfeCount       = 0;
TradeInfo     g_openTrades[100];
int           g_openTradeCount = 0;
MultiTradeSet g_tradeSets[20];
int           g_tradeSetCount  = 0;
double        g_tradeHistory[100];
int           g_histHead       = 0;
int           g_histCount      = 0;

//====================================================================
//  VARIABLES DE ESTADO GLOBAL
//====================================================================
ENUM_CAP_MODE   g_capMode      = CAP_NANO;
ENUM_MKT_REGIME g_regime       = REGIME_TREND;
ENUM_RECOVERY   g_recoveryMode = REC_NONE;

// Capital & riesgo
double g_riskPct, g_dailyLossUSD, g_dailyProfitUSD;
double g_minProfitLock, g_profitRetrace;
double g_trailingMult, g_scalperRR;
int    g_maxTradesDay, g_maxBarsOpen, g_maxNegBars;
double g_partialAt1R, g_partialAt2R;
int    g_multiTradeCount = 1;

// Kelly
double g_kellyRiskPct = 1.0;
double g_kellyWinRate = 0.55;
double g_kellyAvgWin  = 0.0;
double g_kellyAvgLoss = 0.0;
double g_kellyPF      = 1.0;
int    g_kellySamples = 0;
bool   g_kellyReady   = false;

// Compound
double g_compoundBoost      = 1.0;
double g_compoundPeakBal    = 0.0;
double g_compoundDayGainPct = 0.0;
bool   g_compoundActive     = false;
double g_realizedGainToday  = 0.0;

// Recovery
int      g_consecLosses       = 0;
int      g_dailyLosses        = 0;
int      g_dailyWins          = 0;
double   g_recoveryMult_state = 1.0;
datetime g_recoveryStartTime  = 0;
int      g_smartModeMinScore  = 85;

// Sesgo multi-TF
bool g_sesgoUp=false, g_sesgoDn=false;
bool g_h1Up  =false, g_h1Dn  =false;
bool g_m20Up =false, g_m20Dn =false;
bool g_m15Up =false, g_m15Dn =false;
bool g_m6Up  =false, g_m6Dn  =false;
bool g_m5Up  =false, g_m5Dn  =false;

// Range/Breakout
double   g_rangeHigh=0, g_rangeLow=0;
bool     g_dayInvalid=false, g_initialized=false, g_triggered=false;
datetime g_breakoutTime=0;

// Estado diario
int      g_tradesToday=0;
double   g_dayStartBal=0;
datetime g_lastDay=0;
bool     g_partial1Done=false, g_partial2Done=false;
bool     g_beMoved=false;
double   g_peakProfit=0;

// Caché de indicadores
double   g_atr_cached   =0;
double   g_atr_h1_cached=0;
double   g_atr_d1_cached=0;
double   g_bbMid_cached =0;
double   g_adxVal       =0;
double   g_atrRatio     =0;
double   g_rsiM5_cached =50;
double   g_rsiH1_cached =50;
double   g_rsiD1_cached =50;
datetime g_lastBarM5    =0;

// Estadísticas
int    g_winsToday  =0, g_lossesToday=0;
int    g_totalWins  =0, g_totalLosses=0;
double g_totalWon   =0, g_totalLost  =0;
double g_maxDrawdown=0, g_equityPeak =0;

// Info de última entrada
int                g_lastEntryScore = 0;
ENUM_ENTRY_PATTERN g_lastPattern    = PAT_NONE;

//====================================================================
//  OnInit
//====================================================================
int OnInit()
{
   // ── Crear handles D1 ──
   hEMA50_D1  = iMA  (_Symbol, PERIOD_D1, 50, 0, MODE_EMA, PRICE_CLOSE);
   hEMA200_D1 = iMA  (_Symbol, PERIOD_D1, 200, 0, MODE_EMA, PRICE_CLOSE);
   hATR_D1    = iATR (_Symbol, PERIOD_D1, InpATRPeriod);
   hRSI_D1    = iRSI (_Symbol, PERIOD_D1, InpRSIPeriod, PRICE_CLOSE);
   hADX_D1    = iADX (_Symbol, PERIOD_D1, InpADXPeriod);

   // ── Crear handles H1 ──
   hEMA21_H1  = iMA  (_Symbol, PERIOD_H1, 21, 0, MODE_EMA, PRICE_CLOSE);
   hEMA50_H1  = iMA  (_Symbol, PERIOD_H1, 50, 0, MODE_EMA, PRICE_CLOSE);
   hATR_H1    = iATR (_Symbol, PERIOD_H1, InpATRPeriod);
   hRSI_H1    = iRSI (_Symbol, PERIOD_H1, InpRSIPeriod, PRICE_CLOSE);
   hADX_H1    = iADX (_Symbol, PERIOD_H1, InpADXPeriod);
   hBB_H1     = iBands(_Symbol, PERIOD_H1, InpBBPeriod, 0, 2.0, PRICE_CLOSE);

   // ── Crear handles M20 ──
   hEMA_M20   = iMA  (_Symbol, PERIOD_M20, 21, 0, MODE_EMA, PRICE_CLOSE);
   hATR_M20   = iATR (_Symbol, PERIOD_M20, InpATRPeriod);
   hRSI_M20   = iRSI (_Symbol, PERIOD_M20, InpRSIPeriod, PRICE_CLOSE);
   hADX_M20   = iADX (_Symbol, PERIOD_M20, InpADXPeriod);
   hBB_M20    = iBands(_Symbol, PERIOD_M20, InpBBPeriod, 0, 2.0, PRICE_CLOSE);

   // ── Crear handles M15 ──
   hEMA21_M15 = iMA  (_Symbol, PERIOD_M15, 21, 0, MODE_EMA, PRICE_CLOSE);
   hATR_M15   = iATR (_Symbol, PERIOD_M15, InpATRPeriod);
   hRSI_M15   = iRSI (_Symbol, PERIOD_M15, InpRSIPeriod, PRICE_CLOSE);
   hADX_M15   = iADX (_Symbol, PERIOD_M15, InpADXPeriod);
   hBB_M15    = iBands(_Symbol, PERIOD_M15, InpBBPeriod, 0, 2.0, PRICE_CLOSE);

   // ── Crear handles M6 ──
   hFastEMA_M6 = iMA (_Symbol, PERIOD_M6, InpFastEMA, 0, MODE_EMA, PRICE_CLOSE);
   hSlowEMA_M6 = iMA (_Symbol, PERIOD_M6, InpSlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   hATR_M6     = iATR(_Symbol, PERIOD_M6, InpATRPeriod);
   hRSI_M6     = iRSI(_Symbol, PERIOD_M6, InpRSIPeriod, PRICE_CLOSE);
   hADX_M6     = iADX(_Symbol, PERIOD_M6, InpADXPeriod);

   // ── Crear handles M5 ──
   hFastEMA_M5  = iMA (_Symbol, PERIOD_M5, InpFastEMA,  0, MODE_EMA, PRICE_CLOSE);
   hSlowEMA_M5  = iMA (_Symbol, PERIOD_M5, InpSlowEMA,  0, MODE_EMA, PRICE_CLOSE);
   hTrendEMA_M5 = iMA (_Symbol, PERIOD_M5, InpTrendEMA, 0, MODE_EMA, PRICE_CLOSE);
   hLongEMA_M5  = iMA (_Symbol, PERIOD_M5, InpLongEMA,  0, MODE_EMA, PRICE_CLOSE);
   hATR_M5      = iATR(_Symbol, PERIOD_M5, InpATRPeriod);
   hRSI_M5      = iRSI(_Symbol, PERIOD_M5, InpRSIPeriod, PRICE_CLOSE);
   hMFI_M5      = iMFI(_Symbol, PERIOD_M5, InpMFIPeriod, VOLUME_TICK);
   hBB_M5       = iBands(_Symbol, PERIOD_M5, InpBBPeriod, 0, 2.0, PRICE_CLOSE);
   hStoch_M5    = iStochastic(_Symbol, PERIOD_M5, InpStochK, InpStochD, 3, MODE_SMA, STO_LOWHIGH);
   hADX_M5      = iADX(_Symbol, PERIOD_M5, InpADXPeriod);

   // ── Validar TODOS los handles ──
   int handles[] = {
      hEMA50_D1, hEMA200_D1, hATR_D1, hRSI_D1, hADX_D1,
      hEMA21_H1, hEMA50_H1, hATR_H1, hRSI_H1, hADX_H1, hBB_H1,
      hEMA_M20, hATR_M20, hRSI_M20, hADX_M20, hBB_M20,
      hEMA21_M15, hATR_M15, hRSI_M15, hADX_M15, hBB_M15,
      hFastEMA_M6, hSlowEMA_M6, hATR_M6, hRSI_M6, hADX_M6,
      hFastEMA_M5, hSlowEMA_M5, hTrendEMA_M5, hLongEMA_M5,
      hATR_M5, hRSI_M5, hMFI_M5, hBB_M5, hStoch_M5, hADX_M5
   };
   for(int i = 0; i < ArraySize(handles); i++)
   {
      if(handles[i] == INVALID_HANDLE)
      { Alert("❌ Handle #", i, " inválido – EA detenido"); return INIT_FAILED; }
   }

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(10);
   trade.SetTypeFilling(ORDER_FILLING_IOC);

   g_dayStartBal     = AccountInfoDouble(ACCOUNT_BALANCE);
   g_equityPeak      = g_dayStartBal;
   g_compoundPeakBal = g_dayStartBal;

   LoadKellyHistory();
   DetectCapitalMode();
   DailyReset();

   Print("✅ QQ v9.0 Pro | $", DoubleToString(g_dayStartBal,2),
         " | ", CapModeStr(),
         " | Trades/set: ", g_multiTradeCount,
         " | Score mín: ", InpMinEntryScore,
         " | Kelly: ", InpKellyOn?"ON":"OFF",
         " | MFE: ", InpMFEOn?"ON":"OFF");
   return INIT_SUCCEEDED;
}

//====================================================================
//  OnDeinit
//====================================================================
void OnDeinit(const int reason)
{
   Comment("");
   int h[] = {
      hEMA50_D1, hEMA200_D1, hATR_D1, hRSI_D1, hADX_D1,
      hEMA21_H1, hEMA50_H1, hATR_H1, hRSI_H1, hADX_H1, hBB_H1,
      hEMA_M20, hATR_M20, hRSI_M20, hADX_M20, hBB_M20,
      hEMA21_M15, hATR_M15, hRSI_M15, hADX_M15, hBB_M15,
      hFastEMA_M6, hSlowEMA_M6, hATR_M6, hRSI_M6, hADX_M6,
      hFastEMA_M5, hSlowEMA_M5, hTrendEMA_M5, hLongEMA_M5,
      hATR_M5, hRSI_M5, hMFI_M5, hBB_M5, hStoch_M5, hADX_M5
   };
   for(int i = 0; i < ArraySize(h); i++) IndicatorRelease(h[i]);
}

//====================================================================
//  OnTick – Bucle principal
//====================================================================
void OnTick()
{
   CheckDayReset();
   UpdateAllBias();
   DetectMarketRegime();
   UpdateRecoveryState();
   UpdateCompoundAccelerator();
   DetectCapitalMode();   // Actualizar multiTradeCount con equity en tiempo real

   if(!g_dayInvalid)
   {
      datetime curBarM5 = iTime(_Symbol, PERIOD_M5, 0);
      bool newBarM5     = (curBarM5 != g_lastBarM5);
      if(newBarM5) g_lastBarM5 = curBarM5;

      // Entradas solo en cierre de vela (evita entradas prematuras intra-vela)
      if(newBarM5 || !InpRequireCandleClose)
      {
         BuildRange();
         ValidateRange();
         SearchPrecisionEntry(true);
         SearchPrecisionEntry(false);
      }
   }

   ManageOpenTrades();
   UpdateMFETracker();
   TrackClosedTrades();
   UpdateKellyFromHistory();
   UpdateDrawdown();
   DrawPanel();
}

//====================================================================
//  RESET DIARIO
//====================================================================
void DailyReset()
{
   g_rangeHigh=0; g_rangeLow=0;
   g_dayInvalid=false; g_initialized=false;
   g_triggered=false; g_breakoutTime=0;
   g_sesgoUp=false; g_sesgoDn=false;
   g_h1Up=false; g_h1Dn=false;
   g_m20Up=false; g_m20Dn=false;
   g_m15Up=false; g_m15Dn=false;
   g_m6Up=false; g_m6Dn=false;
   g_m5Up=false; g_m5Dn=false;
   g_tradesToday=0; g_peakProfit=0;
   g_partial1Done=false; g_partial2Done=false;
   g_beMoved=false;
   g_openTradeCount=0; g_mfeCount=0; g_tradeSetCount=0;
   g_winsToday=0; g_lossesToday=0; g_totalWon=0; g_totalLost=0;
   g_compoundBoost=1.0; g_compoundActive=false;
   g_realizedGainToday=0.0;
   g_compoundPeakBal=AccountInfoDouble(ACCOUNT_BALANCE);
   g_dailyLosses=0; g_dailyWins=0;
   g_lastEntryScore=0; g_lastPattern=PAT_NONE;

   // Anti-deadlock: reducir consecLosses si excede umbral global
   if(g_consecLosses >= InpGlobalLossReset)
   {
      Print("🔄 AUTO-RESET Recovery: consecLosses=",g_consecLosses," → 1 (desbloqueado)");
      g_consecLosses = 1;
   }
   g_recoveryStartTime = TimeCurrent();
   DetectCapitalMode();
}

void CheckDayReset()
{
   datetime today = iTime(_Symbol, PERIOD_D1, 0);
   if(today != g_lastDay)
   { g_dayStartBal = AccountInfoDouble(ACCOUNT_BALANCE); g_lastDay = today; DailyReset(); }
}

//====================================================================
//  DETECCIÓN DE CAPITAL Y MULTI-TRADE
//  Se ejecuta cada tick para que refleje equity actualizado
//====================================================================
void DetectCapitalMode()
{
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);

   // Número de trades simultáneos según equity ACTUAL
   if(InpMultiTradeOn)
   {
      if     (eq >= 250.0) g_multiTradeCount = 5;
      else if(eq >= 130.0) g_multiTradeCount = 4;
      else if(eq >= 50.0)  g_multiTradeCount = 3;
      else if(eq >= 25.0)  g_multiTradeCount = 2;
      else                 g_multiTradeCount = 1;
   }
   else g_multiTradeCount = 1;

   if(!InpAutoCapital)
   {
      g_capMode=CAP_STANDARD; g_riskPct=InpRiskPercent;
      g_dailyLossUSD=eq*0.03; g_dailyProfitUSD=eq*0.08;
      g_minProfitLock=eq*0.010; g_profitRetrace=eq*0.004;
      g_trailingMult=1.0; g_scalperRR=1.8;
      g_maxTradesDay=8; g_maxBarsOpen=120; g_maxNegBars=20;
      g_partialAt1R=0.30; g_partialAt2R=0.40; return;
   }

   if(eq < 25.0)
   { g_capMode=CAP_NANO; g_riskPct=1.2;
     g_dailyLossUSD=eq*0.07; g_dailyProfitUSD=eq*0.20;
     g_minProfitLock=eq*0.025; g_profitRetrace=eq*0.008;
     g_trailingMult=0.60; g_scalperRR=2.5;
     g_maxTradesDay=3; g_maxBarsOpen=40; g_maxNegBars=6;
     g_partialAt1R=0.50; g_partialAt2R=0.40; }
   else if(eq < 50.0)
   { g_capMode=CAP_MICRO; g_riskPct=1.0;
     g_dailyLossUSD=eq*0.06; g_dailyProfitUSD=eq*0.18;
     g_minProfitLock=eq*0.020; g_profitRetrace=eq*0.008;
     g_trailingMult=0.65; g_scalperRR=2.2;
     g_maxTradesDay=4; g_maxBarsOpen=50; g_maxNegBars=8;
     g_partialAt1R=0.45; g_partialAt2R=0.40; }
   else if(eq < 130.0)
   { g_capMode=CAP_SMALL; g_riskPct=0.9;
     g_dailyLossUSD=eq*0.05; g_dailyProfitUSD=eq*0.14;
     g_minProfitLock=eq*0.015; g_profitRetrace=eq*0.006;
     g_trailingMult=0.75; g_scalperRR=2.0;
     g_maxTradesDay=5; g_maxBarsOpen=70; g_maxNegBars=12;
     g_partialAt1R=0.38; g_partialAt2R=0.40; }
   else if(eq < 250.0)
   { g_capMode=CAP_MEDIUM; g_riskPct=0.80;
     g_dailyLossUSD=eq*0.04; g_dailyProfitUSD=eq*0.12;
     g_minProfitLock=eq*0.012; g_profitRetrace=eq*0.005;
     g_trailingMult=0.85; g_scalperRR=1.9;
     g_maxTradesDay=6; g_maxBarsOpen=90; g_maxNegBars=15;
     g_partialAt1R=0.32; g_partialAt2R=0.40; }
   else if(eq < 1000.0)
   { g_capMode=CAP_STANDARD; g_riskPct=0.70;
     g_dailyLossUSD=eq*0.035; g_dailyProfitUSD=eq*0.10;
     g_minProfitLock=eq*0.010; g_profitRetrace=eq*0.004;
     g_trailingMult=0.90; g_scalperRR=1.8;
     g_maxTradesDay=8; g_maxBarsOpen=100; g_maxNegBars=18;
     g_partialAt1R=0.30; g_partialAt2R=0.40; }
   else
   { g_capMode=CAP_LARGE; g_riskPct=InpRiskPercent*0.80;
     g_dailyLossUSD=eq*0.025; g_dailyProfitUSD=eq*0.08;
     g_minProfitLock=eq*0.008; g_profitRetrace=eq*0.003;
     g_trailingMult=1.0; g_scalperRR=1.8;
     g_maxTradesDay=10; g_maxBarsOpen=120; g_maxNegBars=20;
     g_partialAt1R=0.28; g_partialAt2R=0.38; }
}

string CapModeStr()
{
   string c[] = {"NANO(<$25)","MICRO($25-49)","SMALL($50-129)",
                 "MEDIUM($130-249)","STD($250-999)","LARGE($1K+)"};
   return c[(int)g_capMode] + " | " + IntegerToString(g_multiTradeCount) + "T";
}

//====================================================================
//  SESGO MULTI-TIMEFRAME: D1, H1, M20, M15, M6, M5
//====================================================================
void UpdateAllBias()
{
   // D1
   double e50d[1], e200d[1], rD[1];
   if(CopyBuffer(hEMA50_D1,0,0,1,e50d)>0 && CopyBuffer(hEMA200_D1,0,0,1,e200d)>0)
   { g_sesgoUp=e50d[0]>e200d[0]; g_sesgoDn=e50d[0]<e200d[0]; }
   if(CopyBuffer(hRSI_D1,0,0,1,rD)>0) g_rsiD1_cached=rD[0];

   // H1
   double e21h[1], e50h[1], rH[1];
   if(CopyBuffer(hEMA21_H1,0,0,1,e21h)>0 && CopyBuffer(hEMA50_H1,0,0,1,e50h)>0 &&
      CopyBuffer(hRSI_H1,0,0,1,rH)>0)
   { g_h1Up=(e21h[0]>e50h[0])&&(rH[0]>50);
     g_h1Dn=(e21h[0]<e50h[0])&&(rH[0]<50);
     g_rsiH1_cached=rH[0]; }

   // M20
   double em20[1], rm20[1], am20[1];
   if(CopyBuffer(hEMA_M20,0,0,1,em20)>0 && CopyBuffer(hRSI_M20,0,0,1,rm20)>0 &&
      CopyBuffer(hADX_M20,0,0,1,am20)>0)
   { double cM20=iClose(_Symbol,PERIOD_M20,1);
     g_m20Up=(cM20>em20[0])&&(rm20[0]>51)&&(am20[0]>18);
     g_m20Dn=(cM20<em20[0])&&(rm20[0]<49)&&(am20[0]>18); }

   // M15
   double em15[1], rm15[1], am15[1];
   if(CopyBuffer(hEMA21_M15,0,0,1,em15)>0 && CopyBuffer(hRSI_M15,0,0,1,rm15)>0 &&
      CopyBuffer(hADX_M15,0,0,1,am15)>0)
   { double cM15=iClose(_Symbol,PERIOD_M15,1);
     g_m15Up=(cM15>em15[0])&&(rm15[0]>51)&&(am15[0]>18);
     g_m15Dn=(cM15<em15[0])&&(rm15[0]<49)&&(am15[0]>18); }

   // M6
   double fm6[1], sm6[1], rm6[1], am6[1];
   if(CopyBuffer(hFastEMA_M6,0,0,1,fm6)>0 && CopyBuffer(hSlowEMA_M6,0,0,1,sm6)>0 &&
      CopyBuffer(hRSI_M6,0,0,1,rm6)>0 && CopyBuffer(hADX_M6,0,0,1,am6)>0)
   { g_m6Up=(fm6[0]>sm6[0])&&(rm6[0]>52)&&(am6[0]>15);
     g_m6Dn=(fm6[0]<sm6[0])&&(rm6[0]<48)&&(am6[0]>15); }

   // M5
   double fm5[1], sm5[1], tm5[1], rm5[1], am5[1];
   if(CopyBuffer(hFastEMA_M5,0,0,1,fm5)>0 && CopyBuffer(hSlowEMA_M5,0,0,1,sm5)>0 &&
      CopyBuffer(hTrendEMA_M5,0,0,1,tm5)>0 && CopyBuffer(hRSI_M5,0,0,1,rm5)>0 &&
      CopyBuffer(hADX_M5,0,0,1,am5)>0)
   { g_m5Up=(fm5[0]>sm5[0])&&(sm5[0]>tm5[0])&&(rm5[0]>52);
     g_m5Dn=(fm5[0]<sm5[0])&&(sm5[0]<tm5[0])&&(rm5[0]<48);
     g_rsiM5_cached=rm5[0]; }

   // Cachés ATR
   double aM5b[1], aH1b[1], aD1b[1];
   if(CopyBuffer(hATR_M5,0,0,1,aM5b)>0 && aM5b[0]>0) g_atr_cached=aM5b[0];
   if(CopyBuffer(hATR_H1,0,0,1,aH1b)>0 && aH1b[0]>0) g_atr_h1_cached=aH1b[0];
   if(CopyBuffer(hATR_D1,0,0,1,aD1b)>0 && aD1b[0]>0)
   { g_atr_d1_cached=aD1b[0];
     if(aM5b[0]>0) g_atrRatio=aM5b[0]/aD1b[0]; }

   double bbM[1];
   if(CopyBuffer(hBB_M5,0,0,1,bbM)>0) g_bbMid_cached=bbM[0];
}

//====================================================================
//  RÉGIMEN DE MERCADO
//====================================================================
void DetectMarketRegime()
{
   double axH1[1], axM15[1], axM5[1];
   double sum=0; int cnt=0;
   if(CopyBuffer(hADX_H1, 0,0,1,axH1) >0) { sum+=axH1[0];  cnt++; }
   if(CopyBuffer(hADX_M15,0,0,1,axM15)>0) { sum+=axM15[0]; cnt++; }
   if(CopyBuffer(hADX_M5, 0,0,1,axM5) >0) { sum+=axM5[0];  cnt++; }
   if(cnt>0) g_adxVal=sum/cnt;

   if(g_atrRatio>0.08)    g_regime=REGIME_VOLATILE;
   else if(g_adxVal>=23)  g_regime=REGIME_TREND;
   else                   g_regime=REGIME_RANGE;
}
string RegimeStr()
{ return g_regime==REGIME_TREND?"📈TREND":(g_regime==REGIME_RANGE?"↔RANGE":"⚡VOLATILE"); }

//====================================================================
//  RECOVERY ANTI-DEADLOCK – Completamente rediseñado
//====================================================================
void UpdateRecoveryState()
{
   if(!InpRecoveryOn) { g_recoveryMode=REC_NONE; g_recoveryMult_state=1.0; return; }

   // Pausa diaria: solo ese día, no indefinida
   if(g_dailyLosses >= InpDailyLossLimit)
   { g_recoveryMode=REC_PAUSE; g_recoveryMult_state=0.0; g_dayInvalid=true; return; }

   // Timeout: reducir consecLosses gradualmente si lleva mucho en recovery
   if(g_recoveryStartTime>0 && g_recoveryMode>=REC_REDUCE)
   {
      double hoursIn=(double)(TimeCurrent()-g_recoveryStartTime)/3600.0;
      if(hoursIn >= InpRecoveryTimeoutH)
      { g_consecLosses=MathMax(0,g_consecLosses-1);
        g_recoveryStartTime=TimeCurrent();
        Print("⏰ Recovery timeout → consecLosses=",g_consecLosses); }
   }

   ENUM_RECOVERY prev=g_recoveryMode;
   if(g_consecLosses==0)      { g_recoveryMode=REC_NONE;    g_recoveryMult_state=1.00; }
   else if(g_consecLosses==1) { g_recoveryMode=REC_CAUTION; g_recoveryMult_state=0.80; }
   else if(g_consecLosses==2) { g_recoveryMode=REC_REDUCE;  g_recoveryMult_state=0.60; }
   else                       { g_recoveryMode=REC_SMART;   g_recoveryMult_state=0.50; }

   if(prev==REC_NONE && g_recoveryMode!=REC_NONE)
      g_recoveryStartTime=TimeCurrent();

   // En SMART: score alto pero nunca bloqueo total
   g_smartModeMinScore=(g_recoveryMode==REC_SMART)?85:InpMinEntryScore;
}
string RecoveryStr()
{ string s[]={"✅NORMAL","⚠️CAUTION","🔶REDUCE","🔴SMART","⛔PAUSA"}; return s[(int)g_recoveryMode]; }

//====================================================================
//  ★ SISTEMA DE PUNTUACIÓN DE ENTRADA (0–100)
//  Evalúa 5 categorías antes de abrir cualquier trade
//  Previene entradas prematuras que van en contra antes de ir a favor
//====================================================================
int CalcEntryScore(bool isBuy)
{
   int score = 0;

   // 1. ALINEACIÓN MULTI-TF  ── máx 30 pts (5 por TF)
   int tfOk = 0;
   if(isBuy) {
      if(g_sesgoUp) tfOk++;
      if(g_h1Up)    tfOk++;
      if(g_m20Up)   tfOk++;
      if(g_m15Up)   tfOk++;
      if(g_m6Up)    tfOk++;
      if(g_m5Up)    tfOk++;
   } else {
      if(g_sesgoDn) tfOk++;
      if(g_h1Dn)    tfOk++;
      if(g_m20Dn)   tfOk++;
      if(g_m15Dn)   tfOk++;
      if(g_m6Dn)    tfOk++;
      if(g_m5Dn)    tfOk++;
   }
   score += tfOk * 5;
   if(tfOk < InpMinTFAlignment) return 0; // Corte duro: no puntuar si hay muy pocos TF

   // 2. PATRÓN DE VELA CONFIRMADA  ── máx 20 pts
   ENUM_ENTRY_PATTERN pat = DetectCandlePattern(isBuy);
   g_lastPattern = pat;
   switch(pat) {
      case PAT_ENGULFING:    score += 20; break;
      case PAT_PINBAR:       score += 16; break;
      case PAT_INSIDE_BREAK: score += 12; break;
      case PAT_MOMENTUM:     score += 8;  break;
      default: break; // 0 pts, se puede compensar con otros factores
   }

   // 3. MOMENTUM RSI MULTI-TF  ── máx 20 pts
   if(isBuy) {
      if(g_rsiM5_cached>52 && g_rsiM5_cached<70) score+=7;
      if(g_rsiH1_cached>50 && g_rsiH1_cached<70) score+=7;
      if(g_rsiD1_cached>50 && g_rsiD1_cached<72) score+=6;
   } else {
      if(g_rsiM5_cached<48 && g_rsiM5_cached>30) score+=7;
      if(g_rsiH1_cached<50 && g_rsiH1_cached>30) score+=7;
      if(g_rsiD1_cached<50 && g_rsiD1_cached>28) score+=6;
   }

   // 4. VOLATILIDAD ÓPTIMA  ── máx 15 pts
   if(g_atr_cached>0 && g_atr_d1_cached>0)
   {
      double atrPct = g_atr_cached / g_atr_d1_cached;
      if(atrPct>=0.018 && atrPct<=0.060)     score+=15;
      else if(atrPct>=0.010 && atrPct<0.018) score+=8;
      else if(atrPct>0.060 && atrPct<=0.090) score+=6;
      // > 9% de ATR diario = mercado demasiado volátil, no sumar
   }

   // 5. SESIÓN/HORARIO  ── máx 15 pts
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   int h = dt.hour;
   if     (h>=7  && h<12) score+=15;  // Sesión Londres (optimal)
   else if(h>=12 && h<17) score+=12;  // Overlap Londres–NY
   else if(h>=17 && h<20) score+=8;   // Sesión NY

   return score;
}

//====================================================================
//  DETECCIÓN DE PATRONES DE VELA
//====================================================================
ENUM_ENTRY_PATTERN DetectCandlePattern(bool isBuy)
{
   double o1=iOpen (_Symbol,PERIOD_M5,1), h1=iHigh (_Symbol,PERIOD_M5,1);
   double l1=iLow  (_Symbol,PERIOD_M5,1), c1=iClose(_Symbol,PERIOD_M5,1);
   double o2=iOpen (_Symbol,PERIOD_M5,2), h2=iHigh (_Symbol,PERIOD_M5,2);
   double l2=iLow  (_Symbol,PERIOD_M5,2), c2=iClose(_Symbol,PERIOD_M5,2);
   if(o1==0||o2==0) return PAT_NONE;

   double body1 =MathAbs(c1-o1), body2=MathAbs(c2-o2);
   double range1=h1-l1,           range2=h2-l2;
   if(range1<=0||range2<=0) return PAT_NONE;

   // ── Engulfing (vela 1 envuelve completamente a vela 2) ──
   if(isBuy  && c2<o2 && c1>o1 && c1>=o2 && o1<=c2 && body1>=body2*0.85) return PAT_ENGULFING;
   if(!isBuy && c2>o2 && c1<o1 && c1<=o2 && o1>=c2 && body1>=body2*0.85) return PAT_ENGULFING;

   // ── Pin bar ──
   {
      double upWick =h1-MathMax(o1,c1);
      double dnWick =MathMin(o1,c1)-l1;
      bool smallBody=(body1<range1*0.35);
      if(isBuy  && smallBody && dnWick>body1*2.0 && dnWick>upWick*1.5) return PAT_PINBAR;
      if(!isBuy && smallBody && upWick>body1*2.0 && upWick>dnWick*1.5) return PAT_PINBAR;
   }

   // ── Inside bar break (vela 2 inside de vela 3, vela 1 rompe) ──
   double o3=iOpen(_Symbol,PERIOD_M5,3), h3=iHigh(_Symbol,PERIOD_M5,3);
   double l3=iLow(_Symbol,PERIOD_M5,3),  c3=iClose(_Symbol,PERIOD_M5,3);
   if(o3!=0 && h3>0 && l3>0)
   {
      bool inside=(h2<=h3&&l2>=l3);
      if(inside && isBuy  && c1>h3 && body1>body2*0.5) return PAT_INSIDE_BREAK;
      if(inside && !isBuy && c1<l3 && body1>body2*0.5) return PAT_INSIDE_BREAK;
   }

   // ── Vela momentum ──
   if(isBuy  && c1>o1 && (body1/range1)>0.62 && body1>body2) return PAT_MOMENTUM;
   if(!isBuy && c1<o1 && (body1/range1)>0.62 && body1>body2) return PAT_MOMENTUM;

   return PAT_NONE;
}

string PatternStr(ENUM_ENTRY_PATTERN p)
{
   switch(p) {
      case PAT_ENGULFING:    return "ENGULFING";
      case PAT_PINBAR:       return "PINBAR";
      case PAT_INSIDE_BREAK: return "INSIDE_BREAK";
      case PAT_MOMENTUM:     return "MOMENTUM";
      default:               return "NONE";
   }
}

//====================================================================
//  CONFIRMACIÓN DE VOLUMEN
//====================================================================
bool ConfirmVolume()
{
   if(!InpRequireVolume) return true;
   long vol1=iVolume(_Symbol,PERIOD_M5,1);
   long sumVol=0;
   for(int i=2;i<=21;i++) sumVol+=iVolume(_Symbol,PERIOD_M5,i);
   double avgVol=(double)sumVol/20.0;
   if(avgVol<=0) return true;
   return ((double)vol1 >= avgVol*InpVolumeMult);
}

//====================================================================
//  CONSTRUCCIÓN DE RANGO HORARIO
//====================================================================
void BuildRange()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   if(dt.hour<7||dt.hour>=10) return;
   if(g_initialized) return;

   g_rangeHigh=0; g_rangeLow=9e9;
   int bars=iBars(_Symbol,PERIOD_M5);
   for(int i=1;i<MathMin(bars,25);i++)
   {
      datetime bt=(datetime)iTime(_Symbol,PERIOD_M5,i);
      MqlDateTime bdt; TimeToStruct(bt,bdt);
      if(bdt.hour<7||bdt.hour>=9) continue;
      double h=iHigh(_Symbol,PERIOD_M5,i);
      double l=iLow (_Symbol,PERIOD_M5,i);
      if(h>g_rangeHigh) g_rangeHigh=h;
      if(l<g_rangeLow)  g_rangeLow =l;
   }
   if(g_rangeHigh>g_rangeLow) g_initialized=true;
}

void ValidateRange()
{
   if(!g_initialized) return;
   double rng=g_rangeHigh-g_rangeLow;
   double minR=1.0*_Point*10, maxR=15.0*_Point*10;
   if(rng<minR||rng>maxR) g_dayInvalid=true;
}

//====================================================================
//  ★ ENTRADA ULTRA-PRECISA – Sistema central
//  Combina score de entrada + patrón + volumen + multi-TF
//  Ejecuta multi-trade con TPs progresivos
//====================================================================
void SearchPrecisionEntry(bool isBuy)
{
   // ── Protecciones iniciales ──
   if(g_recoveryMode==REC_PAUSE) return;
   if(g_tradesToday>=g_maxTradesDay) return;

   int openPos=CountOpenPositions();
   int maxOpen=MathMin(g_maxTradesDay*g_multiTradeCount,20);
   if(openPos>=maxOpen) return;

   // Spread
   double spread=(double)SymbolInfoInteger(_Symbol,SYMBOL_SPREAD)*_Point;
   if(spread/_Point/10.0>InpMaxSpread) return;

   // Sesión
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   if(dt.hour<InpSessionStart||dt.hour>=InpSessionEnd) return;

   // Sesgo D1 obligatorio
   if(isBuy  && g_sesgoDn) return;
   if(!isBuy && g_sesgoUp) return;

   // Límites diarios de PnL
   double eq    =AccountInfoDouble(ACCOUNT_EQUITY);
   double dayPnL=eq-g_dayStartBal;
   if(dayPnL<=-g_dailyLossUSD) { g_dayInvalid=true; return; }
   if(dayPnL>= g_dailyProfitUSD) return;

   // ── Score de entrada ──
   int score   = CalcEntryScore(isBuy);
   int minScore= (g_recoveryMode==REC_SMART)?g_smartModeMinScore:InpMinEntryScore;
   if(score<minScore) return;

   if(!ConfirmVolume()) return;

   // ── ATR y parámetros SL/TP ──
   double atr=g_atr_cached;
   if(atr<=0) return;
   double atrH1=(g_atr_h1_cached>0)?g_atr_h1_cached:atr*3.0;

   // SL basado en ATR M5 con piso de ATR H1 para robustez
   double slDist=MathMax(atr*InpATR_SL_Mult, atrH1*0.35);

   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double price=isBuy?ask:bid;

   double sl=NormalizeDouble(isBuy?price-slDist:price+slDist,_Digits);

   // Verificar R:R mínimo con TP1
   if((atr*InpATR_TP1)/slDist < InpMinRR) return;

   // ── Cálculo de riesgo con Kelly + Recovery + Compound ──
   double riskPct=g_riskPct*g_recoveryMult_state*g_compoundBoost;
   riskPct=MathMax(0.10,MathMin(2.5,riskPct));

   if(InpKellyOn && g_kellyReady)
   {
      double kr=CalcKellyRisk();
      riskPct=MathMax(InpKellyMinRisk,MathMin(InpKellyMaxRisk,kr));
      riskPct*=g_recoveryMult_state*g_compoundBoost;
      riskPct=MathMax(0.10,MathMin(2.5,riskPct));
   }

   // Lote total → dividido equitativamente entre los N trades del set
   double lotBase=CalcLot(slDist,riskPct);
   if(lotBase<=0) return;

   double lotPerTrade=NormLot(lotBase/(double)g_multiTradeCount);
   if(lotPerTrade<=0) return;

   double tpMults[]={InpATR_TP1,InpATR_TP2,InpATR_TP3,InpATR_TP4,InpATR_TP5};

   // ── Ejecutar set de N trades simultáneos ──
   MultiTradeSet ts;
   ts.openTime  =TimeCurrent();
   ts.count     =0;
   ts.isBuy     =isBuy;
   ts.entryPrice=price;
   ts.sl        =sl;

   bool anyOpened=false;

   for(int t=0;t<g_multiTradeCount;t++)
   {
      double tpDist=atr*tpMults[t];
      double tp   =NormalizeDouble(isBuy?price+tpDist:price-tpDist,_Digits);
      string comm ="QQ9T"+IntegerToString(t+1)+"|S"+IntegerToString(score);

      bool ok;
      if(isBuy)  ok=trade.Buy (lotPerTrade,_Symbol,0,sl,tp,comm);
      else       ok=trade.Sell(lotPerTrade,_Symbol,0,sl,tp,comm);

      if(ok && trade.ResultRetcode()==TRADE_RETCODE_DONE)
      {
         ulong ticket=trade.ResultOrder();
         if(ts.count<5){ ts.tickets[ts.count]=ticket; ts.count++; }
         RegisterTrade(ticket,price,isBuy);
         AddMFETracker(ticket,price,sl,tp,isBuy);
         anyOpened=true;
      }
      else
      { Print("⚠️ Trade ",t+1,"/",g_multiTradeCount,
              " falló: ",trade.ResultRetcodeDescription()); }
   }

   if(anyOpened)
   {
      if(g_tradeSetCount<20){ g_tradeSets[g_tradeSetCount]=ts; g_tradeSetCount++; }
      g_tradesToday++;
      g_lastEntryScore=score;
      Print("🚀 ENTRY | ",isBuy?"BUY":"SELL",
            " | Score:",score,"/100",
            " | Pat:",PatternStr(g_lastPattern),
            " | ",g_multiTradeCount,"T × ",NormLot(lotPerTrade),"L",
            " | SL:",DoubleToString(slDist/_Point/10,1),"pts");
   }
}

//====================================================================
//  CÁLCULO DE LOTE
//====================================================================
double CalcLot(double slDist, double riskPct)
{
   double eq      =AccountInfoDouble(ACCOUNT_EQUITY);
   double riskMoney=eq*riskPct/100.0;
   double tickVal =SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   double tickSize=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tickVal<=0||tickSize<=0||slDist<=0) return 0;
   double pipValue=tickVal*(slDist/tickSize);
   if(pipValue<=0) return 0;
   return NormLot(riskMoney/pipValue);
}

double CalcKellyRisk()
{
   if(!g_kellyReady||g_kellyAvgLoss<=0) return g_riskPct;
   double b=(g_kellyAvgLoss>0)?g_kellyAvgWin/g_kellyAvgLoss:1.0;
   double p=g_kellyWinRate;
   double kf=((b*p)-(1.0-p))/b;
   kf=MathMax(0,kf)*InpKellyFraction;
   return MathMax(InpKellyMinRisk,MathMin(InpKellyMaxRisk,kf*100.0));
}

//====================================================================
//  GESTIÓN DE TRADES ABIERTOS
//====================================================================
void ManageOpenTrades()
{
   // Lock de ganancias global
   double totalPnL=0;
   for(int i=0;i<PositionsTotal();i++)
   { ulong t=PositionGetTicket(i);
     if(!PositionSelectByTicket(t)) continue;
     if(PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
     totalPnL+=PositionGetDouble(POSITION_PROFIT); }

   if(totalPnL>0)
   { if(totalPnL>g_peakProfit) g_peakProfit=totalPnL; }

   if(g_peakProfit>=g_minProfitLock && totalPnL<(g_peakProfit-g_profitRetrace))
   { CloseAllMagic(); Print("💰 Peak Lock $",DoubleToString(g_peakProfit,2)); g_peakProfit=0; return; }
   else if(totalPnL<=0) g_peakProfit=0;

   // Trailing y cierre parcial por posición
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i);
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      bool buy=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
      ApplyTrailing(t,buy);
      ApplyPartialClose(t,buy);
   }

   // Cierre forzado de trades estancados en pérdida
   for(int i=0;i<g_openTradeCount;i++)
   {
      if(!PositionSelectByTicket(g_openTrades[i].ticket)) continue;
      double pnl=PositionGetDouble(POSITION_PROFIT);
      if(pnl>=0) continue;
      datetime ot=(datetime)PositionGetInteger(POSITION_TIME);
      int barsOpen=(int)((TimeCurrent()-ot)/PeriodSeconds(PERIOD_M5));
      if(barsOpen>g_maxNegBars && pnl<0)
      { trade.PositionClose(g_openTrades[i].ticket);
        RemoveTradeTracker(g_openTrades[i].ticket);
        RemoveMFETracker(g_openTrades[i].ticket); i--;
        Print("⏱️ Cierre forzado: trade estancado ",barsOpen," barras en pérdida"); }
   }
}

//====================================================================
//  TRAILING STOP
//====================================================================
void ApplyTrailing(ulong ticket, bool isBuy)
{
   if(!PositionSelectByTicket(ticket)) return;
   double curSL=PositionGetDouble(POSITION_SL);
   double curTP=PositionGetDouble(POSITION_TP);
   double cur  =PositionGetDouble(POSITION_PRICE_CURRENT);
   double openP=PositionGetDouble(POSITION_PRICE_OPEN);
   double atr  =(g_atr_cached>0)?g_atr_cached:10*_Point;
   double dist =MathAbs(cur-openP);
   double tf   =(dist>atr*2)?0.75:g_trailingMult;
   double trail=atr*tf;

   if(isBuy)
   {
      if(cur<=openP) return;
      double nSL=NormalizeDouble(cur-trail,_Digits);
      if(nSL>curSL+_Point && nSL>=openP)
         trade.PositionModify(ticket,nSL,curTP);
   }
   else
   {
      if(cur>=openP) return;
      double nSL=NormalizeDouble(cur+trail,_Digits);
      if((nSL<curSL-_Point||curSL==0) && nSL<=openP)
         trade.PositionModify(ticket,nSL,curTP);
   }
}

//====================================================================
//  CIERRE PARCIAL
//====================================================================
void ApplyPartialClose(ulong ticket, bool isBuy)
{
   if(!PositionSelectByTicket(ticket)) return;
   double openP=PositionGetDouble(POSITION_PRICE_OPEN);
   double sl   =PositionGetDouble(POSITION_SL);
   double cur  =PositionGetDouble(POSITION_PRICE_CURRENT);
   double tp   =PositionGetDouble(POSITION_TP);
   if(sl==0||tp==0) return;
   double rDist=MathAbs(tp-openP);
   if(rDist<=0) return;

   double pnlR=isBuy?(cur-openP)/rDist:(openP-cur)/rDist;

   // Parcial 1 al ~1R → mover a breakeven
   if(!g_partial1Done && pnlR>=g_partialAt1R)
   {
      double vol=PositionGetDouble(POSITION_VOLUME);
      double mn =SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
      double cv =NormLot(vol*0.35);
      if(cv>=mn && cv<vol)
      {
         trade.PositionClosePartial(ticket,cv);
         g_partial1Done=true;
         // Breakeven
         if(PositionSelectByTicket(ticket))
         { double beSL=NormalizeDouble(isBuy?openP+_Point:openP-_Point,_Digits);
           trade.PositionModify(ticket,beSL,PositionGetDouble(POSITION_TP));
           g_beMoved=true; }
      }
   }

   // Parcial 2 al ~2R
   if(g_partial1Done && !g_partial2Done && pnlR>=g_partialAt2R*2.0)
   {
      if(!PositionSelectByTicket(ticket)) return;
      double vol=PositionGetDouble(POSITION_VOLUME);
      double mn =SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
      double cv =NormLot(vol*0.40);
      if(cv>=mn && cv<vol)
      { trade.PositionClosePartial(ticket,cv); g_partial2Done=true; }
   }
}

//====================================================================
//  MFE TRACKER
//====================================================================
void AddMFETracker(ulong ticket, double entry, double sl, double tp, bool isBuy)
{
   if(!InpMFEOn) return;
   if(g_mfeCount>=100) return;   // Protección desbordamiento corregida
   MFETracker &m=g_mfeTrades[g_mfeCount];
   m.ticket=ticket; m.entryPrice=entry; m.originalTP=tp; m.originalSL=sl;
   m.peakFav=0; m.peakPrice=entry; m.extensions=0;
   m.isBuy=isBuy; m.lockedProfit=0;
   g_mfeCount++;
}

void RemoveMFETracker(ulong ticket)
{
   for(int i=0;i<g_mfeCount;i++)
   { if(g_mfeTrades[i].ticket==ticket)
     { for(int j=i;j<g_mfeCount-1;j++) g_mfeTrades[j]=g_mfeTrades[j+1];
       g_mfeCount--; return; } }
}

void UpdateMFETracker()
{
   if(!InpMFEOn) return;
   for(int i=0;i<g_mfeCount;i++)
   {
      MFETracker &m=g_mfeTrades[i];
      if(!PositionSelectByTicket(m.ticket)) { RemoveMFETracker(m.ticket); i--; continue; }
      double cur=PositionGetDouble(POSITION_PRICE_CURRENT);
      double sl =PositionGetDouble(POSITION_SL);
      double tp =PositionGetDouble(POSITION_TP);
      double fav=m.isBuy?(cur-m.entryPrice):(m.entryPrice-cur);
      if(fav>m.peakFav){ m.peakFav=fav; m.peakPrice=cur; }

      double tpDist=MathAbs(m.originalTP-m.entryPrice);
      if(tpDist>0 && fav>=tpDist*InpMFE_ExtendAt && m.extensions<InpMFE_MaxExtensions)
      {
         double newTP=m.isBuy?cur+tpDist*InpMFE_ExtendMult:cur-tpDist*InpMFE_ExtendMult;
         double newSL=m.isBuy?m.entryPrice+fav*InpMFE_LockPct:m.entryPrice-fav*InpMFE_LockPct;
         bool slOk=m.isBuy?(newSL>sl):(newSL<sl||sl==0);
         if(slOk)
         { trade.PositionModify(m.ticket,NormalizeDouble(newSL,_Digits),
                                         NormalizeDouble(newTP,_Digits));
           m.originalTP=newTP; m.extensions++; m.lockedProfit=fav*InpMFE_LockPct;
           Print("📈 MFE ext#",m.extensions," | ticket:",m.ticket); }
      }
   }
}

//====================================================================
//  COMPOUND ACCELERATOR
//====================================================================
void UpdateCompoundAccelerator()
{
   if(!InpCompoundOn) { g_compoundBoost=1.0; g_compoundActive=false; return; }
   double bal=AccountInfoDouble(ACCOUNT_BALANCE);
   double eq =AccountInfoDouble(ACCOUNT_EQUITY);
   if(bal>g_compoundPeakBal) g_compoundPeakBal=bal;
   // Reset por drawdown desde pico
   double ddPeak=(g_compoundPeakBal>0)?(g_compoundPeakBal-eq)/g_compoundPeakBal*100.0:0;
   if(ddPeak>=InpCompound_DDReset)
   { g_compoundBoost=1.0; g_compoundActive=false;
     Print("📉 Compound reset DD=",DoubleToString(ddPeak,2),"%"); return; }
   // Ganancia realizada del día (solo trades cerrados, no equity flotante)
   g_compoundDayGainPct=(g_dayStartBal>0)?g_realizedGainToday/g_dayStartBal*100.0:0;
   if(g_compoundDayGainPct>=InpCompound_Trigger)
   { g_compoundActive=true;
     double ratio=g_compoundDayGainPct/InpCompound_Trigger;
     g_compoundBoost=MathMin(InpCompound_MaxBoost,1.0+(ratio-1.0)*InpCompound_Boost*0.3); }
   else { g_compoundBoost=1.0; g_compoundActive=false; }
}

//====================================================================
//  KELLY HISTORY
//====================================================================
void AddToKellyHistory(double profit)
{ g_tradeHistory[g_histHead]=profit;
  g_histHead=(g_histHead+1)%100;
  if(g_histCount<100) g_histCount++; }

void LoadKellyHistory()
{
   HistorySelect(TimeCurrent()-86400*30,TimeCurrent());
   int total=HistoryDealsTotal();
   for(int i=MathMax(0,total-100);i<total;i++)
   { ulong t=HistoryDealGetTicket(i); if(t==0) continue;
     if(HistoryDealGetInteger(t,DEAL_MAGIC)!=InpMagic) continue;
     if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(t,DEAL_ENTRY)!=DEAL_ENTRY_OUT) continue;
     AddToKellyHistory(HistoryDealGetDouble(t,DEAL_PROFIT)); }
}

void UpdateKellyFromHistory()
{
   if(g_histCount<InpKellySampleSize){ g_kellyReady=false; return; }
   int w=0,l=0; double won=0,lost=0;
   for(int i=0;i<g_histCount;i++)
   { double p=g_tradeHistory[i];
     if(p>0){w++;won+=p;} else if(p<0){l++;lost+=MathAbs(p);} }
   int tot=w+l;
   if(tot<InpKellySampleSize){ g_kellyReady=false; return; }
   g_kellyWinRate=(double)w/tot;
   g_kellyAvgWin =(w>0)?won/w:0;
   g_kellyAvgLoss=(l>0)?lost/l:0;
   g_kellyPF     =(g_kellyAvgLoss>0)?g_kellyAvgWin/g_kellyAvgLoss:1.0;
   g_kellySamples=tot;
   g_kellyReady  =true;
}

//====================================================================
//  TRACKING DE TRADES CERRADOS
//====================================================================
void TrackClosedTrades()
{
   static int hC=0;
   HistorySelect(0,TimeCurrent());
   int total=HistoryDealsTotal();
   if(total==hC) return;
   for(int i=hC;i<total;i++)
   {
      ulong t=HistoryDealGetTicket(i); if(t==0) continue;
      if(HistoryDealGetInteger(t,DEAL_MAGIC)!=InpMagic) continue;
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(t,DEAL_ENTRY)!=DEAL_ENTRY_OUT) continue;
      double profit=HistoryDealGetDouble(t,DEAL_PROFIT);
      if(profit>0)
      { g_winsToday++; g_totalWins++; g_totalWon+=profit;
        g_consecLosses=0; g_dailyWins++;
        g_realizedGainToday+=profit;
        AddToKellyHistory(profit); }
      else if(profit<0)
      { g_lossesToday++; g_totalLosses++; g_totalLost+=MathAbs(profit);
        g_consecLosses++; g_dailyLosses++;
        AddToKellyHistory(profit);
        Print("⚠️ Pérdida día#",g_dailyLosses,
              " Global#",g_consecLosses,
              ": $",DoubleToString(profit,2),
              " | ",RecoveryStr()); }
   }
   hC=total;
}

void UpdateDrawdown()
{
   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq>g_equityPeak) g_equityPeak=eq;
   if(g_equityPeak>0)
   { double dd=(g_equityPeak-eq)/g_equityPeak*100.0;
     if(dd>g_maxDrawdown) g_maxDrawdown=dd; }
}

//====================================================================
//  HELPERS
//====================================================================
void RegisterTrade(ulong ticket, double entry, bool isBuy)
{ if(ticket==0||g_openTradeCount>=100) return;
  g_openTrades[g_openTradeCount].ticket    =ticket;
  g_openTrades[g_openTradeCount].openTime  =TimeCurrent();
  g_openTrades[g_openTradeCount].entryPrice=entry;
  g_openTrades[g_openTradeCount].isBuy     =isBuy;
  g_openTradeCount++; }

int FindTradeTracker(ulong ticket)
{ for(int i=0;i<g_openTradeCount;i++) if(g_openTrades[i].ticket==ticket) return i; return -1; }

void RemoveTradeTracker(ulong ticket)
{ for(int i=0;i<g_openTradeCount;i++)
  { if(g_openTrades[i].ticket==ticket)
    { for(int j=i;j<g_openTradeCount-1;j++) g_openTrades[j]=g_openTrades[j+1];
      g_openTradeCount--; return; } } }

int CountOpenPositions()
{ int c=0; for(int i=0;i<PositionsTotal();i++)
  { ulong t=PositionGetTicket(i);
    if(PositionSelectByTicket(t)&&PositionGetInteger(POSITION_MAGIC)==InpMagic) c++; }
  return c; }

void CloseAllMagic()
{ for(int i=PositionsTotal()-1;i>=0;i--)
  { ulong t=PositionGetTicket(i);
    if(PositionSelectByTicket(t)&&PositionGetInteger(POSITION_MAGIC)==InpMagic)
    { trade.PositionClose(t); RemoveTradeTracker(t); RemoveMFETracker(t); } } }

double NormLot(double lot)
{ double mn=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
  double mx=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
  double st=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
  if(st<=0) return mn;
  lot=MathFloor(lot/st)*st;
  return MathMax(mn,MathMin(mx,lot)); }

//====================================================================
//  PANEL
//====================================================================
void DrawPanel()
{
   if(!InpShowPanel) return;
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   int pos=0; double pnlO=0,vol=0;
   for(int i=0;i<PositionsTotal();i++)
   { ulong t=PositionGetTicket(i); if(!PositionSelectByTicket(t)) continue;
     if(PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
     pos++; pnlO+=PositionGetDouble(POSITION_PROFIT); vol+=PositionGetDouble(POSITION_VOLUME); }

   double eq     =AccountInfoDouble(ACCOUNT_EQUITY);
   double bal    =AccountInfoDouble(ACCOUNT_BALANCE);
   double dayPnL =eq-g_dayStartBal;
   int    total  =g_winsToday+g_lossesToday;
   double wr     =total>0?100.0*g_winsToday/total:0;
   double pf     =g_totalLost>0?g_totalWon/g_totalLost:0;
   double dayPct =g_dayStartBal>0?dayPnL/g_dayStartBal*100.0:0;

   string est=g_dayInvalid?"❌PAUSADO":(pos>0?"✅OPERANDO":"🎯VIGILANDO");
   string ali="";
   ali+=g_sesgoUp?"D1↑":(g_sesgoDn?"D1↓":"D1=");
   ali+=g_h1Up  ?" H1↑" :(g_h1Dn  ?" H1↓" :" H1=");
   ali+=g_m20Up ?" M20↑":(g_m20Dn ?" M20↓":" M20=");
   ali+=g_m15Up ?" M15↑":(g_m15Dn ?" M15↓":" M15=");
   ali+=g_m6Up  ?" M6↑" :(g_m6Dn  ?" M6↓" :" M6=");
   ali+=g_m5Up  ?" M5↑" :(g_m5Dn  ?" M5↓" :" M5=");

   string txt="";
   txt+="╔════ QQ ULTIMATE v9.0 – PRO EDITION ════╗\n";
   txt+=StringFormat("║ %02d:%02d | %s | %s\n",dt.hour,dt.min,est,RegimeStr());
   txt+=StringFormat("║ %s\n",CapModeStr());
   txt+=StringFormat("║ Balance: $%.2f | Equity: $%.2f\n",bal,eq);
   txt+=StringFormat("║ PnL Día: $%.2f (%.2f%%) | Límite: $%.2f\n",dayPnL,dayPct,g_dailyProfitUSD);
   txt+=StringFormat("║ ATR M5: %.4f | ATR H1: %.4f | ADX: %.1f\n",
         g_atr_cached,g_atr_h1_cached,g_adxVal);
   txt+="╠════ ALINEACIÓN 6-TF ════╣\n";
   txt+=StringFormat("║ %s\n",ali);
   txt+=StringFormat("║ RSI M5:%.1f H1:%.1f D1:%.1f\n",g_rsiM5_cached,g_rsiH1_cached,g_rsiD1_cached);
   txt+="╠════ ENTRADA ULTRA-PRECISA ════╣\n";
   txt+=StringFormat("║ Último Score: %d / 100 (mín: %d)\n",g_lastEntryScore,InpMinEntryScore);
   txt+=StringFormat("║ Patrón: %s | Vol.Confirm: %s\n",
         PatternStr(g_lastPattern),InpRequireVolume?"ON":"OFF");
   txt+=StringFormat("║ TF mín: %d/6 | Candle-close: %s\n",
         InpMinTFAlignment,InpRequireCandleClose?"ON":"OFF");
   txt+="╠════ MULTI-TRADE ════╣\n";
   txt+=StringFormat("║ Trades/set: %d | Equity: $%.2f\n",g_multiTradeCount,eq);
   txt+=StringFormat("║ <$25=1T | $25=2T | $50=3T | $130=4T | $250=5T\n");
   txt+=StringFormat("║ TP1:%.1fx TP2:%.1fx TP3:%.1fx TP4:%.1fx TP5:%.1fx\n",
         InpATR_TP1,InpATR_TP2,InpATR_TP3,InpATR_TP4,InpATR_TP5);
   txt+="╠════ RECOVERY ANTI-DEADLOCK ════╣\n";
   txt+=StringFormat("║ Estado: %s | Mult: %.2f\n",RecoveryStr(),g_recoveryMult_state);
   txt+=StringFormat("║ Pérd.Día: %d/%d | Global: %d | AutoReset@%d\n",
         g_dailyLosses,InpDailyLossLimit,g_consecLosses,InpGlobalLossReset);
   txt+=StringFormat("║ Timeout: %dh | Wins hoy: %d\n",InpRecoveryTimeoutH,g_dailyWins);
   txt+="╠════ KELLY & COMPOUND ════╣\n";
   txt+=StringFormat("║ Kelly Risk: %.2f%% | PF: %.2f | WR: %.1f%%\n",
         g_kellyRiskPct,g_kellyPF,g_kellyWinRate*100);
   txt+=StringFormat("║ AvgW: $%.2f | AvgL: $%.2f | Muestras: %d\n",
         g_kellyAvgWin,g_kellyAvgLoss,g_kellySamples);
   txt+=StringFormat("║ Compound: x%.2f | %s | Real: $%.2f (%.2f%%)\n",
         g_compoundBoost,g_compoundActive?"✅ACTIVO":"⬜OFF",
         g_realizedGainToday,g_compoundDayGainPct);
   txt+="╠════ TRADES ABIERTOS ════╣\n";
   txt+=StringFormat("║ Pos: %d | Vol: %.2f | PnL: $%.2f\n",pos,vol,pnlO);
   txt+=StringFormat("║ Hoy: %d/%d | MFE activos: %d | Sets: %d\n",
         g_tradesToday,g_maxTradesDay,g_mfeCount,g_tradeSetCount);
   txt+=StringFormat("║ BE: %s | P1: %s | P2: %s\n",
         g_beMoved?"✅":"⬜",g_partial1Done?"✅":"⬜",g_partial2Done?"✅":"⬜");
   txt+="╠════ ESTADÍSTICAS ════╣\n";
   txt+=StringFormat("║ W: %d | L: %d | WR: %.1f%% | PF: %.2f\n",
         g_winsToday,g_lossesToday,wr,pf);
   txt+=StringFormat("║ Total ganado: $%.2f | MaxDD: %.1f%%\n",g_totalWon,g_maxDrawdown);
   txt+=StringFormat("║ Global W:%d L:%d | Peak: $%.2f\n",
         g_totalWins,g_totalLosses,g_peakProfit);
   txt+="╚══════════════════════════════════════════╝";
   Comment(txt);
}
//+------------------------------------------------------------------+
//  FIN – QQ ULTIMATE v9.0 PRO EDITION
//+------------------------------------------------------------------+
