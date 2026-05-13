//+------------------------------------------------------------------+
//|  XAUUSD QUANTUM QUEEN ULTIMATE v6.0 – LONDON EDITION            |
//|  Estrategias: Breakout | EMA Scalper | Pyramid | Retest |        |
//|               London Open Range Breakout (S2)                    |
//|  Sistema de Pérdidas: 10 Capas de Protección (Pro Edition)       |
//|  Timeframes análisis: D1/H1/M15 | Ejecución: M5/M1              |
//|  Magic Numbers independientes por estrategia                     |
//+------------------------------------------------------------------+
#property copyright "QQ Ultimate v6.0 – London Edition"
#property version   "6.00"
#property strict

#include <Trade/Trade.mqh>
CTrade trade;

//====================================================================
//  ENUMERACIÓN DE MODOS DE CAPITAL
//====================================================================
enum ENUM_CAP_MODE
{
   CAP_MICRO    = 0,  // < $50   – Ultra conservador
   CAP_SMALL    = 1,  // $50-199 – Conservador
   CAP_MEDIUM   = 2,  // $200-999– Estándar
   CAP_STANDARD = 3   // >= $1000– Completo
};

//====================================================================
//  INPUTS – GESTIÓN DE CAPITAL (compartida)
//====================================================================
input group "=== GESTIÓN DE CAPITAL ==="
input bool   InpAutoCapital     = true;    // Detectar capital automáticamente
input double InpRiskPercent     = 0.8;     // % riesgo base por trade
input double InpLotFixed        = 0.01;    // Lote fijo (si auto=false)
input int    InpMagic           = 5900;    // Magic number QQ (Breakout/Scalper)

//====================================================================
//  INPUTS – ESTRATEGIA QQ BREAKOUT (original)
//====================================================================
input group "=== ESTRATEGIA QQ BREAKOUT ==="
input int    InpRangeHourStart  = 7;       // Hora inicio rango QQ
input int    InpRangeHourEnd    = 8;       // Hora fin rango QQ
input int    InpBreakoutHourEnd = 10;      // Hora fin ventana breakout QQ
input double InpRangeMinPts     = 1.5;     // Tamaño mínimo rango (pts)
input double InpRangeMaxPts     = 12.0;    // Tamaño máximo rango (pts)
input double InpBreakoutOffset  = 0.20;    // Offset ruptura (pts)
input double InpRR              = 2.2;     // R:R ratio QQ

//====================================================================
//  INPUTS – ESTRATEGIA EMA SCALPER
//====================================================================
input group "=== ESTRATEGIA EMA SCALPER ==="
input bool   InpScalperOn       = true;    // Activar Scalper EMA M1/M5
input int    InpScalperHourStart= 8;       // Hora inicio scalper
input int    InpScalperHourEnd  = 20;      // Hora fin scalper
input int    InpFastEMA         = 9;       // EMA rápida
input int    InpSlowEMA         = 21;      // EMA lenta
input int    InpTrendEMA        = 50;      // EMA tendencia

//====================================================================
//  INPUTS – ESTRATEGIA LONDON ORB (S2) — Horario y filtros
//====================================================================
input group "=== ESTRATEGIA LONDON ORB (S2) ==="
input bool   InpLondonORBOn     = true;    // Activar estrategia London ORB
input int    InpMagicORB        = 20250800;// Magic number London ORB (INDEPENDIENTE)
input int    InpORBRangeHStart  = 7;       // Inicio construcción rango ORB (UTC)
input int    InpORBRangeHEnd    = 7;       // Fin hora rango ORB (minuto 59)
input int    InpORBTradeHStart  = 8;       // Inicio ventana de entrada ORB
input int    InpORBTradeHEnd    = 9;       // Fin ventana de entrada ORB (inclusive)
input int    InpORBMaxMinutes   = 120;     // Cierre forzado tras N minutos
input double InpORBRangeMinPts  = 2.0;     // Tamaño mínimo del rango ORB
input double InpORBRangeMaxPts  = 10.0;    // Tamaño máximo del rango ORB
input int    InpORBMinBars      = 25;      // Barras mínimas en hora 07:00
input double InpORBBreakBuf     = 0.2;     // Buffer ruptura (pts)
input double InpORBSLBuffer     = 0.3;     // Buffer SL (pts)
input double InpORBRR           = 2.0;     // R:R multiplicador ORB
input int    InpORBEmaFast      = 50;      // EMA rápida sesgo ORB
input int    InpORBEmaSlow      = 200;     // EMA lenta sesgo ORB
input int    InpORBMaxSpread    = 50;      // Spread máximo ORB (puntos)

//====================================================================
//  INPUTS – SL/TP DINÁMICO (ATR)
//====================================================================
input group "=== SL/TP DINÁMICO ==="
input double InpATR_SL_Mult     = 1.3;    // Multiplicador ATR para SL
input double InpATR_TP_Mult     = 2.6;    // Multiplicador ATR para TP

//====================================================================
//  INPUTS – SISTEMA PIRAMIDAL
//====================================================================
input group "=== SISTEMA PIRAMIDAL ==="
input bool   InpPyramidOn       = true;    // Activar pirámide
input int    InpPyramidLevels   = 2;       // Niveles adicionales

//====================================================================
//  INPUTS – SISTEMA DE CIERRE (10 CAPAS)
//====================================================================
input group "=== CIERRES AUTOMÁTICOS ==="
input bool   InpTrailingOn      = true;    // Trailing stop ATR
input bool   InpPartialClose    = true;    // Cierre parcial progresivo
input bool   InpSmartExitOn     = true;    // Salida inteligente por indicadores
input bool   InpMomentumExitOn  = true;    // Cierre por pérdida de momentum
input double InpMinProfitLock   = 0.30;    // Ganancia mín para activar lock ($)

//====================================================================
//  INPUTS – PROTECCIONES GLOBALES
//====================================================================
input group "=== PROTECCIONES ==="
input double InpMaxSpread       = 45.0;    // Spread máximo QQ (puntos)
input double InpMaxDailyLossPct = 3.0;     // Stop diario máximo (% balance) — override de seguridad
input bool   InpNewsFilter      = false;   // Pausar 15 min antes/después de hora cerrada (reservado)

//====================================================================
//  INPUTS – INDICADORES
//====================================================================
input group "=== INDICADORES ==="
input int    InpBBPeriod        = 20;      // Bollinger Bands período
input int    InpRSIPeriod       = 14;      // RSI período
input int    InpMFIPeriod       = 14;      // MFI período
input int    InpATRPeriod       = 14;      // ATR período

input group "=== MONITOREO ==="
input bool   InpShowPanel       = true;    // Mostrar panel

//====================================================================
//  HANDLES DE INDICADORES – QQ ORIGINAL
//====================================================================
int hEMA50_D1, hEMA200_D1;
int hRSI_H1,   hATR_H1;
int hBB_M5,    hRSI_M5, hMFI_M5, hATR_M5;
int hFastEMA_M5, hSlowEMA_M5, hTrendEMA_M5;
int hFastEMA_M1, hSlowEMA_M1, hTrendEMA_M1;
int hRSI_M1,   hATR_M1;

//====================================================================
//  HANDLES DE INDICADORES – LONDON ORB
//====================================================================
int hORB_EmaFast, hORB_EmaSlow;

//====================================================================
//  VARIABLES DE CAPITAL AUTOMÁTICO
//====================================================================
ENUM_CAP_MODE g_capMode         = CAP_MICRO;
double        g_riskPct         = 0.8;
double        g_dailyLossUSD    = 0;
double        g_dailyProfitUSD  = 0;
double        g_minProfitLock   = 0;
double        g_profitRetrace   = 0;
double        g_pyramidTrig1    = 0;
double        g_pyramidTrig2    = 0;
double        g_pyramidLotMult  = 0;
double        g_trailingMult    = 0;
double        g_scalperRR       = 0;
int           g_maxTradesDay    = 0;
int           g_maxBarsOpen     = 0;
int           g_maxNegBars      = 0;
double        g_partialAt1R     = 0;
double        g_partialAt2R     = 0;

//====================================================================
//  ESTADO QQ ORIGINAL
//====================================================================
double   g_rangeHigh     = 0, g_rangeLow = 0;
int      g_rangeBars     = 0;
bool     g_dayInvalid    = false;
bool     g_initialized   = false;
bool     g_triggered     = false;
datetime g_breakoutTime  = 0;

bool     g_sesgoUp       = false, g_sesgoDn = false;
bool     g_h1Up          = false, g_h1Dn    = false;

int      g_tradesToday   = 0;
double   g_dayStartBal   = 0;
datetime g_lastDay       = 0;

int      g_pyramidLevel  = 0;
double   g_entry1Lot     = 0, g_entry1Price = 0;
bool     g_partial1Done  = false, g_partial2Done = false, g_beMoved = false;
double   g_peakProfit    = 0;
double   g_atr_cached    = 0, g_bbMid_cached = 0;

datetime g_lastBarM5     = 0;

struct TradeInfo { ulong ticket; datetime openTime; };
TradeInfo g_openTrades[50];
int       g_openTradeCount = 0;

