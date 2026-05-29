//+------------------------------------------------------------------+
//|              RSI_BB_SmartTP_v3.mq5                               |
//|    Bot Algorítmico Profesional con Smart TP (Quantum Style)      |
//|                                                                  |
//|  ── ENTRADAS ────────────────────────────────────────────────── |
//|    BUY  : RSI(1,HLCC/4) ≤ 8.9 + precio bajo BB Middle          |
//|    SELL : RSI(1,HLCC/4) ≥ 70  + precio sobre BB Middle         |
//|                                                                  |
//|  ── SMART TP SYSTEM (estilo Quantum) ───────────────────────── |
//|    FASE 0 · NORMAL  : Trailing estándar, sin señal TP aún       |
//|    FASE 1 · TP ZONE : RSI cruza 50 / precio toca BB Middle      |
//|                       → ¿Ganancia supera umbral?                |
//|                          SÍ → no cerrar, activar HARVEST        |
//|                          NO → cerrar con ganancia acumulada      |
//|    FASE 2 · HARVEST : Trailing ultrajustado (micro-gap)         |
//|                       seguimiento del precio tick a tick         |
//|                       cierre solo cuando el mercado revierta     |
//|    FASE 3 · RETRACEMENT GUARD : Si ganancia cae X% del pico     |
//|                       → cierre forzado con máxima captura        |
//+------------------------------------------------------------------+
#property copyright "RSI BB SmartTP v3.0"
#property link      ""
#property version   "3.00"
#property description "RSI(1)+BB(14,0.111) | Smart TP Quantum Style"

#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>

//==================================================================
//  PARÁMETROS DE ENTRADA
//==================================================================

input group "══════ RSI — Señales de Entrada ══════"
input int    InpRSI_Period     = 1;       // RSI Período
input double InpRSI_BuyLevel  = 8.9;     // RSI Nivel BUY  (≤ señal de compra)
input double InpRSI_SellLevel = 70.0;    // RSI Nivel SELL (≥ señal de venta)
input double InpRSI_TPLevel   = 50.0;    // RSI Nivel TP (cruza → activa zona TP)

input group "══════ BOLLINGER BANDS ══════"
input int    InpBB_Period     = 14;       // BB Período
input double InpBB_Deviation  = 0.111;   // BB Desviación
input int    InpBB_Shift      = 0;       // BB Desplazamiento

input group "══════ GESTIÓN DE ÓRDENES ══════"
input double InpLotSize       = 0.10;    // Tamaño del lote
input long   InpMagicNumber   = 20250601;// Magic Number único
input int    InpMaxBuys       = 1;       // Máx. BUYs simultáneos
input int    InpMaxSells      = 1;       // Máx. SELLs simultáneos
input double InpSL_Pips       = 0.0;    // Stop Loss en pips (0 = sin SL)

input group "══════ FASE 0 · TRAILING NORMAL ══════"
input bool   InpUseTrailing   = true;    // Activar trailing estándar
input double InpTrailStart    = 6.0;     // Activar trailing al ganar X pips
input double InpTrailGap      = 3.5;    // Distancia trailing normal (pips)

input group "══════ FASE 1 · SMART TP ZONE ══════"
input double InpSmartTP_Threshold = 8.0; // Umbral: si ganancia > X pips al llegar TP → HARVEST (no cerrar)
input bool   InpCloseIfBelowThreshold = true; // Cerrar si ganancia ≤ umbral al llegar TP

input group "══════ FASE 2 · HARVEST MODE ══════"
input double InpHarvestGap    = 1.5;     // Trailing micro-gap en modo Harvest (pips)
input double InpHarvestBreakout = 5.0;   // Extra pips sobre el TP para confirmar modo Harvest fuerte

input group "══════ FASE 3 · RETRACEMENT GUARD ══════"
input double InpRetracePct    = 35.0;    // Cerrar si ganancia cae X% desde el pico (35% = conservador)
input double InpMinPeakToActivate = 10.0;// Pico mínimo en pips para activar Retracement Guard

input group "══════ FILTROS DE ENTRADA ══════"
input bool   InpBBDirFilter   = true;    // Filtro: precio del lado correcto de BB Middle
input bool   InpNewBarEntry   = true;    // Buscar entradas solo en nueva vela
input bool   InpAllowBothSides = false;  // Permitir BUY y SELL simultáneos

