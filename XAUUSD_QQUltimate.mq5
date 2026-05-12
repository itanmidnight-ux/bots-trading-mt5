//+------------------------------------------------------------------+
//|  XAUUSD QUANTUM QUEEN ULTIMATE v5.0 – SMART CAPITAL EDITION     |
//|  Auto-detección de capital | Micro/Mini/Standard Accounts        |
//|  Estrategias: Range Breakout | EMA Scalper | Pyramid | Retest   |
//|  Timeframes análisis: D1/H1/M15 | Ejecución: M5/M1              |
//+------------------------------------------------------------------+
#property copyright "QQ Ultimate v5.0 – Smart Capital"
#property version   "5.00"
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
//  INPUTS – Solo los que el usuario puede querer personalizar
//====================================================================

input group "=== GESTIÓN DE CAPITAL ==="
input bool   InpAutoCapital     = true;    // Detectar capital automáticamente
input double InpRiskPercent     = 0.8;     // % riesgo base por trade (ajustado por modo)
input double InpLotFixed        = 0.01;    // Lote fijo (si auto=false)
input int    InpMagic           = 5900;    // Magic number

input group "=== ESTRATEGIA BREAKOUT ==="
input int    InpRangeHourStart  = 7;       // Hora inicio rango
input int    InpRangeHourEnd    = 8;       // Hora fin rango
input int    InpBreakoutHourEnd = 10;      // Hora fin ventana breakout
input double InpRangeMinPts     = 1.5;    // Tamaño mínimo rango (pts)
input double InpRangeMaxPts     = 12.0;   // Tamaño máximo rango (pts)
input double InpBreakoutOffset  = 0.20;   // Offset ruptura (pts)
input double InpRR              = 2.2;     // R:R ratio

input group "=== ESTRATEGIA EMA SCALPER ==="
input bool   InpScalperOn       = true;    // Activar Scalper EMA M1/M5
input int    InpScalperHourStart= 8;       // Hora inicio scalper
input int    InpScalperHourEnd  = 20;      // Hora fin scalper
input int    InpFastEMA         = 9;       // EMA rápida
input int    InpSlowEMA         = 21;      // EMA lenta
input int    InpTrendEMA        = 50;      // EMA tendencia

input group "=== SL/TP DINÁMICO ==="
input double InpATR_SL_Mult     = 1.3;    // Multiplicador ATR para SL
input double InpATR_TP_Mult     = 2.6;    // Multiplicador ATR para TP

input group "=== SISTEMA PIRAMIDAL ==="
input bool   InpPyramidOn       = true;    // Activar pirámide
input int    InpPyramidLevels   = 2;       // Niveles adicionales

input group "=== CIERRES AUTOMÁTICOS ==="
input bool   InpTrailingOn      = true;    // Trailing stop ATR
input bool   InpPartialClose    = true;    // Cierre parcial progresivo
input bool   InpSmartExitOn     = true;    // Salida inteligente por indicadores
input bool   InpMomentumExitOn  = true;    // Cierre por pérdida de momentum
input double InpMinProfitLock   = 0.30;   // Ganancia mín para activar lock ($)

input group "=== PROTECCIONES ==="
input double InpMaxSpread       = 45.0;   // Spread máximo (puntos)

input group "=== INDICADORES ==="
input int    InpBBPeriod        = 20;      // Bollinger Bands período
input int    InpRSIPeriod       = 14;      // RSI período
input int    InpMFIPeriod       = 14;      // MFI período
input int    InpATRPeriod       = 14;      // ATR período

input group "=== MONITOREO ==="
input bool   InpShowPanel       = true;    // Mostrar panel

//====================================================================
//  HANDLES DE INDICADORES
//====================================================================
int hEMA50_D1, hEMA200_D1;
int hRSI_H1,   hATR_H1;
int hBB_M5,    hRSI_M5, hMFI_M5, hATR_M5;
int hFastEMA_M5, hSlowEMA_M5, hTrendEMA_M5;
int hFastEMA_M1, hSlowEMA_M1, hTrendEMA_M1;
int hRSI_M1,   hATR_M1;

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
//  VARIABLES DE ESTADO
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

