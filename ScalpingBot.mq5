
//+------------------------------------------------------------------+
//|                                                    ScalpingBot.mq5|
//|       Expert Advisor: RSI1+RSI5+BB+EMA+MACD+ATR Multi-TF         |
//|       Autor: Fabian                                             |
//+------------------------------------------------------------------+
#property strict

//--- Input Parameters
input double lotSize = 0.1;
input int slMultiplier = 120; // Stop Loss = ATR*slMultiplier/100
input int tpMultiplier = 150; // Take Profit = ATR*tpMultiplier/100

//--- RSI Parameters
input int rsi1Period = 1;
input int rsi5Period = 5;
input double rsiBuyLevel = 8.9;
input double rsiSellLevel = 70;
input double rsiTpLevel = 50;

//--- Bollinger Bands Parameters
input int bbPeriod = 14;
input double bbDeviation = 0.18;

//--- EMA Parameters
input int emaFastPeriod = 9;
input int emaSlowPeriod = 21;

//--- MACD Parameters
input int macdFast = 12;
input int macdSlow = 26;
input int macdSignal = 9;

//--- ATR Parameters
input int atrPeriod = 14;

//--- Multi-Timeframe Parameters
input ENUM_TIMEFRAMES tfShort = PERIOD_M5;
input ENUM_TIMEFRAMES tfConfirm1 = PERIOD_M15;
input ENUM_TIMEFRAMES tfConfirm2 = PERIOD_H1;

//+------------------------------------------------------------------+
//| Expert Initialization                                            |
//+------------------------------------------------------------------+
int rsi1Handle, rsi5Handle;
int bbHandle;
int emaFastHandle, emaSlowHandle;
int macdHandle;
int atrHandle;

//+------------------------------------------------------------------+
int OnInit()
{
   // RSI handles
   rsi1Handle = iRSI(_Symbol, tfShort, rsi1Period, PRICE_WEIGHTED);
   rsi5Handle = iRSI(_Symbol, tfShort, rsi5Period, PRICE_WEIGHTED);

   // Bollinger Bands handle
   bbHandle = iBands(_Symbol, tfShort, bbPeriod, bbDeviation, 0, PRICE_WEIGHTED);

   // EMA handles
   emaFastHandle = iMA(_Symbol, tfShort, emaFastPeriod, 0, MODE_EMA, PRICE_CLOSE);
   emaSlowHandle = iMA(_Symbol, tfShort, emaSlowPeriod, 0, MODE_EMA, PRICE_CLOSE);

   // MACD handle
   macdHandle = iMACD(_Symbol, tfShort, macdFast, macdSlow, macdSignal, PRICE_CLOSE);

   // ATR handle
   atrHandle = iATR(_Symbol, tfShort, atrPeriod);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert Tick                                                      |
//+------------------------------------------------------------------+
void OnTick()
{
   double rsi1, rsi5;
   double bbUpper, bbMiddle, bbLower;
   double emaFast, emaSlow;
   double macdMain, macdSignal, macdHist;
   double atrValue;

   //--- Get latest indicator values
   rsi1 = iRSI(_Symbol, tfShort, rsi1Period, PRICE_WEIGHTED, 0);
   rsi5 = iRSI(_Symbol, tfShort, rsi5Period, PRICE_WEIGHTED, 0);

   bbUpper = iBands(_Symbol, tfShort, bbPeriod, bbDeviation, 0, PRICE_WEIGHTED, MODE_UPPER, 0);
   bbMiddle = iBands(_Symbol, tfShort, bbPeriod, bbDeviation, 0, PRICE_WEIGHTED, MODE_MAIN, 0);
   bbLower = iBands(_Symbol, tfShort, bbPeriod, bbDeviation, 0, PRICE_WEIGHTED, MODE_LOWER, 0);

   emaFast = iMA(_Symbol, tfShort, emaFastPeriod, 0, MODE_EMA, PRICE_CLOSE, 0);
   emaSlow = iMA(_Symbol, tfShort, emaSlowPeriod, 0, MODE_EMA, PRICE_CLOSE, 0);

   macdMain = iMACD(_Symbol, tfShort, macdFast, macdSlow, macdSignal, PRICE_CLOSE, MODE_MAIN, 0);
   macdSignal = iMACD(_Symbol, tfShort, macdFast, macdSlow, macdSignal, PRICE_CLOSE, MODE_SIGNAL, 0);

   atrValue = iATR(_Symbol, tfShort, atrPeriod, 0);

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   //--- Confirm trend in higher timeframes
   bool trendUp = iMA(_Symbol, tfConfirm1, emaFastPeriod, 0, MODE_EMA, PRICE_CLOSE, 0) >
                  iMA(_Symbol, tfConfirm1, emaSlowPeriod, 0, MODE_EMA, PRICE_CLOSE, 0) &&
                  iMA(_Symbol, tfConfirm2, emaFastPeriod, 0, MODE_EMA, PRICE_CLOSE, 0) >
                  iMA(_Symbol, tfConfirm2, emaSlowPeriod, 0, MODE_EMA, PRICE_CLOSE, 0);

   bool trendDown = iMA(_Symbol, tfConfirm1, emaFastPeriod, 0, MODE_EMA, PRICE_CLOSE, 0) <
                    iMA(_Symbol, tfConfirm1, emaSlowPeriod, 0, MODE_EMA, PRICE_CLOSE, 0) &&
                    iMA(_Symbol, tfConfirm2, emaFastPeriod, 0, MODE_EMA, PRICE_CLOSE, 0) <
                    iMA(_Symbol, tfConfirm2, emaSlowPeriod, 0, MODE_EMA, PRICE_CLOSE, 0);

   //--- Buy conditions
   if(rsi1 < rsiBuyLevel && rsi5 > rsi1 && bid <= bbLower && emaFast > emaSlow && macdMain > macdSignal && trendUp)
   {
      OpenTrade(ORDER_TYPE_BUY, lotSize, ask, atrValue);
   }

   //--- Sell conditions
   if(rsi1 > rsiSellLevel && rsi5 < rsi1 && ask >= bbUpper && emaFast < emaSlow && macdMain < macdSignal && trendDown)
   {
      OpenTrade(ORDER_TYPE_SELL, lotSize, bid, atrValue);
   }
}

//+------------------------------------------------------------------+
//| Function to Open Trades                                          |
//+------------------------------------------------------------------+
void OpenTrade(int type, double lots, double price, double atrValue)
{
   double sl, tp;
   if(type == ORDER_TYPE_BUY)
   {
      sl = price - (atrValue * slMultiplier/100);
      tp = price + (atrValue * tpMultiplier/100);
   }
   else
   {
      sl = price + (atrValue * slMultiplier/100);
      tp = price - (atrValue * tpMultiplier/100);
   }

   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);

   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = lots;
   request.type = type;
   request.price = price;
   request.sl = sl;
   request.tp = tp;
   request.deviation = 10;
   request.magic = 123456;
   request.comment = "ScalpingBotTrade";

   OrderSend(request, result);
}
//+------------------------------------------------------------------+
