//+------------------------------------------------------------------+
//|               RSI_BB_TradingBot_v2.mq5                           |
//|       Bot de Trading Algorítmico Profesional — MT5 v2.0          |
//|                                                                  |
//|  ESTRATEGIA:                                                     |
//|  · ENTRADA BUY  → RSI(1,HLCC/4) ≤ 8.9                          |
//|  · ENTRADA SELL → RSI(1,HLCC/4) ≥ 70                            |
//|  · BB(14, 0.111, HLCC/4) como filtro de dirección               |
//|                                                                  |
//|  TAKE PROFIT MULTICAPA (revisado en cada tick):                  |
//|  · Capa 1 — RSI cruza nivel 50 (regla primaria)                 |
//|  · Capa 2 — Precio alcanza BB Middle Line (objetivo de precio)   |
//|  · Capa 3 — Trailing Stop activo (captura máximos de ganancia)   |
//|  · Capa 4 — TP fijo en pips (red de seguridad)                  |
//+------------------------------------------------------------------+
#property copyright "RSI BB TradingBot v2.0"
#property link      ""
#property version   "2.00"
#property description "RSI(1) + BB(14,0.111) | TP: RSI-50 + BB-Middle + Trailing"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//==================================================================
//  PARÁMETROS DE ENTRADA
//==================================================================

input group "══════ RSI (Período 1, HLCC/4) ══════"
input int    InpRSI_Period     = 1;         // RSI: Período
input double InpRSI_BuyLevel  = 8.9;       // RSI: Nivel BUY  (≤ este valor = señal)
input double InpRSI_SellLevel = 70.0;      // RSI: Nivel SELL (≥ este valor = señal)
input double InpRSI_TPLevel   = 50.0;      // RSI: Nivel Take Profit

input group "══════ BOLLINGER BANDS (14, 0.111, HLCC/4) ══════"
input int    InpBB_Period     = 14;         // BB: Período
input double InpBB_Deviation  = 0.111;     // BB: Desviación estándar
input int    InpBB_Shift      = 0;         // BB: Desplazamiento

input group "══════ GESTIÓN DE LOTES ══════"
input double InpLotSize       = 0.10;      // Tamaño del lote
input long   InpMagicNumber   = 20250601;  // Magic Number (identificador único del bot)
input int    InpMaxBuys       = 1;         // Máximo BUYs abiertos simultáneos
input int    InpMaxSells      = 1;         // Máximo SELLs abiertos simultáneos

input group "══════ STOP LOSS ══════"
input double InpSL_Pips       = 0.0;       // Stop Loss en pips (0 = sin SL — libertad al mercado)

input group "══════ TAKE PROFIT FIJO (Red de Seguridad) ══════"
input double InpFixedTP_Pips  = 25.0;      // TP fijo en pips (0 = desactivado)

input group "══════ TRAILING STOP (Captura Ganancias) ══════"
input bool   InpUseTrailing   = true;      // Activar Trailing Stop
input double InpTrailStart    = 7.0;       // Trailing: activar al ganar X pips
input double InpTrailGap      = 4.0;       // Trailing: distancia al precio en pips

input group "══════ FILTROS DE ENTRADA ══════"
input bool   InpBBDirFilter   = true;      // Filtro: precio debe estar del lado correcto de BB Middle
input bool   InpNewBarEntry   = true;      // Solo buscar entradas en nueva vela
input bool   InpAllowBothSides = false;    // Permitir BUY y SELL al mismo tiempo

//==================================================================
//  VARIABLES GLOBALES
//==================================================================

CTrade       g_trade;
CSymbolInfo  g_sym;

int      g_rsi_h    = INVALID_HANDLE;
int      g_bb_h     = INVALID_HANDLE;
datetime g_last_bar = 0;
double   g_pip      = 0.0;   // 1 pip en precio del símbolo

