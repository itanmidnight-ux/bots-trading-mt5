//+------------------------------------------------------------------+
//|                                    SuperTrendMTF_Scalper.mq5    |
//|             Supertrend + EMA Multi-Timeframe Scalper EA          |
//|                              Version 2.0 — Produccion           |
//|                                                                  |
//|  INSTRUCCIONES:                                                  |
//|  - Adjuntar en grafico M5 (recomendado) o M1                    |
//|  - Funciona en multiples instrumentos simultaneamente            |
//|  - Un trade a la vez por instrumento (modo netting)              |
//|  - Usar en cuenta FBS con spreads bajos (preferir pares mayor)   |
//|                                                                  |
//|  ESTRATEGIA:                                                     |
//|  Entrada: Supertrend(10,2) + EMA9/21 en TF actual, 15M y 1H     |
//|  + RSI(14) momentum + Filtro de spread + Filtro ATR flat         |
//|  Salida: ATR x2 TP | ATR x1 SL | Trailing | Reversal ST         |
//+------------------------------------------------------------------+
#property copyright "SuperTrendMTF Scalper v2.0"
#property version   "2.00"
#property strict

#include <Trade\Trade.mqh>

//==========================================================================
//  PARAMETROS DE ENTRADA
//==========================================================================

input group "=== SUPERTREND (Señal Principal) ==="
input int    InpST_ATR_Period  = 10;    // Supertrend: Periodo ATR
input double InpST_Multiplier  = 2.0;  // Supertrend: Multiplicador

input group "=== EMA (Filtro de Tendencia) ==="
input int    InpEMA_Fast       = 9;    // EMA rapida
input int    InpEMA_Slow       = 21;   // EMA lenta

input group "=== RSI (Filtro de Momentum) ==="
input int    InpRSI_Period     = 14;   // RSI Periodo
input double InpRSI_BullMin    = 45.0; // RSI minimo para confirmar BUY
input double InpRSI_BearMax    = 55.0; // RSI maximo para confirmar SELL

input group "=== SL / TP DINAMICO (ATR) ==="
input int    InpATR_Period     = 14;   // ATR Periodo base
input double InpSL_ATR         = 1.0;  // Stop Loss = X * ATR
input double InpTP_ATR         = 2.0;  // Take Profit = X * ATR  (RR 1:2)
input bool   InpUseTrailing    = true; // Activar trailing stop ATR
input double InpTrailATR       = 1.2;  // Distancia trailing = X * ATR

input group "=== FILTROS DE CALIDAD ==="
input int    InpMaxSpread      = 25;   // Spread maximo permitido (puntos)
input int    InpATR_AvgBars    = 20;   // Barras para calcular ATR promedio
input double InpATR_MinRatio   = 0.85; // Ratio ATR actual/promedio (filtro flat)

input group "=== FILTRO HORARIO ==="
input int    InpFridayStop     = 20;   // Viernes: cerrar nuevas entradas desde hora
input int    InpMondayStart    = 2;    // Lunes: abrir operaciones desde hora

input group "=== CONFIGURACION EA ==="
input double InpLotSize        = 0.01; // Tamano de lote fijo
input int    InpMagicNumber    = 88888;// Magic Number (diferente por simbolo)
input int    InpSlippage       = 10;   // Slippage maximo (puntos)

//==========================================================================
//  VARIABLES GLOBALES
//==========================================================================
CTrade trade;

// Handles de indicadores
int hEMA9_TF,  hEMA21_TF;   // EMA en TF del grafico
int hEMA9_M15, hEMA21_M15;  // EMA en 15M
int hEMA9_H1,  hEMA21_H1;   // EMA en 1H
int hRSI;                    // RSI(14)
int hATR_ST;                 // ATR para Supertrend
int hATR;                    // ATR para SL/TP

