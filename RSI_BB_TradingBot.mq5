//+------------------------------------------------------------------+
//|                     RSI_BB_TradingBot.mq5                        |
//|          Algorithmic Trading Bot - RSI + Bollinger Bands         |
//|                                                                  |
//|  Estrategia:                                                     |
//|  - BUY:  RSI <= 8.9  Y  precio <= BB Lower Band                 |
//|  - SELL: RSI >= 70   Y  precio >= BB Upper Band                 |
//|  - TAKE PROFIT: RSI cruza el nivel 50                           |
//+------------------------------------------------------------------+
#property copyright   "RSI BB TradingBot"
#property link        ""
#property version     "1.00"
#property description "Bot de trading usando RSI (Periodo 1) + Bollinger Bands (Periodo 14, Dev 0.111)"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//--- ================================================================
//    PARÁMETROS DE ENTRADA
//--- ================================================================

input group "=== CONFIGURACIÓN RSI ==="
input int    InpRSI_Period     = 1;      // RSI Período
input double InpRSI_BuyLevel  = 8.9;    // RSI Nivel de Compra
input double InpRSI_SellLevel = 70.0;   // RSI Nivel de Venta
input double InpRSI_TPLevel   = 50.0;   // RSI Nivel de Take Profit

input group "=== CONFIGURACIÓN BOLLINGER BANDS ==="
input int    InpBB_Period     = 14;      // BB Período
input double InpBB_Deviation  = 0.111;  // BB Desviación estándar
input int    InpBB_Shift      = 0;      // BB Desplazamiento

input group "=== CONFIGURACIÓN DE TRADING ==="
input double InpLotSize       = 0.10;   // Tamaño del lote
input int    InpMagicNumber   = 20250101; // Número mágico
input double InpStopLoss_Pips = 0.0;    // Stop Loss en pips (0 = sin SL)
input int    InpMaxBuyTrades  = 1;      // Máximo de operaciones BUY abiertas
input int    InpMaxSellTrades = 1;      // Máximo de operaciones SELL abiertas
input bool   InpUseNewBarOnly = true;   // Operar solo en nueva vela

input group "=== FILTROS BOLLINGER BANDS ==="
input bool   InpUseBBFilter   = true;   // Usar filtro de Bollinger Bands
input bool   InpAllowBothDirs = false;  // Permitir ambas direcciones simultáneamente

//--- ================================================================
//    VARIABLES GLOBALES
//--- ================================================================

CTrade         g_trade;
CPositionInfo  g_position;

int    g_rsi_handle  = INVALID_HANDLE;
int    g_bb_handle   = INVALID_HANDLE;

