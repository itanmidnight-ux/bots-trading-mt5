//+------------------------------------------------------------------+
//|  XAUUSD QUANTUM QUEEN ULTIMATE v7.0 – MULTI-TRADE EDITION       |
//|                                                                  |
//|  Motores  : QQ Breakout | EMA Scalper | Retest | Pirámide        |
//|             London Open Range Breakout (S2)                      |
//|  Nuevo    : Sistema Multi-Trades por Capital + Validación MTF    |
//|  Gestión  : 10 Capas de Protección | Peak Lock | Smart Exit      |
//|                                                                  |
//|  Diseño MTF para ejecución M1:                                   |
//|    • D1 / H1  → VETO DURO (sin puntaje, bloquean la señal)      |
//|    • H4       → Confirmador de contexto (peso 20%)              |
//|    • M5       → Momentum pre-ejecución  (peso 45%)              |
//|    • M1       → Confirmación de entrada (peso 35%)              |
//|                                                                  |
//|  Multi-Trade: mismo SL/TP para todos los trades del grupo.       |
//|  Cada trade se gestiona de forma completamente independiente.    |
//|  Magic QQ = 5900 | Magic ORB = 20250800                         |
//+------------------------------------------------------------------+
#property copyright "QQ Ultimate v7.0 – Multi-Trade Edition"
#property version   "7.00"
#property strict

#include <Trade/Trade.mqh>
CTrade trade;

//====================================================================
//  ENUMERACIONES
//====================================================================
enum ENUM_CAP_MODE
{
   CAP_MICRO    = 0,  // $1   – $24.99  → 1 trade máximo por señal
   CAP_SMALL    = 1,  // $25  – $59.99  → 2 trades máximo por señal
   CAP_MEDIUM   = 2,  // $60  – $119.99 → 3 trades máximo por señal
   CAP_UPPER    = 3,  // $120 – $239.99 → 4 trades máximo por señal
   CAP_STANDARD = 4   // $240+          → 5 trades máximo por señal
};

//====================================================================
//  INPUTS – GESTIÓN DE CAPITAL
//====================================================================
input group "=== GESTIÓN DE CAPITAL ==="
input bool   InpAutoCapital      = true;   // Detectar capital en tiempo real
input double InpRiskPercent      = 0.8;    // % riesgo base por trade individual
input int    InpMagic            = 5900;   // Magic QQ (Breakout / Scalper / Retest)

//====================================================================
//  INPUTS – SISTEMA MULTI-TRADES
//====================================================================
input group "=== SISTEMA MULTI-TRADES ==="
input bool   InpMultiTradeOn     = true;   // Activar sistema multi-trades
input double InpMTF_ScoreThresh  = 82.0;   // Score MTF mínimo para activar (0-100)
input int    InpMTF_WindowSec    = 4;      // Ventana máxima de apertura tardía (seg)
// Nota: todos los trades del grupo comparten el mismo SL y TP del trade principal

//====================================================================
//  INPUTS – ESTRATEGIA QQ BREAKOUT
//====================================================================
input group "=== ESTRATEGIA QQ BREAKOUT ==="
input int    InpRangeHourStart   = 7;
input int    InpRangeHourEnd     = 8;
input int    InpBreakoutHourEnd  = 10;
input double InpRangeMinPts      = 1.5;
input double InpRangeMaxPts      = 12.0;
input double InpBreakoutOffset   = 0.20;
input double InpRR               = 2.2;

//====================================================================
//  INPUTS – EMA SCALPER
//====================================================================
input group "=== ESTRATEGIA EMA SCALPER ==="
input bool   InpScalperOn        = true;
input int    InpScalperHourStart = 8;
input int    InpScalperHourEnd   = 20;
input int    InpFastEMA          = 9;
input int    InpSlowEMA          = 21;
input int    InpTrendEMA         = 50;

//====================================================================
//  INPUTS – LONDON ORB
//====================================================================
input group "=== ESTRATEGIA LONDON ORB (S2) ==="
input bool   InpLondonORBOn      = true;
input int    InpMagicORB         = 20250800;
input int    InpORBRangeHStart   = 7;
input int    InpORBTradeHStart   = 8;
input int    InpORBTradeHEnd     = 9;
input int    InpORBMaxMinutes    = 120;
input double InpORBRangeMinPts   = 2.0;
input double InpORBRangeMaxPts   = 10.0;
input int    InpORBMinBars       = 25;
input double InpORBBreakBuf      = 0.2;
input double InpORBSLBuffer      = 0.3;
input double InpORBRR            = 2.0;
input int    InpORBEmaFast       = 50;
input int    InpORBEmaSlow       = 200;
input int    InpORBMaxSpread     = 50;

//====================================================================
//  INPUTS – SL/TP DINÁMICO
//====================================================================
input group "=== SL/TP DINÁMICO ==="
input double InpATR_SL_Mult      = 1.3;
input double InpATR_TP_Mult      = 2.6;

//====================================================================
//  INPUTS – SISTEMA PIRAMIDAL
//====================================================================
input group "=== SISTEMA PIRAMIDAL ==="
input bool   InpPyramidOn        = true;
input int    InpPyramidLevels    = 2;

//====================================================================
//  INPUTS – CIERRES
//====================================================================
input group "=== CIERRES AUTOMÁTICOS ==="
input bool   InpTrailingOn       = true;
input bool   InpPartialClose     = true;
input bool   InpSmartExitOn      = true;
input bool   InpMomentumExitOn   = true;
input double InpMinProfitLock    = 0.30;

//====================================================================
//  INPUTS – PROTECCIONES
//====================================================================
input group "=== PROTECCIONES ==="
input double InpMaxSpread        = 45.0;
input double InpMaxDailyLossPct  = 3.0;

//====================================================================
//  INPUTS – INDICADORES
//====================================================================
input group "=== INDICADORES ==="
input int    InpBBPeriod         = 20;
input int    InpRSIPeriod        = 14;
input int    InpMFIPeriod        = 14;
input int    InpATRPeriod        = 14;

input group "=== MONITOREO ==="
input bool   InpShowPanel        = true;

//====================================================================
//  HANDLES – QQ ORIGINAL
//====================================================================
int hEMA50_D1,  hEMA200_D1;
int hRSI_H1,    hATR_H1;
int hBB_M5,     hRSI_M5,    hMFI_M5,    hATR_M5;
int hFastEMA_M5,hSlowEMA_M5,hTrendEMA_M5;
int hFastEMA_M1,hSlowEMA_M1,hTrendEMA_M1;
int hRSI_M1,    hATR_M1;

//====================================================================
//  HANDLES – SISTEMA MTF MULTI-TRADE
//  Vetos : D1 (EMA50/200) y H1 (RSI + EMA estructura) — sin puntuación
//  Score : H4 (20%) + M5 (45%) + M1 (35%)
//====================================================================
// Vetos D1 — ya cubiertos por hEMA50_D1 / hEMA200_D1

// Vetos H1 — reutiliza hRSI_H1 + dos EMAs adicionales
int hEMA21_H1, hEMA50_H1;

// Contexto H4 (20%)
int hRSI_H4, hATR_H4, hEMA50_H4;

// Momentum M5 (45%)
int hEMA9_M5, hEMA21_M5mt, hMACD_M5_main, hMACD_M5_signal;
// NOTA: usamos dos EMAs cruzadas + RSI M5 existente + ATR M5 existente

// Confirmación M1 (35%)
int hEMA9_M1, hEMA21_M1, hRSI_M1mt, hATR_M1mt;

//====================================================================
//  HANDLES – LONDON ORB
//====================================================================
int hORB_EmaFast, hORB_EmaSlow;

//====================================================================
//  VARIABLES DE CAPITAL
//====================================================================
ENUM_CAP_MODE g_capMode          = CAP_MICRO;
double        g_riskPct          = 0.8;
double        g_dailyLossUSD     = 0;
double        g_dailyProfitUSD   = 0;
double        g_minProfitLock    = 0;
double        g_profitRetrace    = 0;
double        g_pyramidTrig1     = 0;
double        g_pyramidTrig2     = 0;
double        g_pyramidLotMult   = 0;
double        g_trailingMult     = 0;
double        g_scalperRR        = 0;
int           g_maxTradesDay     = 0;
int           g_maxBarsOpen      = 0;
int           g_maxNegBars       = 0;
double        g_partialAt1R      = 0;
double        g_partialAt2R      = 0;
int           g_maxMultiTrades   = 1;  // Actualizado en tiempo real según capital

//====================================================================
//  ESTADO QQ
//====================================================================
double   g_rangeHigh    = 0, g_rangeLow = 0;
int      g_rangeBars    = 0;
bool     g_dayInvalid   = false;
bool     g_initialized  = false;
bool     g_triggered    = false;
datetime g_breakoutTime = 0;
bool     g_sesgoUp      = false, g_sesgoDn = false;
bool     g_h1Up         = false, g_h1Dn    = false;
int      g_tradesToday  = 0;
double   g_dayStartBal  = 0;
datetime g_lastDay      = 0;
int      g_pyramidLevel = 0;
double   g_entry1Lot    = 0, g_entry1Price = 0;
bool     g_partial1Done = false, g_partial2Done = false, g_beMoved = false;
double   g_peakProfit   = 0;
double   g_atr_cached   = 0, g_bbMid_cached = 0;
datetime g_lastBarM5    = 0;

struct TradeInfo { ulong ticket; datetime openTime; };
TradeInfo g_openTrades[50];
int       g_openTradeCount = 0;

int    g_winsToday  = 0, g_lossesToday = 0;
double g_totalWon   = 0, g_totalLost   = 0;

//====================================================================
//  ESTADO SISTEMA MULTI-TRADES
//====================================================================

