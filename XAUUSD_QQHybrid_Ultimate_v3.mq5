//+------------------------------------------------------------------+
//|  XAUUSD QUANTUM QUEEN ULTIMATE v4.0                              |
//|  QQ Hybrid Pyramid + EMA Scalper Fusion Edition                  |
//|  Estrategias: Range Breakout | EMA Scalper | Retest | Pyramid   |
//|  Timeframes: M1 + M5 (trading) + M15/H1/D1 (análisis)          |
//+------------------------------------------------------------------+
#property copyright "QQ Ultimate v4.0"
#property version   "4.00"
#property strict

#include <Trade/Trade.mqh>
CTrade trade;

//====================================================================
//  INPUTS
//====================================================================

input group "=== ESTRATEGIA PRINCIPAL ==="
input int    InpRangeHourStart   = 7;      // Hora inicio rango
input int    InpRangeHourEnd     = 8;      // Hora fin rango / trigger
input int    InpBreakoutHourEnd  = 10;     // Hora cierre ventana breakout
input double InpRangeMinPts      = 1.5;   // Tamaño mínimo rango (pts)
input double InpRangeMaxPts      = 12.0;  // Tamaño máximo rango (pts)
input int    InpMinBars          = 25;    // Barras mínimas en rango
input double InpBreakoutOffset   = 0.30;  // Offset ruptura (puntos)
input double InpSLOffset         = 0.50;  // Offset SL base (puntos)
input double InpRR               = 2.0;   // Risk/Reward ratio entrada 1

input group "=== ESTRATEGIA EMA SCALPER (M1/M5) ==="
input bool   InpScalperOn        = true;   // Activar estrategia Scalper EMA
input int    InpScalperHourStart = 8;      // Hora inicio scalper
input int    InpScalperHourEnd   = 20;     // Hora fin scalper
input int    InpFastEMA          = 9;      // EMA rápida scalper
input int    InpSlowEMA          = 21;     // EMA lenta scalper
input int    InpTrendEMA         = 50;     // EMA tendencia scalper
input double InpScalperRR        = 1.8;   // R:R scalper
input double InpScalperRiskPct   = 0.4;   // % riesgo por trade scalper

input group "=== GESTIÓN DE CAPITAL ==="
input bool   InpUseDynamicLot    = true;   // Usar lote dinámico
input double InpRiskPercent      = 0.5;    // % capital por trade (E1)
input double InpLotFixed         = 0.01;   // Lote fijo (si dinámico=false)
input int    InpMagic            = 5900;   // Magic number
input int    InpMaxBarsOpen      = 120;    // Máx barras con trade abierto (M1)
input int    InpMaxTradesDay     = 6;      // Máx trades por día (ambas estrategias)

input group "=== SISTEMA PIRAMIDAL ==="
input bool   InpPyramidOn        = true;   // Activar pirámide
input int    InpPyramidLevels    = 2;      // Niveles adicionales (1-3)
input double InpPyramidTrigger1  = 1.0;   // Ganancia (pts) para nivel 2
input double InpPyramidTrigger2  = 2.0;   // Ganancia (pts) para nivel 3
input double InpPyramidLotMult   = 0.75;  // Multiplicador lote por nivel
input double InpPyramidRR        = 1.5;   // R:R posiciones pirámide
input bool   InpPyramidUseBE     = true;  // SL pirámide en BE

input group "=== CIERRE PARCIAL PROGRESIVO ==="
input bool   InpPartialClose     = true;   // Activar cierre parcial
input double InpPartialAt1R      = 0.30;  // Cerrar 30% al 1R
input double InpPartialAt2R      = 0.40;  // Cerrar 40% al 2R
input bool   InpMoveToBreakEven  = true;  // Mover SL a BE tras 1R

input group "=== SL/TP DINÁMICO ATR ==="
input bool   InpUseATR_SLTP      = true;   // Usar ATR para SL/TP
input double InpATR_SL_Mult      = 1.2;   // Multiplicador ATR para SL
input double InpATR_TP_Mult      = 2.4;   // Multiplicador ATR para TP

input group "=== SESGO ALCISTA ORO ==="
input bool   InpGoldBullBias     = true;   // Sesgo alcista estructural en ORO
input double InpBullBias_RSI     = 50.0;  // RSI mín para buys con sesgo
input double InpBullBias_LotMult = 1.20;  // Multiplicador lote buys

input group "=== RETEST ENTRY ==="
input bool   InpAllowRetestEntry = true;   // Permitir entrada en retest
input double InpRetestZone       = 0.50;  // Zona retest (pts desde rango)
input int    InpRetestWindowBars = 30;    // Máx barras para retest válido

input group "=== SISTEMAS DE CIERRE AVANZADO ==="
input bool   InpTrailingOn       = true;   // Trailing stop ATR
input double InpTrailingATRMult  = 1.0;   // ATR mult para trailing
input double InpMinProfitLock    = 0.50;  // Ganancia mín para activar lock
input double InpProfitRetrace    = 0.20;  // Retroceso para cierre total
input bool   InpSmartExitOn      = true;   // Salida inteligente por indicadores
input double InpRSI_BuyExit      = 38.0;  // RSI bajo esto en BUY = cierre
input double InpRSI_SellExit     = 62.0;  // RSI alto esto en SELL = cierre
input bool   InpVWAPExitOn       = true;   // Cierre si precio cruza VWAP (BB mid proxy)
input bool   InpMomentumExitOn   = true;   // Cierre por pérdida de momentum EMA
input int    InpMaxNegBars       = 20;    // Cierre si negativo X barras en M5

input group "=== PROTECCIONES ==="
input double InpMaxSpread        = 50.0;  // Spread máximo (puntos)
input double InpDailyLossUSD     = 50.0;  // Límite pérdida diaria USD
input double InpDailyProfitUSD   = 200.0; // Target ganancia diaria

