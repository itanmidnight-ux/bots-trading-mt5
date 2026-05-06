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
input group "=== CAPITAL & RISK PROFILES ===";
enum RiskProfileEnum {Conservative=0, Balanced=1, Aggressive=2, Extreme=3};
input RiskProfileEnum RiskProfile = Conservative;

input group "=== LEVERAGE MODES (informative) ===";
input double LeverageLowBalance = 3000.0; // used when balance <= LeverageSwitchBalance (informative)
input double LeverageHighBalance = 500.0; // used when balance > LeverageSwitchBalance (informative)
input double LeverageSwitchBalance = 250.0; // threshold to switch leverage profile

input group "=== GRID / LOTS ===";
input double baseLot = 0.01;           // lote base mínimo
input bool   autoLot = true;           // calcular lotes automáticamente
input double riskPercentPerGrid = 0.25; // % del balance por nivel (Conservative default)
input int    maxLevels = 6;            // niveles máximos del grid
input double gridDistancePoints = 400; // distancia entre niveles en puntos (XAUUSD ~ 400 points = 40 pips)
input double levelFactor = 0.20;       // factor de escalado por nivel (smart scaling)

input group "=== INDICADORES ===";
input int FastEMA   = 9;
input int SlowEMA   = 21;
input int TrendEMA  = 50;
input int RSI_Per   = 14;
input int ATR_Per   = 14;

input group "=== FILTERS & SAFETY ===";
input double MaxSpreadPoints = 50;     // en puntos
input double MaxATRMultiplier = 2.5;   // bloquear apertura si ATR > ATR_MA * multiplier
input double MaxDrawdownPercent = 40.0; // stop trading if drawdown > X% from equity peak (profile adjusted)
input double MinBalanceForScaling = 14.0; // mínimo balance target
input int    SessionStartHour = 0;     // sesión permitida (0-23) - 0 = todo el día
input int    SessionEndHour = 23;

input group "=== BASKET MANAGEMENT ===";
input double BasketTakeProfitUSD = 5.0; // objetivo por basket en USD (conservador)
input double BasketPartialClosePercent = 50.0; // % a cerrar cuando se alcanza objetivo
input double MinProfitLock = 0.50;      // conservar ganancia (ya en tu EA)
input double ProfitRetrace = 0.20;      // retrace para cerrar basket (ya en tu EA)

input group "=== MISC ===";
input int Magic = 777;
input bool EnableMultiTF = true;        // validar M5/M15/H1 antes de abrir
input bool EnableVolatilityFilter = true;
input bool EnableDrawdownKillSwitch = true;
input bool EnableNewsFilter = false;    // placeholder (no news feed implemented)

//---------------- GLOBALS ----------------//
int hFast, hSlow, hTrend, hRSI, hATR;
datetime lastBar = 0;
double GlobalPeakEquity = 0;
double EquityPeak = 0;

// Grid storage (parallel arrays)
int    gridCount = 0;
ulong  gridTicket[256];
double gridPrice[256];
double gridLot[256];
int    gridLevel[256];
bool   gridIsBuy[256];

//+------------------------------------------------------------------+
// Utility: profile adjustments
void ApplyProfileSettings() {
   switch(RiskProfile) {
      case Conservative:
         // conservative defaults
         if(!autoLot) baseLot = MathMax(baseLot, 0.01);
         riskPercentPerGrid = 0.25;
         maxLevels = 6;
         gridDistancePoints = 400;
         levelFactor = 0.18;
         BasketTakeProfitUSD = MathMax(BasketTakeProfitUSD, 5.0);
         MaxDrawdownPercent = 40.0;
         break;
      case Balanced:
         riskPercentPerGrid = 0.5;
         maxLevels = 8;
         gridDistancePoints = 350;
         levelFactor = 0.25;
         BasketTakeProfitUSD = MathMax(BasketTakeProfitUSD, 10.0);
         MaxDrawdownPercent = 45.0;
         break;
      case Aggressive:
         riskPercentPerGrid = 1.0;
         maxLevels = 10;
         gridDistancePoints = 300;
         levelFactor = 0.35;
         BasketTakeProfitUSD = MathMax(BasketTakeProfitUSD, 20.0);
         MaxDrawdownPercent = 55.0;
         break;
      case Extreme:
         riskPercentPerGrid = 2.0;
         maxLevels = 12;
         gridDistancePoints = 250;
         levelFactor = 0.5;
         BasketTakeProfitUSD = MathMax(BasketTakeProfitUSD, 50.0);
         MaxDrawdownPercent = 70.0;
         break;
   }
}

