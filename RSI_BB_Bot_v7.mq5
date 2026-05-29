//+------------------------------------------------------------------+
//|              RSI_BB_Bot_v7.mq5                                   |
//|   Bot Algorítmico Universal — Todos los símbolos MT5             |
//|   RSI(1,HLCC/4) + BB(14,0.111,HLCC/4)                          |
//|                                                                  |
//|  ═══ SEÑALES DE ENTRADA ════════════════════════════════════════|
//|    RSI ≤  9  → ZONA BUY  exclusiva                              |
//|    RSI ≥ 85  → ZONA SELL exclusiva                              |
//|    RSI entre 9 y 85 → ZONA MUERTA, cero operaciones            |
//|    2 trades por señal separados por 3 segundos                  |
//|                                                                  |
//|  ═══ SISTEMA SMART TP — DOS FASES ══════════════════════════════|
//|    FASE 1 · WAITING  : sin SL, mercado completamente libre      |
//|                        NO se cierra por ningún motivo            |
//|                        Espera UNO de estos dos eventos:         |
//|                        A) RSI cruza el nivel 50                 |
//|                        B) Ganancia supera InpMinProfitUSD       |
//|    FASE 2 · HARVEST  : micro-trailing activo                    |
//|                        Retracement Guard SOLO si profit ≥ $min  |
//|                        Trailing stop cierra de forma natural    |
//|                                                                  |
//|  ═══ REGLAS ABSOLUTAS ══════════════════════════════════════════|
//|    ✦ JAMÁS cierra antes de RSI-50 o ganancia ≥ InpMinProfitUSD  |
//|    ✦ JAMÁS cierra con pérdida por código                        |
//|    ✦ Compatible con TODOS los símbolos (Forex, Oro, Índices…)   |
//|                                                                  |
//|  ═══ FILTROS DE SESIÓN ═════════════════════════════════════════|
//|    Viernes  : sin nuevas entradas 3h antes del cierre           |
//|               posiciones existentes → Harvest acelerado         |
//|    Lunes    : sin entradas antes de InpMondayStartHour          |
//|    Fin de semana: sin operaciones                               |
//+------------------------------------------------------------------+
#property copyright "RSI BB Bot v7.0 — Universal"
#property link      ""
#property version   "7.00"
#property description "RSI(1)+BB(14,0.111) | Universal | BUY≤9 | SELL≥85 | SmartTP"

#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>

//==================================================================
//  PARÁMETROS DE ENTRADA
//==================================================================

input group "═══ RSI ═══"
input int    InpRSI_Period     = 1;        // RSI Período
input double InpRSI_BuyLevel  = 9.0;      // RSI BUY  (≤ → zona compra)
input double InpRSI_SellLevel = 85.0;     // RSI SELL (≥ → zona venta)
input double InpRSI_TPLevel   = 50.0;     // RSI nivel TP (dispara Harvest)

input group "═══ BOLLINGER BANDS ═══"
input int    InpBB_Period     = 14;        // BB Período
input double InpBB_Deviation  = 0.111;    // BB Desviación
input int    InpBB_Shift      = 0;        // BB Desplazamiento

input group "═══ ÓRDENES ═══"
input double InpLotSize          = 0.01;  // Lote por trade
input long   InpMagicNumber      = 20250601;
input int    InpSecondTradeDelay = 3;     // Segundos entre 1er y 2do trade
input bool   InpBBDirFilter      = true;  // Filtro: precio del lado correcto de BB Middle
input bool   InpNewBarEntry      = true;  // Solo entrar en nueva vela

input group "═══ SMART TP — CONDICIONES DE CIERRE ═══"
// El bot espera hasta que ocurra UNO de estos dos eventos:
//   Evento A: RSI cruza el nivel 50 (señal TP de la estrategia)
//   Evento B: La ganancia supera InpMinProfitUSD
// Antes de eso: JAMÁS cierra la posición
input double InpMinProfitUSD   = 9.00;   // Mínimo USD para activar Smart TP
input double InpRetracePct     = 40.0;   // Retracement Guard: cerrar si retrocede X%
input double InpRetraceMinUSD  = 9.00;   // Pico mínimo en USD para activar guard

input group "═══ HARVEST — MICRO-TRAILING ═══"
input double InpHarvestGap_USD = 0.80;   // Gap del micro-trailing en USD

input group "═══ RED DE SEGURIDAD (servidor) ═══"
input double InpSafetyTP_USD   = 60.00;  // TP fijo servidor ($USD, 0=off)