//==========================================================================
//  INICIALIZACION
//==========================================================================
int OnInit()
{
   // Advertencia de timeframe
   if(_Period != PERIOD_M5 && _Period != PERIOD_M1 && _Period != PERIOD_M15)
      Alert("ADVERTENCIA: EA optimizado para M5. Timeframe actual: ", EnumToString(_Period));

   // EMAs en el timeframe del grafico
   hEMA9_TF   = iMA(_Symbol, _Period, InpEMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
   hEMA21_TF  = iMA(_Symbol, _Period, InpEMA_Slow, 0, MODE_EMA, PRICE_CLOSE);

   // EMAs MTF confirmacion
   hEMA9_M15  = iMA(_Symbol, PERIOD_M15, InpEMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
   hEMA21_M15 = iMA(_Symbol, PERIOD_M15, InpEMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
   hEMA9_H1   = iMA(_Symbol, PERIOD_H1,  InpEMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
   hEMA21_H1  = iMA(_Symbol, PERIOD_H1,  InpEMA_Slow, 0, MODE_EMA, PRICE_CLOSE);

   // RSI
   hRSI    = iRSI(_Symbol, _Period, InpRSI_Period, PRICE_CLOSE);

   // ATR para calculo interno del Supertrend
   hATR_ST = iATR(_Symbol, _Period, InpST_ATR_Period);

   // ATR para SL/TP
   hATR    = iATR(_Symbol, _Period, InpATR_Period);

   // Validar todos los handles
   if(hEMA9_TF  == INVALID_HANDLE || hEMA21_TF  == INVALID_HANDLE ||
      hEMA9_M15 == INVALID_HANDLE || hEMA21_M15 == INVALID_HANDLE ||
      hEMA9_H1  == INVALID_HANDLE || hEMA21_H1  == INVALID_HANDLE ||
      hRSI      == INVALID_HANDLE || hATR_ST    == INVALID_HANDLE ||
      hATR      == INVALID_HANDLE)
   {
      Alert("ERROR CRITICO: Fallo al crear indicadores en ", _Symbol,
            ". Verificar que el simbolo este disponible.");
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippage);
   trade.SetTypeFilling(GetFillingMode());

   PrintFormat("SuperTrendMTF Scalper v2.0 | Simbolo: %s | TF: %s | Magic: %d | Lote: %.2f",
               _Symbol, EnumToString(_Period), InpMagicNumber, InpLotSize);
   return INIT_SUCCEEDED;
}

//==========================================================================
//  LIBERACION
//==========================================================================
void OnDeinit(const int reason)
{
   IndicatorRelease(hEMA9_TF);  IndicatorRelease(hEMA21_TF);
   IndicatorRelease(hEMA9_M15); IndicatorRelease(hEMA21_M15);
   IndicatorRelease(hEMA9_H1);  IndicatorRelease(hEMA21_H1);
   IndicatorRelease(hRSI);
   IndicatorRelease(hATR_ST);
   IndicatorRelease(hATR);
}

//==========================================================================
//  CALCULO NATIVO DE SUPERTREND
//  No requiere indicador externo. 100% autocontenido.
//  Retorna: 1=alcista, -1=bajista, 0=error
//  flipSignal: true si la direccion cambio en la ultima vela cerrada
//==========================================================================
int CalcSupertrend(bool &flipSignal)
{
   flipSignal  = false;
   const int BARS = 200; // Barras suficientes para inicializar correctamente

   // Arrays cronologicos: index 0 = mas antiguo, index BARS-1 = vela actual (incompleta)
   double H[], L[], C[], ATR_buf[];
   ArraySetAsSeries(H,       false);
   ArraySetAsSeries(L,       false);
   ArraySetAsSeries(C,       false);
   ArraySetAsSeries(ATR_buf, false);

   if(CopyHigh  (_Symbol, _Period, 0, BARS, H)       < BARS) return 0;
   if(CopyLow   (_Symbol, _Period, 0, BARS, L)       < BARS) return 0;
   if(CopyClose (_Symbol, _Period, 0, BARS, C)       < BARS) return 0;
   if(CopyBuffer(hATR_ST, 0,       0, BARS, ATR_buf) < BARS) return 0;

   // Buffers de calculo
   double upperBand[200], lowerBand[200], superT[200];
   ArrayInitialize(upperBand, 0);
   ArrayInitialize(lowerBand, 0);
   ArrayInitialize(superT,    0);

   // Semilla inicial en el primer bar valido
   int seed = InpST_ATR_Period + 2;
   if(seed >= BARS - 2) return 0;

   double hl2_seed   = (H[seed] + L[seed]) / 2.0;
   upperBand[seed]   = hl2_seed + InpST_Multiplier * ATR_buf[seed];
   lowerBand[seed]   = hl2_seed - InpST_Multiplier * ATR_buf[seed];
   superT[seed]      = (C[seed] > hl2_seed) ? lowerBand[seed] : upperBand[seed];

   // Calcular Supertrend bar a bar (cronologico)
   // Nos detenemos en BARS-2 para no incluir la vela actual incompleta
   for(int i = seed + 1; i <= BARS - 2; i++)
   {
      double hl2 = (H[i] + L[i]) / 2.0;
      double atr = ATR_buf[i];

      // Bandas brutas
      double rawUp  = hl2 + InpST_Multiplier * atr;
      double rawDn  = hl2 - InpST_Multiplier * atr;

      // Banda superior: solo baja si precio anterior rompió por encima
      upperBand[i] = (rawUp < upperBand[i-1] || C[i-1] > upperBand[i-1])
                     ? rawUp : upperBand[i-1];

      // Banda inferior: solo sube si precio anterior rompió por debajo
      lowerBand[i] = (rawDn > lowerBand[i-1] || C[i-1] < lowerBand[i-1])
                     ? rawDn : lowerBand[i-1];

      // Direccion: si la vela cierra debajo de la banda activa → cambia
      bool prevBearish = (superT[i-1] == upperBand[i-1]);

      if(prevBearish)
         superT[i] = (C[i] > upperBand[i]) ? lowerBand[i] : upperBand[i]; // Posible flip a alcista
      else
         superT[i] = (C[i] < lowerBand[i]) ? upperBand[i] : lowerBand[i]; // Posible flip a bajista
   }

   // Leer resultados en vela cerrada (BARS-2) y anterior (BARS-3)
   int cur  = BARS - 2;
   int prev = BARS - 3;

   if(cur < seed + 1 || prev < seed) return 0;

   bool curBull  = (superT[cur]  == lowerBand[cur]);
   bool prevBull = (superT[prev] == lowerBand[prev]);

   // Detectar cambio de direccion (flip = señal mas fuerte)
   if(curBull != prevBull) flipSignal = true;

   return curBull ? 1 : -1;
}

//==========================================================================
//  FUNCIONES AUXILIARES
//==========================================================================

// Leer un valor de buffer de indicador (shift=1 = ultima vela cerrada)
double GetVal(int handle, int buffer, int shift = 1)
{
   double arr[];
   ArraySetAsSeries(arr, true);
   if(CopyBuffer(handle, buffer, shift, 1, arr) != 1) return EMPTY_VALUE;
   return arr[0];
}

// Calcular promedio del ATR sobre N barras cerradas (filtro mercado plano)
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

// Verificar si hay una posicion abierta para este simbolo y magic
bool HasPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         (int)PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
         return true;
   }
   return false;
}

// Obtener ticket de la posicion activa
ulong GetTicket()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         (int)PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
         return t;
   }
   return 0;
}

