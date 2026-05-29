//+------------------------------------------------------------------+
//|              RSI_BB_PatientTP_v4.mq5                             |
//|    Bot Algorítmico — Smart Patient TP (Quantum Style v4)         |
//|                                                                  |
//|  ── LÓGICA DE DIRECCIÓN ─────────────────────────────────────── |
//|    RSI ≥ 80   → ZONA SELL exclusiva  (solo abre SELLs)          |
//|    RSI ≤ 8.9  → ZONA BUY  exclusiva  (solo abre BUYs)           |
//|    RSI entre ambos → sin nuevas entradas                        |
//|                                                                  |
//|  ── REGLAS ABSOLUTAS ────────────────────────────────────────── |
//|    ✦ JAMÁS cierra en pérdida por código                         |
//|    ✦ Espera el pico máximo antes de cerrar                      |
//|    ✦ El cierre real solo lo ejecuta el trailing stop            |
//|                                                                  |
//|  ── FASES DEL SMART TP ──────────────────────────────────────── |
//|    FASE 0 · WAITING   : posición abierta, sin SL, espera        |
//|    FASE 1 · BREAKEVEN : ganó BE_pips → SL movido a entrada      |
//|    FASE 2 · TRAILING  : ganó TrailStart_pips → trailing activo  |
//|    FASE 3 · HARVEST   : señal TP recibida → micro-trailing      |
//|             el cierre ocurre SOLO cuando el mercado revierte     |
//|             y el trailing stop es alcanzado naturalmente         |
//+------------------------------------------------------------------+
#property copyright "RSI BB PatientTP v4.0"
#property link      ""
#property version   "4.00"
#property description "RSI(1)+BB(14,0.111) | Smart Patient TP | Sin cierres en pérdida"

#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>

//==================================================================
//  PARÁMETROS DE ENTRADA
//==================================================================

input group "══════ RSI — Niveles ══════"
input int    InpRSI_Period     = 1;       // RSI Período
input double InpRSI_BuyLevel  = 8.9;     // RSI: zona BUY  (≤ → solo compras)
input double InpRSI_SellLevel = 80.0;    // RSI: zona SELL (≥ → solo ventas)
input double InpRSI_TPLevel   = 50.0;    // RSI: nivel señal TP (activa Harvest)

input group "══════ BOLLINGER BANDS ══════"
input int    InpBB_Period     = 14;       // BB Período
input double InpBB_Deviation  = 0.111;   // BB Desviación
input int    InpBB_Shift      = 0;       // BB Desplazamiento

input group "══════ GESTIÓN DE ÓRDENES ══════"
input double InpLotSize       = 0.01;    // Lote (0.01 fijo)
input long   InpMagicNumber   = 20250601;// Magic Number
input int    InpMaxTrades     = 2;       // Máx. trades simultáneos (buys+sells)

input group "══════ FASE 0→1 · BREAK-EVEN ══════"
input double InpBE_Pips       = 5.0;     // Activar BE al ganar X pips
// (SL se mueve al precio de entrada — posición nunca puede cerrar en pérdida)

input group "══════ FASE 1→2 · TRAILING NORMAL ══════"
input double InpTrailStart    = 8.0;     // Activar trailing al ganar X pips
input double InpTrailGap      = 4.0;     // Gap trailing normal (pips)

input group "══════ FASE 2→3 · HARVEST MODE ══════"
// Se activa cuando RSI cruza 50 o precio toca BB Middle
// No cierra la posición — solo aplica micro-trailing
input double InpHarvestGap    = 1.5;     // Gap micro-trailing Harvest (pips)

input group "══════ RETRACEMENT GUARD (solo si profit > 0) ══════"
input double InpRetracePct    = 40.0;    // Cerrar si retrocede X% desde pico
input double InpRetraceMinPip = 12.0;    // Pico mínimo en pips para activar guard

input group "══════ RED DE SEGURIDAD (servidor) ══════"
input double InpSafetyTP_Pips = 80.0;   // TP fijo amplio en servidor (pips)
// Actúa solo si el micro-trailing falla por algún motivo

input group "══════ FILTRO BB DE ENTRADA ══════"
input bool   InpBBDirFilter   = true;    // Precio debe estar del lado correcto vs BB Middle
input bool   InpNewBarEntry   = true;    // Entradas solo en nueva vela