// Un grupo contiene hasta 5 tickets (1 maestro + hasta 4 adicionales)
// Todos comparten el mismo SL y TP; cada trade se gestiona solo.
struct MultiTradeGroup
{
   ulong    tickets[5];      // tickets[0] = trade maestro, [1..N] = adicionales
   int      count;           // número real de trades en el grupo
   bool     isBuy;
   double   sharedSL;        // SL idéntico para todos
   double   sharedTP;        // TP idéntico para todos
   double   baseLot;         // lote del trade maestro
   datetime openTime;        // marca temporal del grupo
   double   mtfScore;        // score MTF que desencadenó el grupo
};

MultiTradeGroup g_mtGroup;
bool            g_mtGroupActive = false;

// Estadísticas MT
int    g_mtWinsTotal  = 0, g_mtLossTotal = 0;
double g_mtWonTotal   = 0, g_mtLostTotal = 0;

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
   //---- QQ original ----
   hEMA50_D1    = iMA(_Symbol, PERIOD_D1, 50,  0, MODE_EMA, PRICE_CLOSE);
   hEMA200_D1   = iMA(_Symbol, PERIOD_D1, 200, 0, MODE_EMA, PRICE_CLOSE);
   hRSI_H1      = iRSI(_Symbol, PERIOD_H1, InpRSIPeriod, PRICE_CLOSE);
   hATR_H1      = iATR(_Symbol, PERIOD_H1, InpATRPeriod);
   hBB_M5       = iBands(_Symbol, PERIOD_M5, InpBBPeriod, 0, 2.0, PRICE_CLOSE);
   hRSI_M5      = iRSI(_Symbol,  PERIOD_M5, InpRSIPeriod, PRICE_CLOSE);
   hMFI_M5      = iMFI(_Symbol,  PERIOD_M5, InpMFIPeriod, VOLUME_TICK);
   hATR_M5      = iATR(_Symbol,  PERIOD_M5, InpATRPeriod);
   hFastEMA_M5  = iMA(_Symbol,  PERIOD_M5, InpFastEMA,   0, MODE_EMA, PRICE_CLOSE);
   hSlowEMA_M5  = iMA(_Symbol,  PERIOD_M5, InpSlowEMA,   0, MODE_EMA, PRICE_CLOSE);
   hTrendEMA_M5 = iMA(_Symbol,  PERIOD_M5, InpTrendEMA,  0, MODE_EMA, PRICE_CLOSE);
   hFastEMA_M1  = iMA(_Symbol,  PERIOD_M1, InpFastEMA,   0, MODE_EMA, PRICE_CLOSE);
   hSlowEMA_M1  = iMA(_Symbol,  PERIOD_M1, InpSlowEMA,   0, MODE_EMA, PRICE_CLOSE);
   hTrendEMA_M1 = iMA(_Symbol,  PERIOD_M1, InpTrendEMA,  0, MODE_EMA, PRICE_CLOSE);
   hRSI_M1      = iRSI(_Symbol,  PERIOD_M1, InpRSIPeriod, PRICE_CLOSE);
   hATR_M1      = iATR(_Symbol,  PERIOD_M1, InpATRPeriod);

   //---- MTF Multi-Trade ----
   // Vetos H1
   hEMA21_H1    = iMA(_Symbol, PERIOD_H1, 21, 0, MODE_EMA, PRICE_CLOSE);
   hEMA50_H1    = iMA(_Symbol, PERIOD_H1, 50, 0, MODE_EMA, PRICE_CLOSE);
   // Contexto H4
   hRSI_H4      = iRSI(_Symbol, PERIOD_H4, InpRSIPeriod, PRICE_CLOSE);
   hATR_H4      = iATR(_Symbol, PERIOD_H4, InpATRPeriod);
   hEMA50_H4    = iMA(_Symbol,  PERIOD_H4, 50, 0, MODE_EMA, PRICE_CLOSE);
   // Momentum M5
   hEMA9_M5     = iMA(_Symbol,  PERIOD_M5, 9,  0, MODE_EMA, PRICE_CLOSE);
   hEMA21_M5mt  = iMA(_Symbol,  PERIOD_M5, 21, 0, MODE_EMA, PRICE_CLOSE);
   // Confirmación M1
   hEMA9_M1     = iMA(_Symbol,  PERIOD_M1, 9,  0, MODE_EMA, PRICE_CLOSE);
   hEMA21_M1    = iMA(_Symbol,  PERIOD_M1, 21, 0, MODE_EMA, PRICE_CLOSE);
   hRSI_M1mt    = iRSI(_Symbol, PERIOD_M1, InpRSIPeriod, PRICE_CLOSE);
   hATR_M1mt    = iATR(_Symbol, PERIOD_M1, InpATRPeriod);

   //---- ORB ----
   hORB_EmaFast = iMA(_Symbol, PERIOD_M1, InpORBEmaFast, 0, MODE_EMA, PRICE_CLOSE);
   hORB_EmaSlow = iMA(_Symbol, PERIOD_M1, InpORBEmaSlow, 0, MODE_EMA, PRICE_CLOSE);

   // Verificar handles críticos
   int criticals[] = {
      hEMA50_D1, hEMA200_D1, hRSI_H1, hATR_H1,
      hBB_M5, hRSI_M5, hATR_M5, hFastEMA_M5, hFastEMA_M1,
      hEMA21_H1, hEMA50_H1, hRSI_H4, hATR_H4, hEMA50_H4,
      hEMA9_M5, hEMA21_M5mt, hEMA9_M1, hEMA21_M1, hRSI_M1mt, hATR_M1mt,
      hORB_EmaFast, hORB_EmaSlow
   };
   for(int i = 0; i < ArraySize(criticals); i++)
      if(criticals[i] == INVALID_HANDLE)
      { Alert("❌ QQ v7.0: Handle inválido #", i); return INIT_FAILED; }

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(10);
   trade.SetTypeFilling(ORDER_FILLING_FOK);

   g_dayStartBal = AccountInfoDouble(ACCOUNT_BALANCE);
   DetectCapitalMode();
   DailyReset();

   Print("✅ QQ Ultimate v7.0 | Balance: $",  DoubleToString(g_dayStartBal, 2),
         " | Modo: ",  CapModeStr(),
         " | Max trades/señal: ", g_maxMultiTrades,
         " | ORB Magic: ", InpMagicORB);
   return INIT_SUCCEEDED;
}

//====================================================================
//  OnDeinit
//====================================================================
void OnDeinit(const int reason)
{
   Comment("");
   int h[] = {
      hEMA50_D1, hEMA200_D1, hRSI_H1, hATR_H1,
      hBB_M5, hRSI_M5, hMFI_M5, hATR_M5,
      hFastEMA_M5, hSlowEMA_M5, hTrendEMA_M5,
      hFastEMA_M1, hSlowEMA_M1, hTrendEMA_M1, hRSI_M1, hATR_M1,
      hEMA21_H1, hEMA50_H1, hRSI_H4, hATR_H4, hEMA50_H4,
      hEMA9_M5, hEMA21_M5mt, hEMA9_M1, hEMA21_M1, hRSI_M1mt, hATR_M1mt,
      hORB_EmaFast, hORB_EmaSlow
   };
   for(int i = 0; i < ArraySize(h); i++)
      if(h[i] != INVALID_HANDLE) IndicatorRelease(h[i]);
   ORBDeleteDrawings();
}

//====================================================================
//  DETECCIÓN DE CAPITAL EN TIEMPO REAL
//  Llamado en cada tick — capital siempre actualizado.
//====================================================================
void DetectCapitalMode()
{
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);

   if(bal < 25.0)
   {
      g_capMode        = CAP_MICRO;    g_maxMultiTrades = 1;
      g_riskPct        = 1.0;
      g_dailyLossUSD   = bal * 0.06;  g_dailyProfitUSD = bal * 0.15;
      g_minProfitLock  = bal * 0.020; g_profitRetrace  = bal * 0.008;
      g_pyramidTrig1   = 2.0;         g_pyramidTrig2   = 4.0;
      g_pyramidLotMult = 0.50;        g_trailingMult   = 0.70;
      g_scalperRR      = 2.0;         g_maxTradesDay   = 3;
      g_maxBarsOpen    = 60;          g_maxNegBars     = 10;
      g_partialAt1R    = 0.40;        g_partialAt2R    = 0.40;
   }
   else if(bal < 60.0)
   {
      g_capMode        = CAP_SMALL;   g_maxMultiTrades = 2;
      g_riskPct        = 0.9;
      g_dailyLossUSD   = bal * 0.05;  g_dailyProfitUSD = bal * 0.12;
      g_minProfitLock  = bal * 0.015; g_profitRetrace  = bal * 0.006;
      g_pyramidTrig1   = 1.5;         g_pyramidTrig2   = 3.0;
      g_pyramidLotMult = 0.60;        g_trailingMult   = 0.80;
      g_scalperRR      = 1.9;         g_maxTradesDay   = 4;
      g_maxBarsOpen    = 80;          g_maxNegBars     = 15;
      g_partialAt1R    = 0.35;        g_partialAt2R    = 0.40;
   }
   else if(bal < 120.0)
   {
      g_capMode        = CAP_MEDIUM;  g_maxMultiTrades = 3;
      g_riskPct        = 0.80;
      g_dailyLossUSD   = bal * 0.045; g_dailyProfitUSD = bal * 0.11;
      g_minProfitLock  = bal * 0.014; g_profitRetrace  = bal * 0.006;
      g_pyramidTrig1   = 1.0;         g_pyramidTrig2   = 2.0;
      g_pyramidLotMult = 0.65;        g_trailingMult   = 0.90;
      g_scalperRR      = 1.8;         g_maxTradesDay   = 5;
      g_maxBarsOpen    = 100;         g_maxNegBars     = 18;
      g_partialAt1R    = 0.30;        g_partialAt2R    = 0.40;
   }
   else if(bal < 240.0)
   {
      g_capMode        = CAP_UPPER;   g_maxMultiTrades = 4;
      g_riskPct        = 0.75;
      g_dailyLossUSD   = bal * 0.040; g_dailyProfitUSD = bal * 0.10;
      g_minProfitLock  = bal * 0.012; g_profitRetrace  = bal * 0.005;
      g_pyramidTrig1   = 1.0;         g_pyramidTrig2   = 2.0;
      g_pyramidLotMult = 0.65;        g_trailingMult   = 0.95;
      g_scalperRR      = 1.8;         g_maxTradesDay   = 5;
      g_maxBarsOpen    = 110;         g_maxNegBars     = 20;
      g_partialAt1R    = 0.30;        g_partialAt2R    = 0.40;
   }
   else  // $240+
   {
      g_capMode        = CAP_STANDARD; g_maxMultiTrades = 5;
      g_riskPct        = 0.70;
      g_dailyLossUSD   = bal * 0.030; g_dailyProfitUSD = bal * 0.08;
      g_minProfitLock  = bal * 0.010; g_profitRetrace  = bal * 0.004;
      g_pyramidTrig1   = 1.0;         g_pyramidTrig2   = 2.0;
      g_pyramidLotMult = 0.70;        g_trailingMult   = 1.00;
      g_scalperRR      = 1.8;         g_maxTradesDay   = 6;
      g_maxBarsOpen    = 120;         g_maxNegBars     = 20;
      g_partialAt1R    = 0.30;        g_partialAt2R    = 0.40;
   }

   // Override de seguridad — límite manual siempre tiene prioridad
   double manualCap = AccountInfoDouble(ACCOUNT_BALANCE) * InpMaxDailyLossPct / 100.0;
   if(manualCap < g_dailyLossUSD) g_dailyLossUSD = manualCap;
}

