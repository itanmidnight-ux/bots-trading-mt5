//+------------------------------------------------------------------+
//|  EURUSD QQ ULTIMATE – DUAL STRATEGY EDITION v1.0                |
//|                                                                  |
//|  Motores de Entrada: S1 BB+RSI  |  S2 Stochastic+RSI            |
//|  Sistemas: Multi-Trade MTF | Pirámide | London ORB               |
//|  Gestión : 10 Capas de Protección | Peak Lock | Smart Exit       |
//|                                                                  |
//|  Diseño MTF para ejecución M5:                                   |
//|    • D1 / H1  → VETO DURO                                       |
//|    • H4       → Confirmador de contexto (peso 20%)              |
//|    • M5       → Momentum pre-ejecución  (peso 45%)              |
//|    • M1       → Confirmación de entrada (peso 35%)              |
//|                                                                  |
//|  Magic S1 = 10001 | Magic S2 = 10002 | Magic ORB = 20260100    |
//+------------------------------------------------------------------+
#property copyright "EURUSD QQ Ultimate – Dual Strategy Edition v1.0"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>

CTrade        trade;
CPositionInfo Pos;

//====================================================================
//  ENUMERACIONES
//====================================================================
enum ENUM_CAP_MODE
{
   CAP_MICRO    = 0,
   CAP_SMALL    = 1,
   CAP_MEDIUM   = 2,
   CAP_UPPER    = 3,
   CAP_STANDARD = 4
};

//====================================================================
//  INPUTS – GENERAL
//====================================================================
input group "=== GENERAL ==="
input string InpComment         = "DS_QQ";
input int    InpSlippage        = 10;

//====================================================================
//  INPUTS – GESTIÓN DE CAPITAL
//====================================================================
input group "=== GESTIÓN DE CAPITAL ==="
input bool   InpAutoCapital     = true;
input double InpRiskPercent     = 0.8;     // % riesgo base por trade individual
input int    InpMagicS1         = 10001;   // Magic Estrategia 1 (BB+RSI)
input int    InpMagicS2         = 10002;   // Magic Estrategia 2 (Stoch+RSI)
input double InpMaxLot          = 2.0;
input double InpMinLot          = 0.01;
input double InpMaxDailyLossPct = 3.0;

//====================================================================
//  INPUTS – ESTRATEGIAS ACTIVAS
//====================================================================
input group "=== ESTRATEGIAS ACTIVAS ==="
input bool   InpUseS1           = true;
input bool   InpUseS2           = true;
input int    InpMaxOpenS1       = 1;
input int    InpMaxOpenS2       = 1;

//====================================================================
//  INPUTS – SISTEMA MULTI-TRADES
//====================================================================
input group "=== SISTEMA MULTI-TRADES ==="
input bool   InpMultiTradeOn    = true;
input double InpMTF_ScoreThresh = 78.0;   // Score mínimo para activar (0-100)
input int    InpMTF_WindowSec   = 4;

//====================================================================
//  INPUTS – SL / TP (ATR-based)
//====================================================================
input group "=== SL / TP DINÁMICO ==="
input double InpSLMult          = 1.5;    // SL = N x ATR(14)
input double InpTPMult          = 1.0;    // TP = N x ATR(14)
input double InpATR_TP_MultQQ   = 2.0;    // TP ratio para pirámide / ORB

//====================================================================
//  INPUTS – ESTRATEGIA 1: BB + RSI
//====================================================================
input group "=== ESTRATEGIA 1: BB + RSI ==="
input int    InpBBPeriod        = 20;
input double InpBBDev           = 2.0;
input int    InpRSIPeriodS1     = 14;
input double InpRSIOversoldS1   = 35.0;
input double InpRSIOverboughtS1 = 65.0;

//====================================================================
//  INPUTS – ESTRATEGIA 2: STOCH + RSI
//====================================================================
input group "=== ESTRATEGIA 2: STOCH + RSI ==="
input int    InpStochK          = 14;
input int    InpStochD          = 3;
input int    InpStochSlow       = 3;
input double InpStochOversold   = 25.0;
input double InpStochOverbought = 75.0;
input int    InpRSIPeriodS2     = 14;
input double InpRSIFilter       = 50.0;

//====================================================================
//  INPUTS – FILTROS
//====================================================================
input group "=== FILTROS ==="
input bool   InpUseADX          = true;
input int    InpADXPeriod       = 14;
input double InpADXMax          = 30.0;
input bool   InpUseTimeFilter   = true;
input int    InpStartHour       = 7;
input int    InpEndHour         = 21;
input bool   InpNoFridayTrades  = true;
input int    InpFridayHour      = 20;

//====================================================================
//  INPUTS – CIERRES INTELIGENTES
//====================================================================
input group "=== CIERRES AUTOMÁTICOS ==="
input bool   InpUseBreakEven    = true;
input double InpBEMult          = 0.6;
input bool   InpUseTrailing     = true;
input double InpTrailActiveMult = 0.8;
input double InpTrailStepMult   = 0.3;
input bool   InpUsePartialClose = true;
input double InpPartialPct      = 50.0;
input bool   InpUseTrendExit    = true;
input bool   InpUseTimeExit     = true;
input int    InpMaxBarsOpen     = 48;     // 48 x M5 = 4h
input bool   InpSmartExitOn     = true;
input bool   InpMomentumExitOn  = true;
input double InpMinProfitLock   = 0.30;

//====================================================================
//  INPUTS – SISTEMA PIRAMIDAL
//====================================================================
input group "=== SISTEMA PIRAMIDAL ==="
input bool   InpPyramidOn       = true;
input int    InpPyramidLevels   = 2;

//====================================================================
//  INPUTS – LONDON ORB
//====================================================================
input group "=== ESTRATEGIA LONDON ORB ==="
input bool   InpLondonORBOn     = true;
input int    InpMagicORB        = 20260100;
input int    InpORBRangeHStart  = 7;
input int    InpORBTradeHStart  = 8;
input int    InpORBTradeHEnd    = 9;
input int    InpORBMaxMinutes   = 120;
input double InpORBRangeMinPts  = 0.0005;  // ~5 pips EURUSD
input double InpORBRangeMaxPts  = 0.0040;  // ~40 pips EURUSD
input int    InpORBMinBars      = 25;
input double InpORBBreakBuf     = 0.0001;  // 1 pip buffer
input double InpORBSLBuffer     = 0.0001;
input double InpORBRRatio       = 2.0;
input int    InpORBEmaFast      = 50;
input int    InpORBEmaSlow      = 200;
input int    InpORBMaxSpread    = 20;      // spreads típicos EURUSD

//====================================================================
//  INPUTS – PROTECCIONES
//====================================================================
input group "=== PROTECCIONES ==="
input double InpMaxSpread       = 20.0;   // spread máx en puntos (EURUSD)

//====================================================================
//  INPUTS – INDICADORES AUXILIARES
//====================================================================
input group "=== INDICADORES AUXILIARES ==="
input int    InpATRPeriod       = 14;
input int    InpMFIPeriod       = 14;

//====================================================================
//  INPUTS – MONITOREO
//====================================================================
input group "=== MONITOREO ==="
input bool   InpShowPanel       = true;
input bool   InpShowDash        = true;
input int    InpDashX           = 12;
input int    InpDashY           = 28;

//====================================================================
//  HANDLES – ESTRATEGIAS DUALES
//====================================================================
int hBB, hRSI1, hStoch, hRSI2, hATR_M5, hADX;

//====================================================================
//  HANDLES – MTF
//====================================================================
int hEMA50_D1, hEMA200_D1;
int hRSI_H1;
int hEMA21_H1, hEMA50_H1;
int hRSI_H4, hATR_H4, hEMA50_H4;
int hEMA9_M5, hEMA21_M5mt;
int hEMA9_M1, hEMA21_M1, hRSI_M1mt, hATR_M1mt;

//====================================================================
//  HANDLES – LONDON ORB
//====================================================================
int hORB_EmaFast, hORB_EmaSlow;

//====================================================================
//  VARIABLES DE CAPITAL
//====================================================================
ENUM_CAP_MODE g_capMode        = CAP_MICRO;
double        g_riskPct        = 0.8;
double        g_dailyLossUSD   = 0;
double        g_dailyProfitUSD = 0;
double        g_minProfitLock  = 0;
double        g_profitRetrace  = 0;
double        g_pyramidTrig1   = 0;
double        g_pyramidTrig2   = 0;
double        g_pyramidLotMult = 0;
double        g_trailingMult   = 0;
int           g_maxTradesDay   = 0;
int           g_maxBarsOpen    = 0;
int           g_maxNegBars     = 0;
double        g_partialAt1R    = 0;
double        g_partialAt2R    = 0;
int           g_maxMultiTrades = 1;

//====================================================================
//  ESTADO DUAL STRATEGY
//====================================================================
double   g_DayStartBalance;
datetime g_LastDay;

int    g_TradesS1, g_WinsS1, g_LossS1;
int    g_TradesS2, g_WinsS2, g_LossS2;
double g_GrossWinS1, g_GrossLossS1;
double g_GrossWinS2, g_GrossLossS2;
double g_NetS1, g_NetS2;

ulong  g_PartialDone[];
int    g_PartialCount;

string g_Pfx = "DSQQ_";

//====================================================================
//  ESTADO QQ GLOBAL
//====================================================================
bool     g_dayInvalid    = false;
bool     g_sesgoUp       = false, g_sesgoDn  = false;
bool     g_h1Up          = false, g_h1Dn     = false;
int      g_tradesToday   = 0;
double   g_dayStartBal   = 0;
datetime g_lastDay       = 0;
int      g_pyramidLevel  = 0;
double   g_entry1Lot     = 0, g_entry1Price  = 0;
bool     g_partial1Done  = false, g_partial2Done = false, g_beMoved = false;
double   g_peakProfit    = 0;
double   g_atr_cached    = 0;

struct TradeInfo { ulong ticket; datetime openTime; };
TradeInfo g_openTrades[100];
int       g_openTradeCount = 0;

int    g_winsToday  = 0, g_lossesToday = 0;
double g_totalWon   = 0, g_totalLost   = 0;

//====================================================================
//  ESTADO SISTEMA MULTI-TRADES
//====================================================================
struct MultiTradeGroup
{
   ulong    tickets[5];
   int      count;
   bool     isBuy;
   double   sharedSL;
   double   sharedTP;
   double   baseLot;
   datetime openTime;
   double   mtfScore;
};

MultiTradeGroup g_mtGroup;
bool            g_mtGroupActive = false;

