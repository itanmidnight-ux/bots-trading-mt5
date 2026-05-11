//+------------------------------------------------------------------+
//|  XAUUSD QUANTUM QUEEN HYBRID v2.0                                 |
//|  Range Breakout 59% WR + Filtros QQ + Gestión Avanzada            |
//+------------------------------------------------------------------+
#property copyright "QQ Hybrid v2.0"
#property version   "2.00"
#property strict

#include <Trade/Trade.mqh>

CTrade trade;

//====================================================================
//  INPUTS
//====================================================================
input group "=== RANGO BREAKOUT (ESTRATEGIA PRINCIPAL) ==="
input int    InpRangeHourStart  = 7;     // Hora inicio rango
input int    InpRangeHourEnd    = 8;     // Hora fin rango / trigger
input int    InpBreakoutHourEnd = 10;    // Hora cierre ventana
input double InpRangeMinPts     = 1.5;  // Tamaño mínimo rango
input double InpRangeMaxPts     = 12.0; // Tamaño máximo rango
input int    InpMinBars         = 25;   // Barras mínimas en rango
input double InpBreakoutOffset  = 0.30; // Offset ruptura (puntos)
input double InpSLOffset        = 0.50; // Offset SL (puntos)
input double InpRR              = 2.0;  // Risk/Reward ratio

input group "=== GESTIÓN DE CAPITAL ==="
input double InpLot             = 0.01; // Lote fijo
input int    InpMagic           = 5900; // Magic number
input int    InpMaxBarsOpen     = 120;  // Máx barras con trade abierto
input int    InpMaxTradesDay    = 3;    // Máx trades por día

input group "=== PROTECCIONES ==="
input double InpMaxSpread       = 50.0; // Spread máximo (puntos)
input double InpDailyLossUSD    = 50.0; // Límite pérdida diaria USD
input bool   InpTrailingOn      = true; // Usar trailing stop
input double InpTrailingPts     = 10.0; // Trailing stop (puntos)
input double InpMinProfitLock   = 0.50; // Ganancia para activar lock
input double InpProfitRetrace   = 0.20; // Retroceso para cerrar

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
input bool   InpShowPanel       = true; // Mostrar panel de info

//====================================================================
//  VARIABLES GLOBALES
//====================================================================

// Handles indicadores
int hEMA50, hEMA200, hBB, hRSI, hMFI, hATR;

// Estado del rango
double   g_rangeHigh    = 0;
double   g_rangeLow     = 0;
int      g_rangeBars    = 0;
bool     g_dayInvalid   = false;
bool     g_initialized  = false;
bool     g_triggered    = false;

// Sesgo tendencia
bool     g_sesgoUp      = false;
bool     g_sesgoDn      = false;

// Gestión diaria
int      g_tradesToday  = 0;
double   g_dayStartBal  = 0;
datetime g_lastDay      = 0;

// Tracking ganancia
double   g_peakProfit   = 0;

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
      Alert("Error creando handles de indicadores");
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(10);

   g_dayStartBal = AccountInfoDouble(ACCOUNT_BALANCE);
   DailyReset();

   Print("✅ QQ Hybrid v2.0 iniciado en ", _Symbol);
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
   }

   ManageOpenTrades();
   DrawPanel();
}