// Variables winrate tracking
int      g_winsToday     = 0;
int      g_lossesToday   = 0;
double   g_totalWon      = 0;
double   g_totalLost     = 0;

//====================================================================
//  OnInit
//====================================================================
int OnInit()
{
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

   if(hEMA50_D1 == INVALID_HANDLE || hEMA200_D1 == INVALID_HANDLE ||
      hRSI_H1   == INVALID_HANDLE || hBB_M5     == INVALID_HANDLE ||
      hRSI_M5   == INVALID_HANDLE || hATR_M5    == INVALID_HANDLE ||
      hFastEMA_M5 == INVALID_HANDLE || hFastEMA_M1 == INVALID_HANDLE)
   {
      Alert("❌ Error creando handles de indicadores");
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(10);

   g_dayStartBal = AccountInfoDouble(ACCOUNT_BALANCE);
   DetectCapitalMode();
   DailyReset();

   Print("✅ QQ Ultimate v5.0 | Capital: $", DoubleToString(g_dayStartBal, 2),
         " | Modo: ", CapModeStr());
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
}

//====================================================================
//  ★ DETECCIÓN AUTOMÁTICA DE CAPITAL Y CONFIGURACIÓN ÓPTIMA
//====================================================================
void DetectCapitalMode()
{
   if(!InpAutoCapital)
   {
      // Modo manual: usar inputs base
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
      g_partialAt1R    = 0.30; g_partialAt2R    = 0.40;
      return;
   }

   double bal = AccountInfoDouble(ACCOUNT_BALANCE);

   // ── MICRO ACCOUNT < $50 (ej. $14) ──
   if(bal < 50.0)
   {
      g_capMode        = CAP_MICRO;
      // Riesgo ultra controlado: máx 1% por trade con lote mínimo
      g_riskPct        = 1.0;
      // Límites diarios como % del balance (más relevante que USD fijo)
      g_dailyLossUSD   = bal * 0.06;    // Stop si pierde 6% del balance
      g_dailyProfitUSD = bal * 0.15;    // Target 15% diario
      g_minProfitLock  = bal * 0.02;    // Lock desde 2% de ganancia abierta
      g_profitRetrace  = bal * 0.008;   // Cierra si retrocede 0.8%
      // Pirámide desactivada en micro (riesgo demasiado alto con capital mínimo)
      g_pyramidTrig1   = 2.0; g_pyramidTrig2 = 4.0;
      g_pyramidLotMult = 0.5;
      // Trailing más ajustado para proteger ganancias pequeñas
      g_trailingMult   = 0.7;
      // Scalper con R:R más alto para compensar spread
      g_scalperRR      = 2.0;
      // Menos trades para conservar capital
      g_maxTradesDay   = 3;
      g_maxBarsOpen    = 60;   // Cerrar antes en M1
      g_maxNegBars     = 10;
      g_partialAt1R    = 0.40; g_partialAt2R = 0.40; // 80% asegurado
   }
   // ── SMALL ACCOUNT $50-$199 ──
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
   // ── MEDIUM ACCOUNT $200-$999 ──
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
   // ── STANDARD ACCOUNT >= $1000 ──
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
}

string CapModeStr()
{
   if(g_capMode == CAP_MICRO)    return "MICRO (<$50)";
   if(g_capMode == CAP_SMALL)    return "SMALL ($50-199)";
   if(g_capMode == CAP_MEDIUM)   return "MEDIUM ($200-999)";
   return "STANDARD (>=$1000)";
}

//====================================================================
//  OnTick
//====================================================================
void OnTick()
{
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

   ManageOpenTrades();
   TrackClosedTrades();
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
   // Re-detectar capital cada día (puede haber crecido)
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
//  ACTUALIZAR SESGO MULTI-TIMEFRAME
//====================================================================
void UpdateMarketBias()
{
   double ema50[1], ema200[1];
   if(CopyBuffer(hEMA50_D1, 0, 0, 1, ema50)  > 0 &&
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
//  RANGO
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
      Print("⚠️ Rango breakout inválido (size=", rngSize, ") | Scalper activo");
}

//====================================================================
//  OBTENER INDICADORES M5
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
//  ★ FILTROS WINRATE – Multi-confirmación para alta precisión
//====================================================================

// Filtro 1: Tendencia D1 alineada (macro)
bool FilterTrendD1(bool isBuy) { return isBuy ? g_sesgoUp : g_sesgoDn; }

// Filtro 2: Momentum H1 alineado
bool FilterMomentumH1(bool isBuy)
{
   // En micro-accounts: relajar filtro H1 para no perder señales
   if(g_capMode == CAP_MICRO) return true;
   return isBuy ? g_h1Up : g_h1Dn;
}

// Filtro 3: RSI en zona de momentum (no en extremo)
bool FilterRSI(double rsi, bool isBuy)
{
   if(isBuy)  return (rsi > 48.0 && rsi < 72.0);
   else        return (rsi < 52.0 && rsi > 28.0);
}

// Filtro 4: Precio sobre/bajo BB Mid (tendencia M5)
bool FilterBBTrend(double close, double bbM, bool isBuy)
{
   return isBuy ? (close > bbM) : (close < bbM);
}

// Filtro 5: MFI confirma volumen de dinero
bool FilterMFI(double mfi, bool isBuy)
{
   if(g_capMode == CAP_MICRO) return true; // Relajar en micro
   return isBuy ? (mfi > 48.0) : (mfi < 52.0);
}

// Filtro 6: Sesgo alcista estructural del oro
bool FilterGoldBias(double rsi, bool isBuy)
{
   if(isBuy)  return (rsi > 47.0 || g_sesgoUp);
   else        return (!g_sesgoUp && rsi < 50.0);
}

// Filtro 7: ATR mínimo (evitar mercado plano sin movimiento)
bool FilterATRMin(double atr)
{
   // Mercado debe tener volatilidad suficiente para el trade
   double minATR = (g_capMode == CAP_MICRO) ? 0.5 : 0.8;
   return (atr >= minATR * _Point * 100);
}

// Filtro 8: Spread acceptable según modo capital
bool FilterSpread()
{
   double spread = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   double maxSpr = (g_capMode == CAP_MICRO) ? 30.0 : InpMaxSpread;
   return (spread <= maxSpr);
}

// Evaluación global de calidad de señal (score 0-8)
int SignalScore(bool isBuy, double close, double bbM, double rsi, double mfi, double atr)
{
   int score = 0;
   if(FilterTrendD1(isBuy))            score++;
   if(FilterMomentumH1(isBuy))         score++;
   if(FilterRSI(rsi, isBuy))           score++;
   if(FilterBBTrend(close, bbM, isBuy))score++;
   if(FilterMFI(mfi, isBuy))           score++;
   if(FilterGoldBias(rsi, isBuy))      score++;
   if(FilterATRMin(atr))               score++;
   if(FilterSpread())                  score++;
   return score;
}

// Score mínimo requerido según modo capital
int MinScoreRequired()
{
   if(g_capMode == CAP_MICRO)    return 5; // Más permisivo pero con filtros clave
   if(g_capMode == CAP_SMALL)    return 6;
   return 6;
}

//====================================================================
//  CÁLCULO DE LOT DINÁMICO
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

   // En micro-accounts: jamás superar el lote mínimo × 2
   if(g_capMode == CAP_MICRO)
      lot = MathMin(lot, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN) * 2.0);

   return NormLot(lot);
}

//====================================================================
//  CALCULAR SL/TP (ATR-based)
//====================================================================
void CalcSLTP(bool isBuy, double entry, double atr, double &sl, double &tp, double rrMult = 1.0)
{
   double slD = atr * InpATR_SL_Mult;
   double tpD = atr * InpATR_TP_Mult * rrMult;
   // En micro: ampliar ligeramente SL para evitar stop-hunting
   if(g_capMode == CAP_MICRO) slD *= 1.15;
   sl = isBuy ? entry - slD : entry + slD;
   tp = isBuy ? entry + tpD : entry - tpD;
}

//====================================================================
//  BREAKOUT ENTRY
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

   // LONG
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
         Print("🟢 BREAKOUT LONG @ ", ask, " SL:", sl, " TP:", tp,
               " Lot:", lot, " Score:", score);
      }
   }
   // SHORT
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
         Print("🔴 BREAKOUT SHORT @ ", bid, " SL:", sl, " TP:", tp,
               " Lot:", lot, " Score:", score);
      }
   }
}

