//+------------------------------------------------------------------+
//|                                              ScalpingMTF_EA.mq5  |
//|                     Multi-Timeframe Scalping Expert Advisor       |
//|                                                      Version 1.0  |
//|  Estrategia: RSI(1)+RSI(5)+BB+EMA+MACD+ATR | MTF: 15m+1H        |
//+------------------------------------------------------------------+
#property copyright "ScalpingMTF EA v1.0"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//==========================================================================
//  INPUTS
//==========================================================================
input group "=== GESTION DE RIESGO ==="
input double   InpLotSize         = 0.01;  // Lote fijo
input double   InpSL_ATR          = 1.2;   // Multiplicador SL (x ATR)
input double   InpTP_ATR          = 1.5;   // Multiplicador TP (x ATR)
input bool     InpUseTrailing     = true;  // Activar trailing stop ATR

input group "=== RSI ==="
input double   InpRSI1_Buy        = 8.9;   // RSI(1) nivel BUY
input double   InpRSI1_Sell       = 70.0;  // RSI(1) nivel SELL
input double   InpRSI_TP          = 50.0;  // RSI nivel Take Profit

input group "=== BOLLINGER BANDS ==="
input int      InpBB_Period       = 14;    // Periodo BB
input double   InpBB_Dev          = 0.18;  // Desviacion BB

input group "=== ATR ==="
input int      InpATR_Period      = 14;    // Periodo ATR
input int      InpATR_AvgBars     = 20;    // Barras promedio ATR (filtro flat)

input group "=== FILTRO HORARIO ==="
input int      InpFridayStopHour  = 20;    // Viernes: detener trades desde hora
input int      InpMondayStartHour = 2;     // Lunes: iniciar trades desde hora

input group "=== EA CONFIGURACION ==="
input int      InpMagicNumber     = 77777; // Magic Number EA
input int      InpSlippage        = 10;    // Slippage maximo (puntos)

//==========================================================================
//  HANDLES DE INDICADORES
//==========================================================================
int hRSI1, hRSI5;        // RSI periodo 1 y 5 (HLCC/4)
int hBB;                  // Bollinger Bands
int hEMA9_M1,  hEMA21_M1;
int hEMA9_M15, hEMA21_M15;
int hEMA9_H1,  hEMA21_H1;
int hMACD;                // MACD 12/26/9
int hATR;                 // ATR 14

CTrade trade;

//==========================================================================
//  INICIALIZACION
//==========================================================================
int OnInit()
{
   //--- RSI con PRICE_WEIGHTED = HLCC/4
   hRSI1      = iRSI(_Symbol, PERIOD_M1,  1, PRICE_WEIGHTED);
   hRSI5      = iRSI(_Symbol, PERIOD_M1,  5, PRICE_WEIGHTED);

   //--- Bollinger Bands con PRICE_WEIGHTED = HLCC/4
   hBB        = iBands(_Symbol, PERIOD_M1, InpBB_Period, 0, InpBB_Dev, PRICE_WEIGHTED);

   //--- EMA 9 y 21 en 1M
   hEMA9_M1   = iMA(_Symbol, PERIOD_M1,   9, 0, MODE_EMA, PRICE_CLOSE);
   hEMA21_M1  = iMA(_Symbol, PERIOD_M1,  21, 0, MODE_EMA, PRICE_CLOSE);

   //--- EMA 9 y 21 en 15M (confirmacion MTF)
   hEMA9_M15  = iMA(_Symbol, PERIOD_M15,  9, 0, MODE_EMA, PRICE_CLOSE);
   hEMA21_M15 = iMA(_Symbol, PERIOD_M15, 21, 0, MODE_EMA, PRICE_CLOSE);

   //--- EMA 9 y 21 en 1H (confirmacion MTF)
   hEMA9_H1   = iMA(_Symbol, PERIOD_H1,   9, 0, MODE_EMA, PRICE_CLOSE);
   hEMA21_H1  = iMA(_Symbol, PERIOD_H1,  21, 0, MODE_EMA, PRICE_CLOSE);

   //--- MACD 12/26/9
   hMACD      = iMACD(_Symbol, PERIOD_M1, 12, 26, 9, PRICE_CLOSE);

   //--- ATR 14
   hATR       = iATR(_Symbol, PERIOD_M1, InpATR_Period);

   //--- Validacion de handles
   if(hRSI1==INVALID_HANDLE || hRSI5==INVALID_HANDLE || hBB==INVALID_HANDLE  ||
      hEMA9_M1==INVALID_HANDLE  || hEMA21_M1==INVALID_HANDLE  ||
      hEMA9_M15==INVALID_HANDLE || hEMA21_M15==INVALID_HANDLE ||
      hEMA9_H1==INVALID_HANDLE  || hEMA21_H1==INVALID_HANDLE  ||
      hMACD==INVALID_HANDLE     || hATR==INVALID_HANDLE)
   {
      Alert("ScalpingMTF EA | ERROR: No se pudieron crear los handles de indicadores. Simbolo: ", _Symbol);
      return INIT_FAILED;
   }

   //--- Configuracion del objeto trade
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippage);
   trade.SetTypeFilling(GetFillingMode());

   Print("ScalpingMTF EA iniciado | Simbolo: ", _Symbol,
         " | Magic: ", InpMagicNumber,
         " | Lote: ", InpLotSize);
   return INIT_SUCCEEDED;
}

