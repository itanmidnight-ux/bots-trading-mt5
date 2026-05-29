//+------------------------------------------------------------------+
//|              RSI_BB_GoldBot_v6.mq5                               |
//|   Bot Algorítmico Final — XAUUSD | RSI(1) + BB(14,0.111)        |
//|                                                                  |
//|  ═══ SEÑALES DE ENTRADA ═══════════════════════════════════════ |
//|    RSI ≤  9  → ZONA BUY  exclusiva (solo compras)               |
//|    RSI ≥ 85  → ZONA SELL exclusiva (solo ventas)                |
//|    RSI entre 9 y 85 → ZONA MUERTA — cero operaciones           |
//|    2 trades por señal separados por 3 segundos                  |
//|                                                                  |
//|  ═══ REGLAS ABSOLUTAS ═════════════════════════════════════════ |
//|    ✦ JAMÁS cierra con pérdida por código                        |
//|    ✦ Smart TP solo actúa si ganancia ≥ $9 USD                   |
//|    ✦ Umbrales expresados en USD (correcto para XAUUSD)          |
//|                                                                  |
//|  ═══ FILTROS DE SESIÓN ════════════════════════════════════════ |
//|    Viernes : sin nuevas entradas 3h antes del cierre            |
//|              posiciones existentes cambian a Harvest (ajustado) |
//|    Lunes   : sin entradas hasta la hora configurada             |
//|    Fin de semana: sin operaciones                               |
//|                                                                  |
//|  ═══ FASES SMART PATIENT TP ═══════════════════════════════════ |
//|    FASE 0 · WAITING   : sin SL, mercado libre                   |
//|    FASE 1 · BREAKEVEN : SL = entrada (no más pérdidas posibles) |
//|    FASE 2 · TRAILING  : trailing activo en USD                  |
//|    FASE 3 · HARVEST   : micro-trailing al detectar señal TP     |
//|    RETRACEMENT GUARD  : cierra si retrocede X% del pico        |
//|                         SOLO si profit ≥ $9 USD                 |
//+------------------------------------------------------------------+
#property copyright "RSI BB GoldBot v6.0"
#property link      ""
#property version   "6.00"
#property description "XAUUSD | RSI(1)+BB(14,0.111) | BUY≤9 | SELL≥85 | SmartTP $9min"

#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>

//==================================================================
//  PARÁMETROS DE ENTRADA
//==================================================================

input group "═══ RSI — Niveles de Señal ═══"
input int    InpRSI_Period     = 1;        // RSI Período
input double InpRSI_BuyLevel  = 9.0;      // RSI BUY  (≤ → zona compra)
input double InpRSI_SellLevel = 85.0;     // RSI SELL (≥ → zona venta)
input double InpRSI_TPLevel   = 50.0;     // RSI nivel señal TP (activa Harvest)

input group "═══ BOLLINGER BANDS ═══"
input int    InpBB_Period     = 14;        // BB Período
input double InpBB_Deviation  = 0.111;    // BB Desviación
input int    InpBB_Shift      = 0;        // BB Desplazamiento

input group "═══ ÓRDENES ═══"
input double InpLotSize          = 0.01;  // Lote por trade
input long   InpMagicNumber      = 20250601; // Magic Number
input int    InpSecondTradeDelay = 3;     // Segundos entre 1er y 2do trade
input bool   InpBBDirFilter      = true;  // Filtro BB Middle (precio del lado correcto)
input bool   InpNewBarEntry      = true;  // Solo entrar en nueva vela

input group "═══ FASE 0→1 · BREAK-EVEN (en USD) ═══"
input double InpBE_USD         = 1.50;   // Mover SL a entrada al ganar $X USD

input group "═══ FASE 1→2 · TRAILING (en USD) ═══"
input double InpTrailStart_USD = 4.00;   // Activar trailing al ganar $X USD
input double InpTrailGap_USD   = 1.50;   // Gap trailing: SL a $X del precio actual

input group "═══ FASE 2→3 · HARVEST (en USD) ═══"
input double InpHarvestGap_USD = 0.60;   // Gap micro-trailing Harvest ($X del precio)

input group "═══ SMART TP — MÍNIMO $9 USD ═══"
input double InpMinProfitUSD   = 9.00;   // Smart TP actúa SOLO si profit ≥ $X USD
input double InpRetracePct     = 40.0;   // Cerrar si retrocede X% del pico
input double InpRetraceMinUSD  = 9.00;   // Pico mínimo en USD para activar guard