int    g_mtWinsTotal = 0, g_mtLossTotal = 0;
double g_mtWonTotal  = 0, g_mtLostTotal = 0;

//====================================================================
//  ESTADO LONDON ORB
//====================================================================
double   g_orbRangeHigh      = 0;
double   g_orbRangeLow       = DBL_MAX;
int      g_orbRangeBars      = 0;
bool     g_orbRangeBuilt     = false;
bool     g_orbTradeTriggered = false;
datetime g_orbLastResetDate  = 0;
datetime g_orbTradeOpenTime  = 0;
int      g_orbWinsToday      = 0, g_orbLossesToday = 0;
double   g_orbWonToday       = 0, g_orbLostToday   = 0;

//====================================================================
//  OnInit
//====================================================================
int OnInit()
{
   if(!InpUseS1 && !InpUseS2)
   { Alert("Activa al menos una estrategia."); return INIT_PARAMETERS_INCORRECT; }

   // Modo de relleno de orden
   ENUM_ORDER_TYPE_FILLING fill = ORDER_FILLING_RETURN;
   uint fm = (uint)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((fm & SYMBOL_FILLING_IOC) != 0)      fill = ORDER_FILLING_IOC;
   else if((fm & SYMBOL_FILLING_FOK) != 0) fill = ORDER_FILLING_FOK;

   trade.SetDeviationInPoints(InpSlippage);
   trade.SetTypeFilling(fill);

   //---- Indicadores Dual Strategy ----
   hBB    = iBands(_Symbol, PERIOD_M5, InpBBPeriod, 0, InpBBDev, PRICE_CLOSE);
   hRSI1  = iRSI(_Symbol, PERIOD_M5, InpRSIPeriodS1, PRICE_CLOSE);
   hStoch = iStochastic(_Symbol, PERIOD_M5, InpStochK, InpStochD, InpStochSlow, MODE_SMA, STO_LOWHIGH);
   hRSI2  = iRSI(_Symbol, PERIOD_M5, InpRSIPeriodS2, PRICE_CLOSE);
   hATR_M5= iATR(_Symbol, PERIOD_M5, InpATRPeriod);
   hADX   = iADX(_Symbol, PERIOD_M5, InpADXPeriod);

   //---- MTF ----
   hEMA50_D1  = iMA(_Symbol, PERIOD_D1, 50,  0, MODE_EMA, PRICE_CLOSE);
   hEMA200_D1 = iMA(_Symbol, PERIOD_D1, 200, 0, MODE_EMA, PRICE_CLOSE);
   hRSI_H1    = iRSI(_Symbol, PERIOD_H1, InpATRPeriod, PRICE_CLOSE);
   hEMA21_H1  = iMA(_Symbol, PERIOD_H1, 21, 0, MODE_EMA, PRICE_CLOSE);
   hEMA50_H1  = iMA(_Symbol, PERIOD_H1, 50, 0, MODE_EMA, PRICE_CLOSE);
   hRSI_H4    = iRSI(_Symbol, PERIOD_H4, InpATRPeriod, PRICE_CLOSE);
   hATR_H4    = iATR(_Symbol, PERIOD_H4, InpATRPeriod);
   hEMA50_H4  = iMA(_Symbol,  PERIOD_H4, 50, 0, MODE_EMA, PRICE_CLOSE);
   hEMA9_M5   = iMA(_Symbol,  PERIOD_M5, 9,  0, MODE_EMA, PRICE_CLOSE);
   hEMA21_M5mt= iMA(_Symbol,  PERIOD_M5, 21, 0, MODE_EMA, PRICE_CLOSE);
   hEMA9_M1   = iMA(_Symbol,  PERIOD_M1, 9,  0, MODE_EMA, PRICE_CLOSE);
   hEMA21_M1  = iMA(_Symbol,  PERIOD_M1, 21, 0, MODE_EMA, PRICE_CLOSE);
   hRSI_M1mt  = iRSI(_Symbol, PERIOD_M1, InpATRPeriod, PRICE_CLOSE);
   hATR_M1mt  = iATR(_Symbol, PERIOD_M1, InpATRPeriod);

   //---- ORB ----
   hORB_EmaFast = iMA(_Symbol, PERIOD_M1, InpORBEmaFast, 0, MODE_EMA, PRICE_CLOSE);
   hORB_EmaSlow = iMA(_Symbol, PERIOD_M1, InpORBEmaSlow, 0, MODE_EMA, PRICE_CLOSE);

   // Verificar handles críticos
   int h[] = {
      hBB, hRSI1, hStoch, hRSI2, hATR_M5, hADX,
      hEMA50_D1, hEMA200_D1, hRSI_H1, hEMA21_H1, hEMA50_H1,
      hRSI_H4, hATR_H4, hEMA50_H4,
      hEMA9_M5, hEMA21_M5mt,
      hEMA9_M1, hEMA21_M1, hRSI_M1mt, hATR_M1mt,
      hORB_EmaFast, hORB_EmaSlow
   };
   for(int i = 0; i < ArraySize(h); i++)
      if(h[i] == INVALID_HANDLE)
      { Alert("❌ Handle inválido #", i); return INIT_FAILED; }

   // Estado inicial
   g_DayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_LastDay         = TimeCurrent();
   g_PartialCount    = 0;
   ArrayResize(g_PartialDone, 0);
   g_TradesS1=g_WinsS1=g_LossS1=0;
   g_TradesS2=g_WinsS2=g_LossS2=0;
   g_GrossWinS1=g_GrossLossS1=g_GrossWinS2=g_GrossLossS2=0;
   g_NetS1=g_NetS2=0;

   g_dayStartBal = AccountInfoDouble(ACCOUNT_BALANCE);
   DetectCapitalMode();
   DailyReset();

   if(InpShowDash) CreateDash();

   Print("✅ EURUSD QQ Ultimate DS v1.0 | Balance: $", DoubleToString(g_dayStartBal, 2),
         " | Modo: ", CapModeStr(), " | Max trades/señal: ", g_maxMultiTrades);
   return INIT_SUCCEEDED;
}

//====================================================================
//  OnDeinit
//====================================================================
void OnDeinit(const int reason)
{
   Comment("");
   int h[] = {
      hBB, hRSI1, hStoch, hRSI2, hATR_M5, hADX,
      hEMA50_D1, hEMA200_D1, hRSI_H1, hEMA21_H1, hEMA50_H1,
      hRSI_H4, hATR_H4, hEMA50_H4,
      hEMA9_M5, hEMA21_M5mt,
      hEMA9_M1, hEMA21_M1, hRSI_M1mt, hATR_M1mt,
      hORB_EmaFast, hORB_EmaSlow
   };
   for(int i = 0; i < ArraySize(h); i++)
      if(h[i] != INVALID_HANDLE) IndicatorRelease(h[i]);
   DeleteDash();
   ORBDeleteDrawings();
}

//====================================================================
//  DETECCIÓN DE CAPITAL EN TIEMPO REAL
//====================================================================
void DetectCapitalMode()
{
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);

   if(bal < 25.0)
   {
      g_capMode=CAP_MICRO;    g_maxMultiTrades=1;
      g_riskPct=1.0;
      g_dailyLossUSD=bal*0.06;   g_dailyProfitUSD=bal*0.15;
      g_minProfitLock=bal*0.020; g_profitRetrace=bal*0.008;
      g_pyramidTrig1=0.0010;     g_pyramidTrig2=0.0020;
      g_pyramidLotMult=0.50;     g_trailingMult=0.70;
      g_maxTradesDay=3;          g_maxBarsOpen=60; g_maxNegBars=10;
      g_partialAt1R=0.40;        g_partialAt2R=0.40;
   }
   else if(bal < 60.0)
   {
      g_capMode=CAP_SMALL;    g_maxMultiTrades=2;
      g_riskPct=0.9;
      g_dailyLossUSD=bal*0.05;   g_dailyProfitUSD=bal*0.12;
      g_minProfitLock=bal*0.015; g_profitRetrace=bal*0.006;
      g_pyramidTrig1=0.0008;     g_pyramidTrig2=0.0015;
      g_pyramidLotMult=0.60;     g_trailingMult=0.80;
      g_maxTradesDay=4;          g_maxBarsOpen=80; g_maxNegBars=15;
      g_partialAt1R=0.35;        g_partialAt2R=0.40;
   }
   else if(bal < 120.0)
   {
      g_capMode=CAP_MEDIUM;   g_maxMultiTrades=3;
      g_riskPct=0.80;
      g_dailyLossUSD=bal*0.045;  g_dailyProfitUSD=bal*0.11;
      g_minProfitLock=bal*0.014; g_profitRetrace=bal*0.006;
      g_pyramidTrig1=0.0008;     g_pyramidTrig2=0.0015;
      g_pyramidLotMult=0.65;     g_trailingMult=0.90;
      g_maxTradesDay=5;          g_maxBarsOpen=100; g_maxNegBars=18;
      g_partialAt1R=0.30;        g_partialAt2R=0.40;
   }
   else if(bal < 240.0)
   {
      g_capMode=CAP_UPPER;    g_maxMultiTrades=4;
      g_riskPct=0.75;
      g_dailyLossUSD=bal*0.040;  g_dailyProfitUSD=bal*0.10;
      g_minProfitLock=bal*0.012; g_profitRetrace=bal*0.005;
      g_pyramidTrig1=0.0006;     g_pyramidTrig2=0.0012;
      g_pyramidLotMult=0.65;     g_trailingMult=0.95;
      g_maxTradesDay=5;          g_maxBarsOpen=110; g_maxNegBars=20;
      g_partialAt1R=0.30;        g_partialAt2R=0.40;
   }
   else
   {
      g_capMode=CAP_STANDARD; g_maxMultiTrades=5;
      g_riskPct=0.70;
      g_dailyLossUSD=bal*0.030;  g_dailyProfitUSD=bal*0.08;
      g_minProfitLock=bal*0.010; g_profitRetrace=bal*0.004;
      g_pyramidTrig1=0.0005;     g_pyramidTrig2=0.0010;
      g_pyramidLotMult=0.70;     g_trailingMult=1.00;
      g_maxTradesDay=6;          g_maxBarsOpen=120; g_maxNegBars=20;
      g_partialAt1R=0.30;        g_partialAt2R=0.40;
   }

   double manualCap = AccountInfoDouble(ACCOUNT_BALANCE) * InpMaxDailyLossPct / 100.0;
   if(manualCap < g_dailyLossUSD) g_dailyLossUSD = manualCap;
}