input group "=== FILTROS QUANTUM QUEEN ==="
input bool   InpQQ1_Squeeze      = true;  // QQ1: Bollinger Squeeze
input bool   InpQQ2_DirBreak     = true;  // QQ2: Directional Breakout
input bool   InpQQ4_Trend        = true;  // QQ4: EMA Trend
input bool   InpQQ6_VolMom       = true;  // QQ6: Volume Momentum

input group "=== INDICADORES ==="
input int    InpEMA50            = 50;    // EMA sesgo D1
input int    InpEMA200           = 200;   // EMA sesgo D1
input int    InpBBPeriod         = 20;    // Bollinger Bands período
input int    InpRSIPeriod        = 14;    // RSI período
input int    InpMFIPeriod        = 14;    // MFI período
input int    InpATRPeriod        = 14;    // ATR período

input group "=== MONITOREO ==="
input bool   InpShowPanel        = true;  // Mostrar panel

//====================================================================
//  HANDLES DE INDICADORES – MÚLTIPLES TIMEFRAMES
//====================================================================

// D1 – Sesgo estructural
int hEMA50_D1, hEMA200_D1;

// H1 – Dirección de mercado
int hATR_H1, hRSI_H1;

// M15 – Fuerza y filtro adicional
int hATR_M15, hBB_M15, hRSI_M15;

// M5 – Ejecución principal
int hBB_M5, hRSI_M5, hMFI_M5, hATR_M5;
int hFastEMA_M5, hSlowEMA_M5, hTrendEMA_M5;

// M1 – Scalper y timing fino
int hFastEMA_M1, hSlowEMA_M1, hTrendEMA_M1;
int hRSI_M1, hATR_M1;

//====================================================================
//  VARIABLES GLOBALES
//====================================================================

// Estado rango (estrategia principal)
double   g_rangeHigh      = 0;
double   g_rangeLow       = 0;
int      g_rangeBars      = 0;
bool     g_dayInvalid     = false;
bool     g_initialized    = false;
bool     g_triggered      = false;
bool     g_retestWaiting  = false;
datetime g_breakoutTime   = 0;

// Sesgo D1
bool     g_sesgoUp        = false;
bool     g_sesgoDn        = false;

// Dirección H1
bool     g_h1Up           = false;
bool     g_h1Dn           = false;

// Gestión diaria
int      g_tradesToday    = 0;
double   g_dayStartBal    = 0;
datetime g_lastDay        = 0;

// Tracking pirámide
int      g_pyramidLevel   = 0;
double   g_entry1Lot      = 0;
double   g_entry1Price    = 0;
bool     g_partial1Done   = false;
bool     g_partial2Done   = false;
bool     g_beMoved        = false;

// Peak profit lock
double   g_peakProfit     = 0;

// Cache indicadores
double   g_atr_cached     = 0;
double   g_bbMid_cached   = 0;

// Scalper – control de barra
datetime g_lastBarM1      = 0;
datetime g_lastBarM5      = 0;

// Tracking apertura de cada posición (para contar barras negativas)
struct TradeInfo
{
   ulong    ticket;
   datetime openTime;
   int      negBars;
};
TradeInfo g_openTrades[50];
int       g_openTradeCount = 0;

