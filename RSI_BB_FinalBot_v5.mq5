//+------------------------------------------------------------------+
//|              RSI_BB_FinalBot_v5.mq5                              |
//|      Bot Algorítmico Final — RSI(1) + BB(14,0.111) HLCC/4       |
//|                                                                  |
//|  ═══ LÓGICA DE ENTRADA ════════════════════════════════════════ |
//|    RSI ≤  9  → ZONA BUY  : abre 2 BUYs con 3 seg de diferencia |
//|    RSI ≥ 85  → ZONA SELL : abre 2 SELLs con 3 seg de diferencia |
//|    RSI entre 9 y 85 → ZONA MUERTA — cero operaciones           |
//|                                                                  |
//|  ═══ REGLAS ABSOLUTAS ═════════════════════════════════════════ |
//|    ✦ Máximo 2 trades simultáneos                                |
//|    ✦ JAMÁS abre trades en zona muerta                           |
//|    ✦ JAMÁS cierra con pérdida por código                        |
//|    ✦ Espera el pico máximo (trailing lo cierra naturalmente)    |
//|                                                                  |
//|  ═══ FASES SMART PATIENT TP ═══════════════════════════════════ |
//|    FASE 0 · WAITING   : sin SL, espera ganancia                 |
//|    FASE 1 · BREAKEVEN : SL = precio entrada (protección total)  |
//|    FASE 2 · TRAILING  : trailing activo (gap configurable)      |
//|    FASE 3 · HARVEST   : micro-trailing al detectar señal TP     |
//+------------------------------------------------------------------+
#property copyright "RSI BB FinalBot v5.0"
#property link      ""
#property version   "5.00"
#property description "RSI(1)+BB(14,0.111) HLCC/4 | BUY≤9 | SELL≥85 | Dual Entry 3s"

#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>

//==================================================================
//  PARÁMETROS DE ENTRADA
//==================================================================

input group "═══ RSI — Niveles de Señal ═══"
input int    InpRSI_Period     = 1;       // RSI Período
input double InpRSI_BuyLevel  = 9.0;     // RSI BUY  (≤ → zona compra)
input double InpRSI_SellLevel = 85.0;    // RSI SELL (≥ → zona venta)
input double InpRSI_TPLevel   = 50.0;    // RSI TP   (señal activación Harvest)

input group "═══ BOLLINGER BANDS ═══"
input int    InpBB_Period     = 14;       // BB Período
input double InpBB_Deviation  = 0.111;   // BB Desviación
input int    InpBB_Shift      = 0;       // BB Desplazamiento

input group "═══ ÓRDENES ═══"
input double InpLotSize       = 0.01;    // Lote por trade
input long   InpMagicNumber   = 20250601;// Magic Number
input int    InpSecondTradeDelay = 3;    // Segundos entre el 1er y 2do trade

input group "═══ FASE 0→1 · BREAK-EVEN ═══"
input double InpBE_Pips       = 5.0;     // Activar BE al ganar X pips

input group "═══ FASE 1→2 · TRAILING ═══"
input double InpTrailStart    = 8.0;     // Activar trailing al ganar X pips
input double InpTrailGap      = 4.0;     // Gap trailing normal (pips)

input group "═══ FASE 2→3 · HARVEST ═══"
input double InpHarvestGap    = 1.5;     // Gap micro-trailing Harvest (pips)

input group "═══ RETRACEMENT GUARD ═══"
input double InpRetracePct    = 40.0;    // Cerrar si retrocede X% desde pico
input double InpRetraceMinPip = 12.0;    // Pico mínimo para activar guard (pips)

input group "═══ RED DE SEGURIDAD (servidor) ═══"
input double InpSafetyTP_Pips = 100.0;  // TP fijo amplio servidor (pips, 0=off)

input group "═══ FILTROS ═══"
input bool   InpBBDirFilter   = true;    // Filtro dirección BB Middle
input bool   InpNewBarEntry   = true;    // Entradas solo en nueva vela