input group "═══ RED DE SEGURIDAD (servidor) ═══"
input double InpSafetyTP_USD   = 60.00;  // TP fijo en servidor ($X USD, 0=desactivado)

input group "═══ FILTROS DE SESIÓN ═══"
input int    InpFridayCloseHour = 21;    // Hora de cierre Gold viernes (horario servidor)
// El bot dejará de abrir trades 3h antes de esta hora
input int    InpMondayStartHour = 2;     // No operar hasta esta hora los lunes

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
   int    pos_type;          // 0=BUY, 1=SELL
   double open_price;
   double peak_profit_usd;   // máxima ganancia vista en USD
   double peak_price;        // precio más favorable registrado
   double last_log_usd;      // último pico logueado (anti-spam)
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

// Control del 2do trade programado
bool            g_second_pending  = false;
datetime        g_second_open_at  = 0;
ENUM_ORDER_TYPE g_second_type     = ORDER_TYPE_BUY;

// Flag para avisar una sola vez del filtro de sesión activo
bool g_session_warned = false;

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

   // RSI(1) → Weighted Close (HLCC/4)
   g_rsi_h = iRSI(_Symbol, _Period, InpRSI_Period, PRICE_WEIGHTED);
   if(g_rsi_h == INVALID_HANDLE)
   {
      Print("ERROR RSI: ", GetLastError());
      return INIT_FAILED;
   }

   // BB(14, 0.111) → Weighted Close (HLCC/4) | buf0=Mid buf1=Up buf2=Dn
   g_bb_h = iBands(_Symbol, _Period, InpBB_Period, InpBB_Shift,
                   InpBB_Deviation, PRICE_WEIGHTED);
   if(g_bb_h == INVALID_HANDLE)
   {
      Print("ERROR BB: ", GetLastError());
      return INIT_FAILED;
   }

   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(20);
   g_trade.SetTypeFilling(DetectFilling());
   g_trade.LogLevel(LOG_LEVEL_ERRORS);

   for(int i = 0; i < MAX_TRACKED; i++) ResetState(i);
   g_second_pending = false;
   g_session_warned = false;

   // Verificar valores del símbolo para el log
   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

   Print("╔══════════════════════════════════════════════════╗");
   Print("║      RSI BB GoldBot v6.0 — INICIADO              ║");
   Print("╠══════════════════════════════════════════════════╣");
   Print("║  ", _Symbol, " | TF: ", EnumToString(_Period));
   Print("║  BUY≤", DoubleToString(InpRSI_BuyLevel,1),
         " | SELL≥", DoubleToString(InpRSI_SellLevel,1),
         " | TP@",   DoubleToString(InpRSI_TPLevel,1));
   Print("║  Lote=", DoubleToString(InpLotSize,2),
         " | TickVal=", DoubleToString(tv,4),
         " | TickSz=",  DoubleToString(ts,5));
   Print("║  BE=$",    DoubleToString(InpBE_USD,2),
         " | Trail=$", DoubleToString(InpTrailStart_USD,2),
         "/gap$",      DoubleToString(InpTrailGap_USD,2),
         " | Harvest=$", DoubleToString(InpHarvestGap_USD,2));
   Print("║  SmartTP min=$", DoubleToString(InpMinProfitUSD,2),
         " | Retrace=",  DoubleToString(InpRetracePct,0), "%");
   Print("║  Viernes cierre=", InpFridayCloseHour,
         ":00 | Lunes inicio=", InpMondayStartHour, ":00");
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

   // Leer indicadores (3 barras para detección de cruces)
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
   //  PASO 2 — Smart Patient TP (cada tick, prioridad absoluta)
   //================================================================
   PatientTPManager(rsi_now, rsi_prev, mid_now, ask, bid);

   //================================================================
   //  PASO 3 — 2do trade programado (disparo por tiempo, 3 segundos)
   //================================================================
   if(g_second_pending && TimeCurrent() >= g_second_open_at)
   {
      g_second_pending = false;

      // Verificar sesión antes de abrir el 2do trade
      if(IsNewTradesAllowed() && TotalPositions() < 2)
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
            Print("2do trade cancelado: RSI salió de zona (", DoubleToString(rsi_now,1), ")");
      }
      else
         Print("2do trade cancelado: filtro de sesión activo o máx. trades alcanzado");
   }

   //================================================================
   //  PASO 4 — Filtro nueva vela (para señales de entrada)
   //================================================================
   if(InpNewBarEntry)
   {
      datetime t0 = iTime(_Symbol, _Period, 0);
      if(t0 == g_last_bar) return;
      g_last_bar = t0;
   }

   //================================================================
   //  PASO 5 — SEÑALES DE ENTRADA
   //  ZONA MUERTA absoluta: RSI entre 9 y 85 → cero operaciones
   //================================================================
   if(!IsNewTradesAllowed()) return;
   if(TotalPositions() >= 2) return;
   if(g_second_pending)      return;

   //--- ZONA BUY: RSI ≤ 9
   if(rsi_now <= InpRSI_BuyLevel)
   {
      if(InpBBDirFilter && ask >= mid_now) return;

      ExecuteOrder(ORDER_TYPE_BUY, ask, mid_now, rsi_now, false);

      if(TotalPositions() < 2)
      {
         g_second_pending = true;
         g_second_open_at = TimeCurrent() + (datetime)InpSecondTradeDelay;
         g_second_type    = ORDER_TYPE_BUY;
         Print("⏱ 2do BUY en ", InpSecondTradeDelay, " seg | RSI=", DoubleToString(rsi_now,1));
      }
   }
   //--- ZONA SELL: RSI ≥ 85
   else if(rsi_now >= InpRSI_SellLevel)
   {
      if(InpBBDirFilter && bid <= mid_now) return;

      ExecuteOrder(ORDER_TYPE_SELL, bid, mid_now, rsi_now, false);

      if(TotalPositions() < 2)
      {
         g_second_pending = true;
         g_second_open_at = TimeCurrent() + (datetime)InpSecondTradeDelay;
         g_second_type    = ORDER_TYPE_SELL;
         Print("⏱ 2do SELL en ", InpSecondTradeDelay, " seg | RSI=", DoubleToString(rsi_now,1));
      }
   }
   // RSI entre 9 y 85 → ZONA MUERTA, sin acción
}