//====================================================================
//  OnInit
//====================================================================
int OnInit()
{
   // D1
   hEMA50_D1    = iMA(_Symbol, PERIOD_D1, InpEMA50,  0, MODE_EMA, PRICE_CLOSE);
   hEMA200_D1   = iMA(_Symbol, PERIOD_D1, InpEMA200, 0, MODE_EMA, PRICE_CLOSE);

   // H1
   hATR_H1      = iATR(_Symbol, PERIOD_H1, InpATRPeriod);
   hRSI_H1      = iRSI(_Symbol, PERIOD_H1, InpRSIPeriod, PRICE_CLOSE);

   // M15
   hATR_M15     = iATR(_Symbol, PERIOD_M15, InpATRPeriod);
   hBB_M15      = iBands(_Symbol, PERIOD_M15, InpBBPeriod, 0, 2.0, PRICE_CLOSE);
   hRSI_M15     = iRSI(_Symbol, PERIOD_M15, InpRSIPeriod, PRICE_CLOSE);

   // M5
   hBB_M5       = iBands(_Symbol, PERIOD_M5, InpBBPeriod, 0, 2.0, PRICE_CLOSE);
   hRSI_M5      = iRSI(_Symbol, PERIOD_M5, InpRSIPeriod, PRICE_CLOSE);
   hMFI_M5      = iMFI(_Symbol, PERIOD_M5, InpMFIPeriod, VOLUME_TICK);
   hATR_M5      = iATR(_Symbol, PERIOD_M5, InpATRPeriod);
   hFastEMA_M5  = iMA(_Symbol, PERIOD_M5, InpFastEMA,  0, MODE_EMA, PRICE_CLOSE);
   hSlowEMA_M5  = iMA(_Symbol, PERIOD_M5, InpSlowEMA,  0, MODE_EMA, PRICE_CLOSE);
   hTrendEMA_M5 = iMA(_Symbol, PERIOD_M5, InpTrendEMA, 0, MODE_EMA, PRICE_CLOSE);

   // M1
   hFastEMA_M1  = iMA(_Symbol, PERIOD_M1, InpFastEMA,  0, MODE_EMA, PRICE_CLOSE);
   hSlowEMA_M1  = iMA(_Symbol, PERIOD_M1, InpSlowEMA,  0, MODE_EMA, PRICE_CLOSE);
   hTrendEMA_M1 = iMA(_Symbol, PERIOD_M1, InpTrendEMA, 0, MODE_EMA, PRICE_CLOSE);
   hRSI_M1      = iRSI(_Symbol, PERIOD_M1, InpRSIPeriod, PRICE_CLOSE);
   hATR_M1      = iATR(_Symbol, PERIOD_M1, InpATRPeriod);

   if(hEMA50_D1 == INVALID_HANDLE || hEMA200_D1 == INVALID_HANDLE ||
      hATR_H1   == INVALID_HANDLE || hRSI_H1    == INVALID_HANDLE ||
      hBB_M5    == INVALID_HANDLE || hRSI_M5    == INVALID_HANDLE ||
      hMFI_M5   == INVALID_HANDLE || hATR_M5    == INVALID_HANDLE ||
      hFastEMA_M1 == INVALID_HANDLE || hRSI_M1  == INVALID_HANDLE)
   {
      Alert("❌ Error creando handles de indicadores");
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(10);

   g_dayStartBal = AccountInfoDouble(ACCOUNT_BALANCE);
   DailyReset();

   Print("✅ QQ Ultimate v4.0 iniciado | Magic:", InpMagic);
   return INIT_SUCCEEDED;
}

//====================================================================
//  OnDeinit
//====================================================================
void OnDeinit(const int reason)
{
   Comment("");
   IndicatorRelease(hEMA50_D1);   IndicatorRelease(hEMA200_D1);
   IndicatorRelease(hATR_H1);     IndicatorRelease(hRSI_H1);
   IndicatorRelease(hATR_M15);    IndicatorRelease(hBB_M15);    IndicatorRelease(hRSI_M15);
   IndicatorRelease(hBB_M5);      IndicatorRelease(hRSI_M5);
   IndicatorRelease(hMFI_M5);     IndicatorRelease(hATR_M5);
   IndicatorRelease(hFastEMA_M5); IndicatorRelease(hSlowEMA_M5); IndicatorRelease(hTrendEMA_M5);
   IndicatorRelease(hFastEMA_M1); IndicatorRelease(hSlowEMA_M1); IndicatorRelease(hTrendEMA_M1);
   IndicatorRelease(hRSI_M1);     IndicatorRelease(hATR_M1);
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
      // Estrategia 1: Range Breakout (ventana horaria)
      BuildRange();
      ValidateRange();
      SearchBreakout();
      SearchRetestEntry();
      ManagePyramid();

      // Estrategia 2: EMA Scalper (M1 y M5)
      if(InpScalperOn) RunScalperStrategy();
   }

   ManageOpenTrades();
   DrawPanel();
}

//====================================================================
//  RESET DIARIO
//====================================================================
void DailyReset()
{
   g_rangeHigh     = 0; g_rangeLow    = 0; g_rangeBars  = 0;
   g_dayInvalid    = false; g_initialized = false;
   g_triggered     = false; g_retestWaiting = false;
   g_breakoutTime  = 0; g_sesgoUp = false; g_sesgoDn = false;
   g_h1Up          = false; g_h1Dn = false;
   g_tradesToday   = 0; g_peakProfit  = 0;
   g_pyramidLevel  = 0; g_entry1Lot   = 0; g_entry1Price = 0;
   g_partial1Done  = false; g_partial2Done = false; g_beMoved = false;
   g_openTradeCount = 0;
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
   // D1 – Sesgo estructural (EMA50 vs EMA200)
   double ema50[1], ema200[1];
   if(CopyBuffer(hEMA50_D1, 0, 0, 1, ema50) > 0 &&
      CopyBuffer(hEMA200_D1, 0, 0, 1, ema200) > 0)
   {
      g_sesgoUp = (ema50[0] > ema200[0]);
      g_sesgoDn = (ema50[0] < ema200[0]);
   }

   // H1 – Dirección táctica (RSI H1 centrado)
   double rsiH1[1];
   if(CopyBuffer(hRSI_H1, 0, 0, 1, rsiH1) > 0)
   {
      g_h1Up = (rsiH1[0] > 52.0);
      g_h1Dn = (rsiH1[0] < 48.0);
   }
}

//====================================================================
//  FASE 1 – CONSTRUIR RANGO 07:00-07:59
//====================================================================
void BuildRange()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(dt.hour != InpRangeHourStart) return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(g_rangeHigh == 0) g_rangeHigh = ask;
   if(g_rangeLow  == 0) g_rangeLow  = bid;
   g_rangeHigh = MathMax(g_rangeHigh, ask);
   g_rangeLow  = MathMin(g_rangeLow,  bid);
   g_rangeBars++;
}

//====================================================================
//  FASE 2 – VALIDAR RANGO 08:00:00
//====================================================================
void ValidateRange()
{
   if(g_initialized) return;
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(dt.hour != InpRangeHourEnd || dt.min != 0) return;

   double rngSize = g_rangeHigh - g_rangeLow;
   if(g_rangeBars < InpMinBars || rngSize < InpRangeMinPts || rngSize > InpRangeMaxPts)
   {
      // Rango inválido para breakout, pero scalper puede seguir
      g_initialized = true;
      g_dayInvalid  = false; // No bloquear scalper
      Print("⚠️ Rango breakout inválido | Scalper continúa activo");
      return;
   }

   g_initialized = true;
   Print("✅ Rango OK | High:", g_rangeHigh, " Low:", g_rangeLow,
         " Size:", rngSize, " SesgoD1:", (g_sesgoUp ? "ALCISTA" : "BAJISTA"),
         " H1:", (g_h1Up ? "↑" : (g_h1Dn ? "↓" : "=")));
}