//==================================================================
//  CONSTANTES DE FASE
//==================================================================
#define PHASE_WAITING   0
#define PHASE_BREAKEVEN 1
#define PHASE_TRAILING  2
#define PHASE_HARVEST   3
#define PHASE_CLOSED   -1

//==================================================================
//  ESTRUCTURA DE ESTADO POR POSICIÓN
//==================================================================
#define MAX_TRACKED 6

struct PosState
{
   ulong  ticket;
   int    phase;
   int    pos_type;           // 0=BUY, 1=SELL
   double open_price;
   double peak_profit_pip;
   double peak_price;
   double last_log_pip;
};

PosState g_states[MAX_TRACKED];

//==================================================================
//  VARIABLES GLOBALES
//==================================================================
CTrade       g_trade;
CSymbolInfo  g_sym;

int      g_rsi_h    = INVALID_HANDLE;
int      g_bb_h     = INVALID_HANDLE;
datetime g_last_bar = 0;
double   g_pip      = 0.0;

// Control del 2do trade (3 segundos después del 1ro)
bool             g_second_pending  = false;
datetime         g_second_open_at  = 0;
ENUM_ORDER_TYPE  g_second_type     = ORDER_TYPE_BUY;

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

   // RSI(1) aplicado a Weighted Close HLCC/4
   g_rsi_h = iRSI(_Symbol, _Period, InpRSI_Period, PRICE_WEIGHTED);
   if(g_rsi_h == INVALID_HANDLE)
   {
      Print("ERROR RSI handle: ", GetLastError());
      return INIT_FAILED;
   }

   // BB(14, 0.111) aplicado a Weighted Close HLCC/4
   // buf 0=Middle  1=Upper  2=Lower
   g_bb_h = iBands(_Symbol, _Period, InpBB_Period, InpBB_Shift,
                   InpBB_Deviation, PRICE_WEIGHTED);
   if(g_bb_h == INVALID_HANDLE)
   {
      Print("ERROR BB handle: ", GetLastError());
      return INIT_FAILED;
   }

   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(20);
   g_trade.SetTypeFilling(DetectFilling());
   g_trade.LogLevel(LOG_LEVEL_ERRORS);

   // Inicializar estados
   for(int i = 0; i < MAX_TRACKED; i++) ResetState(i);

   g_second_pending = false;

   Print("╔══════════════════════════════════════════════════╗");
   Print("║     RSI BB FinalBot v5.0 — INICIADO              ║");
   Print("╠══════════════════════════════════════════════════╣");
   Print("║  Símbolo : ", _Symbol, " | TF: ", EnumToString(_Period), "                    ║");
   Print("║  BUY  ≤  ", DoubleToString(InpRSI_BuyLevel,1),
         "  |  SELL ≥ ",  DoubleToString(InpRSI_SellLevel,1),
         "  |  TP @ ",    DoubleToString(InpRSI_TPLevel,1), "           ║");
   Print("║  Lote: ",    DoubleToString(InpLotSize,2),
         " | Dual entry: ", InpSecondTradeDelay, "s gap              ║");
   Print("║  BE=",       DoubleToString(InpBE_Pips,1),
         " | Trail=",    DoubleToString(InpTrailStart,1), "/",
                         DoubleToString(InpTrailGap,1),
         " | Harvest=",  DoubleToString(InpHarvestGap,1), " pips        ║");
   Print("╚══════════════════════════════════════════════════╝");

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

   // Leer indicadores
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
   //  PASO 1 — Sincronizar tracking
   //================================================================
   SyncTracking();

   //================================================================
   //  PASO 2 — Smart Patient TP Manager (cada tick, prioridad max)
   //================================================================
   PatientTPManager(rsi_now, rsi_prev, mid_now, ask, bid);

   //================================================================
   //  PASO 3 — 2do trade programado (3 segundos después del 1ro)
   //  No requiere nueva vela — lo ejecuta el tiempo
   //================================================================
   if(g_second_pending && TimeCurrent() >= g_second_open_at)
   {
      g_second_pending = false;

      // Solo abrir si hay capacidad y RSI sigue en zona correcta
      if(TotalPositions() < 2)
      {
         bool rsi_ok = (g_second_type == ORDER_TYPE_BUY)
                       ? (rsi_now <= InpRSI_BuyLevel)
                       : (rsi_now >= InpRSI_SellLevel);

         if(rsi_ok)
         {
            double price = (g_second_type == ORDER_TYPE_BUY) ? ask : bid;
            ExecuteOrder(g_second_type, price, mid_now, rsi_now, true);
         }
         else
            Print("2do trade cancelado: RSI salió de zona (",
                  DoubleToString(rsi_now,1), ")");
      }
   }

   //================================================================
   //  PASO 4 — Filtro nueva vela (solo para entradas nuevas)
   //================================================================
   if(InpNewBarEntry)
   {
      datetime t0 = iTime(_Symbol, _Period, 0);
      if(t0 == g_last_bar) return;
      g_last_bar = t0;
   }

   //================================================================
   //  PASO 5 — SEÑALES DE ENTRADA
   //  ZONA MUERTA: RSI entre 9 y 85 → NUNCA operar
   //================================================================

   // Si ya hay 2 trades abiertos → no buscar nuevas entradas
   if(TotalPositions() >= 2) return;

   // Si ya hay un 2do trade pendiente → esperar
   if(g_second_pending) return;

   //--- ZONA BUY exclusiva: RSI ≤ 9
   if(rsi_now <= InpRSI_BuyLevel)
   {
      // Filtro BB: precio debe estar BAJO la BB Middle line
      if(InpBBDirFilter && ask >= mid_now) return;

      // Abrir 1er BUY ahora
      ExecuteOrder(ORDER_TYPE_BUY, ask, mid_now, rsi_now, false);

      // Programar 2do BUY en 3 segundos
      if(TotalPositions() < 2)
      {
         g_second_pending = true;
         g_second_open_at = TimeCurrent() + (datetime)InpSecondTradeDelay;
         g_second_type    = ORDER_TYPE_BUY;
         Print("⏱ 2do BUY programado en ", InpSecondTradeDelay, " seg");
      }
   }

   //--- ZONA SELL exclusiva: RSI ≥ 85
   else if(rsi_now >= InpRSI_SellLevel)
   {
      // Filtro BB: precio debe estar SOBRE la BB Middle line
      if(InpBBDirFilter && bid <= mid_now) return;

      // Abrir 1er SELL ahora
      ExecuteOrder(ORDER_TYPE_SELL, bid, mid_now, rsi_now, false);

      // Programar 2do SELL en 3 segundos
      if(TotalPositions() < 2)
      {
         g_second_pending = true;
         g_second_open_at = TimeCurrent() + (datetime)InpSecondTradeDelay;
         g_second_type    = ORDER_TYPE_SELL;
         Print("⏱ 2do SELL programado en ", InpSecondTradeDelay, " seg");
      }
   }
   // RSI entre 9 y 85 → ZONA MUERTA, no se hace nada
}

