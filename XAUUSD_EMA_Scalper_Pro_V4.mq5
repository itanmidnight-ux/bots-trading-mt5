//+------------------------------------------------------------------+
//| XAUUSD PRO BOT V2 - PYRAMID + SMART FILTERS                      |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>

CTrade trade;

//---------------- INPUTS ----------------//
input double LotSize = 0.01;
input int Magic = 777;

input int FastEMA = 9;
input int SlowEMA = 21;
input int TrendEMA = 50;
input int RSI_Per = 14;
input int ATR_Per = 14;

input double Risk_ATR_SL = 2.0;
input double RR_Ratio = 2.0;
input double Trail_ATR = 1.2;

input double MinATR = 50;
input double MaxSpread = 30;

// Piramidación
input int MaxPositions = 3;
input double PyramidStepATR = 1.0;

// Horario
input int LondonStart = 7;
input int NewYorkEnd  = 20;

//---------------- GLOBALS ----------------//
int hFast, hSlow, hTrend, hRSI, hATR;
datetime lastBar = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   hFast  = iMA(_Symbol,_Period,FastEMA,0,MODE_EMA,PRICE_CLOSE);
   hSlow  = iMA(_Symbol,_Period,SlowEMA,0,MODE_EMA,PRICE_CLOSE);
   hTrend = iMA(_Symbol,_Period,TrendEMA,0,MODE_EMA,PRICE_CLOSE);
   hRSI   = iRSI(_Symbol,_Period,RSI_Per,PRICE_CLOSE);
   hATR   = iATR(_Symbol,_Period,ATR_Per);

   if(hFast==INVALID_HANDLE || hSlow==INVALID_HANDLE || hTrend==INVALID_HANDLE || hRSI==INVALID_HANDLE || hATR==INVALID_HANDLE)
      return INIT_FAILED;

   trade.SetExpertMagicNumber(Magic);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
bool IsTradingTime()
{
   MqlDateTime t;
   TimeToStruct(TimeCurrent(), t);
   if(t.hour < 1) return false;
   return (t.hour >= LondonStart && t.hour <= NewYorkEnd);
}

//+------------------------------------------------------------------+
int CountPositions()
{
   int count=0;
   for(int i=0;i<PositionsTotal();i++)
   {
      ulong tk = PositionGetTicket(i);
      if(PositionSelectByTicket(tk))
         if(PositionGetInteger(POSITION_MAGIC)==Magic)
            count++;
   }
   return count;
}

//+------------------------------------------------------------------+
double GetLastEntryPrice(bool &isBuy)
{
   double price=0;
   datetime last=0;

   for(int i=0;i<PositionsTotal();i++)
   {
      ulong tk = PositionGetTicket(i);
      if(PositionSelectByTicket(tk))
      {
         if(PositionGetInteger(POSITION_MAGIC)!=Magic) continue;

         datetime t = (datetime)PositionGetInteger(POSITION_TIME);
         if(t > last)
         {
            last = t;
            price = PositionGetDouble(POSITION_PRICE_OPEN);
            isBuy = PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY;
         }
      }
   }
   return price;
}

//+------------------------------------------------------------------+
bool GetIndicators(double &fast,double &slow,double &trend,double &rsi,double &atr)
{
   double f[],s[],t[],r[],a[];
   ArraySetAsSeries(f,true); ArraySetAsSeries(s,true);
   ArraySetAsSeries(t,true); ArraySetAsSeries(r,true);
   ArraySetAsSeries(a,true);

   if(CopyBuffer(hFast,0,0,2,f)<=0) return false;
   if(CopyBuffer(hSlow,0,0,2,s)<=0) return false;
   if(CopyBuffer(hTrend,0,0,2,t)<=0) return false;
   if(CopyBuffer(hRSI,0,0,2,r)<=0) return false;
   if(CopyBuffer(hATR,0,0,2,a)<=0) return false;

   fast=f[0]; slow=s[0]; trend=t[0]; rsi=r[0]; atr=a[0];
   return true;
}

//+------------------------------------------------------------------+
void OpenTrade(bool buy,double atr)
{
   double price = buy ? SymbolInfoDouble(_Symbol,SYMBOL_ASK)
                      : SymbolInfoDouble(_Symbol,SYMBOL_BID);

   double sl = buy ? price - atr*Risk_ATR_SL
                   : price + atr*Risk_ATR_SL;

   double tp = buy ? price + atr*Risk_ATR_SL*RR_Ratio
                   : price - atr*Risk_ATR_SL*RR_Ratio;

   trade.Buy(LotSize,_Symbol,price,sl,tp);
   if(!buy)
      trade.Sell(LotSize,_Symbol,price,sl,tp);
}

//+------------------------------------------------------------------+
void ManageTrailing()
{
   for(int i=0;i<PositionsTotal();i++)
   {
      ulong tk = PositionGetTicket(i);
      if(!PositionSelectByTicket(tk)) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=Magic) continue;

      double atr[];
      ArraySetAsSeries(atr,true);
      if(CopyBuffer(hATR,0,0,1,atr)<=0) continue;

      double trail = atr[0]*Trail_ATR;
      double current = PositionGetDouble(POSITION_PRICE_CURRENT);
      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);

      bool buy = PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY;

      if(buy && current > open + atr[0])
      {
         double newSL = current - trail;
         if(newSL > sl) trade.PositionModify(tk,newSL,tp);
      }
      else if(!buy && current < open - atr[0])
      {
         double newSL = current + trail;
         if(newSL < sl) trade.PositionModify(tk,newSL,tp);
      }
   }
}

//+------------------------------------------------------------------+
void OnTick()
{
   double spread = (SymbolInfoDouble(_Symbol,SYMBOL_ASK)-SymbolInfoDouble(_Symbol,SYMBOL_BID))/_Point;
   if(spread > MaxSpread) return;
   if(!IsTradingTime()) return;

   ManageTrailing();

   datetime t = iTime(_Symbol,_Period,0);
   if(t == lastBar) return;
   lastBar = t;

   double fast,slow,trend,rsi,atr;
   if(!GetIndicators(fast,slow,trend,rsi,atr)) return;
   if(atr/_Point < MinATR) return;

   double price = iClose(_Symbol,_Period,0);
   double prevClose = iClose(_Symbol,_Period,1);

   double body = MathAbs(iClose(_Symbol,_Period,0)-iOpen(_Symbol,_Period,0));
   double range = iHigh(_Symbol,_Period,0)-iLow(_Symbol,_Period,0);
   if(body < range*0.4) return;

   double strength = MathAbs(fast - slow)/_Point;
   if(strength < 20) return;

   int total = CountPositions();

   // ENTRADA INICIAL
   if(total == 0)
   {
      if(fast > slow && price > trend && rsi > 55 && price > prevClose)
         OpenTrade(true,atr);

      else if(fast < slow && price < trend && rsi < 45 && price < prevClose)
         OpenTrade(false,atr);
   }
   // PIRAMIDACIÓN INTELIGENTE
   else if(total < MaxPositions)
   {
      bool isBuy;
      double lastPrice = GetLastEntryPrice(isBuy);

      if(isBuy && price > lastPrice + atr*PyramidStepATR)
         OpenTrade(true,atr);

      else if(!isBuy && price < lastPrice - atr*PyramidStepATR)
         OpenTrade(false,atr);
   }
}