//==================================================================
//  CONSTANTES DE FASE
//==================================================================
#define PHASE_WAITING   0   // Sin SL, esperando ganancia para BE
#define PHASE_BREAKEVEN 1   // SL en precio de entrada (sin pérdida posible)
#define PHASE_TRAILING  2   // Trailing activo (profit creciendo)
#define PHASE_HARVEST   3   // Señal TP recibida → micro-trailing máximo
#define PHASE_CLOSED   -1   // Posición ya cerrada

//==================================================================
//  ESTRUCTURA DE ESTADO POR POSICIÓN
//==================================================================
#define MAX_TRACKED 10

struct PosState
{
   ulong  ticket;
   int    phase;
   int    pos_type;           // 0 = BUY, 1 = SELL
   double open_price;
   double peak_profit_pip;    // máxima ganancia vista (pips)
   double peak_price;         // precio más favorable registrado
   double last_log_pip;       // último pico logueado (anti-spam)
};

PosState g_states[MAX_TRACKED];
int      g_state_count = 0;

//==================================================================
//  VARIABLES GLOBALES
//==================================================================
CTrade       g_trade;
CSymbolInfo  g_sym;

int      g_rsi_h    = INVALID_HANDLE;
int      g_bb_h     = INVALID_HANDLE;
datetime g_last_bar = 0;
double   g_pip      = 0.0;

//==================================================================
//  INICIALIZACIÓN
//==================================================================
int OnInit()
{
   if(!g_sym.Name(_Symbol))
   {
      Print("ERROR: símbolo inválido");
      return INIT_FAILED;
   }
   g_sym.RefreshRates();

   int digs = (int)g_sym.Digits();
   g_pip    = (digs == 5 || digs == 3) ? g_sym.Point() * 10.0 : g_sym.Point();

   //--- RSI: período 1, Weighted Close (HLCC/4)
   g_rsi_h = iRSI(_Symbol, _Period, InpRSI_Period, PRICE_WEIGHTED);
   if(g_rsi_h == INVALID_HANDLE)
   {
      Print("ERROR RSI: ", GetLastError());
      return INIT_FAILED;
   }

   //--- BB: período 14, desv 0.111, Weighted Close (HLCC/4)
   //    buf0=Middle  buf1=Upper  buf2=Lower
   g_bb_h = iBands(_Symbol, _Period, InpBB_Period, InpBB_Shift, InpBB_Deviation, PRICE_WEIGHTED);
   if(g_bb_h == INVALID_HANDLE)
   {
      Print("ERROR BB: ", GetLastError());
      return INIT_FAILED;
   }

   //--- Trade config
   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(20);
   g_trade.SetTypeFilling(DetectFilling());
   g_trade.LogLevel(LOG_LEVEL_ERRORS);

   //--- Inicializar estados
   for(int i = 0; i < MAX_TRACKED; i++) ResetState(i);
   g_state_count = 0;

   Print("╔════════════════════════════════════════════════╗");
   Print("║  RSI BB PatientTP v4.0 — INICIADO              ║");
   Print("╠════════════════════════════════════════════════╣");
   Print("║  BUY  zona: RSI ≤ ", DoubleToString(InpRSI_BuyLevel,1),
         "   |  SELL zona: RSI ≥ ", DoubleToString(InpRSI_SellLevel,1), "   ║");
   Print("║  Lote: ", DoubleToString(InpLotSize,2),
         "  |  Máx trades: ", InpMaxTrades,
         "  |  pip=", DoubleToString(g_pip,_Digits), "  ║");
   Print("║  BE=", DoubleToString(InpBE_Pips,1),
         " pips | Trail=", DoubleToString(InpTrailStart,1),
         "/", DoubleToString(InpTrailGap,1),
         " | Harvest=", DoubleToString(InpHarvestGap,1), " pips  ║");
   Print("╚════════════════════════════════════════════════╝");

   return INIT_SUCCEEDED;
}

//==================================================================
//  DESINICIALIZACIÓN
//==================================================================
void OnDeinit(const int reason)
{
   if(g_rsi_h != INVALID_HANDLE){ IndicatorRelease(g_rsi_h); g_rsi_h = INVALID_HANDLE; }
   if(g_bb_h  != INVALID_HANDLE){ IndicatorRelease(g_bb_h);  g_bb_h  = INVALID_HANDLE; }
}