//==================================================================
//  SMART PATIENT TP MANAGER — cada tick
//  Regla maestra: JAMÁS cierra en pérdida por código
//==================================================================
void PatientTPManager(double rsi_now, double rsi_prev,
                      double mid_now, double ask, double bid)
{
   for(int i = 0; i < MAX_TRACKED; i++)
   {
      if(g_states[i].ticket == 0 || g_states[i].phase == PHASE_CLOSED)
         continue;

      ulong  tk      = g_states[i].ticket;
      int    ptype   = g_states[i].pos_type;   // 0=BUY 1=SELL
      double o_price = g_states[i].open_price;

      if(!PositionSelectByTicket(tk)) continue;
      double cur_sl = PositionGetDouble(POSITION_SL);
      double cur_tp = PositionGetDouble(POSITION_TP);

      double fav_price  = (ptype == 0) ? bid : ask;
      double profit_pip = (ptype == 0)
                          ? (bid    - o_price) / g_pip
                          : (o_price - ask)    / g_pip;

      // Actualizar pico de ganancia (solo máximos)
      if(profit_pip > g_states[i].peak_profit_pip)
      {
         g_states[i].peak_profit_pip = profit_pip;
         g_states[i].peak_price      = fav_price;
      }
      double peak_pip = g_states[i].peak_profit_pip;

      //------------------------------------------------------------
      //  FASE 0 → 1: WAITING → BREAK-EVEN
      //  SL se mueve al precio de apertura
      //  A partir de aquí: imposible cerrar en pérdida
      //------------------------------------------------------------
      if(g_states[i].phase == PHASE_WAITING)
      {
         if(profit_pip >= InpBE_Pips)
         {
            double be = NormalizeDouble(o_price, _Digits);
            bool   ok = false;

            if(ptype == 0 && be > cur_sl + g_sym.Point())
               ok = g_trade.PositionModify(tk, be, cur_tp);
            else if(ptype == 1 && (cur_sl < g_sym.Point() || be < cur_sl - g_sym.Point()))
               ok = g_trade.PositionModify(tk, be, cur_tp);

            if(ok)
            {
               g_states[i].phase = PHASE_BREAKEVEN;
               Print("■ BE #", tk, " | SL=entrada ", DoubleToString(o_price,_Digits),
                     " | Profit=", DoubleToString(profit_pip,1), " pips");
            }
         }
         // Mercado en contra → bot espera, sin cierre, sin pánico
         continue;
      }

      //------------------------------------------------------------
      //  FASE 1 → 2: BREAKEVEN → TRAILING
      //------------------------------------------------------------
      if(g_states[i].phase == PHASE_BREAKEVEN)
      {
         if(profit_pip >= InpTrailStart)
         {
            g_states[i].phase = PHASE_TRAILING;
            Print("► TRAILING #", tk, " | Profit=", DoubleToString(profit_pip,1),
                  " pips | Gap=", DoubleToString(InpTrailGap,1), " pips");
         }
         else
            continue;
      }

      //------------------------------------------------------------
      //  FASE 2: TRAILING NORMAL
      //  Mueve SL con gap InpTrailGap, garantizando SL ≥ open_price
      //  Señal TP (RSI 50 o BB Middle) → transición a HARVEST
      //------------------------------------------------------------
      if(g_states[i].phase == PHASE_TRAILING)
      {
         SafeTrail(tk, ptype, fav_price, cur_sl, cur_tp, o_price, InpTrailGap);

         bool sig_rsi = (ptype == 0)
                        ? (rsi_prev < InpRSI_TPLevel && rsi_now >= InpRSI_TPLevel)
                        : (rsi_prev > InpRSI_TPLevel && rsi_now <= InpRSI_TPLevel);

         bool sig_bb  = (ptype == 0) ? (bid >= mid_now) : (ask <= mid_now);

         if(sig_rsi || sig_bb)
         {
            g_states[i].phase = PHASE_HARVEST;
            Print("◈ HARVEST #", tk,
                  " | Señal=", sig_rsi ? "RSI-50" : "BB-Middle",
                  " | Profit=", DoubleToString(profit_pip,1), " pips",
                  " | MicroGap=", DoubleToString(InpHarvestGap,1), " pips");
         }
         continue;
      }

      //------------------------------------------------------------
      //  FASE 3: HARVEST — micro-trailing + Retracement Guard
      //
      //  El mercado puede seguir corriendo.
      //  El bot NO cierra por código a menos que:
      //    → Retracement Guard se active (y profit > 0 SIEMPRE)
      //  El trailing stop cierra la posición de forma natural
      //------------------------------------------------------------
      if(g_states[i].phase == PHASE_HARVEST)
      {
         SafeTrail(tk, ptype, fav_price, cur_sl, cur_tp, o_price, InpHarvestGap);

         // Retracement Guard — SOLO si profit > 0 (jamás en pérdida)
         if(peak_pip >= InpRetraceMinPip && profit_pip > 0.0)
         {
            double retrace = ((peak_pip - profit_pip) / peak_pip) * 100.0;
            if(retrace >= InpRetracePct)
            {
               ForceClose(tk, StringFormat(
                  "RETRACEMENT | Pico=%.1f | Actual=%.1f | Ret=%.0f%%",
                  peak_pip, profit_pip, retrace));
               continue;
            }
         }

         // Log progreso cada 3 pips de nuevo pico
         if(peak_pip > g_states[i].last_log_pip + 3.0)
         {
            Print("🚀 HARVEST #", tk,
                  " Pico=",   DoubleToString(peak_pip,1),
                  " Actual=", DoubleToString(profit_pip,1), " pips",
                  " SL=",     DoubleToString(cur_sl,_Digits));
            g_states[i].last_log_pip = peak_pip;
         }
      }
   }
}

