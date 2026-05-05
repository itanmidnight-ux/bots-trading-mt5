//+------------------------------------------------------------------+
//| EMA PRO TREND BOT (STABLE VERSION)                               |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>
CTrade trade;

//---------------- INPUTS ----------------//
input double Lot = 0.01;

input int FastEMA = 9;
input int SlowEMA = 26;
input int TrendEMA = 50;

input int ConfirmCandles = 3;

input double SL_Points = 120;
input double MoneyTP = 1.40;

input double BE_Points = 60;
input double Trail_Start = 80;
input double Trail_Step = 40;

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

//+------------------------------------------------------------------+
void ManageTrade()
{
   if(!PositionSelect(_Symbol)) return;

   double profit = PositionGetDouble(POSITION_PROFIT);
   double open   = PositionGetDouble(POSITION_PRICE_OPEN);
   double sl     = PositionGetDouble(POSITION_SL);

   bool isBuy = PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY;

   double price = isBuy ? SymbolInfoDouble(_Symbol,SYMBOL_BID)
                        : SymbolInfoDouble(_Symbol,SYMBOL_ASK);

   double pts = MathAbs(price-open)/_Point;

   // TP mínimo
   if(profit >= MoneyTP && pts < Trail_Start)
   {
      trade.PositionClose(_Symbol);
      return;
   }

   // BreakEven
   if(pts > BE_Points)
   {
      if(isBuy && sl < open) trade.PositionModify(_Symbol,open,0);
      if(!isBuy && sl > open) trade.PositionModify(_Symbol,open,0);
   }

   // Trailing
   if(pts > Trail_Start)
   {
      double newSL = isBuy ? price - Trail_Step*_Point
                           : price + Trail_Step*_Point;

      if((isBuy && newSL>sl) || (!isBuy && newSL<sl))
         trade.PositionModify(_Symbol,newSL,0);
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

   if(PositionSelect(_Symbol)) return;

   double f[], s[], t[];

   if(!GetEMA(f,s,t)) return;

   double trend = t[0];

   // FILTRO DE TENDENCIA
   bool trendBuy  = f[0] > trend;
   bool trendSell = f[0] < trend;

   bool buySignal  = ConfirmBuy(f,s)  && trendBuy;
   bool sellSignal = ConfirmSell(f,s) && trendSell;

   if(buySignal)  OpenTrade(true);
   if(sellSignal) OpenTrade(false);
}