//==========================================================================
//  LIBERACION DE INDICADORES
//==========================================================================
void OnDeinit(const int reason)
{
   IndicatorRelease(hRSI1);
   IndicatorRelease(hRSI5);
   IndicatorRelease(hBB);
   IndicatorRelease(hEMA9_M1);
   IndicatorRelease(hEMA21_M1);
   IndicatorRelease(hEMA9_M15);
   IndicatorRelease(hEMA21_M15);
   IndicatorRelease(hEMA9_H1);
   IndicatorRelease(hEMA21_H1);
   IndicatorRelease(hMACD);
   IndicatorRelease(hATR);
}

//==========================================================================
//  FUNCION PRINCIPAL
//==========================================================================
void OnTick()
{
   //--- Filtro horario (Viernes tarde / Lunes apertura)
   if(!IsTimeAllowed()) return;

   //--- Gestionar posiciones abiertas cada tick (salidas rapidas)
   ManagePositions();

   //--- Solo abrir trades en nueva vela (evitar multiples entradas)
   static datetime lastBarTime = 0;
   datetime currentBarTime = iTime(_Symbol, PERIOD_M1, 0);
   if(currentBarTime == lastBarTime) return;
   lastBarTime = currentBarTime;

   //--- Verificar limite de posiciones por balance
   if(CountPositions() >= GetMaxTrades()) return;

   //--- Leer todos los indicadores (shift=1 = vela cerrada confirmada)
   double rsi1     = GetVal(hRSI1,    0, 1);
   double rsi5     = GetVal(hRSI5,    0, 1);
   double bbMid    = GetVal(hBB,      0, 1); // Buffer 0 = linea media
   double bbUpper  = GetVal(hBB,      1, 1); // Buffer 1 = banda superior
   double bbLower  = GetVal(hBB,      2, 1); // Buffer 2 = banda inferior
   double ema9M1   = GetVal(hEMA9_M1, 0, 1);
   double ema21M1  = GetVal(hEMA21_M1,0, 1);
   double ema9M15  = GetVal(hEMA9_M15, 0, 1);
   double ema21M15 = GetVal(hEMA21_M15,0, 1);
   double ema9H1   = GetVal(hEMA9_H1,  0, 1);
   double ema21H1  = GetVal(hEMA21_H1, 0, 1);
   double macdMain = GetVal(hMACD,    0, 1); // Buffer 0 = MACD line
   double macdSig  = GetVal(hMACD,    1, 1); // Buffer 1 = Signal line
   double atr      = GetVal(hATR,     0, 1);

   //--- Validar que todos los valores son validos
   if(rsi1==EMPTY_VALUE    || rsi5==EMPTY_VALUE   || bbLower==EMPTY_VALUE ||
      ema9M1==EMPTY_VALUE  || ema21M1==EMPTY_VALUE||
      ema9M15==EMPTY_VALUE || ema21M15==EMPTY_VALUE ||
      ema9H1==EMPTY_VALUE  || ema21H1==EMPTY_VALUE  ||
      macdMain==EMPTY_VALUE|| atr==EMPTY_VALUE) return;

   //--- Filtro de mercado plano: ATR actual < promedio ATR(20)
   double atrAvg = GetATRAvg();
   if(atrAvg <= 0 || atr < atrAvg) return;

   double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double slDist = InpSL_ATR * atr;
   double tpDist = InpTP_ATR * atr;

   //--- CONDICIONES BUY
   bool buySignal = (rsi1 < InpRSI1_Buy)     // RSI1 sobrevendido
                 && (rsi5 > rsi1)             // RSI5 confirma alcista
                 && (ask  <= bbLower)         // Precio en/bajo banda inferior
                 && (ema9M1  > ema21M1)       // Tendencia alcista 1M
                 && (ema9M15 > ema21M15)      // Tendencia alcista 15M
                 && (ema9H1  > ema21H1)       // Tendencia alcista 1H
                 && (macdMain > macdSig);     // MACD confirma fuerza

   //--- CONDICIONES SELL
   bool sellSignal = (rsi1 > InpRSI1_Sell)   // RSI1 sobrecomprado
                  && (rsi5 < rsi1)            // RSI5 confirma bajista
                  && (bid  >= bbUpper)        // Precio en/sobre banda superior
                  && (ema9M1  < ema21M1)      // Tendencia bajista 1M
                  && (ema9M15 < ema21M15)     // Tendencia bajista 15M
                  && (ema9H1  < ema21H1)      // Tendencia bajista 1H
                  && (macdMain < macdSig);    // MACD confirma fuerza

   //--- EJECUCION DE ORDENES
   if(buySignal)
   {
      double sl = NormalizeDouble(ask - slDist, _Digits);
      double tp = NormalizeDouble(ask + tpDist, _Digits);

      if(trade.Buy(InpLotSize, _Symbol, ask, sl, tp, "MTF_BUY"))
         PrintFormat("BUY abierto | Precio=%.5f | SL=%.5f | TP=%.5f | RSI1=%.2f | ATR=%.5f",
                     ask, sl, tp, rsi1, atr);
      else
         PrintFormat("ERROR BUY: %d - %s", GetLastError(), trade.ResultComment());
   }
   else if(sellSignal)
   {
      double sl = NormalizeDouble(bid + slDist, _Digits);
      double tp = NormalizeDouble(bid - tpDist, _Digits);

      if(trade.Sell(InpLotSize, _Symbol, bid, sl, tp, "MTF_SELL"))
         PrintFormat("SELL abierto | Precio=%.5f | SL=%.5f | TP=%.5f | RSI1=%.2f | ATR=%.5f",
                     bid, sl, tp, rsi1, atr);
      else
         PrintFormat("ERROR SELL: %d - %s", GetLastError(), trade.ResultComment());
   }
}

