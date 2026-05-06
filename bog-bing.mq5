//+------------------------------------------------------------------+
//| XAUUSD_EMA_QuantumLike.mq5                                       |
//| EMA + Grid Adaptive + SmartLotScaling + MultiTF + Basket Manager |
//+------------------------------------------------------------------+
#property copyright "Adapted"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>

CTrade trade;

//---------------- INPUTS ----------------//
input string  EA_Comment = "XAUUSD_EMA_QuantumLike";
enum RiskProfileEnum {Conservative=0, Balanced=1, Aggressive=2, Extreme=3};
input RiskProfileEnum RiskProfile = Conservative;

input double  LeverageLowBalance  = 3000.0; // informative
input double  LeverageHighBalance = 500.0;  // informative
input double  LeverageSwitchBalance = 250.0; // threshold

input double  baseLot = 0.01;           // lote base mínimo
input bool    autoLot = true;           // calcular lotes automáticamente
input double  riskPercentPerGrid = 0.25; // % del balance por nivel (Conservative default)
input int     maxLevels = 6;            // niveles máximos del grid
input double  gridDistancePoints = 400; // distancia entre niveles en puntos (XAUUSD ~ 400 points = 40 pips)
input double  levelFactor = 0.18;       // factor de escalado por nivel (smart scaling)

input int     FastEMA   = 9;
input int     SlowEMA   = 21;
input int     TrendEMA  = 50;
input int     RSI_Per   = 14;
input int     ATR_Per   = 14;

input double  MaxSpreadPoints = 50;     // en puntos
input double  MaxATRMultiplier = 2.5;   // bloquear apertura si ATR > ATR_MA * multiplier
input double  MaxDrawdownPercent = 40.0; // stop trading if drawdown > X% from equity peak
input double  MinBalanceForScaling = 14.0; // mínimo balance target
input int     SessionStartHour = 0;     // sesión permitida (0-23)
input int     SessionEndHour = 23;

input double  BasketTakeProfitUSD = 5.0; // objetivo por basket en USD (conservador)
input double  BasketPartialClosePercent = 50.0; // % a cerrar cuando se alcanza objetivo
input double  MinProfitLock = 0.50;      // conservar ganancia
input double  ProfitRetrace = 0.20;      // retrace para cerrar basket

input int     Magic = 777;
input bool    EnableMultiTF = true;
input bool    EnableVolatilityFilter = true;
input bool    EnableDrawdownKillSwitch = true;
input bool    EnableNewsFilter = false; // placeholder

//---------------- GLOBALS ----------------//
int hFast = INVALID_HANDLE, hSlow = INVALID_HANDLE, hTrend = INVALID_HANDLE, hRSI = INVALID_HANDLE, hATR = INVALID_HANDLE;
datetime lastBar = 0;
double GlobalPeakProfit = 0.0;
double EquityPeak = 0.0;

// Grid state (simple)
double gridBasePrice = 0.0;
bool   gridBaseIsBuy = false;
int    gridLevelsOpened = 0; // includes base level as 1 when opened

//+------------------------------------------------------------------+
// Apply profile defaults
void ApplyProfileSettings()
{
   switch(RiskProfile)
   {
      case Conservative:
         riskPercentPerGrid = 0.25;
         maxLevels = MathMax(1, maxLevels);
         gridDistancePoints = MathMax(100.0, gridDistancePoints);
         levelFactor = 0.18;
         BasketTakeProfitUSD = MathMax(1.0, BasketTakeProfitUSD);
         MaxDrawdownPercent = 40.0;
         break;
      case Balanced:
         riskPercentPerGrid = 0.5;
         maxLevels = MathMax(2, maxLevels);
         gridDistancePoints = MathMax(100.0, gridDistancePoints);
         levelFactor = 0.25;
         BasketTakeProfitUSD = MathMax(5.0, BasketTakeProfitUSD);
         MaxDrawdownPercent = 45.0;
         break;
      case Aggressive:
         riskPercentPerGrid = 1.0;
         maxLevels = MathMax(2, maxLevels);
         gridDistancePoints = MathMax(80.0, gridDistancePoints);
         levelFactor = 0.35;
         BasketTakeProfitUSD = MathMax(10.0, BasketTakeProfitUSD);
         MaxDrawdownPercent = 55.0;
         break;
      case Extreme:
         riskPercentPerGrid = 2.0;
         maxLevels = MathMax(2, maxLevels);
         gridDistancePoints = MathMax(50.0, gridDistancePoints);
         levelFactor = 0.5;
         BasketTakeProfitUSD = MathMax(20.0, BasketTakeProfitUSD);
         MaxDrawdownPercent = 70.0;
         break;
   }
}

