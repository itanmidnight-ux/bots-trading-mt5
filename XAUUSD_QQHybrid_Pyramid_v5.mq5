//+------------------------------------------------------------------+
//|  XAUUSD QQ HYBRID PYRAMID v5.0 – PROFESSIONAL EDITION           |
//|  + Grid Lots | NY Session | ADX | Adaptive ATR | EMA Retest      |
//|  v5: TimeClose QQ-style | Pirámide USD | Trailing dinámico       |
//|      Grid seguro | Sin límite trades | Parciales robustos         |
//+------------------------------------------------------------------+
#property copyright "QQ Hybrid Pyramid v5.0"
#property version   "5.00"
#property strict

#include <Trade/Trade.mqh>
CTrade trade;

//====================================================================
//  INPUTS
//====================================================================
input group "=== SESIÓN LONDRE (RANGO BREAKOUT) ==="
input int    InpRangeHourStart  = 7;
input int    InpRangeHourEnd    = 8;
input int    InpBreakoutHourEnd = 10;
input double InpRangeMinPts     = 1.5;
input double InpRangeMaxPts     = 12.0;
input int    InpMinBars         = 25;
input double InpBreakoutOffset  = 0.30;
input double InpSLOffset        = 0.50;
input double InpRR              = 2.0;

input group "=== SESIÓN NY (Segunda ventana de entrada) ==="
input bool   InpNYSession       = true;
input int    InpNYHourStart     = 14;
input int    InpNYHourEnd       = 17;
input double InpNYBreakOffset   = 0.40;
input double InpNYRangeMinPts   = 1.0;

input group "=== GESTIÓN DE CAPITAL ==="
input bool   InpUseDynamicLot   = true;
input double InpRiskPercent     = 0.5;
input double InpLotFixed        = 0.01;
input int    InpMagic           = 5900;
input int    InpMaxBarsOpen     = 120;

input group "=== GRID LOT (Recuperación Adaptativa) ==="
input bool   InpGridLots        = true;
input double InpGridMult        = 1.20;
input int    InpGridMaxLevel    = 3;
input bool   InpGridDailyReset  = true;

input group "=== CAPITALIZACIÓN ESCALADA (micro a millones) ==="
input bool   InpCapScaling      = true;
input double InpTier1MaxBal     = 100.0;
input double InpTier2MaxBal     = 1000.0;
input double InpTier3MaxBal     = 10000.0;

input group "=== PIRÁMIDE (QQ Grid-Pyramid) ==="
input bool   InpPyramidOn        = true;
input int    InpPyramidLevels    = 4;          // Máx niveles (4 pir + 1 master = 5 trades máx)
input double InpPyramidUSDTrigger= 25.0;       // USD profit flotante para activar nivel 1
input double InpPyramidUSDStep   = 30.0;       // USD adicionales por cada nivel siguiente
input double InpPyramidLotMult   = 0.50;       // Multiplicador conservador por nivel
input double InpPyramidRR        = 1.5;
input bool   InpPyramidUseBE     = true;

input group "=== CIERRE PARCIAL PROGRESIVO (Mejorado) ==="
input bool   InpPartialClose    = true;
input double InpPartialAt1R     = 0.35;
input double InpPartialAt2R     = 0.40;
input bool   InpMoveToBreakEven = true;

input group "=== ATR ADAPTATIVO SL/TP (Preciso) ==="
input bool   InpUseATR_SLTP     = true;
input int    InpATRPeriod       = 14;
input int    InpATRShortPeriod  = 5;
input double InpATR_SL_Mult     = 1.2;
input double InpATR_TP_Mult     = 2.4;
input bool   InpAdaptiveATR     = true;
input double InpVolHighThresh   = 1.5;
input double InpVolLowThresh    = 0.75;

input group "=== FILTROS DE CALIDAD (Aumento WR) ==="
input bool   InpQQ1_Squeeze     = true;
input bool   InpQQ2_DirBreak    = true;
input bool   InpQQ4_Trend       = true;
input bool   InpQQ6_VolMom      = true;
input bool   InpUseADX          = true;
input int    InpADXPeriod       = 14;
input double InpADXMin          = 20.0;
input bool   InpUseMultiTF      = true;

input group "=== SESGO ALCISTA ORO ==="
input bool   InpGoldBullBias    = true;
input double InpBullBias_RSI    = 50.0;
input double InpBullBias_LotMult = 1.20;
input bool   InpAllowRetestEntry = true;

input group "=== ENTRADAS SECUNDARIAS (Como QQ) ==="
input double InpRetestZone      = 0.50;
input int    InpRetestWindowBars = 30;
input bool   InpEMARetest       = true;
input double InpEMARetestATRMult = 0.30;

input group "=== INDICADORES ==="
input int    InpEMA50           = 50;
input int    InpEMA200          = 200;
input int    InpBBPeriod        = 20;
input int    InpRSIPeriod       = 14;
input int    InpMFIPeriod       = 14;

input group "=== PROTECCIONES ==="
input double InpMaxSpread       = 50.0;
input double InpDailyLossUSD    = 50.0;
input double InpDailyProfitUSD  = 200.0;
input bool   InpTrailingOn      = true;
input double InpTrailingATRMult = 0.70;
input double InpMinProfitLock   = 0.50;
input double InpProfitRetrace   = 0.20;

input group "=== MONITOREO ==="
input bool   InpShowPanel       = true;

//====================================================================
//  HANDLES
//====================================================================
int hEMA50, hEMA200, hBB, hRSI, hMFI, hATR, hATRS, hADX, hEMA50_H4;