int      g_winsToday     = 0;
int      g_lossesToday   = 0;
double   g_totalWon      = 0;
double   g_totalLost     = 0;

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

// Estadísticas ORB independientes
int      g_orbWinsToday   = 0;
int      g_orbLossesToday = 0;
double   g_orbWonToday    = 0;
double   g_orbLostToday   = 0;

//====================================================================
//  OnInit
//====================================================================
int OnInit()
{
   // ---- Handles QQ original ----
   hEMA50_D1    = iMA(_Symbol, PERIOD_D1, 50,  0, MODE_EMA, PRICE_CLOSE);
   hEMA200_D1   = iMA(_Symbol, PERIOD_D1, 200, 0, MODE_EMA, PRICE_CLOSE);
   hRSI_H1      = iRSI(_Symbol, PERIOD_H1,  InpRSIPeriod, PRICE_CLOSE);
   hATR_H1      = iATR(_Symbol, PERIOD_H1,  InpATRPeriod);
   hBB_M5       = iBands(_Symbol, PERIOD_M5, InpBBPeriod, 0, 2.0, PRICE_CLOSE);
   hRSI_M5      = iRSI(_Symbol,  PERIOD_M5, InpRSIPeriod, PRICE_CLOSE);
   hMFI_M5      = iMFI(_Symbol,  PERIOD_M5, InpMFIPeriod, VOLUME_TICK);
   hATR_M5      = iATR(_Symbol,  PERIOD_M5, InpATRPeriod);
   hFastEMA_M5  = iMA(_Symbol,  PERIOD_M5, InpFastEMA,  0, MODE_EMA, PRICE_CLOSE);
   hSlowEMA_M5  = iMA(_Symbol,  PERIOD_M5, InpSlowEMA,  0, MODE_EMA, PRICE_CLOSE);
   hTrendEMA_M5 = iMA(_Symbol,  PERIOD_M5, InpTrendEMA, 0, MODE_EMA, PRICE_CLOSE);
   hFastEMA_M1  = iMA(_Symbol,  PERIOD_M1, InpFastEMA,  0, MODE_EMA, PRICE_CLOSE);
   hSlowEMA_M1  = iMA(_Symbol,  PERIOD_M1, InpSlowEMA,  0, MODE_EMA, PRICE_CLOSE);
   hTrendEMA_M1 = iMA(_Symbol,  PERIOD_M1, InpTrendEMA, 0, MODE_EMA, PRICE_CLOSE);
   hRSI_M1      = iRSI(_Symbol,  PERIOD_M1, InpRSIPeriod, PRICE_CLOSE);
   hATR_M1      = iATR(_Symbol,  PERIOD_M1, InpATRPeriod);

   // ---- Handles London ORB (M1 para sesgo de tendencia) ----
   hORB_EmaFast = iMA(_Symbol, PERIOD_M1, InpORBEmaFast, 0, MODE_EMA, PRICE_CLOSE);
   hORB_EmaSlow = iMA(_Symbol, PERIOD_M1, InpORBEmaSlow, 0, MODE_EMA, PRICE_CLOSE);

   if(hEMA50_D1 == INVALID_HANDLE || hEMA200_D1 == INVALID_HANDLE ||
      hRSI_H1   == INVALID_HANDLE || hBB_M5     == INVALID_HANDLE ||
      hRSI_M5   == INVALID_HANDLE || hATR_M5    == INVALID_HANDLE ||
      hFastEMA_M5 == INVALID_HANDLE || hFastEMA_M1 == INVALID_HANDLE ||
      hORB_EmaFast == INVALID_HANDLE || hORB_EmaSlow == INVALID_HANDLE)
   {
      Alert("❌ Error creando handles de indicadores (QQ v6.0)");
      return INIT_FAILED;
   }

   // Dos magic numbers independientes — sin conflictos
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(10);
   trade.SetTypeFilling(ORDER_FILLING_FOK);

   g_dayStartBal = AccountInfoDouble(ACCOUNT_BALANCE);
   DetectCapitalMode();
   DailyReset();

   Print("✅ QQ Ultimate v6.0 – London Edition | Capital: $",
         DoubleToString(g_dayStartBal, 2),
         " | Modo: ", CapModeStr(),
         " | ORB Magic: ", InpMagicORB);

   return INIT_SUCCEEDED;
}

//====================================================================
//  OnDeinit
//====================================================================
void OnDeinit(const int reason)
{
   Comment("");
   IndicatorRelease(hEMA50_D1);   IndicatorRelease(hEMA200_D1);
   IndicatorRelease(hRSI_H1);     IndicatorRelease(hATR_H1);
   IndicatorRelease(hBB_M5);      IndicatorRelease(hRSI_M5);
   IndicatorRelease(hMFI_M5);     IndicatorRelease(hATR_M5);
   IndicatorRelease(hFastEMA_M5); IndicatorRelease(hSlowEMA_M5);
   IndicatorRelease(hTrendEMA_M5);
   IndicatorRelease(hFastEMA_M1); IndicatorRelease(hSlowEMA_M1);
   IndicatorRelease(hTrendEMA_M1);
   IndicatorRelease(hRSI_M1);     IndicatorRelease(hATR_M1);
   IndicatorRelease(hORB_EmaFast);IndicatorRelease(hORB_EmaSlow);
   ORBDeleteDrawings();
}

//====================================================================
//  ★ DETECCIÓN AUTOMÁTICA DE CAPITAL
//====================================================================
void DetectCapitalMode()
{
   if(!InpAutoCapital)
   {
      g_capMode        = CAP_STANDARD;
      g_riskPct        = InpRiskPercent;
      g_dailyLossUSD   = 10.0;
      g_dailyProfitUSD = 30.0;
      g_minProfitLock  = InpMinProfitLock;
      g_profitRetrace  = 0.15;
      g_pyramidTrig1   = 1.0; g_pyramidTrig2   = 2.0;
      g_pyramidLotMult = 0.70;
      g_trailingMult   = 1.0;
      g_scalperRR      = 1.8;
      g_maxTradesDay   = 6;
      g_maxBarsOpen    = 120;
      g_maxNegBars     = 20;
      g_partialAt1R    = 0.30; g_partialAt2R = 0.40;
      return;
   }

   double bal = AccountInfoDouble(ACCOUNT_BALANCE);

   if(bal < 50.0)
   {
      g_capMode        = CAP_MICRO;
      g_riskPct        = 1.0;
      g_dailyLossUSD   = bal * 0.06;
      g_dailyProfitUSD = bal * 0.15;
      g_minProfitLock  = bal * 0.02;
      g_profitRetrace  = bal * 0.008;
      g_pyramidTrig1   = 2.0; g_pyramidTrig2 = 4.0;
      g_pyramidLotMult = 0.5;
      g_trailingMult   = 0.7;
      g_scalperRR      = 2.0;
      g_maxTradesDay   = 3;
      g_maxBarsOpen    = 60;
      g_maxNegBars     = 10;
      g_partialAt1R    = 0.40; g_partialAt2R = 0.40;
   }
   else if(bal < 200.0)
   {
      g_capMode        = CAP_SMALL;
      g_riskPct        = 0.9;
      g_dailyLossUSD   = bal * 0.05;
      g_dailyProfitUSD = bal * 0.12;
      g_minProfitLock  = bal * 0.015;
      g_profitRetrace  = bal * 0.006;
      g_pyramidTrig1   = 1.5; g_pyramidTrig2 = 3.0;
      g_pyramidLotMult = 0.60;
      g_trailingMult   = 0.8;
      g_scalperRR      = 1.9;
      g_maxTradesDay   = 4;
      g_maxBarsOpen    = 80;
      g_maxNegBars     = 15;
      g_partialAt1R    = 0.35; g_partialAt2R = 0.40;
   }
   else if(bal < 1000.0)
   {
      g_capMode        = CAP_MEDIUM;
      g_riskPct        = 0.7;
      g_dailyLossUSD   = bal * 0.04;
      g_dailyProfitUSD = bal * 0.10;
      g_minProfitLock  = bal * 0.012;
      g_profitRetrace  = bal * 0.005;
      g_pyramidTrig1   = 1.0; g_pyramidTrig2 = 2.0;
      g_pyramidLotMult = 0.65;
      g_trailingMult   = 0.9;
      g_scalperRR      = 1.8;
      g_maxTradesDay   = 5;
      g_maxBarsOpen    = 100;
      g_maxNegBars     = 18;
      g_partialAt1R    = 0.30; g_partialAt2R = 0.40;
   }
   else
   {
      g_capMode        = CAP_STANDARD;
      g_riskPct        = InpRiskPercent;
      g_dailyLossUSD   = bal * 0.03;
      g_dailyProfitUSD = bal * 0.08;
      g_minProfitLock  = bal * 0.010;
      g_profitRetrace  = bal * 0.004;
      g_pyramidTrig1   = 1.0; g_pyramidTrig2 = 2.0;
      g_pyramidLotMult = 0.70;
      g_trailingMult   = 1.0;
      g_scalperRR      = 1.8;
      g_maxTradesDay   = 6;
      g_maxBarsOpen    = 120;
      g_maxNegBars     = 20;
      g_partialAt1R    = 0.30; g_partialAt2R = 0.40;
   }

   // Override de seguridad: nunca superar el límite manual si es más conservador
   double manualStopUSD = AccountInfoDouble(ACCOUNT_BALANCE) * InpMaxDailyLossPct / 100.0;
   if(manualStopUSD < g_dailyLossUSD) g_dailyLossUSD = manualStopUSD;
}