//==================================================================
//  INICIALIZACIÓN
//==================================================================
int OnInit()
{
   //--- Verificar símbolo
   if(!g_sym.Name(_Symbol))
   {
      Print("ERROR: No se pudo inicializar el símbolo ", _Symbol);
      return INIT_FAILED;
   }
   g_sym.RefreshRates();

   //--- Calcular valor de 1 pip según dígitos del símbolo
   int digits = (int)g_sym.Digits();
   g_pip = (digits == 5 || digits == 3) ? g_sym.Point() * 10.0 : g_sym.Point();

   //--- Handle RSI: período 1, aplicado a Weighted Close (HLCC/4)
   g_rsi_h = iRSI(_Symbol, _Period, InpRSI_Period, PRICE_WEIGHTED);
   if(g_rsi_h == INVALID_HANDLE)
   {
      Print("ERROR: No se creó el handle RSI | Código: ", GetLastError());
      return INIT_FAILED;
   }

   //--- Handle Bollinger Bands: período 14, desv 0.111, HLCC/4
   //    Buffer 0 = Middle (base line)
   //    Buffer 1 = Upper Band
   //    Buffer 2 = Lower Band
   g_bb_h = iBands(_Symbol, _Period, InpBB_Period, InpBB_Shift, InpBB_Deviation, PRICE_WEIGHTED);
   if(g_bb_h == INVALID_HANDLE)
   {
      Print("ERROR: No se creó el handle Bollinger Bands | Código: ", GetLastError());
      return INIT_FAILED;
   }

   //--- Configurar objeto de trading
   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(20);
   g_trade.SetTypeFilling(GetOptimalFilling());
   g_trade.LogLevel(LOG_LEVEL_ERRORS);

   //--- Log de inicio
   Print("╔══════════════════════════════════════════╗");
   Print("║  RSI BB TradingBot v2.0 — INICIADO       ║");
   Print("╚══════════════════════════════════════════╝");
   Print("Símbolo: ", _Symbol, " | Timeframe: ", EnumToString(_Period));
   Print("RSI(", InpRSI_Period, ") | Buy≤", InpRSI_BuyLevel,
         " | Sell≥", InpRSI_SellLevel, " | TP@", InpRSI_TPLevel);
   Print("BB(", InpBB_Period, ", dev=", InpBB_Deviation, ") | Aplicado a HLCC/4");
   Print("Pip = ", DoubleToString(g_pip, digits));
   Print("Filling mode: ", EnumToString(GetOptimalFilling()));

   return INIT_SUCCEEDED;
}

//==================================================================
//  DESINICIALIZACIÓN
//==================================================================
void OnDeinit(const int reason)
{
   if(g_rsi_h != INVALID_HANDLE) { IndicatorRelease(g_rsi_h); g_rsi_h = INVALID_HANDLE; }
   if(g_bb_h  != INVALID_HANDLE) { IndicatorRelease(g_bb_h);  g_bb_h  = INVALID_HANDLE; }
   Print("RSI BB TradingBot detenido | Razón: ", reason);
}

