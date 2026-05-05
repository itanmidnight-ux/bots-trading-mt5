//+------------------------------------------------------------------+
//| EMA PRO TREND BOT (PYRAMIDAL VERSION)                            |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>
CTrade trade;

//---------------- INPUTS ----------------//
input group "--- Configuración de Lotes ---"
input double Lot = 0.01;
input bool   UsePyramiding = true; // Activar sistema piramidal

input group "--- Indicadores EMA ---"
input int FastEMA = 9;
input int SlowEMA = 26;
input int TrendEMA = 50;
input int ConfirmCandles = 3;

input group "--- Gestión de Riesgo ---"
input double SL_Points = 120;
input double MoneyTP = 1.40;
input double BE_Points = 60;
input double Trail_Start = 80;
input double Trail_Step = 40;

input group "--- Filtros y Sistema ---"
input double MaxSpread = 50;
input int Magic = 777;

//---------------- HANDLES ----------------//
int hFast, hSlow, hTrend;

//---------------- CONTROL ----------------//
datetime lastBar = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   hFast  = iMA(_Symbol, _Period, FastEMA, 0, MODE_EMA, PRICE_CLOSE);
   hSlow  = iMA(_Symbol, _Period, SlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   hTrend = iMA(_Symbol, _Period, TrendEMA, 0, MODE_EMA, PRICE_CLOSE);

   if(hFast==INVALID_HANDLE || hSlow==INVALID_HANDLE || hTrend==INVALID_HANDLE)
      return INIT_FAILED;

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
bool NewBar()
{
   datetime t = iTime(_Symbol,_Period,0);
   if(t!=lastBar)
   {
      lastBar=t;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
// Función para determinar cuántos trades abrir según el capital
int GetPyramidTrades()
{
   if(!UsePyramiding) return 1;

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   
   if(balance >= 200) return 6;
   if(balance >= 130) return 5;
   if(balance >= 90)  return 4;
   if(balance >= 60)  return 3;
   if(balance >= 30)  return 2;
   
   return 1; // Menos de 30 USD
}

//+------------------------------------------------------------------+
bool GetEMA(double &f[], double &s[], double &t[])
{
   int size = ConfirmCandles + 2;
   ArrayResize(f,size);
   ArrayResize(s,size);
   ArrayResize(t,1);

   if(CopyBuffer(hFast,0,0,size,f)<=0) return false;
   if(CopyBuffer(hSlow,0,0,size,s)<=0) return false;
   if(CopyBuffer(hTrend,0,0,1,t)<=0) return false;

   return true;
}

//+------------------------------------------------------------------+
bool ConfirmBuy(double &f[], double &s[])
{
   for(int i=1;i<=ConfirmCandles;i++)
      if(f[i]<=s[i]) return false;
   return true;
}

//+------------------------------------------------------------------+
bool ConfirmSell(double &f[], double &s[])
{
   for(int i=1;i<=ConfirmCandles;i++)
      if(f[i]>=s[i]) return false;
   return true;
}

//+------------------------------------------------------------------+
void OpenTrade(bool buy)
{
   int tradesToOpen = GetPyramidTrades();
   
   for(int i=0; i<tradesToOpen; i++)
   {
      double price = buy ? SymbolInfoDouble(_Symbol,SYMBOL_ASK)
                          : SymbolInfoDouble(_Symbol,SYMBOL_BID);

      double sl = buy ? price - SL_Points*_Point
                      : price + SL_Points*_Point;

      trade.SetExpertMagicNumber(Magic);

      if(buy)
         trade.Buy(Lot,_Symbol,price,sl,0);
      else
         trade.Sell(Lot,_Symbol,price,sl,0);
   }
}

//+------------------------------------------------------------------+
// Gestión Profesional: Recorre todas las posiciones abiertas por el bot
void ManageTrade()
{
   // Recorremos todas las posiciones abiertas en la cuenta
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         // Filtramos por símbolo y Magic Number para no cerrar trades manuales u otros bots
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == Magic)
         {
            double profit = PositionGetDouble(POSITION_PROFIT);
            double open   = PositionGetDouble(POSITION_PRICE_OPEN);
            double sl     = PositionGetDouble(POSITION_SL);
            bool isBuy    = PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY;

            double price = isBuy ? SymbolInfoDouble(_Symbol,SYMBOL_BID)
                                  : SymbolInfoDouble(_Symbol,SYMBOL_ASK);

            double pts = MathAbs(price-open)/_Point;

            // 1. TP mínimo por dinero
            if(profit >= MoneyTP && pts < Trail_Start)
            {
               trade.PositionClose(ticket);
               continue; // Pasar a la siguiente posición
            }

            // 2. BreakEven
            if(pts > BE_Points)
            {
               if(isBuy && sl < open) trade.PositionModify(ticket,open,0);
               if(!isBuy && sl > open) trade.PositionModify(ticket,open,0);
            }

            // 3. Trailing Stop
            if(pts > Trail_Start)
            {
               double newSL = isBuy ? price - Trail_Step*_Point
                                    : price + Trail_Step*_Point;

               if((isBuy && newSL>sl) || (!isBuy && newSL<sl))
                  trade.PositionModify(ticket,newSL,0);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
void OnTick()
{
   double spread = (SymbolInfoDouble(_Symbol,SYMBOL_ASK) -
                    SymbolInfoDouble(_Symbol,SYMBOL_BID))/_Point;

   if(spread > MaxSpread) return;

   ManageTrade();

   if(!NewBar()) return;

   // IMPORTANTE: Cambiamos PositionSelect por un contador para permitir 
   // que el sistema piramidal abra el set de trades solo cuando no haya ninguno activo.
   if(CountOpenPositions() > 0) return;

   double f[], s[], t[];
   if(!GetEMA(f,s,t)) return;

   double trend = t[0];

   bool trendBuy  = f[0] > trend;
   bool trendSell = f[0] < trend;

   bool buySignal  = ConfirmBuy(f,s)  && trendBuy;
   bool sellSignal = ConfirmSell(f,s) && trendSell;

   if(buySignal)  OpenTrade(true);
   if(sellSignal) OpenTrade(false);
}

//+------------------------------------------------------------------+
// Función auxiliar para contar posiciones abiertas por este bot
int CountOpenPositions()
{
   int count = 0;
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == Magic)
            count++;
      }
   }
   return count;
}