//==================================================================
//  TICK PRINCIPAL
//==================================================================
void OnTick()
{
   if(!g_sym.RefreshRates()) return;

   //--- Leer indicadores (3 barras para detectar cruces)
   double rsi_buf[3], bb_mid[3], bb_up[3], bb_dn[3];
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
   //  PASO 1 — Sincronizar tracking con posiciones reales del broker
   //================================================================
   SyncTracking();

   //================================================================
   //  PASO 2 — SMART PATIENT TP (cada tick, prioridad absoluta)
   //================================================================
   PatientTPManager(rsi_now, rsi_prev, mid_now, ask, bid);

   //================================================================
   //  PASO 3 — Filtro de nueva vela (entradas)
   //================================================================
   if(InpNewBarEntry)
   {
      datetime t0 = iTime(_Symbol, _Period, 0);
      if(t0 == g_last_bar) return;
      g_last_bar = t0;
   }

   //================================================================
   //  PASO 4 — SEÑALES DE ENTRADA con dirección exclusiva
   //================================================================
   int total_open = TotalPositions();

   if(total_open < InpMaxTrades)
   {
      //--- ZONA BUY: RSI ≤ 8.9 → SOLO compras permitidas
      if(rsi_now <= InpRSI_BuyLevel)
      {
         bool ok = true;
         if(InpBBDirFilter && ask >= mid_now) ok = false;  // precio debe estar bajo BB Middle
         if(ok) TryOpenTrade(ORDER_TYPE_BUY, ask, mid_now, rsi_now);
      }

      //--- ZONA SELL: RSI ≥ 80 → SOLO ventas permitidas
      else if(rsi_now >= InpRSI_SellLevel)
      {
         bool ok = true;
         if(InpBBDirFilter && bid <= mid_now) ok = false;  // precio debe estar sobre BB Middle
         if(ok) TryOpenTrade(ORDER_TYPE_SELL, bid, mid_now, rsi_now);
      }
      //--- RSI entre 8.9 y 80 → sin nuevas entradas
   }
}