//+------------------------------------------------------------------+
// OnInit: create indicator handles
int OnInit() {
   ApplyProfileSettings();

   hFast  = iMA(_Symbol, _Period, FastEMA, 0, MODE_EMA, PRICE_CLOSE);
   hSlow  = iMA(_Symbol, _Period, SlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   hTrend = iMA(_Symbol, _Period, TrendEMA, 0, MODE_EMA, PRICE_CLOSE);
   hRSI   = iRSI(_Symbol, _Period, RSI_Per, PRICE_CLOSE);
   hATR   = iATR(_Symbol, _Period, ATR_Per);

   trade.SetExpertMagicNumber(Magic);

   // init grid arrays
   gridCount = 0;
   for(int i=0;i<ArraySize(gridTicket);i++) { gridTicket[i]=0; gridPrice[i]=0; gridLot[i]=0; gridLevel[i]=0; gridIsBuy[i]=false; }

   EquityPeak = AccountInfoDouble(ACCOUNT_EQUITY);
   GlobalPeakEquity = EquityPeak;

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
// Helper: get current spread in points
double SpreadPoints() {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   return (ask - bid) / _Point;
}

//+------------------------------------------------------------------+
// ATR current value
double CurrentATR() {
   double atrArr[];
   ArraySetAsSeries(atrArr,true);
   if(CopyBuffer(hATR,0,0,1,atrArr) <= 0) return 0;
   return atrArr[0];
}

//+------------------------------------------------------------------+
// Multi timeframe bias check (M5, M15, H1) - returns +1 buy bias, -1 sell bias, 0 neutral
int MultiTFBias() {
   if(!EnableMultiTF) return 0;
   // We'll check EMA cross on M5 and M15 and H1: require majority agreement
   int votes = 0;
   int checks = 0;
   ENUM_TIMEFRAMES tfs[3] = {PERIOD_M5, PERIOD_M15, PERIOD_H1};
   for(int i=0;i<3;i++) {
      int tf = tfs[i];
      double fast = iMA(_Symbol, tf, FastEMA, 0, MODE_EMA, PRICE_CLOSE, 0);
      double slow = iMA(_Symbol, tf, SlowEMA, 0, MODE_EMA, PRICE_CLOSE, 0);
      if(fast == 0 || slow == 0) continue;
      checks++;
      if(fast > slow) votes++;
      else votes--;
   }
   if(checks == 0) return 0;
   if(votes > 0) return 1;
   if(votes < 0) return -1;
   return 0;
}

//+------------------------------------------------------------------+
// Smart lot calculation based on balance and level
double SmartLot(int level) {
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(minLot <= 0) minLot = 0.01;
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(maxLot <= 0) maxLot = 100.0;

   // base lot scaled by balance and riskPercentPerGrid
   double lotFromRisk = (bal * (riskPercentPerGrid/100.0)) / 1000.0; // heuristic divisor
   // fallback to baseLot if autoLot disabled
   double lot = autoLot ? MathMax(baseLot, lotFromRisk) : baseLot;

   // scale by level using levelFactor
   lot = lot * (1.0 + levelFactor * level);

   // ensure within min/max and round to step
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0) step = 0.01;
   lot = MathMax(minLot, MathMin(maxLot, lot));
   // round to step
   lot = MathFloor(lot/step) * step;
   if(lot < minLot) lot = minLot;
   return NormalizeDouble(lot,2);
}

//+------------------------------------------------------------------+
// Add grid level record
void AddGridRecord(ulong ticket, double price, double lot, int level, bool isBuy) {
   if(gridCount >= ArraySize(gridTicket)) return;
   gridTicket[gridCount] = ticket;
   gridPrice[gridCount]  = price;
   gridLot[gridCount]    = lot;
   gridLevel[gridCount]  = level;
   gridIsBuy[gridCount]  = isBuy;
   gridCount++;
}

//+------------------------------------------------------------------+
// Remove grid record by index
void RemoveGridRecordByIndex(int idx) {
   if(idx < 0 || idx >= gridCount) return;
   for(int i=idx;i<gridCount-1;i++) {
      gridTicket[i] = gridTicket[i+1];
      gridPrice[i]  = gridPrice[i+1];
      gridLot[i]    = gridLot[i+1];
      gridLevel[i]  = gridLevel[i+1];
      gridIsBuy[i]  = gridIsBuy[i+1];
   }
   gridCount--;
}

//+------------------------------------------------------------------+
// Open initial grid (base) and optionally pre-place symmetric levels
void OpenInitialGrid(bool buy) {
   double price = buy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   int bias = MultiTFBias();
   if(bias != 0) {
      if(buy && bias < 0) return; // multiTF disagrees
      if(!buy && bias > 0) return;
   }

   // Volatility filter
   if(EnableVolatilityFilter) {
      double atr = CurrentATR();
      if(atr <= 0) return;
      // compute ATR moving average (simple using last 10 ATRs)
      double atrs[10];
      ArraySetAsSeries(atrs,true);
      int copied = CopyBuffer(hATR,0,0,10,atrs);
      if(copied > 0) {
         double sum=0;
         for(int i=0;i<copied;i++) sum += atrs[i];
         double atrMA = sum / copied;
         if(atr > atrMA * MaxATRMultiplier) return; // too volatile
      }
   }

   // Spread filter
   if(SpreadPoints() > MaxSpreadPoints) return;

   // Session filter
   datetime now = TimeCurrent();
   MqlDateTime dt; TimeToStruct(now, dt);
   if(!(SessionStartHour <= dt.hour && dt.hour <= SessionEndHour)) return;

   // Drawdown kill-switch
   if(EnableDrawdownKillSwitch) {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(EquityPeak <= 0) EquityPeak = equity;
      double ddPercent = (EquityPeak - equity) / EquityPeak * 100.0;
      if(ddPercent > MaxDrawdownPercent) return;
   }

   // Place base order
   double lot = SmartLot(0);
   double sl = buy ? price - 2000*_Point : price + 2000*_Point; // large emergency SL (user had EmergencySL)
   bool ok=false;
   ulong ticket=0;
   if(buy) {
      ok = trade.Buy(lot, NULL, price, sl, 0);
      ticket = trade.ResultOrder();
   } else {
      ok = trade.Sell(lot, NULL, price, sl, 0);
      ticket = trade.ResultOrder();
   }
   if(!ok) return;

   AddGridRecord(ticket, price, lot, 0, buy);

   // Pre-place symmetric grid levels (only place orders when price moves into them)
   // We'll not place pending orders to avoid broker restrictions; instead we add logic to add levels dynamically in OnTick
}

//+------------------------------------------------------------------+
// Add next grid level when price moves away from base
void TryAddGridLevels() {
   if(gridCount == 0) return;
   // find base price (level 0)
   double basePrice = gridPrice[0];
   bool baseIsBuy = gridIsBuy[0];
   // count existing levels
   int levelsExisting = 0;
   for(int i=0;i<gridCount;i++) if(gridLevel[i] >= 0) levelsExisting = MathMax(levelsExisting, gridLevel[i]);

   // determine if we can add next level
   if(levelsExisting >= maxLevels-1) return;

   double currentPrice = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) + SymbolInfoDouble(_Symbol, SYMBOL_BID)) / 2.0;
   int nextLevel = levelsExisting + 1;
   double distance = gridDistancePoints * _Point * nextLevel;
   double targetPrice = baseIsBuy ? basePrice - distance : basePrice + distance;

   // If price has reached targetPrice (or beyond), open new level
   if(baseIsBuy) {
      if(currentPrice <= targetPrice) {
         double lot = SmartLot(nextLevel);
         double sl = currentPrice - 2000*_Point;
         bool ok = trade.Buy(lot, NULL, SymbolInfoDouble(_Symbol, SYMBOL_ASK), sl, 0);
         if(ok) {
            ulong tk = trade.ResultOrder();
            AddGridRecord(tk, SymbolInfoDouble(_Symbol, SYMBOL_ASK), lot, nextLevel, true);
         }
      }
   } else {
      if(currentPrice >= targetPrice) {
         double lot = SmartLot(nextLevel);
         double sl = currentPrice + 2000*_Point;
         bool ok = trade.Sell(lot, NULL, SymbolInfoDouble(_Symbol, SYMBOL_BID), sl, 0);
         if(ok) {
            ulong tk = trade.ResultOrder();
            AddGridRecord(tk, SymbolInfoDouble(_Symbol, SYMBOL_BID), lot, nextLevel, false);
         }
      }
   }
}