string CapModeStr()
{
   if(g_capMode == CAP_MICRO)  return "MICRO (<$50)";
   if(g_capMode == CAP_SMALL)  return "SMALL ($50-199)";
   if(g_capMode == CAP_MEDIUM) return "MEDIUM ($200-999)";
   return "STANDARD (>=$1000)";
}

//====================================================================
//  OnTick – Orquestador principal
//====================================================================
void OnTick()
{
   CheckDayReset();
   UpdateMarketBias();

   // ── Motor QQ original ──
   if(!g_dayInvalid)
   {
      BuildRange();
      ValidateRange();
      SearchBreakout();
      SearchRetestEntry();
      ManagePyramid();
      if(InpScalperOn) RunScalperStrategy();
   }

   ManageOpenTrades();     // Gestión 10 capas para QQ
   TrackClosedTrades();

   // ── Motor London ORB (independiente, solo en M1) ──
   if(InpLondonORBOn)
   {
      RunLondonORB();
      ManageORBTrades();   // Gestión de cierre por tiempo del ORB
   }

   DrawPanel();
}

//====================================================================
//  RESET DIARIO
//====================================================================
void DailyReset()
{
   g_rangeHigh = 0; g_rangeLow = 0; g_rangeBars = 0;
   g_dayInvalid = false; g_initialized = false;
   g_triggered = false; g_breakoutTime = 0;
   g_sesgoUp = false; g_sesgoDn = false;
   g_h1Up = false; g_h1Dn = false;
   g_tradesToday = 0; g_peakProfit = 0;
   g_pyramidLevel = 0; g_entry1Lot = 0; g_entry1Price = 0;
   g_partial1Done = false; g_partial2Done = false; g_beMoved = false;
   g_openTradeCount = 0;
   g_winsToday = 0; g_lossesToday = 0;
   g_totalWon = 0; g_totalLost = 0;
   // ORB reset diario
   ORBDailyReset();
   DetectCapitalMode();
}

void CheckDayReset()
{
   datetime currentDay = iTime(_Symbol, PERIOD_D1, 0);
   if(currentDay != g_lastDay)
   {
      g_dayStartBal = AccountInfoDouble(ACCOUNT_BALANCE);
      g_lastDay = currentDay;
      DailyReset();
   }
}

//====================================================================
//  SESGO MULTI-TIMEFRAME
//====================================================================
void UpdateMarketBias()
{
   double ema50[1], ema200[1];
   if(CopyBuffer(hEMA50_D1,  0, 0, 1, ema50)  > 0 &&
      CopyBuffer(hEMA200_D1, 0, 0, 1, ema200) > 0)
   {
      g_sesgoUp = (ema50[0] > ema200[0]);
      g_sesgoDn = (ema50[0] < ema200[0]);
   }
   double rsiH1[1];
   if(CopyBuffer(hRSI_H1, 0, 0, 1, rsiH1) > 0)
   {
      g_h1Up = (rsiH1[0] > 53.0);
      g_h1Dn = (rsiH1[0] < 47.0);
   }
}

//====================================================================
//  RANGO QQ
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
   double rngSize = g_rangeHigh - g_rangeLow;
   g_initialized = true;
   if(g_rangeBars < 25 || rngSize < InpRangeMinPts || rngSize > InpRangeMaxPts)
      Print("⚠️ Rango QQ inválido (size=", rngSize, ") | Scalper activo");
}

//====================================================================
//  INDICADORES M5
//====================================================================
bool GetIndM5(double &bbU, double &bbD, double &bbM,
              double &rsi, double &mfi, double &atr)
{
   double bU[1], bD[1], bM[1], r[1], m[1], a[1];
   if(CopyBuffer(hBB_M5,  1, 0, 1, bU) <= 0) return false;
   if(CopyBuffer(hBB_M5,  2, 0, 1, bD) <= 0) return false;
   if(CopyBuffer(hBB_M5,  0, 0, 1, bM) <= 0) return false;
   if(CopyBuffer(hRSI_M5, 0, 0, 1, r)  <= 0) return false;
   if(CopyBuffer(hMFI_M5, 0, 0, 1, m)  <= 0) return false;
   if(CopyBuffer(hATR_M5, 0, 0, 1, a)  <= 0) return false;
   bbU = bU[0]; bbD = bD[0]; bbM = bM[0];
   rsi = r[0];  mfi = m[0];  atr = a[0];
   g_bbMid_cached = bM[0];
   g_atr_cached   = a[0];
   return true;
}

//====================================================================
//  FILTROS DE WINRATE – 8 confirmaciones
//====================================================================
bool FilterTrendD1(bool isBuy)    { return isBuy ? g_sesgoUp : g_sesgoDn; }

bool FilterMomentumH1(bool isBuy)
{
   if(g_capMode == CAP_MICRO) return true;
   return isBuy ? g_h1Up : g_h1Dn;
}

bool FilterRSI(double rsi, bool isBuy)
{
   return isBuy ? (rsi > 48.0 && rsi < 72.0) : (rsi < 52.0 && rsi > 28.0);
}

bool FilterBBTrend(double close, double bbM, bool isBuy)
{
   return isBuy ? (close > bbM) : (close < bbM);
}

bool FilterMFI(double mfi, bool isBuy)
{
   if(g_capMode == CAP_MICRO) return true;
   return isBuy ? (mfi > 48.0) : (mfi < 52.0);
}

bool FilterGoldBias(double rsi, bool isBuy)
{
   return isBuy ? (rsi > 47.0 || g_sesgoUp) : (!g_sesgoUp && rsi < 50.0);
}

bool FilterATRMin(double atr)
{
   double minATR = (g_capMode == CAP_MICRO) ? 0.5 : 0.8;
   return (atr >= minATR * _Point * 100);
}

bool FilterSpread()
{
   double spread = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   double maxSpr = (g_capMode == CAP_MICRO) ? 30.0 : InpMaxSpread;
   return (spread <= maxSpr);
}

int SignalScore(bool isBuy, double close, double bbM, double rsi, double mfi, double atr)
{
   int score = 0;
   if(FilterTrendD1(isBuy))             score++;
   if(FilterMomentumH1(isBuy))          score++;
   if(FilterRSI(rsi, isBuy))            score++;
   if(FilterBBTrend(close, bbM, isBuy)) score++;
   if(FilterMFI(mfi, isBuy))            score++;
   if(FilterGoldBias(rsi, isBuy))       score++;
   if(FilterATRMin(atr))                score++;
   if(FilterSpread())                   score++;
   return score;
}

int MinScoreRequired()
{
   if(g_capMode == CAP_MICRO) return 5;
   if(g_capMode == CAP_SMALL) return 6;
   return 6;
}

//====================================================================
//  CÁLCULO DE LOTAJE
//====================================================================
double CalcLot(double slPts, double riskMult)
{
   double riskPct = g_riskPct * riskMult;
   double bal     = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk    = bal * (riskPct / 100.0);
   double tv      = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double ts      = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(slPts <= 0 || tv <= 0 || ts <= 0) return NormLot(0.01);
   double slMoney = slPts / ts * tv;
   double lot     = (slMoney > 0) ? risk / slMoney : 0.01;
   if(g_capMode == CAP_MICRO)
      lot = MathMin(lot, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN) * 2.0);
   return NormLot(lot);
}

void CalcSLTP(bool isBuy, double entry, double atr, double &sl, double &tp, double rrMult = 1.0)
{
   double slD = atr * InpATR_SL_Mult;
   double tpD = atr * InpATR_TP_Mult * rrMult;
   if(g_capMode == CAP_MICRO) slD *= 1.15;
   sl = isBuy ? entry - slD : entry + slD;
   tp = isBuy ? entry + tpD : entry - tpD;
}