//+------------------------------------------------------------------+
// OnInit
int OnInit()
{
   ApplyProfileSettings();

   // create indicator handles on current timeframe
   hFast  = iMA(_Symbol, _Period, FastEMA, 0, MODE_EMA, PRICE_CLOSE);
   hSlow  = iMA(_Symbol, _Period, SlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   hTrend = iMA(_Symbol, _Period, TrendEMA, 0, MODE_EMA, PRICE_CLOSE);
   hRSI   = iRSI(_Symbol, _Period, RSI_Per, PRICE_CLOSE);
   hATR   = iATR(_Symbol, _Period, ATR_Per);

   trade.SetExpertMagicNumber(Magic);
   trade.SetComment(EA_Comment);

   EquityPeak = AccountInfoDouble(ACCOUNT_EQUITY);
   GlobalPeakProfit = 0.0;

   gridBasePrice = 0.0;
   gridBaseIsBuy = false;
   gridLevelsOpened = 0;

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
// OnDeinit
void OnDeinit(const int reason)
{
   if(hFast != INVALID_HANDLE) IndicatorRelease(hFast);
   if(hSlow != INVALID_HANDLE) IndicatorRelease(hSlow);
   if(hTrend != INVALID_HANDLE) IndicatorRelease(hTrend);
   if(hRSI != INVALID_HANDLE) IndicatorRelease(hRSI);
   if(hATR != INVALID_HANDLE) IndicatorRelease(hATR);
}

//+------------------------------------------------------------------+
// Helpers
double SpreadPoints()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask==0 || bid==0) return 999999;
   return (ask - bid) / _Point;
}

double CurrentATR()
{
   if(hATR==INVALID_HANDLE) return 0.0;
   double arr[];
   ArraySetAsSeries(arr,true);
   if(CopyBuffer(hATR,0,0,3,arr) <= 0) return 0.0;
   return arr[0];
}

// Multi timeframe bias: check EMA cross on M5, M15, H1
int MultiTFBias()
{
   if(!EnableMultiTF) return 0;
   int votes = 0;
   int checks = 0;
   ENUM_TIMEFRAMES tfs[3] = {PERIOD_M5, PERIOD_M15, PERIOD_H1};
   for(int i=0;i<3;i++)
   {
      int tf = tfs[i];
      double fast = iMA(_Symbol, tf, FastEMA, 0, MODE_EMA, PRICE_CLOSE, 0);
      double slow = iMA(_Symbol, tf, SlowEMA, 0, MODE_EMA, PRICE_CLOSE, 0);
      if(fast==0 || slow==0) continue;
      checks++;
      if(fast > slow) votes++;
      else votes--;
   }
   if(checks==0) return 0;
   if(votes>0) return 1;
   if(votes<0) return -1;
   return 0;
}

// Smart lot calculation
double SmartLot(int level)
{
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(minLot <= 0) minLot = 0.01;
   if(step <= 0) step = 0.01;
   if(maxLot <= 0) maxLot = 100.0;

   double lot = baseLot;
   if(autoLot)
   {
      // compute a conservative lot from riskPercentPerGrid
      // riskPercentPerGrid is percent (e.g., 0.25 means 0.25%)
      double riskFraction = riskPercentPerGrid / 100.0;
      // heuristic: lot proportional to balance and risk fraction
      double heuristic = (bal * riskFraction) / 1000.0; // divisor chosen to keep lot small for XAUUSD
      if(heuristic > lot) lot = heuristic;
   }

   // scale by level
   lot = lot * (1.0 + levelFactor * level);

   // clamp and round to step
   lot = MathMax(minLot, MathMin(maxLot, lot));
   double steps = MathFloor(lot / step + 0.0000001);
   lot = steps * step;
   if(lot < minLot) lot = minLot;
   return NormalizeDouble(lot,2);
}