//==================================================================
//  TICK PRINCIPAL
//==================================================================
void OnTick()
{
   //--- Refrescar precios del símbolo
   if(!g_sym.RefreshRates()) return;

   //--- ─────────────────────────────────────────────────────────
   //    PASO 1: Leer indicadores
   //    ─────────────────────────────────────────────────────────
   double rsi_buf[], bb_mid[], bb_up[], bb_dn[];
   ArraySetAsSeries(rsi_buf, true);
   ArraySetAsSeries(bb_mid,  true);
   ArraySetAsSeries(bb_up,   true);
   ArraySetAsSeries(bb_dn,   true);

   if(CopyBuffer(g_rsi_h, 0, 0, 3, rsi_buf) < 3) return;
   if(CopyBuffer(g_bb_h,  0, 0, 3, bb_mid)  < 3) return;
   if(CopyBuffer(g_bb_h,  1, 0, 3, bb_up)   < 3) return;
   if(CopyBuffer(g_bb_h,  2, 0, 3, bb_dn)   < 3) return;

   double rsi_now  = rsi_buf[0];   // RSI barra actual
   double rsi_prev = rsi_buf[1];   // RSI barra anterior

   double mid_now = bb_mid[0];     // BB Middle Line actual
   double ask     = g_sym.Ask();
   double bid     = g_sym.Bid();

   //--- ─────────────────────────────────────────────────────────
   //    PASO 2: GESTIÓN DE POSICIONES ABIERTAS (cada tick)
   //    ¡PRIORIDAD MÁXIMA — antes de cualquier filtro de entrada!
   //    ─────────────────────────────────────────────────────────

   //--- 2a. Trailing Stop (captura ganancias en desarrollo)
   if(InpUseTrailing)
      ExecuteTrailingStop(ask, bid);

   //--- 2b. Take Profit para BUYs abiertos
   if(CountPositions(POSITION_TYPE_BUY) > 0)
   {
      // Capa 1: RSI cruza nivel 50 hacia arriba (señal primaria de la estrategia)
      bool tp_rsi = (rsi_prev < InpRSI_TPLevel && rsi_now >= InpRSI_TPLevel);

      // Capa 2: Precio bid alcanza o supera la BB Middle Line
      bool tp_bb  = (bid >= mid_now);

      if(tp_rsi || tp_bb)
      {
         string reason = tp_rsi
                         ? StringFormat("RSI cruzo 50 (prev=%.1f, now=%.1f)", rsi_prev, rsi_now)
                         : StringFormat("Precio alcanzo BB Middle (bid=%.5f, mid=%.5f)", bid, mid_now);
         CloseByType(POSITION_TYPE_BUY, reason);
      }
   }

   //--- 2c. Take Profit para SELLs abiertos
   if(CountPositions(POSITION_TYPE_SELL) > 0)
   {
      // Capa 1: RSI cruza nivel 50 hacia abajo (señal primaria de la estrategia)
      bool tp_rsi = (rsi_prev > InpRSI_TPLevel && rsi_now <= InpRSI_TPLevel);

      // Capa 2: Precio ask alcanza o cae bajo la BB Middle Line
      bool tp_bb  = (ask <= mid_now);

      if(tp_rsi || tp_bb)
      {
         string reason = tp_rsi
                         ? StringFormat("RSI cruzo 50 (prev=%.1f, now=%.1f)", rsi_prev, rsi_now)
                         : StringFormat("Precio alcanzo BB Middle (ask=%.5f, mid=%.5f)", ask, mid_now);
         CloseByType(POSITION_TYPE_SELL, reason);
      }
   }

   //--- ─────────────────────────────────────────────────────────
   //    PASO 3: Control de entrada — nueva vela (si aplica)
   //    ─────────────────────────────────────────────────────────
   if(InpNewBarEntry)
   {
      datetime bar_time = iTime(_Symbol, _Period, 0);
      if(bar_time == g_last_bar) return;
      g_last_bar = bar_time;
   }

   //--- ─────────────────────────────────────────────────────────
   //    PASO 4: SEÑALES DE ENTRADA
   //    ─────────────────────────────────────────────────────────
   int n_buys  = CountPositions(POSITION_TYPE_BUY);
   int n_sells = CountPositions(POSITION_TYPE_SELL);

   //===== SEÑAL BUY =====
   // Condición principal: RSI ≤ nivel de compra (8.9)
   // Condición BB (opcional): precio por debajo de BB Middle (espacio para subir)
   bool buy_sig = (rsi_now <= InpRSI_BuyLevel);
   if(InpBBDirFilter)
      buy_sig = buy_sig && (ask < mid_now);
   if(!InpAllowBothSides && n_sells > 0)
      buy_sig = false;

   if(buy_sig && n_buys < InpMaxBuys)
   {
      double sl = CalcSL(POSITION_TYPE_BUY, ask);
      double tp = CalcTP(POSITION_TYPE_BUY, ask);

      if(g_trade.Buy(InpLotSize, _Symbol, ask, sl, tp, "RSI_BB_BUY"))
      {
         Print("▲ BUY ABIERTO",
               " | Ask=",     DoubleToString(ask,    _Digits),
               " | RSI=",     DoubleToString(rsi_now, 2),
               " | BBmid=",   DoubleToString(mid_now, _Digits),
               " | SL=",      DoubleToString(sl,      _Digits),
               " | TP_fijo=", DoubleToString(tp,      _Digits));
      }
      else
         Print("ERROR BUY: [", g_trade.ResultRetcode(), "] ",
               g_trade.ResultRetcodeDescription());
   }

   //===== SEÑAL SELL =====
   // Condición principal: RSI ≥ nivel de venta (70)
   // Condición BB (opcional): precio por encima de BB Middle (espacio para bajar)
   bool sell_sig = (rsi_now >= InpRSI_SellLevel);
   if(InpBBDirFilter)
      sell_sig = sell_sig && (bid > mid_now);
   if(!InpAllowBothSides && n_buys > 0)
      sell_sig = false;

   if(sell_sig && n_sells < InpMaxSells)
   {
      double sl = CalcSL(POSITION_TYPE_SELL, bid);
      double tp = CalcTP(POSITION_TYPE_SELL, bid);

      if(g_trade.Sell(InpLotSize, _Symbol, bid, sl, tp, "RSI_BB_SELL"))
      {
         Print("▼ SELL ABIERTO",
               " | Bid=",     DoubleToString(bid,    _Digits),
               " | RSI=",     DoubleToString(rsi_now, 2),
               " | BBmid=",   DoubleToString(mid_now, _Digits),
               " | SL=",      DoubleToString(sl,      _Digits),
               " | TP_fijo=", DoubleToString(tp,      _Digits));
      }
      else
         Print("ERROR SELL: [", g_trade.ResultRetcode(), "] ",
               g_trade.ResultRetcodeDescription());
   }
}