string CapModeStr()
{
   if(g_capMode == CAP_MICRO)    return "MICRO(<$25)";
   if(g_capMode == CAP_SMALL)    return "SMALL($25-59)";
   if(g_capMode == CAP_MEDIUM)   return "MEDIUM($60-119)";
   if(g_capMode == CAP_UPPER)    return "UPPER($120-239)";
   return "STANDARD($240+)";
}

//====================================================================
//  OnTick — Orquestador principal
//====================================================================
void OnTick()
{
   DetectCapitalMode();   // Capital actualizado antes de cualquier decisión
   CheckDayReset();
   UpdateMarketBias();

   if(!g_dayInvalid)
   {
      BuildRange();
      ValidateRange();
      SearchBreakout();
      SearchRetestEntry();
      ManagePyramid();
      if(InpScalperOn) RunScalperStrategy();
   }

   ManageOpenTrades();     // 10 capas para trades QQ individuales

   if(InpLondonORBOn)
   {
      RunLondonORB();
      ManageORBTrades();
   }

   TrackClosedTrades();
   DrawPanel();
}

//====================================================================
//  RESET DIARIO
//====================================================================
void DailyReset()
{
   g_rangeHigh     = 0;  g_rangeLow    = 0; g_rangeBars     = 0;
   g_dayInvalid    = false; g_initialized = false;
   g_triggered     = false; g_breakoutTime = 0;
   g_sesgoUp       = false; g_sesgoDn  = false;
   g_h1Up          = false; g_h1Dn     = false;
   g_tradesToday   = 0;  g_peakProfit  = 0;
   g_pyramidLevel  = 0;  g_entry1Lot   = 0; g_entry1Price   = 0;
   g_partial1Done  = false; g_partial2Done = false; g_beMoved = false;
   g_openTradeCount= 0;
   g_winsToday     = 0;  g_lossesToday = 0;
   g_totalWon      = 0;  g_totalLost   = 0;
   g_mtGroupActive = false;
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
      DailyReset();
   }
}

//====================================================================
//  SESGO D1/H1
//====================================================================
void UpdateMarketBias()
{
   double e50[1], e200[1];
   if(CopyBuffer(hEMA50_D1, 0,0,1,e50)   > 0 &&
      CopyBuffer(hEMA200_D1,0,0,1,e200)  > 0)
   { g_sesgoUp = (e50[0] > e200[0]); g_sesgoDn = (e50[0] < e200[0]); }

   double rH1[1];
   if(CopyBuffer(hRSI_H1,   0,0,1,rH1)   > 0)
   { g_h1Up = (rH1[0] > 53.0); g_h1Dn = (rH1[0] < 47.0); }
}

//====================================================================
//  CONSTRUCCIÓN DE RANGO QQ
//====================================================================
void BuildRange()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   if(dt.hour != InpRangeHourStart) return;
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(g_rangeHigh == 0) g_rangeHigh = ask;
   if(g_rangeLow  == 0) g_rangeLow  = bid;
   g_rangeHigh = MathMax(g_rangeHigh, ask);
   g_rangeLow  = MathMin(g_rangeLow,  bid);
   g_rangeBars++;
}

void ValidateRange()
{
   if(g_initialized) return;
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   if(dt.hour != InpRangeHourEnd || dt.min != 0) return;
   double sz = g_rangeHigh - g_rangeLow;
   g_initialized = true;
   if(g_rangeBars < 25 || sz < InpRangeMinPts || sz > InpRangeMaxPts)
      Print("⚠️ Rango QQ inválido (sz=", sz, ") | Solo Scalper activo");
}

//====================================================================
//  LECTURA INDICADORES M5
//====================================================================
bool GetIndM5(double &bbU, double &bbD, double &bbM,
              double &rsi, double &mfi, double &atr)
{
   double bU[1],bD[1],bM[1],r[1],m[1],a[1];
   if(CopyBuffer(hBB_M5,  1,0,1,bU) <=0) return false;
   if(CopyBuffer(hBB_M5,  2,0,1,bD) <=0) return false;
   if(CopyBuffer(hBB_M5,  0,0,1,bM) <=0) return false;
   if(CopyBuffer(hRSI_M5, 0,0,1,r)  <=0) return false;
   if(CopyBuffer(hMFI_M5, 0,0,1,m)  <=0) return false;
   if(CopyBuffer(hATR_M5, 0,0,1,a)  <=0) return false;
   bbU=bU[0]; bbD=bD[0]; bbM=bM[0];
   rsi=r[0];  mfi=m[0];  atr=a[0];
   g_bbMid_cached = bM[0];
   g_atr_cached   = a[0];
   return true;
}

//====================================================================
//  FILTROS DE CALIDAD QQ (8 confirmaciones)
//====================================================================
bool FilterTrendD1(bool b)    { return b ? g_sesgoUp : g_sesgoDn; }
bool FilterMomentumH1(bool b) { if(g_capMode==CAP_MICRO) return true; return b?g_h1Up:g_h1Dn; }
bool FilterRSI(double r, bool b)   { return b?(r>48&&r<72):(r<52&&r>28); }
bool FilterBBT(double c,double m,bool b) { return b?(c>m):(c<m); }
bool FilterMFI(double f,bool b)    { if(g_capMode==CAP_MICRO) return true; return b?(f>48):(f<52); }
bool FilterGold(double r,bool b)   { return b?(r>47||g_sesgoUp):(!g_sesgoUp&&r<50); }
bool FilterATR(double a)           { return a >= ((g_capMode==CAP_MICRO)?0.5:0.8)*_Point*100; }
bool FilterSpread()
{
   double sp=(double)SymbolInfoInteger(_Symbol,SYMBOL_SPREAD);
   return sp <= (g_capMode==CAP_MICRO?30.0:InpMaxSpread);
}

int SignalScore(bool b,double c,double m,double r,double f,double a)
{
   int s=0;
   if(FilterTrendD1(b))     s++;
   if(FilterMomentumH1(b))  s++;
   if(FilterRSI(r,b))       s++;
   if(FilterBBT(c,m,b))     s++;
   if(FilterMFI(f,b))       s++;
   if(FilterGold(r,b))      s++;
   if(FilterATR(a))         s++;
   if(FilterSpread())       s++;
   return s;
}
int MinScore() { return (g_capMode<=CAP_SMALL)?5:6; }

//====================================================================
//  ★ SISTEMA DE VALIDACIÓN MTF — DISEÑO M1
//
//  Lógica de decisión en dos etapas:
//
//  ETAPA 1 – VETOS DUROS (bloqueo total si fallan)
//    • D1: EMA50 vs EMA200 — debe estar alineada con la dirección
//    • H1: EMA21 vs EMA50 Y RSI — si ambas están en contra, veto
//
//  ETAPA 2 – SCORE PONDERADO 0-100
//    • H4 (20%) : contexto macro intradiario — ATR y sesgo
//    • M5 (45%) : momentum pre-entrada — cruces EMA, RSI, velocidad
//    • M1 (35%) : confirmación de la vela de entrada — EMA, ATR, RSI
//
//  Solo si pasa los vetos Y el score ≥ InpMTF_ScoreThresh
//  se activa el sistema multi-trades.
//====================================================================
struct MTFResult
{
   bool   passed;    // true = activar multi-trade
   double score;     // 0-100
   string detail;    // para el log y el panel
};