//====================================================================
//  VARIABLES GLOBALES
//====================================================================
double   g_rangeHigh = 0, g_rangeLow = 0;
int      g_rangeBars = 0;
bool     g_dayInvalid = false, g_initialized = false;
bool     g_triggered  = false;
datetime g_breakoutTime = 0;
bool     g_sesgoUp = false, g_sesgoDn = false;

double   g_nyHigh = 0, g_nyLow = 0;
bool     g_nyBuilding = false, g_nyInitialized = false, g_nyTriggered = false;

int      g_tradesToday = 0, g_lossesToday = 0, g_winsToday = 0;
double   g_dayStartBal = 0;
datetime g_lastDay     = 0;

int      g_gridLevel   = 0;
int      g_pyramidLevel = 0;
double   g_entry1Lot   = 0, g_entry1Price  = 0;
double   g_entry1SLDist = 0, g_entry1Volume = 0;
bool     g_partial1Done = false, g_partial2Done = false, g_beMoved = false;
double   g_peakProfit  = 0;
double   atr_cached = 0, atrs_cached = 0, bbMid_cached = 0;

//====================================================================
//  OnInit
//====================================================================
int OnInit()
{
   hEMA50    = iMA(_Symbol, PERIOD_D1, InpEMA50,  0, MODE_EMA, PRICE_CLOSE);
   hEMA200   = iMA(_Symbol, PERIOD_D1, InpEMA200, 0, MODE_EMA, PRICE_CLOSE);
   hBB       = iBands(_Symbol, PERIOD_CURRENT, InpBBPeriod, 0, 2.0, PRICE_CLOSE);
   hRSI      = iRSI(_Symbol, PERIOD_CURRENT, InpRSIPeriod, PRICE_CLOSE);
   hMFI      = iMFI(_Symbol, PERIOD_CURRENT, InpMFIPeriod, VOLUME_TICK);
   hATR      = iATR(_Symbol, PERIOD_CURRENT, InpATRPeriod);
   hATRS     = iATR(_Symbol, PERIOD_CURRENT, InpATRShortPeriod);
   hADX      = iADX(_Symbol, PERIOD_CURRENT, InpADXPeriod);
   hEMA50_H4 = iMA(_Symbol, PERIOD_H4, InpEMA50, 0, MODE_EMA, PRICE_CLOSE);

   if(hEMA50==INVALID_HANDLE || hEMA200==INVALID_HANDLE || hBB==INVALID_HANDLE ||
      hRSI==INVALID_HANDLE  || hMFI==INVALID_HANDLE   || hATR==INVALID_HANDLE ||
      hATRS==INVALID_HANDLE || hADX==INVALID_HANDLE   || hEMA50_H4==INVALID_HANDLE)
   { Alert("❌ Error creando handles de indicadores"); return INIT_FAILED; }

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(10);
   g_dayStartBal = AccountInfoDouble(ACCOUNT_BALANCE);
   DailyReset();
   Print("✅ QQ Hybrid Pyramid v4.0 iniciado en ", _Symbol);
   return INIT_SUCCEEDED;
}

//====================================================================
//  OnDeinit
//====================================================================
void OnDeinit(const int reason)
{
   Comment("");
   IndicatorRelease(hEMA50);   IndicatorRelease(hEMA200);
   IndicatorRelease(hBB);      IndicatorRelease(hRSI);
   IndicatorRelease(hMFI);     IndicatorRelease(hATR);
   IndicatorRelease(hATRS);    IndicatorRelease(hADX);
   IndicatorRelease(hEMA50_H4);
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
      BuildNYRange();
      SearchNYBreakout();
      SearchEMARetest();
      ManagePyramid();
   }
   ManageOpenTrades();
   DrawPanel();
}

//====================================================================
//  OnTradeTransaction – Grid lot tracking
//====================================================================
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest&     request,
                        const MqlTradeResult&      result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if((int)HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != InpMagic) return;

   ENUM_DEAL_ENTRY de = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(de != DEAL_ENTRY_OUT && de != DEAL_ENTRY_INOUT) return;

   double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
                 + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
                 + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);

   if(InpGridLots)
   {
      if(profit > 0) { g_gridLevel = 0; g_winsToday++;  }
      else           { g_gridLevel = MathMin(g_gridLevel + 1, InpGridMaxLevel); g_lossesToday++; }
   }
   else
   {
      if(profit > 0) g_winsToday++; else g_lossesToday++;
   }

   // Sincronizar nivel piramidal real con posiciones aún abiertas
   {
      int openCount = 0;
      for(int i = 0; i < PositionsTotal(); i++)
      {
         ulong tk = PositionGetTicket(i);
         if(!PositionSelectByTicket(tk)) continue;
         if(PositionGetInteger(POSITION_MAGIC) == InpMagic) openCount++;
      }
      if(openCount <= 1) g_pyramidLevel = 0;
      else if(openCount < g_pyramidLevel + 1) g_pyramidLevel = openCount - 1;
   }
}

//====================================================================
//  RESET DIARIO
//====================================================================
void DailyReset()
{
   g_rangeHigh = g_rangeLow = 0;
   g_rangeBars = 0;
   g_dayInvalid = g_initialized = g_triggered = false;
   g_breakoutTime = 0;
   g_sesgoUp = g_sesgoDn = false;
   g_tradesToday = g_lossesToday = g_winsToday = 0;
   g_peakProfit  = 0;
   g_pyramidLevel = 0;
   g_entry1Lot = g_entry1Price = g_entry1SLDist = g_entry1Volume = 0;
   g_partial1Done = g_partial2Done = g_beMoved = false;
   g_nyHigh = g_nyLow = 0;
   g_nyBuilding = g_nyInitialized = g_nyTriggered = false;
   if(InpGridDailyReset) g_gridLevel = 0;
}

