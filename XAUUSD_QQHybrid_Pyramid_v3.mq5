//+------------------------------------------------------------------+
//|  XAUUSD QUANTUM QUEEN HYBRID v3.0 – PYRAMID EDITION             |
//|  Range Breakout + Pirámide Inteligente + Sesgo Alcista Gold      |
//|  Inspirado en Quantum Queen: Grid-Pyramid + Gestión Avanzada     |
//+------------------------------------------------------------------+
#property copyright "QQ Hybrid Pyramid v3.0"
#property version   "3.00"
#property strict

#include <Trade/Trade.mqh>
CTrade trade;

//====================================================================
//  ██████  INPUTS
//====================================================================

input group "=== RANGO BREAKOUT (ESTRATEGIA PRINCIPAL) ==="
input int    InpRangeHourStart  = 7;     // Hora inicio rango
input int    InpRangeHourEnd    = 8;     // Hora fin rango / trigger
input int    InpBreakoutHourEnd = 10;    // Hora cierre ventana
input double InpRangeMinPts     = 1.5;  // Tamaño mínimo rango (pts)
input double InpRangeMaxPts     = 12.0; // Tamaño máximo rango (pts)
input int    InpMinBars         = 25;   // Barras mínimas en rango
input double InpBreakoutOffset  = 0.30; // Offset ruptura (puntos)
input double InpSLOffset        = 0.50; // Offset SL base (puntos)
input double InpRR              = 2.0;  // Risk/Reward ratio entrada 1

input group "=== GESTIÓN DE CAPITAL (RIESGO DINÁMICO) ==="
input bool   InpUseDynamicLot   = true;  // Usar lote dinámico (% riesgo)
input double InpRiskPercent     = 0.5;   // % de capital por trade (E1)
input double InpLotFixed        = 0.01;  // Lote fijo (si dinámico=false)
input int    InpMagic           = 5900;  // Magic number
input int    InpMaxBarsOpen     = 120;   // Máx barras con trade abierto
input int    InpMaxTradesDay    = 4;     // Máx trades/entradas por día

input group "=== ★ SISTEMA PIRAMIDAL (inspirado en QQ) ==="
input bool   InpPyramidOn       = true;  // Activar pirámide
input int    InpPyramidLevels   = 2;     // Niveles adicionales (1-3)
input double InpPyramidTrigger1 = 1.0;  // Ganancia (pts) para nivel 2
input double InpPyramidTrigger2 = 2.0;  // Ganancia (pts) para nivel 3
input double InpPyramidLotMult  = 0.75; // Multiplicador lote por nivel
input double InpPyramidRR       = 1.5;  // R:R de posiciones pirámide
input bool   InpPyramidUseBE    = true; // Mover SL pirámide a BE

input group "=== CIERRE PARCIAL (PROFIT LOCK PROGRESIVO) ==="
input bool   InpPartialClose    = true;  // Activar cierre parcial
input double InpPartialAt1R     = 0.30; // Cerrar 30% al alcanzar 1R
input double InpPartialAt2R     = 0.40; // Cerrar 40% adicional al 2R
input bool   InpMoveToBreakEven = true; // Mover SL a BE tras 1R

input group "=== SL/TP DINÁMICO (ATR-BASED) ==="
input bool   InpUseATR_SLTP     = true;  // Usar ATR para SL/TP
input double InpATR_SL_Mult     = 1.2;  // Multiplicador ATR para SL
input double InpATR_TP_Mult     = 2.4;  // Multiplicador ATR para TP

input group "=== SESGO ALCISTA ORO (QQ Gold Bias) ==="
input bool   InpGoldBullBias    = true;  // Activar sesgo alcista en ORO
input double InpBullBias_RSI    = 50.0; // RSI mín para buys con sesgo
input double InpBullBias_LotMult = 1.20; // Multiplicador lote buys
input bool   InpAllowRetestEntry = true; // Permitir entrada en retest

input group "=== RETEST ENTRY (Segunda oportunidad) ==="
input double InpRetestZone      = 0.50; // Zona retest (pts desde rango)
input int    InpRetestWindowBars = 30;  // Máx barras para retest válido