//====================================================================
//  OBTENER INDICADORES M5 (para breakout y gestión)
//====================================================================
bool GetIndicatorsM5(double &bbU, double &bbD, double &bbM,
                     double &rsi, double &mfi, double &atr)
{
   double bufBBU[1], bufBBD[1], bufBBM[1];
   double bufRSI[1], bufMFI[1], bufATR[1];

   if(CopyBuffer(hBB_M5,  1, 0, 1, bufBBU) <= 0) return false;
   if(CopyBuffer(hBB_M5,  2, 0, 1, bufBBD) <= 0) return false;
   if(CopyBuffer(hBB_M5,  0, 0, 1, bufBBM) <= 0) return false;
   if(CopyBuffer(hRSI_M5, 0, 0, 1, bufRSI) <= 0) return false;
   if(CopyBuffer(hMFI_M5, 0, 0, 1, bufMFI) <= 0) return false;
   if(CopyBuffer(hATR_M5, 0, 0, 1, bufATR) <= 0) return false;

   bbU = bufBBU[0]; bbD = bufBBD[0]; bbM = bufBBM[0];
   rsi = bufRSI[0]; mfi = bufMFI[0]; atr = bufATR[0];
   g_bbMid_cached = bbM;
   g_atr_cached   = bufATR[0];
   return true;
}

//====================================================================
//  FILTROS QQ
//====================================================================
bool FilterQQ1(double bbWidth, double rsi)
{
   if(!InpQQ1_Squeeze) return true;
   bool squeeze = (bbWidth < bbWidth * 0.45);
   bool extreme = (rsi < 25.0 || rsi > 75.0);
   return (squeeze || extreme);
}
bool FilterQQ2(bool isBuy, double rsi)
{
   if(!InpQQ2_DirBreak) return true;
   return isBuy ? (rsi > 52.0) : (rsi < 48.0);
}
bool FilterQQ4(double close, double bbMid, bool isBuy)
{
   if(!InpQQ4_Trend) return true;
   return isBuy ? (close > bbMid) : (close < bbMid);
}
bool FilterQQ6(double rsi, double mfi, bool isBuy)
{
   if(!InpQQ6_VolMom) return true;
   return isBuy ? (rsi > 52.0 && mfi > 50.0) : (rsi < 48.0 && mfi < 50.0);
}
bool FilterGoldBullBias(double rsi, bool isBuy)
{
   if(!InpGoldBullBias) return true;
   return isBuy ? (rsi > InpBullBias_RSI) : (rsi < 45.0 && !g_sesgoUp);
}

//====================================================================
//  CALCULAR LOT DINÁMICO
//====================================================================
double CalcDynamicLot(double slPts, double riskMult = 1.0)
{
   if(!InpUseDynamicLot) return NormLot(InpLotFixed * riskMult);

   double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * (InpRiskPercent / 100.0) * riskMult;
   double tickValue  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

   if(slPts <= 0 || tickValue <= 0 || tickSize <= 0) return NormLot(InpLotFixed);
   double slMoney = slPts / tickSize * tickValue;
   double lot     = (slMoney > 0) ? riskAmount / slMoney : InpLotFixed;
   return NormLot(lot);
}

double CalcScalperLot(double slPts)
{
   if(!InpUseDynamicLot) return NormLot(InpLotFixed);
   double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * (InpScalperRiskPct / 100.0);
   double tickValue  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(slPts <= 0 || tickValue <= 0 || tickSize <= 0) return NormLot(InpLotFixed);
   double slMoney = slPts / tickSize * tickValue;
   double lot     = (slMoney > 0) ? riskAmount / slMoney : InpLotFixed;
   return NormLot(lot);
}

//====================================================================
//  CALCULAR SL/TP
//====================================================================
void CalcSLTP(bool isBuy, double entryPrice, double atr,
              double &sl, double &tp)
{
   double slDist, tpDist;
   if(InpUseATR_SLTP)
   {
      slDist = atr * InpATR_SL_Mult;
      tpDist = atr * InpATR_TP_Mult;
   }
   else
   {
      double slOff = InpSLOffset * _Point * 10;
      slDist = (g_rangeHigh - g_rangeLow) + slOff;
      tpDist = slDist * InpRR;
   }
   if(isBuy) { sl = entryPrice - slDist; tp = entryPrice + tpDist; }
   else       { sl = entryPrice + slDist; tp = entryPrice - tpDist; }
}