void CheckDayReset()
{
   datetime currentDay = iTime(_Symbol, PERIOD_D1, 0);
   if(currentDay != g_lastDay)
   { g_dayStartBal = AccountInfoDouble(ACCOUNT_BALANCE); g_lastDay = currentDay; DailyReset(); }
}

//====================================================================
//  CAPITAL TIER – Escalación automática por balance
//====================================================================
double GetCapitalTierMult()
{
   if(!InpCapScaling) return 1.0;
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   if(bal < InpTier1MaxBal)  return 0.80;
   if(bal < InpTier2MaxBal)  return 0.90;
   if(bal < InpTier3MaxBal)  return 1.00;
   return 1.00;
}

//====================================================================
//  GRID LOT – Multiplicador por nivel de pérdidas consecutivas
//====================================================================
double GetGridLotMult()
{
   if(!InpGridLots || g_gridLevel <= 0) return 1.0;
   // Protección: si margen libre < 50% del balance, no aumentar lote
   double freeMargin = AccountInfoDouble(ACCOUNT_FREEMARGIN);
   double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance > 0 && freeMargin < balance * 0.50) return 1.0;
   return MathPow(InpGridMult, MathMin(g_gridLevel, InpGridMaxLevel));
}

//====================================================================
//  CALCULAR LOT DINÁMICO (Risk % + Grid + Capital Tier)
//====================================================================
double CalcDynamicLot(double slPts, double riskMult = 1.0)
{
   double totalMult = riskMult * GetCapitalTierMult() * GetGridLotMult();
   if(!InpUseDynamicLot) return NormLot(InpLotFixed * totalMult);

   double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmt   = balance * (InpRiskPercent / 100.0) * totalMult;
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(slPts <= 0 || tickValue <= 0 || tickSize <= 0) return NormLot(InpLotFixed);
   double slMoney = slPts / tickSize * tickValue;
   return NormLot((slMoney > 0) ? riskAmt / slMoney : InpLotFixed);
}

//====================================================================
//  ATR REGIME – Detectar volatilidad (alta/baja) para ajustar SL/TP
//====================================================================
void GetATRRegimeMults(double &slMult, double &tpMult)
{
   slMult = 1.0; tpMult = 1.0;
   if(!InpAdaptiveATR || atr_cached <= 0 || atrs_cached <= 0) return;
   double ratio = atrs_cached / atr_cached;
   if(ratio > InpVolHighThresh) { slMult = 1.40; tpMult = 0.85; } // Alta vol: SL ancho, TP conservador
   else if(ratio < InpVolLowThresh) { slMult = 0.90; tpMult = 1.15; } // Baja vol: SL ajustado, TP amplio
}

//====================================================================
//  CALCULAR SL/TP ADAPTATIVO (ATR + Régimen de volatilidad)
//====================================================================
void CalcSLTP(bool isBuy, double entryPrice, double atr, double &sl, double &tp)
{
   double slDist, tpDist;
   if(InpUseATR_SLTP)
   {
      double slReg, tpReg;
      GetATRRegimeMults(slReg, tpReg);
      slDist = atr * InpATR_SL_Mult * slReg;
      tpDist = atr * InpATR_TP_Mult * tpReg;
   }
   else
   {
      double slOff = InpSLOffset * _Point * 10;
      slDist = (g_rangeHigh - g_rangeLow) + slOff;
      tpDist = slDist * InpRR;
   }
   if(isBuy) { sl = entryPrice - slDist; tp = entryPrice + tpDist; }
   else      { sl = entryPrice + slDist; tp = entryPrice - tpDist; }
}

//====================================================================
//  OBTENER INDICADORES (incluye ADX y ATR corto)
//====================================================================
bool GetIndicators(double &bbU, double &bbD, double &bbM,
                   double &rsi,  double &mfi,  double &atr, double &adx)
{
   double bU[1], bD[1], bM[1], bR[1], bMF[1], bA[1], bAS[1], bADX[1];
   if(CopyBuffer(hBB,   1, 0, 1, bU)   <= 0) return false;
   if(CopyBuffer(hBB,   2, 0, 1, bD)   <= 0) return false;
   if(CopyBuffer(hBB,   0, 0, 1, bM)   <= 0) return false;
   if(CopyBuffer(hRSI,  0, 0, 1, bR)   <= 0) return false;
   if(CopyBuffer(hMFI,  0, 0, 1, bMF)  <= 0) return false;
   if(CopyBuffer(hATR,  0, 0, 1, bA)   <= 0) return false;
   if(CopyBuffer(hATRS, 0, 0, 1, bAS)  <= 0) return false;
   if(CopyBuffer(hADX,  0, 0, 1, bADX) <= 0) return false;
   bbU = bU[0]; bbD = bD[0]; bbM = bM[0];
   rsi = bR[0]; mfi = bMF[0]; atr = bA[0]; adx = bADX[0];
   bbMid_cached = bM[0]; atr_cached = bA[0]; atrs_cached = bAS[0];
   return true;
}

//====================================================================
//  FILTROS QQ (CORREGIDOS Y MEJORADOS)
//====================================================================