//====================================================================
//  BREAKOUT QQ
//====================================================================
void SearchBreakout()
{
   if(g_triggered || !g_initialized) return;
   if(g_rangeHigh == 0 || g_rangeLow == 0) return;
   if(g_tradesToday >= g_maxTradesDay) return;

   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   if(dt.hour < InpRangeHourEnd || dt.hour >= InpBreakoutHourEnd) return;

   double dayPnL = AccountInfoDouble(ACCOUNT_BALANCE) - g_dayStartBal;
   if(dayPnL < -g_dailyLossUSD || dayPnL > g_dailyProfitUSD) return;

   double close = iClose(_Symbol, PERIOD_M5, 0);
   double bbU, bbD, bbM, rsi, mfi, atr;
   if(!GetIndM5(bbU, bbD, bbM, rsi, mfi, atr)) return;
   double offset = InpBreakoutOffset * _Point * 10;

   if(close > (g_rangeHigh + offset))
   {
      int score = SignalScore(true, close, bbM, rsi, mfi, atr);
      if(score < MinScoreRequired()) return;
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl, tp;
      CalcSLTP(true, ask, atr, sl, tp);
      double lot = CalcLot(ask - sl, 1.0);
      if(trade.Buy(lot, _Symbol, ask, sl, tp))
      {
         g_triggered = true; g_tradesToday++;
         g_entry1Lot = lot; g_entry1Price = ask;
         g_pyramidLevel = 0; g_partial1Done = false;
         g_partial2Done = false; g_beMoved = false;
         g_breakoutTime = TimeCurrent();
         RegisterTrade(trade.ResultOrder());
         Print("🟢 QQ BREAKOUT LONG @ ", ask, " SL:", sl, " TP:", tp,
               " Lot:", lot, " Score:", score);
      }
   }
   else if(close < (g_rangeLow - offset))
   {
      int score = SignalScore(false, close, bbM, rsi, mfi, atr);
      if(score < MinScoreRequired()) return;
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl, tp;
      CalcSLTP(false, bid, atr, sl, tp);
      double lot = CalcLot(sl - bid, 1.0);
      if(trade.Sell(lot, _Symbol, bid, sl, tp))
      {
         g_triggered = true; g_tradesToday++;
         g_entry1Lot = lot; g_entry1Price = bid;
         g_pyramidLevel = 0; g_partial1Done = false;
         g_partial2Done = false; g_beMoved = false;
         g_breakoutTime = TimeCurrent();
         RegisterTrade(trade.ResultOrder());
         Print("🔴 QQ BREAKOUT SHORT @ ", bid, " SL:", sl, " TP:", tp,
               " Lot:", lot, " Score:", score);
      }
   }
}

//====================================================================
//  RETEST QQ
//====================================================================
void SearchRetestEntry()
{
   if(!g_triggered || g_tradesToday >= g_maxTradesDay) return;
   if(CountOpenPositions() > 0) return;
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   if(dt.hour >= InpBreakoutHourEnd) return;

   if(g_breakoutTime > 0)
   {
      int bars = (int)((TimeCurrent() - g_breakoutTime) / PeriodSeconds(PERIOD_M5));
      if(bars > 30) return;
   }

   double close = iClose(_Symbol, PERIOD_M5, 0);
   double bbU, bbD, bbM, rsi, mfi, atr;
   if(!GetIndM5(bbU, bbD, bbM, rsi, mfi, atr)) return;
   double zone = 0.50 * _Point * 10;

   if(g_sesgoUp && g_h1Up)
   {
      if(close <= g_rangeHigh + zone && close >= g_rangeHigh - zone)
      {
         int score = SignalScore(true, close, bbM, rsi, mfi, atr);
         if(score < MinScoreRequired()) return;
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double sl, tp;
         CalcSLTP(true, ask, atr, sl, tp);
         double lot = CalcLot(ask - sl, 0.70);
         if(trade.Buy(lot, _Symbol, ask, sl, tp))
         {
            g_tradesToday++;
            RegisterTrade(trade.ResultOrder());
            Print("🟢 QQ RETEST LONG @ ", ask, " Lot:", lot);
         }
      }
   }
   else if(g_sesgoDn && g_h1Dn)
   {
      if(close >= g_rangeLow - zone && close <= g_rangeLow + zone)
      {
         int score = SignalScore(false, close, bbM, rsi, mfi, atr);
         if(score < MinScoreRequired()) return;
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double sl, tp;
         CalcSLTP(false, bid, atr, sl, tp);
         double lot = CalcLot(sl - bid, 0.70);
         if(trade.Sell(lot, _Symbol, bid, sl, tp))
         {
            g_tradesToday++;
            RegisterTrade(trade.ResultOrder());
            Print("🔴 QQ RETEST SHORT @ ", bid, " Lot:", lot);
         }
      }
   }
}

//====================================================================
//  PIRAMIDAL QQ
//====================================================================
void ManagePyramid()
{
   if(!InpPyramidOn || !g_triggered) return;
   if(g_pyramidLevel >= InpPyramidLevels) return;
   if(g_tradesToday >= g_maxTradesDay) return;
   if(g_capMode == CAP_MICRO) return;

   ulong masterTicket = 0; bool masterIsBuy = false;
   double masterSL = 0, masterPrice = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      masterTicket  = ticket;
      masterIsBuy   = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      masterSL      = PositionGetDouble(POSITION_SL);
      masterPrice   = PositionGetDouble(POSITION_PRICE_OPEN);
      break;
   }
   if(masterTicket == 0) return;

   double trigPts = (g_pyramidLevel == 0) ? g_pyramidTrig1 * _Point * 10
                                           : g_pyramidTrig2 * _Point * 10;
   double curP    = masterIsBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double move    = masterIsBuy ? (curP - masterPrice) : (masterPrice - curP);
   if(move < trigPts) return;

   double pyrLot = NormLot(g_entry1Lot * MathPow(g_pyramidLotMult, g_pyramidLevel + 1));
   double bbU, bbD, bbM, rsi, mfi, atr;
   if(!GetIndM5(bbU, bbD, bbM, rsi, mfi, atr)) return;
   double sl, tp;

   if(masterIsBuy)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      sl = masterPrice;
      tp = ask + atr * InpATR_TP_Mult * (g_capMode == CAP_SMALL ? 2.0 : 1.5);
      if(trade.Buy(pyrLot, _Symbol, ask, sl, tp))
      {
         g_pyramidLevel++; g_tradesToday++;
         RegisterTrade(trade.ResultOrder());
         Print("📈 PIRÁMIDE L", g_pyramidLevel, " @ ", ask, " Lot:", pyrLot);
      }
   }
   else
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      sl = masterPrice;
      tp = bid - atr * InpATR_TP_Mult * (g_capMode == CAP_SMALL ? 2.0 : 1.5);
      if(trade.Sell(pyrLot, _Symbol, bid, sl, tp))
      {
         g_pyramidLevel++; g_tradesToday++;
         RegisterTrade(trade.ResultOrder());
         Print("📉 PIRÁMIDE L", g_pyramidLevel, " @ ", bid, " Lot:", pyrLot);
      }
   }
}

//====================================================================
//  EMA SCALPER QQ
//====================================================================
void RunScalperStrategy()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   if(dt.hour < InpScalperHourStart || dt.hour >= InpScalperHourEnd) return;
   if(g_tradesToday >= g_maxTradesDay) return;
   if(CountOpenPositions() > 0) return;
   if(!FilterSpread()) return;

   double dayPnL = AccountInfoDouble(ACCOUNT_BALANCE) - g_dayStartBal;
   if(dayPnL < -g_dailyLossUSD || dayPnL > g_dailyProfitUSD) return;

   datetime barM5 = iTime(_Symbol, PERIOD_M5, 0);
   if(barM5 == g_lastBarM5) return;

   double fM5[3], sM5[3], tM5[3];
   ArraySetAsSeries(fM5, true); ArraySetAsSeries(sM5, true); ArraySetAsSeries(tM5, true);
   if(CopyBuffer(hFastEMA_M5,  0, 0, 3, fM5)  <= 0) return;
   if(CopyBuffer(hSlowEMA_M5,  0, 0, 3, sM5)  <= 0) return;
   if(CopyBuffer(hTrendEMA_M5, 0, 0, 3, tM5)  <= 0) return;

   double fM1[2], sM1[2], tM1[2];
   ArraySetAsSeries(fM1, true); ArraySetAsSeries(sM1, true); ArraySetAsSeries(tM1, true);
   if(CopyBuffer(hFastEMA_M1,  0, 0, 2, fM1)  <= 0) return;
   if(CopyBuffer(hSlowEMA_M1,  0, 0, 2, sM1)  <= 0) return;
   if(CopyBuffer(hTrendEMA_M1, 0, 0, 2, tM1)  <= 0) return;

   double bbU, bbD, bbM, rsi, mfi, atr;
   if(!GetIndM5(bbU, bbD, bbM, rsi, mfi, atr)) return;
   if(atr <= 0) return;

   double close = iClose(_Symbol, PERIOD_M5, 0);

   bool crossUpM5 = (fM5[0] > sM5[0]) && (fM5[1] <= sM5[1]);
   bool crossDnM5 = (fM5[0] < sM5[0]) && (fM5[1] >= sM5[1]);
   bool trendUpM5 = (fM5[0] > tM5[0]);
   bool trendDnM5 = (fM5[0] < tM5[0]);
   bool alignUpM1 = (fM1[0] > sM1[0] && fM1[0] > tM1[0]);
   bool alignDnM1 = (fM1[0] < sM1[0] && fM1[0] < tM1[0]);

   bool sigBuy  = crossUpM5 && trendUpM5 && alignUpM1;
   bool sigSell = crossDnM5 && trendDnM5 && alignDnM1;

   if(!sigBuy && !sigSell) return;

   if(sigBuy)
   {
      int score = SignalScore(true, close, bbM, rsi, mfi, atr);
      if(score < MinScoreRequired()) return;
      g_lastBarM5 = barM5;
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl, tp;
      CalcSLTP(true, ask, atr, sl, tp, g_scalperRR / InpRR);
      double lot = CalcLot(ask - sl, 0.80);
      if(trade.Buy(lot, _Symbol, ask, sl, tp))
      {
         g_tradesToday++;
         RegisterTrade(trade.ResultOrder());
         Print("⚡ SCALPER BUY @ ", ask, " SL:", sl, " TP:", tp,
               " Lot:", lot, " Score:", score);
      }
   }
   else if(sigSell)
   {
      int score = SignalScore(false, close, bbM, rsi, mfi, atr);
      if(score < MinScoreRequired()) return;
      g_lastBarM5 = barM5;
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl, tp;
      CalcSLTP(false, bid, atr, sl, tp, g_scalperRR / InpRR);
      double lot = CalcLot(sl - bid, 0.80);
      if(trade.Sell(lot, _Symbol, bid, sl, tp))
      {
         g_tradesToday++;
         RegisterTrade(trade.ResultOrder());
         Print("⚡ SCALPER SELL @ ", bid, " SL:", sl, " TP:", tp,
               " Lot:", lot, " Score:", score);
      }
   }
}