// Count our positions
int CountOurPositions()
{
   int cnt = 0;
   for(int i=0;i<PositionsTotal();i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if((int)PositionGetInteger(POSITION_MAGIC) == Magic && StringCompare(PositionGetString(POSITION_SYMBOL), _Symbol)==0) cnt++;
      }
   }
   return cnt;
}

// Basket profit USD
double BasketProfitUSD()
{
   double total = 0.0;
   for(int i=0;i<PositionsTotal();i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if((int)PositionGetInteger(POSITION_MAGIC) == Magic && StringCompare(PositionGetString(POSITION_SYMBOL), _Symbol)==0)
            total += PositionGetDouble(POSITION_PROFIT);
      }
   }
   return total;
}

// Close all our positions
void CloseAllPositions()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if((int)PositionGetInteger(POSITION_MAGIC) == Magic && StringCompare(PositionGetString(POSITION_SYMBOL), _Symbol)==0)
         {
            trade.PositionClose(ticket);
         }
      }
   }
   // reset grid state
   gridBasePrice = 0.0;
   gridLevelsOpened = 0;
}

// Partial close by percent of volume
void PartialCloseByPercent(double percent)
{
   if(percent <= 0 || percent > 100) return;
   double p = percent / 100.0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if((int)PositionGetInteger(POSITION_MAGIC) == Magic && StringCompare(PositionGetString(POSITION_SYMBOL), _Symbol)==0)
         {
            double vol = PositionGetDouble(POSITION_VOLUME);
            double closeVol = vol * p;
            double minVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
            double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
            if(step <= 0) step = 0.01;
            // round closeVol to step
            double steps = MathFloor(closeVol / step + 0.0000001);
            closeVol = steps * step;
            if(closeVol < minVol) closeVol = vol; // if too small, close full
            if(closeVol > 0 && closeVol <= vol) trade.PositionClosePartial(ticket, closeVol);
         }
      }
   }
}

// Should close negative position (trend + momentum)
bool ShouldCloseNegative(bool isBuy)
{
   double rsiArr[1];
   ArraySetAsSeries(rsiArr,true);
   if(CopyBuffer(hRSI,0,0,1,rsiArr) <= 0) return false;

   double fastArr[1], slowArr[1];
   ArraySetAsSeries(fastArr,true); ArraySetAsSeries(slowArr,true);
   if(CopyBuffer(hFast,0,0,1,fastArr) <= 0 || CopyBuffer(hSlow,0,0,1,slowArr) <= 0) return false;

   double closePrice = iClose(_Symbol, _Period, 0);
   double trendEMA = iMA(_Symbol, _Period, TrendEMA, 0, MODE_EMA, PRICE_CLOSE, 0);

   bool trendWrong = isBuy ? (closePrice < trendEMA) : (closePrice > trendEMA);
   bool momentumWrong = isBuy ? (rsiArr[0] < 40.0 || fastArr[0] < slowArr[0]) : (rsiArr[0] > 60.0 || fastArr[0] > slowArr[0]);

   return (trendWrong && momentumWrong);
}

// Manage existing positions: close negative ones if conditions met
void ManagePositions()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if((int)PositionGetInteger(POSITION_MAGIC) == Magic && StringCompare(PositionGetString(POSITION_SYMBOL), _Symbol)==0)
         {
            double profit = PositionGetDouble(POSITION_PROFIT);
            bool isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
            if(profit < 0)
            {
               if(ShouldCloseNegative(isBuy))
               {
                  trade.PositionClose(ticket);
               }
            }
         }
      }
   }
}

// Try to add next grid level based on base price and current price
void TryAddGridLevel()
{
   if(gridLevelsOpened == 0) return;
   if(gridLevelsOpened >= maxLevels) return;

   double currentPrice = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) + SymbolInfoDouble(_Symbol, SYMBOL_BID)) / 2.0;
   int nextLevel = gridLevelsOpened; // base is level 0 counted as 1 opened
   double distance = gridDistancePoints * _Point * (nextLevel); // distance from base
   double targetPrice = gridBaseIsBuy ? gridBasePrice - distance : gridBasePrice + distance;

   // check if price reached or passed target
   if(gridBaseIsBuy)
   {
      if(currentPrice <= targetPrice)
      {
         double lot = SmartLot(nextLevel);
         double sl = currentPrice - 2000*_Point;
         bool ok = trade.Buy(lot, _Symbol, 0, sl, 0);
         if(ok)
         {
            gridLevelsOpened++;
         }
      }
   }
   else
   {
      if(currentPrice >= targetPrice)
      {
         double lot = SmartLot(nextLevel);
         double sl = currentPrice + 2000*_Point;
         bool ok = trade.Sell(lot, _Symbol, 0, sl, 0);
         if(ok)
         {
            gridLevelsOpened++;
         }
      }
   }
}