input group "=== PROTECCIONES ==="
input double InpMaxSpread       = 50.0; // Spread máximo (puntos)
input double InpDailyLossUSD    = 50.0; // Límite pérdida diaria USD
input double InpDailyProfitUSD  = 200.0; // Target ganancia diaria (cierra)
input bool   InpTrailingOn      = true; // Trailing stop
input double InpTrailingATRMult = 1.0;  // ATR mult para trailing
input double InpMinProfitLock   = 0.50; // Ganancia para activar lock
input double InpProfitRetrace   = 0.20; // Retroceso para cierre total

input group "=== FILTROS QUANTUM QUEEN ==="
input bool   InpQQ1_Squeeze     = true; // QQ1: Bollinger Squeeze
input bool   InpQQ2_DirBreak    = true; // QQ2: Directional Breakout
input bool   InpQQ4_Trend       = true; // QQ4: EMA Trend
input bool   InpQQ6_VolMom      = true; // QQ6: Volume Momentum

input group "=== INDICADORES ==="
input int    InpEMA50           = 50;   // EMA sesgo D1
input int    InpEMA200          = 200;  // EMA sesgo D1
input int    InpBBPeriod        = 20;   // Bollinger Bands período
input int    InpRSIPeriod       = 14;   // RSI período
input int    InpMFIPeriod       = 14;   // MFI período
input int    InpATRPeriod       = 14;   // ATR período

input group "=== MONITOREO ==="
input bool   InpShowPanel       = true; // Mostrar panel

//====================================================================
//  VARIABLES GLOBALES
//====================================================================

int hEMA50, hEMA200, hBB, hRSI, hMFI, hATR;

// Estado rango
double   g_rangeHigh     = 0;
double   g_rangeLow      = 0;
int      g_rangeBars     = 0;
bool     g_dayInvalid    = false;
bool     g_initialized   = false;
bool     g_triggered     = false;
bool     g_retestWaiting = false;
datetime g_breakoutTime  = 0;

// Sesgo
bool     g_sesgoUp       = false;
bool     g_sesgoDn       = false;

// Gestión diaria
int      g_tradesToday   = 0;
double   g_dayStartBal   = 0;
datetime g_lastDay       = 0;

// Tracking pirámide
int      g_pyramidLevel  = 0;   // 0=solo E1, 1=E2 añadida, 2=E3 añadida
double   g_entry1Lot     = 0;   // Lote de la entrada original
double   g_entry1Price   = 0;   // Precio entrada original
bool     g_partial1Done  = false;
bool     g_partial2Done  = false;
bool     g_beMoved       = false;

// Tracking ganancia
double   g_peakProfit    = 0;

// Cache indicadores
double   bbMid_cached    = 0;
double   atr_cached      = 0;