//====================================================================
//  RESET DIARIO
//====================================================================
void DailyReset()
{
   g_rangeHigh   = 0;
   g_rangeLow    = 0;
   g_rangeBars   = 0;
   g_dayInvalid  = false;
   g_initialized = false;
   g_triggered   = false;
   g_sesgoUp     = false;
   g_sesgoDn     = false;
   g_tradesToday = 0;
   g_peakProfit  = 0;
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

   // Sesgo por EMA D1
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

// QQ1 – Bollinger Squeeze
bool FilterQQ1(double close, double bbUpper, double bbLower, double bbMid,
               double bbWidth, double rsi)
{
   if(!InpQQ1_Squeeze) return true;

   double bbWidthBuf[20];
   // Usamos bb_width actual como referencia vs media implícita
   bool squeeze = (bbWidth < (bbUpper - bbLower) * 0.45);
   bool stochEx  = (rsi < 25.0 || rsi > 75.0);
   return (squeeze || stochEx);
}

// QQ2 – Directional Breakout
bool FilterQQ2(double close, double bbUpper, double bbLower, double rsi, bool isBuy)
{
   if(!InpQQ2_DirBreak) return true;
   if(isBuy)  return (close > bbMid_cached) && (rsi > 55.0);
   else        return (close < bbMid_cached) && (rsi < 45.0);
}

// QQ4 – Trend EMA Confirmation
bool FilterQQ4(double close, double bbMid, bool isBuy)
{
   if(!InpQQ4_Trend) return true;
   if(isBuy)  return (close > bbMid);
   else        return (close < bbMid);
}

// QQ6 – Volume Momentum
bool FilterQQ6(double rsi, double mfi, bool isBuy)
{
   if(!InpQQ6_VolMom) return true;
   if(isBuy)  return (rsi > 55.0 && mfi > 52.0);
   else        return (rsi < 45.0 && mfi < 48.0);
}

// Cache de bbMid para QQ2
double bbMid_cached = 0;

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
   return true;
}

//====================================================================
//  FASE 3 – BUSCAR BREAKOUT 08:00-09:59
//====================================================================
void SearchBreakout()
{
   if(g_triggered || !g_initialized || g_dayInvalid) return;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(dt.hour < InpRangeHourEnd || dt.hour >= InpBreakoutHourEnd) return;
   if(g_tradesToday >= InpMaxTradesDay) return;

   // Validar spread
   double spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > InpMaxSpread) return;

   // Límite pérdida diaria
   double dayPnL = AccountInfoDouble(ACCOUNT_BALANCE) - g_dayStartBal;
   if(dayPnL < -InpDailyLossUSD) return;

   double close = iClose(_Symbol, PERIOD_CURRENT, 0);

   // Obtener indicadores
   double bbU, bbD, bbM, rsi, mfi, atr;
   if(!GetIndicators(bbU, bbD, bbM, rsi, mfi, atr)) return;

   double bbW = bbU - bbD;

   // ──── ENTRADA LONG ────
   if(close > (g_rangeHigh + InpBreakoutOffset) && g_sesgoUp)
   {
      if(!FilterQQ1(close, bbU, bbD, bbM, bbW, rsi)) return;
      if(!FilterQQ2(close, bbU, bbD, rsi, true))     return;
      if(!FilterQQ4(close, bbM, true))                return;
      if(!FilterQQ6(rsi, mfi, true))                  return;

      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl  = g_rangeLow - InpSLOffset;
      double tp  = ask + ((ask - sl) * InpRR);

      if(trade.Buy(NormLot(InpLot), _Symbol, ask, sl, tp))
      {
         g_triggered   = true;
         g_tradesToday++;
         Print("🟢 LONG @ ", ask, " SL:", sl, " TP:", tp);
      }
   }

   // ──── ENTRADA SHORT ────
   else if(close < (g_rangeLow - InpBreakoutOffset) && g_sesgoDn)
   {
      if(!FilterQQ1(close, bbU, bbD, bbM, bbW, rsi)) return;
      if(!FilterQQ2(close, bbU, bbD, rsi, false))    return;
      if(!FilterQQ4(close, bbM, false))               return;
      if(!FilterQQ6(rsi, mfi, false))                 return;

      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl  = g_rangeHigh + InpSLOffset;
      double tp  = bid - ((sl - bid) * InpRR);

      if(trade.Sell(NormLot(InpLot), _Symbol, bid, sl, tp))
      {
         g_triggered   = true;
         g_tradesToday++;
         Print("🔴 SHORT @ ", bid, " SL:", sl, " TP:", tp);
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

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))           continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      double profit  = PositionGetDouble(POSITION_PROFIT);
      bool   isBuy   = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      datetime tOpen = (datetime)PositionGetInteger(POSITION_TIME);

      totalPnL += profit;
      count++;

      // 1. Cierre por tiempo (120 barras)
      int barsOpen = (int)((TimeCurrent() - tOpen) / PeriodSeconds(PERIOD_CURRENT));
      if(barsOpen >= InpMaxBarsOpen)
      {
         trade.PositionClose(ticket);
         Print("⏱️ Cierre tiempo: ", barsOpen, " barras");
         continue;
      }

      // 2. Trailing Stop
      if(InpTrailingOn) ApplyTrailing(ticket, isBuy);
   }

   // 3. Lock Profit (Peak retrace)
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
//  TRAILING STOP
//====================================================================
void ApplyTrailing(ulong ticket, bool isBuy)
{
   if(!PositionSelectByTicket(ticket)) return;

   double curSL    = PositionGetDouble(POSITION_SL);
   double curTP    = PositionGetDouble(POSITION_TP);
   double curPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
   double trailPts = InpTrailingPts * _Point;

   if(isBuy)
   {
      double newSL = curPrice - trailPts;
      if(newSL > curSL + _Point)
         trade.PositionModify(ticket, newSL, curTP);
   }
   else
   {
      double newSL = curPrice + trailPts;
      if(newSL < curSL - _Point || curSL == 0)
         trade.PositionModify(ticket, newSL, curTP);
   }
}