//==================================================================
//  PATIENT TP MANAGER — gestiona todas las posiciones (cada tick)
//  REGLA MAESTRA: el código NUNCA llama a ClosePosition en pérdida
//  Solo el TRAILING STOP cierra posiciones naturalmente
//==================================================================
void PatientTPManager(double rsi_now, double rsi_prev,
                      double mid_now, double ask, double bid)
{
   for(int i = 0; i < MAX_TRACKED; i++)
   {
      if(g_states[i].phase == PHASE_CLOSED) continue;
      if(g_states[i].ticket == 0)           continue;

      ulong  tk      = g_states[i].ticket;
      int    ptype   = g_states[i].pos_type;    // 0=BUY 1=SELL
      double o_price = g_states[i].open_price;

      //--- Seleccionar posición para leer SL/TP actuales
      if(!PositionSelectByTicket(tk)) continue;
      double cur_sl  = PositionGetDouble(POSITION_SL);
      double cur_tp  = PositionGetDouble(POSITION_TP);

      //--- Precio favorable actual
      double fav_price = (ptype == 0) ? bid : ask;

      //--- Ganancia actual en pips (puede ser negativa si mercado en contra)
      double profit_pip = (ptype == 0)
                          ? (bid    - o_price) / g_pip
                          : (o_price - ask)    / g_pip;

      //--- Actualizar pico de ganancia (solo registra nuevos máximos)
      if(profit_pip > g_states[i].peak_profit_pip)
      {
         g_states[i].peak_profit_pip = profit_pip;
         g_states[i].peak_price      = fav_price;
      }
      double peak_pip = g_states[i].peak_profit_pip;

      //============================================================
      //  FASE 0 → 1: WAITING → BREAK-EVEN
      //  Cuando ganancia ≥ InpBE_Pips → mover SL a precio de entrada
      //  A partir de aquí la posición JAMÁS puede cerrar en pérdida
      //============================================================
      if(g_states[i].phase == PHASE_WAITING)
      {
         if(profit_pip >= InpBE_Pips)
         {
            double be_sl = NormalizeDouble(o_price, _Digits);

            bool move_ok = false;
            if(ptype == 0 && be_sl > cur_sl + g_sym.Point())
               move_ok = g_trade.PositionModify(tk, be_sl, cur_tp);
            else if(ptype == 1 && (cur_sl < g_sym.Point() || be_sl < cur_sl - g_sym.Point()))
               move_ok = g_trade.PositionModify(tk, be_sl, cur_tp);

            if(move_ok)
            {
               g_states[i].phase = PHASE_BREAKEVEN;
               Print("■ BREAK-EVEN #", tk,
                     " | SL movido a entrada: ", DoubleToString(o_price,_Digits),
                     " | Profit actual: ",       DoubleToString(profit_pip,1), " pips");
            }
         }
         // En WAITING: si no alcanzó BE aún, el mercado puede ir en nuestra contra
         // El bot ESPERA — sin cierre forzado, sin pánico
         if(g_states[i].phase == PHASE_WAITING) continue;
      }

      //============================================================
      //  FASE 1 → 2: BREAK-EVEN → TRAILING NORMAL
      //  Cuando ganancia ≥ InpTrailStart → activar trailing
      //  SL se mueve SOLO hacia ganancia, nunca hacia pérdida
      //============================================================
      if(g_states[i].phase == PHASE_BREAKEVEN)
      {
         if(profit_pip >= InpTrailStart)
         {
            g_states[i].phase = PHASE_TRAILING;
            Print("► TRAILING ACTIVO #", tk,
                  " | Profit: ", DoubleToString(profit_pip,1), " pips",
                  " | Gap: ",    DoubleToString(InpTrailGap,1), " pips");
            // Aplica trailing inmediatamente (cae al bloque siguiente)
         }
         else
            continue; // Todavía no hay suficiente ganancia para trailing
      }

      //============================================================
      //  FASE 2: TRAILING NORMAL
      //  Mueve SL siguiendo al precio con InpTrailGap pips de distancia
      //  Si señal TP (RSI 50 / BB Middle) → pasa a HARVEST
      //  El SL NUNCA baja de open_price (garantía anti-pérdida)
      //============================================================
      if(g_states[i].phase == PHASE_TRAILING)
      {
         ApplySafeTrail(tk, ptype, fav_price, cur_sl, cur_tp, o_price, InpTrailGap);

         //--- Detectar señal TP → transición a Harvest
         bool sig_rsi = (ptype == 0)
                        ? (rsi_prev < InpRSI_TPLevel  && rsi_now >= InpRSI_TPLevel)
                        : (rsi_prev > InpRSI_TPLevel  && rsi_now <= InpRSI_TPLevel);

         bool sig_bb  = (ptype == 0) ? (bid >= mid_now) : (ask <= mid_now);

         if(sig_rsi || sig_bb)
         {
            g_states[i].phase = PHASE_HARVEST;
            Print("◈ HARVEST #", tk,
                  " | Señal: ",  sig_rsi ? "RSI-50" : "BB-Middle",
                  " | Profit: ", DoubleToString(profit_pip,1), " pips",
                  " → micro-trailing ", DoubleToString(InpHarvestGap,1), " pips activo");
         }
      }

      //============================================================
      //  FASE 3: HARVEST — Micro-trailing + Retracement Guard
      //
      //  El mercado puede seguir corriendo indefinidamente.
      //  El bot NO cierra — solo el trailing stop lo hará
      //  cuando el mercado revierta lo suficiente.
      //
      //  Excepción: Retracement Guard (solo si profit > 0 y peak > umbral)
      //  → cierra si el mercado ya retrocedió X% del pico,
      //    asegurando capturar la mayor ganancia posible
      //============================================================
      if(g_states[i].phase == PHASE_HARVEST)
      {
         //--- Micro-trailing ultraajustado
         ApplySafeTrail(tk, ptype, fav_price, cur_sl, cur_tp, o_price, InpHarvestGap);

         //--- Retracement Guard
         //    Solo actúa si: 1) pico ≥ umbral mínimo
         //                   2) ganancia actual > 0 (JAMÁS cierra en pérdida)
         if(peak_pip >= InpRetraceMinPip && profit_pip > 0.0)
         {
            double retrace_pct = ((peak_pip - profit_pip) / peak_pip) * 100.0;

            if(retrace_pct >= InpRetracePct)
            {
               ForceClose(tk, StringFormat(
                  "RETRACEMENT GUARD | Pico=%.1f pips | Actual=%.1f pips | Retroceso=%.0f%%",
                  peak_pip, profit_pip, retrace_pct));
               continue;
            }
         }

         //--- Log de progreso (cada 3 pips de nuevo pico, anti-spam)
         if(peak_pip > g_states[i].last_log_pip + 3.0)
         {
            Print("🚀 HARVEST #", tk,
                  " | Pico=",    DoubleToString(peak_pip,  1), " pips",
                  " | Actual=",  DoubleToString(profit_pip,1), " pips",
                  " | SL=",      DoubleToString(cur_sl,    _Digits));
            g_states[i].last_log_pip = peak_pip;
         }
      }
   }
}