input group "══════ RED DE SEGURIDAD ══════"
input double InpSafetyTP_Pips = 40.0;   // TP fijo del servidor (red final, 0=desactivado)

//==================================================================
//  CONSTANTES — FASES DEL SMART TP
//==================================================================
#define PHASE_NORMAL    0   // Trailing estándar, TP no activado aún
#define PHASE_HARVEST   1   // TP zona superada, micro-trailing activo
#define PHASE_CLOSED   -1   // Posición cerrada/inválida

//==================================================================
//  ESTRUCTURA DE ESTADO POR POSICIÓN
//==================================================================
struct PosState
{
   ulong  ticket;
   int    phase;
   double peak_profit_pip;     // máxima ganancia vista en pips
   double peak_price;          // precio más favorable visto
   double open_price;          // precio de apertura
   int    pos_type;            // 0=BUY, 1=SELL
   double last_reported_pip;   // último pico reportado en log (evita spam)
};

#define MAX_TRACKED 20
PosState g_states[MAX_TRACKED];
int      g_state_count = 0;

//==================================================================
//  VARIABLES GLOBALES
//==================================================================
CTrade      g_trade;
CSymbolInfo g_sym;

int      g_rsi_h    = INVALID_HANDLE;
int      g_bb_h     = INVALID_HANDLE;
datetime g_last_bar = 0;
double   g_pip      = 0.0;

//==================================================================
//  INICIALIZACIÓN
//==================================================================
int OnInit()
{
   //--- Símbolo
   if(!g_sym.Name(_Symbol))
   {
      Print("ERROR: No se pudo inicializar símbolo");
      return INIT_FAILED;
   }
   g_sym.RefreshRates();

   //--- Calcular pip
   int digs = (int)g_sym.Digits();
   g_pip    = (digs == 5 || digs == 3) ? g_sym.Point() * 10.0 : g_sym.Point();

   //--- RSI handle
   g_rsi_h = iRSI(_Symbol, _Period, InpRSI_Period, PRICE_WEIGHTED);
   if(g_rsi_h == INVALID_HANDLE)
   {
      Print("ERROR RSI handle: ", GetLastError());
      return INIT_FAILED;
   }

   //--- BB handle  (buf0=Middle, buf1=Upper, buf2=Lower)
   g_bb_h = iBands(_Symbol, _Period, InpBB_Period, InpBB_Shift, InpBB_Deviation, PRICE_WEIGHTED);
   if(g_bb_h == INVALID_HANDLE)
   {
      Print("ERROR BB handle: ", GetLastError());
      return INIT_FAILED;
   }

   //--- Trade config
   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(20);
   g_trade.SetTypeFilling(DetectFilling());
   g_trade.LogLevel(LOG_LEVEL_ERRORS);

   //--- Inicializar tracking
   for(int i = 0; i < MAX_TRACKED; i++)
   {
      g_states[i].ticket          = 0;
      g_states[i].phase           = PHASE_CLOSED;
      g_states[i].peak_profit_pip = 0.0;
      g_states[i].peak_price      = 0.0;
      g_states[i].open_price      = 0.0;
      g_states[i].pos_type        = -1;
      g_states[i].last_reported_pip = 0.0;
   }
   g_state_count = 0;

   Print("╔══════════════════════════════════════════════╗");
   Print("║  RSI BB SmartTP Bot v3.0 — INICIADO          ║");
   Print("╚══════════════════════════════════════════════╝");
   Print("Symbol=", _Symbol, " | TF=", EnumToString(_Period),
         " | pip=", DoubleToString(g_pip,_Digits));
   Print("RSI(", InpRSI_Period, ") BUY≤", InpRSI_BuyLevel,
         " | SELL≥", InpRSI_SellLevel, " | TP@", InpRSI_TPLevel);
   Print("BB(", InpBB_Period, ",dev=", InpBB_Deviation, ") HLCC/4");
   Print("SmartTP threshold=", InpSmartTP_Threshold, " pips",
         " | HarvestGap=", InpHarvestGap, " pips",
         " | RetracePct=", InpRetracePct, "%");

   return INIT_SUCCEEDED;
}

//==================================================================
//  DESINICIALIZACIÓN
//==================================================================
void OnDeinit(const int reason)
{
   if(g_rsi_h != INVALID_HANDLE) { IndicatorRelease(g_rsi_h); g_rsi_h = INVALID_HANDLE; }
   if(g_bb_h  != INVALID_HANDLE) { IndicatorRelease(g_bb_h);  g_bb_h  = INVALID_HANDLE; }
}