//==================================================================
//  SAFE TRAIL — trailing con garantía anti-pérdida absoluta
//  BUY : SL nunca baja del precio de apertura
//  SELL: SL nunca sube del precio de apertura
//==================================================================
void SafeTrail(ulong tk, int ptype, double fav_price,
               double cur_sl, double cur_tp,
               double open_price, double gap_pips)
{
   double gap = gap_pips * g_pip;

   if(ptype == 0) // BUY
   {
      double new_sl = NormalizeDouble(MathMax(fav_price - gap, open_price), _Digits);
      if(new_sl > cur_sl + g_sym.Point())
         g_trade.PositionModify(tk, new_sl, cur_tp);
   }
   else // SELL
   {
      double new_sl = NormalizeDouble(MathMin(fav_price + gap, open_price), _Digits);
      bool not_set  = (cur_sl < g_sym.Point());
      if(not_set || new_sl < cur_sl - g_sym.Point())
         g_trade.PositionModify(tk, new_sl, cur_tp);
   }
}

//==================================================================
//  EJECUTAR ORDEN (1er o 2do trade)
//==================================================================
void ExecuteOrder(ENUM_ORDER_TYPE otype, double price,
                  double mid, double rsi, bool is_second)
{
   if(TotalPositions() >= 2) return;

   double sl = 0.0;
   double tp = 0.0;
   if(InpSafetyTP_Pips > 0.0)
   {
      double d = InpSafetyTP_Pips * g_pip;
      tp = NormalizeDouble(otype == ORDER_TYPE_BUY ? price + d : price - d, _Digits);
   }

   bool ok = (otype == ORDER_TYPE_BUY)
             ? g_trade.Buy (InpLotSize, _Symbol, price, sl, tp, "RSI_BB_v5")
             : g_trade.Sell(InpLotSize, _Symbol, price, sl, tp, "RSI_BB_v5");

   if(ok)
   {
      ulong pos_tk = GetNewestTicket(otype);
      if(pos_tk > 0)
         AddTracking(pos_tk, price, otype == ORDER_TYPE_BUY ? 0 : 1);

      Print(is_second ? "▶▶" : "▶",
            otype == ORDER_TYPE_BUY ? " BUY " : " SELL ",
            is_second ? "(2/2)" : "(1/2)",
            " | Price=", DoubleToString(price, _Digits),
            " | RSI=",   DoubleToString(rsi,   2),
            " | BBmid=", DoubleToString(mid,   _Digits),
            " | Tk=",    GetNewestTicket(otype));
   }
   else
      Print("ERROR ", is_second ? "2do " : "1er ",
            EnumToString(otype), ": [",
            g_trade.ResultRetcode(), "] ",
            g_trade.ResultRetcodeDescription());
}