//==================================================================
//  APPLY SAFE TRAIL — trailing con garantía anti-pérdida
//  El SL NUNCA se mueve por debajo del open_price (para BUY)
//  ni por encima del open_price (para SELL)
//==================================================================
void ApplySafeTrail(ulong tk,     int ptype, double fav_price,
                    double cur_sl, double cur_tp,
                    double open_price, double gap_pips)
{
   double gap = gap_pips * g_pip;

   if(ptype == 0) // BUY: SL sube, nunca baja
   {
      double raw_sl  = fav_price - gap;
      // Garantía: SL nunca por debajo del precio de apertura
      double new_sl  = NormalizeDouble(MathMax(raw_sl, open_price), _Digits);

      if(new_sl > cur_sl + g_sym.Point())
         g_trade.PositionModify(tk, new_sl, cur_tp);
   }
   else // SELL: SL baja, nunca sube
   {
      double raw_sl  = fav_price + gap;
      // Garantía: SL nunca por encima del precio de apertura
      double new_sl  = NormalizeDouble(MathMin(raw_sl, open_price), _Digits);

      bool sl_not_set = (cur_sl < g_sym.Point());
      if(sl_not_set || new_sl < cur_sl - g_sym.Point())
         g_trade.PositionModify(tk, new_sl, cur_tp);
   }
}

//==================================================================
//  ABRIR TRADE — con validaciones y tracking
//==================================================================
void TryOpenTrade(ENUM_ORDER_TYPE otype, double price,
                  double mid, double rsi)
{
   //--- No abrir duplicados en misma dirección si ya hay 2 en total
   if(TotalPositions() >= InpMaxTrades) return;

   double sl = 0.0;    // Sin SL inicial (el sistema de fases lo gestiona)
   double tp = 0.0;
   if(InpSafetyTP_Pips > 0.0)
   {
      double tp_d = InpSafetyTP_Pips * g_pip;
      tp = NormalizeDouble(otype == ORDER_TYPE_BUY ? price + tp_d
                                                    : price - tp_d, _Digits);
   }

   bool ok = (otype == ORDER_TYPE_BUY)
             ? g_trade.Buy (InpLotSize, _Symbol, price, sl, tp, "PatientTP_BUY")
             : g_trade.Sell(InpLotSize, _Symbol, price, sl, tp, "PatientTP_SELL");

   if(ok)
   {
      // Buscar ticket de la posición recién abierta
      ulong pos_tk = GetNewestTicket(otype);
      if(pos_tk > 0)
         AddTracking(pos_tk, price, otype == ORDER_TYPE_BUY ? 0 : 1);

      Print(otype == ORDER_TYPE_BUY ? "▲ BUY" : "▼ SELL",
            " ABIERTO | Price=", DoubleToString(price, _Digits),
            " | RSI=",           DoubleToString(rsi,   2),
            " | BBmid=",         DoubleToString(mid,   _Digits),
            " | SafetyTP=",      DoubleToString(tp,    _Digits),
            " | Ticket=",        pos_tk);
   }
   else
      Print("ERROR ORDEN ", EnumToString(otype), ": [",
            g_trade.ResultRetcode(), "] ",
            g_trade.ResultRetcodeDescription());
}

//==================================================================
//  CIERRE FORZADO (solo para Retracement Guard — siempre en profit)
//==================================================================
void ForceClose(ulong tk, string reason)
{
   if(!PositionSelectByTicket(tk)) return;
   double profit = PositionGetDouble(POSITION_PROFIT);

   // Garantía doble: solo cerramos si hay ganancia real
   if(profit <= 0.0)
   {
      Print("⚠ ForceClose bloqueado para #", tk,
            " — profit=", DoubleToString(profit,2), " (protección anti-pérdida)");
      return;
   }

   if(g_trade.PositionClose(tk))
   {
      Print("✔ CERRADO #", tk,
            " | P&L=",    DoubleToString(profit,2),
            " | Razón: ", reason);
      RemoveTracking(tk);
   }
   else
      Print("✘ ERROR cerrando #", tk, " [",
            g_trade.ResultRetcode(), "] ",
            g_trade.ResultRetcodeDescription());
}