// Open initial grid base position
void OpenInitialGrid(bool buy)
{
   // MultiTF bias
   int bias = MultiTFBias();
   if(bias != 0)
   {
      if(buy && bias < 0) return;
      if(!buy && bias > 0) return;
   }

   // Volatility filter
   if(EnableVolatilityFilter)
   {
      double atr = CurrentATR();
      if(atr <= 0) return;
      // compute simple ATR MA of last 5 values
      double arr[5];
      ArraySetAsSeries(arr,true);
      int copied = CopyBuffer(hATR,0,0,5,arr);
      if(copied > 0)
      {
         double sum = 0;
         for(int i=0;i<copied;i++) sum += arr[i];
         double atrMA = sum / copied;
         if(atr > atrMA * MaxATRMultiplier) return;
      }
   }

   // Spread filter
   if(SpreadPoints() > MaxSpreadPoints) return;

   // Session filter
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   if(!(SessionStartHour <= dt.hour && dt.hour <= SessionEndHour)) return;

   // Drawdown kill-switch
   if(EnableDrawdownKillSwitch)
   {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(EquityPeak <= 0) EquityPeak = equity;
      double ddPercent = (EquityPeak - equity) / EquityPeak * 100.0;
      if(ddPercent > MaxDrawdownPercent) return;
   }

   // place base order
   double price = buy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double lot = SmartLot(0);
   double sl = buy ? price - 2000*_Point : price + 2000*_Point;
   bool ok = false;
   if(buy) ok = trade.Buy(lot, _Symbol, 0, sl, 0);
   else    ok = trade.Sell(lot, _Symbol, 0, sl, 0);

   if(ok)
   {
      gridBasePrice = price;
      gridBaseIsBuy = buy;
      gridLevelsOpened = 1; // base opened
   }
}

// Manage basket: partial close on target, profit lock
void ManageBasket()
{
   double basketProfit = BasketProfitUSD();
   if(basketProfit > GlobalPeakProfit) GlobalPeakProfit = basketProfit;

   // Partial close when basket target reached
   if(basketProfit >= BasketTakeProfitUSD && BasketTakeProfitUSD > 0)
   {
      PartialCloseByPercent(BasketPartialClosePercent);
      // increase target slightly to avoid immediate repeat
      BasketTakeProfitUSD *= 1.05;
   }

   // Profit retrace lock
   if(GlobalPeakProfit >= MinProfitLock && basketProfit < (GlobalPeakProfit - ProfitRetrace))
   {
      CloseAllPositions();
   }
}

// OnTick main
void OnTick()
{
   // update equity peak
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity > EquityPeak) EquityPeak = equity;

   // basic spread filter
   if(SpreadPoints() > MaxSpreadPoints) return;

   // manage existing positions
   ManagePositions();
   ManageBasket();

   // allow adding levels even within same bar
   TryAddGridLevel();

   // bar change guard for new grid open
   datetime t = iTime(_Symbol, _Period, 0);
   if(t == lastBar) return;
   lastBar = t;

   // do not open new grid if we already have positions
   if(CountOurPositions() > 0) return;

   // indicators for entry
   double fArr[2], sArr[2], tArr[2];
   ArraySetAsSeries(fArr,true); ArraySetAsSeries(sArr,true); ArraySetAsSeries(tArr,true);
   if(CopyBuffer(hFast,0,0,2,fArr) <= 0) return;
   if(CopyBuffer(hSlow,0,0,2,sArr) <= 0) return;
   if(CopyBuffer(hTrend,0,0,2,tArr) <= 0) return;

   // entry logic: EMA cross + trend alignment
   if(fArr[0] > sArr[0] && fArr[0] > tArr[0])
   {
      OpenInitialGrid(true);
   }
   else if(fArr[0] < sArr[0] && fArr[0] < tArr[0])
   {
      OpenInitialGrid(false);
   }
}