//==================================================================
//  SMART PATIENT TP MANAGER — cada tick
//  Garantías: JAMÁS cierra en pérdida | Smart TP requiere ≥ $9
//==================================================================
void PatientTPManager(double rsi_now, double rsi_prev,
                      double mid_now, double ask, double bid)
{
   // Pre-cierre de viernes: forzar modo Harvest en posiciones TRAILING
   bool friday_pre = IsFridayPreClose();

   for(int i = 0; i < MAX_TRACKED; i++)
   {
      if(g_states[i].ticket == 0 || g_states[i].phase == PHASE_CLOSED)
         continue;

      ulong  tk      = g_states[i].ticket;
      int    ptype   = g_states[i].pos_type;
      double o_price = g_states[i].open_price;

      if(!PositionSelectByTicket(tk)) continue;
      double cur_sl     = PositionGetDouble(POSITION_SL);
      double cur_tp     = PositionGetDouble(POSITION_TP);
      double profit_usd = PositionGetDouble(POSITION_PROFIT); // ganancia en USD

      double fav_price = (ptype == 0) ? bid : ask;

      // Actualizar pico de ganancia en USD (solo máximos positivos)
      if(profit_usd > g_states[i].peak_profit_usd)
      {
         g_states[i].peak_profit_usd = profit_usd;
         g_states[i].peak_price      = fav_price;
      }
      double peak_usd = g_states[i].peak_profit_usd;

      //------------------------------------------------------------
      //  FASE 0 → 1: WAITING → BREAK-EVEN
      //  Cuando profit ≥ InpBE_USD → SL al precio de apertura
      //  A partir de aquí: posición NO puede cerrar con pérdida
      //------------------------------------------------------------
      if(g_states[i].phase == PHASE_WAITING)
      {
         if(profit_usd >= InpBE_USD)
         {
            double be = NormalizeDouble(o_price, _Digits);
            bool ok   = false;

            if(ptype == 0 && be > cur_sl + g_sym.Point())
               ok = g_trade.PositionModify(tk, be, cur_tp);
            else if(ptype == 1 && (cur_sl < g_sym.Point() || be < cur_sl - g_sym.Point()))
               ok = g_trade.PositionModify(tk, be, cur_tp);

            if(ok)
            {
               g_states[i].phase = PHASE_BREAKEVEN;
               Print("■ BREAK-EVEN #", tk,
                     " | SL=", DoubleToString(o_price, _Digits),
                     " | P&L=$", DoubleToString(profit_usd, 2));
            }
         }
         // Mercado en contra → bot espera pacientemente, sin acción
         continue;
      }

      //------------------------------------------------------------
      //  FASE 1 → 2: BREAKEVEN → TRAILING
      //------------------------------------------------------------
      if(g_states[i].phase == PHASE_BREAKEVEN)
      {
         if(profit_usd >= InpTrailStart_USD)
         {
            g_states[i].phase = PHASE_TRAILING;
            Print("► TRAILING #", tk,
                  " | P&L=$", DoubleToString(profit_usd, 2),
                  " | Gap=$",  DoubleToString(InpTrailGap_USD, 2));
         }
         else
            continue;
      }

      //------------------------------------------------------------
      //  FASE 2: TRAILING NORMAL
      //  Viernes pre-cierre: pasar a HARVEST inmediatamente
      //  Señal TP (RSI 50 o BB Middle) → HARVEST
      //------------------------------------------------------------
      if(g_states[i].phase == PHASE_TRAILING)
      {
         // Viernes: accelerar a Harvest para capturar profit antes del cierre
         if(friday_pre)
         {
            g_states[i].phase = PHASE_HARVEST;
            Print("◈ HARVEST FORZADO (viernes pre-cierre) #", tk,
                  " | P&L=$", DoubleToString(profit_usd,2));
         }
         else
         {
            SafeTrail(tk, ptype, fav_price, cur_sl, cur_tp, o_price, InpTrailGap_USD);

            bool sig_rsi = (ptype == 0)
                           ? (rsi_prev < InpRSI_TPLevel && rsi_now >= InpRSI_TPLevel)
                           : (rsi_prev > InpRSI_TPLevel && rsi_now <= InpRSI_TPLevel);

            bool sig_bb  = (ptype == 0) ? (bid >= mid_now) : (ask <= mid_now);

            if(sig_rsi || sig_bb)
            {
               g_states[i].phase = PHASE_HARVEST;
               Print("◈ HARVEST #", tk,
                     " | Señal=", sig_rsi ? "RSI-50" : "BB-Mid",
                     " | P&L=$",  DoubleToString(profit_usd,2));
            }
         }
         continue;
      }

      //------------------------------------------------------------
      //  FASE 3: HARVEST — micro-trailing máximo
      //  El mercado corre libremente — el bot NO cierra por código
      //  EXCEPCIÓN (Retracement Guard):
      //    → Solo actúa si profit ≥ $9 USD (InpMinProfitUSD)
      //    → Solo actúa si pico ≥ InpRetraceMinUSD
      //    → JAMÁS cierra si profit ≤ 0
      //------------------------------------------------------------
      if(g_states[i].phase == PHASE_HARVEST)
      {
         // Gap más ajustado en viernes pre-cierre
         double gap_usd = friday_pre
                          ? InpHarvestGap_USD * 0.5
                          : InpHarvestGap_USD;
         SafeTrail(tk, ptype, fav_price, cur_sl, cur_tp, o_price, gap_usd);

         // Retracement Guard — triple verificación antes de cerrar
         if(peak_usd   >= InpRetraceMinUSD  &&   // pico suficiente
            profit_usd >= InpMinProfitUSD   &&   // ganancia mínima $9 cumplida
            profit_usd >  0.0)                    // jamás en pérdida
         {
            double retrace = ((peak_usd - profit_usd) / peak_usd) * 100.0;
            if(retrace >= InpRetracePct)
            {
               ForceClose(tk, StringFormat(
                  "RETRACEMENT | Pico=$%.2f | Actual=$%.2f | Ret=%.0f%%",
                  peak_usd, profit_usd, retrace));
               continue;
            }
         }

         // Log de progreso (cada $2 de nuevo pico, anti-spam)
         if(peak_usd > g_states[i].last_log_usd + 2.0)
         {
            Print("🚀 HARVEST #", tk,
                  " | Pico=$",   DoubleToString(peak_usd,  2),
                  " | Actual=$", DoubleToString(profit_usd,2),
                  " | SL=",      DoubleToString(cur_sl,_Digits));
            g_states[i].last_log_usd = peak_usd;
         }
      }
   }
}

