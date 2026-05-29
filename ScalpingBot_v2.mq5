
//+------------------------------------------------------------------+
//|                                                ScalpingBot_v2.mq5|
//|      Expert Advisor: RSI1+RSI5+BB+EMA+MACD+ATR Multi-TF           |
//|      Autor: Fabian                                               |
//+------------------------------------------------------------------+
#property strict
#property version   "1.0"
#property description "EA de scalping con RSI1+RSI5+Bollinger+EMA+MACD+ATR con confirmación multi-timeframe"

//--- Inputs
input double lotSize = 0.1;
input int slMultiplier = 120; // Stop Loss = ATR*slMultiplier/100
input int tpMultiplier = 150; // Take Profit = ATR*tpMultiplier/100

// RSI
input int rsi1Period = 1;
input int rsi5Period = 5;
input double rsiBuyLevel = 8.9;
input double rsiSellLevel = 70;

// Bollinger Bands
input int bbPeriod = 14;
input double bbDeviation = 0.18;

// EMA
input int emaFastPeriod = 9;
input int emaSlowPeriod = 21;

// MACD
input int macdFast = 12;
input int macdSlow = 26;
input int macdSignal = 9;

// ATR
input int atrPeriod = 14;

// Multi-timeframe EMA confirmation
input ENUM_TIMEFRAMES tfConfirm1 = PERIOD_M15;
input ENUM_TIMEFRAMES tfConfirm2 = PERIOD_H1;

// Magic number
input int magicNumber = 123456;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("ScalpingBot_v2 inicializado correctamente.");
   return(INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // --- Siempre operar en 1m
   ENUM_TIMEFRAMES tfShort = PERIOD_M1;

   // --- Variables para indicadores
   double rsi1 = iRSI(_Symbol, tfShort, rsi1Period, PRICE_WEIGHTED, 0);
   double rsi5 = iRSI(_Symbol, tfShort, rsi5Period, PRICE_WEIGHTED, 0);
   double bbUpper = iBands(_Symbol, tfShort, bbPeriod, bbDeviation, 0, PRICE_WEIGHTED, MODE_UPPER, 0);
   double bbMiddle = iBands(_Symbol, tfShort, bbPeriod, bbDeviation, 0, PRICE_WEIGHTED, MODE_MAIN, 0);
   double bbLower = iBands(_Symbol, tfShort, bbPeriod, bbDeviation, 0, PRICE_WEIGHTED, MODE_LOWER, 0);
   double emaFast = iMA(_Symbol, tfShort, emaFastPeriod, 0, MODE_EMA, PRICE_CLOSE, 0);
   double emaSlow = iMA(_Symbol, tfShort, emaSlowPeriod, 0, MODE_EMA, PRICE_CLOSE, 0);
   double macdMain = iMACD(_Symbol, tfShort, macdFast, macdSlow, macdSignal, PRICE_CLOSE, MODE_MAIN, 0);
   double macdSignalVal = iMACD(_Symbol, tfShort, macdFast, macdSlow, macdSignal, PRICE_CLOSE, MODE_SIGNAL, 0);
   double atrValue = iATR(_Symbol, tfShort, atrPeriod, 0);

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // --- Confirmación EMA en timeframes mayores
   double emaConfirmFast1 = iMA(_Symbol, tfConfirm1, emaFastPeriod, 0, MODE_EMA, PRICE_CLOSE, 0);
   double emaConfirmSlow1 = iMA(_Symbol, tfConfirm1, emaSlowPeriod, 0, MODE_EMA, PRICE_CLOSE, 0);
   double emaConfirmFast2 = iMA(_Symbol, tfConfirm2, emaFastPeriod, 0, MODE_EMA, PRICE_CLOSE, 0);
   double emaConfirmSlow2 = iMA(_Symbol, tfConfirm2, emaSlowPeriod, 0, MODE_EMA, PRICE_CLOSE, 0);

   bool trendUp = (emaConfirmFast1 > emaConfirmSlow1) && (emaConfirmFast2 > emaConfirmSlow2);
   bool trendDown = (emaConfirmFast1 < emaConfirmSlow1) && (emaConfirmFast2 < emaConfirmSlow2);

   // --- Comprar
   if(rsi1 < rsiBuyLevel && rsi5 > rsi1 && bid <= bbLower && emaFast > emaSlow && macdMain > macdSignalVal && trendUp)
   {
      if(!PositionSelect(_Symbol))
         OpenTrade(ORDER_TYPE_BUY, lotSize, ask, atrValue);
   }

   // --- Vender
   if(rsi1 > rsiSellLevel && rsi5 < rsi1 && ask >= bbUpper && emaFast < emaSlow && macdMain < macdSignalVal && trendDown)
   {
      if(!PositionSelect(_Symbol))
         OpenTrade(ORDER_TYPE_SELL, lotSize, bid, atrValue);
   }
}
//+------------------------------------------------------------------+
//| Función para abrir órdenes                                        |
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
   request.magic = magicNumber;
   request.comment = "ScalpingBot_v2";

   if(!OrderSend(request,result))
      Print("Error al enviar orden: ", GetLastError());
   else
      Print("Orden ejecutada correctamente: ", (type==ORDER_TYPE_BUY?"BUY":"SELL"));
}
//+------------------------------------------------------------------+