//==================================================================
//  TICK PRINCIPAL
//==================================================================
void OnTick()
{
   if(!g_sym.RefreshRates()) return;

   //--- Leer indicadores
   double rsi_buf[], bb_mid[], bb_up[], bb_dn[];
   ArraySetAsSeries(rsi_buf, true);
   ArraySetAsSeries(bb_mid,  true);
   ArraySetAsSeries(bb_up,   true);
   ArraySetAsSeries(bb_dn,   true);

   if(CopyBuffer(g_rsi_h, 0, 0, 3, rsi_buf) < 3) return;
   if(CopyBuffer(g_bb_h,  0, 0, 3, bb_mid)  < 3) return;
   if(CopyBuffer(g_bb_h,  1, 0, 3, bb_up)   < 3) return;
   if(CopyBuffer(g_bb_h,  2, 0, 3, bb_dn)   < 3) return;

   double rsi_now  = rsi_buf[0];
   double rsi_prev = rsi_buf[1];
   double mid_now  = bb_mid[0];
   double ask      = g_sym.Ask();
   double bid      = g_sym.Bid();

   //================================================================
   //  PASO 1 — Sincronizar tracking con posiciones reales
   //================================================================
   SyncPositionTracking();

   //================================================================
   //  PASO 2 — SMART TP MANAGER (cada tick, prioridad absoluta)
   //================================================================
   SmartTPManager(rsi_now, rsi_prev, mid_now, ask, bid);

   //================================================================
   //  PASO 3 — Filtro de nueva vela para entradas
   //================================================================
   if(InpNewBarEntry)
   {
      datetime bar0 = iTime(_Symbol, _Period, 0);
      if(bar0 == g_last_bar) return;
      g_last_bar = bar0;
   }

   //================================================================
   //  PASO 4 — SEÑALES DE ENTRADA
   //================================================================
   int n_buys  = CountPositions(POSITION_TYPE_BUY);
   int n_sells = CountPositions(POSITION_TYPE_SELL);

   //--- BUY: RSI ≤ nivel compra + (opcional) precio bajo BB Middle
   bool buy_sig = (rsi_now <= InpRSI_BuyLevel);
   if(InpBBDirFilter)   buy_sig = buy_sig && (ask < mid_now);
   if(!InpAllowBothSides && n_sells > 0) buy_sig = false;

   if(buy_sig && n_buys < InpMaxBuys)
      OpenTrade(ORDER_TYPE_BUY, ask, mid_now, rsi_now);

   //--- SELL: RSI ≥ nivel venta + (opcional) precio sobre BB Middle
   bool sell_sig = (rsi_now >= InpRSI_SellLevel);
   if(InpBBDirFilter)   sell_sig = sell_sig && (bid > mid_now);
   if(!InpAllowBothSides && n_buys > 0) sell_sig = false;

   if(sell_sig && n_sells < InpMaxSells)
      OpenTrade(ORDER_TYPE_SELL, bid, mid_now, rsi_now);
}