//====================================================================
//  OnInit
//====================================================================
int OnInit()
{
   hEMA50  = iMA(_Symbol, PERIOD_D1, InpEMA50,  0, MODE_EMA, PRICE_CLOSE);
   hEMA200 = iMA(_Symbol, PERIOD_D1, InpEMA200, 0, MODE_EMA, PRICE_CLOSE);
   hBB     = iBands(_Symbol, PERIOD_CURRENT, InpBBPeriod, 0, 2.0, PRICE_CLOSE);
   hRSI    = iRSI(_Symbol, PERIOD_CURRENT, InpRSIPeriod, PRICE_CLOSE);
   hMFI    = iMFI(_Symbol, PERIOD_CURRENT, InpMFIPeriod, VOLUME_TICK);
   hATR    = iATR(_Symbol, PERIOD_CURRENT, InpATRPeriod);

   if(hEMA50 == INVALID_HANDLE || hEMA200 == INVALID_HANDLE ||
      hBB == INVALID_HANDLE || hRSI == INVALID_HANDLE ||
      hMFI == INVALID_HANDLE || hATR == INVALID_HANDLE)
   {
      Alert("❌ Error creando handles de indicadores");
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(10);

   g_dayStartBal = AccountInfoDouble(ACCOUNT_BALANCE);
   DailyReset();

   Print("✅ QQ Hybrid Pyramid v3.0 iniciado en ", _Symbol);
   return INIT_SUCCEEDED;
}

//====================================================================
//  OnDeinit
//====================================================================
void OnDeinit(const int reason)
{
   Comment("");
   IndicatorRelease(hEMA50);
   IndicatorRelease(hEMA200);
   IndicatorRelease(hBB);
   IndicatorRelease(hRSI);
   IndicatorRelease(hMFI);
   IndicatorRelease(hATR);
}

//====================================================================
//  OnTick
//====================================================================
void OnTick()
{
   CheckDayReset();

   if(!g_dayInvalid)
   {
      BuildRange();
      ValidateRange();
      SearchBreakout();
      SearchRetestEntry();
      ManagePyramid();
   }

   ManageOpenTrades();
   DrawPanel();
}

//====================================================================
//  RESET DIARIO
//====================================================================
void DailyReset()
{
   g_rangeHigh     = 0;
   g_rangeLow      = 0;
   g_rangeBars     = 0;
   g_dayInvalid    = false;
   g_initialized   = false;
   g_triggered     = false;
   g_retestWaiting = false;
   g_breakoutTime  = 0;
   g_sesgoUp       = false;
   g_sesgoDn       = false;
   g_tradesToday   = 0;
   g_peakProfit    = 0;
   g_pyramidLevel  = 0;
   g_entry1Lot     = 0;
   g_entry1Price   = 0;
   g_partial1Done  = false;
   g_partial2Done  = false;
   g_beMoved       = false;
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
      g_dayInvalid = true;
      Print("❌ Rango inválido | Barras:", g_rangeBars, " Size:", rngSize);
      return;
   }

   double ema50[1], ema200[1];
   if(CopyBuffer(hEMA50,  0, 0, 1, ema50)  <= 0) { g_dayInvalid = true; return; }
   if(CopyBuffer(hEMA200, 0, 0, 1, ema200) <= 0) { g_dayInvalid = true; return; }

   g_sesgoUp = (ema50[0] > ema200[0]);
   g_sesgoDn = (ema50[0] < ema200[0]);

   g_initialized = true;
   Print("✅ Rango OK | High:", g_rangeHigh, " Low:", g_rangeLow,
         " Size:", rngSize, " Sesgo:", (g_sesgoUp ? "ALCISTA" : "BAJISTA"));
}

//====================================================================
//  FILTROS QUANTUM QUEEN
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
   if(isBuy)  return (rsi > 52.0);
   else        return (rsi < 48.0);
}

bool FilterQQ4(double close, double bbMid, bool isBuy)
{
   if(!InpQQ4_Trend) return true;
   if(isBuy)  return (close > bbMid);
   else        return (close < bbMid);
}

bool FilterQQ6(double rsi, double mfi, bool isBuy)
{
   if(!InpQQ6_VolMom) return true;
   if(isBuy)  return (rsi > 52.0 && mfi > 50.0);
   else        return (rsi < 48.0 && mfi < 50.0);
}

// ★ GOLD BULL BIAS – Filtro adicional para buys en ORO (inspirado en QQ)
bool FilterGoldBullBias(double rsi, bool isBuy)
{
   if(!InpGoldBullBias) return true;
   // El oro tiene tendencia alcista estructural (como QQ lo aprovecha)
   // En buys: relajar condición de RSI mínimo; en shorts: exigir más
   if(isBuy)  return (rsi > InpBullBias_RSI);
   else        return (rsi < 45.0 && !g_sesgoUp); // Short solo si sesgo bajista claro
}

//====================================================================
//  OBTENER INDICADORES
//====================================================================
bool GetIndicators(double &bbU, double &bbD, double &bbM,
                   double &rsi, double &mfi, double &atr)
{
   double bufBBU[1], bufBBD[1], bufBBM[1];
   double bufRSI[1], bufMFI[1], bufATR[1];

   if(CopyBuffer(hBB,  1, 0, 1, bufBBU) <= 0) return false;
   if(CopyBuffer(hBB,  2, 0, 1, bufBBD) <= 0) return false;
   if(CopyBuffer(hBB,  0, 0, 1, bufBBM) <= 0) return false;
   if(CopyBuffer(hRSI, 0, 0, 1, bufRSI) <= 0) return false;
   if(CopyBuffer(hMFI, 0, 0, 1, bufMFI) <= 0) return false;
   if(CopyBuffer(hATR, 0, 0, 1, bufATR) <= 0) return false;

   bbU = bufBBU[0]; bbD = bufBBD[0]; bbM = bufBBM[0];
   rsi = bufRSI[0]; mfi = bufMFI[0]; atr = bufATR[0];
   bbMid_cached = bbM;
   atr_cached   = atr;
   return true;
}