string CapModeStr()
{
   if(g_capMode==CAP_MICRO)    return "MICRO(<$25)";
   if(g_capMode==CAP_SMALL)    return "SMALL($25-59)";
   if(g_capMode==CAP_MEDIUM)   return "MEDIUM($60-119)";
   if(g_capMode==CAP_UPPER)    return "UPPER($120-239)";
   return "STANDARD($240+)";
}

//====================================================================
//  RESET DIARIO
//====================================================================
void DailyReset()
{
   g_dayInvalid=false;
   g_sesgoUp=false; g_sesgoDn=false;
   g_h1Up=false;    g_h1Dn=false;
   g_tradesToday=0; g_peakProfit=0;
   g_pyramidLevel=0; g_entry1Lot=0; g_entry1Price=0;
   g_partial1Done=false; g_partial2Done=false; g_beMoved=false;
   g_openTradeCount=0;
   g_winsToday=0; g_lossesToday=0;
   g_totalWon=0;  g_totalLost=0;
   g_mtGroupActive=false;
   ORBDailyReset();
   DetectCapitalMode();
}

void CheckDayReset()
{
   datetime day = iTime(_Symbol, PERIOD_D1, 0);
   if(day != g_lastDay)
   {
      g_dayStartBal = AccountInfoDouble(ACCOUNT_BALANCE);
      g_lastDay     = day;
      // También resetear contadores DS
      g_DayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      g_LastDay         = TimeCurrent();
      DailyReset();
   }
}

//====================================================================
//  SESGO D1/H1
//====================================================================
void UpdateMarketBias()
{
   double e50[1], e200[1];
   if(CopyBuffer(hEMA50_D1, 0,0,1,e50)  > 0 &&
      CopyBuffer(hEMA200_D1,0,0,1,e200) > 0)
   { g_sesgoUp=(e50[0]>e200[0]); g_sesgoDn=(e50[0]<e200[0]); }

   double rH1[1];
   if(CopyBuffer(hRSI_H1,0,0,1,rH1) > 0)
   { g_h1Up=(rH1[0]>53.0); g_h1Dn=(rH1[0]<47.0); }
}

//====================================================================
//  OnTick – ORQUESTADOR PRINCIPAL
//====================================================================
void OnTick()
{
   DetectCapitalMode();
   CheckDayReset();
   UpdateMarketBias();

   if(!IsNewBar()) return;

   UpdateDayBalance();

   if(DailyLimitHit())
   {
      CloseAll("DAILY_LIMIT");
      CloseAllORB("DAILY_LIMIT");
      g_dayInvalid = true;
      if(InpShowDash) UpdateDash();
      if(InpShowPanel) DrawPanel();
      return;
   }

   if(InpNoFridayTrades && IsFridayClose())
   {
      CloseAll("FRIDAY");
      CloseAllORB("FRIDAY");
      if(InpShowDash) UpdateDash();
      if(InpShowPanel) DrawPanel();
      return;
   }

   // Leer ATR y ADX
   double atr[1], adxVal[1];
   if(CopyBuffer(hATR_M5, 0, 1, 1, atr)    < 1) return;
   if(CopyBuffer(hADX,    0, 1, 1, adxVal) < 1) return;
   if(atr[0] > 0) g_atr_cached = atr[0];

   // Gestión de posiciones (10 capas)
   ManageOpenTrades();

   // Filtros globales de entrada
   bool timeOK  = (!InpUseTimeFilter || ValidHour());
   bool adxOK   = (!InpUseADX        || adxVal[0] <= InpADXMax);
   bool dayOK   = !g_dayInvalid && !DailyLimitHit();
   bool tradesOK= (g_tradesToday < g_maxTradesDay);

   if(dayOK && timeOK && adxOK && tradesOK)
   {
      if(InpUseS1) RunS1(atr[0]);
      if(InpUseS2) RunS2(atr[0]);
   }

   // Gestión pirámide sobre posiciones existentes
   if(InpPyramidOn && dayOK) ManagePyramid(atr[0]);

   // London ORB
   if(InpLondonORBOn)
   {
      RunLondonORB();
      ManageORBTrades();
   }

   TrackClosedTrades();

   if(InpShowDash) UpdateDash();
   if(InpShowPanel) DrawPanel();
}

//====================================================================
//  ESTRATEGIA 1: BB + RSI
//====================================================================
void RunS1(double atr)
{
   if(CountPos((ulong)InpMagicS1) >= InpMaxOpenS1) return;

   double bbU[1], bbL[1], bbM[1], rsi[1];
   if(CopyBuffer(hBB,   0, 1, 1, bbM) < 1) return;
   if(CopyBuffer(hBB,   1, 1, 1, bbU) < 1) return;
   if(CopyBuffer(hBB,   2, 1, 1, bbL) < 1) return;
   if(CopyBuffer(hRSI1, 0, 1, 1, rsi) < 1) return;

   double cl = iClose(_Symbol, PERIOD_M5, 1);
   if(cl <= 0) return;

   int    dg  = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl  = NormalizeDouble(InpSLMult * atr, dg);
   double tp  = NormalizeDouble(InpTPMult * atr, dg);
   double lot = CalcLotDS(sl);
   if(lot <= 0) return;

   trade.SetExpertMagicNumber((ulong)InpMagicS1);

   if(cl < bbL[0] && rsi[0] < InpRSIOversoldS1)
   {
      double slP = NormalizeDouble(ask - sl, dg);
      double tpP = NormalizeDouble(ask + tp, dg);
      if(trade.Buy(lot, _Symbol, ask, slP, tpP, InpComment + "_S1B"))
      {
         ulong t = trade.ResultOrder();
         g_tradesToday++; RegisterTrade(t);
         Print("[S1 BUY] lot=", lot, " entry=", ask);
         TryActivateMultiTrade(true, t, ask, slP, tpP, atr);
      }
   }
   else if(cl > bbU[0] && rsi[0] > InpRSIOverboughtS1)
   {
      double slP = NormalizeDouble(bid + sl, dg);
      double tpP = NormalizeDouble(bid - tp, dg);
      if(trade.Sell(lot, _Symbol, bid, slP, tpP, InpComment + "_S1S"))
      {
         ulong t = trade.ResultOrder();
         g_tradesToday++; RegisterTrade(t);
         Print("[S1 SELL] lot=", lot, " entry=", bid);
         TryActivateMultiTrade(false, t, bid, slP, tpP, atr);
      }
   }
}

//====================================================================
//  ESTRATEGIA 2: STOCH + RSI
//====================================================================
void RunS2(double atr)
{
   if(CountPos((ulong)InpMagicS2) >= InpMaxOpenS2) return;

   double sk[2], sd[2], rsi[1];
   if(CopyBuffer(hStoch, MAIN_LINE,   1, 2, sk)  < 2) return;
   if(CopyBuffer(hStoch, SIGNAL_LINE, 1, 2, sd)  < 2) return;
   if(CopyBuffer(hRSI2,  0,           1, 1, rsi) < 1) return;

   int    dg  = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl  = NormalizeDouble(InpSLMult * atr, dg);
   double tp  = NormalizeDouble(InpTPMult * atr, dg);
   double lot = CalcLotDS(sl);
   if(lot <= 0) return;

   // [0]=más antigua [1]=más reciente (última cerrada)
   bool crossUp = (sk[1] > sd[1]) && (sk[0] <= sd[0]);
   bool crossDn = (sk[1] < sd[1]) && (sk[0] >= sd[0]);

   trade.SetExpertMagicNumber((ulong)InpMagicS2);

   if(sk[1] < InpStochOversold && crossUp && rsi[0] < InpRSIFilter)
   {
      double slP = NormalizeDouble(ask - sl, dg);
      double tpP = NormalizeDouble(ask + tp, dg);
      if(trade.Buy(lot, _Symbol, ask, slP, tpP, InpComment + "_S2B"))
      {
         ulong t = trade.ResultOrder();
         g_tradesToday++; RegisterTrade(t);
         Print("[S2 BUY] lot=", lot, " sk=", sk[1], " rsi=", rsi[0]);
         TryActivateMultiTrade(true, t, ask, slP, tpP, atr);
      }
   }
   else if(sk[1] > InpStochOverbought && crossDn && rsi[0] > InpRSIFilter)
   {
      double slP = NormalizeDouble(bid + sl, dg);
      double tpP = NormalizeDouble(bid - tp, dg);
      if(trade.Sell(lot, _Symbol, bid, slP, tpP, InpComment + "_S2S"))
      {
         ulong t = trade.ResultOrder();
         g_tradesToday++; RegisterTrade(t);
         Print("[S2 SELL] lot=", lot, " sk=", sk[1], " rsi=", rsi[0]);
         TryActivateMultiTrade(false, t, bid, slP, tpP, atr);
      }
   }
}

//====================================================================
//  CÁLCULO DE LOTE – DUAL STRATEGY
//====================================================================
double CalcLotDS(double slDist)
{
   if(slDist <= 0) return 0;
   double bal  = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk = bal * g_riskPct / 100.0;
   double tv   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double ts   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(tv <= 0 || ts <= 0) return 0;
   double lot = risk / ((slDist / ts) * tv);
   if(g_capMode == CAP_MICRO) lot = MathMin(lot, minL * 2.0);
   lot = MathFloor(lot / step) * step;
   lot = MathMax(InpMinLot, MathMin(InpMaxLot, lot));
   lot = MathMax(minL,      MathMin(maxL, lot));
   return NormalizeDouble(lot, 2);
}

//====================================================================
//  CÁLCULO DE LOTE – SISTEMA QQ (con multiplicador de riesgo)
//====================================================================
double CalcLot(double slPts, double riskMult)
{
   double riskPct = g_riskPct * riskMult;
   double bal     = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk    = bal * (riskPct / 100.0);
   double tv      = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double ts      = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(slPts<=0||tv<=0||ts<=0) return NormLot(InpMinLot);
   double slMoney = slPts / ts * tv;
   double lot     = (slMoney > 0) ? risk / slMoney : InpMinLot;
   if(g_capMode == CAP_MICRO)
      lot = MathMin(lot, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN) * 2.0);
   return NormLot(lot);
}