//====================================================================
//  RETEST ENTRY
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
            Print("🟢 RETEST LONG @ ", ask, " Lot:", lot);
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
            Print("🔴 RETEST SHORT @ ", bid, " Lot:", lot);
         }
      }
   }
}

//====================================================================
//  PIRAMIDAL
//====================================================================
void ManagePyramid()
{
   if(!InpPyramidOn || !g_triggered) return;
   if(g_pyramidLevel >= InpPyramidLevels) return;
   if(g_tradesToday >= g_maxTradesDay) return;
   // Pirámide deshabilitada en micro para proteger capital
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
      sl = masterPrice; // BE
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
//  ★ EMA SCALPER – M5 con confirmación M1
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

   // Cruce M5 nuevo (no estaba cruzado en barra anterior)
   bool crossUpM5   = (fM5[0] > sM5[0]) && (fM5[1] <= sM5[1]);
   bool crossDnM5   = (fM5[0] < sM5[0]) && (fM5[1] >= sM5[1]);
   bool trendUpM5   = (fM5[0] > tM5[0]);
   bool trendDnM5   = (fM5[0] < tM5[0]);
   bool alignUpM1   = (fM1[0] > sM1[0] && fM1[0] > tM1[0]);
   bool alignDnM1   = (fM1[0] < sM1[0] && fM1[0] < tM1[0]);

   bool sigBuy  = crossUpM5 && trendUpM5 && alignUpM1;
   bool sigSell = crossDnM5 && trendDnM5 && alignDnM1;

   if(!sigBuy && !sigSell) return;

   // Score de calidad
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
//  ★ GESTIÓN DE TRADES – SISTEMA DE CIERRE DE 8 CAPAS
//====================================================================
void ManageOpenTrades()
{
   double totalPnL = 0;
   int    count    = 0;
   double dayPnL   = AccountInfoDouble(ACCOUNT_BALANCE) - g_dayStartBal;

   // Stop diario y target
   if(dayPnL >= g_dailyProfitUSD) { CloseAllMagic(); g_dayInvalid = true;
      Print("🎯 TARGET DIARIO $", dayPnL); return; }
   if(dayPnL <= -g_dailyLossUSD)  { CloseAllMagic(); g_dayInvalid = true;
      Print("🛑 STOP DIARIO $", dayPnL); return; }

   // Indicadores para cierre
   double rsiM5[1], fM5[1], sM5[1], tM5[1], atrM5[1];
   bool hR  = (CopyBuffer(hRSI_M5,     0, 0, 1, rsiM5) > 0);
   bool hE  = (CopyBuffer(hFastEMA_M5, 0, 0, 1, fM5)   > 0 &&
               CopyBuffer(hSlowEMA_M5, 0, 0, 1, sM5)   > 0 &&
               CopyBuffer(hTrendEMA_M5,0, 0, 1, tM5)   > 0);
   bool hA  = (CopyBuffer(hATR_M5,     0, 0, 1, atrM5) > 0);
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
         Print("⏱️ Cierre tiempo+ganancia: ", barsM1, "barras M1 $", profit);
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

      // ── CAPA 4: Cierre VWAP proxy (BB Mid cruzado adversamente en ganancia) ──
      if(profit > 0 && g_bbMid_cached > 0)
      {
         bool adverse = isBuy ? (curPrice < g_bbMid_cached && openPrice > g_bbMid_cached)
                              : (curPrice > g_bbMid_cached && openPrice < g_bbMid_cached);
         if(adverse)
         {
            trade.PositionClose(ticket); RemoveTradeTracker(ticket);
            Print("🔀 Cierre BB Mid adverso (ganancia): $", profit);
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

      // ── CAPA 7: Trailing Stop ATR (solo en ganancia, protege BE) ──
      if(InpTrailingOn) ApplyTrailing(ticket, isBuy);
   }

   // ── CAPA 8: Peak Profit Lock global ──
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
//  TRACKING DE TRADES CERRADOS (para estadísticas)
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
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != InpMagic) continue;
      ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT) continue;
      double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
      if(profit > 0) { g_winsToday++; g_totalWon += profit; }
      else if(profit < 0) { g_lossesToday++; g_totalLost += MathAbs(profit); }
   }
   histCount = total;
}