//+------------------------------------------------------------------+
// Compute basket profit (USD) for our magic
double BasketProfitUSD() {
   double total = 0.0;
   for(int i=PositionsTotal()-1;i>=0;i--) {
      ulong tk = PositionGetTicket(i);
      if(PositionSelectByTicket(tk) && PositionGetInteger(POSITION_MAGIC) == Magic) {
         total += PositionGetDouble(POSITION_PROFIT);
      }
   }
   return total;
}

//+------------------------------------------------------------------+
// Basket management: close partial or full when target reached or retrace occurs
void ManageBasket() {
   double basketProfit = BasketProfitUSD();
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity > EquityPeak) EquityPeak = equity;

   // update global peak for profit lock
   if(basketProfit > GlobalPeakEquity) GlobalPeakEquity = basketProfit;

   // Partial/Full close on basket target
   if(basketProfit >= BasketTakeProfitUSD) {
      // close partial: close X% of positions by volume
      double toClosePercent = BasketPartialClosePercent / 100.0;
      // iterate positions and close proportionally
      for(int i=PositionsTotal()-1;i>=0;i--) {
         ulong tk = PositionGetTicket(i);
         if(PositionSelectByTicket(tk) && PositionGetInteger(POSITION_MAGIC) == Magic) {
            double vol = PositionGetDouble(POSITION_VOLUME);
            double closeVol = vol * toClosePercent;
            if(closeVol < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) closeVol = vol; // close full if too small
            trade.PositionClosePartial(tk, closeVol);
         }
      }
      // after partial close, reset basket target slightly higher to avoid immediate re-close
      BasketTakeProfitUSD *= 1.1;
   }

   // Profit retrace lock (from your EA)
   if(GlobalPeakEquity >= MinProfitLock && basketProfit < (GlobalPeakEquity - ProfitRetrace)) {
      // close all
      CloseAllPositions();
   }
}