//==================================================================
//  SAFE TRAIL — USD gap convertido a distancia de precio
//  Garantía: SL nunca cruza el precio de apertura (protección total)
//==================================================================
void SafeTrail(ulong tk,     int ptype,     double fav_price,
               double cur_sl, double cur_tp,
               double open_price, double gap_usd)
{
   double gap_price = USDtoPriceGap(gap_usd);
   if(gap_price < g_sym.Point()) return;

   if(ptype == 0) // BUY: SL sube, nunca baja del open
   {
      double raw    = fav_price - gap_price;
      double new_sl = NormalizeDouble(MathMax(raw, open_price), _Digits);
      if(new_sl > cur_sl + g_sym.Point())
         g_trade.PositionModify(tk, new_sl, cur_tp);
   }
   else // SELL: SL baja, nunca sube del open
   {
      double raw    = fav_price + gap_price;
      double new_sl = NormalizeDouble(MathMin(raw, open_price), _Digits);
      bool not_set  = (cur_sl < g_sym.Point());
      if(not_set || new_sl < cur_sl - g_sym.Point())
         g_trade.PositionModify(tk, new_sl, cur_tp);
   }
}

//==================================================================
//  CONVERTIR USD A DISTANCIA DE PRECIO
//  Usa tick value y tick size del símbolo (compatible con XAUUSD y Forex)
//==================================================================
double USDtoPriceGap(double usd_amount)
{
   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE); // USD por tick, 1 lot
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);  // precio por tick
   if(tv < 1e-10 || InpLotSize < 1e-10) return g_pip;

   double lot_tick_val = tv * InpLotSize; // USD por tick para nuestro lote
   if(lot_tick_val < 1e-10) return g_pip;

   return (usd_amount * ts) / lot_tick_val;
}