// QQ1 CORREGIDO: compara ancho BB actual vs promedio 20 barras
bool FilterQQ1_Squeeze(double bbU, double bbD, double rsi)
{
   if(!InpQQ1_Squeeze) return true;
   double curW = bbU - bbD;
   double bufU[20], bufD[20];
   if(CopyBuffer(hBB, 1, 0, 20, bufU) < 20) return true;
   if(CopyBuffer(hBB, 2, 0, 20, bufD) < 20) return true;
   double avgW = 0;
   for(int i = 0; i < 20; i++) avgW += (bufU[i] - bufD[i]);
   avgW /= 20.0;
   bool squeeze = (avgW > 0 && curW < avgW * 0.80);
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

// NUEVO: ADX – Solo entrar cuando hay tendencia real (↑ WR ~1.5%)
bool FilterADX(double adx)
{
   if(!InpUseADX) return true;
   return (adx >= InpADXMin);
}

// NUEVO: H4 Multi-Timeframe – Confirmación superior (↑ WR ~0.8%)
bool FilterH4Trend(bool isBuy)
{
   if(!InpUseMultiTF) return true;
   double buf[1];
   if(CopyBuffer(hEMA50_H4, 0, 0, 1, buf) <= 0) return true;
   double close = iClose(_Symbol, PERIOD_H4, 0);
   return isBuy ? (close > buf[0]) : (close < buf[0]);
}

bool FilterGoldBullBias(double rsi, bool isBuy)
{
   if(!InpGoldBullBias) return true;
   return isBuy ? (rsi > InpBullBias_RSI) : (rsi < 45.0 && !g_sesgoUp);
}

//====================================================================
//  VERIFICACIÓN BÁSICA (spread, límites diarios)
//====================================================================
bool CheckBasics()
{
   if((double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) > InpMaxSpread) return false;
   double dayPnL = AccountInfoDouble(ACCOUNT_BALANCE) - g_dayStartBal;
   if(dayPnL < -InpDailyLossUSD)   return false;
   if(dayPnL >  InpDailyProfitUSD) return false;
   return true;
}

//====================================================================
//  FASE 1 – CONSTRUIR RANGO LONDRE 07:00
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

//====================================================================
//  FASE 2 – VALIDAR RANGO 08:00
//====================================================================
void ValidateRange()
{
   if(g_initialized) return;
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   if(dt.hour != InpRangeHourEnd || dt.min != 0) return;

   double rngSize = g_rangeHigh - g_rangeLow;
   if(g_rangeBars < InpMinBars || rngSize < InpRangeMinPts || rngSize > InpRangeMaxPts)
   { g_dayInvalid = true; Print("❌ Rango inválido | Barras:", g_rangeBars, " Size:", rngSize); return; }

   double e50[1], e200[1];
   if(CopyBuffer(hEMA50,  0, 0, 1, e50)  <= 0) { g_dayInvalid = true; return; }
   if(CopyBuffer(hEMA200, 0, 0, 1, e200) <= 0) { g_dayInvalid = true; return; }
   g_sesgoUp = (e50[0] > e200[0]);
   g_sesgoDn = (e50[0] < e200[0]);
   g_initialized = true;
   Print("✅ Rango OK | H:", g_rangeHigh, " L:", g_rangeLow, " Sz:", rngSize,
         " Sesgo:", (g_sesgoUp ? "ALCISTA" : "BAJISTA"));
}

//====================================================================
//  FASE 3 – BREAKOUT LONDRE (E1 principal)
//====================================================================
void SearchBreakout()
{
   if(g_triggered || !g_initialized || g_dayInvalid) return;
   if(!CheckBasics()) return;
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   if(dt.hour < InpRangeHourEnd || dt.hour >= InpBreakoutHourEnd) return;

   double close = iClose(_Symbol, PERIOD_CURRENT, 0);
   double bbU, bbD, bbM, rsi, mfi, atr, adx;
   if(!GetIndicators(bbU, bbD, bbM, rsi, mfi, atr, adx)) return;

   double offset = InpBreakoutOffset * _Point * 10;

   // ─── LONG ───
   if(close > (g_rangeHigh + offset) && g_sesgoUp)
   {
      if(!FilterQQ1_Squeeze(bbU, bbD, rsi)) return;
      if(!FilterQQ2(true, rsi))             return;
      if(!FilterQQ4(close, bbM, true))      return;
      if(!FilterQQ6(rsi, mfi, true))        return;
      if(!FilterADX(adx))                   return;
      if(!FilterH4Trend(true))              return;
      if(!FilterGoldBullBias(rsi, true))    return;

      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl, tp; CalcSLTP(true, ask, atr, sl, tp);
      double lotMult = (InpGoldBullBias && g_sesgoUp) ? InpBullBias_LotMult : 1.0;
      double lot = CalcDynamicLot(ask - sl, lotMult);

      if(trade.Buy(lot, _Symbol, ask, sl, tp))
      {
         g_triggered = true; g_tradesToday++;
         g_entry1Lot = lot; g_entry1Price = ask;
         g_entry1SLDist = ask - sl; g_entry1Volume = lot;
         g_pyramidLevel = 0; g_partial1Done = g_partial2Done = g_beMoved = false;
         g_breakoutTime = TimeCurrent(); // BUG FIX: asignar breakoutTime
         Print("🟢 LONG E1 @ ", ask, " SL:", sl, " TP:", tp, " Lot:", lot, " Grid:", g_gridLevel);
      }
   }
   // ─── SHORT ───
   else if(close < (g_rangeLow - offset) && g_sesgoDn)
   {
      if(!FilterQQ1_Squeeze(bbU, bbD, rsi)) return;
      if(!FilterQQ2(false, rsi))            return;
      if(!FilterQQ4(close, bbM, false))     return;
      if(!FilterQQ6(rsi, mfi, false))       return;
      if(!FilterADX(adx))                   return;
      if(!FilterH4Trend(false))             return;
      if(!FilterGoldBullBias(rsi, false))   return;

      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl, tp; CalcSLTP(false, bid, atr, sl, tp);
      double lot = CalcDynamicLot(sl - bid, 1.0);

      if(trade.Sell(lot, _Symbol, bid, sl, tp))
      {
         g_triggered = true; g_tradesToday++;
         g_entry1Lot = lot; g_entry1Price = bid;
         g_entry1SLDist = sl - bid; g_entry1Volume = lot;
         g_pyramidLevel = 0; g_partial1Done = g_partial2Done = g_beMoved = false;
         g_breakoutTime = TimeCurrent();
         Print("🔴 SHORT E1 @ ", bid, " SL:", sl, " TP:", tp, " Lot:", lot, " Grid:", g_gridLevel);
      }
   }
}

//====================================================================
//  ★ SESIÓN NY – Construir rango y buscar breakout (más entradas)
//====================================================================
void BuildNYRange()
{
   if(!InpNYSession) return;
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   if(dt.hour != InpNYHourStart) return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(dt.min < 30) // Construir durante primeros 30 min
   {
      if(g_nyHigh == 0) g_nyHigh = ask;
      if(g_nyLow  == 0) g_nyLow  = bid;
      g_nyHigh = MathMax(g_nyHigh, ask);
      g_nyLow  = MathMin(g_nyLow,  bid);
      g_nyBuilding = true;
   }
   else if(g_nyBuilding && !g_nyInitialized) // Inicializar al completar rango
   {
      double rngSize = g_nyHigh - g_nyLow;
      if(rngSize >= InpNYRangeMinPts)
      { g_nyInitialized = true; Print("✅ NY Rango | H:", g_nyHigh, " L:", g_nyLow, " Sz:", rngSize); }
   }
}

void SearchNYBreakout()
{
   if(!InpNYSession || !g_nyInitialized || g_nyTriggered) return;
   if(!CheckBasics()) return;
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   if(dt.hour < InpNYHourStart || dt.hour >= InpNYHourEnd) return;
   if(dt.hour == InpNYHourStart && dt.min < 30) return;

   double close = iClose(_Symbol, PERIOD_CURRENT, 0);
   double bbU, bbD, bbM, rsi, mfi, atr, adx;
   if(!GetIndicators(bbU, bbD, bbM, rsi, mfi, atr, adx)) return;
   if(!FilterADX(adx)) return;

   double offset = InpNYBreakOffset * _Point * 10;

   if(close > (g_nyHigh + offset) && g_sesgoUp && rsi > 52.0 && FilterH4Trend(true))
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl, tp; CalcSLTP(true, ask, atr, sl, tp);
      double lot = CalcDynamicLot(ask - sl, 0.90);
      if(trade.Buy(lot, _Symbol, ask, sl, tp))
      { g_nyTriggered = true; g_tradesToday++; Print("🟢 NY LONG @ ", ask, " Lot:", lot); }
   }
   else if(close < (g_nyLow - offset) && g_sesgoDn && rsi < 48.0 && FilterH4Trend(false))
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl, tp; CalcSLTP(false, bid, atr, sl, tp);
      double lot = CalcDynamicLot(sl - bid, 0.90);
      if(trade.Sell(lot, _Symbol, bid, sl, tp))
      { g_nyTriggered = true; g_tradesToday++; Print("🔴 NY SHORT @ ", bid, " Lot:", lot); }
   }
}