//====================================================================
//  FASE 3 – BÚSQUEDA DE BREAKOUT (Entrada Principal E1)
//====================================================================
void SearchBreakout()
{
   if(g_triggered || !g_initialized || g_dayInvalid) return;
   if(g_rangeHigh == 0 || g_rangeLow == 0) return;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(dt.hour < InpRangeHourEnd || dt.hour >= InpBreakoutHourEnd) return;
   if(g_tradesToday >= InpMaxTradesDay) return;

   double spread = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > InpMaxSpread) return;

   double dayPnL = AccountInfoDouble(ACCOUNT_BALANCE) - g_dayStartBal;
   if(dayPnL < -InpDailyLossUSD) return;
   if(dayPnL >  InpDailyProfitUSD) return;

   double close = iClose(_Symbol, PERIOD_M5, 0);
   double bbU, bbD, bbM, rsi, mfi, atr;
   if(!GetIndicatorsM5(bbU, bbD, bbM, rsi, mfi, atr)) return;
   double bbW = bbU - bbD;

   // Confirmación H1 alineada (dirección macro)
   bool h1AlignBuy  = g_h1Up || !g_h1Dn;
   bool h1AlignSell = g_h1Dn || !g_h1Up;

   // ENTRADA LONG E1
   if(close > (g_rangeHigh + InpBreakoutOffset * _Point * 10) && g_sesgoUp && h1AlignBuy)
   {
      if(!FilterQQ1(bbW, rsi))           return;
      if(!FilterQQ2(true, rsi))          return;
      if(!FilterQQ4(close, bbM, true))   return;
      if(!FilterQQ6(rsi, mfi, true))     return;
      if(!FilterGoldBullBias(rsi, true)) return;

      double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl, tp;
      CalcSLTP(true, ask, atr, sl, tp);
      double lotMult = (InpGoldBullBias && g_sesgoUp) ? InpBullBias_LotMult : 1.0;
      double lot     = CalcDynamicLot(ask - sl, lotMult);

      if(trade.Buy(lot, _Symbol, ask, sl, tp))
      {
         g_triggered = true; g_tradesToday++;
         g_entry1Lot = lot; g_entry1Price = ask;
         g_pyramidLevel = 0; g_partial1Done = false;
         g_partial2Done = false; g_beMoved = false;
         g_breakoutTime = TimeCurrent();
         RegisterTrade(trade.ResultOrder());
         Print("🟢 LONG E1 @ ", ask, " SL:", sl, " TP:", tp, " Lot:", lot);
      }
   }
   // ENTRADA SHORT E1
   else if(close < (g_rangeLow - InpBreakoutOffset * _Point * 10) && g_sesgoDn && h1AlignSell)
   {
      if(!FilterQQ1(bbW, rsi))            return;
      if(!FilterQQ2(false, rsi))          return;
      if(!FilterQQ4(close, bbM, false))   return;
      if(!FilterQQ6(rsi, mfi, false))     return;
      if(!FilterGoldBullBias(rsi, false)) return;

      double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl, tp;
      CalcSLTP(false, bid, atr, sl, tp);
      double lot = CalcDynamicLot(sl - bid, 1.0);

      if(trade.Sell(lot, _Symbol, bid, sl, tp))
      {
         g_triggered = true; g_tradesToday++;
         g_entry1Lot = lot; g_entry1Price = bid;
         g_pyramidLevel = 0; g_partial1Done = false;
         g_partial2Done = false; g_beMoved = false;
         g_breakoutTime = TimeCurrent();
         RegisterTrade(trade.ResultOrder());
         Print("🔴 SHORT E1 @ ", bid, " SL:", sl, " TP:", tp, " Lot:", lot);
      }
   }
}

//====================================================================
//  RETEST ENTRY
//====================================================================
void SearchRetestEntry()
{
   if(!InpAllowRetestEntry || !g_triggered) return;
   if(g_tradesToday >= InpMaxTradesDay) return;
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(dt.hour >= InpBreakoutHourEnd) return;
   if(CountOpenPositions() > 0) return;

   if(g_breakoutTime > 0)
   {
      int barsSince = (int)((TimeCurrent() - g_breakoutTime) / PeriodSeconds(PERIOD_M5));
      if(barsSince > InpRetestWindowBars) return;
   }

   double close = iClose(_Symbol, PERIOD_M5, 0);
   double bbU, bbD, bbM, rsi, mfi, atr;
   if(!GetIndicatorsM5(bbU, bbD, bbM, rsi, mfi, atr)) return;

   double retestZone = InpRetestZone * _Point * 10;

   if(g_sesgoUp && g_h1Up)
   {
      double retestLevel = g_rangeHigh + retestZone;
      if(close <= retestLevel && close >= g_rangeHigh - retestZone)
      {
         if(rsi > 45.0 && mfi > 45.0)
         {
            double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            double sl, tp;
            CalcSLTP(true, ask, atr, sl, tp);
            double lot = CalcDynamicLot(ask - sl, 0.75);
            if(trade.Buy(lot, _Symbol, ask, sl, tp))
            {
               g_tradesToday++;
               RegisterTrade(trade.ResultOrder());
               Print("🟢 RETEST LONG @ ", ask, " Lot:", lot);
            }
         }
      }
   }
}

//====================================================================
//  SISTEMA PIRAMIDAL
//====================================================================
void ManagePyramid()
{
   if(!InpPyramidOn || !g_triggered) return;
   if(g_pyramidLevel >= InpPyramidLevels) return;
   if(g_tradesToday >= InpMaxTradesDay) return;

   ulong  masterTicket = 0;
   bool   masterIsBuy  = false;
   double masterSL     = 0;
   double masterPrice  = 0;

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

   double triggerPts = (g_pyramidLevel == 0)
                       ? InpPyramidTrigger1 * _Point * 10
                       : InpPyramidTrigger2 * _Point * 10;

   double curPrice  = masterIsBuy
                      ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                      : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double moveInFav = masterIsBuy ? (curPrice - masterPrice) : (masterPrice - curPrice);
   if(moveInFav < triggerPts) return;

   double pyrLotMult = MathPow(InpPyramidLotMult, g_pyramidLevel + 1);
   double pyrLot     = NormLot(g_entry1Lot * pyrLotMult);

   double bbU, bbD, bbM, rsi, mfi, atr;
   if(!GetIndicatorsM5(bbU, bbD, bbM, rsi, mfi, atr)) return;

   double sl, tp;
   if(masterIsBuy)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      sl = InpPyramidUseBE ? masterPrice : (ask - atr * InpATR_SL_Mult);
      tp = ask + atr * InpATR_TP_Mult * InpPyramidRR;
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
      sl = InpPyramidUseBE ? masterPrice : (bid + atr * InpATR_SL_Mult);
      tp = bid - atr * InpATR_TP_Mult * InpPyramidRR;
      if(trade.Sell(pyrLot, _Symbol, bid, sl, tp))
      {
         g_pyramidLevel++; g_tradesToday++;
         RegisterTrade(trade.ResultOrder());
         Print("📉 PIRÁMIDE L", g_pyramidLevel, " @ ", bid, " Lot:", pyrLot);
      }
   }
}