MTFResult EvaluateMTF(bool isBuy)
{
   MTFResult res;
   res.passed = false;
   res.score  = 0;
   res.detail = "";

   //------------------------------------------------------------------
   //  ETAPA 1: VETOS DUROS
   //------------------------------------------------------------------

   // Veto D1: tendencia macro
   double e50d1[1], e200d1[1];
   if(CopyBuffer(hEMA50_D1, 0,0,1,e50d1)  <=0) return res;
   if(CopyBuffer(hEMA200_D1,0,0,1,e200d1) <=0) return res;
   bool d1Favor = isBuy ? (e50d1[0] > e200d1[0]) : (e50d1[0] < e200d1[0]);
   if(!d1Favor)
   {
      res.detail = "VETO D1";
      return res;   // Tendencia macro adversa — no continuar
   }

   // Veto H1: estructura intradiaria (solo bloquea si AMBAS condiciones están en contra)
   double e21h1[1], e50h1[1], rsiH1v[1];
   if(CopyBuffer(hEMA21_H1, 0,0,1,e21h1)  <=0) return res;
   if(CopyBuffer(hEMA50_H1, 0,0,1,e50h1)  <=0) return res;
   if(CopyBuffer(hRSI_H1,   0,0,1,rsiH1v) <=0) return res;
   bool h1EmaAdverse = isBuy ? (e21h1[0] < e50h1[0]) : (e21h1[0] > e50h1[0]);
   bool h1RsiAdverse = isBuy ? (rsiH1v[0] < 45.0)    : (rsiH1v[0] > 55.0);
   if(h1EmaAdverse && h1RsiAdverse)
   {
      res.detail = "VETO H1";
      return res;   // Estructura H1 totalmente adversa — no continuar
   }

   //------------------------------------------------------------------
   //  ETAPA 2: SCORE PONDERADO
   //------------------------------------------------------------------

   double weightedSum = 0;
   double totalWeight = 100.0;   // H4:20 + M5:45 + M1:35

   // ── H4 — Contexto macro intradiario (peso 20) ──────────────────
   {
      double score_h4 = 0;

      double rsiH4[1], atrH4[3], e50h4[1];
      bool ok  = (CopyBuffer(hRSI_H4,  0,0,1,rsiH4) > 0);
      bool ok2 = (CopyBuffer(hATR_H4,  0,0,3,atrH4) > 0);
      bool ok3 = (CopyBuffer(hEMA50_H4,0,0,1,e50h4) > 0);

      // Criterio 1: RSI H4 en zona momentum (40 pts de H4)
      if(ok)
      {
         bool rsiOK = isBuy ? (rsiH4[0] > 50.0 && rsiH4[0] < 76.0)
                            : (rsiH4[0] < 50.0 && rsiH4[0] > 24.0);
         if(rsiOK) score_h4 += 40;
      }

      // Criterio 2: ATR H4 no en colapso (mercado activo) (30 pts de H4)
      if(ok2)
      {
         ArraySetAsSeries(atrH4, true);
         double atrAvg = (atrH4[0]+atrH4[1]+atrH4[2])/3.0;
         if(atrH4[0] >= atrAvg * 0.80) score_h4 += 30;
      }

      // Criterio 3: Precio sobre/bajo EMA50 H4 (30 pts de H4)
      double closeH4 = iClose(_Symbol, PERIOD_H4, 0);
      if(ok3)
      {
         bool priceOK = isBuy ? (closeH4 > e50h4[0]) : (closeH4 < e50h4[0]);
         if(priceOK) score_h4 += 30;
      }

      weightedSum += 20.0 * (score_h4 / 100.0);
      res.detail += "H4:" + DoubleToString(score_h4, 0) + " ";
   }

   // ── M5 — Momentum pre-entrada (peso 45) ─────────────────────────
   {
      double score_m5 = 0;

      double e9m5[3], e21m5[3], rsiM5v[1], atrM5v[1];
      ArraySetAsSeries(e9m5,  true);
      ArraySetAsSeries(e21m5, true);
      bool ok1 = (CopyBuffer(hEMA9_M5,    0,0,3,e9m5)  > 0);
      bool ok2 = (CopyBuffer(hEMA21_M5mt, 0,0,3,e21m5) > 0);
      bool ok3 = (CopyBuffer(hRSI_M5,     0,0,1,rsiM5v)> 0);
      bool ok4 = (CopyBuffer(hATR_M5,     0,0,1,atrM5v)> 0);

      // Criterio 1: Cruce reciente EMA9/EMA21 en M5 (máx 2 barras atrás) (35 pts)
      if(ok1 && ok2)
      {
         bool crossNow = isBuy  ? (e9m5[0]>e21m5[0] && e9m5[1]<=e21m5[1])
                                : (e9m5[0]<e21m5[0] && e9m5[1]>=e21m5[1]);
         bool crossPrev= isBuy  ? (e9m5[1]>e21m5[1] && e9m5[2]<=e21m5[2])
                                : (e9m5[1]<e21m5[1] && e9m5[2]>=e21m5[2]);
         bool aligned  = isBuy  ? (e9m5[0] > e21m5[0]) : (e9m5[0] < e21m5[0]);
         if(crossNow || crossPrev)      score_m5 += 35;
         else if(aligned)               score_m5 += 15;
      }

      // Criterio 2: RSI M5 en zona correcta y sin sobreextensión (30 pts)
      if(ok3)
      {
         bool rsiOK      = isBuy ? (rsiM5v[0]>52 && rsiM5v[0]<74)
                                 : (rsiM5v[0]<48 && rsiM5v[0]>26);
         if(rsiOK) score_m5 += 30;
      }

      // Criterio 3: EMA9 separada de EMA21 (velocidad de precio) (20 pts)
      if(ok1 && ok2)
      {
         double sep = MathAbs(e9m5[0] - e21m5[0]);
         double minSep = 0.15 * _Point * 10;
         if(sep >= minSep) score_m5 += 20;
      }

      // Criterio 4: ATR M5 por encima de media reciente (15 pts)
      if(ok4)
      {
         double atrM5_3[3];
         ArraySetAsSeries(atrM5_3, true);
         if(CopyBuffer(hATR_M5, 0,0,3,atrM5_3) > 0)
         {
            double avg3 = (atrM5_3[0]+atrM5_3[1]+atrM5_3[2])/3.0;
            if(atrM5_3[0] >= avg3 * 0.90) score_m5 += 15;
         }
      }

      score_m5 = MathMin(score_m5, 100.0);
      weightedSum += 45.0 * (score_m5 / 100.0);
      res.detail += "M5:" + DoubleToString(score_m5, 0) + " ";
   }

   // ── M1 — Confirmación de vela de entrada (peso 35) ───────────────
   {
      double score_m1 = 0;

      double e9m1[2], e21m1[2], rsiM1v[1], atrM1v[2];
      ArraySetAsSeries(e9m1,  true);
      ArraySetAsSeries(e21m1, true);
      ArraySetAsSeries(atrM1v,true);
      bool ok1 = (CopyBuffer(hEMA9_M1,   0,0,2,e9m1)  > 0);
      bool ok2 = (CopyBuffer(hEMA21_M1,  0,0,2,e21m1) > 0);
      bool ok3 = (CopyBuffer(hRSI_M1mt,  0,0,1,rsiM1v)> 0);
      bool ok4 = (CopyBuffer(hATR_M1mt,  0,0,2,atrM1v)> 0);

      // Criterio 1: EMA9 > EMA21 en M1 (alineadas) (30 pts)
      if(ok1 && ok2)
      {
         bool align = isBuy ? (e9m1[0]>e21m1[0]) : (e9m1[0]<e21m1[0]);
         if(align) score_m1 += 30;
      }

      // Criterio 2: Cruce EMA9/21 en esta misma barra M1 (25 pts extra)
      if(ok1 && ok2)
      {
         bool crossM1 = isBuy ? (e9m1[0]>e21m1[0] && e9m1[1]<=e21m1[1])
                              : (e9m1[0]<e21m1[0] && e9m1[1]>=e21m1[1]);
         if(crossM1) score_m1 += 25;
      }

      // Criterio 3: RSI M1 con momentum (25 pts)
      if(ok3)
      {
         bool rsiM1ok = isBuy ? (rsiM1v[0]>52 && rsiM1v[0]<76)
                              : (rsiM1v[0]<48 && rsiM1v[0]>24);
         if(rsiM1ok) score_m1 += 25;
      }

      // Criterio 4: ATR M1 creciente respecto a barra anterior (volatilidad real) (20 pts)
      if(ok4)
      {
         if(atrM1v[0] >= atrM1v[1] * 0.95) score_m1 += 20;
      }

      score_m1 = MathMin(score_m1, 100.0);
      weightedSum += 35.0 * (score_m1 / 100.0);
      res.detail += "M1:" + DoubleToString(score_m1, 0);
   }

   //------------------------------------------------------------------
   //  Resultado final
   //------------------------------------------------------------------
   res.score  = MathMin(weightedSum, 100.0);
   res.passed = (res.score >= InpMTF_ScoreThresh);
   return res;
}