//====================================================================
//  ★ GESTIÓN DE TRADES QQ – SISTEMA 10 CAPAS (MEJORADO)
//====================================================================
void ManageOpenTrades()
{
   double totalPnL = 0;
   int    count    = 0;
   double dayPnL   = AccountInfoDouble(ACCOUNT_BALANCE) - g_dayStartBal;

   // ── CAPA 0: Stop/Target diario global (incluye ORB en el PnL total del día) ──
   if(dayPnL >= g_dailyProfitUSD)
   {
      CloseAllMagic();
      // También cerrar ORB si target alcanzado (proteger ganancias del día)
      CloseAllORB("Target diario alcanzado");
      g_dayInvalid = true;
      Print("🎯 TARGET DIARIO $", dayPnL);
      return;
   }
   if(dayPnL <= -g_dailyLossUSD)
   {
      CloseAllMagic();
      CloseAllORB("Stop diario alcanzado");
      g_dayInvalid = true;
      Print("🛑 STOP DIARIO $", dayPnL);
      return;
   }

   double rsiM5[1], fM5[1], sM5[1], tM5[1], atrM5[1];
   bool hR = (CopyBuffer(hRSI_M5,     0, 0, 1, rsiM5) > 0);
   bool hE = (CopyBuffer(hFastEMA_M5, 0, 0, 1, fM5)   > 0 &&
              CopyBuffer(hSlowEMA_M5, 0, 0, 1, sM5)   > 0 &&
              CopyBuffer(hTrendEMA_M5,0, 0, 1, tM5)   > 0);
   bool hA = (CopyBuffer(hATR_M5,     0, 0, 1, atrM5) > 0);
   if(hA && atrM5[0] > 0) g_atr_cached = atrM5[0];

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      double profit    = PositionGetDouble(POSITION_PROFIT);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL     = PositionGetDouble(POSITION_SL);
      double curTP     = PositionGetDouble(POSITION_TP);
      double volume    = PositionGetDouble(POSITION_VOLUME);
      bool   isBuy     = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      datetime tOpen   = (datetime)PositionGetInteger(POSITION_TIME);
      double curPrice  = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                               : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      totalPnL += profit;
      count++;

      // ── CAPA 1: Cierre por tiempo SI está en ganancia ──
      int barsM1 = (int)((TimeCurrent() - tOpen) / PeriodSeconds(PERIOD_M1));
      if(barsM1 >= g_maxBarsOpen && profit > 0)
      {
         trade.PositionClose(ticket); RemoveTradeTracker(ticket);
         Print("⏱️ Cierre tiempo+ganancia: ", barsM1, " barras | $", profit);
         continue;
      }

      // ── CAPA 2: Cierre inteligente en pérdida (tendencia+RSI invertidos) ──
      if(InpSmartExitOn && profit < 0)
      {
         bool trendWrong = false, momWrong = false;
         if(hE) trendWrong = isBuy ? (curPrice < tM5[0]) : (curPrice > tM5[0]);
         if(hR) momWrong   = isBuy ? (rsiM5[0] < 38.0)  : (rsiM5[0] > 62.0);
         if(trendWrong && momWrong)
         {
            trade.PositionClose(ticket); RemoveTradeTracker(ticket);
            Print("🧠 Cierre inteligente (pérdida controlada): $", profit);
            continue;
         }
      }

      // ── CAPA 3: Cierre por pérdida de momentum EN GANANCIA ──
      if(InpMomentumExitOn && profit > 0 && hE)
      {
         bool momLost = isBuy ? (fM5[0] < sM5[0]) : (fM5[0] > sM5[0]);
         if(momLost)
         {
            trade.PositionClose(ticket); RemoveTradeTracker(ticket);
            Print("⚡ Cierre momentum perdido (ganancia): $", profit);
            continue;
         }
      }

      // ── CAPA 4: Cierre BB Mid adverso en ganancia (VWAP proxy) ──
      if(profit > 0 && g_bbMid_cached > 0)
      {
         bool adverse = isBuy ? (curPrice < g_bbMid_cached && openPrice > g_bbMid_cached)
                              : (curPrice > g_bbMid_cached && openPrice < g_bbMid_cached);
         if(adverse)
         {
            trade.PositionClose(ticket); RemoveTradeTracker(ticket);
            Print("🔀 Cierre BB Mid adverso: $", profit);
            continue;
         }
      }

      // ── CAPA 5: Barras negativas prolongadas con tendencia adversa ──
      if(profit < 0 && g_maxNegBars > 0)
      {
         int idx = FindTradeTracker(ticket);
         if(idx >= 0)
         {
            int barsM5n = (int)((TimeCurrent() - g_openTrades[idx].openTime) / PeriodSeconds(PERIOD_M5));
            if(barsM5n >= g_maxNegBars && hE)
            {
               bool tAdv = isBuy ? (fM5[0] < tM5[0]) : (fM5[0] > tM5[0]);
               if(tAdv)
               {
                  trade.PositionClose(ticket); RemoveTradeTracker(ticket);
                  Print("⏰ Cierre negativo prolongado (", barsM5n, " barras M5): $", profit);
                  continue;
               }
            }
         }
      }

      // ── CAPA 6: Cierre parcial progresivo ──
      if(InpPartialClose && ticket == GetOldestMagicTicket())
      {
         double slDist = MathAbs(openPrice - curSL);
         double moveR  = (slDist > 0) ? MathAbs(curPrice - openPrice) / slDist : 0;

         if(!g_partial1Done && moveR >= 1.0)
         {
            double cv = NormLot(volume * g_partialAt1R);
            double minV = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
            if(cv >= minV) trade.PositionClosePartial(ticket, cv);
            if(!g_beMoved)
            {
               double newSL = isBuy ? openPrice + _Point : openPrice - _Point;
               trade.PositionModify(ticket, newSL, curTP);
               g_beMoved = true;
            }
            g_partial1Done = true;
            Print("💰 Parcial 1 (", g_partialAt1R*100, "%) @ 1R | BE activado");
         }
         if(!g_partial2Done && moveR >= 2.0 && g_partial1Done)
         {
            double cv2 = NormLot(volume * g_partialAt2R);
            double minV = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
            if(cv2 >= minV) trade.PositionClosePartial(ticket, cv2);
            g_partial2Done = true;
            Print("💰 Parcial 2 (", g_partialAt2R*100, "%) @ 2R");
         }
      }

      // ── CAPA 7: Trailing Stop ATR ──
      if(InpTrailingOn) ApplyTrailing(ticket, isBuy);

      // ── CAPA 8 (NUEVA): Break-even automático a 0.5R si se detecta reversión ──
      if(!g_beMoved && hE && hR && curSL > 0)
      {
         double slDist  = MathAbs(openPrice - curSL);
         double moveR   = (slDist > 0) ? MathAbs(curPrice - openPrice) / slDist : 0;
         bool revSignal = isBuy ? (fM5[0] < sM5[0] && rsiM5[0] < 50.0)
                                : (fM5[0] > sM5[0] && rsiM5[0] > 50.0);
         if(moveR >= 0.5 && revSignal)
         {
            double newSL = isBuy ? openPrice + _Point : openPrice - _Point;
            if((isBuy && newSL > curSL) || (!isBuy && (newSL < curSL || curSL == 0)))
            {
               trade.PositionModify(ticket, newSL, curTP);
               g_beMoved = true;
               Print("🛡️ Break-even anticipado a 0.5R por señal de reversión");
            }
         }
      }

      // ── CAPA 9 (NUEVA): RSI extremo en posición abierta — cierre profiláctico ──
      if(InpSmartExitOn && profit > 0 && hR)
      {
         bool rsiExtreme = isBuy ? (rsiM5[0] > 78.0) : (rsiM5[0] < 22.0);
         if(rsiExtreme)
         {
            trade.PositionClose(ticket); RemoveTradeTracker(ticket);
            Print("🔥 Cierre RSI extremo (sobreextensión): $", profit);
            continue;
         }
      }
   }

   // ── CAPA 10: Peak Profit Lock global (protege el máximo flotante) ──
   if(count > 0)
   {
      if(totalPnL > g_peakProfit) g_peakProfit = totalPnL;
      if(g_peakProfit >= g_minProfitLock &&
         totalPnL < (g_peakProfit - g_profitRetrace))
      {
         CloseAllMagic();
         Print("💰 Peak Profit Lock: Peak=$", g_peakProfit, " PnL=$", totalPnL);
      }
   }
   else g_peakProfit = 0;
}