//==========================================================================
//  GESTION DE POSICIONES ABIERTAS (salidas dinamicas + trailing)
//==========================================================================
void ManagePositions()
{
   double rsi1  = GetVal(hRSI1,     0, 1);
   double bbMid = GetVal(hBB,       0, 1);
   double ema21 = GetVal(hEMA21_M1, 0, 1);
   double atr   = GetVal(hATR,      0, 1);

   if(rsi1==EMPTY_VALUE || bbMid==EMPTY_VALUE || ema21==EMPTY_VALUE || atr<=0) return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;

      ENUM_POSITION_TYPE pType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double curSL  = PositionGetDouble(POSITION_SL);
      double curTP  = PositionGetDouble(POSITION_TP);
      double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double slDist = InpSL_ATR * atr;

      bool   shouldClose = false;
      double newSL       = curSL;

      if(pType == POSITION_TYPE_BUY)
      {
         //--- Salidas anticipadas BUY
         if(rsi1 >= InpRSI_TP) shouldClose = true;  // RSI cruza nivel TP
         if(bid  >= bbMid)     shouldClose = true;  // Precio cruza media BB
         if(bid  <  ema21)     shouldClose = true;  // Precio rompe EMA21

         //--- Trailing Stop BUY
         if(InpUseTrailing && !shouldClose)
         {
            double trailSL = NormalizeDouble(bid - slDist, _Digits);
            if(trailSL > curSL) newSL = trailSL;
         }
      }
      else // POSITION_TYPE_SELL
      {
         //--- Salidas anticipadas SELL
         if(rsi1 <= InpRSI_TP) shouldClose = true;  // RSI cruza nivel TP
         if(ask  <= bbMid)     shouldClose = true;  // Precio cruza media BB
         if(ask  >  ema21)     shouldClose = true;  // Precio rompe EMA21

         //--- Trailing Stop SELL
         if(InpUseTrailing && !shouldClose)
         {
            double trailSL = NormalizeDouble(ask + slDist, _Digits);
            if(curSL == 0 || trailSL < curSL) newSL = trailSL;
         }
      }

      if(shouldClose)
         trade.PositionClose(ticket);
      else if(newSL != curSL && newSL > 0)
         trade.PositionModify(ticket, newSL, curTP);
   }
}