//==================================================================
//  TRAILING STOP — ejecutado en cada tick
//  Activa cuando la posición gana InpTrailStart pips,
//  y mantiene el SL a InpTrailGap pips del precio actual.
//==================================================================
void ExecuteTrailingStop(const double ask, const double bid)
{
   double activate_dist = InpTrailStart * g_pip;
   double trail_dist    = InpTrailGap   * g_pip;

   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL)  != _Symbol)        continue;
      if(PositionGetInteger(POSITION_MAGIC)  != InpMagicNumber) continue;

      ENUM_POSITION_TYPE ptype  = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double open_price         = PositionGetDouble(POSITION_PRICE_OPEN);
      double current_sl         = PositionGetDouble(POSITION_SL);
      double current_tp         = PositionGetDouble(POSITION_TP);

      if(ptype == POSITION_TYPE_BUY)
      {
         double profit_dist = bid - open_price;
         if(profit_dist >= activate_dist)
         {
            double new_sl = NormalizeDouble(bid - trail_dist, _Digits);
            // Solo mover el SL si sube (nunca bajar el SL de un BUY)
            if(new_sl > current_sl + g_sym.Point())
            {
               if(g_trade.PositionModify(ticket, new_sl, current_tp))
                  Print("⟳ TRAIL BUY #", ticket,
                        " | Nuevo SL=", DoubleToString(new_sl, _Digits),
                        " | Profit=",   DoubleToString(profit_dist / g_pip, 1), " pips");
            }
         }
      }
      else if(ptype == POSITION_TYPE_SELL)
      {
         double profit_dist = open_price - ask;
         if(profit_dist >= activate_dist)
         {
            double new_sl = NormalizeDouble(ask + trail_dist, _Digits);
            // Solo mover el SL si baja (nunca subir el SL de un SELL)
            if(current_sl < g_sym.Point() || new_sl < current_sl - g_sym.Point())
            {
               if(g_trade.PositionModify(ticket, new_sl, current_tp))
                  Print("⟳ TRAIL SELL #", ticket,
                        " | Nuevo SL=", DoubleToString(new_sl, _Digits),
                        " | Profit=",   DoubleToString(profit_dist / g_pip, 1), " pips");
            }
         }
      }
   }
}

//==================================================================
//  Calcular Stop Loss según configuración
//==================================================================
double CalcSL(const ENUM_POSITION_TYPE ptype, const double entry_price)
{
   if(InpSL_Pips <= 0.0) return 0.0;

   double sl_dist = InpSL_Pips * g_pip;
   double sl      = (ptype == POSITION_TYPE_BUY)
                    ? entry_price - sl_dist
                    : entry_price + sl_dist;
   return NormalizeDouble(sl, _Digits);
}

//==================================================================
//  Calcular Take Profit fijo según configuración
//==================================================================
double CalcTP(const ENUM_POSITION_TYPE ptype, const double entry_price)
{
   if(InpFixedTP_Pips <= 0.0) return 0.0;

   double tp_dist = InpFixedTP_Pips * g_pip;
   double tp      = (ptype == POSITION_TYPE_BUY)
                    ? entry_price + tp_dist
                    : entry_price - tp_dist;
   return NormalizeDouble(tp, _Digits);
}

//==================================================================
//  Contar posiciones abiertas del bot por tipo
//==================================================================
int CountPositions(const ENUM_POSITION_TYPE ptype)
{
   int count = 0;
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL)  != _Symbol)        continue;
      if(PositionGetInteger(POSITION_MAGIC)  != InpMagicNumber) continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == ptype)
         count++;
   }
   return count;
}

//==================================================================
//  Cerrar posiciones del bot por tipo con logging de razón
//==================================================================
void CloseByType(const ENUM_POSITION_TYPE ptype, const string reason)
{
   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL)  != _Symbol)        continue;
      if(PositionGetInteger(POSITION_MAGIC)  != InpMagicNumber) continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != ptype) continue;

      double profit     = PositionGetDouble(POSITION_PROFIT);
      double open_price = PositionGetDouble(POSITION_PRICE_OPEN);

      if(g_trade.PositionClose(ticket))
      {
         Print("✔ TP EJECUTADO | ", EnumToString(ptype),
               " #", ticket,
               " | P&L=", DoubleToString(profit, 2),
               " | Open=", DoubleToString(open_price, _Digits),
               " | Razón: ", reason);
      }
      else
      {
         Print("✘ ERROR cerrando #", ticket,
               " [", g_trade.ResultRetcode(), "] ",
               g_trade.ResultRetcodeDescription());
      }
   }
}

//==================================================================
//  Detectar automáticamente el modo de filling compatible con el broker
//==================================================================
ENUM_ORDER_TYPE_FILLING GetOptimalFilling()
{
   uint filling = (uint)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
      return ORDER_FILLING_FOK;
   if((filling & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
      return ORDER_FILLING_IOC;
   return ORDER_FILLING_RETURN;
}
//+------------------------------------------------------------------+