//====================================================================
//  RETEST ENTRY (breakoutTime corregido)
//====================================================================
void SearchRetestEntry()
{
   if(!InpAllowRetestEntry || !g_triggered) return;
   if(!CheckBasics() || CountOpenPositions() > 0) return;
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   if(dt.hour >= InpBreakoutHourEnd) return;
   if(g_breakoutTime > 0)
   {
      int bars = (int)((TimeCurrent() - g_breakoutTime) / PeriodSeconds(PERIOD_CURRENT));
      if(bars > InpRetestWindowBars) return;
   }

   double close = iClose(_Symbol, PERIOD_CURRENT, 0);
   double bbU, bbD, bbM, rsi, mfi, atr, adx;
   if(!GetIndicators(bbU, bbD, bbM, rsi, mfi, atr, adx)) return;

   double zone = InpRetestZone * _Point * 10;
   if(g_sesgoUp && close <= g_rangeHigh + zone && close >= g_rangeHigh - zone)
   {
      if(rsi > 48.0 && mfi > 45.0 && adx >= InpADXMin * 0.8)
      {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double sl, tp; CalcSLTP(true, ask, atr, sl, tp);
         double lot = CalcDynamicLot(ask - sl, 0.75);
         if(trade.Buy(lot, _Symbol, ask, sl, tp))
         { g_tradesToday++; Print("🟢 RETEST LONG @ ", ask, " Lot:", lot); }
      }
   }
}