//==================================================================
//  CIERRE FORZADO — SOLO si profit > 0 (doble garantía)
//==================================================================
void ForceClose(ulong tk, string reason)
{
   if(!PositionSelectByTicket(tk)) return;
   double profit = PositionGetDouble(POSITION_PROFIT);

   if(profit <= 0.0)
   {
      Print("⚠ ForceClose bloqueado #", tk,
            " profit=", DoubleToString(profit,2), " — protección anti-pérdida activa");
      return;
   }

   if(g_trade.PositionClose(tk))
   {
      Print("✔ CERRADO #", tk,
            " | P&L=", DoubleToString(profit,2),
            " | ", reason);
      RemoveTracking(tk);
   }
   else
      Print("✘ ERROR cerrando #", tk, " [", g_trade.ResultRetcode(), "] ",
            g_trade.ResultRetcodeDescription());
}

//==================================================================
//  SINCRONIZAR TRACKING
//==================================================================
void SyncTracking()
{
   // Limpiar tickets cerrados
   for(int i = 0; i < MAX_TRACKED; i++)
   {
      if(g_states[i].ticket == 0) continue;
      if(!PositionSelectByTicket(g_states[i].ticket))
         ResetState(i);
   }
   // Detectar posiciones no rastreadas (ej: reinicio del EA)
   int total = PositionsTotal();
   for(int j = 0; j < total; j++)
   {
      ulong tk = PositionGetTicket(j);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL)  != _Symbol)        continue;
      if(PositionGetInteger(POSITION_MAGIC)  != InpMagicNumber) continue;
      if(FindIdx(tk) == -1)
      {
         int    pt  = (int)PositionGetInteger(POSITION_TYPE);
         double opx = PositionGetDouble(POSITION_PRICE_OPEN);
         AddTracking(tk, opx, pt);
      }
   }
}