//====================================================================
//  ★ ESTRATEGIA EMA SCALPER – M1 y M5 (nueva integración)
//====================================================================
void RunScalperStrategy()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(dt.hour < InpScalperHourStart || dt.hour >= InpScalperHourEnd) return;
   if(g_tradesToday >= InpMaxTradesDay) return;

   double spread = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > InpMaxSpread) return;

   double dayPnL = AccountInfoDouble(ACCOUNT_BALANCE) - g_dayStartBal;
   if(dayPnL < -InpDailyLossUSD || dayPnL > InpDailyProfitUSD) return;

   // Solo si NO hay posiciones abiertas del magic (evitar solapamiento)
   if(CountOpenPositions() > 0) return;

   // ── SEÑAL M5 (principal) ──
   datetime barM5 = iTime(_Symbol, PERIOD_M5, 0);
   if(barM5 == g_lastBarM5) return; // Solo en nueva vela M5

   double fM5[2], sM5[2], tM5[2];
   ArraySetAsSeries(fM5, true); ArraySetAsSeries(sM5, true); ArraySetAsSeries(tM5, true);
   if(CopyBuffer(hFastEMA_M5,  0, 0, 2, fM5)  <= 0) return;
   if(CopyBuffer(hSlowEMA_M5,  0, 0, 2, sM5)  <= 0) return;
   if(CopyBuffer(hTrendEMA_M5, 0, 0, 2, tM5)  <= 0) return;

   // ── CONFIRMACIÓN M1 (timing fino) ──
   double fM1[2], sM1[2], tM1[2];
   ArraySetAsSeries(fM1, true); ArraySetAsSeries(sM1, true); ArraySetAsSeries(tM1, true);
   if(CopyBuffer(hFastEMA_M1,  0, 0, 2, fM1)  <= 0) return;
   if(CopyBuffer(hSlowEMA_M1,  0, 0, 2, sM1)  <= 0) return;
   if(CopyBuffer(hTrendEMA_M1, 0, 0, 2, tM1)  <= 0) return;

   double rsiM5[1];
   if(CopyBuffer(hRSI_M5, 0, 0, 1, rsiM5) <= 0) return;

   double atrM5[1];
   if(CopyBuffer(hATR_M5, 0, 0, 1, atrM5) <= 0) return;
   g_atr_cached = atrM5[0];

   // Cruce M5 + alineación M1 + alineación D1/H1
   bool signalBuy  = (fM5[0] > sM5[0]) && (fM5[0] > tM5[0]) // Cruce M5 alcista
                     && (fM1[0] > sM1[0]) && (fM1[0] > tM1[0]) // M1 confirma
                     && g_sesgoUp && g_h1Up                      // D1 y H1 alineados
                     && (rsiM5[0] > 50.0 && rsiM5[0] < 75.0);   // RSI momentum

   bool signalSell = (fM5[0] < sM5[0]) && (fM5[0] < tM5[0])
                     && (fM1[0] < sM1[0]) && (fM1[0] < tM1[0])
                     && g_sesgoDn && g_h1Dn
                     && (rsiM5[0] < 50.0 && rsiM5[0] > 25.0);

   // Verificar cruce nuevo (no existía en barra anterior)
   bool crossBuyNew  = signalBuy  && !(fM5[1] > sM5[1] && fM5[1] > tM5[1]);
   bool crossSellNew = signalSell && !(fM5[1] < sM5[1] && fM5[1] < tM5[1]);

   if(!crossBuyNew && !crossSellNew) return;

   g_lastBarM5 = barM5;

   double atr = atrM5[0];
   if(atr <= 0) return;

   if(crossBuyNew)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl  = ask - atr * InpATR_SL_Mult;
      double tp  = ask + atr * InpATR_TP_Mult * InpScalperRR;
      double lot = CalcScalperLot(ask - sl);

      if(trade.Buy(lot, _Symbol, ask, sl, tp))
      {
         g_tradesToday++;
         RegisterTrade(trade.ResultOrder());
         Print("⚡ SCALPER BUY @ ", ask, " SL:", sl, " TP:", tp, " Lot:", lot);
      }
   }
   else if(crossSellNew)
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl  = bid + atr * InpATR_SL_Mult;
      double tp  = bid - atr * InpATR_TP_Mult * InpScalperRR;
      double lot = CalcScalperLot(sl - bid);

      if(trade.Sell(lot, _Symbol, bid, sl, tp))
      {
         g_tradesToday++;
         RegisterTrade(trade.ResultOrder());
         Print("⚡ SCALPER SELL @ ", bid, " SL:", sl, " TP:", tp, " Lot:", lot);
      }
   }
}