//====================================================================
//  CALCULAR LOT DINÁMICO (% riesgo de capital)
//====================================================================
double CalcDynamicLot(double slPts, double riskMult = 1.0)
{
   if(!InpUseDynamicLot) return NormLot(InpLotFixed * riskMult);

   double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * (InpRiskPercent / 100.0) * riskMult;
   double tickValue  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

   if(slPts <= 0 || tickValue <= 0 || tickSize <= 0) return NormLot(InpLotFixed);

   double slMoney   = slPts / tickSize * tickValue;
   double lot       = (slMoney > 0) ? riskAmount / slMoney : InpLotFixed;
   return NormLot(lot);
}

//====================================================================
//  CALCULAR SL/TP (Fijo O ATR-BASED)
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

   if(isBuy)
   {
      sl = entryPrice - slDist;
      tp = entryPrice + tpDist;
   }
   else
   {
      sl = entryPrice + slDist;
      tp = entryPrice - tpDist;
   }
}

//====================================================================
//  FASE 3 – BUSCAR BREAKOUT (Entrada Principal E1)
//====================================================================
void SearchBreakout()
{
   if(g_triggered || !g_initialized || g_dayInvalid) return;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(dt.hour < InpRangeHourEnd || dt.hour >= InpBreakoutHourEnd) return;
   if(g_tradesToday >= InpMaxTradesDay) return;

   double spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > InpMaxSpread) return;

   double dayPnL = AccountInfoDouble(ACCOUNT_BALANCE) - g_dayStartBal;
   if(dayPnL < -InpDailyLossUSD)  return;
   if(dayPnL >  InpDailyProfitUSD) return; // Target diario alcanzado

   double close = iClose(_Symbol, PERIOD_CURRENT, 0);
   double bbU, bbD, bbM, rsi, mfi, atr;
   if(!GetIndicators(bbU, bbD, bbM, rsi, mfi, atr)) return;

   double bbW = bbU - bbD;

   // ──── ENTRADA LONG (E1) ────
   if(close > (g_rangeHigh + InpBreakoutOffset * _Point * 10) && g_sesgoUp)
   {
      if(!FilterQQ1(bbW, rsi))           return;
      if(!FilterQQ2(true, rsi))          return;
      if(!FilterQQ4(close, bbM, true))   return;
      if(!FilterQQ6(rsi, mfi, true))     return;
      if(!FilterGoldBullBias(rsi, true)) return;

      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl, tp;
      CalcSLTP(true, ask, atr, sl, tp);

      // ★ Multiplicador de lote por sesgo alcista ORO
      double lotMult = (InpGoldBullBias && g_sesgoUp) ? InpBullBias_LotMult : 1.0;
      double slPts   = ask - sl;
      double lot     = CalcDynamicLot(slPts, lotMult);

      if(trade.Buy(lot, _Symbol, ask, sl, tp))
      {
         g_triggered    = true;
         g_tradesToday++;
         g_entry1Lot    = lot;
         g_entry1Price  = ask;
         g_pyramidLevel = 0;
         g_partial1Done = false;
         g_partial2Done = false;
         g_beMoved      = false;
         if(InpAllowRetestEntry)
         {
            g_retestWaiting = false; // Retest no necesario si E1 ejecutada
         }
         Print("🟢 LONG E1 @ ", ask, " SL:", sl, " TP:", tp, " Lot:", lot);
      }
   }

   // ──── ENTRADA SHORT (E1) ────
   else if(close < (g_rangeLow - InpBreakoutOffset * _Point * 10) && g_sesgoDn)
   {
      if(!FilterQQ1(bbW, rsi))            return;
      if(!FilterQQ2(false, rsi))          return;
      if(!FilterQQ4(close, bbM, false))   return;
      if(!FilterQQ6(rsi, mfi, false))     return;
      if(!FilterGoldBullBias(rsi, false)) return;

      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl, tp;
      CalcSLTP(false, bid, atr, sl, tp);

      double slPts = sl - bid;
      double lot   = CalcDynamicLot(slPts, 1.0);

      if(trade.Sell(lot, _Symbol, bid, sl, tp))
      {
         g_triggered    = true;
         g_tradesToday++;
         g_entry1Lot    = lot;
         g_entry1Price  = bid;
         g_pyramidLevel = 0;
         g_partial1Done = false;
         g_partial2Done = false;
         g_beMoved      = false;
         Print("🔴 SHORT E1 @ ", bid, " SL:", sl, " TP:", tp, " Lot:", lot);
      }
   }
}