//====================================================================
//  ★ ACTIVACIÓN DEL GRUPO MULTI-TRADES
//  Se llama inmediatamente después de abrir el trade maestro.
//  Todos los trades del grupo reciben el MISMO SL y TP que el maestro.
//  La ventana de 4 segundos controla que no se abran tarde.
//====================================================================
void TryActivateMultiTrade(bool isBuy, ulong masterTicket,
                            double entry, double sl, double tp, double atr)
{
   if(!InpMultiTradeOn) return;
   if(g_maxMultiTrades <= 1) return;
   if(g_mtGroupActive)       return;

   MTFResult mtf = EvaluateMTF(isBuy);
   if(!mtf.passed)
   {
      Print("🔍 MTF: ", DoubleToString(mtf.score, 1), "% < umbral ",
            InpMTF_ScoreThresh, "% | ", mtf.detail, " → Sin multi-trade");
      return;
   }

   // Inicializar grupo
   ArrayInitialize(g_mtGroup.tickets, 0);
   g_mtGroup.tickets[0] = masterTicket;
   g_mtGroup.count      = 1;
   g_mtGroup.isBuy      = isBuy;
   g_mtGroup.sharedSL   = sl;
   g_mtGroup.sharedTP   = tp;
   g_mtGroup.baseLot    = CalcLot(MathAbs(entry - sl), 1.0);
   g_mtGroup.openTime   = TimeCurrent();
   g_mtGroup.mtfScore   = mtf.score;

   datetime signalTime  = TimeCurrent();
   int opened           = 0;

   for(int i = 1; i < g_maxMultiTrades; i++)
   {
      // Verificar ventana temporal
      long elapsed = (long)(TimeCurrent() - signalTime);
      if(elapsed > (long)InpMTF_WindowSec)
      {
         Print("⏰ Ventana MTF cerrada (", elapsed, "s) en trade #", i+1,
               " — grupo parcial con ", opened, " trades adicionales");
         break;
      }

      // Lotaje igual al trade maestro para todos (mismo riesgo, mismo TP)
      double lot = CalcLot(MathAbs(entry - sl), 1.0);
      if(lot <= 0) break;

      bool ok = false;
      if(isBuy)
         ok = trade.Buy(lot,  _Symbol, SymbolInfoDouble(_Symbol, SYMBOL_ASK),  sl, tp);
      else
         ok = trade.Sell(lot, _Symbol, SymbolInfoDouble(_Symbol, SYMBOL_BID), sl, tp);

      if(ok)
      {
         ulong t = trade.ResultOrder();
         g_mtGroup.tickets[i] = t;
         g_mtGroup.count++;
         g_tradesToday++;
         RegisterTrade(t);
         opened++;
         Print("📊 MT trade #", i+1, " | Lot=", lot,
               " SL=", DoubleToString(sl, 2), " TP=", DoubleToString(tp, 2));
      }
      else
         Print("⚠️ MT trade #", i+1, " error: ", trade.ResultRetcodeDescription());
   }

   if(opened > 0)
   {
      g_mtGroupActive = true;
      Print("✅ Grupo MT activo | Trades totales: ", g_mtGroup.count,
            " | Score: ", DoubleToString(mtf.score, 1), "% | ", mtf.detail);
   }
}

//====================================================================
//  CÁLCULO DE LOTE
//====================================================================
double CalcLot(double slPts, double riskMult)
{
   double riskPct = g_riskPct * riskMult;
   double bal     = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk    = bal * (riskPct / 100.0);
   double tv      = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double ts      = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(slPts<=0||tv<=0||ts<=0) return NormLot(0.01);
   double slMoney = slPts / ts * tv;
   double lot     = (slMoney>0) ? risk/slMoney : 0.01;
   if(g_capMode == CAP_MICRO)
      lot = MathMin(lot, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)*2.0);
   return NormLot(lot);
}

void CalcSLTP(bool isBuy, double entry, double atr,
              double &sl, double &tp, double rrMult=1.0)
{
   double slD = atr * InpATR_SL_Mult;
   double tpD = atr * InpATR_TP_Mult * rrMult;
   if(g_capMode==CAP_MICRO) slD *= 1.15;
   sl = isBuy ? entry-slD : entry+slD;
   tp = isBuy ? entry+tpD : entry-tpD;
}

//====================================================================
//  BREAKOUT QQ
//====================================================================
void SearchBreakout()
{
   if(g_triggered || !g_initialized) return;
   if(g_rangeHigh==0||g_rangeLow==0) return;
   if(g_tradesToday >= g_maxTradesDay) return;
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   if(dt.hour < InpRangeHourEnd || dt.hour >= InpBreakoutHourEnd) return;
   double dayPnL = AccountInfoDouble(ACCOUNT_BALANCE) - g_dayStartBal;
   if(dayPnL<-g_dailyLossUSD || dayPnL>g_dailyProfitUSD) return;

   double close=iClose(_Symbol,PERIOD_M5,0);
   double bbU,bbD,bbM,rsi,mfi,atr;
   if(!GetIndM5(bbU,bbD,bbM,rsi,mfi,atr)) return;
   double off = InpBreakoutOffset*_Point*10;

   if(close>(g_rangeHigh+off))
   {
      if(SignalScore(true,close,bbM,rsi,mfi,atr) < MinScore()) return;
      double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK), sl, tp;
      CalcSLTP(true,ask,atr,sl,tp);
      double lot=CalcLot(ask-sl,1.0);
      if(trade.Buy(lot,_Symbol,ask,sl,tp))
      {
         ulong t=trade.ResultOrder();
         g_triggered=true; g_tradesToday++;
         g_entry1Lot=lot; g_entry1Price=ask;
         g_pyramidLevel=0; g_partial1Done=false;
         g_partial2Done=false; g_beMoved=false;
         g_breakoutTime=TimeCurrent();
         RegisterTrade(t);
         Print("🟢 BREAKOUT LONG @",ask," SL:",sl," TP:",tp," Lot:",lot);
         TryActivateMultiTrade(true, t, ask, sl, tp, atr);
      }
   }
   else if(close<(g_rangeLow-off))
   {
      if(SignalScore(false,close,bbM,rsi,mfi,atr) < MinScore()) return;
      double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID), sl, tp;
      CalcSLTP(false,bid,atr,sl,tp);
      double lot=CalcLot(sl-bid,1.0);
      if(trade.Sell(lot,_Symbol,bid,sl,tp))
      {
         ulong t=trade.ResultOrder();
         g_triggered=true; g_tradesToday++;
         g_entry1Lot=lot; g_entry1Price=bid;
         g_pyramidLevel=0; g_partial1Done=false;
         g_partial2Done=false; g_beMoved=false;
         g_breakoutTime=TimeCurrent();
         RegisterTrade(t);
         Print("🔴 BREAKOUT SHORT @",bid," SL:",sl," TP:",tp," Lot:",lot);
         TryActivateMultiTrade(false, t, bid, sl, tp, atr);
      }
   }
}

//====================================================================
//  RETEST QQ
//====================================================================
void SearchRetestEntry()
{
   if(!g_triggered || g_tradesToday>=g_maxTradesDay) return;
   if(CountOpenPositions()>0) return;
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   if(dt.hour>=InpBreakoutHourEnd) return;
   if(g_breakoutTime>0 &&
      (int)((TimeCurrent()-g_breakoutTime)/PeriodSeconds(PERIOD_M5))>30) return;

   double close=iClose(_Symbol,PERIOD_M5,0);
   double bbU,bbD,bbM,rsi,mfi,atr;
   if(!GetIndM5(bbU,bbD,bbM,rsi,mfi,atr)) return;
   double zone=0.50*_Point*10;

   if(g_sesgoUp && g_h1Up &&
      close<=g_rangeHigh+zone && close>=g_rangeHigh-zone)
   {
      if(SignalScore(true,close,bbM,rsi,mfi,atr) < MinScore()) return;
      double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK), sl, tp;
      CalcSLTP(true,ask,atr,sl,tp);
      double lot=CalcLot(ask-sl,0.70);
      if(trade.Buy(lot,_Symbol,ask,sl,tp))
      {
         ulong t=trade.ResultOrder();
         g_tradesToday++;
         RegisterTrade(t);
         Print("🟢 RETEST LONG @",ask," Lot:",lot);
         TryActivateMultiTrade(true, t, ask, sl, tp, atr);
      }
   }
   else if(g_sesgoDn && g_h1Dn &&
           close>=g_rangeLow-zone && close<=g_rangeLow+zone)
   {
      if(SignalScore(false,close,bbM,rsi,mfi,atr) < MinScore()) return;
      double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID), sl, tp;
      CalcSLTP(false,bid,atr,sl,tp);
      double lot=CalcLot(sl-bid,0.70);
      if(trade.Sell(lot,_Symbol,bid,sl,tp))
      {
         ulong t=trade.ResultOrder();
         g_tradesToday++;
         RegisterTrade(t);
         Print("🔴 RETEST SHORT @",bid," Lot:",lot);
         TryActivateMultiTrade(false, t, bid, sl, tp, atr);
      }
   }
}

//====================================================================
//  PIRAMIDAL QQ
//====================================================================
void ManagePyramid()
{
   if(!InpPyramidOn||!g_triggered) return;
   if(g_pyramidLevel>=InpPyramidLevels||g_tradesToday>=g_maxTradesDay) return;
   if(g_capMode==CAP_MICRO) return;

   ulong mt=0; bool mIsBuy=false; double mSL=0,mP=0;
   for(int i=0;i<PositionsTotal();i++)
   {
      ulong t=PositionGetTicket(i);
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      mt=t; mIsBuy=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
      mSL=PositionGetDouble(POSITION_SL); mP=PositionGetDouble(POSITION_PRICE_OPEN);
      break;
   }
   if(!mt) return;

   double trig=(g_pyramidLevel==0)?g_pyramidTrig1*_Point*10:g_pyramidTrig2*_Point*10;
   double cur =mIsBuy?SymbolInfoDouble(_Symbol,SYMBOL_BID):SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double mov =mIsBuy?(cur-mP):(mP-cur);
   if(mov<trig) return;

   double bbU,bbD,bbM,rsi,mfi,atr;
   if(!GetIndM5(bbU,bbD,bbM,rsi,mfi,atr)) return;
   double pyrLot=NormLot(g_entry1Lot*MathPow(g_pyramidLotMult,g_pyramidLevel+1));
   double sl,tp;

   if(mIsBuy)
   {
      double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      sl=mP; tp=ask+atr*InpATR_TP_Mult*(g_capMode==CAP_SMALL?2.0:1.5);
      if(trade.Buy(pyrLot,_Symbol,ask,sl,tp))
      { g_pyramidLevel++; g_tradesToday++; RegisterTrade(trade.ResultOrder());
        Print("📈 PIRÁMIDE L",g_pyramidLevel," @",ask," Lot:",pyrLot); }
   }
   else
   {
      double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
      sl=mP; tp=bid-atr*InpATR_TP_Mult*(g_capMode==CAP_SMALL?2.0:1.5);
      if(trade.Sell(pyrLot,_Symbol,bid,sl,tp))
      { g_pyramidLevel++; g_tradesToday++; RegisterTrade(trade.ResultOrder());
        Print("📉 PIRÁMIDE L",g_pyramidLevel," @",bid," Lot:",pyrLot); }
   }
}