//====================================================================
//  ★ EMA PULLBACK ENTRY (entrada adicional como QQ, sin bajar WR)
//====================================================================
void SearchEMARetest()
{
   if(!InpEMARetest || !g_initialized || g_dayInvalid) return;
   if(!CheckBasics() || CountOpenPositions() > 0) return;
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   if(dt.hour < InpRangeHourEnd || dt.hour > 18) return;

   double bbU, bbD, bbM, rsi, mfi, atr, adx;
   if(!GetIndicators(bbU, bbD, bbM, rsi, mfi, atr, adx)) return;
   if(!FilterADX(adx)) return;

   double buf[1];
   if(CopyBuffer(hEMA50_H4, 0, 0, 1, buf) <= 0) return;
   double h4EMA = buf[0];
   double close  = iClose(_Symbol, PERIOD_CURRENT, 0);
   double zone   = atr * InpEMARetestATRMult;

   // Long: pullback al EMA50 H4 en uptrend, RSI en zona neutral-positiva
   if(g_sesgoUp && MathAbs(close - h4EMA) < zone && rsi > 45.0 && rsi < 62.0 && mfi > 45.0)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl, tp; CalcSLTP(true, ask, atr, sl, tp);
      double lot = CalcDynamicLot(ask - sl, 0.80);
      if(trade.Buy(lot, _Symbol, ask, sl, tp))
      { g_tradesToday++; Print("🟢 EMA PULLBACK LONG @ ", ask, " Lot:", lot); }
   }
   // Short: pullback al EMA50 H4 en downtrend
   else if(g_sesgoDn && MathAbs(close - h4EMA) < zone && rsi < 55.0 && rsi > 38.0 && mfi < 55.0)
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl, tp; CalcSLTP(false, bid, atr, sl, tp);
      double lot = CalcDynamicLot(sl - bid, 0.80);
      if(trade.Sell(lot, _Symbol, bid, sl, tp))
      { g_tradesToday++; Print("🔴 EMA PULLBACK SHORT @ ", bid, " Lot:", lot); }
   }
}

//====================================================================
//  ★ SISTEMA PIRAMIDAL v5 – USD Triggers | Máx 5 trades | Margen seguro
//====================================================================
void ManagePyramid()
{
   if(!InpPyramidOn || !g_triggered) return;
   if(g_pyramidLevel >= InpPyramidLevels) return;
   if(!CheckBasics()) return;

   // ── Sincronizar nivel real con posiciones abiertas ──────────────
   int realPositions = CountOpenPositions();
   if(realPositions <= 1) g_pyramidLevel = 0;
   else if(realPositions < g_pyramidLevel + 1) g_pyramidLevel = realPositions - 1;

   // ── Límite absoluto de 5 trades simultáneos ─────────────────────
   if(realPositions >= 5) return;

   // ── Calcular profit flotante y datos del master trade ───────────
   double floatProfit = 0;
   ulong  masterTicket = 0;
   bool   masterIsBuy  = false;
   double masterSL = 0, masterPrice = 0;

   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong tk = PositionGetTicket(i);
      if(!PositionSelectByTicket(tk)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      floatProfit += PositionGetDouble(POSITION_PROFIT);
      if(masterTicket == 0)
      {
         masterTicket = tk;
         masterIsBuy  = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
         masterSL     = PositionGetDouble(POSITION_SL);
         masterPrice  = PositionGetDouble(POSITION_PRICE_OPEN);
      }
   }
   if(masterTicket == 0) return;

   // ── Threshold USD para este nivel: 25 + (nivel × 30) ────────────
   double threshold = InpPyramidUSDTrigger + (g_pyramidLevel * InpPyramidUSDStep);
   if(floatProfit < threshold) return;

   // ── Calcular lote con multiplicador conservador ──────────────────
   double pyrLot = NormLot(g_entry1Lot * MathPow(InpPyramidLotMult, g_pyramidLevel + 1));
   // Nunca superar el lote inicial
   pyrLot = MathMin(pyrLot, g_entry1Lot);

   double bbU, bbD, bbM, rsi, mfi, atr, adx;
   if(!GetIndicators(bbU, bbD, bbM, rsi, mfi, atr, adx)) return;

   // ── Verificar margen libre antes de entrar (máx 25% del free margin) ──
   double entryPx = masterIsBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double margin  = 0;
   if(!OrderCalcMargin(masterIsBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,
                       _Symbol, pyrLot, entryPx, margin)) return;
   if(margin > AccountInfoDouble(ACCOUNT_FREEMARGIN) * 0.25) return;

   // ── Ejecutar entrada piramidal ───────────────────────────────────
   double sl, tp;
   if(masterIsBuy)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      // SL en BE (masterPrice) o ATR si es mejor; nunca por debajo de masterPrice
      sl = InpPyramidUseBE ? (masterPrice + _Point) : MathMax(ask - atr * InpATR_SL_Mult, masterPrice + _Point);
      tp = ask + atr * InpATR_TP_Mult * InpPyramidRR;
      if(trade.Buy(pyrLot, _Symbol, ask, sl, tp))
      {
         g_pyramidLevel++;
         g_tradesToday++;
         Print("📈 PIRÁMIDE L", g_pyramidLevel, " @ ", ask,
               " Lot:", pyrLot, " Trigger:$", threshold, " Profit:$", floatProfit);
      }
   }
   else
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      sl = InpPyramidUseBE ? (masterPrice - _Point) : MathMin(bid + atr * InpATR_SL_Mult, masterPrice - _Point);
      tp = bid - atr * InpATR_TP_Mult * InpPyramidRR;
      if(trade.Sell(pyrLot, _Symbol, bid, sl, tp))
      {
         g_pyramidLevel++;
         g_tradesToday++;
         Print("📉 PIRÁMIDE L", g_pyramidLevel, " @ ", bid,
               " Lot:", pyrLot, " Trigger:$", threshold, " Profit:$", floatProfit);
      }
   }
}