//====================================================================
//  ★ RETEST ENTRY – Segunda oportunidad si precio vuelve al rango
//====================================================================
void SearchRetestEntry()
{
   if(!InpAllowRetestEntry)  return;
   if(!g_triggered)          return; // Necesita breakout previo
   if(g_tradesToday >= InpMaxTradesDay) return;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(dt.hour >= InpBreakoutHourEnd) return;

   // Solo si no hay ya posición abierta del magic
   if(CountOpenPositions() > 0) return;

   // Verificar tiempo desde breakout (máx InpRetestWindowBars barras)
   if(g_breakoutTime > 0)
   {
      int barsSince = (int)((TimeCurrent() - g_breakoutTime) / PeriodSeconds(PERIOD_CURRENT));
      if(barsSince > InpRetestWindowBars) return;
   }

   double close = iClose(_Symbol, PERIOD_CURRENT, 0);
   double bbU, bbD, bbM, rsi, mfi, atr;
   if(!GetIndicators(bbU, bbD, bbM, rsi, mfi, atr)) return;

   double retestZone = InpRetestZone * _Point * 10;

   // Retest en zona de ruptura alcista: precio vuelve cerca del High del rango
   if(g_sesgoUp)
   {
      double retestLevel = g_rangeHigh + retestZone;
      if(close <= retestLevel && close >= g_rangeHigh - retestZone)
      {
         if(rsi > 45.0 && mfi > 45.0) // Confirmación momentum mínima
         {
            double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            double sl, tp;
            CalcSLTP(true, ask, atr, sl, tp);
            double lot = CalcDynamicLot(ask - sl, 0.75); // 75% del lote base

            if(trade.Buy(lot, _Symbol, ask, sl, tp))
            {
               g_tradesToday++;
               Print("🟢 RETEST LONG @ ", ask, " Lot:", lot);
            }
         }
      }
   }
}

//====================================================================
//  ★ SISTEMA PIRAMIDAL (Quantum Queen Grid-Pyramid Inspired)
//====================================================================
void ManagePyramid()
{
   if(!InpPyramidOn)    return;
   if(!g_triggered)     return;
   if(g_pyramidLevel >= InpPyramidLevels) return;
   if(g_tradesToday >= InpMaxTradesDay)   return;

   // Buscar la posición original
   ulong masterTicket = 0;
   double masterProfit = 0;
   bool   masterIsBuy  = false;
   double masterSL     = 0;
   double masterPrice  = 0;

   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      masterTicket   = ticket;
      masterProfit   = PositionGetDouble(POSITION_PROFIT);
      masterIsBuy    = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      masterSL       = PositionGetDouble(POSITION_SL);
      masterPrice    = PositionGetDouble(POSITION_PRICE_OPEN);
      break;
   }

   if(masterTicket == 0) return;

   double triggerPts = 0;
   if(g_pyramidLevel == 0) triggerPts = InpPyramidTrigger1 * _Point * 10;
   if(g_pyramidLevel == 1) triggerPts = InpPyramidTrigger2 * _Point * 10;

   double curPrice   = masterIsBuy
                       ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                       : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double moveInFav  = masterIsBuy ? (curPrice - masterPrice) : (masterPrice - curPrice);

   if(moveInFav < triggerPts) return;

   // Calcular lote pirámide (decrece con cada nivel)
   double pyrLotMult = MathPow(InpPyramidLotMult, g_pyramidLevel + 1);
   double pyrLot     = NormLot(g_entry1Lot * pyrLotMult);

   // SL/TP para posición pirámide
   double bbU, bbD, bbM, rsi, mfi, atr;
   if(!GetIndicators(bbU, bbD, bbM, rsi, mfi, atr)) return;

   double sl, tp;
   if(masterIsBuy)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      // SL de pirámide = BE de la entrada original (protege capital)
      sl = InpPyramidUseBE ? masterPrice : (ask - atr * InpATR_SL_Mult);
      tp = ask + atr * InpATR_TP_Mult * InpPyramidRR;

      if(trade.Buy(pyrLot, _Symbol, ask, sl, tp))
      {
         g_pyramidLevel++;
         g_tradesToday++;
         Print("📈 PIRÁMIDE L", g_pyramidLevel, " @ ", ask, " Lot:", pyrLot, " SL:", sl);
      }
   }
   else
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      sl = InpPyramidUseBE ? masterPrice : (bid + atr * InpATR_SL_Mult);
      tp = bid - atr * InpATR_TP_Mult * InpPyramidRR;

      if(trade.Sell(pyrLot, _Symbol, bid, sl, tp))
      {
         g_pyramidLevel++;
         g_tradesToday++;
         Print("📉 PIRÁMIDE L", g_pyramidLevel, " @ ", bid, " Lot:", pyrLot, " SL:", sl);
      }
   }
}