datetime g_last_bar_time = 0;

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Crear handle del RSI con PRICE_WEIGHTED (HLCC/4)
   g_rsi_handle = iRSI(_Symbol, _Period, InpRSI_Period, PRICE_WEIGHTED);
   if(g_rsi_handle == INVALID_HANDLE)
   {
      Print("ERROR: No se pudo crear el indicador RSI. Código: ", GetLastError());
      return INIT_FAILED;
   }

   //--- Crear handle de Bollinger Bands con PRICE_WEIGHTED (HLCC/4)
   g_bb_handle = iBands(_Symbol, _Period, InpBB_Period, InpBB_Shift, InpBB_Deviation, PRICE_WEIGHTED);
   if(g_bb_handle == INVALID_HANDLE)
   {
      Print("ERROR: No se pudo crear el indicador Bollinger Bands. Código: ", GetLastError());
      return INIT_FAILED;
   }

   //--- Configurar objeto de trading
   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(20);
   g_trade.SetTypeFilling(ORDER_FILLING_FOK);
   g_trade.LogLevel(LOG_LEVEL_ERRORS);

   Print("=== RSI + BB TradingBot inicializado correctamente ===");
   Print("RSI Período: ",    InpRSI_Period,   " | Buy: ", InpRSI_BuyLevel,
         " | Sell: ", InpRSI_SellLevel, " | TP: ", InpRSI_TPLevel);
   Print("BB Período: ",     InpBB_Period,    " | Desviación: ", InpBB_Deviation,
         " | Aplicado a: Weighted Close (HLCC/4)");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_rsi_handle != INVALID_HANDLE)
   {
      IndicatorRelease(g_rsi_handle);
      g_rsi_handle = INVALID_HANDLE;
   }
   if(g_bb_handle != INVALID_HANDLE)
   {
      IndicatorRelease(g_bb_handle);
      g_bb_handle = INVALID_HANDLE;
   }
   Print("RSI BB TradingBot detenido. Razón: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Verificar si hay una nueva vela (si el filtro está activo)
   if(InpUseNewBarOnly)
   {
      datetime current_bar = iTime(_Symbol, _Period, 0);
      if(current_bar == g_last_bar_time) return;
      g_last_bar_time = current_bar;
   }

   //--- Obtener valores del RSI
   double rsi_buf[];
   ArraySetAsSeries(rsi_buf, true);
   if(CopyBuffer(g_rsi_handle, 0, 0, 3, rsi_buf) < 3)
   {
      Print("ERROR: No se pudo copiar buffer RSI. Código: ", GetLastError());
      return;
   }

   //--- Obtener valores de Bollinger Bands
   //    Buffer 0 = Línea Media (Middle)
   //    Buffer 1 = Banda Superior (Upper)
   //    Buffer 2 = Banda Inferior (Lower)
   double bb_middle[], bb_upper[], bb_lower[];
   ArraySetAsSeries(bb_middle, true);
   ArraySetAsSeries(bb_upper,  true);
   ArraySetAsSeries(bb_lower,  true);

   if(CopyBuffer(g_bb_handle, 0, 0, 3, bb_middle) < 3 ||
      CopyBuffer(g_bb_handle, 1, 0, 3, bb_upper)  < 3 ||
      CopyBuffer(g_bb_handle, 2, 0, 3, bb_lower)  < 3)
   {
      Print("ERROR: No se pudo copiar buffer BB. Código: ", GetLastError());
      return;
   }

   //--- Valores actuales y anteriores del RSI
   double rsi_now  = rsi_buf[0];
   double rsi_prev = rsi_buf[1];

   //--- Valores actuales de las Bandas de Bollinger
   double bb_upper_now  = bb_upper[0];
   double bb_middle_now = bb_middle[0];
   double bb_lower_now  = bb_lower[0];

   //--- Precios actuales
   double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   //--- Contar posiciones abiertas
   int buys  = CountPositions(POSITION_TYPE_BUY);
   int sells = CountPositions(POSITION_TYPE_SELL);

   //=================================================================
   // TAKE PROFIT - Prioridad máxima - Se verifica en cada tick
   //=================================================================

   //--- TP para BUYs: RSI cruza el nivel 50 hacia arriba
   if(buys > 0)
   {
      if(rsi_prev < InpRSI_TPLevel && rsi_now >= InpRSI_TPLevel)
      {
         ClosePositionsByType(POSITION_TYPE_BUY);
         Print("TAKE PROFIT BUY ejecutado | RSI actual: ", DoubleToString(rsi_now, 2));
         buys = 0;
      }
   }

   //--- TP para SELLs: RSI cruza el nivel 50 hacia abajo
   if(sells > 0)
   {
      if(rsi_prev > InpRSI_TPLevel && rsi_now <= InpRSI_TPLevel)
      {
         ClosePositionsByType(POSITION_TYPE_SELL);
         Print("TAKE PROFIT SELL ejecutado | RSI actual: ", DoubleToString(rsi_now, 2));
         sells = 0;
      }
   }

   //=================================================================
   // SEÑAL DE COMPRA (BUY)
   // Condición: RSI <= Nivel de compra (8.9)
   //            + precio <= BB Banda inferior (si filtro activo)
   //=================================================================
   bool buy_signal = (rsi_now <= InpRSI_BuyLevel);

   if(InpUseBBFilter)
      buy_signal = buy_signal && (ask <= bb_lower_now);

   //--- No abrir SELL y BUY al mismo tiempo (si no se permite)
   if(!InpAllowBothDirs && sells > 0)
      buy_signal = false;

   if(buy_signal && buys < InpMaxBuyTrades)
   {
      double sl = 0.0;
      if(InpStopLoss_Pips > 0.0)
         sl = NormalizeDouble(ask - InpStopLoss_Pips * point * 10.0, _Digits);

      if(g_trade.Buy(InpLotSize, _Symbol, ask, sl, 0.0, "RSI_BB_BUY"))
      {
         Print("BUY abierto | Ask: ",      DoubleToString(ask, _Digits),
               " | RSI: ",                 DoubleToString(rsi_now, 2),
               " | BB Lower: ",            DoubleToString(bb_lower_now, _Digits),
               " | BB Middle: ",           DoubleToString(bb_middle_now, _Digits));
      }
      else
      {
         Print("ERROR abriendo BUY: ", g_trade.ResultRetcode(), " - ", g_trade.ResultRetcodeDescription());
      }
   }

   //=================================================================
   // SEÑAL DE VENTA (SELL)
   // Condición: RSI >= Nivel de venta (70)
   //            + precio >= BB Banda superior (si filtro activo)
   //=================================================================
   bool sell_signal = (rsi_now >= InpRSI_SellLevel);

   if(InpUseBBFilter)
      sell_signal = sell_signal && (bid >= bb_upper_now);

   //--- No abrir BUY y SELL al mismo tiempo (si no se permite)
   if(!InpAllowBothDirs && buys > 0)
      sell_signal = false;

   if(sell_signal && sells < InpMaxSellTrades)
   {
      double sl = 0.0;
      if(InpStopLoss_Pips > 0.0)
         sl = NormalizeDouble(bid + InpStopLoss_Pips * point * 10.0, _Digits);

      if(g_trade.Sell(InpLotSize, _Symbol, bid, sl, 0.0, "RSI_BB_SELL"))
      {
         Print("SELL abierto | Bid: ",     DoubleToString(bid, _Digits),
               " | RSI: ",                 DoubleToString(rsi_now, 2),
               " | BB Upper: ",            DoubleToString(bb_upper_now, _Digits),
               " | BB Middle: ",           DoubleToString(bb_middle_now, _Digits));
      }
      else
      {
         Print("ERROR abriendo SELL: ", g_trade.ResultRetcode(), " - ", g_trade.ResultRetcodeDescription());
      }
   }
}