//====================================================================
//  CERRAR TODOS LOS TRADES DEL MAGIC
//====================================================================
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

//====================================================================
//  NORMALIZAR LOTE
//====================================================================
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

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);

   // Contar trades activos
   int    activePos  = 0;
   double activePnL  = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      activePos++;
      activePnL += PositionGetDouble(POSITION_PROFIT);
   }

   string estado = g_dayInvalid   ? "❌ DÍA INVÁLIDO"  :
                   !g_initialized ? "⏳ CONSTRUYENDO"   :
                   g_triggered    ? "✅ OPERANDO"       : "🎯 ESPERANDO";

   string sesgoStr = g_sesgoUp ? "📈 ALCISTA" : (g_sesgoDn ? "📉 BAJISTA" : "---");

   string txt = "";
   txt += "═══════ QUANTUM QUEEN HYBRID v2.0 ═══════\n";
   txt += StringFormat("Hora actual   : %02d:%02d\n", dt.hour, dt.min);
   txt += StringFormat("Estado        : %s\n", estado);
   txt += StringFormat("Rango High    : %.2f\n", g_rangeHigh);
   txt += StringFormat("Rango Low     : %.2f\n", g_rangeLow);
   txt += StringFormat("Rango Size    : %.2f pts\n", g_rangeHigh - g_rangeLow);
   txt += StringFormat("Sesgo D1      : %s\n", sesgoStr);
   txt += StringFormat("Trades Hoy    : %d / %d\n", g_tradesToday, InpMaxTradesDay);
   txt += StringFormat("Posiciones    : %d\n", activePos);
   txt += StringFormat("PnL Abierto   : $%.2f\n", activePnL);
   txt += StringFormat("PnL Día       : $%.2f\n",
                        AccountInfoDouble(ACCOUNT_BALANCE) - g_dayStartBal);
   txt += StringFormat("Balance       : $%.2f\n", AccountInfoDouble(ACCOUNT_BALANCE));
   txt += "══════════════════════════════════════════\n";
   txt += StringFormat("QQ1 Squeeze   : %s\n", InpQQ1_Squeeze   ? "ON" : "OFF");
   txt += StringFormat("QQ2 DirBreak  : %s\n", InpQQ2_DirBreak  ? "ON" : "OFF");
   txt += StringFormat("QQ4 Trend     : %s\n", InpQQ4_Trend     ? "ON" : "OFF");
   txt += StringFormat("QQ6 VolMom    : %s\n", InpQQ6_VolMom    ? "ON" : "OFF");

   Comment(txt);
}

//====================================================================
//  FIN DEL CÓDIGO
//====================================================================