//====================================================================
//  GESTIÓN DE TRADES ABIERTOS
//====================================================================
void ManageOpenTrades()
{
   double totalPnL = 0;
   int    count    = 0;
   double dayPnL   = AccountInfoDouble(ACCOUNT_BALANCE) - g_dayStartBal;

   // Target diario: cerrar todo si se alcanza
   if(dayPnL >= InpDailyProfitUSD && InpDailyProfitUSD > 0)
   {
      CloseAllMagic();
      g_dayInvalid = true; // No más trades hoy
      Print("🎯 TARGET DIARIO alcanzado: $", dayPnL);
      return;
   }

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))          continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      double profit   = PositionGetDouble(POSITION_PROFIT);
      double openPrice= PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL    = PositionGetDouble(POSITION_SL);
      double curTP    = PositionGetDouble(POSITION_TP);
      double volume   = PositionGetDouble(POSITION_VOLUME);
      bool   isBuy    = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      datetime tOpen  = (datetime)PositionGetInteger(POSITION_TIME);

      totalPnL += profit;
      count++;

      // 1. Cierre por tiempo
      int barsOpen = (int)((TimeCurrent() - tOpen) / PeriodSeconds(PERIOD_CURRENT));
      if(barsOpen >= InpMaxBarsOpen)
      {
         trade.PositionClose(ticket);
         Print("⏱️ Cierre tiempo: ", barsOpen, " barras");
         continue;
      }

      // 2. ★ CIERRE PARCIAL PROGRESIVO
      if(InpPartialClose && ticket == GetOldestMagicTicket())
      {
         double slDist = MathAbs(openPrice - curSL);
         double curPrice = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                 : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double moveR   = slDist > 0 ? MathAbs(curPrice - openPrice) / slDist : 0;

         // Al 1R: cerrar 30% + mover SL a BE
         if(!g_partial1Done && moveR >= 1.0)
         {
            double closeVol = NormLot(volume * InpPartialAt1R);
            if(closeVol >= SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
            {
               trade.PositionClosePartial(ticket, closeVol);
               Print("💰 Cierre parcial 1 (30%) @ 1R | Vol:", closeVol);
            }
            // Mover SL a BE
            if(InpMoveToBreakEven && !g_beMoved)
            {
               double newSL = isBuy ? openPrice + _Point : openPrice - _Point;
               trade.PositionModify(ticket, newSL, curTP);
               g_beMoved = true;
               Print("🔒 SL movido a Break-Even");
            }
            g_partial1Done = true;
         }

         // Al 2R: cerrar 40% adicional
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

      // 3. Trailing Stop (ATR-based)
      if(InpTrailingOn) ApplyTrailingATR(ticket, isBuy, atr_cached);
   }

   // 4. Peak Profit Lock
   if(count > 0)
   {
      if(totalPnL > g_peakProfit) g_peakProfit = totalPnL;
      if(g_peakProfit >= InpMinProfitLock &&
         totalPnL < (g_peakProfit - InpProfitRetrace))
      {
         CloseAllMagic();
         Print("💰 Lock Profit: Peak=", g_peakProfit, " PnL=", totalPnL);
      }
   }
   else { g_peakProfit = 0; }
}