//====================================================================
//  SEÑAL CONTRARIA (para cierre por tendencia opuesta)
//====================================================================
bool HasOppositeSignal(bool posIsBuy, ulong magic)
{
   if(magic == (ulong)InpMagicS1)
   {
      double bbU[1], bbL[1], bbM[1], rsi[1];
      if(CopyBuffer(hBB,   0, 1, 1, bbM) < 1) return false;
      if(CopyBuffer(hBB,   1, 1, 1, bbU) < 1) return false;
      if(CopyBuffer(hBB,   2, 1, 1, bbL) < 1) return false;
      if(CopyBuffer(hRSI1, 0, 1, 1, rsi) < 1) return false;
      double cl = iClose(_Symbol, PERIOD_M5, 1);
      if(posIsBuy) return (cl > bbU[0] && rsi[0] > InpRSIOverboughtS1);
      else         return (cl < bbL[0] && rsi[0] < InpRSIOversoldS1);
   }
   if(magic == (ulong)InpMagicS2)
   {
      double sk[2], sd[2], rsi[1];
      if(CopyBuffer(hStoch, MAIN_LINE,   1, 2, sk)  < 2) return false;
      if(CopyBuffer(hStoch, SIGNAL_LINE, 1, 2, sd)  < 2) return false;
      if(CopyBuffer(hRSI2,  0,           1, 1, rsi) < 1) return false;
      bool crossUp = (sk[1] > sd[1]) && (sk[0] <= sd[0]);
      bool crossDn = (sk[1] < sd[1]) && (sk[0] >= sd[0]);
      if(posIsBuy) return (sk[1] > InpStochOverbought && crossDn && rsi[0] > InpRSIFilter);
      else         return (sk[1] < InpStochOversold   && crossUp && rsi[0] < InpRSIFilter);
   }
   return false;
}

//====================================================================
//  SISTEMA MULTI-TRADES MTF
//====================================================================
struct MTFResult
{
   bool   passed;
   double score;
   string detail;
};

MTFResult EvaluateMTF(bool isBuy)
{
   MTFResult res;
   res.passed=false; res.score=0; res.detail="";

   // Veto D1
   double e50d1[1], e200d1[1];
   if(CopyBuffer(hEMA50_D1, 0,0,1,e50d1)  <=0) return res;
   if(CopyBuffer(hEMA200_D1,0,0,1,e200d1) <=0) return res;
   if(isBuy ? (e50d1[0]<=e200d1[0]) : (e50d1[0]>=e200d1[0]))
   { res.detail="VETO D1"; return res; }

   // Veto H1
   double e21h1[1], e50h1[1], rsiH1v[1];
   if(CopyBuffer(hEMA21_H1, 0,0,1,e21h1)  <=0) return res;
   if(CopyBuffer(hEMA50_H1, 0,0,1,e50h1)  <=0) return res;
   if(CopyBuffer(hRSI_H1,   0,0,1,rsiH1v) <=0) return res;
   bool h1EmaAdv = isBuy?(e21h1[0]<e50h1[0]):(e21h1[0]>e50h1[0]);
   bool h1RsiAdv = isBuy?(rsiH1v[0]<45.0)   :(rsiH1v[0]>55.0);
   if(h1EmaAdv && h1RsiAdv) { res.detail="VETO H1"; return res; }

   double weightedSum = 0;

   // H4 (peso 20)
   {
      double s4=0, rsiH4[1], atrH4[3], e50h4[1];
      if(CopyBuffer(hRSI_H4,  0,0,1,rsiH4)>0)
      { bool ok=isBuy?(rsiH4[0]>50&&rsiH4[0]<76):(rsiH4[0]<50&&rsiH4[0]>24); if(ok) s4+=40; }
      if(CopyBuffer(hATR_H4,  0,0,3,atrH4)>0)
      { ArraySetAsSeries(atrH4,true); double avg=(atrH4[0]+atrH4[1]+atrH4[2])/3.0; if(atrH4[0]>=avg*0.80) s4+=30; }
      double cH4=iClose(_Symbol,PERIOD_H4,0);
      if(CopyBuffer(hEMA50_H4,0,0,1,e50h4)>0)
      { if(isBuy?(cH4>e50h4[0]):(cH4<e50h4[0])) s4+=30; }
      weightedSum+=20.0*(s4/100.0);
      res.detail+="H4:"+DoubleToString(s4,0)+" ";
   }

   // M5 (peso 45)
   {
      double s5=0, e9[3], e21[3], rM5[1], aM5[1];
      ArraySetAsSeries(e9,true); ArraySetAsSeries(e21,true);
      bool ok1=(CopyBuffer(hEMA9_M5,    0,0,3,e9) >0);
      bool ok2=(CopyBuffer(hEMA21_M5mt, 0,0,3,e21)>0);
      bool ok3=(CopyBuffer(hRSI1,       0,0,1,rM5)>0);
      bool ok4=(CopyBuffer(hATR_M5,     0,0,1,aM5)>0);
      if(ok1&&ok2)
      {
         bool cx=(isBuy?(e9[0]>e21[0]&&e9[1]<=e21[1]):(e9[0]<e21[0]&&e9[1]>=e21[1]));
         bool cp=(isBuy?(e9[1]>e21[1]&&e9[2]<=e21[2]):(e9[1]<e21[1]&&e9[2]>=e21[2]));
         bool al=(isBuy?(e9[0]>e21[0]):(e9[0]<e21[0]));
         if(cx||cp) s5+=35; else if(al) s5+=15;
         double sep=MathAbs(e9[0]-e21[0]);
         if(sep>=0.00015) s5+=20;
      }
      if(ok3){ bool ok=isBuy?(rM5[0]>52&&rM5[0]<74):(rM5[0]<48&&rM5[0]>26); if(ok) s5+=30; }
      if(ok4)
      {
         double a3[3]; ArraySetAsSeries(a3,true);
         if(CopyBuffer(hATR_M5,0,0,3,a3)>0)
         { double av=(a3[0]+a3[1]+a3[2])/3.0; if(a3[0]>=av*0.90) s5+=15; }
      }
      s5=MathMin(s5,100.0);
      weightedSum+=45.0*(s5/100.0);
      res.detail+="M5:"+DoubleToString(s5,0)+" ";
   }

   // M1 (peso 35)
   {
      double s1=0, e9[2], e21[2], rM1[1], aM1[2];
      ArraySetAsSeries(e9,true); ArraySetAsSeries(e21,true); ArraySetAsSeries(aM1,true);
      bool ok1=(CopyBuffer(hEMA9_M1,  0,0,2,e9) >0);
      bool ok2=(CopyBuffer(hEMA21_M1, 0,0,2,e21)>0);
      bool ok3=(CopyBuffer(hRSI_M1mt, 0,0,1,rM1)>0);
      bool ok4=(CopyBuffer(hATR_M1mt, 0,0,2,aM1)>0);
      if(ok1&&ok2)
      {
         if(isBuy?(e9[0]>e21[0]):(e9[0]<e21[0])) s1+=30;
         bool cx=isBuy?(e9[0]>e21[0]&&e9[1]<=e21[1]):(e9[0]<e21[0]&&e9[1]>=e21[1]);
         if(cx) s1+=25;
      }
      if(ok3){ bool ok=isBuy?(rM1[0]>52&&rM1[0]<76):(rM1[0]<48&&rM1[0]>24); if(ok) s1+=25; }
      if(ok4&&aM1[1]>0&&aM1[0]>=aM1[1]*0.95) s1+=20;
      s1=MathMin(s1,100.0);
      weightedSum+=35.0*(s1/100.0);
      res.detail+="M1:"+DoubleToString(s1,0);
   }

   res.score  = MathMin(weightedSum, 100.0);
   res.passed = (res.score >= InpMTF_ScoreThresh);
   return res;
}

void TryActivateMultiTrade(bool isBuy, ulong masterTicket,
                            double entry, double sl, double tp, double atr)
{
   if(!InpMultiTradeOn || g_maxMultiTrades<=1 || g_mtGroupActive) return;

   MTFResult mtf = EvaluateMTF(isBuy);
   if(!mtf.passed)
   { Print("🔍 MTF: ", DoubleToString(mtf.score,1), "% < umbral | ", mtf.detail); return; }

   ArrayInitialize(g_mtGroup.tickets, 0);
   g_mtGroup.tickets[0] = masterTicket;
   g_mtGroup.count      = 1;
   g_mtGroup.isBuy      = isBuy;
   g_mtGroup.sharedSL   = sl;
   g_mtGroup.sharedTP   = tp;
   g_mtGroup.baseLot    = CalcLot(MathAbs(entry - sl), 1.0);
   g_mtGroup.openTime   = TimeCurrent();
   g_mtGroup.mtfScore   = mtf.score;

   datetime signalTime = TimeCurrent();
   int opened = 0;

   for(int i = 1; i < g_maxMultiTrades; i++)
   {
      if((long)(TimeCurrent()-signalTime) > (long)InpMTF_WindowSec)
      { Print("⏰ Ventana MTF cerrada en trade #", i+1, " — grupo parcial: ", opened); break; }

      double lot = CalcLot(MathAbs(entry - sl), 1.0);
      if(lot <= 0) break;

      // Usar magic del maestro para los adicionales
      ulong masterMagic = (isBuy && masterTicket > 0) ? (ulong)InpMagicS1 : (ulong)InpMagicS1;
      // Detectar magic del maestro desde posiciones abiertas
      if(PositionSelectByTicket(masterTicket))
         masterMagic = (ulong)PositionGetInteger(POSITION_MAGIC);
      trade.SetExpertMagicNumber(masterMagic);

      bool ok = false;
      if(isBuy)  ok = trade.Buy(lot,  _Symbol, SymbolInfoDouble(_Symbol,SYMBOL_ASK), sl, tp);
      else       ok = trade.Sell(lot, _Symbol, SymbolInfoDouble(_Symbol,SYMBOL_BID), sl, tp);

      if(ok)
      {
         ulong t = trade.ResultOrder();
         g_mtGroup.tickets[i] = t;
         g_mtGroup.count++;
         g_tradesToday++;
         RegisterTrade(t);
         opened++;
         Print("📊 MT trade #", i+1, " | Lot=", lot);
      }
      else Print("⚠️ MT trade #", i+1, " error: ", trade.ResultRetcodeDescription());
   }

   if(opened > 0)
   {
      g_mtGroupActive = true;
      Print("✅ Grupo MT activo | Trades: ", g_mtGroup.count, " | Score: ", DoubleToString(mtf.score,1), "%");
   }
}