//====================================================================
//  GESTIÓN DE TRADES ABIERTOS – SISTEMA MULTI-CIERRE
//====================================================================
void ManageOpenTrades()
{
   double totalPnL = 0;
   int    count    = 0;
   double dayPnL   = AccountInfoDouble(ACCOUNT_BALANCE) - g_dayStartBal;

   // Target diario
   if(dayPnL >= InpDailyProfitUSD && InpDailyProfitUSD > 0)
   {
      CloseAllMagic();
      g_dayInvalid = true;
      Print("🎯 TARGET DIARIO: $", dayPnL);
      return;
   }

   // Pérdida límite diaria
   if(dayPnL <= -InpDailyLossUSD)
   {
      CloseAllMagic();
      g_dayInvalid = true;
      Print("🛑 STOP DIARIO: $", dayPnL);
      return;
   }

   // Indicadores para cierre inteligente
   double rsiM5[1], rsiM1[1];
   bool haveRSI_M5 = (CopyBuffer(hRSI_M5, 0, 0, 1, rsiM5) > 0);
   bool haveRSI_M1 = (CopyBuffer(hRSI_M1, 0, 0, 1, rsiM1) > 0);

   double fM5[1], sM5[1], tM5[1];
   bool haveEMA_M5 = (CopyBuffer(hFastEMA_M5,  0, 0, 1, fM5) > 0 &&
                      CopyBuffer(hSlowEMA_M5,  0, 0, 1, sM5) > 0 &&
                      CopyBuffer(hTrendEMA_M5, 0, 0, 1, tM5) > 0);

   double atrM5[1];
   bool haveATR_M5 = (CopyBuffer(hATR_M5, 0, 0, 1, atrM5) > 0);
   if(haveATR_M5 && atrM5[0] > 0) g_atr_cached = atrM5[0];

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

      totalPnL += profit;
      count++;

      double curPrice = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                              : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      // ── CIERRE 1: Por tiempo (anti-stagnation) ──
      int barsOpenM1 = (int)((TimeCurrent() - tOpen) / PeriodSeconds(PERIOD_M1));
      if(barsOpenM1 >= InpMaxBarsOpen && profit > 0)
      {
         trade.PositionClose(ticket);
         Print("⏱️ Cierre tiempo+positivo: ", barsOpenM1, " barras M1");
         RemoveTradeTracker(ticket);
         continue;
      }

      // ── CIERRE 2: Salida inteligente por indicadores ──
      if(InpSmartExitOn && profit < 0)
      {
         bool trendWrong = false;
         bool momentumWrong = false;

         if(haveEMA_M5)
            trendWrong = isBuy ? (curPrice < tM5[0]) : (curPrice > tM5[0]);

         if(haveRSI_M5)
            momentumWrong = isBuy ? (rsiM5[0] < InpRSI_BuyExit)
                                  : (rsiM5[0] > InpRSI_SellExit);

         if(trendWrong && momentumWrong)
         {
            trade.PositionClose(ticket);
            Print("🧠 Cierre inteligente (tendencia+RSI invertidos)");
            RemoveTradeTracker(ticket);
            continue;
         }
      }

      // ── CIERRE 3: Pérdida de momentum EMA M5 en positivo ──
      if(InpMomentumExitOn && profit > 0 && haveEMA_M5)
      {
         bool momentumLost = isBuy ? (fM5[0] < sM5[0]) : (fM5[0] > sM5[0]);
         if(momentumLost)
         {
            // Asegurar ganancia: cerrar si hay cruce adverso
            trade.PositionClose(ticket);
            Print("⚡ Cierre momentum perdido (ganancia asegurada): $", profit);
            RemoveTradeTracker(ticket);
            continue;
         }
      }

      // ── CIERRE 4: VWAP Proxy – precio cruza BB Mid en adverso ──
      if(InpVWAPExitOn && profit > 0 && g_bbMid_cached > 0)
      {
         bool crossedBBMidAdverse = isBuy ? (curPrice < g_bbMid_cached && openPrice > g_bbMid_cached)
                                          : (curPrice > g_bbMid_cached && openPrice < g_bbMid_cached);
         if(crossedBBMidAdverse)
         {
            trade.PositionClose(ticket);
            Print("🔀 Cierre BB Mid cruzado (VWAP proxy): $", profit);
            RemoveTradeTracker(ticket);
            continue;
         }
      }

      // ── CIERRE 5: Barras negativas consecutivas M5 ──
      if(InpMaxNegBars > 0)
      {
         int idx = FindTradeTracker(ticket);
         if(idx >= 0)
         {
            int barsM5 = (int)((TimeCurrent() - g_openTrades[idx].openTime) / PeriodSeconds(PERIOD_M5));
            if(profit < 0)
            {
               // Solo cerrar si llevamos muchas barras negativos Y tendencia adversa
               if(barsM5 >= InpMaxNegBars && haveEMA_M5)
               {
                  bool trendAdverse = isBuy ? (fM5[0] < tM5[0]) : (fM5[0] > tM5[0]);
                  if(trendAdverse)
                  {
                     trade.PositionClose(ticket);
                     Print("⏰ Cierre negativo prolongado (", barsM5, " barras M5)");
                     RemoveTradeTracker(ticket);
                     continue;
                  }
               }
            }
         }
      }

      // ── CIERRE 6: Cierre parcial progresivo (solo posición principal) ──
      if(InpPartialClose && ticket == GetOldestMagicTicket())
      {
         double slDist = MathAbs(openPrice - curSL);
         double moveR  = (slDist > 0) ? MathAbs(curPrice - openPrice) / slDist : 0;

         if(!g_partial1Done && moveR >= 1.0)
         {
            double closeVol = NormLot(volume * InpPartialAt1R);
            if(closeVol >= SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
            {
               trade.PositionClosePartial(ticket, closeVol);
               Print("💰 Cierre parcial 1 (30%) @ 1R | Vol:", closeVol);
            }
            if(InpMoveToBreakEven && !g_beMoved)
            {
               double newSL = isBuy ? openPrice + _Point : openPrice - _Point;
               trade.PositionModify(ticket, newSL, curTP);
               g_beMoved = true;
               Print("🔒 SL movido a Break-Even");
            }
            g_partial1Done = true;
         }
         if(!g_partial2Done && moveR >= 2.0 && g_partial1Done)
         {
            double closeVol2 = NormLot(volume * InpPartialAt2R);
            if(closeVol2 >= SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
            {
               trade.PositionClosePartial(ticket, closeVol2);
               Print("💰 Cierre parcial 2 (40%) @ 2R | Vol:", closeVol2);
            }
            g_partial2Done = true;
         }
      }

      // ── CIERRE 7: Trailing Stop ATR ──
      if(InpTrailingOn) ApplyTrailingATR(ticket, isBuy, g_atr_cached);
   }

   // ── CIERRE 8: Peak Profit Lock ──
   if(count > 0)
   {
      if(totalPnL > g_peakProfit) g_peakProfit = totalPnL;
      if(g_peakProfit >= InpMinProfitLock &&
         totalPnL < (g_peakProfit - InpProfitRetrace))
      {
         CloseAllMagic();
         Print("💰 Peak Profit Lock: Peak=$", g_peakProfit, " PnL=$", totalPnL);
      }
   }
   else { g_peakProfit = 0; }
}

//====================================================================
//  TRAILING STOP ATR-BASED (mejorado – activación progresiva)
//====================================================================
void ApplyTrailingATR(ulong ticket, bool isBuy, double atr)
{
   if(!PositionSelectByTicket(ticket)) return;

   double curSL     = PositionGetDouble(POSITION_SL);
   double curTP     = PositionGetDouble(POSITION_TP);
   double curPrice  = PositionGetDouble(POSITION_PRICE_CURRENT);
   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double trailDist = (atr > 0) ? atr * InpTrailingATRMult : 10 * _Point * 10;

   if(isBuy)
   {
      if(curPrice <= openPrice) return;
      double newSL = curPrice - trailDist;
      // Asegurar que nuevo SL sea mejor que el actual y no baje de BE
      if(newSL > curSL + _Point && newSL >= openPrice - _Point)
         trade.PositionModify(ticket, newSL, curTP);
   }
   else
   {
      if(curPrice >= openPrice) return;
      double newSL = curPrice + trailDist;
      if(newSL < curSL - _Point || curSL == 0)
         if(newSL <= openPrice + _Point)
            trade.PositionModify(ticket, newSL, curTP);
   }
}

//====================================================================
//  HELPERS – TRACKING DE TRADES
//====================================================================
void RegisterTrade(ulong ticket)
{
   if(ticket == 0) return;
   if(g_openTradeCount >= 50) return;
   g_openTrades[g_openTradeCount].ticket   = ticket;
   g_openTrades[g_openTradeCount].openTime = TimeCurrent();
   g_openTrades[g_openTradeCount].negBars  = 0;
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
            g_openTrades[j] = g_openTrades[j + 1];
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
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) == InpMagic) cnt++;
   }
   return cnt;
}