//====================================================================
//  ★ TRAILING STOP ATR-BASED
//====================================================================
void ApplyTrailingATR(ulong ticket, bool isBuy, double atr)
{
   if(!PositionSelectByTicket(ticket)) return;

   double curSL     = PositionGetDouble(POSITION_SL);
   double curTP     = PositionGetDouble(POSITION_TP);
   double curPrice  = PositionGetDouble(POSITION_PRICE_CURRENT);
   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double trailDist = (atr > 0) ? atr * InpTrailingATRMult : 10 * _Point * 10;

   // Trailing solo si precio ya en territorio positivo
   if(isBuy)
   {
      if(curPrice <= openPrice) return; // No trailar en negativo
      double newSL = curPrice - trailDist;
      if(newSL > curSL + _Point)
         trade.PositionModify(ticket, newSL, curTP);
   }
   else
   {
      if(curPrice >= openPrice) return;
      double newSL = curPrice + trailDist;
      if(newSL < curSL - _Point || curSL == 0)
         trade.PositionModify(ticket, newSL, curTP);
   }
}

//====================================================================
//  HELPERS
//====================================================================
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
   ulong  oldest   = 0;
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
//  PANEL DE INFORMACIÓN AMPLIADO
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

   string estado = g_dayInvalid   ? "❌ DÍA INVÁLIDO"  :
                   !g_initialized ? "⏳ CONSTRUYENDO"   :
                   g_triggered    ? "✅ OPERANDO"       : "🎯 ESPERANDO";

   string sesgoStr = g_sesgoUp ? "📈 ALCISTA (QQ Bias ON)" :
                    (g_sesgoDn ? "📉 BAJISTA" : "---");

   string pyramidStr = g_triggered
      ? StringFormat("E1+%d niveles | Vol: %.2f", g_pyramidLevel, totalVol)
      : "---";

   string txt = "";
   txt += "════ QUANTUM QUEEN HYBRID v3.0 – PYRAMID ════\n";
   txt += StringFormat("Hora actual    : %02d:%02d\n", dt.hour, dt.min);
   txt += StringFormat("Estado         : %s\n", estado);
   txt += StringFormat("Rango High     : %.2f\n", g_rangeHigh);
   txt += StringFormat("Rango Low      : %.2f\n", g_rangeLow);
   txt += StringFormat("Rango Size     : %.2f pts\n", g_rangeHigh - g_rangeLow);
   txt += StringFormat("Sesgo D1       : %s\n", sesgoStr);
   txt += StringFormat("Trades Hoy     : %d / %d\n", g_tradesToday, InpMaxTradesDay);
   txt += StringFormat("Pirámide       : %s\n", pyramidStr);
   txt += StringFormat("Cierre Parcial : %s%s\n",
          g_partial1Done?"✅1R ":"⬜1R ", g_partial2Done?"✅2R":"⬜2R");
   txt += StringFormat("BE Activado    : %s\n", g_beMoved?"✅ SÍ":"⬜ NO");
   txt += StringFormat("Posiciones     : %d\n", activePos);
   txt += StringFormat("PnL Abierto    : $%.2f\n", activePnL);
   txt += StringFormat("PnL Día        : $%.2f\n", dayPnL);
   txt += StringFormat("Balance        : $%.2f\n", balance);
   txt += StringFormat("Target Día     : $%.2f\n", InpDailyProfitUSD);
   txt += "══════════════════════════════════════════════\n";
   txt += StringFormat("QQ1 Squeeze    : %s | QQ2 DirBreak: %s\n",
          InpQQ1_Squeeze?"ON":"OFF", InpQQ2_DirBreak?"ON":"OFF");
   txt += StringFormat("QQ4 Trend      : %s | QQ6 VolMom  : %s\n",
          InpQQ4_Trend?"ON":"OFF", InpQQ6_VolMom?"ON":"OFF");
   txt += StringFormat("Gold Bull Bias : %s | ATR SLTP: %s\n",
          InpGoldBullBias?"ON":"OFF", InpUseATR_SLTP?"ON":"OFF");
   txt += StringFormat("Pirámide       : %s (%d niveles)\n",
          InpPyramidOn?"ON":"OFF", InpPyramidLevels);

   Comment(txt);
}

//+------------------------------------------------------------------+
//  FIN DEL CÓDIGO – QUANTUM QUEEN HYBRID PYRAMID v3.0
//+------------------------------------------------------------------+