//==================================================================
//  AGREGAR TRACKING
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
         return;
      }
   }
}

//==================================================================
//  ELIMINAR TRACKING
//==================================================================
void RemoveTracking(ulong tk)
{
   int idx = FindIdx(tk);
   if(idx >= 0) ResetState(idx);
}

//==================================================================
//  RESET SLOT
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
//  BUSCAR ÍNDICE
//==================================================================
int FindIdx(ulong tk)
{
   for(int i = 0; i < MAX_TRACKED; i++)
      if(g_states[i].ticket == tk) return i;
   return -1;
}

//==================================================================
//  TICKET MÁS RECIENTE (no rastreado aún)
//==================================================================
ulong GetNewestTicket(ENUM_ORDER_TYPE otype)
{
   ulong    best = 0;
   datetime best_t = 0;
   int      total = PositionsTotal();

   for(int i = 0; i < total; i++)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL)  != _Symbol)        continue;
      if(PositionGetInteger(POSITION_MAGIC)  != InpMagicNumber) continue;

      ENUM_POSITION_TYPE pt = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if(otype == ORDER_TYPE_BUY  && pt != POSITION_TYPE_BUY)  continue;
      if(otype == ORDER_TYPE_SELL && pt != POSITION_TYPE_SELL) continue;
      if(FindIdx(tk) != -1) continue; // ya rastreado

      datetime t = (datetime)PositionGetInteger(POSITION_TIME);
      if(t >= best_t){ best_t = t; best = tk; }
   }
   return best;
}

//==================================================================
//  TOTAL POSICIONES DEL BOT
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
//  DETECTAR FILLING MODE COMPATIBLE
//==================================================================
ENUM_ORDER_TYPE_FILLING DetectFilling()
{
   uint fm = (uint)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((fm & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK) return ORDER_FILLING_FOK;
   if((fm & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC) return ORDER_FILLING_IOC;
   return ORDER_FILLING_RETURN;
}
//+------------------------------------------------------------------+