//==========================================================================
//  FUNCIONES AUXILIARES
//==========================================================================

//--- Leer valor de buffer de indicador
double GetVal(int handle, int buffer, int shift = 1)
{
   double arr[];
   ArraySetAsSeries(arr, true);
   if(CopyBuffer(handle, buffer, shift, 1, arr) != 1) return EMPTY_VALUE;
   return arr[0];
}

//--- Promedio de ATR(14) en los ultimos N bars (filtro mercado plano)
double GetATRAvg()
{
   double arr[];
   ArraySetAsSeries(arr, true);
   int copied = CopyBuffer(hATR, 0, 1, InpATR_AvgBars, arr);
   if(copied < InpATR_AvgBars) return 0;
   double sum = 0;
   for(int i = 0; i < InpATR_AvgBars; i++) sum += arr[i];
   return sum / InpATR_AvgBars;
}

//--- Contar posiciones abiertas para este simbolo y magic
int CountPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         (int)PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
         count++;
   }
   return count;
}

//--- Max trades segun balance de cuenta
int GetMaxTrades()
{
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   if(bal <  30.0) return 1;
   if(bal <  60.0) return 2;
   if(bal < 120.0) return 3;
   return 4;
}

//--- Filtro horario: bloquear Viernes tarde y Lunes apertura
bool IsTimeAllowed()
{
   MqlDateTime t;
   TimeToStruct(TimeCurrent(), t);
   if(t.day_of_week == 5 && t.hour >= InpFridayStopHour)  return false; // Viernes
   if(t.day_of_week == 1 && t.hour <  InpMondayStartHour) return false; // Lunes
   return true;
}

//--- Detectar modo de relleno de ordenes compatible con el broker
ENUM_ORDER_TYPE_FILLING GetFillingMode()
{
   uint filling = (uint)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_FOK) != 0) return ORDER_FILLING_FOK;
   if((filling & SYMBOL_FILLING_IOC) != 0) return ORDER_FILLING_IOC;
   return ORDER_FILLING_RETURN;
}

//+------------------------------------------------------------------+
//  FIN DEL EA
//+------------------------------------------------------------------+