// Filtro horario: bloquear Viernes tarde y Lunes apertura
bool IsTimeAllowed()
{
   MqlDateTime t;
   TimeToStruct(TimeCurrent(), t);
   if(t.day_of_week == 5 && t.hour >= InpFridayStop)  return false;
   if(t.day_of_week == 1 && t.hour < InpMondayStart)  return false;
   return true;
}

// Detectar el modo de relleno de ordenes del broker (compatibilidad FBS)
ENUM_ORDER_TYPE_FILLING GetFillingMode()
{
   uint filling = (uint)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_FOK) != 0) return ORDER_FILLING_FOK;
   if((filling & SYMBOL_FILLING_IOC) != 0) return ORDER_FILLING_IOC;
   return ORDER_FILLING_RETURN;
}

// Verificar SL minimo del broker y ajustar si es necesario
double ValidateSL(double price, double sl, ENUM_ORDER_TYPE type)
{
   double minStop = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   double minDist = MathMax(minStop, 5.0 * _Point); // Al menos 5 puntos de distancia

   if(type == ORDER_TYPE_BUY  && (price - sl) < minDist)
      sl = NormalizeDouble(price - minDist * 1.5, _Digits);
   if(type == ORDER_TYPE_SELL && (sl - price) < minDist)
      sl = NormalizeDouble(price + minDist * 1.5, _Digits);

   return sl;
}