//====================================================================
//  PIRAMIDAL
//====================================================================
void ManagePyramid(double atr)
{
   if(!InpPyramidOn) return;
   if(g_pyramidLevel >= InpPyramidLevels || g_tradesToday >= g_maxTradesDay) return;
   if(g_capMode == CAP_MICRO) return;

   ulong mt=0; bool mIsBuy=false; double mSL=0, mP=0; ulong mMagic=0;
   for(int i=0;i<PositionsTotal();i++)
   {
      ulong t=PositionGetTicket(i);
      if(!PositionSelectByTicket(t)) continue;
      ulong mg=(ulong)PositionGetInteger(POSITION_MAGIC);
      if(mg!=(ulong)InpMagicS1 && mg!=(ulong)InpMagicS2) continue;
      mt=t; mIsBuy=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
      mSL=PositionGetDouble(POSITION_SL);
      mP=PositionGetDouble(POSITION_PRICE_OPEN);
      mMagic=mg;
      break;
   }
   if(!mt) return;

   double trig=(g_pyramidLevel==0)?g_pyramidTrig1:g_pyramidTrig2;
   double cur =mIsBuy?SymbolInfoDouble(_Symbol,SYMBOL_BID):SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double mov =mIsBuy?(cur-mP):(mP-cur);
   if(mov<trig) return;

   int dg=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   double pyrLot=NormLot(g_entry1Lot>0?g_entry1Lot*MathPow(g_pyramidLotMult,g_pyramidLevel+1):CalcLot(atr*InpSLMult,0.5));
   trade.SetExpertMagicNumber(mMagic);

   if(mIsBuy)
   {
      double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      double slP=mP;
      double tpP=NormalizeDouble(ask+atr*InpATR_TP_MultQQ,dg);
      if(trade.Buy(pyrLot,_Symbol,ask,slP,tpP))
      { g_pyramidLevel++; g_tradesToday++; RegisterTrade(trade.ResultOrder());
        Print("📈 PIRÁMIDE L",g_pyramidLevel," @",ask," Lot:",pyrLot); }
   }
   else
   {
      double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
      double slP=mP;
      double tpP=NormalizeDouble(bid-atr*InpATR_TP_MultQQ,dg);
      if(trade.Sell(pyrLot,_Symbol,bid,slP,tpP))
      { g_pyramidLevel++; g_tradesToday++; RegisterTrade(trade.ResultOrder());
        Print("📉 PIRÁMIDE L",g_pyramidLevel," @",bid," Lot:",pyrLot); }
   }
}

//====================================================================
//  GESTIÓN DE POSICIONES – 10 CAPAS
//====================================================================
void ManageOpenTrades()
{
   double dayPnL = AccountInfoDouble(ACCOUNT_BALANCE) - g_dayStartBal;

   // Capa 0: Stop/Target diario global
   if(dayPnL >= g_dailyProfitUSD)
   { CloseAll("Target diario"); CloseAllORB("Target diario"); g_dayInvalid=true;
     Print("🎯 TARGET DIARIO $", dayPnL); return; }
   if(dayPnL <= -g_dailyLossUSD)
   { CloseAll("Stop diario"); CloseAllORB("Stop diario"); g_dayInvalid=true;
     Print("🛑 STOP DIARIO $", dayPnL); return; }

   double rsiM5[1], e9[1], e21[1], atrM5[1];
   bool hR=(CopyBuffer(hRSI1,    0,0,1,rsiM5)>0);
   bool hE=(CopyBuffer(hEMA9_M5, 0,0,1,e9)   >0 && CopyBuffer(hEMA21_M5mt,0,0,1,e21)>0);
   bool hA=(CopyBuffer(hATR_M5,  0,0,1,atrM5)>0);
   if(hA && atrM5[0]>0) g_atr_cached=atrM5[0];

   double totalPnL=0; int count=0;

   int total = PositionsTotal();
   for(int i = total-1; i >= 0; i--)
   {
      if(!Pos.SelectByIndex(i)) continue;
      if(Pos.Symbol() != _Symbol) continue;
      ulong magic = Pos.Magic();
      if(magic!=(ulong)InpMagicS1 && magic!=(ulong)InpMagicS2) continue;

      ulong  ticket   = Pos.Ticket();
      bool   isBuy    = (Pos.PositionType()==POSITION_TYPE_BUY);
      double openP    = Pos.PriceOpen();
      double curSL    = Pos.StopLoss();
      double curTP    = Pos.TakeProfit();
      double vol      = Pos.Volume();
      datetime tOpen  = (datetime)Pos.Time();
      double curP     = isBuy?SymbolInfoDouble(_Symbol,SYMBOL_BID):SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      double profit   = Pos.Profit();
      double point    = SymbolInfoDouble(_Symbol,SYMBOL_POINT);
      int    dg       = (int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
      totalPnL+=profit; count++;

      trade.SetExpertMagicNumber(magic);

      // Capa 1: Cierre por tiempo máximo (con ganancia)
      if(InpUseTimeExit)
      {
         int barsOpen = Bars(_Symbol, PERIOD_M5, tOpen, TimeCurrent()) - 1;
         if(barsOpen >= InpMaxBarsOpen)
         { if(trade.PositionClose(ticket)) { RemoveTradeTracker(ticket); RemovePartialEntry(ticket);
             Print("⏱️ Cierre tiempo(", barsOpen, "b) S", magic==InpMagicS1?1:2, " $", profit); } continue; }
      }

      // Capa 2: Cierre por señal contraria
      if(InpUseTrendExit && HasOppositeSignal(isBuy, magic))
      { if(trade.PositionClose(ticket)) { RemoveTradeTracker(ticket); RemovePartialEntry(ticket);
          Print("[SIGNAL_EXIT] ticket=", ticket); } continue; }

      // Capa 3: Smart Exit – tendencia+RSI adversos en pérdida
      if(InpSmartExitOn && profit < 0 && hE && hR)
      {
         bool tW=(isBuy?(curP<e21[0]):(curP>e21[0]));
         bool mW=(isBuy?(rsiM5[0]<38):(rsiM5[0]>62));
         if(tW && mW)
         { if(trade.PositionClose(ticket)) { RemoveTradeTracker(ticket); RemovePartialEntry(ticket);
             Print("🧠 Smart Exit pérdida: $", profit); } continue; }
      }

      // Capa 4: Momentum Exit – pérdida de momentum en ganancia
      if(InpMomentumExitOn && profit > 0 && hE)
      {
         bool mL=isBuy?(e9[0]<e21[0]):(e9[0]>e21[0]);
         if(mL)
         { if(trade.PositionClose(ticket)) { RemoveTradeTracker(ticket); RemovePartialEntry(ticket);
             Print("⚡ Momentum perdido: $", profit); } continue; }
      }

      // Capa 5: Cierre parcial (al alcanzar mitad del TP)
      if(InpUsePartialClose && !IsPartialDone(ticket) && curTP > 0)
      {
         double halfTP = MathAbs(curTP - openP) / 2.0;
         double movProfit = isBuy?(curP-openP):(openP-curP);
         if(movProfit >= halfTP && halfTP > 0)
         {
            double volStep=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
            double minVol =SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
            double closeLot=MathFloor(vol*InpPartialPct/100.0/volStep)*volStep;
            if(closeLot>=minVol && closeLot<vol)
            { if(trade.PositionClosePartial(ticket, closeLot))
              { MarkPartialDone(ticket); Print("[PARTIAL] ticket=", ticket, " lot=", closeLot); } }
         }
      }

      // Capa 6: Break Even
      if(InpUseBreakEven)
      {
         double movE = isBuy?(curP-openP):(openP-curP);
         if(movE >= (InpBEMult * g_atr_cached))
         {
            double newSL; bool move;
            if(isBuy)  { newSL=NormalizeDouble(openP+point,dg); move=(newSL>curSL+point); }
            else       { newSL=NormalizeDouble(openP-point,dg); move=(curSL==0.0||newSL<curSL-point); }
            if(move) trade.PositionModify(ticket, newSL, curTP);
         }
      }

      // Capa 7: Trailing Stop
      if(InpUseTrailing) ApplyTrailingDS(ticket, isBuy, openP, curSL, curTP, curP);

      // Capa 8: Break-even anticipado a 0.5R con señal de reversión
      if(!g_beMoved && hE && hR && curSL>0)
      {
         double slD=MathAbs(openP-curSL);
         double mR=(slD>0)?MathAbs(curP-openP)/slD:0;
         bool rev=isBuy?(e9[0]<e21[0]&&rsiM5[0]<50):(e9[0]>e21[0]&&rsiM5[0]>50);
         if(mR>=0.5&&rev)
         {
            double nSL=isBuy?NormalizeDouble(openP+point,dg):NormalizeDouble(openP-point,dg);
            if((isBuy&&nSL>curSL)||(!isBuy&&(nSL<curSL||curSL==0)))
            { trade.PositionModify(ticket,nSL,curTP); g_beMoved=true;
              Print("🛡️ BE anticipado @0.5R"); }
         }
      }

      // Capa 9: RSI extremo en ganancia
      if(InpSmartExitOn && profit>0 && hR)
      {
         bool ext=isBuy?(rsiM5[0]>78):(rsiM5[0]<22);
         if(ext)
         { if(trade.PositionClose(ticket)) { RemoveTradeTracker(ticket); RemovePartialEntry(ticket);
             Print("🔥 RSI extremo: $", profit); } continue; }
      }
   }

   // Capa 10: Peak Profit Lock global
   if(count>0)
   {
      if(totalPnL>g_peakProfit) g_peakProfit=totalPnL;
      if(g_peakProfit>=g_minProfitLock && totalPnL<(g_peakProfit-g_profitRetrace))
      { CloseAll("Peak Lock"); Print("💰 Peak Lock: Peak=$",g_peakProfit," PnL=$",totalPnL); }
   }
   else g_peakProfit=0;
}

//====================================================================
//  TRAILING STOP
//====================================================================
void ApplyTrailingDS(ulong ticket, bool isBuy, double openP, double curSL, double curTP, double curP)
{
   if(g_atr_cached <= 0) return;
   double movE = isBuy?(curP-openP):(openP-curP);
   if(movE < InpTrailActiveMult * g_atr_cached) return;

   double step  = InpTrailStepMult * g_atr_cached;
   int    dg    = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double newSL; bool move;

   if(isBuy)
   { newSL=NormalizeDouble(curP-step,dg); move=(newSL>curSL+point); }
   else
   { newSL=NormalizeDouble(curP+step,dg); move=(curSL==0.0||newSL<curSL-point); }

   if(move) trade.PositionModify(ticket, newSL, curTP);
}

void ApplyTrailing(ulong ticket, bool isBuy)
{
   if(!PositionSelectByTicket(ticket)) return;
   double cSL=PositionGetDouble(POSITION_SL);
   double cTP=PositionGetDouble(POSITION_TP);
   double cP =PositionGetDouble(POSITION_PRICE_CURRENT);
   double oP =PositionGetDouble(POSITION_PRICE_OPEN);
   double atr=(g_atr_cached>0)?g_atr_cached:0.0010;
   double tr =atr*g_trailingMult;
   double pt =SymbolInfoDouble(_Symbol,SYMBOL_POINT);

   if(isBuy)
   { if(cP<=oP) return;
     double nSL=cP-tr;
     if(nSL>cSL+pt && nSL>=oP-pt) trade.PositionModify(ticket,nSL,cTP); }
   else
   { if(cP>=oP) return;
     double nSL=cP+tr;
     if((nSL<cSL-pt||cSL==0) && nSL<=oP+pt) trade.PositionModify(ticket,nSL,cTP); }
}

//====================================================================
//  MOTOR LONDON ORB
//====================================================================
void ORBDailyReset()
{
   g_orbRangeHigh=0; g_orbRangeLow=DBL_MAX; g_orbRangeBars=0;
   g_orbRangeBuilt=false; g_orbTradeTriggered=false; g_orbTradeOpenTime=0;
   g_orbWinsToday=0; g_orbLossesToday=0; g_orbWonToday=0; g_orbLostToday=0;
   ORBDeleteDrawings();
   Print("ORB: Reset diario.");
}

void RunLondonORB()
{
   static datetime lastBarORB=0;
   datetime cb=iTime(_Symbol,PERIOD_M1,0);
   if(cb==lastBarORB) return;
   lastBarORB=cb;

   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   datetime today=StringToTime(TimeToString(TimeCurrent(),TIME_DATE));
   if(today!=g_orbLastResetDate){ ORBDailyReset(); g_orbLastResetDate=today; }

   if(dt.hour==InpORBRangeHStart && dt.min>=0 && dt.min<=59)
   {
      double hi=iHigh(_Symbol,PERIOD_M1,1), lo=iLow(_Symbol,PERIOD_M1,1);
      if(hi>g_orbRangeHigh) g_orbRangeHigh=hi;
      if(lo<g_orbRangeLow)  g_orbRangeLow=lo;
      g_orbRangeBars++;
   }

   if(dt.hour==InpORBTradeHStart && dt.min==0 && !g_orbRangeBuilt && g_orbRangeBars>0)
   {
      double sz=g_orbRangeHigh-g_orbRangeLow;
      if(g_orbRangeBars<InpORBMinBars || sz<InpORBRangeMinPts || sz>InpORBRangeMaxPts)
      { Print("ORB: Rango inválido sz=",sz," bars=",g_orbRangeBars); return; }
      g_orbRangeBuilt=true;
      Print("ORB: Rango OK H=",g_orbRangeHigh," L=",g_orbRangeLow," sz=",sz);
      ORBDrawRangeLines();
   }

   if(!g_orbRangeBuilt||g_orbTradeTriggered) return;
   if(dt.hour<InpORBTradeHStart||dt.hour>InpORBTradeHEnd) return;
   double dayPnL=AccountInfoDouble(ACCOUNT_BALANCE)-g_dayStartBal;
   if(dayPnL<=-g_dailyLossUSD) return;
   if(SymbolInfoInteger(_Symbol,SYMBOL_SPREAD)>InpORBMaxSpread) return;

   double ef[1],es[1]; ArraySetAsSeries(ef,true); ArraySetAsSeries(es,true);
   if(CopyBuffer(hORB_EmaFast,0,1,1,ef)<=0) return;
   if(CopyBuffer(hORB_EmaSlow,0,1,1,es)<=0) return;

   double closeM1=iClose(_Symbol,PERIOD_M1,1);
   int dg=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);

   if(closeM1>g_orbRangeHigh+InpORBBreakBuf && ef[0]>es[0] && (g_sesgoUp||!g_sesgoDn))
   {
      double en=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      double sl=NormalizeDouble(g_orbRangeLow-InpORBSLBuffer,dg);
      double risk=en-sl; if(risk<=0) return;
      double tp=NormalizeDouble(en+risk*InpORBRRatio,dg);
      double lots=ORBCalcLots(risk); if(lots<=0) return;
      trade.SetExpertMagicNumber((ulong)InpMagicORB);
      if(trade.Buy(lots,_Symbol,en,sl,tp,"EURUSD_LondonORB"))
      { g_orbTradeTriggered=true; g_orbTradeOpenTime=TimeCurrent();
        Print("✅ ORB LONG @",en," SL=",sl," TP=",tp," lots=",lots);
        ORBDrawEntryLines(en,sl,tp,true); }
      trade.SetExpertMagicNumber((ulong)InpMagicS1);
   }
   else if(closeM1<g_orbRangeLow-InpORBBreakBuf && ef[0]<es[0] && (g_sesgoDn||!g_sesgoUp))
   {
      double en=SymbolInfoDouble(_Symbol,SYMBOL_BID);
      double sl=NormalizeDouble(g_orbRangeHigh+InpORBSLBuffer,dg);
      double risk=sl-en; if(risk<=0) return;
      double tp=NormalizeDouble(en-risk*InpORBRRatio,dg);
      double lots=ORBCalcLots(risk); if(lots<=0) return;
      trade.SetExpertMagicNumber((ulong)InpMagicORB);
      if(trade.Sell(lots,_Symbol,en,sl,tp,"EURUSD_LondonORB"))
      { g_orbTradeTriggered=true; g_orbTradeOpenTime=TimeCurrent();
        Print("✅ ORB SHORT @",en," SL=",sl," TP=",tp," lots=",lots);
        ORBDrawEntryLines(en,sl,tp,false); }
      trade.SetExpertMagicNumber((ulong)InpMagicS1);
   }
}