//+------------------------------------------------------------------+
// Close all positions with our magic
void CloseAllPositions() {
   for(int i=PositionsTotal()-1;i>=0;i--) {
      ulong tk = PositionGetTicket(i);
      if(PositionSelectByTicket(tk) && PositionGetInteger(POSITION_MAGIC) == Magic) {
         trade.PositionClose(tk);
      }
   }
   // clear grid records
   gridCount = 0;
}

//+------------------------------------------------------------------+
// ShouldCloseNegative: improved logic using trend and momentum (from original EA)
bool ShouldCloseNegative(bool isBuy) {
   double rsiArr[], fArr[], sArr[];
   ArraySetAsSeries(rsiArr,true); ArraySetAsSeries(fArr,true); ArraySetAsSeries(sArr,true);
   if(CopyBuffer(hRSI,0,0,1,rsiArr) <= 0) return false;
   if(CopyBuffer(hFast,0,0,1,fArr) <= 0 || CopyBuffer(hSlow,0,0,1,sArr) <= 0) return false;

   bool trendWrong = isBuy ? (iClose(_Symbol, _Period, 0) < iMA(_Symbol, _Period, TrendEMA, 0, MODE_EMA, PRICE_CLOSE))
                           : (iClose(_Symbol, _Period, 0) > iMA(_Symbol, _Period, TrendEMA, 0, MODE_EMA, PRICE_CLOSE));
   bool momentumWrong = isBuy ? (rsiArr[0] < 40.0 || fArr[0] < sArr[0])
                              : (rsiArr[0] > 60.0 || fArr[0] > sArr[0]);
   return (trendWrong && momentumWrong);
}