double ValidateTP(double price, double tp, ENUM_ORDER_TYPE type)
{
   double minStop = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   double minDist = MathMax(minStop, 5.0 * _Point);

   if(type == ORDER_TYPE_BUY  && (tp - price) < minDist)
      tp = NormalizeDouble(price + minDist * 1.5, _Digits);
   if(type == ORDER_TYPE_SELL && (price - tp) < minDist)
      tp = NormalizeDouble(price - minDist * 1.5, _Digits);

   return tp;
}

//==========================================================================
//  GESTION DE POSICION ABIERTA (cada tick)
//  1. Cierre si Supertrend revierte (proteccion)
//  2. Trailing Stop basado en ATR
//==========================================================================
void ManagePosition()
{
   ulong ticket = GetTicket();
   if(ticket == 0) return;
   if(!PositionSelectByTicket(ticket)) return;

   ENUM_POSITION_TYPE pType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double curSL    = PositionGetDouble(POSITION_SL);
   double curTP    = PositionGetDouble(POSITION_TP);
   double openPx   = PositionGetDouble(POSITION_PRICE_OPEN);
   double bid      = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask      = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double atr      = GetVal(hATR, 0, 0); // Valor ATR del tick actual
   if(atr == EMPTY_VALUE || atr <= 0) return;

   // --- Verificar reversal de Supertrend ---
   bool flipSignal;
   int stDir = CalcSupertrend(flipSignal);
   if(stDir != 0 && flipSignal)
   {
      if((pType == POSITION_TYPE_BUY  && stDir == -1) ||
         (pType == POSITION_TYPE_SELL && stDir ==  1))
      {
         trade.PositionClose(ticket);
         PrintFormat("[CIERRE ST REVERSAL] %s | Dir: %s | Ticket: %I64u",
                     _Symbol, (stDir==1?"BULL":"BEAR"), ticket);
         return;
      }
   }

   // --- Trailing Stop ATR ---
   if(!InpUseTrailing) return;

   double trailDist = InpTrailATR * atr;
   double newSL     = curSL;
   bool   modify    = false;

   if(pType == POSITION_TYPE_BUY)
   {
      // Mover SL hacia arriba solo si estamos en ganancia
      if(bid > openPx)
      {
         double trail = NormalizeDouble(bid - trailDist, _Digits);
         if(trail > curSL + _Point)
         {
            newSL  = trail;
            modify = true;
         }
      }
   }
   else // SELL
   {
      // Mover SL hacia abajo solo si estamos en ganancia
      if(ask < openPx)
      {
         double trail = NormalizeDouble(ask + trailDist, _Digits);
         if(curSL == 0 || trail < curSL - _Point)
         {
            newSL  = trail;
            modify = true;
         }
      }
   }

   if(modify) trade.PositionModify(ticket, newSL, curTP);
}