void ManageORBTrades()
{
   if(!g_orbTradeTriggered) return;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i);
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=(long)InpMagicORB) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;

      double profit=PositionGetDouble(POSITION_PROFIT);
      double cSL   =PositionGetDouble(POSITION_SL);
      double cTP   =PositionGetDouble(POSITION_TP);
      double oP    =PositionGetDouble(POSITION_PRICE_OPEN);
      double vol   =PositionGetDouble(POSITION_VOLUME);
      bool   isBuy =(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
      double cP    =isBuy?SymbolInfoDouble(_Symbol,SYMBOL_BID):SymbolInfoDouble(_Symbol,SYMBOL_ASK);

      if(g_orbTradeOpenTime>0 &&
         (int)((TimeCurrent()-g_orbTradeOpenTime)/60)>=InpORBMaxMinutes)
      { trade.SetExpertMagicNumber((ulong)InpMagicORB);
        trade.PositionClose(t);
        trade.SetExpertMagicNumber((ulong)InpMagicS1);
        Print("ORB: Cierre tiempo: $",profit); continue; }

      if(InpUseTrailing && g_atr_cached>0 && profit>0)
      {
         double tr=g_atr_cached*g_trailingMult;
         double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
         trade.SetExpertMagicNumber((ulong)InpMagicORB);
         if(isBuy){ double nSL=cP-tr; if(nSL>cSL+pt&&nSL>=oP-pt) trade.PositionModify(t,nSL,cTP); }
         else     { double nSL=cP+tr; if((nSL<cSL-pt||cSL==0)&&nSL<=oP+pt) trade.PositionModify(t,nSL,cTP); }
         trade.SetExpertMagicNumber((ulong)InpMagicS1);
      }

      if(InpUsePartialClose && g_capMode>=CAP_MEDIUM && cSL>0)
      {
         double slD=MathAbs(oP-cSL);
         double mR=(slD>0)?MathAbs(cP-oP)/slD:0;
         if(mR>=1.0)
         {
            double minV=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
            double hV=NormLot(vol*0.50);
            if(hV>=minV)
            {
               static datetime lPB=0; datetime cbr=iTime(_Symbol,PERIOD_M5,0);
               if(cbr!=lPB)
               {
                  trade.SetExpertMagicNumber((ulong)InpMagicORB);
                  trade.PositionClosePartial(t,hV);
                  double pt2=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
                  double nSL=isBuy?oP+pt2:oP-pt2;
                  if((isBuy&&nSL>cSL)||(!isBuy&&nSL<cSL)) trade.PositionModify(t,nSL,cTP);
                  trade.SetExpertMagicNumber((ulong)InpMagicS1);
                  lPB=cbr; Print("💰 ORB Parcial 50% @1R | BE: $",profit);
               }
            }
         }
      }
   }
}

double ORBCalcLots(double riskPts)
{
   double bal=AccountInfoDouble(ACCOUNT_BALANCE);
   double rf=(CountOpenPositions()>0)?0.50:1.0;
   double ra=bal*g_riskPct/100.0*rf;
   double tv=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   double ts=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   double pv=(ts>0)?(tv/ts*_Point):0;
   if(pv<=0||riskPts<=0) return 0;
   double lots=ra/((riskPts/_Point)*pv);
   if(g_capMode==CAP_MICRO) lots=MathMin(lots,SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN)*2.0);
   return NormLot(lots);
}

void CloseAllORB(string reason)
{
   trade.SetExpertMagicNumber((ulong)InpMagicORB);
   for(int i=PositionsTotal()-1;i>=0;i--)
   { ulong t=PositionGetTicket(i);
     if(!PositionSelectByTicket(t)) continue;
     if(PositionGetInteger(POSITION_MAGIC)==(long)InpMagicORB &&
        PositionGetString(POSITION_SYMBOL)==_Symbol) trade.PositionClose(t); }
   trade.SetExpertMagicNumber((ulong)InpMagicS1);
   Print("ORB cerrado: ",reason);
}

//====================================================================
//  TRACKING
//====================================================================
void TrackClosedTrades()
{
   static int hC=0; int tot=HistoryDealsTotal();
   if(tot==hC) return;
   for(int i=hC;i<tot;i++)
   {
      ulong t=HistoryDealGetTicket(i); if(!t) continue;
      long mg=(long)HistoryDealGetInteger(t,DEAL_MAGIC);
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(t,DEAL_ENTRY)!=DEAL_ENTRY_OUT) continue;
      double p=HistoryDealGetDouble(t,DEAL_PROFIT);
      if(mg==InpMagicS1||mg==InpMagicS2)
      { if(p>0){g_winsToday++;g_totalWon+=p;} else if(p<0){g_lossesToday++;g_totalLost+=MathAbs(p);} }
      else if(mg==InpMagicORB)
      { if(p>0){g_orbWinsToday++;g_orbWonToday+=p;} else if(p<0){g_orbLossesToday++;g_orbLostToday+=MathAbs(p);} }
   }
   hC=tot;
}