//==================================================================
//  EJECUTAR ORDEN
//==================================================================
void ExecuteOrder(ENUM_ORDER_TYPE otype, double price,
                  double mid, double rsi, bool is_second)
{
   if(TotalPositions() >= 2) return;

   double sl = 0.0;
   double tp = 0.0;
   if(InpSafetyTP_USD > 0.0)
   {
      double tp_dist = USDtoPriceGap(InpSafetyTP_USD);
      tp = NormalizeDouble(otype == ORDER_TYPE_BUY
                           ? price + tp_dist
                           : price - tp_dist, _Digits);
   }

   bool ok = (otype == ORDER_TYPE_BUY)
             ? g_trade.Buy (InpLotSize, _Symbol, price, sl, tp, "GoldBot_v6")
             : g_trade.Sell(InpLotSize, _Symbol, price, sl, tp, "GoldBot_v6");

   if(ok)
   {
      ulong pos_tk = GetNewestTicket(otype);
      if(pos_tk > 0)
         AddTracking(pos_tk, price, otype == ORDER_TYPE_BUY ? 0 : 1);

      Print(is_second ? "▶▶" : "▶",
            otype == ORDER_TYPE_BUY ? " BUY " : " SELL ",
            is_second ? "(2/2)" : "(1/2)",
            " | Price=",    DoubleToString(price,_Digits),
            " | RSI=",      DoubleToString(rsi,1),
            " | BBmid=",    DoubleToString(mid, _Digits),
            " | SafetyTP=", DoubleToString(tp,  _Digits));
   }
   else
      Print("ERROR ", is_second ? "2do " : "1er ",
            EnumToString(otype), ": [",
            g_trade.ResultRetcode(), "] ",
            g_trade.ResultRetcodeDescription());
}

//==================================================================
//  CIERRE FORZADO (Retracement Guard) — siempre con profit ≥ $9
//==================================================================
void ForceClose(ulong tk, string reason)
{
   if(!PositionSelectByTicket(tk)) return;
   double profit = PositionGetDouble(POSITION_PROFIT);

   // Doble verificación: jamás cerramos con pérdida ni por debajo del mínimo
   if(profit < InpMinProfitUSD)
   {
      Print("⚠ ForceClose bloqueado #", tk,
            " | P&L=$", DoubleToString(profit,2),
            " | Mínimo requerido=$", DoubleToString(InpMinProfitUSD,2));
      return;
   }

   if(g_trade.PositionClose(tk))
   {
      Print("✔ CERRADO #", tk,
            " | P&L=$",   DoubleToString(profit,2),
            " | Razón: ", reason);
      RemoveTracking(tk);
   }
   else
      Print("✘ ERROR cerrando #", tk, " [",
            g_trade.ResultRetcode(), "] ",
            g_trade.ResultRetcodeDescription());
}

