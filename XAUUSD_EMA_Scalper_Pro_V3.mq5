//+------------------------------------------------------------------+
//| EMA PRO TREND BOT - ULTRA SAFE EDITION                           |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>

CTrade trade;

//---------------- INPUTS ----------------//
input group "=== CAPITAL PROTECT ==="
input double FixedLot    = 0.01; // Lote FIJO siempre
input int    MaxPyramid  = 6;    // Máximo de trades por entrada

input group "=== INDICADORES ==="
input int FastEMA   = 9;
input int SlowEMA   = 21;
input int TrendEMA  = 50;
input int RSI_Per   = 14;

input group "=== GESTIÓN DE PÉRDIDAS (SISTEMA POSIBLE) ==="
input double EmergencySL = 300;   // SL Hard en puntos para evitar quema total
input double RSI_BuyExit = 40.0;  // RSI bajo esto en BUY = Peligro
input double RSI_SellExit = 60.0; // RSI alto esto en SELL = Peligro

input group "=== GESTIÓN DE GANANCIAS ==="
input double MinProfitLock = 0.50; // Asegurar ganancia a partir de $0.50
input double ProfitRetrace = 0.20; // Cerrar si cae $0.20 desde el pico

input group "=== FILTROS ==="
input double MaxSpread = 50;
input int Magic = 777;

//---------------- GLOBALS ----------------//
int hFast, hSlow, hTrend, hRSI;
datetime lastBar = 0;
double GlobalPeak = 0;

//+------------------------------------------------------------------+
int OnInit() {
   hFast  = iMA(_Symbol, _Period, FastEMA, 0, MODE_EMA, PRICE_CLOSE);
   hSlow  = iMA(_Symbol, _Period, SlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   hTrend = iMA(_Symbol, _Period, TrendEMA, 0, MODE_EMA, PRICE_CLOSE);
   hRSI   = iRSI(_Symbol, _Period, RSI_Per, PRICE_CLOSE);
   trade.SetExpertMagicNumber(Magic);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
// Pirámide según balance para NO quemar la cuenta
int GetSafePyramid() {
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   if(bal < 30) return 1;       // < 30 USD: Solo 1 trade (Seguridad máxima)
   if(bal < 100) return 3;      // 30-100 USD: Máximo 3 trades
   return MaxPyramid;           // > 100 USD: Hasta 6 trades
}

//+------------------------------------------------------------------+
// SISTEMA POSIBLE: Valida si el trade negativo debe cerrarse ya
bool ShouldCloseNegative(bool isBuy) {
   double rsi[]; 
   ArraySetAsSeries(rsi, true);
   if(CopyBuffer(hRSI, 0, 0, 2, rsi) <= 0) return false;

   double f[], s[];
   ArraySetAsSeries(f, true); ArraySetAsSeries(s, true);
   if(CopyBuffer(hFast, 0, 0, 2, f) <= 0 || CopyBuffer(hSlow, 0, 0, 2, s) <= 0) return false;

   // VALIDACIÓN 1: Dirección del Precio vs EMA Trend (Filtro de Tendencia)
   bool trendWrong = isBuy ? (iClose(_Symbol, _Period, 0) < iMA(_Symbol, _Period, TrendEMA, 0, MODE_EMA, PRICE_CLOSE))
                           : (iClose(_Symbol, _Period, 0) > iMA(_Symbol, _Period, TrendEMA, 0, MODE_EMA, PRICE_CLOSE));
   
   // VALIDACIÓN 2: Momentum (RSI y Cruce EMA)
   bool momentumWrong = isBuy ? (rsi[0] < RSI_BuyExit || f[0] < s[0])
                              : (rsi[0] > RSI_SellExit || f[0] > s[0]);

   return (trendWrong && momentumWrong); // Cierre inmediato si AMBOS confirman giro
}

//+------------------------------------------------------------------+
void OpenTrade(bool buy) {
   int n = GetSafePyramid();
   double price = buy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = buy ? price - EmergencySL * _Point : price + EmergencySL * _Point;

   for(int i=0; i<n; i++) {
      if(buy) trade.Buy(FixedLot, _Symbol, price, sl, 0);
      else trade.Sell(FixedLot, _Symbol, price, sl, 0);
   }
   GlobalPeak = 0;
}

//+------------------------------------------------------------------+
void ManageTrade() {
   double currentPnL = 0;
   int count = 0;

   for(int i=PositionsTotal()-1; i>=0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket) && PositionGetInteger(POSITION_MAGIC) == Magic) {
         count++;
         double profit = PositionGetDouble(POSITION_PROFIT);
         bool isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
         currentPnL += profit;

         // 1. GESTIÓN DE PÉRDIDAS (SISTEMA POSIBLE)
         if(profit < 0) {
            if(ShouldCloseNegative(isBuy)) {
               trade.PositionClose(ticket);
               continue;
            }
         }
      }
   }

   if(count == 0) { GlobalPeak = 0; return; }

   // 2. GESTIÓN DE GANANCIAS (Reverse TP / Lock Profit)
   if(currentPnL > GlobalPeak) GlobalPeak = currentPnL;
   if(GlobalPeak >= MinProfitLock && currentPnL < (GlobalPeak - ProfitRetrace)) {
      CloseAll();
   }
}

//+------------------------------------------------------------------+
void CloseAll() {
   for(int i=PositionsTotal()-1; i>=0; i--) {
      ulong tk = PositionGetTicket(i);
      if(PositionSelectByTicket(tk) && PositionGetInteger(POSITION_MAGIC) == Magic)
         trade.PositionClose(tk);
   }
}

//+------------------------------------------------------------------+
void OnTick() {
   if((SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / _Point > MaxSpread) return;

   ManageTrade();

   datetime t = iTime(_Symbol, _Period, 0);
   if(t == lastBar) return;
   lastBar = t;

   // Evitar abrir nuevos trades si hay alguno activo
   int total = 0;
   for(int i=PositionsTotal()-1; i>=0; i--) {
      if(PositionSelectByTicket(PositionGetTicket(i)) && PositionGetInteger(POSITION_MAGIC) == Magic) total++;
   }
   if(total > 0) return;

   double f[], s[], t_ema[];
   ArraySetAsSeries(f, true); ArraySetAsSeries(s, true); ArraySetAsSeries(t_ema, true);
   if(CopyBuffer(hFast, 0, 0, 2, f) <= 0 || CopyBuffer(hSlow, 0, 0, 2, s) <= 0 || CopyBuffer(hTrend, 0, 0, 2, t_ema) <= 0) return;

   if(f[0] > s[0] && f[0] > t_ema[0]) OpenTrade(true);
   else if(f[0] < s[0] && f[0] < t_ema[0]) OpenTrade(false);
}