//====================================================================
//  OnTradeTransaction – Estadísticas DS
//====================================================================
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest     &req,
                        const MqlTradeResult      &res)
{
   if(trans.type!=TRADE_TRANSACTION_DEAL_ADD) return;
   ulong deal=trans.deal; if(deal==0) return;
   if(!HistoryDealSelect(deal)) return;

   ENUM_DEAL_ENTRY de=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal,DEAL_ENTRY);
   if(de!=DEAL_ENTRY_OUT && de!=DEAL_ENTRY_OUT_BY) return;

   ulong  mg  =(ulong)HistoryDealGetInteger(deal,DEAL_MAGIC);
   double pnl =HistoryDealGetDouble(deal,DEAL_PROFIT)
              +HistoryDealGetDouble(deal,DEAL_SWAP)
              +HistoryDealGetDouble(deal,DEAL_COMMISSION);
   ulong  posId=(ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID);

   RemovePartialEntry(posId);

   if(mg==(ulong)InpMagicS1)
   { g_TradesS1++; g_NetS1+=pnl;
     if(pnl>=0){g_WinsS1++; g_GrossWinS1+=pnl;} else {g_LossS1++; g_GrossLossS1+=MathAbs(pnl);} }
   else if(mg==(ulong)InpMagicS2)
   { g_TradesS2++; g_NetS2+=pnl;
     if(pnl>=0){g_WinsS2++; g_GrossWinS2+=pnl;} else {g_LossS2++; g_GrossLossS2+=MathAbs(pnl);} }

   // Gestión grupo MT
   if((mg==(ulong)InpMagicS1||mg==(ulong)InpMagicS2) && g_mtGroupActive)
   {
      bool anyLeft=false;
      for(int i=0;i<g_maxMultiTrades;i++)
         if(g_mtGroup.tickets[i]&&PositionSelectByTicket(g_mtGroup.tickets[i]))
         { anyLeft=true; break; }
      if(!anyLeft) { g_mtGroupActive=false; Print("📊 Grupo MT completado."); }
   }

   string src=(mg==(ulong)InpMagicORB)?"[ORB]":
              (mg==(ulong)InpMagicS1)?"[S1]":"[S2]";
   Print(src," CIERRE $",DoubleToString(pnl,2),pnl>=0?" ✅":" ❌");
}

//====================================================================
//  HELPERS
//====================================================================
bool IsNewBar()
{
   static datetime last=0;
   datetime cur=iTime(_Symbol,PERIOD_M5,0);
   if(cur==last) return false;
   last=cur; return true;
}

int CountPos(ulong magic)
{
   int n=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
      if(Pos.SelectByIndex(i) && Pos.Symbol()==_Symbol && Pos.Magic()==magic)
         n++;
   return n;
}

int CountOpenPositions()
{
   int c=0;
   for(int i=0;i<PositionsTotal();i++)
   { ulong t=PositionGetTicket(i);
     if(PositionSelectByTicket(t))
     { long mg=(long)PositionGetInteger(POSITION_MAGIC);
       if(mg==InpMagicS1||mg==InpMagicS2) c++; } }
   return c;
}

void CloseAll(string reason)
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      if(!Pos.SelectByIndex(i)) continue;
      if(Pos.Symbol()!=_Symbol) continue;
      ulong mg=Pos.Magic();
      if(mg!=(ulong)InpMagicS1 && mg!=(ulong)InpMagicS2) continue;
      trade.SetExpertMagicNumber(mg);
      trade.PositionClose(Pos.Ticket());
      RemoveTradeTracker(Pos.Ticket());
   }
   Print("[",reason,"] Posiciones cerradas.");
}

bool DailyLimitHit()
{
   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
   double lim = g_DayStartBalance * InpMaxDailyLossPct / 100.0;
   return ((g_DayStartBalance - eq) >= lim);
}

void UpdateDayBalance()
{
   MqlDateTime n, l;
   TimeToStruct(TimeCurrent(), n);
   TimeToStruct(g_LastDay,     l);
   if(n.day!=l.day || n.mon!=l.mon || n.year!=l.year)
   { g_DayStartBalance=AccountInfoDouble(ACCOUNT_BALANCE); g_LastDay=TimeCurrent(); }
}

bool IsFridayClose()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   return (dt.day_of_week==5 && dt.hour>=InpFridayHour);
}

bool ValidHour()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   return (dt.hour>=InpStartHour && dt.hour<InpEndHour);
}

bool IsPartialDone(ulong ticket)
{
   for(int i=0;i<g_PartialCount;i++) if(g_PartialDone[i]==ticket) return true;
   return false;
}

void MarkPartialDone(ulong ticket)
{
   if(IsPartialDone(ticket)) return;
   ArrayResize(g_PartialDone, g_PartialCount+1);
   g_PartialDone[g_PartialCount]=ticket;
   g_PartialCount++;
}

void RemovePartialEntry(ulong ticket)
{
   for(int i=0;i<g_PartialCount;i++)
   { if(g_PartialDone[i]==ticket)
     { for(int j=i;j<g_PartialCount-1;j++) g_PartialDone[j]=g_PartialDone[j+1];
       g_PartialCount--; ArrayResize(g_PartialDone,g_PartialCount); return; } }
}

void RegisterTrade(ulong t)
{ if(!t||g_openTradeCount>=100) return;
  g_openTrades[g_openTradeCount].ticket=t;
  g_openTrades[g_openTradeCount].openTime=TimeCurrent();
  g_openTradeCount++; }

int FindTradeTracker(ulong t)
{ for(int i=0;i<g_openTradeCount;i++) if(g_openTrades[i].ticket==t) return i; return -1; }

void RemoveTradeTracker(ulong t)
{ for(int i=0;i<g_openTradeCount;i++)
  { if(g_openTrades[i].ticket==t)
    { for(int j=i;j<g_openTradeCount-1;j++) g_openTrades[j]=g_openTrades[j+1];
      g_openTradeCount--; return; } } }

double NormLot(double lot)
{ double mn=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
  double mx=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
  double st=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
  lot=MathFloor(lot/st)*st;
  return MathMax(mn,MathMin(mx,lot)); }

//====================================================================
//  GRÁFICOS ORB
//====================================================================
void ORBDrawRangeLines()
{
   ObjectDelete(0,"ORB_HIGH"); ObjectDelete(0,"ORB_LOW");
   ObjectDelete(0,"ORB_BULL"); ObjectDelete(0,"ORB_BEAR");
   ObjectCreate(0,"ORB_HIGH",OBJ_HLINE,0,0,g_orbRangeHigh);
   ObjectSetInteger(0,"ORB_HIGH",OBJPROP_COLOR,clrDodgerBlue);
   ObjectSetInteger(0,"ORB_HIGH",OBJPROP_STYLE,STYLE_DASH);
   ObjectSetString(0, "ORB_HIGH",OBJPROP_TEXT,"ORB H:"+DoubleToString(g_orbRangeHigh,5));
   ObjectCreate(0,"ORB_LOW",OBJ_HLINE,0,0,g_orbRangeLow);
   ObjectSetInteger(0,"ORB_LOW",OBJPROP_COLOR,clrOrangeRed);
   ObjectSetInteger(0,"ORB_LOW",OBJPROP_STYLE,STYLE_DASH);
   ObjectSetString(0, "ORB_LOW",OBJPROP_TEXT,"ORB L:"+DoubleToString(g_orbRangeLow,5));
   ObjectCreate(0,"ORB_BULL",OBJ_HLINE,0,0,g_orbRangeHigh+InpORBBreakBuf);
   ObjectSetInteger(0,"ORB_BULL",OBJPROP_COLOR,clrLimeGreen);
   ObjectSetInteger(0,"ORB_BULL",OBJPROP_STYLE,STYLE_DOT);
   ObjectSetString(0, "ORB_BULL",OBJPROP_TEXT,"LONG TRIGGER");
   ObjectCreate(0,"ORB_BEAR",OBJ_HLINE,0,0,g_orbRangeLow-InpORBBreakBuf);
   ObjectSetInteger(0,"ORB_BEAR",OBJPROP_COLOR,clrRed);
   ObjectSetInteger(0,"ORB_BEAR",OBJPROP_STYLE,STYLE_DOT);
   ObjectSetString(0, "ORB_BEAR",OBJPROP_TEXT,"SHORT TRIGGER");
   ChartRedraw();
}

void ORBDrawEntryLines(double en, double sl, double tp, bool isLong)
{
   string p=isLong?"LONG":"SHORT";
   ObjectDelete(0,"ORB_ENTRY"); ObjectDelete(0,"ORB_SL"); ObjectDelete(0,"ORB_TP");
   ObjectCreate(0,"ORB_ENTRY",OBJ_HLINE,0,0,en);
   ObjectSetInteger(0,"ORB_ENTRY",OBJPROP_COLOR,clrGold);
   ObjectSetInteger(0,"ORB_ENTRY",OBJPROP_WIDTH,2);
   ObjectSetString(0, "ORB_ENTRY",OBJPROP_TEXT,p+" ENTRY:"+DoubleToString(en,5));
   ObjectCreate(0,"ORB_SL",OBJ_HLINE,0,0,sl);
   ObjectSetInteger(0,"ORB_SL",OBJPROP_COLOR,clrRed);
   ObjectSetInteger(0,"ORB_SL",OBJPROP_WIDTH,2);
   ObjectSetString(0, "ORB_SL",OBJPROP_TEXT,"SL:"+DoubleToString(sl,5));
   ObjectCreate(0,"ORB_TP",OBJ_HLINE,0,0,tp);
   ObjectSetInteger(0,"ORB_TP",OBJPROP_COLOR,clrLimeGreen);
   ObjectSetInteger(0,"ORB_TP",OBJPROP_WIDTH,2);
   ObjectSetString(0, "ORB_TP",OBJPROP_TEXT,"TP:"+DoubleToString(tp,5));
   ChartRedraw();
}

void ORBDeleteDrawings()
{
   string n[]={"ORB_HIGH","ORB_LOW","ORB_BULL","ORB_BEAR","ORB_ENTRY","ORB_SL","ORB_TP"};
   for(int i=0;i<ArraySize(n);i++) ObjectDelete(0,n[i]);
   ChartRedraw();
}