//+------------------------------------------------------------------+
//| Contar posiciones abiertas por tipo                               |
//+------------------------------------------------------------------+
int CountPositions(ENUM_POSITION_TYPE pos_type)
{
   int count = 0;
   int total = PositionsTotal();

   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;

      if(PositionGetString(POSITION_SYMBOL)  == _Symbol &&
         (long)PositionGetInteger(POSITION_MAGIC) == (long)InpMagicNumber &&
         (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == pos_type)
      {
         count++;
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| Cerrar todas las posiciones de un tipo determinado               |
//+------------------------------------------------------------------+
void ClosePositionsByType(ENUM_POSITION_TYPE pos_type)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;

      if(PositionGetString(POSITION_SYMBOL)  == _Symbol &&
         (long)PositionGetInteger(POSITION_MAGIC) == (long)InpMagicNumber &&
         (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == pos_type)
      {
         if(!g_trade.PositionClose(ticket))
         {
            Print("ERROR cerrando posición #", ticket, ": ",
                  g_trade.ResultRetcode(), " - ", g_trade.ResultRetcodeDescription());
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Cerrar TODAS las posiciones del bot                              |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   ClosePositionsByType(POSITION_TYPE_BUY);
   ClosePositionsByType(POSITION_TYPE_SELL);
}
//+------------------------------------------------------------------+