input group "═══ FILTROS DE SESIÓN ═══"
input int    InpFridayCloseHour = 21;    // Hora cierre mercado viernes (hora servidor)
input int    InpMondayStartHour = 2;     // No operar lunes antes de esta hora

//==================================================================
//  FASES DEL SMART TP (solo 2)
//==================================================================
#define PHASE_WAITING  0   // Sin SL — esperando Evento A o B
#define PHASE_HARVEST  1   // Micro-trailing activo — cazando el pico
#define PHASE_CLOSED  -1

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
   double peak_profit_usd;
   double peak_price;
   double last_log_usd;
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

bool            g_second_pending  = false;
datetime        g_second_open_at  = 0;
ENUM_ORDER_TYPE g_second_type     = ORDER_TYPE_BUY;

//==================================================================
//  INICIALIZACIÓN
//==================================================================
int OnInit()
{
   if(!g_sym.Name(_Symbol))
   {
      Print("ERROR: símbolo inválido"); return INIT_FAILED;
   }
   g_sym.RefreshRates();

   // Calcular pip de forma universal (Forex 5d, JPY 3d, Gold/Índices 2d, etc.)
   int digs = (int)g_sym.Digits();
   g_pip    = (digs == 5 || digs == 3) ? g_sym.Point() * 10.0 : g_sym.Point();

   // RSI(1) — Weighted Close (HLCC/4)
   g_rsi_h = iRSI(_Symbol, _Period, InpRSI_Period, PRICE_WEIGHTED);
   if(g_rsi_h == INVALID_HANDLE){ Print("ERROR RSI: ", GetLastError()); return INIT_FAILED; }

   // BB(14, 0.111) — Weighted Close (HLCC/4) | buf0=Mid buf1=Up buf2=Dn
   g_bb_h = iBands(_Symbol, _Period, InpBB_Period, InpBB_Shift,
                   InpBB_Deviation, PRICE_WEIGHTED);
   if(g_bb_h == INVALID_HANDLE){ Print("ERROR BB: ", GetLastError()); return INIT_FAILED; }

   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(20);
   g_trade.SetTypeFilling(DetectFilling());
   g_trade.LogLevel(LOG_LEVEL_ERRORS);

   for(int i = 0; i < MAX_TRACKED; i++) ResetState(i);
   g_second_pending = false;

   // Verificar que USDtoPriceGap funcione correctamente para este símbolo
   double test_gap = USDtoPriceGap(1.0);
   Print("╔══════════════════════════════════════════════════════╗");
   Print("║      RSI BB Bot v7.0 — UNIVERSAL — INICIADO          ║");
   Print("╠══════════════════════════════════════════════════════╣");
   Print("║  Símbolo: ", _Symbol, " | TF: ", EnumToString(_Period),
         " | Digits: ", digs);
   Print("║  Pip: ", DoubleToString(g_pip,_Digits),
         " | $1 USD → ", DoubleToString(test_gap,_Digits), " precio");
   Print("║  BUY≤", DoubleToString(InpRSI_BuyLevel,1),
         " | SELL≥", DoubleToString(InpRSI_SellLevel,1),
         " | TP@",   DoubleToString(InpRSI_TPLevel,1));
   Print("║  Smart TP mín=$", DoubleToString(InpMinProfitUSD,2),
         " | Harvest gap=$", DoubleToString(InpHarvestGap_USD,2),
         " | Retrace=",      DoubleToString(InpRetracePct,0), "%");
   Print("║  Viernes stop=", InpFridayCloseHour,
         ":00-3h | Lunes inicio=", InpMondayStartHour, ":00");
   Print("╚══════════════════════════════════════════════════════╝");

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

   // Paso 1: sincronizar tracking
   SyncTracking();

   // Paso 2: gestión de posiciones abiertas (cada tick — prioridad absoluta)
   SmartTPManager(rsi_now, rsi_prev, mid_now, ask, bid);

   // Paso 3: segundo trade programado (temporizador de 3 segundos)
   if(g_second_pending && TimeCurrent() >= g_second_open_at)
   {
      g_second_pending = false;
      if(IsNewTradesAllowed() && TotalPositions() < 2)
      {
         bool rsi_ok = (g_second_type == ORDER_TYPE_BUY)
                       ? (rsi_now <= InpRSI_BuyLevel)
                       : (rsi_now >= InpRSI_SellLevel);
         if(rsi_ok)
         {
            double px = (g_second_type == ORDER_TYPE_BUY) ? ask : bid;
            ExecuteOrder(g_second_type, px, mid_now, rsi_now, true);
         }
         else
            Print("2do trade cancelado — RSI fuera de zona: ", DoubleToString(rsi_now,1));
      }
   }

   // Paso 4: filtro de nueva vela
   if(InpNewBarEntry)
   {
      datetime t0 = iTime(_Symbol, _Period, 0);
      if(t0 == g_last_bar) return;
      g_last_bar = t0;
   }

   // Paso 5: señales de entrada
   if(!IsNewTradesAllowed())  return;
   if(TotalPositions() >= 2)  return;
   if(g_second_pending)       return;

   // ZONA BUY: RSI ≤ 9
   if(rsi_now <= InpRSI_BuyLevel)
   {
      if(InpBBDirFilter && ask >= mid_now) return;
      ExecuteOrder(ORDER_TYPE_BUY, ask, mid_now, rsi_now, false);
      if(TotalPositions() < 2)
      {
         g_second_pending = true;
         g_second_open_at = TimeCurrent() + (datetime)InpSecondTradeDelay;
         g_second_type    = ORDER_TYPE_BUY;
         Print("⏱ 2do BUY en ", InpSecondTradeDelay, "s | RSI=", DoubleToString(rsi_now,1));
      }
   }
   // ZONA SELL: RSI ≥ 85
   else if(rsi_now >= InpRSI_SellLevel)
   {
      if(InpBBDirFilter && bid <= mid_now) return;
      ExecuteOrder(ORDER_TYPE_SELL, bid, mid_now, rsi_now, false);
      if(TotalPositions() < 2)
      {
         g_second_pending = true;
         g_second_open_at = TimeCurrent() + (datetime)InpSecondTradeDelay;
         g_second_type    = ORDER_TYPE_SELL;
         Print("⏱ 2do SELL en ", InpSecondTradeDelay, "s | RSI=", DoubleToString(rsi_now,1));
      }
   }
   // RSI entre 9 y 85: ZONA MUERTA — sin acción
}