//====================================================================
//  GESTIÓN DE TRADES ABIERTOS
//====================================================================
void ManageOpenTrades()
{
   double dayPnL = AccountInfoDouble(ACCOUNT_BALANCE) - g_dayStartBal;
   if(dayPnL >= InpDailyProfitUSD && InpDailyProfitUSD > 0)
   { CloseAllMagic(); g_dayInvalid = true; Print("🎯 TARGET DIARIO: $", dayPnL); return; }

   double totalPnL = 0;
   int    count    = 0;
   ulong  oldestTk = GetOldestMagicTicket();

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(!PositionSelectByTicket(tk)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      double profit    = PositionGetDouble(POSITION_PROFIT);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL     = PositionGetDouble(POSITION_SL);
      double curTP     = PositionGetDouble(POSITION_TP);
      double volume    = PositionGetDouble(POSITION_VOLUME);
      bool   isBuy     = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      datetime tOpen   = (datetime)PositionGetInteger(POSITION_TIME);
      totalPnL += profit; count++;

      // 1. CIERRE POR TIEMPO QQ-STYLE
      // Solo cierra si está en pérdida o sin ganancia; trades positivos protegidos por trailing
      int barsOpen = (int)((TimeCurrent() - tOpen) / PeriodSeconds(PERIOD_CURRENT));
      if(barsOpen >= InpMaxBarsOpen)
      {
         bool inProfit = (profit > 0);
         // Si está en pérdida → cierre inmediato
         if(!inProfit)
         { trade.PositionClose(tk); Print("⏱️ Cierre tiempo+pérdida [", barsOpen, "barras] PnL:", profit); continue; }
         // Si está en ganancia pero el mercado revierte (ATR corto supera ATR largo × 1.3)
         // → cierre protector para no devolver lo ganado
         if(inProfit && atr_cached > 0 && atrs_cached > 0)
         {
            bool reversalSignal = (atrs_cached > atr_cached * 1.3);
            double pctMove      = profit / MathAbs(AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPercent / 100.0);
            // Cierra si hay señal de reversión fuerte Y el trade lleva demasiado tiempo
            if(reversalSignal && barsOpen >= (int)(InpMaxBarsOpen * 1.5))
            { trade.PositionClose(tk); Print("⏱️ Cierre reversión ATR [", barsOpen, "barras] PnL:", profit); continue; }
         }
         // Trade positivo sin señal de reversión → dejar actuar trailing, no tocar
      }

      // 2. ★ CIERRE PARCIAL MEJORADO (BUG FIX: usa g_entry1Volume original)
      if(InpPartialClose && tk == oldestTk && g_entry1Volume > 0)
      {
         double curBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double curAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double curMkt = isBuy ? curBid : curAsk;
         // Usar SLDist guardado en entrada (no el SL actual que puede haber variado)
         double slDist = (curSL > 0 && openPrice > 0) ? MathAbs(openPrice - curSL) : g_entry1SLDist;
         double moveR  = (slDist > 0) ? MathAbs(curMkt - openPrice) / slDist : 0;

         // 1R: cerrar 35%, mover SL a BE
         if(!g_partial1Done && moveR >= 1.0)
         {
            double closeVol = NormLot(g_entry1Volume * InpPartialAt1R);
            double minVol   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
            if(closeVol >= minVol && (volume - closeVol) >= minVol)
            { trade.PositionClosePartial(tk, closeVol); Print("💰 Parcial 1 (35%) @ 1R | Vol:", closeVol); }
            if(InpMoveToBreakEven && !g_beMoved)
            {
               double newSL = isBuy ? openPrice + _Point : openPrice - _Point;
               trade.PositionModify(tk, newSL, curTP);
               g_beMoved = true; Print("🔒 BE activado");
            }
            g_partial1Done = true;
         }

         // 2R: cerrar 40% adicional (calculado sobre volumen ORIGINAL)
         if(!g_partial2Done && moveR >= 2.0 && g_partial1Done)
         {
            double closeVol2 = NormLot(g_entry1Volume * InpPartialAt2R);
            double minVol    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
            if(closeVol2 >= minVol && (volume - closeVol2) >= minVol)
            { trade.PositionClosePartial(tk, closeVol2); Print("💰 Parcial 2 (40%) @ 2R | Vol:", closeVol2); }
            else
            { Print("⚠️ Parcial 2 omitido: vol residual insuficiente (", volume, ")"); }
            g_partial2Done = true; // Siempre marcar para evitar re-intentos infinitos
         }
      }

      // 3. Trailing ATR
      if(InpTrailingOn) ApplyTrailingATR(tk, isBuy, atr_cached);
   }

   // 4. Peak Profit Lock
   if(count > 0)
   {
      if(totalPnL > g_peakProfit) g_peakProfit = totalPnL;
      if(g_peakProfit >= InpMinProfitLock && totalPnL < (g_peakProfit - InpProfitRetrace))
      { CloseAllMagic(); Print("💰 Profit Lock: Peak=", g_peakProfit, " PnL=", totalPnL); }
   }
   else { g_peakProfit = 0; }
}