//====================================================================
//  PANEL UNIFICADO
//====================================================================
void DrawPanel()
{
   if(!InpShowPanel) return;
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);

   int posS1=0, posS2=0, posORB=0, posMT=0;
   double pnlS1=0, pnlS2=0, pnlORB=0, pnlMT=0;

   for(int i=0;i<PositionsTotal();i++)
   { ulong t=PositionGetTicket(i);
     if(!PositionSelectByTicket(t)) continue;
     long mg=(long)PositionGetInteger(POSITION_MAGIC);
     if(mg==InpMagicS1)  {posS1++;  pnlS1 +=PositionGetDouble(POSITION_PROFIT);}
     else if(mg==InpMagicS2) {posS2++; pnlS2+=PositionGetDouble(POSITION_PROFIT);}
     else if(mg==InpMagicORB){posORB++;pnlORB+=PositionGetDouble(POSITION_PROFIT);} }

   if(g_mtGroupActive)
      for(int i=1;i<g_maxMultiTrades;i++)
      { if(!g_mtGroup.tickets[i]) continue;
        if(PositionSelectByTicket(g_mtGroup.tickets[i]))
        {posMT++;pnlMT+=PositionGetDouble(POSITION_PROFIT);} }

   double dayPnL=AccountInfoDouble(ACCOUNT_BALANCE)-g_dayStartBal;
   double bal   =AccountInfoDouble(ACCOUNT_BALANCE);
   int    tAll  =g_winsToday+g_lossesToday;
   double wrAll =tAll>0?(100.0*g_winsToday/tAll):0;
   int    tORB  =g_orbWinsToday+g_orbLossesToday;
   double wrORB =tORB>0?(100.0*g_orbWinsToday/tORB):0;

   string wr1=(g_TradesS1>0)?DoubleToString((double)g_WinsS1/g_TradesS1*100.0,1)+"%":"-";
   string wr2=(g_TradesS2>0)?DoubleToString((double)g_WinsS2/g_TradesS2*100.0,1)+"%":"-";
   string orbR=(g_orbRangeHigh>0&&g_orbRangeLow<DBL_MAX)?
      DoubleToString(g_orbRangeHigh,5)+"/"+DoubleToString(g_orbRangeLow,5):"---";

   string sORB=!InpLondonORBOn?"⬜OFF":g_orbTradeTriggered?"✅TRADE":g_orbRangeBuilt?"🎯ESPERA":
               (dt.hour==InpORBRangeHStart?"📐CONSTRUYENDO":"⏳ESPERA 07:00");
   string sMT=!InpMultiTradeOn?"⬜OFF":g_mtGroupActive?
               StringFormat("🔥ACTIVO(%d)",posMT+1):StringFormat("🔍Umbral:%.0f%%",InpMTF_ScoreThresh);

   string txt="";
   txt+="═══ EURUSD QQ ULTIMATE – DUAL STRATEGY v1.0 ═══\n";
   txt+=StringFormat("Hora: %02d:%02d | %s | Max/señal: %d\n",dt.hour,dt.min,CapModeStr(),g_maxMultiTrades);
   txt+=StringFormat("Bal : $%.2f | PnL Día: $%.2f\n",bal,dayPnL);
   txt+=StringFormat("Tgt : +$%.2f | Stop: -$%.2f\n",g_dailyProfitUSD,g_dailyLossUSD);
   txt+=StringFormat("D1  : %s | H1: %s | ATR: %.5f\n",
        g_sesgoUp?"📈BUY":(g_sesgoDn?"📉SELL":"---"),
        g_h1Up?"↑UP":(g_h1Dn?"↓DWN":"="),g_atr_cached);
   txt+="─── S1: BB+RSI ───\n";
   txt+=StringFormat("Pos : %d pnl:$%.2f | Trades: %d W:%d L:%d WR:%s Net:$%.2f\n",
        posS1,pnlS1,g_TradesS1,g_WinsS1,g_LossS1,wr1,g_NetS1);
   txt+="─── S2: Stoch+RSI ───\n";
   txt+=StringFormat("Pos : %d pnl:$%.2f | Trades: %d W:%d L:%d WR:%s Net:$%.2f\n",
        posS2,pnlS2,g_TradesS2,g_WinsS2,g_LossS2,wr2,g_NetS2);
   txt+="─── Multi-Trade MTF ───\n";
   txt+=StringFormat("Est : %s\n",sMT);
   if(g_mtGroupActive)
      txt+=StringFormat("Grp : %d trades | PnL: $%.2f | Score: %.0f%%\n",
           g_mtGroup.count,pnlMT+pnlS1+pnlS2,g_mtGroup.mtfScore);
   txt+="─── Pirámide ───\n";
   txt+=StringFormat("Niv : %d/%d | BE:%s P1:%s P2:%s Peak:$%.2f\n",
        g_pyramidLevel,InpPyramidLevels,g_beMoved?"✅":"○",
        g_partial1Done?"✅":"○",g_partial2Done?"✅":"○",g_peakProfit);
   txt+="─── London ORB ───\n";
   txt+=StringFormat("Est : %s\n",sORB);
   txt+=StringFormat("Rng : %s (%d barras)\n",orbR,g_orbRangeBars);
   txt+=StringFormat("Pos : %d pnl:$%.2f\n",posORB,pnlORB);
   txt+=StringFormat("Res : W%d L%d WR:%.1f%% $%.2f\n",g_orbWinsToday,g_orbLossesToday,wrORB,g_orbWonToday);
   txt+=StringFormat("─── Totales ───\n");
   txt+=StringFormat("Hoy : %d trades | W%d L%d WR:%.1f%% | Trades: %d/%d\n",
        tAll+tORB,g_winsToday,g_lossesToday,wrAll,g_tradesToday,g_maxTradesDay);
   Comment(txt);
}

//====================================================================
//  DASHBOARD (esquina superior izquierda – estilo DS)
//====================================================================
void DashLabel(string id, int x, int y, string txt, color cl, int sz=9)
{
   string n=g_Pfx+id;
   if(ObjectFind(0,n)<0)
   { ObjectCreate(0,n,OBJ_LABEL,0,0,0);
     ObjectSetInteger(0,n,OBJPROP_CORNER,CORNER_LEFT_UPPER);
     ObjectSetInteger(0,n,OBJPROP_SELECTABLE,false);
     ObjectSetInteger(0,n,OBJPROP_HIDDEN,true);
     ObjectSetInteger(0,n,OBJPROP_BACK,false); }
   ObjectSetInteger(0,n,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,n,OBJPROP_YDISTANCE,y);
   ObjectSetString (0,n,OBJPROP_TEXT,txt);
   ObjectSetInteger(0,n,OBJPROP_COLOR,cl);
   ObjectSetInteger(0,n,OBJPROP_FONTSIZE,sz);
   ObjectSetString (0,n,OBJPROP_FONT,"Consolas");
}

void CreateDash() { UpdateDash(); }
void DeleteDash() { ObjectsDeleteAll(0,g_Pfx); ChartRedraw(0); }

void UpdateDash()
{
   int x=InpDashX, y=InpDashY, lh=15;
   color cT=clrWhite, cH=clrDeepSkyBlue, cB=clrSilver;
   color cG=clrLimeGreen, cR=clrTomato, cY=clrGold, cGr=clrDimGray;

   string wr1=(g_TradesS1>0)?DoubleToString((double)g_WinsS1/g_TradesS1*100.0,1)+"%":"-";
   string wr2=(g_TradesS2>0)?DoubleToString((double)g_WinsS2/g_TradesS2*100.0,1)+"%":"-";
   string pf1=(g_GrossLossS1>0)?DoubleToString(g_GrossWinS1/g_GrossLossS1,2):(g_GrossWinS1>0?"inf":"-");
   string pf2=(g_GrossLossS2>0)?DoubleToString(g_GrossWinS2/g_GrossLossS2,2):(g_GrossWinS2>0?"inf":"-");
   color wr1c=(g_TradesS1>0)?((double)g_WinsS1/g_TradesS1>=0.6?cG:cY):cB;
   color wr2c=(g_TradesS2>0)?((double)g_WinsS2/g_TradesS2>=0.6?cG:cY):cB;

   bool   alive=!DailyLimitHit();
   double bal  =AccountInfoDouble(ACCOUNT_BALANCE);
   double eq   =AccountInfoDouble(ACCOUNT_EQUITY);

   DashLabel("T",  x, y,        "= EURUSD QQ DS v1.0 =",  cT,  10);
   DashLabel("D0", x, y+lh,     "----------------------", cGr,   8);
   DashLabel("H1", x, y+lh*2,   "S1  BB+RSI",             cH,    9);
   DashLabel("1A", x, y+lh*3,   StringFormat("  Trades : %d (%dW/%dL)",g_TradesS1,g_WinsS1,g_LossS1), cB, 9);
   DashLabel("1B", x, y+lh*4,   StringFormat("  WinRate: %s",wr1),  wr1c, 9);
   DashLabel("1C", x, y+lh*5,   StringFormat("  ProfFac: %s",pf1),  cB,   9);
   DashLabel("1D", x, y+lh*6,   StringFormat("  Net P&L: %+.2f",g_NetS1), g_NetS1>=0?cG:cR, 9);
   DashLabel("D1", x, y+lh*7+2, "----------------------", cGr,   8);
   DashLabel("H2", x, y+lh*8,   "S2  STOCH+RSI",          cH,    9);
   DashLabel("2A", x, y+lh*9,   StringFormat("  Trades : %d (%dW/%dL)",g_TradesS2,g_WinsS2,g_LossS2), cB, 9);
   DashLabel("2B", x, y+lh*10,  StringFormat("  WinRate: %s",wr2),  wr2c, 9);
   DashLabel("2C", x, y+lh*11,  StringFormat("  ProfFac: %s",pf2),  cB,   9);
   DashLabel("2D", x, y+lh*12,  StringFormat("  Net P&L: %+.2f",g_NetS2), g_NetS2>=0?cG:cR, 9);
   DashLabel("D2", x, y+lh*13+2,"----------------------", cGr,   8);
   DashLabel("BA", x, y+lh*14,  StringFormat("  Balance: %.2f",bal), cB,  9);
   DashLabel("EQ", x, y+lh*15,  StringFormat("  Equity : %.2f",eq),  eq>=bal?cG:cY, 9);
   DashLabel("ST", x, y+lh*16,  StringFormat("  Estado : %s",alive?"ACTIVO":"DAILY LIMIT"), alive?cG:cR, 9);
   DashLabel("MT", x, y+lh*17,  StringFormat("  MTF    : %s | Cap: %s",
             g_mtGroupActive?"ACTIVO":"en espera", CapModeStr()), cB, 9);
   ChartRedraw(0);
}
//+------------------------------------------------------------------+
//  FIN – EURUSD QQ ULTIMATE DUAL STRATEGY EDITION v1.0
//+------------------------------------------------------------------+