//==================================================================
//  SMART TP MANAGER — Sistema de 2 fases
//
//  FASE 1 · WAITING
//    El mercado corre libremente, SIN SL ni trailing.
//    El bot NO toca la posición por ningún motivo.
//    Solo espera uno de estos dos eventos:
//      Evento A: RSI cruza el nivel 50 (señal TP de la estrategia)
//      Evento B: La ganancia supera InpMinProfitUSD ($9)
//    Cuando ocurre → pasa a HARVEST
//
//  FASE 2 · HARVEST
//    Micro-trailing activo (InpHarvestGap_USD).
//    Retracement Guard solo si profit ≥ InpMinProfitUSD.
//    El trailing stop cierra la posición de forma natural.
//==================================================================
void SmartTPManager(double rsi_now, double rsi_prev,
                    double mid_now, double ask, double bid)
{
   bool friday_pre = IsFridayPreClose();

   for(int i = 0; i < MAX_TRACKED; i++)
   {
      if(g_states[i].ticket == 0 || g_states[i].phase == PHASE_CLOSED) continue;

      ulong  tk      = g_states[i].ticket;
      int    ptype   = g_states[i].pos_type;
      double o_price = g_states[i].open_price;

      if(!PositionSelectByTicket(tk)) continue;
      double cur_sl     = PositionGetDouble(POSITION_SL);
      double cur_tp     = PositionGetDouble(POSITION_TP);
      double profit_usd = PositionGetDouble(POSITION_PROFIT);
      double fav_price  = (ptype == 0) ? bid : ask;

      // Actualizar pico de ganancia (solo máximos positivos)
      if(profit_usd > g_states[i].peak_profit_usd)
      {
         g_states[i].peak_profit_usd = profit_usd;
         g_states[i].peak_price      = fav_price;
      }
      double peak_usd = g_states[i].peak_profit_usd;

      //------------------------------------------------------------
      //  FASE 1 — WAITING
      //  EL BOT NO HACE NADA AQUÍ excepto detectar los dos eventos
      //  que activan el Harvest.
      //------------------------------------------------------------
      if(g_states[i].phase == PHASE_WAITING)
      {
         // Evento A: RSI cruza el nivel 50
         bool evento_a = (ptype == 0)
                         ? (rsi_prev < InpRSI_TPLevel && rsi_now >= InpRSI_TPLevel)
                         : (rsi_prev > InpRSI_TPLevel && rsi_now <= InpRSI_TPLevel);

         // Evento B: ganancia supera el mínimo configurado
         bool evento_b = (profit_usd >= InpMinProfitUSD);

         // Viernes pre-cierre: forzar transición para proteger ganancias
         bool force_friday = friday_pre && (profit_usd > 0.0);

         if(evento_a || evento_b || force_friday)
         {
            g_states[i].phase = PHASE_HARVEST;

            string trigger = evento_a     ? StringFormat("RSI-50 (RSI=%.1f)", rsi_now)
                           : force_friday ? "Viernes pre-cierre"
                           : StringFormat("Profit=$%.2f ≥ mínimo=$%.2f",
                                          profit_usd, InpMinProfitUSD);
            Print("◈ HARVEST activado #", tk,
                  " | P&L=$",   DoubleToString(profit_usd,2),
                  " | Evento: ", trigger);
            // No continuar: cae directamente al bloque HARVEST abajo
         }
         else
         {
            // Ningún evento aún → no hacer absolutamente nada, dejar correr
            continue;
         }
      }

      //------------------------------------------------------------
      //  FASE 2 — HARVEST
      //  Micro-trailing activo. El cierre ocurre cuando:
      //    1) El trailing stop es alcanzado (broker lo cierra)
      //    2) El Safety TP del servidor es alcanzado
      //    3) Retracement Guard (solo si profit ≥ $9)
      //------------------------------------------------------------
      if(g_states[i].phase == PHASE_HARVEST)
      {
         // Gap más ajustado en viernes pre-cierre
         double gap_usd = friday_pre
                          ? InpHarvestGap_USD * 0.5
                          : InpHarvestGap_USD;

         SafeTrail(tk, ptype, fav_price, cur_sl, cur_tp, o_price, gap_usd);

         // Retracement Guard — triple verificación
         //   ① Pico ≥ InpRetraceMinUSD
         //   ② Ganancia actual ≥ InpMinProfitUSD (NUNCA cierra por debajo de $9)
         //   ③ Ganancia actual > 0 (NUNCA cierra en pérdida)
         if(peak_usd    >= InpRetraceMinUSD  &&
            profit_usd  >= InpMinProfitUSD   &&
            profit_usd  >  0.0)
         {
            double retrace = ((peak_usd - profit_usd) / peak_usd) * 100.0;
            if(retrace >= InpRetracePct)
            {
               ForceClose(tk, StringFormat(
                  "RETRACEMENT | Pico=$%.2f | Actual=$%.2f | Retroceso=%.0f%%",
                  peak_usd, profit_usd, retrace));
               continue;
            }
         }

         // Log progreso cada $2 de nuevo pico
         if(peak_usd > g_states[i].last_log_usd + 2.0)
         {
            Print("🚀 HARVEST #", tk,
                  " | Pico=$",   DoubleToString(peak_usd,  2),
                  " | Actual=$", DoubleToString(profit_usd,2),
                  " | SL=",      DoubleToString(cur_sl,    _Digits));
            g_states[i].last_log_usd = peak_usd;
         }
      }
   }
}