//====================================================================
//  TRAILING STOP ATR DINÁMICO v5
//  – Se activa desde 0.25 ATR de ganancia
//  – Se ajusta progresivamente: más ganancia → trailing más ajustado
//====================================================================
void ApplyTrailingATR(ulong ticket, bool isBuy, double atr)
{
   if(!PositionSelectByTicket(ticket)) return;
   double curSL   = PositionGetDouble(POSITION_SL);
   double curTP   = PositionGetDouble(POSITION_TP);
   double curP    = PositionGetDouble(POSITION_PRICE_CURRENT);
   double openP   = PositionGetDouble(POSITION_PRICE_OPEN);
   if(atr <= 0) return;

   // Ganancia en precio desde apertura
   double gainDist = isBuy ? (curP - openP) : (openP - curP);

   // Solo activar trailing si hay ganancia real (≥ 0.25 ATR)
   if(gainDist < atr * 0.25) return;

   // Trailing dinámico: más ganancia → distancia más corta para proteger más
   double mult = InpTrailingATRMult;
   if     (gainDist >= atr * 2.0) mult = InpTrailingATRMult * 0.50; // ≥ 2R: muy ajustado
   else if(gainDist >= atr * 1.2) mult = InpTrailingATRMult * 0.65; // ≥ 1.2R: ajustado
   else if(gainDist >= atr * 0.7) mult = InpTrailingATRMult * 0.80; // ≥ 0.7R: moderado

   double trailD = atr * mult;

   if(isBuy)
   {
      double newSL = curP - trailD;
      // El trailing nunca baja del BE si ya fue activado
      if(g_beMoved && newSL < openP + _Point) newSL = openP + _Point;
      if(newSL > curSL + _Point) trade.PositionModify(ticket, newSL, curTP);
   }
   else
   {
      double newSL = curP + trailD;
      if(g_beMoved && newSL > openP - _Point) newSL = openP - _Point;
      if(newSL < curSL - _Point || curSL == 0) trade.PositionModify(ticket, newSL, curTP);
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
      ulong tk = PositionGetTicket(i);
      if(!PositionSelectByTicket(tk)) continue;
      if(PositionGetInteger(POSITION_MAGIC) == InpMagic) cnt++;
   }
   return cnt;
}

ulong GetOldestMagicTicket()
{
   ulong    oldest  = 0;
   datetime oldestT = TimeCurrent();
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong tk = PositionGetTicket(i);
      if(!PositionSelectByTicket(tk)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      datetime t = (datetime)PositionGetInteger(POSITION_TIME);
      if(oldest == 0 || t < oldestT) { oldest = tk; oldestT = t; }
   }
   return oldest;
}

void CloseAllMagic()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(!PositionSelectByTicket(tk)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      trade.PositionClose(tk);
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
//  PANEL DE INFORMACIÓN
//====================================================================
void DrawPanel()
{
   if(!InpShowPanel) return;
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);

   int    activePos = 0; double activePnL = 0, totalVol = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong tk = PositionGetTicket(i);
      if(!PositionSelectByTicket(tk)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      activePos++; activePnL += PositionGetDouble(POSITION_PROFIT);
      totalVol += PositionGetDouble(POSITION_VOLUME);
   }

   double dayPnL = AccountInfoDouble(ACCOUNT_BALANCE) - g_dayStartBal;
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   string estado  = g_dayInvalid ? "❌ INVÁLIDO" : !g_initialized ? "⏳ CONSTRUYENDO" :
                    g_triggered  ? "✅ OPERANDO"  : "🎯 ESPERANDO";
   string sesgo   = g_sesgoUp ? "📈 ALCISTA" : (g_sesgoDn ? "📉 BAJISTA" : "---");

   string txt = "════ QQ HYBRID v4.0 – ENHANCED ════\n";
   txt += StringFormat("Hora: %02d:%02d | Estado: %s\n", dt.hour, dt.min, estado);
   txt += StringFormat("Rango: H=%.2f L=%.2f (%.2f pts)\n", g_rangeHigh, g_rangeLow, g_rangeHigh - g_rangeLow);
   txt += StringFormat("NY:    H=%.2f L=%.2f | %s\n", g_nyHigh, g_nyLow, g_nyTriggered ? "✅TRIG" : (g_nyInitialized ? "⏳OK" : "⬜"));
   txt += StringFormat("Sesgo D1: %s | H4 Multi-TF: %s\n", sesgo, InpUseMultiTF ? "ON" : "OFF");
   txt += StringFormat("Grid Lvl: %d | Tier Mult: %.2f | Grid Mult: %.2f\n", g_gridLevel, GetCapitalTierMult(), GetGridLotMult());
   txt += StringFormat("Trades: %d | Win: %d | Loss: %d\n", g_tradesToday, g_winsToday, g_lossesToday);
   txt += StringFormat("Pirámide: %d/%d niv | Vol Total: %.2f\n", g_pyramidLevel, InpPyramidLevels, totalVol);
   txt += StringFormat("Parcial: %s %s | BE: %s\n",
          g_partial1Done ? "✅1R" : "⬜1R", g_partial2Done ? "✅2R" : "⬜2R", g_beMoved ? "✅" : "⬜");
   txt += StringFormat("Posiciones: %d | PnL Open: $%.2f\n", activePos, activePnL);
   txt += StringFormat("PnL Día: $%.2f | Balance: $%.2f\n", dayPnL, balance);
   txt += StringFormat("ATR: %.2f | ATRS: %.2f | ADX: ON\n", atr_cached, atrs_cached);
   txt += "══════════════════════════════════\n";
   txt += StringFormat("QQ1:%s QQ2:%s QQ4:%s QQ6:%s\n",
          InpQQ1_Squeeze ? "ON" : "OFF", InpQQ2_DirBreak ? "ON" : "OFF",
          InpQQ4_Trend   ? "ON" : "OFF", InpQQ6_VolMom   ? "ON" : "OFF");
   txt += StringFormat("ADX:%s H4TF:%s Grid:%s CapScale:%s\n",
          InpUseADX ? "ON" : "OFF", InpUseMultiTF ? "ON" : "OFF",
          InpGridLots ? "ON" : "OFF", InpCapScaling ? "ON" : "OFF");
   Comment(txt);
}
//+------------------------------------------------------------------+
//  FIN – QUANTUM QUEEN HYBRID PYRAMID v4.0 ENHANCED
//+------------------------------------------------------------------+