//==================================================================
//  SINCRONIZAR TRACKING con posiciones reales
//==================================================================
void SyncTracking()
{
   // Eliminar tickets que ya no existen
   for(int i = 0; i < MAX_TRACKED; i++)
   {
      if(g_states[i].ticket == 0) continue;
      if(!PositionSelectByTicket(g_states[i].ticket))
         ResetState(i);
   }

   // Agregar posiciones nuevas (abiertas manualmente o por reinicio del EA)
   int total = PositionsTotal();
   for(int j = 0; j < total; j++)
   {
      ulong tk = PositionGetTicket(j);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL)  != _Symbol)        continue;
      if(PositionGetInteger(POSITION_MAGIC)  != InpMagicNumber) continue;
      if(FindIdx(tk) == -1)
      {
         int ptype  = (int)PositionGetInteger(POSITION_TYPE);
         double opx = PositionGetDouble(POSITION_PRICE_OPEN);
         AddTracking(tk, opx, ptype);
      }
   }
}

//==================================================================
//  AGREGAR AL TRACKING
//==================================================================
void AddTracking(ulong tk, double open_px, int ptype)
{
   for(int i = 0; i < MAX_TRACKED; i++)
   {
      if(g_states[i].ticket == 0)
      {
         g_states[i].ticket          = tk;
         g_states[i].phase           = PHASE_WAITING;
         g_states[i].pos_type        = ptype;
         g_states[i].open_price      = open_px;
         g_states[i].peak_profit_pip = 0.0;
         g_states[i].peak_price      = open_px;
         g_states[i].last_log_pip    = 0.0;
         g_state_count++;
         Print("TRACKING #", tk,
               " | ", (ptype == 0 ? "BUY" : "SELL"),
               " | Open=", DoubleToString(open_px,_Digits));
         return;
      }
   }
   Print("⚠ Tracking lleno (MAX=", MAX_TRACKED, ")");
}

//==================================================================
//  ELIMINAR DEL TRACKING
//==================================================================
void RemoveTracking(ulong tk)
{
   int idx = FindIdx(tk);
   if(idx >= 0)
   {
      ResetState(idx);
      if(g_state_count > 0) g_state_count--;
   }
}

//==================================================================
//  RESETEAR SLOT DE TRACKING
//==================================================================
void ResetState(int i)
{
   g_states[i].ticket          = 0;
   g_states[i].phase           = PHASE_CLOSED;
   g_states[i].pos_type        = -1;
   g_states[i].open_price      = 0.0;
   g_states[i].peak_profit_pip = 0.0;
   g_states[i].peak_price      = 0.0;
   g_states[i].last_log_pip    = 0.0;
}

//==================================================================
//  BUSCAR ÍNDICE EN TRACKING
//==================================================================
int FindIdx(ulong tk)
{
   for(int i = 0; i < MAX_TRACKED; i++)
      if(g_states[i].ticket == tk) return i;
   return -1;
}

//==================================================================
//  OBTENER TICKET DE LA POSICIÓN MÁS RECIENTE DEL BOT
//==================================================================
ulong GetNewestTicket(ENUM_ORDER_TYPE otype)
{
   ulong    best_tk   = 0;
   datetime best_time = 0;
   int      total     = PositionsTotal();

   for(int i = 0; i < total; i++)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL)  != _Symbol)        continue;
      if(PositionGetInteger(POSITION_MAGIC)  != InpMagicNumber) continue;

      ENUM_POSITION_TYPE pt = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if(otype == ORDER_TYPE_BUY  && pt != POSITION_TYPE_BUY)  continue;
      if(otype == ORDER_TYPE_SELL && pt != POSITION_TYPE_SELL) continue;

      datetime t = (datetime)PositionGetInteger(POSITION_TIME);
      if(t >= best_time && FindIdx(tk) == -1)
      {
         best_time = t;
         best_tk   = tk;
      }
   }
   return best_tk;
}

//==================================================================
//  CONTAR TOTAL DE POSICIONES DEL BOT
//==================================================================
int TotalPositions()
{
   int count = 0;
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL)  != _Symbol)        continue;
      if(PositionGetInteger(POSITION_MAGIC)  != InpMagicNumber) continue;
      count++;
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