//==================================================================
//  FILTRO DE SESIÓN — determina si se permiten nuevas entradas
//==================================================================
bool IsNewTradesAllowed()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int dow = dt.day_of_week;  // 0=Dom 1=Lun 2=Mar 3=Mié 4=Jue 5=Vie 6=Sáb

   // Fin de semana: sin operaciones
   if(dow == 0 || dow == 6)
   {
      if(!g_session_warned)
      {
         Print("⏸ Fin de semana — sin nuevas operaciones");
         g_session_warned = true;
      }
      return false;
   }
   g_session_warned = false;

   // Lunes: esperar hasta InpMondayStartHour para evitar la apertura volátil
   if(dow == 1 && dt.hour < InpMondayStartHour)
   {
      Print("⏸ Lunes apertura — esperando hasta las ",
            InpMondayStartHour, ":00 (hora servidor) | Ahora: ",
            dt.hour, ":", StringFormat("%02d", dt.min));
      return false;
   }

   // Viernes: sin nuevas entradas en las 3 horas antes del cierre
   if(dow == 5)
   {
      int close_min = InpFridayCloseHour * 60;
      int cur_min   = dt.hour * 60 + dt.min;
      if(cur_min >= close_min - 180)
      {
         Print("⏸ Viernes pre-cierre — sin nuevas entradas | ",
               (close_min - cur_min), " min para cierre");
         return false;
      }
   }

   return true;
}

//==================================================================
//  DETECTAR PRE-CIERRE DE VIERNES
//  Activa Harvest en posiciones abiertas para capturar ganancias
//==================================================================
bool IsFridayPreClose()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(dt.day_of_week != 5) return false;
   int close_min = InpFridayCloseHour * 60;
   int cur_min   = dt.hour * 60 + dt.min;
   return (cur_min >= close_min - 180);
}

//==================================================================
//  SINCRONIZAR TRACKING
//==================================================================
void SyncTracking()
{
   for(int i = 0; i < MAX_TRACKED; i++)
   {
      if(g_states[i].ticket == 0) continue;
      if(!PositionSelectByTicket(g_states[i].ticket))
         ResetState(i);
   }
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
         g_states[i].peak_profit_usd = 0.0;
         g_states[i].peak_price      = open_px;
         g_states[i].last_log_usd    = 0.0;
         Print("TRACKING #", tk, " | ", (ptype==0?"BUY":"SELL"),
               " | Open=", DoubleToString(open_px,_Digits));
         return;
      }
   }
   Print("⚠ Tracking lleno");
}

void RemoveTracking(ulong tk)
{
   int idx = FindIdx(tk);
   if(idx >= 0) ResetState(idx);
}

void ResetState(int i)
{
   g_states[i].ticket          = 0;
   g_states[i].phase           = PHASE_CLOSED;
   g_states[i].pos_type        = -1;
   g_states[i].open_price      = 0.0;
   g_states[i].peak_profit_usd = 0.0;
   g_states[i].peak_price      = 0.0;
   g_states[i].last_log_usd    = 0.0;
}

int FindIdx(ulong tk)
{
   for(int i = 0; i < MAX_TRACKED; i++)
      if(g_states[i].ticket == tk) return i;
   return -1;
}

ulong GetNewestTicket(ENUM_ORDER_TYPE otype)
{
   ulong    best   = 0;
   datetime best_t = 0;
   int      total  = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL)  != _Symbol)        continue;
      if(PositionGetInteger(POSITION_MAGIC)  != InpMagicNumber) continue;
      ENUM_POSITION_TYPE pt = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if(otype == ORDER_TYPE_BUY  && pt != POSITION_TYPE_BUY)  continue;
      if(otype == ORDER_TYPE_SELL && pt != POSITION_TYPE_SELL) continue;
      if(FindIdx(tk) != -1) continue;
      datetime t = (datetime)PositionGetInteger(POSITION_TIME);
      if(t >= best_t){ best_t = t; best = tk; }
   }
   return best;
}

int TotalPositions()
{
   int count = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL)  != _Symbol)        continue;
      if(PositionGetInteger(POSITION_MAGIC)  != InpMagicNumber) continue;
      count++;
   }
   return count;
}

ENUM_ORDER_TYPE_FILLING DetectFilling()
{
   uint fm = (uint)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((fm & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK) return ORDER_FILLING_FOK;
   if((fm & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC) return ORDER_FILLING_IOC;
   return ORDER_FILLING_RETURN;
}
//+------------------------------------------------------------------+