//+------------------------------------------------------------------+
// Manage existing positions: close negative ones if conditions met, update grid records
void ManagePositions() {
   // update grid records: remove closed tickets
   for(int gi=gridCount-1; gi>=0; gi--) {
      ulong tk = gridTicket[gi];
      bool found = false;
      for(int i=PositionsTotal()-1;i>=0;i--) {
         ulong pt = PositionGetTicket(i);
         if(pt == tk) { found = true; break; }
      }
      if(!found) RemoveGridRecordByIndex(gi);
   }

   // iterate positions for negative management
   for(int i=PositionsTotal()-1;i>=0;i--) {
      ulong tk = PositionGetTicket(i);
      if(PositionSelectByTicket(tk) && PositionGetInteger(POSITION_MAGIC) == Magic) {
         double profit = PositionGetDouble(POSITION_PROFIT);
         bool isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
         if(profit < 0) {
            if(ShouldCloseNegative(isBuy)) {
               trade.PositionClose(tk);
               // remove from grid records
               for(int gi=0; gi<gridCount; gi++) {
                  if(gridTicket[gi] == tk) { RemoveGridRecordByIndex(gi); break; }
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
// OnTick: main loop
void OnTick() {
   // basic spread filter
   if(SpreadPoints() > MaxSpreadPoints) return;

   // manage positions and basket
   ManagePositions();
   ManageBasket();

   // bar check to avoid repeated open on same bar
   datetime t = iTime(_Symbol, _Period, 0);
   if(t == lastBar) {
      // still try to add grid levels dynamically even within same bar
      TryAddGridLevels();
      return;
   }
   lastBar = t;

   // do not open new grids if drawdown kill switch triggered
   if(EnableDrawdownKillSwitch) {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(equity > EquityPeak) EquityPeak = equity;
      double ddPercent = (EquityPeak - equity) / EquityPeak * 100.0;
      if(ddPercent > MaxDrawdownPercent) return;
   }

   // avoid opening if we already have positions
   int ourPosCount = 0;
   for(int i=PositionsTotal()-1;i>=0;i--) {
      ulong tk = PositionGetTicket(i);
      if(PositionSelectByTicket(tk) && PositionGetInteger(POSITION_MAGIC) == Magic) ourPosCount++;
   }
   if(ourPosCount > 0) {
      // still try to add grid levels
      TryAddGridLevels();
      return;
   }

   // indicator buffers
   double fArr[], sArr[], tArr[];
   ArraySetAsSeries(fArr,true); ArraySetAsSeries(sArr,true); ArraySetAsSeries(tArr,true);
   if(CopyBuffer(hFast,0,0,2,fArr) <= 0 || CopyBuffer(hSlow,0,0,2,sArr) <= 0 || CopyBuffer(hTrend,0,0,2,tArr) <= 0) return;

   // entry logic inspired by EMA PRO TREND + QuantumQueen filters
   // require EMA cross and trend alignment
   if(fArr[0] > sArr[0] && fArr[0] > tArr[0]) {
      // potential buy grid
      OpenInitialGrid(true);
   } else if(fArr[0] < sArr[0] && fArr[0] < tArr[0]) {
      // potential sell grid
      OpenInitialGrid(false);
   }
}

//+------------------------------------------------------------------+
// OnDeinit: cleanup
void OnDeinit(const int reason) {
   // nothing special
}

//+------------------------------------------------------------------+
// Expert helper: manual commands via chart (not required but useful)
//+------------------------------------------------------------------+