//==================================================================
//  SAFE TRAIL — garantía absoluta: SL nunca cruza el open_price
//  El gap se expresa en USD y se convierte a precio por símbolo
//==================================================================
void SafeTrail(ulong tk,     int ptype,     double fav_price,
               double cur_sl, double cur_tp,
               double open_price, double gap_usd)
{
   double gap = USDtoPriceGap(gap_usd);
   if(gap < g_sym.Point()) return;

   if(ptype == 0) // BUY: SL sube, nunca baja del open_price
   {
      double new_sl = NormalizeDouble(MathMax(fav_price - gap, open_price), _Digits);
      if(new_sl > cur_sl + g_sym.Point())
         g_trade.PositionModify(tk, new_sl, cur_tp);
   }
   else // SELL: SL baja, nunca sube del open_price
   {
      double new_sl = NormalizeDouble(MathMin(fav_price + gap, open_price), _Digits);
      bool not_set  = (cur_sl < g_sym.Point());
      if(not_set || new_sl < cur_sl - g_sym.Point())
         g_trade.PositionModify(tk, new_sl, cur_tp);
   }
}

//==================================================================
//  CONVERTIR USD A DISTANCIA DE PRECIO — Universal para todos los símbolos
//  Usa SYMBOL_TRADE_TICK_VALUE y SYMBOL_TRADE_TICK_SIZE
//  Compatible: XAUUSD, EURUSD, USDJPY, NAS100, SP500, etc.
//==================================================================
double USDtoPriceGap(double usd_amount)
{
   if(usd_amount <= 0.0) return g_pip;

   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE); // USD por tick por 1 lot
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);  // precio por tick

   if(tv < 1e-10 || ts < 1e-10 || InpLotSize < 1e-10) return g_pip;

   double lot_tick_usd = tv * InpLotSize; // USD por tick para nuestro lote
   if(lot_tick_usd < 1e-10) return g_pip;

   // precio_gap = (usd_deseado × tamaño_tick) / (usd_por_tick × lote)
   return NormalizeDouble((usd_amount * ts) / lot_tick_usd, _Digits);
}