//==================================================================
//  SMART TP MANAGER — núcleo del sistema (cada tick)
//==================================================================
void SmartTPManager(double rsi_now, double rsi_prev, double mid_now,
                    double ask,     double bid)
{
   for(int i = 0; i < MAX_TRACKED; i++)
   {
      if(g_states[i].phase == PHASE_CLOSED || g_states[i].ticket == 0) continue;

      ulong  ticket  = g_states[i].ticket;
      int    ptype   = g_states[i].pos_type;   // 0=BUY, 1=SELL
      double o_price = g_states[i].open_price;

      //--- Calcular ganancia actual en pips
      double current_profit_pip = (ptype == 0)
                                  ? (bid - o_price) / g_pip
                                  : (o_price - ask) / g_pip;

      //--- Precio actual favorable
      double current_fav_price = (ptype == 0) ? bid : ask;

      //--- ── Actualizar pico de ganancia ──────────────────────────
      if(current_profit_pip > g_states[i].peak_profit_pip)
      {
         g_states[i].peak_profit_pip = current_profit_pip;
         g_states[i].peak_price      = current_fav_price;
      }

      double peak_pip = g_states[i].peak_profit_pip;
      double cur_sl   = PositionSelectByTicket(ticket)
                        ? PositionGetDouble(POSITION_SL) : 0;
      double cur_tp   = PositionSelectByTicket(ticket)
                        ? PositionGetDouble(POSITION_TP) : 0;

      //==============================================================
      //  FASE NORMAL — Trailing estándar + detección zona TP
      //==============================================================
      if(g_states[i].phase == PHASE_NORMAL)
      {
         //--- Trailing estándar
         if(InpUseTrailing && current_profit_pip >= InpTrailStart)
            ApplyTrail(ticket, ptype, current_fav_price, cur_sl, cur_tp,
                       InpTrailGap);

         //--- ¿Se activó la señal de TP?
         bool tp_rsi = (ptype == 0)
                       ? (rsi_prev < InpRSI_TPLevel && rsi_now >= InpRSI_TPLevel)
                       : (rsi_prev > InpRSI_TPLevel && rsi_now <= InpRSI_TPLevel);

         bool tp_bb  = (ptype == 0)
                       ? (bid >= mid_now)
                       : (ask <= mid_now);

         if(tp_rsi || tp_bb)
         {
            //--- ¿Ganancia actual supera el umbral Smart TP?
            if(current_profit_pip > InpSmartTP_Threshold)
            {
               //--- TRANSICIÓN → FASE HARVEST: no cerrar, cazar el pico
               g_states[i].phase = PHASE_HARVEST;
               Print("◈ HARVEST ACTIVADO #", ticket,
                     " | Profit=", DoubleToString(current_profit_pip,1), " pips",
                     " | Razón=", tp_rsi ? "RSI-50" : "BB-Middle",
                     " | MicroGap=", InpHarvestGap, " pips");
            }
            else
            {
               //--- Ganancia modesta → cerrar limpiamente
               if(InpCloseIfBelowThreshold)
               {
                  ClosePosition(ticket, StringFormat(
                     "TP normal | Profit=%.1f pips | %s",
                     current_profit_pip, tp_rsi ? "RSI-50" : "BB-Middle"));
                  continue;
               }
            }
         }
      }

      //==============================================================
      //  FASE HARVEST — Micro-trailing, captura máximo beneficio
      //==============================================================
      if(g_states[i].phase == PHASE_HARVEST)
      {
         //--- Aplicar micro-trailing ultraajustado
         ApplyTrail(ticket, ptype, current_fav_price, cur_sl, cur_tp,
                    InpHarvestGap);

         //--- ── RETRACEMENT GUARD ────────────────────────────────
         //    Si ganancia cae X% desde el pico → cierre forzado
         if(peak_pip >= InpMinPeakToActivate && peak_pip > 0.0)
         {
            double retrace_pct = ((peak_pip - current_profit_pip) / peak_pip) * 100.0;

            if(retrace_pct >= InpRetracePct)
            {
               ClosePosition(ticket, StringFormat(
                  "RETRACEMENT GUARD | Pico=%.1f pips | Actual=%.1f pips | Retroceso=%.1f%%",
                  peak_pip, current_profit_pip, retrace_pct));
               continue;
            }
         }

         //--- ── RSI REVERSAL CHECK ───────────────────────────────
         //    Si el RSI vuelve a zona extrema contraria → cierre
         bool rsi_reversal = (ptype == 0)
                             ? (rsi_now >= InpRSI_SellLevel * 0.85)  // BUY: RSI vuelve a zona alta
                             : (rsi_now <= InpRSI_BuyLevel  * 2.0);  // SELL: RSI vuelve a zona baja

         if(rsi_reversal && current_profit_pip > 0)
         {
            ClosePosition(ticket, StringFormat(
               "RSI REVERSAL en Harvest | RSI=%.1f | Profit=%.1f pips",
               rsi_now, current_profit_pip));
            continue;
         }

         //--- ── BREAKOUT BONUS CHECK ─────────────────────────────
         //    Si supera el TP + bonus, reportar pero NO cerrar aún
         if(current_profit_pip >= InpSmartTP_Threshold + InpHarvestBreakout)
         {
            if(current_profit_pip - g_states[i].last_reported_pip >= 2.0)
            {
               Print("🚀 HARVEST BONUS #", ticket,
                     " | Profit=", DoubleToString(current_profit_pip,1), " pips",
                     " | Pico=",   DoubleToString(peak_pip,1), " pips");
               g_states[i].last_reported_pip = current_profit_pip;
            }
         }
      }
   }
}