//====================================================================
//  TRAILING STOP ATR
//====================================================================
void ApplyTrailing(ulong ticket, bool isBuy)
{
   if(!PositionSelectByTicket(ticket)) return;
   double curSL     = PositionGetDouble(POSITION_SL);
   double curTP     = PositionGetDouble(POSITION_TP);
   double curPrice  = PositionGetDouble(POSITION_PRICE_CURRENT);
   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double atr       = (g_atr_cached > 0) ? g_atr_cached : 10 * _Point * 10;
   double trail     = atr * g_trailingMult;

   if(isBuy)
   {
      if(curPrice <= openPrice) return;
      double newSL = curPrice - trail;
      if(newSL > curSL + _Point && newSL >= openPrice - _Point)
         trade.PositionModify(ticket, newSL, curTP);
   }
   else
   {
      if(curPrice >= openPrice) return;
      double newSL = curPrice + trail;
      if((newSL < curSL - _Point || curSL == 0) && newSL <= openPrice + _Point)
         trade.PositionModify(ticket, newSL, curTP);
   }
}

//====================================================================
//  ★★★ MOTOR LONDON ORB (S2) — ESTRATEGIA INTEGRADA ★★★
//====================================================================

//--------------------------------------------------------------------
//  Reset diario del estado ORB
//--------------------------------------------------------------------
void ORBDailyReset()
{
   g_orbRangeHigh      = 0;
   g_orbRangeLow       = DBL_MAX;
   g_orbRangeBars      = 0;
   g_orbRangeBuilt     = false;
   g_orbTradeTriggered = false;
   g_orbTradeOpenTime  = 0;
   g_orbWinsToday      = 0;
   g_orbLossesToday    = 0;
   g_orbWonToday       = 0;
   g_orbLostToday      = 0;
   ORBDeleteDrawings();
   Print("ORB: Estado diario reiniciado.");
}

//--------------------------------------------------------------------
//  Motor principal London ORB — se llama desde OnTick
//--------------------------------------------------------------------
void RunLondonORB()
{
   // ORB opera en M1 — verificar solo en nueva barra M1 para eficiencia
   static datetime lastBarORB = 0;
   datetime curBar = iTime(_Symbol, PERIOD_M1, 0);
   if(curBar == lastBarORB) return;
   lastBarORB = curBar;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int hour   = dt.hour;
   int minute = dt.min;
   datetime today = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));

   // Reset diario propio del ORB
   if(today != g_orbLastResetDate)
   {
      ORBDailyReset();
      g_orbLastResetDate = today;
   }

   // ── Fase 1: Construir rango 07:00 – 07:59 UTC ──
   if(hour == InpORBRangeHStart && minute >= 0 && minute <= 59)
   {
      double hi = iHigh(_Symbol, PERIOD_M1, 1);
      double lo = iLow(_Symbol,  PERIOD_M1, 1);
      if(hi > g_orbRangeHigh) g_orbRangeHigh = hi;
      if(lo < g_orbRangeLow)  g_orbRangeLow  = lo;
      g_orbRangeBars++;
   }

   // ── Fase 2: Validar rango a las 08:00:00 ──
   if(hour == InpORBTradeHStart && minute == 0 && !g_orbRangeBuilt && g_orbRangeBars > 0)
   {
      double rngSize = g_orbRangeHigh - g_orbRangeLow;
      if(g_orbRangeBars < InpORBMinBars)
      {
         Print("ORB: Rango inválido — barras insuficientes (", g_orbRangeBars,
               " < ", InpORBMinBars, ")");
         return;
      }
      if(rngSize < InpORBRangeMinPts || rngSize > InpORBRangeMaxPts)
      {
         Print("ORB: Rango inválido — tamaño ", DoubleToString(rngSize, 2),
               " fuera de [", InpORBRangeMinPts, ",", InpORBRangeMaxPts, "]");
         return;
      }
      g_orbRangeBuilt = true;
      Print("ORB: Rango válido — HIGH=", DoubleToString(g_orbRangeHigh, 2),
            " LOW=", DoubleToString(g_orbRangeLow, 2),
            " SIZE=", DoubleToString(rngSize, 2),
            " BARS=", g_orbRangeBars);
      ORBDrawRangeLines();
   }

   // ── Fase 3: Buscar entrada 08:00 – 09:59 ──
   if(!g_orbRangeBuilt || g_orbTradeTriggered) return;
   if(hour < InpORBTradeHStart || hour > InpORBTradeHEnd) return;

   // Verificar stop diario — ORB respeta el límite global del día
   double dayPnL = AccountInfoDouble(ACCOUNT_BALANCE) - g_dayStartBal;
   if(dayPnL <= -g_dailyLossUSD)
   {
      Print("ORB: Stop diario activo — sin nuevas entradas.");
      return;
   }

   // Verificar spread
   long spreadPts = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spreadPts > InpORBMaxSpread)
   {
      Print("ORB: Spread demasiado alto (", spreadPts, " > ", InpORBMaxSpread, "). Skip.");
      return;
   }

   // Sesgo EMA en M1
   double emaFastBuf[1], emaSlowBuf[1];
   ArraySetAsSeries(emaFastBuf, true);
   ArraySetAsSeries(emaSlowBuf, true);
   if(CopyBuffer(hORB_EmaFast, 0, 1, 1, emaFastBuf) <= 0) return;
   if(CopyBuffer(hORB_EmaSlow, 0, 1, 1, emaSlowBuf) <= 0) return;

   bool biasUp   = (emaFastBuf[0] > emaSlowBuf[0]);
   bool biasDown = (emaFastBuf[0] < emaSlowBuf[0]);

   // Confirmación adicional: sesgo D1 debe estar alineado con el ORB
   // (evita trades contra la tendencia macro del oro)
   bool macroBullish = g_sesgoUp || (!g_sesgoDn); // permisivo: si D1 no es bajista
   bool macroBearish = g_sesgoDn || (!g_sesgoUp);

   double closePrice = iClose(_Symbol, PERIOD_M1, 1);

   // ── LONG: ruptura alcista ──
   if(closePrice > g_orbRangeHigh + InpORBBreakBuf && biasUp && macroBullish)
   {
      double entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl    = g_orbRangeLow - InpORBSLBuffer;
      double risk  = entry - sl;
      double tp    = entry + risk * InpORBRR;

      if(risk <= 0)
      {
         Print("ORB Long: riesgo inválido. Entry=", entry, " SL=", sl);
         return;
      }

      double lots = ORBCalcLots(risk);
      if(lots <= 0) return;

      // Usar magic independiente para el ORB
      trade.SetExpertMagicNumber(InpMagicORB);
      if(trade.Buy(lots, _Symbol, entry, sl, tp, "S2_LondonORB"))
      {
         g_orbTradeTriggered = true;
         g_orbTradeOpenTime  = TimeCurrent();
         Print("✅ ORB LONG @ ", DoubleToString(entry, 2),
               " SL=", DoubleToString(sl, 2),
               " TP=", DoubleToString(tp, 2),
               " Lots=", lots,
               " Risk=", DoubleToString(risk, 2), " pts");
         ORBDrawEntryLines(entry, sl, tp, true);
      }
      else
         Print("ORB Long error: ", trade.ResultRetcodeDescription());

      // Restaurar magic QQ
      trade.SetExpertMagicNumber(InpMagic);
   }
   // ── SHORT: ruptura bajista ──
   else if(closePrice < g_orbRangeLow - InpORBBreakBuf && biasDown && macroBearish)
   {
      double entry = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl    = g_orbRangeHigh + InpORBSLBuffer;
      double risk  = sl - entry;
      double tp    = entry - risk * InpORBRR;

      if(risk <= 0)
      {
         Print("ORB Short: riesgo inválido. Entry=", entry, " SL=", sl);
         return;
      }

      double lots = ORBCalcLots(risk);
      if(lots <= 0) return;

      trade.SetExpertMagicNumber(InpMagicORB);
      if(trade.Sell(lots, _Symbol, entry, sl, tp, "S2_LondonORB"))
      {
         g_orbTradeTriggered = true;
         g_orbTradeOpenTime  = TimeCurrent();
         Print("✅ ORB SHORT @ ", DoubleToString(entry, 2),
               " SL=", DoubleToString(sl, 2),
               " TP=", DoubleToString(tp, 2),
               " Lots=", lots,
               " Risk=", DoubleToString(risk, 2), " pts");
         ORBDrawEntryLines(entry, sl, tp, false);
      }
      else
         Print("ORB Short error: ", trade.ResultRetcodeDescription());

      trade.SetExpertMagicNumber(InpMagic);
   }
}