ulong GetOldestMagicTicket()
{
   ulong    oldest   = 0;
   datetime oldest_t = TimeCurrent();
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      datetime t = (datetime)PositionGetInteger(POSITION_TIME);
      if(oldest == 0 || t < oldest_t) { oldest = ticket; oldest_t = t; }
   }
   return oldest;
}

void CloseAllMagic()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      trade.PositionClose(ticket);
      RemoveTradeTracker(ticket);
   }
}

double NormLot(double lot)
{
   double minL  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxL  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lot = MathFloor(lot / stepL) * stepL;
   return MathMax(minL, MathMin(maxL, lot));
}

//====================================================================
//  PANEL
//====================================================================
void DrawPanel()
{
   if(!InpShowPanel) return;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);

   int    activePos = 0;
   double activePnL = 0;
   double totalVol  = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      activePos++;
      activePnL += PositionGetDouble(POSITION_PROFIT);
      totalVol  += PositionGetDouble(POSITION_VOLUME);
   }

   double dayPnL  = AccountInfoDouble(ACCOUNT_BALANCE) - g_dayStartBal;
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);

   string estado = g_dayInvalid   ? "❌ PAUSADO"       :
                   !g_initialized ? "⏳ CONSTRUYENDO"  :
                   g_triggered    ? "✅ OPERANDO"      : "🎯 VIGILANDO";

   string sesgoStr = g_sesgoUp ? "📈 ALCISTA" : (g_sesgoDn ? "📉 BAJISTA" : "---");
   string h1Str    = g_h1Up    ? "↑ UP"       : (g_h1Dn    ? "↓ DOWN"    : "= NEUTRAL");

   string txt = "";
   txt += "══ QUANTUM QUEEN ULTIMATE v4.0 ══\n";
   txt += StringFormat("Hora     : %02d:%02d | %s\n", dt.hour, dt.min, estado);
   txt += StringFormat("Sesgo D1 : %s | H1: %s\n", sesgoStr, h1Str);
   txt += StringFormat("Rango    : H=%.2f L=%.2f (%.2f pts)\n",
          g_rangeHigh, g_rangeLow, g_rangeHigh - g_rangeLow);
   txt += StringFormat("Trades   : %d/%d | Pirámide: +%d\n",
          g_tradesToday, InpMaxTradesDay, g_pyramidLevel);
   txt += StringFormat("Parcial  : %s%s | BE: %s\n",
          g_partial1Done ? "✅1R " : "⬜1R ", g_partial2Done ? "✅2R" : "⬜2R",
          g_beMoved ? "✅" : "⬜");
   txt += StringFormat("Pos      : %d | Vol: %.2f\n", activePos, totalVol);
   txt += StringFormat("PnL Open : $%.2f\n", activePnL);
   txt += StringFormat("PnL Día  : $%.2f / $%.2f\n", dayPnL, InpDailyProfitUSD);
   txt += StringFormat("Balance  : $%.2f\n", balance);
   txt += StringFormat("Scalper  : %s | ATR: %.4f\n",
          InpScalperOn ? "ON" : "OFF", g_atr_cached);
   txt += "══ CIERRES ACTIVOS ══\n";
   txt += StringFormat("Trailing:%s Parcial:%s Smart:%s\n",
          InpTrailingOn ? "✅" : "⬜", InpPartialClose ? "✅" : "⬜",
          InpSmartExitOn ? "✅" : "⬜");
   txt += StringFormat("VWAP Exit:%s MomExit:%s PeakLock:$%.2f\n",
          InpVWAPExitOn ? "✅" : "⬜", InpMomentumExitOn ? "✅" : "⬜", g_peakProfit);

   Comment(txt);
}

//+------------------------------------------------------------------+
//  FIN – QUANTUM QUEEN ULTIMATE v4.0
//+------------------------------------------------------------------+