//==========================================================================
//  TICK PRINCIPAL
//==========================================================================
void OnTick()
{
   // 1. Filtro horario siempre activo
   if(!IsTimeAllowed()) return;

   // 2. Gestionar posicion existente cada tick (proteccion activa)
   ManagePosition();

   // 3. Nuevas entradas: solo en nueva vela cerrada
   static datetime lastBar = 0;
   datetime currBar = iTime(_Symbol, _Period, 0);
   if(currBar == lastBar) return;
   lastBar = currBar;

   // 4. No abrir si ya hay posicion (un trade a la vez)
   if(HasPosition()) return;

   // 5. Filtro de spread: evitar spreads altos (noticias, aperturas)
   double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double spread = (ask - bid) / _Point;
   if(spread > InpMaxSpread)
   {
      // Registrar pero no alertar en cada tick (solo en nueva vela)
      PrintFormat("SPREAD ALTO: %.1f pts | Max: %d pts | Omitiendo entrada.", spread, InpMaxSpread);
      return;
   }

   // 6. Filtro mercado plano: ATR actual vs promedio
   double atr    = GetVal(hATR, 0, 1);
   double atrAvg = GetATRAvg();
   if(atr == EMPTY_VALUE || atrAvg <= 0) return;
   if(atr < atrAvg * InpATR_MinRatio) return; // Mercado lateral, no operar

   // 7. Leer indicadores en vela cerrada (shift=1)
   double ema9_tf   = GetVal(hEMA9_TF,   0, 1);
   double ema21_tf  = GetVal(hEMA21_TF,  0, 1);
   double ema9_m15  = GetVal(hEMA9_M15,  0, 1);
   double ema21_m15 = GetVal(hEMA21_M15, 0, 1);
   double ema9_h1   = GetVal(hEMA9_H1,   0, 1);
   double ema21_h1  = GetVal(hEMA21_H1,  0, 1);
   double rsi       = GetVal(hRSI,       0, 1);

   // Validar valores
   if(ema9_tf   == EMPTY_VALUE || ema21_tf   == EMPTY_VALUE) return;
   if(ema9_m15  == EMPTY_VALUE || ema21_m15  == EMPTY_VALUE) return;
   if(ema9_h1   == EMPTY_VALUE || ema21_h1   == EMPTY_VALUE) return;
   if(rsi       == EMPTY_VALUE) return;

   // 8. Supertrend: señal principal + deteccion de flip
   bool flipSignal;
   int stDir = CalcSupertrend(flipSignal);
   if(stDir == 0) return; // Error en calculo

   // 9. Calcular SL y TP
   double slDist = InpSL_ATR * atr;
   double tpDist = InpTP_ATR * atr;

   //=======================================================================
   //  CONDICIONES DE ENTRADA — BUY
   //  Supertrend bullish + EMA alcistas en 3 TFs + RSI momentum
   //=======================================================================
   bool buyOK = (stDir ==  1)            // Supertrend direccion alcista
             && (ema9_tf  > ema21_tf)    // Tendencia alcista en TF base
             && (ema9_m15 > ema21_m15)   // Tendencia alcista en 15M
             && (ema9_h1  > ema21_h1)    // Tendencia alcista en 1H
             && (rsi > InpRSI_BullMin);  // Momentum alcista confirmado

   //=======================================================================
   //  CONDICIONES DE ENTRADA — SELL
   //  Supertrend bearish + EMA bajistas en 3 TFs + RSI momentum
   //=======================================================================
   bool sellOK = (stDir == -1)           // Supertrend direccion bajista
              && (ema9_tf  < ema21_tf)   // Tendencia bajista en TF base
              && (ema9_m15 < ema21_m15)  // Tendencia bajista en 15M
              && (ema9_h1  < ema21_h1)   // Tendencia bajista en 1H
              && (rsi < InpRSI_BearMax); // Momentum bajista confirmado

   //=======================================================================
   //  EJECUCION
   //=======================================================================
   if(buyOK)
   {
      double sl = NormalizeDouble(ask - slDist, _Digits);
      double tp = NormalizeDouble(ask + tpDist, _Digits);
      sl = ValidateSL(ask, sl, ORDER_TYPE_BUY);
      tp = ValidateTP(ask, tp, ORDER_TYPE_BUY);

      if(trade.Buy(InpLotSize, _Symbol, ask, sl, tp, "ST_BUY"))
         PrintFormat("[BUY ABIERTO] %s | Ask=%.5f | SL=%.5f | TP=%.5f | ATR=%.5f | Flip=%s | RSI=%.1f",
                     _Symbol, ask, sl, tp, atr, flipSignal?"SI":"NO", rsi);
      else
         PrintFormat("[ERROR BUY] Codigo=%d | %s", GetLastError(), trade.ResultComment());
   }
   else if(sellOK)
   {
      double sl = NormalizeDouble(bid + slDist, _Digits);
      double tp = NormalizeDouble(bid - tpDist, _Digits);
      sl = ValidateSL(bid, sl, ORDER_TYPE_SELL);
      tp = ValidateTP(bid, tp, ORDER_TYPE_SELL);

      if(trade.Sell(InpLotSize, _Symbol, bid, sl, tp, "ST_SELL"))
         PrintFormat("[SELL ABIERTO] %s | Bid=%.5f | SL=%.5f | TP=%.5f | ATR=%.5f | Flip=%s | RSI=%.1f",
                     _Symbol, bid, sl, tp, atr, flipSignal?"SI":"NO", rsi);
      else
         PrintFormat("[ERROR SELL] Codigo=%d | %s", GetLastError(), trade.ResultComment());
   }
}
//+------------------------------------------------------------------+
//  FIN DEL EA — SuperTrendMTF_Scalper v2.0
//+------------------------------------------------------------------+