//--------------------------------------------------------------------
//  Gestión de tiempo y trailing para posiciones ORB
//--------------------------------------------------------------------
void ManageORBTrades()
{
   // Solo se ejecuta si hay posición ORB activa
   if(!g_orbTradeTriggered) return;

   // Verificar si la posición ORB sigue abierta
   bool positionOpen = false;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicORB) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      positionOpen    = true;
      double profit   = PositionGetDouble(POSITION_PROFIT);
      double curSL    = PositionGetDouble(POSITION_SL);
      double curTP    = PositionGetDouble(POSITION_TP);
      double openPrice= PositionGetDouble(POSITION_PRICE_OPEN);
      double volume   = PositionGetDouble(POSITION_VOLUME);
      bool   isBuy    = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double curPrice = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                              : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      // ── Cierre por tiempo ──
      if(g_orbTradeOpenTime > 0)
      {
         int minutesOpen = (int)((TimeCurrent() - g_orbTradeOpenTime) / 60);
         if(minutesOpen >= InpORBMaxMinutes)
         {
            trade.SetExpertMagicNumber(InpMagicORB);
            trade.PositionClose(ticket);
            trade.SetExpertMagicNumber(InpMagic);
            Print("ORB: Cierre por tiempo (", InpORBMaxMinutes, " min) | P&L=$", profit);
            positionOpen = false;
            continue;
         }
      }

      // ── Trailing stop para ORB (ATR M5 compartido) ──
      // Se activa solo cuando la posición está en ganancia
      if(InpTrailingOn && g_atr_cached > 0 && profit > 0)
      {
         double trail = g_atr_cached * g_trailingMult;
         trade.SetExpertMagicNumber(InpMagicORB);
         if(isBuy)
         {
            double newSL = curPrice - trail;
            if(newSL > curSL + _Point && newSL >= openPrice - _Point)
               trade.PositionModify(ticket, newSL, curTP);
         }
         else
         {
            double newSL = curPrice + trail;
            if((newSL < curSL - _Point || curSL == 0) && newSL <= openPrice + _Point)
               trade.PositionModify(ticket, newSL, curTP);
         }
         trade.SetExpertMagicNumber(InpMagic);
      }

      // ── Cierre parcial ORB al 1R (asegurar la mitad de la posición) ──
      // Solo disponible en modos MEDIUM y STANDARD
      if(InpPartialClose && g_capMode >= CAP_MEDIUM && curSL > 0)
      {
         double slDist = MathAbs(openPrice - curSL);
         double moveR  = (slDist > 0) ? MathAbs(curPrice - openPrice) / slDist : 0;
         if(moveR >= 1.0)
         {
            double minVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
            double halfVol = NormLot(volume * 0.50);
            if(halfVol >= minVol)
            {
               // Cierre parcial solo una vez (flag temporal en apertura de barra)
               static datetime lastPartialBar = 0;
               datetime curBar = iTime(_Symbol, PERIOD_M5, 0);
               if(curBar != lastPartialBar)
               {
                  trade.SetExpertMagicNumber(InpMagicORB);
                  trade.PositionClosePartial(ticket, halfVol);
                  trade.SetExpertMagicNumber(InpMagic);
                  // Mover SL a breakeven
                  double newSL = isBuy ? openPrice + _Point : openPrice - _Point;
                  if((isBuy && newSL > curSL) || (!isBuy && newSL < curSL))
                  {
                     trade.SetExpertMagicNumber(InpMagicORB);
                     trade.PositionModify(ticket, newSL, curTP);
                     trade.SetExpertMagicNumber(InpMagic);
                  }
                  lastPartialBar = curBar;
                  Print("💰 ORB Parcial 50% @ 1R | BE activado | P&L=$", profit);
               }
            }
         }
      }
   }
}

//--------------------------------------------------------------------
//  Lotaje ORB — basado en el mismo sistema de riesgo del bot
//--------------------------------------------------------------------
double ORBCalcLots(double riskPts)
{
   double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
   // ORB usa el mismo % de riesgo del capital pero con reducción del 10%
   // para no solapar excesivamente el riesgo con posibles trades QQ activos
   double riskFactor = (CountOpenPositions() > 0) ? 0.50 : 1.0;
   double riskAmount = balance * g_riskPct / 100.0 * riskFactor;

   double tickValue  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double pointValue = tickValue / tickSize * _Point;

   if(pointValue <= 0 || riskPts <= 0) return 0;

   double riskPoints = riskPts / _Point;
   double lots       = riskAmount / (riskPoints * pointValue);

   // En micro: nunca superar lote mínimo × 2
   if(g_capMode == CAP_MICRO)
      lots = MathMin(lots, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN) * 2.0);

   return NormLot(lots);
}

//--------------------------------------------------------------------
//  Cerrar todas las posiciones ORB
//--------------------------------------------------------------------
void CloseAllORB(string reason)
{
   Print("ORB: Cerrando posición por: ", reason);
   trade.SetExpertMagicNumber(InpMagicORB);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) == InpMagicORB &&
         PositionGetString(POSITION_SYMBOL) == _Symbol)
         trade.PositionClose(ticket);
   }
   trade.SetExpertMagicNumber(InpMagic);
}

//====================================================================
//  TRACKING DE TRADES CERRADOS
//====================================================================
void TrackClosedTrades()
{
   static int histCount = 0;
   int total = HistoryDealsTotal();
   if(total == histCount) return;

   for(int i = histCount; i < total; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;

      long magic = (long)HistoryDealGetInteger(ticket, DEAL_MAGIC);
      ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT) continue;

      double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);

      if(magic == InpMagic)
      {
         if(profit > 0) { g_winsToday++; g_totalWon += profit; }
         else if(profit < 0) { g_lossesToday++; g_totalLost += MathAbs(profit); }
      }
      else if(magic == InpMagicORB)
      {
         if(profit > 0) { g_orbWinsToday++; g_orbWonToday += profit; }
         else if(profit < 0) { g_orbLossesToday++; g_orbLostToday += MathAbs(profit); }
      }
   }
   histCount = total;
}

//====================================================================
//  HELPERS QQ
//====================================================================
void RegisterTrade(ulong ticket)
{
   if(ticket == 0 || g_openTradeCount >= 50) return;
   g_openTrades[g_openTradeCount].ticket   = ticket;
   g_openTrades[g_openTradeCount].openTime = TimeCurrent();
   g_openTradeCount++;
}

int FindTradeTracker(ulong ticket)
{
   for(int i = 0; i < g_openTradeCount; i++)
      if(g_openTrades[i].ticket == ticket) return i;
   return -1;
}

void RemoveTradeTracker(ulong ticket)
{
   for(int i = 0; i < g_openTradeCount; i++)
   {
      if(g_openTrades[i].ticket == ticket)
      {
         for(int j = i; j < g_openTradeCount - 1; j++)
            g_openTrades[j] = g_openTrades[j+1];
         g_openTradeCount--;
         return;
      }
   }
}

int CountOpenPositions()
{
   int cnt = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong t = PositionGetTicket(i);
      if(PositionSelectByTicket(t) && PositionGetInteger(POSITION_MAGIC) == InpMagic) cnt++;
   }
   return cnt;
}

ulong GetOldestMagicTicket()
{
   ulong oldest = 0; datetime ot = TimeCurrent();
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong t = PositionGetTicket(i);
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      datetime tt = (datetime)PositionGetInteger(POSITION_TIME);
      if(oldest == 0 || tt < ot) { oldest = t; ot = tt; }
   }
   return oldest;
}

void CloseAllMagic()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(PositionSelectByTicket(t) && PositionGetInteger(POSITION_MAGIC) == InpMagic)
      {
         trade.PositionClose(t);
         RemoveTradeTracker(t);
      }
   }
}

double NormLot(double lot)
{
   double mn = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double mx = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double st = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lot = MathFloor(lot / st) * st;
   return MathMax(mn, MathMin(mx, lot));
}

//====================================================================
//  GRÁFICOS ORB
//====================================================================
void ORBDrawRangeLines()
{
   ObjectDelete(0, "ORB_HIGH"); ObjectDelete(0, "ORB_LOW");
   ObjectDelete(0, "ORB_BULL"); ObjectDelete(0, "ORB_BEAR");

   ObjectCreate(0, "ORB_HIGH", OBJ_HLINE, 0, 0, g_orbRangeHigh);
   ObjectSetInteger(0, "ORB_HIGH", OBJPROP_COLOR, clrDodgerBlue);
   ObjectSetInteger(0, "ORB_HIGH", OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, "ORB_HIGH", OBJPROP_WIDTH, 1);
   ObjectSetString(0,  "ORB_HIGH", OBJPROP_TEXT, "ORB HIGH: " + DoubleToString(g_orbRangeHigh, 2));

   ObjectCreate(0, "ORB_LOW", OBJ_HLINE, 0, 0, g_orbRangeLow);
   ObjectSetInteger(0, "ORB_LOW", OBJPROP_COLOR, clrOrangeRed);
   ObjectSetInteger(0, "ORB_LOW", OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, "ORB_LOW", OBJPROP_WIDTH, 1);
   ObjectSetString(0,  "ORB_LOW", OBJPROP_TEXT, "ORB LOW: " + DoubleToString(g_orbRangeLow, 2));

   ObjectCreate(0, "ORB_BULL", OBJ_HLINE, 0, 0, g_orbRangeHigh + InpORBBreakBuf);
   ObjectSetInteger(0, "ORB_BULL", OBJPROP_COLOR, clrLimeGreen);
   ObjectSetInteger(0, "ORB_BULL", OBJPROP_STYLE, STYLE_DOT);
   ObjectSetString(0,  "ORB_BULL", OBJPROP_TEXT, "TRIGGER LONG: " + DoubleToString(g_orbRangeHigh + InpORBBreakBuf, 2));

   ObjectCreate(0, "ORB_BEAR", OBJ_HLINE, 0, 0, g_orbRangeLow - InpORBBreakBuf);
   ObjectSetInteger(0, "ORB_BEAR", OBJPROP_COLOR, clrRed);
   ObjectSetInteger(0, "ORB_BEAR", OBJPROP_STYLE, STYLE_DOT);
   ObjectSetString(0,  "ORB_BEAR", OBJPROP_TEXT, "TRIGGER SHORT: " + DoubleToString(g_orbRangeLow - InpORBBreakBuf, 2));

   ChartRedraw();
}