//==================================================================
//  EJECUTAR ORDEN
//==================================================================
void ExecuteOrder(ENUM_ORDER_TYPE otype, double price,
                  double mid, double rsi, bool is_second)
{
   if(TotalPositions() >= 2) return;

   double sl = 0.0; // Sin SL inicial — lo gestiona SmartTPManager
   double tp = 0.0;
   if(InpSafetyTP_USD > 0.0)
   {
      double dist = USDtoPriceGap(InpSafetyTP_USD);
      tp = NormalizeDouble(otype == ORDER_TYPE_BUY
                           ? price + dist
                           : price - dist, _Digits);
   }

   bool ok = (otype == ORDER_TYPE_BUY)
             ? g_trade.Buy (InpLotSize, _Symbol, price, sl, tp, "RSI_BB_v7")
             : g_trade.Sell(InpLotSize, _Symbol, price, sl, tp, "RSI_BB_v7");

   if(ok)
   {
      ulong pos_tk = GetNewestTicket(otype);
      if(pos_tk > 0)
         AddTracking(pos_tk, price, otype == ORDER_TYPE_BUY ? 0 : 1);

      Print(is_second ? "▶▶ " : "▶  ",
            otype == ORDER_TYPE_BUY ? "BUY " : "SELL",
            is_second ? " (2/2)" : " (1/2)",
            " | Price=",     DoubleToString(price,_Digits),
            " | RSI=",       DoubleToString(rsi,  1),
            " | BBmid=",     DoubleToString(mid,  _Digits),
            " | SafetyTP=",  DoubleToString(tp,   _Digits),
            " | #",          pos_tk);
   }
   else
      Print("ERROR ", is_second ? "2do " : "1er ",
            EnumToString(otype), " [",
            g_trade.ResultRetcode(), "] ",
            g_trade.ResultRetcodeDescription());
}

//==================================================================
//  CIERRE FORZADO (Retracement Guard)
//  Verificación triple antes de ejecutar: nunca en pérdida ni < $9
//==================================================================
void ForceClose(ulong tk, string reason)
{
   if(!PositionSelectByTicket(tk)) return;
   double profit = PositionGetDouble(POSITION_PROFIT);

   if(profit < InpMinProfitUSD)
   {
      Print("⚠ ForceClose bloqueado #", tk,
            " | P&L=$", DoubleToString(profit,2),
            " | Requiere≥$", DoubleToString(InpMinProfitUSD,2));
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
//  FILTROS DE SESIÓN
//==================================================================
bool IsNewTradesAllowed()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int dow = dt.day_of_week;

   if(dow == 0 || dow == 6) return false; // fin de semana

   if(dow == 1 && dt.hour < InpMondayStartHour) return false; // lunes apertura

   if(dow == 5)
   {
      int close_min = InpFridayCloseHour * 60;
      int cur_min   = dt.hour * 60 + dt.min;
      if(cur_min >= close_min - 180) return false; // viernes 3h antes del cierre
   }

   return true;
}

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
//  GESTIÓN DEL TRACKING DE POSICIONES
//==================================================================
void SyncTracking()
{
   for(int i = 0; i < MAX_TRACKED; i++)
   {
      if(g_states[i].ticket == 0) continue;
      if(!PositionSelectByTicket(g_states[i].ticket)) ResetState(i);
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
         Print("TRACKING #", tk, " ", (ptype==0?"BUY":"SELL"),
               " Open=", DoubleToString(open_px,_Digits),
               " [WAITING — sin SL hasta RSI-50 o $",
               DoubleToString(InpMinProfitUSD,2), "]");
         return;
      }
   }
   Print("⚠ Tracking array lleno");
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