//==================================================================
//  APLICAR TRAILING STOP (normal o micro-gap)
//  Solo mueve el SL en dirección favorable — nunca retrocede
//==================================================================
void ApplyTrail(ulong ticket, int ptype, double fav_price,
                double cur_sl, double cur_tp, double gap_pips)
{
   double gap = gap_pips * g_pip;

   if(ptype == 0) // BUY
   {
      double new_sl = NormalizeDouble(fav_price - gap, _Digits);
      if(new_sl > cur_sl + g_sym.Point())
         g_trade.PositionModify(ticket, new_sl, cur_tp);
   }
   else // SELL
   {
      double new_sl = NormalizeDouble(fav_price + gap, _Digits);
      if(cur_sl < g_sym.Point() || new_sl < cur_sl - g_sym.Point())
         g_trade.PositionModify(ticket, new_sl, cur_tp);
   }
}

//==================================================================
//  ABRIR TRADE CON LOGGING COMPLETO
//==================================================================
void OpenTrade(ENUM_ORDER_TYPE otype, double price, double mid, double rsi)
{
   double sl = 0.0, tp = 0.0;

   if(InpSL_Pips > 0.0)
   {
      double sl_d = InpSL_Pips * g_pip;
      sl = NormalizeDouble(otype == ORDER_TYPE_BUY ? price - sl_d : price + sl_d, _Digits);
   }
   if(InpSafetyTP_Pips > 0.0)
   {
      double tp_d = InpSafetyTP_Pips * g_pip;
      tp = NormalizeDouble(otype == ORDER_TYPE_BUY ? price + tp_d : price - tp_d, _Digits);
   }

   bool ok = (otype == ORDER_TYPE_BUY)
             ? g_trade.Buy (InpLotSize, _Symbol, price, sl, tp, "SmartTP_BUY")
             : g_trade.Sell(InpLotSize, _Symbol, price, sl, tp, "SmartTP_SELL");

   if(ok)
   {
      ulong new_ticket = g_trade.ResultDeal();
      // Buscar ticket de posición abierta (el deal abre la posición)
      // Necesitamos el ticket de la POSICIÓN, no del DEAL
      // Lo obtenemos escaneando posiciones abiertas
      ulong pos_ticket = GetLastOpenedTicket(otype);

      if(pos_ticket > 0)
         AddPositionTracking(pos_ticket, price,
                             otype == ORDER_TYPE_BUY ? 0 : 1);

      Print(otype == ORDER_TYPE_BUY ? "▲ BUY " : "▼ SELL ",
            "ABIERTO | Price=", DoubleToString(price,_Digits),
            " | RSI=",  DoubleToString(rsi,  2),
            " | BBmid=",DoubleToString(mid,  _Digits),
            " | SL=",   DoubleToString(sl,   _Digits),
            " | SafetyTP=", DoubleToString(tp,_Digits),
            " | Ticket=", pos_ticket);
   }
   else
      Print("ERROR ", EnumToString(otype), ": [",
            g_trade.ResultRetcode(), "] ", g_trade.ResultRetcodeDescription());
}

//==================================================================
//  CERRAR POSICIÓN INDIVIDUAL CON LOG
//==================================================================
void ClosePosition(ulong ticket, string reason)
{
   if(!PositionSelectByTicket(ticket)) return;

   double profit    = PositionGetDouble(POSITION_PROFIT);
   double open_px   = PositionGetDouble(POSITION_PRICE_OPEN);
   double close_px  = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
                      ? g_sym.Bid() : g_sym.Ask();

   if(g_trade.PositionClose(ticket))
   {
      Print("✔ CERRADO #", ticket,
            " | P&L=",    DoubleToString(profit,2),
            " | Open=",   DoubleToString(open_px,  _Digits),
            " | Close=",  DoubleToString(close_px, _Digits),
            " | Razón: ", reason);
      RemovePositionTracking(ticket);
   }
   else
      Print("✘ ERROR cerrando #", ticket, " [",
            g_trade.ResultRetcode(), "] ", g_trade.ResultRetcodeDescription());
}