//====================================================================
//  EMA SCALPER QQ
//====================================================================
void RunScalperStrategy()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   if(dt.hour<InpScalperHourStart||dt.hour>=InpScalperHourEnd) return;
   if(g_tradesToday>=g_maxTradesDay||CountOpenPositions()>0||!FilterSpread()) return;
   double dayPnL=AccountInfoDouble(ACCOUNT_BALANCE)-g_dayStartBal;
   if(dayPnL<-g_dailyLossUSD||dayPnL>g_dailyProfitUSD) return;
   datetime bar=iTime(_Symbol,PERIOD_M5,0);
   if(bar==g_lastBarM5) return;

   double fM5[3],sM5[3],tM5[3];
   ArraySetAsSeries(fM5,true); ArraySetAsSeries(sM5,true); ArraySetAsSeries(tM5,true);
   if(CopyBuffer(hFastEMA_M5, 0,0,3,fM5) <=0) return;
   if(CopyBuffer(hSlowEMA_M5, 0,0,3,sM5) <=0) return;
   if(CopyBuffer(hTrendEMA_M5,0,0,3,tM5) <=0) return;

   double fM1[2],sM1[2],tM1[2];
   ArraySetAsSeries(fM1,true); ArraySetAsSeries(sM1,true); ArraySetAsSeries(tM1,true);
   if(CopyBuffer(hFastEMA_M1, 0,0,2,fM1) <=0) return;
   if(CopyBuffer(hSlowEMA_M1, 0,0,2,sM1) <=0) return;
   if(CopyBuffer(hTrendEMA_M1,0,0,2,tM1) <=0) return;

   double bbU,bbD,bbM,rsi,mfi,atr;
   if(!GetIndM5(bbU,bbD,bbM,rsi,mfi,atr)||atr<=0) return;
   double close=iClose(_Symbol,PERIOD_M5,0);

   bool cUpM5=(fM5[0]>sM5[0])&&(fM5[1]<=sM5[1]);
   bool cDnM5=(fM5[0]<sM5[0])&&(fM5[1]>=sM5[1]);
   bool tUpM5=(fM5[0]>tM5[0]), tDnM5=(fM5[0]<tM5[0]);
   bool aUpM1=(fM1[0]>sM1[0]&&fM1[0]>tM1[0]);
   bool aDnM1=(fM1[0]<sM1[0]&&fM1[0]<tM1[0]);

   if(cUpM5&&tUpM5&&aUpM1 && SignalScore(true,close,bbM,rsi,mfi,atr)>=MinScore())
   {
      g_lastBarM5=bar;
      double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK), sl,tp;
      CalcSLTP(true,ask,atr,sl,tp,g_scalperRR/InpRR);
      double lot=CalcLot(ask-sl,0.80);
      if(trade.Buy(lot,_Symbol,ask,sl,tp))
      {
         ulong t=trade.ResultOrder();
         g_tradesToday++; RegisterTrade(t);
         Print("⚡ SCALPER BUY @",ask," Lot:",lot);
         TryActivateMultiTrade(true, t, ask, sl, tp, atr);
      }
   }
   else if(cDnM5&&tDnM5&&aDnM1 && SignalScore(false,close,bbM,rsi,mfi,atr)>=MinScore())
   {
      g_lastBarM5=bar;
      double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID), sl,tp;
      CalcSLTP(false,bid,atr,sl,tp,g_scalperRR/InpRR);
      double lot=CalcLot(sl-bid,0.80);
      if(trade.Sell(lot,_Symbol,bid,sl,tp))
      {
         ulong t=trade.ResultOrder();
         g_tradesToday++; RegisterTrade(t);
         Print("⚡ SCALPER SELL @",bid," Lot:",lot);
         TryActivateMultiTrade(false, t, bid, sl, tp, atr);
      }
   }
}

//====================================================================
//  GESTIÓN QQ — SISTEMA 10 CAPAS
//====================================================================
void ManageOpenTrades()
{
   double dayPnL=AccountInfoDouble(ACCOUNT_BALANCE)-g_dayStartBal;

   // Capa 0: Stop/Target diario global
   if(dayPnL>=g_dailyProfitUSD)
   { CloseAllMagic(); CloseAllORB("Target diario"); g_dayInvalid=true;
     Print("🎯 TARGET DIARIO $",dayPnL); return; }
   if(dayPnL<=-g_dailyLossUSD)
   { CloseAllMagic(); CloseAllORB("Stop diario"); g_dayInvalid=true;
     Print("🛑 STOP DIARIO $",dayPnL); return; }

   double rsiM5[1],fM5[1],sM5[1],tM5[1],atrM5[1];
   bool hR=(CopyBuffer(hRSI_M5,    0,0,1,rsiM5)>0);
   bool hE=(CopyBuffer(hFastEMA_M5,0,0,1,fM5)  >0 &&
            CopyBuffer(hSlowEMA_M5,0,0,1,sM5)  >0 &&
            CopyBuffer(hTrendEMA_M5,0,0,1,tM5) >0);
   bool hA=(CopyBuffer(hATR_M5,    0,0,1,atrM5)>0);
   if(hA&&atrM5[0]>0) g_atr_cached=atrM5[0];

   double totalPnL=0; int count=0;

   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;

      double profit   =PositionGetDouble(POSITION_PROFIT);
      double openP    =PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL    =PositionGetDouble(POSITION_SL);
      double curTP    =PositionGetDouble(POSITION_TP);
      double vol      =PositionGetDouble(POSITION_VOLUME);
      bool   isBuy    =(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
      datetime tOpen  =(datetime)PositionGetInteger(POSITION_TIME);
      double curP     =isBuy?SymbolInfoDouble(_Symbol,SYMBOL_BID)
                            :SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      totalPnL+=profit; count++;

      // Capa 1: Tiempo + ganancia
      int barsM1=(int)((TimeCurrent()-tOpen)/PeriodSeconds(PERIOD_M1));
      if(barsM1>=g_maxBarsOpen&&profit>0)
      { trade.PositionClose(ticket); RemoveTradeTracker(ticket);
        Print("⏱️ Cierre tiempo(",barsM1,"b): $",profit); continue; }

      // Capa 2: Tendencia+RSI adversos en pérdida
      if(InpSmartExitOn&&profit<0)
      {
         bool tW=hE&&(isBuy?(curP<tM5[0]):(curP>tM5[0]));
         bool mW=hR&&(isBuy?(rsiM5[0]<38):(rsiM5[0]>62));
         if(tW&&mW)
         { trade.PositionClose(ticket); RemoveTradeTracker(ticket);
           Print("🧠 Cierre inteligente pérdida: $",profit); continue; }
      }

      // Capa 3: Pérdida de momentum en ganancia
      if(InpMomentumExitOn&&profit>0&&hE)
      {
         bool mL=isBuy?(fM5[0]<sM5[0]):(fM5[0]>sM5[0]);
         if(mL)
         { trade.PositionClose(ticket); RemoveTradeTracker(ticket);
           Print("⚡ Momentum perdido: $",profit); continue; }
      }

      // Capa 4: BB Mid adverso en ganancia
      if(profit>0&&g_bbMid_cached>0)
      {
         bool adv=isBuy?(curP<g_bbMid_cached&&openP>g_bbMid_cached)
                       :(curP>g_bbMid_cached&&openP<g_bbMid_cached);
         if(adv)
         { trade.PositionClose(ticket); RemoveTradeTracker(ticket);
           Print("🔀 BB Mid adverso: $",profit); continue; }
      }

      // Capa 5: Barras negativas + tendencia adversa
      if(profit<0&&g_maxNegBars>0)
      {
         int idx=FindTradeTracker(ticket);
         if(idx>=0)
         {
            int bM5n=(int)((TimeCurrent()-g_openTrades[idx].openTime)/PeriodSeconds(PERIOD_M5));
            if(bM5n>=g_maxNegBars&&hE)
            {
               bool tA=isBuy?(fM5[0]<tM5[0]):(fM5[0]>tM5[0]);
               if(tA)
               { trade.PositionClose(ticket); RemoveTradeTracker(ticket);
                 Print("⏰ Neg prolongado(",bM5n,"b): $",profit); continue; }
            }
         }
      }

      // Capa 6: Cierre parcial progresivo
      if(InpPartialClose&&ticket==GetOldestMagicTicket())
      {
         double slD=MathAbs(openP-curSL);
         double mR=(slD>0)?MathAbs(curP-openP)/slD:0;
         if(!g_partial1Done&&mR>=1.0)
         {
            double cv=NormLot(vol*g_partialAt1R);
            double minV=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
            if(cv>=minV) trade.PositionClosePartial(ticket,cv);
            if(!g_beMoved)
            { double nSL=isBuy?openP+_Point:openP-_Point;
              trade.PositionModify(ticket,nSL,curTP); g_beMoved=true; }
            g_partial1Done=true;
            Print("💰 Parcial 1 @1R | BE activado");
         }
         if(!g_partial2Done&&mR>=2.0&&g_partial1Done)
         {
            double cv2=NormLot(vol*g_partialAt2R);
            double minV=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
            if(cv2>=minV) trade.PositionClosePartial(ticket,cv2);
            g_partial2Done=true;
            Print("💰 Parcial 2 @2R");
         }
      }

      // Capa 7: Trailing Stop ATR
      if(InpTrailingOn) ApplyTrailing(ticket,isBuy);

      // Capa 8: Break-even anticipado a 0.5R con señal de reversión
      if(!g_beMoved&&hE&&hR&&curSL>0)
      {
         double slD=MathAbs(openP-curSL);
         double mR=(slD>0)?MathAbs(curP-openP)/slD:0;
         bool rev=isBuy?(fM5[0]<sM5[0]&&rsiM5[0]<50):(fM5[0]>sM5[0]&&rsiM5[0]>50);
         if(mR>=0.5&&rev)
         {
            double nSL=isBuy?openP+_Point:openP-_Point;
            if((isBuy&&nSL>curSL)||(!isBuy&&(nSL<curSL||curSL==0)))
            { trade.PositionModify(ticket,nSL,curTP); g_beMoved=true;
              Print("🛡️ BE anticipado @0.5R"); }
         }
      }

      // Capa 9: RSI extremo en ganancia
      if(InpSmartExitOn&&profit>0&&hR)
      {
         bool ext=isBuy?(rsiM5[0]>78):(rsiM5[0]<22);
         if(ext)
         { trade.PositionClose(ticket); RemoveTradeTracker(ticket);
           Print("🔥 RSI extremo: $",profit); continue; }
      }
   }

   // Capa 10: Peak Profit Lock global
   if(count>0)
   {
      if(totalPnL>g_peakProfit) g_peakProfit=totalPnL;
      if(g_peakProfit>=g_minProfitLock&&totalPnL<(g_peakProfit-g_profitRetrace))
      { CloseAllMagic(); Print("💰 Peak Lock: Peak=$",g_peakProfit," PnL=$",totalPnL); }
   }
   else g_peakProfit=0;
}

