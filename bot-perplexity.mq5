
//+------------------------------------------------------------------+
//|                                           Quantum Grid Lite.mq5  |
//|                               Copyright 2026, AI Trading Assist  |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>

CTrade trade;

//--- INPUTS ---
input group "=== GESTIÓN DE RIESGO (Cuenta Pequeña) ==="
input double BaseLot      = 0.01;
input int    MaxLevels    = 5;      // Máximo de niveles en el grid
input int    GridStep     = 300;    // Distancia en puntos entre niveles
input double TakeProfit$  = 2.00;   // Ganancia total del basket en USD

input group "=== FILTROS DE MERCADO ==="
input int    MaxSpread    = 30;     // Filtro de spread estricto
input int    MagicNumber  = 888777;

//--- GLOBAL ---
double GlobalPeak = 0;

int OnInit() {
   trade.SetExpertMagicNumber(MagicNumber);
   return INIT_SUCCEEDED;
}

void OnTick() {
   // 1. Filtro de Spread
   if((SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / _Point > MaxSpread) return;

   // 2. Gestión de Basket
   ManageBasket();

   // 3. Lógica de entrada (si no hay grid, abrir base)
   if(CountPositions() == 0) {
       // Aquí podrías añadir filtros de indicadores (EMA/RSI)
       trade.Buy(BaseLot, _Symbol, SymbolInfoDouble(_Symbol, SYMBOL_ASK), 0, 0);
       trade.Sell(BaseLot, _Symbol, SymbolInfoDouble(_Symbol, SYMBOL_BID), 0, 0);
   }
}

//--- FUNCIONES DE GESTIÓN ---
void ManageBasket() {
   double currentPnL = 0;
   int count = 0;

   for(int i=PositionsTotal()-1; i>=0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket) && PositionGetInteger(POSITION_MAGIC) == MagicNumber) {
         currentPnL += PositionGetDouble(POSITION_PROFIT);
         count++;
      }
   }

   // Cierre del basket
   if(currentPnL >= TakeProfit$) {
      CloseAll();
   }
}

int CountPositions() {
   int total = 0;
   for(int i=PositionsTotal()-1; i>=0; i--) {
      if(PositionSelectByTicket(PositionGetTicket(i)) && PositionGetInteger(POSITION_MAGIC) == MagicNumber) total++;
   }
   return total;
}

void CloseAll() {
   for(int i=PositionsTotal()-1; i>=0; i--) {
      ulong tk = PositionGetTicket(i);
      if(PositionSelectByTicket(tk) && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         trade.PositionClose(tk);
   }
}