void ORBDrawEntryLines(double entry, double sl, double tp, bool isLong)
{
   string prefix = isLong ? "LONG" : "SHORT";
   ObjectDelete(0, "ORB_ENTRY"); ObjectDelete(0, "ORB_SL"); ObjectDelete(0, "ORB_TP");

   ObjectCreate(0, "ORB_ENTRY", OBJ_HLINE, 0, 0, entry);
   ObjectSetInteger(0, "ORB_ENTRY", OBJPROP_COLOR, clrGold);
   ObjectSetInteger(0, "ORB_ENTRY", OBJPROP_WIDTH, 2);
   ObjectSetString(0,  "ORB_ENTRY", OBJPROP_TEXT, prefix + " ENTRY: " + DoubleToString(entry, 2));

   ObjectCreate(0, "ORB_SL", OBJ_HLINE, 0, 0, sl);
   ObjectSetInteger(0, "ORB_SL", OBJPROP_COLOR, clrRed);
   ObjectSetInteger(0, "ORB_SL", OBJPROP_WIDTH, 2);
   ObjectSetString(0,  "ORB_SL", OBJPROP_TEXT, "ORB SL: " + DoubleToString(sl, 2));

   ObjectCreate(0, "ORB_TP", OBJ_HLINE, 0, 0, tp);
   ObjectSetInteger(0, "ORB_TP", OBJPROP_COLOR, clrLimeGreen);
   ObjectSetInteger(0, "ORB_TP", OBJPROP_WIDTH, 2);
   ObjectSetString(0,  "ORB_TP", OBJPROP_TEXT, "ORB TP: " + DoubleToString(tp, 2));

   ChartRedraw();
}

void ORBDeleteDrawings()
{
   string names[] = {"ORB_HIGH","ORB_LOW","ORB_BULL","ORB_BEAR","ORB_ENTRY","ORB_SL","ORB_TP"};
   for(int i = 0; i < ArraySize(names); i++) ObjectDelete(0, names[i]);
   ChartRedraw();
}

//====================================================================
//  ★ PANEL UNIFICADO – QQ + ORB
//====================================================================
void DrawPanel()
{
   if(!InpShowPanel) return;
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);

   // Posiciones QQ
   int    posQQ = 0; double pnlQQ = 0, volQQ = 0;
   // Posiciones ORB
   int    posORB = 0; double pnlORB = 0;

   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong t = PositionGetTicket(i);
      if(!PositionSelectByTicket(t)) continue;
      long magic = (long)PositionGetInteger(POSITION_MAGIC);
      if(magic == InpMagic)
      {
         posQQ++; pnlQQ += PositionGetDouble(POSITION_PROFIT);
         volQQ += PositionGetDouble(POSITION_VOLUME);
      }
      else if(magic == InpMagicORB)
      {
         posORB++; pnlORB += PositionGetDouble(POSITION_PROFIT);
      }
   }

   double dayPnL  = AccountInfoDouble(ACCOUNT_BALANCE) - g_dayStartBal;
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);

   // Estadísticas QQ
   int    totalQQ = g_winsToday + g_lossesToday;
   double wrQQ    = totalQQ > 0 ? (100.0 * g_winsToday / totalQQ) : 0;
   double pfQQ    = g_totalLost > 0 ? g_totalWon / g_totalLost : 0;

   // Estadísticas ORB
   int    totalORB = g_orbWinsToday + g_orbLossesToday;
   double wrORB    = totalORB > 0 ? (100.0 * g_orbWinsToday / totalORB) : 0;

   string estadoQQ = g_dayInvalid    ? "❌ PAUSADO"      :
                     !g_initialized  ? "⏳ CONSTRUYENDO" :
                     g_triggered     ? "✅ OPERANDO"     : "🎯 VIGILANDO";

   string estadoORB = !InpLondonORBOn     ? "⬜ DESACTIVADO"  :
                      g_orbTradeTriggered  ? "✅ TRADE HOY"    :
                      g_orbRangeBuilt      ? "🎯 ESPERANDO RUP":
                      (dt.hour == 7)       ? "📐 CONSTRUYENDO" : "⏳ ESPERA 07:00";

   // Rango ORB legible
   string orbRangeStr = "---";
   if(g_orbRangeHigh > 0 && g_orbRangeLow < DBL_MAX)
      orbRangeStr = DoubleToString(g_orbRangeHigh, 2) + "/" + DoubleToString(g_orbRangeLow, 2);

   string txt = "";
   txt += "══ QQ ULTIMATE v6.0 – LONDON EDITION ══\n";
   txt += StringFormat("Hora     : %02d:%02d | Modo: %s\n", dt.hour, dt.min, CapModeStr());
   txt += StringFormat("Balance  : $%.2f | PnL Día: $%.2f\n", balance, dayPnL);
   txt += StringFormat("Target   : $%.2f | Stop: $%.2f\n", g_dailyProfitUSD, g_dailyLossUSD);
   txt += StringFormat("Sesgo D1 : %s | H1: %s\n",
          g_sesgoUp ? "📈ALCISTA" : (g_sesgoDn ? "📉BAJISTA" : "---"),
          g_h1Up    ? "↑UP"      : (g_h1Dn    ? "↓DOWN"    : "=FLAT"));
   txt += "────── ESTRATEGIA QQ ──────\n";
   txt += StringFormat("Estado   : %s\n", estadoQQ);
   txt += StringFormat("Rango QQ : H=%.2f L=%.2f\n", g_rangeHigh, g_rangeLow);
   txt += StringFormat("Trades   : %d/%d | Pirámide: +%d\n",
          g_tradesToday, g_maxTradesDay, g_pyramidLevel);
   txt += StringFormat("Pos QQ   : %d | Vol: %.2f | PnL: $%.2f\n", posQQ, volQQ, pnlQQ);
   txt += StringFormat("BE: %s | P1:%s | P2:%s\n",
          g_beMoved?"✅":"⬜", g_partial1Done?"✅":"⬜", g_partial2Done?"✅":"⬜");
   txt += StringFormat("W:%d L:%d WR:%.1f%% | Ganado:$%.2f PF:%.2f\n",
          g_winsToday, g_lossesToday, wrQQ, g_totalWon, pfQQ);
   txt += "────── ESTRATEGIA LONDON ORB ──────\n";
   txt += StringFormat("Estado   : %s\n", estadoORB);
   txt += StringFormat("Rango ORB: %s | Barras: %d\n", orbRangeStr, g_orbRangeBars);
   txt += StringFormat("Pos ORB  : %d | PnL: $%.2f\n", posORB, pnlORB);
   txt += StringFormat("W:%d L:%d WR:%.1f%% | Ganado:$%.2f\n",
          g_orbWinsToday, g_orbLossesToday, wrORB, g_orbWonToday);
   txt += "────── SISTEMA DE CIERRES ──────\n";
   txt += StringFormat("Trailing:%s Parcial:%s Smart:%s Mom:%s\n",
          InpTrailingOn?"✅":"⬜", InpPartialClose?"✅":"⬜",
          InpSmartExitOn?"✅":"⬜", InpMomentumExitOn?"✅":"⬜");
   txt += StringFormat("PeakLock:$%.2f | ATR:%.4f | Risk:%.1f%%\n",
          g_peakProfit, g_atr_cached, g_riskPct);

   Comment(txt);
}

//====================================================================
//  EVENTO CIERRE DE DEALS (log extendido)
//====================================================================
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest     &request,
                        const MqlTradeResult      &result)
{
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      if(HistoryDealSelect(trans.deal))
      {
         long magic   = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
         long entry   = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
         double profit= HistoryDealGetDouble(trans.deal, DEAL_PROFIT);

         if(entry == DEAL_ENTRY_OUT)
         {
            string src = (magic == InpMagicORB) ? "[ORB]" : "[QQ]";
            Print(src, " CIERRE: P&L=$", DoubleToString(profit, 2),
                  (profit >= 0 ? " ✅ WIN" : " ❌ LOSS"));
         }
      }
   }
}

//+------------------------------------------------------------------+
//  FIN – QQ ULTIMATE v6.0 LONDON EDITION
//+------------------------------------------------------------------+