//====================================================================
//  HELPERS
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
//  PANEL
//====================================================================
void DrawPanel()
{
   if(!InpShowPanel) return;
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);

   int    pos = 0; double pnlOpen = 0, vol = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong t = PositionGetTicket(i);
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      pos++; pnlOpen += PositionGetDouble(POSITION_PROFIT);
      vol += PositionGetDouble(POSITION_VOLUME);
   }

   double dayPnL  = AccountInfoDouble(ACCOUNT_BALANCE) - g_dayStartBal;
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   int    total   = g_winsToday + g_lossesToday;
   double wr      = total > 0 ? (100.0 * g_winsToday / total) : 0;
   double pf      = g_totalLost > 0 ? g_totalWon / g_totalLost : 0;

   string estado  = g_dayInvalid   ? "❌ PAUSADO"      :
                    !g_initialized ? "⏳ CONSTRUYENDO" :
                    g_triggered    ? "✅ OPERANDO"     : "🎯 VIGILANDO";

   string txt = "";
   txt += "══ QQ ULTIMATE v5.0 – SMART CAPITAL ══\n";
   txt += StringFormat("Hora     : %02d:%02d | %s\n", dt.hour, dt.min, estado);
   txt += StringFormat("Modo Cap : %s\n", CapModeStr());
   txt += StringFormat("Balance  : $%.2f | PnL Día: $%.2f\n", balance, dayPnL);
   txt += StringFormat("Target   : $%.2f | Stop: $%.2f\n", g_dailyProfitUSD, g_dailyLossUSD);
   txt += StringFormat("Sesgo D1 : %s | H1: %s\n",
          g_sesgoUp ? "📈ALCISTA" : (g_sesgoDn ? "📉BAJISTA" : "---"),
          g_h1Up    ? "↑UP"      : (g_h1Dn    ? "↓DOWN"    : "=FLAT"));
   txt += StringFormat("Rango    : H=%.2f L=%.2f\n", g_rangeHigh, g_rangeLow);
   txt += StringFormat("Trades   : %d/%d | Pirámide: +%d\n",
          g_tradesToday, g_maxTradesDay, g_pyramidLevel);
   txt += StringFormat("Pos      : %d | Vol: %.2f | PnL: $%.2f\n", pos, vol, pnlOpen);
   txt += StringFormat("BE: %s | P1:%s | P2:%s\n",
          g_beMoved?"✅":"⬜", g_partial1Done?"✅":"⬜", g_partial2Done?"✅":"⬜");
   txt += "── ESTADÍSTICAS ──\n";
   txt += StringFormat("Wins: %d | Losses: %d | WR: %.1f%%\n",
          g_winsToday, g_lossesToday, wr);
   txt += StringFormat("Ganado: $%.2f | PF: %.2f\n", g_totalWon, pf);
   txt += StringFormat("ATR: %.4f | Risk%%: %.1f%%\n", g_atr_cached, g_riskPct);
   txt += "── CIERRES ACTIVOS ──\n";
   txt += StringFormat("Trailing:%s Parcial:%s Smart:%s Mom:%s\n",
          InpTrailingOn?"✅":"⬜", InpPartialClose?"✅":"⬜",
          InpSmartExitOn?"✅":"⬜", InpMomentumExitOn?"✅":"⬜");
   txt += StringFormat("PeakLock: $%.2f | Retrace: $%.2f\n",
          g_peakProfit, g_profitRetrace);

   Comment(txt);
}

//+------------------------------------------------------------------+
//  FIN – QQ ULTIMATE v5.0 SMART CAPITAL
//+------------------------------------------------------------------+