//==================================================================
//  SINCRONIZAR TRACKING — detecta posiciones nuevas y cerradas
//==================================================================
void SyncPositionTracking()
{
   //--- Marcar como cerradas las que ya no existen
   for(int i = 0; i < MAX_TRACKED; i++)
   {
      if(g_states[i].phase == PHASE_CLOSED) continue;
      if(g_states[i].ticket == 0)           continue;

      if(!PositionSelectByTicket(g_states[i].ticket))
      {
         g_states[i].phase   = PHASE_CLOSED;
         g_states[i].ticket  = 0;
         g_states[i].pos_type = -1;
         if(g_state_count > 0) g_state_count--;
      }
   }

   //--- Detectar posiciones nuevas que no están en tracking
   int total = PositionsTotal();
   for(int j = 0; j < total; j++)
   {
      ulong ticket = PositionGetTicket(j);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)        continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;

      if(FindStateIndex(ticket) == -1)
      {
         double open_px = PositionGetDouble(POSITION_PRICE_OPEN);
         int    ptype   = (int)PositionGetInteger(POSITION_TYPE);
         AddPositionTracking(ticket, open_px, ptype);
      }
   }
}

//==================================================================
//  AGREGAR POSICIÓN AL TRACKING
//==================================================================
void AddPositionTracking(ulong ticket, double open_price, int ptype)
{
   for(int i = 0; i < MAX_TRACKED; i++)
   {
      if(g_states[i].phase == PHASE_CLOSED || g_states[i].ticket == 0)
      {
         g_states[i].ticket          = ticket;
         g_states[i].phase           = PHASE_NORMAL;
         g_states[i].peak_profit_pip = 0.0;
         g_states[i].peak_price      = open_price;
         g_states[i].open_price      = open_price;
         g_states[i].pos_type        = ptype;
         g_states[i].last_reported_pip = 0.0;
         g_state_count++;
         Print("TRACKING iniciado | #", ticket,
               " | Type=", ptype == 0 ? "BUY" : "SELL",
               " | Open=", DoubleToString(open_price,_Digits));
         return;
      }
   }
   Print("ADVERTENCIA: Tracking array lleno (MAX=", MAX_TRACKED, ")");
}

//==================================================================
//  REMOVER POSICIÓN DEL TRACKING
//==================================================================
void RemovePositionTracking(ulong ticket)
{
   int idx = FindStateIndex(ticket);
   if(idx >= 0)
   {
      g_states[idx].ticket  = 0;
      g_states[idx].phase   = PHASE_CLOSED;
      g_states[idx].pos_type = -1;
      if(g_state_count > 0) g_state_count--;
   }
}

//==================================================================
//  BUSCAR ÍNDICE EN TRACKING ARRAY
//==================================================================
int FindStateIndex(ulong ticket)
{
   for(int i = 0; i < MAX_TRACKED; i++)
      if(g_states[i].ticket == ticket) return i;
   return -1;
}

//==================================================================
//  OBTENER TICKET DE LA ÚLTIMA POSICIÓN ABIERTA DEL BOT
//==================================================================
ulong GetLastOpenedTicket(ENUM_ORDER_TYPE otype)
{
   ulong   last_ticket = 0;
   datetime last_time  = 0;

   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL)  != _Symbol)        continue;
      if(PositionGetInteger(POSITION_MAGIC)  != InpMagicNumber) continue;

      ENUM_POSITION_TYPE pt = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if(otype == ORDER_TYPE_BUY  && pt != POSITION_TYPE_BUY)  continue;
      if(otype == ORDER_TYPE_SELL && pt != POSITION_TYPE_SELL) continue;

      datetime open_t = (datetime)PositionGetInteger(POSITION_TIME);
      if(open_t >= last_time)
      {
         last_time   = open_t;
         last_ticket = tk;
      }
   }
   return last_ticket;
}

//==================================================================
//  CONTAR POSICIONES ABIERTAS DEL BOT POR TIPO
//==================================================================
int CountPositions(ENUM_POSITION_TYPE ptype)
{
   int count = 0;
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL)  != _Symbol)        continue;
      if(PositionGetInteger(POSITION_MAGIC)  != InpMagicNumber) continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == ptype) count++;
   }
   return count;
}

//==================================================================
//  DETECTAR FILLING MODE COMPATIBLE CON EL BROKER
//==================================================================
ENUM_ORDER_TYPE_FILLING DetectFilling()
{
   uint fm = (uint)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((fm & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK) return ORDER_FILLING_FOK;
   if((fm & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC) return ORDER_FILLING_IOC;
   return ORDER_FILLING_RETURN;
}
//+------------------------------------------------------------------+