//====================================================================
//  TRAILING STOP ATR
//====================================================================
void ApplyTrailing(ulong ticket, bool isBuy)
{
   if(!PositionSelectByTicket(ticket)) return;
   double cSL=PositionGetDouble(POSITION_SL);
   double cTP=PositionGetDouble(POSITION_TP);
   double cP =PositionGetDouble(POSITION_PRICE_CURRENT);
   double oP =PositionGetDouble(POSITION_PRICE_OPEN);
   double atr=(g_atr_cached>0)?g_atr_cached:10*_Point*10;
   double tr =atr*g_trailingMult;

   if(isBuy)
   { if(cP<=oP) return;
     double nSL=cP-tr;
     if(nSL>cSL+_Point&&nSL>=oP-_Point) trade.PositionModify(ticket,nSL,cTP); }
   else
   { if(cP>=oP) return;
     double nSL=cP+tr;
     if((nSL<cSL-_Point||cSL==0)&&nSL<=oP+_Point) trade.PositionModify(ticket,nSL,cTP); }
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

   if(dt.hour==InpORBRangeHStart&&dt.min>=0&&dt.min<=59)
   {
      double hi=iHigh(_Symbol,PERIOD_M1,1), lo=iLow(_Symbol,PERIOD_M1,1);
      if(hi>g_orbRangeHigh) g_orbRangeHigh=hi;
      if(lo<g_orbRangeLow)  g_orbRangeLow=lo;
      g_orbRangeBars++;
   }

   if(dt.hour==InpORBTradeHStart&&dt.min==0&&!g_orbRangeBuilt&&g_orbRangeBars>0)
   {
      double sz=g_orbRangeHigh-g_orbRangeLow;
      if(g_orbRangeBars<InpORBMinBars||sz<InpORBRangeMinPts||sz>InpORBRangeMaxPts)
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

   if(closeM1>g_orbRangeHigh+InpORBBreakBuf&&ef[0]>es[0]&&(g_sesgoUp||!g_sesgoDn))
   {
      double en=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      double sl=g_orbRangeLow-InpORBSLBuffer;
      double risk=en-sl; if(risk<=0) return;
      double tp=en+risk*InpORBRR;
      double lots=ORBCalcLots(risk); if(lots<=0) return;
      trade.SetExpertMagicNumber(InpMagicORB);
      if(trade.Buy(lots,_Symbol,en,sl,tp,"S2_LondonORB"))
      { g_orbTradeTriggered=true; g_orbTradeOpenTime=TimeCurrent();
        Print("✅ ORB LONG @",en," SL=",sl," TP=",tp," lots=",lots);
        ORBDrawEntryLines(en,sl,tp,true); }
      trade.SetExpertMagicNumber(InpMagic);
   }
   else if(closeM1<g_orbRangeLow-InpORBBreakBuf&&ef[0]<es[0]&&(g_sesgoDn||!g_sesgoUp))
   {
      double en=SymbolInfoDouble(_Symbol,SYMBOL_BID);
      double sl=g_orbRangeHigh+InpORBSLBuffer;
      double risk=sl-en; if(risk<=0) return;
      double tp=en-risk*InpORBRR;
      double lots=ORBCalcLots(risk); if(lots<=0) return;
      trade.SetExpertMagicNumber(InpMagicORB);
      if(trade.Sell(lots,_Symbol,en,sl,tp,"S2_LondonORB"))
      { g_orbTradeTriggered=true; g_orbTradeOpenTime=TimeCurrent();
        Print("✅ ORB SHORT @",en," SL=",sl," TP=",tp," lots=",lots);
        ORBDrawEntryLines(en,sl,tp,false); }
      trade.SetExpertMagicNumber(InpMagic);
   }
}

void ManageORBTrades()
{
   if(!g_orbTradeTriggered) return;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i);
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=InpMagicORB) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;

      double profit =PositionGetDouble(POSITION_PROFIT);
      double cSL    =PositionGetDouble(POSITION_SL);
      double cTP    =PositionGetDouble(POSITION_TP);
      double oP     =PositionGetDouble(POSITION_PRICE_OPEN);
      double vol    =PositionGetDouble(POSITION_VOLUME);
      bool   isBuy  =(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
      double cP     =isBuy?SymbolInfoDouble(_Symbol,SYMBOL_BID)
                          :SymbolInfoDouble(_Symbol,SYMBOL_ASK);

      if(g_orbTradeOpenTime>0&&
         (int)((TimeCurrent()-g_orbTradeOpenTime)/60)>=InpORBMaxMinutes)
      { trade.SetExpertMagicNumber(InpMagicORB);
        trade.PositionClose(t);
        trade.SetExpertMagicNumber(InpMagic);
        Print("ORB: Cierre tiempo: $",profit); continue; }

      if(InpTrailingOn&&g_atr_cached>0&&profit>0)
      {
         double tr=g_atr_cached*g_trailingMult;
         trade.SetExpertMagicNumber(InpMagicORB);
         if(isBuy){ double nSL=cP-tr; if(nSL>cSL+_Point&&nSL>=oP-_Point) trade.PositionModify(t,nSL,cTP); }
         else     { double nSL=cP+tr; if((nSL<cSL-_Point||cSL==0)&&nSL<=oP+_Point) trade.PositionModify(t,nSL,cTP); }
         trade.SetExpertMagicNumber(InpMagic);
      }

      if(InpPartialClose&&g_capMode>=CAP_MEDIUM&&cSL>0)
      {
         double slD=MathAbs(oP-cSL);
         double mR=(slD>0)?MathAbs(cP-oP)/slD:0;
         if(mR>=1.0)
         {
            double minV=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
            double hV=NormLot(vol*0.50);
            if(hV>=minV)
            {
               static datetime lPB=0; datetime cb=iTime(_Symbol,PERIOD_M5,0);
               if(cb!=lPB)
               {
                  trade.SetExpertMagicNumber(InpMagicORB);
                  trade.PositionClosePartial(t,hV);
                  double nSL=isBuy?oP+_Point:oP-_Point;
                  if((isBuy&&nSL>cSL)||(!isBuy&&nSL<cSL)) trade.PositionModify(t,nSL,cTP);
                  trade.SetExpertMagicNumber(InpMagic);
                  lPB=cb; Print("💰 ORB Parcial 50% @1R | BE: $",profit);
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
   double pv=tv/ts*_Point;
   if(pv<=0||riskPts<=0) return 0;
   double lots=ra/((riskPts/_Point)*pv);
   if(g_capMode==CAP_MICRO) lots=MathMin(lots,SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN)*2.0);
   return NormLot(lots);
}

void CloseAllORB(string reason)
{
   trade.SetExpertMagicNumber(InpMagicORB);
   for(int i=PositionsTotal()-1;i>=0;i--)
   { ulong t=PositionGetTicket(i);
     if(!PositionSelectByTicket(t)) continue;
     if(PositionGetInteger(POSITION_MAGIC)==InpMagicORB&&
        PositionGetString(POSITION_SYMBOL)==_Symbol) trade.PositionClose(t); }
   trade.SetExpertMagicNumber(InpMagic);
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
      if(mg==InpMagic)
      { if(p>0){g_winsToday++;g_totalWon+=p;} else if(p<0){g_lossesToday++;g_totalLost+=MathAbs(p);} }
      else if(mg==InpMagicORB)
      { if(p>0){g_orbWinsToday++;g_orbWonToday+=p;} else if(p<0){g_orbLossesToday++;g_orbLostToday+=MathAbs(p);} }
   }
   hC=tot;
}

//====================================================================
//  HELPERS
//====================================================================
void RegisterTrade(ulong t)
{ if(!t||g_openTradeCount>=50) return;
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

int CountOpenPositions()
{ int c=0; for(int i=0;i<PositionsTotal();i++)
  { ulong t=PositionGetTicket(i);
    if(PositionSelectByTicket(t)&&PositionGetInteger(POSITION_MAGIC)==InpMagic) c++; }
  return c; }

ulong GetOldestMagicTicket()
{ ulong o=0; datetime ot=TimeCurrent();
  for(int i=0;i<PositionsTotal();i++)
  { ulong t=PositionGetTicket(i);
    if(!PositionSelectByTicket(t)) continue;
    if(PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
    datetime tt=(datetime)PositionGetInteger(POSITION_TIME);
    if(!o||tt<ot){o=t;ot=tt;} }
  return o; }

void CloseAllMagic()
{ for(int i=PositionsTotal()-1;i>=0;i--)
  { ulong t=PositionGetTicket(i);
    if(PositionSelectByTicket(t)&&PositionGetInteger(POSITION_MAGIC)==InpMagic)
    { trade.PositionClose(t); RemoveTradeTracker(t); } } }

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
   ObjectSetString(0, "ORB_HIGH",OBJPROP_TEXT,"ORB H:"+DoubleToString(g_orbRangeHigh,2));
   ObjectCreate(0,"ORB_LOW",OBJ_HLINE,0,0,g_orbRangeLow);
   ObjectSetInteger(0,"ORB_LOW",OBJPROP_COLOR,clrOrangeRed);
   ObjectSetInteger(0,"ORB_LOW",OBJPROP_STYLE,STYLE_DASH);
   ObjectSetString(0, "ORB_LOW",OBJPROP_TEXT,"ORB L:"+DoubleToString(g_orbRangeLow,2));
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

void ORBDrawEntryLines(double en,double sl,double tp,bool isLong)
{
   string p=isLong?"LONG":"SHORT";
   ObjectDelete(0,"ORB_ENTRY"); ObjectDelete(0,"ORB_SL"); ObjectDelete(0,"ORB_TP");
   ObjectCreate(0,"ORB_ENTRY",OBJ_HLINE,0,0,en);
   ObjectSetInteger(0,"ORB_ENTRY",OBJPROP_COLOR,clrGold);
   ObjectSetInteger(0,"ORB_ENTRY",OBJPROP_WIDTH,2);
   ObjectSetString(0, "ORB_ENTRY",OBJPROP_TEXT,p+" ENTRY:"+DoubleToString(en,2));
   ObjectCreate(0,"ORB_SL",OBJ_HLINE,0,0,sl);
   ObjectSetInteger(0,"ORB_SL",OBJPROP_COLOR,clrRed);
   ObjectSetInteger(0,"ORB_SL",OBJPROP_WIDTH,2);
   ObjectSetString(0, "ORB_SL",OBJPROP_TEXT,"SL:"+DoubleToString(sl,2));
   ObjectCreate(0,"ORB_TP",OBJ_HLINE,0,0,tp);
   ObjectSetInteger(0,"ORB_TP",OBJPROP_COLOR,clrLimeGreen);
   ObjectSetInteger(0,"ORB_TP",OBJPROP_WIDTH,2);
   ObjectSetString(0, "ORB_TP",OBJPROP_TEXT,"TP:"+DoubleToString(tp,2));
   ChartRedraw();
}

void ORBDeleteDrawings()
{ string n[]={"ORB_HIGH","ORB_LOW","ORB_BULL","ORB_BEAR","ORB_ENTRY","ORB_SL","ORB_TP"};
  for(int i=0;i<ArraySize(n);i++) ObjectDelete(0,n[i]); ChartRedraw(); }

//====================================================================
//  PANEL UNIFICADO v7.0
//====================================================================
void DrawPanel()
{
   if(!InpShowPanel) return;
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);

   int posQQ=0,posORB=0,posMT=0;
   double pnlQQ=0,pnlORB=0,pnlMT=0,volQQ=0;

   for(int i=0;i<PositionsTotal();i++)
   { ulong t=PositionGetTicket(i);
     if(!PositionSelectByTicket(t)) continue;
     long mg=(long)PositionGetInteger(POSITION_MAGIC);
     if(mg==InpMagic)   {posQQ++;  pnlQQ +=PositionGetDouble(POSITION_PROFIT); volQQ+=PositionGetDouble(POSITION_VOLUME);}
     else if(mg==InpMagicORB){posORB++; pnlORB+=PositionGetDouble(POSITION_PROFIT);} }

   if(g_mtGroupActive)
      for(int i=1;i<g_maxMultiTrades;i++)
      { if(!g_mtGroup.tickets[i]) continue;
        if(PositionSelectByTicket(g_mtGroup.tickets[i]))
        {posMT++;pnlMT+=PositionGetDouble(POSITION_PROFIT);} }

   double dayPnL=AccountInfoDouble(ACCOUNT_BALANCE)-g_dayStartBal;
   double bal   =AccountInfoDouble(ACCOUNT_BALANCE);
   int    tQQ   =g_winsToday+g_lossesToday;
   double wrQQ  =tQQ>0?(100.0*g_winsToday/tQQ):0;
   double pfQQ  =g_totalLost>0?g_totalWon/g_totalLost:0;
   int    tORB  =g_orbWinsToday+g_orbLossesToday;
   double wrORB =tORB>0?(100.0*g_orbWinsToday/tORB):0;

   string orbR=(g_orbRangeHigh>0&&g_orbRangeLow<DBL_MAX)?
      DoubleToString(g_orbRangeHigh,2)+"/"+DoubleToString(g_orbRangeLow,2):"---";

   string sQQ=g_dayInvalid?"❌PAUSADO":!g_initialized?"⏳CONSTRUYENDO":g_triggered?"✅OPERANDO":"🎯VIGILANDO";
   string sORB=!InpLondonORBOn?"⬜OFF":g_orbTradeTriggered?"✅TRADE":g_orbRangeBuilt?"🎯ESPERA RUP":(dt.hour==7?"📐CONSTRUYENDO":"⏳ESPERA 07:00");
   string sMT =!InpMultiTradeOn?"⬜OFF":g_mtGroupActive?StringFormat("🔥ACTIVO(%d trades)",posMT+1):StringFormat("🔍Umbral: %.0f%%",InpMTF_ScoreThresh);

   string txt="";
   txt+="═══ QQ ULTIMATE v7.0 – MULTI-TRADE ═══\n";
   txt+=StringFormat("Hora : %02d:%02d | %s | Max/señal: %d\n",dt.hour,dt.min,CapModeStr(),g_maxMultiTrades);
   txt+=StringFormat("Bal  : $%.2f | PnL Día: $%.2f\n",bal,dayPnL);
   txt+=StringFormat("Tgt  : +$%.2f | Stop: -$%.2f\n",g_dailyProfitUSD,g_dailyLossUSD);
   txt+=StringFormat("D1   : %s | H1: %s | ATR: %.4f\n",
        g_sesgoUp?"📈BUY":(g_sesgoDn?"📉SELL":"---"),
        g_h1Up?"↑UP":(g_h1Dn?"↓DWN":"="),g_atr_cached);
   txt+="─── QQ Breakout / Scalper ───\n";
   txt+=StringFormat("Est  : %s | %d/%d trades\n",sQQ,g_tradesToday,g_maxTradesDay);
   txt+=StringFormat("Rng  : H=%.2f L=%.2f\n",g_rangeHigh,g_rangeLow);
   txt+=StringFormat("Pos  : %d vol:%.2f pnl:$%.2f\n",posQQ,volQQ,pnlQQ);
   txt+=StringFormat("Res  : W%d L%d WR:%.1f%% PF:%.2f\n",g_winsToday,g_lossesToday,wrQQ,pfQQ);
   txt+=StringFormat("Prot : BE%s P1%s P2%s Peak:$%.2f\n",
        g_beMoved?"✅":"○",g_partial1Done?"✅":"○",g_partial2Done?"✅":"○",g_peakProfit);
   txt+="─── Multi-Trade System ───\n";
   txt+=StringFormat("Est  : %s\n",sMT);
   if(g_mtGroupActive)
      txt+=StringFormat("Grp  : %d trades | PnL: $%.2f | Score: %.0f%%\n",
           g_mtGroup.count,pnlMT+pnlQQ,g_mtGroup.mtfScore);
   txt+="─── London ORB ───\n";
   txt+=StringFormat("Est  : %s\n",sORB);
   txt+=StringFormat("Rng  : %s (%d barras)\n",orbR,g_orbRangeBars);
   txt+=StringFormat("Pos  : %d pnl:$%.2f\n",posORB,pnlORB);
   txt+=StringFormat("Res  : W%d L%d WR:%.1f%% $%.2f\n",g_orbWinsToday,g_orbLossesToday,wrORB,g_orbWonToday);
   Comment(txt);
}

//====================================================================
//  OnTradeTransaction
//====================================================================
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &req,
                        const MqlTradeResult  &res)
{
   if(trans.type==TRADE_TRANSACTION_DEAL_ADD&&HistoryDealSelect(trans.deal))
   {
      long mg  =(long)HistoryDealGetInteger(trans.deal,DEAL_MAGIC);
      long en  =(long)HistoryDealGetInteger(trans.deal,DEAL_ENTRY);
      double p =HistoryDealGetDouble(trans.deal,DEAL_PROFIT);
      if(en==DEAL_ENTRY_OUT)
      {
         string src=(mg==InpMagicORB)?"[ORB]":
                    (g_mtGroupActive)?"[QQ/MT]":"[QQ]";
         Print(src," CIERRE $",DoubleToString(p,2),p>=0?" ✅":" ❌");
         // Si era un trade del grupo MT, verificar si el grupo sigue activo
         if(mg==InpMagic&&g_mtGroupActive)
         {
            bool anyLeft=false;
            for(int i=0;i<g_maxMultiTrades;i++)
               if(g_mtGroup.tickets[i]&&PositionSelectByTicket(g_mtGroup.tickets[i]))
               { anyLeft=true; break; }
            if(!anyLeft) { g_mtGroupActive=false; Print("📊 Grupo MT completado."); }
         }
      }
   }
}

//+------------------------------------------------------------------+
//  FIN – QQ ULTIMATE v7.0 MULTI-TRADE EDITION
//+------------------------------------------------------------------+
