//+------------------------------------------------------------------+
//|  XAUUSD Quantum Sniper EA  v4.0                                  |
//|  Metodología: Trend-Following Grid + Sniper Triple-Filtro        |
//|  Inspirado en Quantum Queen (Bogdan Ion Puscasu)                 |
//|  Compatible: Cuentas desde $10 | Apalancamiento 1:500            |
//|  Símbolo objetivo: XAUUSD (Oro spot)                             |
//+------------------------------------------------------------------+
//
//  MEJORAS CRÍTICAS SOBRE LA VERSIÓN ANTERIOR:
//  ─────────────────────────────────────────────────────────────────
//  [FIX 1] SEÑAL: Cruce real de EMA detectado (antes solo alineación)
//          → Elimina entradas en tendencias agotadas
//  [FIX 2] GRID: Ordenes añadidas en intervalos ATR (no todas a la vez)
//          → Elimina la apertura masiva y simultánea de posiciones
//  [FIX 3] SL/TP: Basados en ATR dinámico (no en puntos fijos)
//          → Adapta el riesgo a la volatilidad real del mercado
//  [FIX 4] TRAILING STOP: Protege ganancias desde X*ATR de beneficio
//  [FIX 5] GRID ADAPTATIVO: Máximo de órdenes según saldo de la cuenta
//          → Cuentas <$50: máx 1 orden | $50-$200: máx 2 | etc.
//  [FIX 6] LOTE ADAPTATIVO: Calculado por % de riesgo + ATR (no fijo)
//  [FIX 7] FILTRO SESIÓN GMT: Solo opera en sesión Londres/NY
//  [FIX 8] FILTRO ATR: Evita mercados planos y noticias explosivas
//  [FIX 9] FILTRO RSI: Evita comprar en sobrecompra o vender en
//          sobreventa (confirma momentum antes de entrar)
//  [FIX 10] BASKET TP/SL: Cierra la cesta completa desde precio
//           promedio ponderado (estrategia Quantum Queen)
//  [FIX 11] DRAWDOWN GLOBAL: Cierra todo si equity cae X% del balance
//  [FIX 12] EMA 200 TREND FILTER: Solo opera a favor de la tendencia
//           mayor (precio > EMA200 → solo BUY; < EMA200 → solo SELL)
//+------------------------------------------------------------------+

#property copyright "Quantum Sniper EA v4.0"
#property version   "4.00"
#property strict

#include <Trade/Trade.mqh>
CTrade trade;

//╔══════════════════════════════════════════════════════════════════╗
//║  PARÁMETROS DE ENTRADA                                           ║
//╚══════════════════════════════════════════════════════════════════╝

input group "═══ RIESGO Y GESTIÓN ═══"
input double InpRiskPct        = 1.5;   // % del balance arriesgado por entrada
input double InpMaxDDPct       = 15.0;  // Drawdown máx global antes de cerrar todo (%)
input int    InpMaxGridOrders  = 4;     // Máx órdenes en grid (solo cuentas grandes)
input double InpGridLotMult    = 1.5;   // Multiplicador de lote en cada nivel grid

input group "═══ ATR — DINÁMICO (base de SL/TP/GRID) ═══"
input int    InpATRPeriod      = 14;
input double InpSL_ATR         = 1.5;   // Stop Loss por posición = X * ATR
input double InpTP_ATR         = 2.0;   // Take Profit individual = X * ATR
input double InpTrail_ATR      = 0.8;   // Trailing activa cuando ganancia >= X * ATR
input double InpGrid_ATR       = 1.0;   // Separación entre niveles grid = X * ATR
input double InpBasketTP_ATR   = 2.5;   // TP de cesta desde precio promedio = X * ATR

input group "═══ INDICADORES ═══"
input int    InpFastEMA        = 9;
input int    InpSlowEMA        = 21;
input int    InpTrendEMA       = 200;
input int    InpRSIPeriod      = 14;
input double InpRSI_MaxBuy     = 70.0;  // No comprar si RSI supera este valor
input double InpRSI_MinSell    = 30.0;  // No vender si RSI está por debajo

input group "═══ FILTROS DE CALIDAD ═══"
input double InpMaxSpreadPts   = 40;    // Spread máximo permitido (puntos)
input double InpMinATR_Pts     = 30;    // ATR mínimo — filtra mercado plano
input double InpMaxATR_Pts     = 1200;  // ATR máximo — evita noticias explosivas
input bool   InpSessionFilter  = true;  // Activar filtro de sesión GMT
input int    InpSessStart      = 7;     // Hora inicio sesión GMT (Londres abre a las 7)
input int    InpSessEnd        = 20;    // Hora cierre sesión GMT

input group "═══ CONFIGURACIÓN EA ═══"
input int    InpMagic          = 2024;
input int    InpSlippage       = 10;

//╔══════════════════════════════════════════════════════════════════╗
//║  VARIABLES GLOBALES                                              ║
//╚══════════════════════════════════════════════════════════════════╝
int      hFast, hSlow, hTrend, hRSI, hATR;
datetime lastBarTime = 0;

//╔══════════════════════════════════════════════════════════════════╗
//║  INICIALIZACIÓN                                                  ║
//╚══════════════════════════════════════════════════════════════════╝

int OnInit() {
   hFast  = iMA(_Symbol, _Period, InpFastEMA,  0, MODE_EMA, PRICE_CLOSE);
   hSlow  = iMA(_Symbol, _Period, InpSlowEMA,  0, MODE_EMA, PRICE_CLOSE);
   hTrend = iMA(_Symbol, _Period, InpTrendEMA, 0, MODE_EMA, PRICE_CLOSE);
   hRSI   = iRSI(_Symbol, _Period, InpRSIPeriod, PRICE_CLOSE);
   hATR   = iATR(_Symbol, _Period, InpATRPeriod);

   if(hFast  == INVALID_HANDLE || hSlow  == INVALID_HANDLE ||
      hTrend == INVALID_HANDLE || hRSI   == INVALID_HANDLE ||
      hATR   == INVALID_HANDLE) {
      Alert("Error crítico: no se pudo inicializar un indicador en ", _Symbol);
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippage);
   PrintFormat("✅ Quantum Sniper EA v4.0 iniciado | Símbolo: %s | TF: %s",
               _Symbol, EnumToString(_Period));
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
   IndicatorRelease(hFast);  IndicatorRelease(hSlow);
   IndicatorRelease(hTrend); IndicatorRelease(hRSI);
   IndicatorRelease(hATR);
}

//╔══════════════════════════════════════════════════════════════════╗
//║  UTILIDADES BÁSICAS                                              ║
//╚══════════════════════════════════════════════════════════════════╝

// Devuelve el ATR actual en unidades de precio (ej: 2.50 para XAUUSD)
double GetATR() {
   double buf[1];
   ArraySetAsSeries(buf, true);
   return (CopyBuffer(hATR, 0, 0, 1, buf) > 0) ? buf[0] : 0.0;
}

// Devuelve el spread actual en puntos
double GetSpreadPts() {
   return (SymbolInfoDouble(_Symbol, SYMBOL_ASK) -
           SymbolInfoDouble(_Symbol, SYMBOL_BID)) / _Point;
}

// Verifica si estamos dentro del horario de sesión GMT configurado
bool IsSessionOpen() {
   if(!InpSessionFilter) return true;
   MqlDateTime gmt;
   TimeToStruct(TimeGMT(), gmt);
   return (gmt.hour >= InpSessStart && gmt.hour < InpSessEnd);
}

// Límite adaptativo de órdenes grid según saldo de la cuenta
// Protege cuentas pequeñas de exposición excesiva
int GetMaxGrid() {
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   if(bal < 50)   return 1;   // $10-$49:  1 orden máximo
   if(bal < 200)  return 2;   // $50-$199: 2 órdenes máximo
   if(bal < 500)  return 3;   // $200-$499: 3 órdenes máximo
   return InpMaxGridOrders;   // $500+: hasta el límite configurado
}

// Calcula el lote base usando riesgo % del balance y ATR como referencia de SL
// Siempre devuelve al menos el lote mínimo permitido por el broker
double CalcBaseLot() {
   double atr  = GetATR();
   double bal  = AccountInfoDouble(ACCOUNT_BALANCE);
   double minL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double maxL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   if(atr <= 0) return minL;

   // Calcula cuánto dinero se pierde por lote estándar si el SL es tocado
   double tv       = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double ts       = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double slDist   = atr * InpSL_ATR;                    // distancia SL en precio
   double slPerLot = (ts > 0) ? (slDist / ts) * tv : 0; // pérdida $ por lote

   if(slPerLot <= 0) return minL;

   double riskMoney = bal * InpRiskPct / 100.0;
   double lot       = riskMoney / slPerLot;
   lot = MathFloor(lot / step) * step;
   return MathMax(minL, MathMin(lot, maxL));
}

// Lote del nivel N del grid (multiplicado exponencialmente)
double CalcGridLot(int level, double baseLot) {
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double maxL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lot  = baseLot * MathPow(InpGridLotMult, level);
   return MathMin(MathFloor(lot / step) * step, maxL);
}

//╔══════════════════════════════════════════════════════════════════╗
//║  ESTRUCTURA DE CESTA (BASKET)                                    ║
//╚══════════════════════════════════════════════════════════════════╝

struct Basket {
   int    total;         // Total de posiciones abiertas (este magic)
   int    buys;          // Cantidad de posiciones BUY
   int    sells;         // Cantidad de posiciones SELL
   double profit;        // Profit + swap total de todas las posiciones
   double avgBuy;        // Precio promedio ponderado de buys
   double avgSell;       // Precio promedio ponderado de sells
   double worstBuy;      // Precio de apertura más bajo entre buys (peor para el grid)
   double worstSell;     // Precio de apertura más alto entre sells (peor para el grid)
};

// Lee todas las posiciones activas del magic y devuelve el estado de la cesta
Basket GetBasket() {
   Basket b  = {};
   b.worstBuy  = DBL_MAX;
   b.worstSell = 0;
   double sumBL = 0, sumBPL = 0; // buy: lots acumulados, price*lot acumulados
   double sumSL = 0, sumSPL = 0; // sell: ídem

   for(int i = PositionsTotal()-1; i >= 0; i--) {
      ulong tk = PositionGetTicket(i);
      if(!PositionSelectByTicket(tk)) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)       continue;

      double lot   = PositionGetDouble(POSITION_VOLUME);
      double open  = PositionGetDouble(POSITION_PRICE_OPEN);
      double pnl   = PositionGetDouble(POSITION_PROFIT) +
                     PositionGetDouble(POSITION_SWAP);
      bool isBuy   = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);

      b.total++;
      b.profit += pnl;

      if(isBuy) {
         b.buys++;
         sumBPL      += open * lot;
         sumBL       += lot;
         b.worstBuy   = MathMin(b.worstBuy, open);
      } else {
         b.sells++;
         sumSPL      += open * lot;
         sumSL       += lot;
         b.worstSell  = MathMax(b.worstSell, open);
      }
   }

   // Precio promedio ponderado por volumen (igual que Quantum Queen)
   if(sumBL > 0) b.avgBuy  = sumBPL / sumBL;
   if(sumSL > 0) b.avgSell = sumSPL / sumSL;
   return b;
}

//╔══════════════════════════════════════════════════════════════════╗
//║  SEÑALES DE ENTRADA — TRIPLE CONFIRMACIÓN (Sniper Filter)        ║
//╚══════════════════════════════════════════════════════════════════╝

// [FILTRO 1] Detección de cruce REAL entre EMA rápida y lenta.
// La barra anterior debe tener cruce invertido respecto a la actual.
// Esto elimina entradas en mitad de tendencias ya establecidas.
bool CrossDetected(bool &isBuy) {
   double f[3], s[3];
   ArraySetAsSeries(f, true);
   ArraySetAsSeries(s, true);
   if(CopyBuffer(hFast, 0, 0, 3, f) <= 0 ||
      CopyBuffer(hSlow, 0, 0, 3, s) <= 0) return false;

   // Cruce alcista: barra[1] fast<=slow, barra[0] fast>slow
   if(f[1] <= s[1] && f[0] > s[0]) { isBuy = true;  return true; }
   // Cruce bajista: barra[1] fast>=slow, barra[0] fast<slow
   if(f[1] >= s[1] && f[0] < s[0]) { isBuy = false; return true; }
   return false;
}

// [FILTRO 2] Precio de cierre de vela confirmada vs EMA 200.
// Solo se compra cuando el mercado está sobre la EMA 200 (tendencia alcista).
// Solo se vende cuando el mercado está bajo la EMA 200 (tendencia bajista).
bool TrendAligned(bool isBuy) {
   double t[1];
   ArraySetAsSeries(t, true);
   if(CopyBuffer(hTrend, 0, 0, 1, t) <= 0) return false;
   double close1 = iClose(_Symbol, _Period, 1); // vela ya cerrada
   return isBuy ? (close1 > t[0]) : (close1 < t[0]);
}

// [FILTRO 3] RSI no debe estar en zona extrema contraria a la operación.
// Evita comprar cuando el mercado está sobrecomprado y vender en sobreventa.
bool RSIOk(bool isBuy) {
   double r[1];
   ArraySetAsSeries(r, true);
   if(CopyBuffer(hRSI, 0, 0, 1, r) <= 0) return false;
   return isBuy ? (r[0] < InpRSI_MaxBuy) : (r[0] > InpRSI_MinSell);
}

//╔══════════════════════════════════════════════════════════════════╗
//║  GESTIÓN DE POSICIONES                                           ║
//╚══════════════════════════════════════════════════════════════════╝

// Cierra todas las posiciones del magic en este símbolo
void CloseAll() {
   for(int i = PositionsTotal()-1; i >= 0; i--) {
      ulong tk = PositionGetTicket(i);
      if(!PositionSelectByTicket(tk)) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      trade.PositionClose(tk);
   }
}

// Cierra solo las posiciones del tipo indicado (BUY o SELL)
void CloseType(bool buyType) {
   ENUM_POSITION_TYPE pt = buyType ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
   for(int i = PositionsTotal()-1; i >= 0; i--) {
      ulong tk = PositionGetTicket(i);
      if(!PositionSelectByTicket(tk)) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != pt) continue;
      trade.PositionClose(tk);
   }
}

// Trailing stop dinámico: se activa cuando la posición alcanza InpTrail_ATR * ATR
// de beneficio. Nunca mueve el SL en dirección desfavorable.
void ApplyTrailing(double atr) {
   if(atr <= 0) return;
   double trailDist = atr * InpTrail_ATR;

   for(int i = PositionsTotal()-1; i >= 0; i--) {
      ulong tk = PositionGetTicket(i);
      if(!PositionSelectByTicket(tk)) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      double curSL   = PositionGetDouble(POSITION_SL);
      double curTP   = PositionGetDouble(POSITION_TP);
      double oprice  = PositionGetDouble(POSITION_PRICE_OPEN);
      bool   isBuy   = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);

      if(isBuy) {
         double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double profDist = bid - oprice; // cuánto ha ganado en precio
         if(profDist < trailDist) continue; // no ha alcanzado el umbral todavía
         double newSL = NormalizeDouble(bid - trailDist, _Digits);
         if(newSL > curSL + _Point)
            trade.PositionModify(tk, newSL, curTP);
      } else {
         double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double profDist = oprice - ask;
         if(profDist < trailDist) continue;
         double newSL = NormalizeDouble(ask + trailDist, _Digits);
         if(newSL < curSL - _Point)
            trade.PositionModify(tk, newSL, curTP);
      }
   }
}

//╔══════════════════════════════════════════════════════════════════╗
//║  GESTIÓN DE CESTA Y GRID (Quantum Queen: Trend-Following Grid)   ║
//╚══════════════════════════════════════════════════════════════════╝
//
//  Lógica de la cesta:
//  1. Si el precio llega al TP de la cesta (precio promedio ± X*ATR), cierra todo.
//  2. Si la pérdida total supera el límite definido, cierra toda la cesta (basket SL).
//  3. Si el precio se aleja InpGrid_ATR desde la peor apertura, añade un nivel grid.
//
void ManageGrid(Basket &b, double atr) {
   if(atr <= 0) return;

   double bal          = AccountInfoDouble(ACCOUNT_BALANCE);
   // La pérdida máxima permitida por cesta es la mitad del drawdown global máximo
   double maxBasketLoss = -(bal * InpMaxDDPct / 2.0 / 100.0);

   // ─── GESTIÓN CESTA BUY ─────────────────────────────────────────
   if(b.buys > 0) {
      double bid      = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double basketTP = b.avgBuy + atr * InpBasketTP_ATR; // TP desde precio prom.

      // TP de cesta: precio supera el objetivo desde el promedio ponderado
      if(bid >= basketTP) {
         PrintFormat("✅ Cesta BUY cerrada en TP | Precio prom: %.2f | TP: %.2f | Profit: $%.2f",
                     b.avgBuy, basketTP, b.profit);
         CloseType(true);
         return;
      }
      // SL de cesta: pérdida total supera el límite
      if(b.sells == 0 && b.profit < maxBasketLoss) {
         PrintFormat("🛑 Cesta BUY cerrada por SL | Pérdida: $%.2f", b.profit);
         CloseType(true);
         return;
      }
      // Grid: añade un nivel si precio cayó InpGrid_ATR*ATR desde la peor apertura
      if(b.buys < GetMaxGrid() && GetSpreadPts() <= InpMaxSpreadPts) {
         double gap = b.worstBuy - bid;
         if(gap >= atr * InpGrid_ATR) {
            double baseLot = CalcBaseLot();
            double newLot  = CalcGridLot(b.buys, baseLot);
            double newSL   = NormalizeDouble(bid - atr * InpSL_ATR, _Digits);
            if(trade.Buy(newLot, _Symbol, SymbolInfoDouble(_Symbol, SYMBOL_ASK),
                         newSL, 0, "QS-Grid-BUY"))
               PrintFormat("📈 Grid BUY nivel %d | Lot: %.2f", b.buys + 1, newLot);
         }
      }
   }

   // ─── GESTIÓN CESTA SELL ────────────────────────────────────────
   if(b.sells > 0) {
      double ask      = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double basketTP = b.avgSell - atr * InpBasketTP_ATR;

      if(ask <= basketTP) {
         PrintFormat("✅ Cesta SELL cerrada en TP | Precio prom: %.2f | TP: %.2f | Profit: $%.2f",
                     b.avgSell, basketTP, b.profit);
         CloseType(false);
         return;
      }
      if(b.buys == 0 && b.profit < maxBasketLoss) {
         PrintFormat("🛑 Cesta SELL cerrada por SL | Pérdida: $%.2f", b.profit);
         CloseType(false);
         return;
      }
      if(b.sells < GetMaxGrid() && GetSpreadPts() <= InpMaxSpreadPts) {
         double gap = ask - b.worstSell;
         if(gap >= atr * InpGrid_ATR) {
            double baseLot = CalcBaseLot();
            double newLot  = CalcGridLot(b.sells, baseLot);
            double newSL   = NormalizeDouble(ask + atr * InpSL_ATR, _Digits);
            if(trade.Sell(newLot, _Symbol, SymbolInfoDouble(_Symbol, SYMBOL_BID),
                          newSL, 0, "QS-Grid-SELL"))
               PrintFormat("📉 Grid SELL nivel %d | Lot: %.2f", b.sells + 1, newLot);
         }
      }
   }
}

//╔══════════════════════════════════════════════════════════════════╗
//║  PROTECCIÓN DRAWDOWN GLOBAL                                      ║
//╚══════════════════════════════════════════════════════════════════╝

void CheckDrawdown() {
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
   if(bal <= 0) return;
   double ddPct = (bal - eq) / bal * 100.0;
   if(ddPct >= InpMaxDDPct) {
      PrintFormat("⚠️ DRAWDOWN GLOBAL %.1f%% >= %.1f%% → Cierre de emergencia.",
                  ddPct, InpMaxDDPct);
      CloseAll();
   }
}

//╔══════════════════════════════════════════════════════════════════╗
//║  APERTURA DE PRIMERA POSICIÓN                                    ║
//╚══════════════════════════════════════════════════════════════════╝

void OpenTrade(bool isBuy, double atr) {
   double baseLot = CalcBaseLot();
   double ask     = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid     = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double price   = isBuy ? ask : bid;

   // SL y TP individuales basados en ATR
   double sl = isBuy ? price - atr * InpSL_ATR : price + atr * InpSL_ATR;
   double tp = isBuy ? price + atr * InpTP_ATR  : price - atr * InpTP_ATR;
   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);

   string comment = isBuy ? "QS-Entry-BUY" : "QS-Entry-SELL";
   bool   ok      = isBuy ? trade.Buy(baseLot,  _Symbol, price, sl, tp, comment)
                           : trade.Sell(baseLot, _Symbol, price, sl, tp, comment);
   if(ok)
      PrintFormat("🎯 %s | Lot: %.2f | SL: %.2f | TP: %.2f | ATR: %.2f",
                  comment, baseLot, sl, tp, atr);
   else
      PrintFormat("❌ Fallo al abrir %s | Error: %d", comment, GetLastError());
}

//╔══════════════════════════════════════════════════════════════════╗
//║  OnTick — BUCLE PRINCIPAL                                        ║
//╚══════════════════════════════════════════════════════════════════╝

void OnTick() {
   // ── 1. Protección drawdown global (se ejecuta en cada tick) ────
   CheckDrawdown();

   // ── 2. Obtener estado actual de la cesta ───────────────────────
   Basket b = GetBasket();

   // ── 3. Si hay posiciones activas: gestionar trailing y grid ────
   if(b.total > 0) {
      double atr = GetATR();
      ApplyTrailing(atr);
      ManageGrid(b, atr);
      return; // No busca nuevas señales mientras hay operaciones abiertas
   }

   // ── 4. Control de nueva vela (señales solo en apertura de barra) ─
   datetime curBar = iTime(_Symbol, _Period, 0);
   if(curBar == lastBarTime) return;
   lastBarTime = curBar;

   // ── 5. Filtros de condición de mercado ─────────────────────────
   double atr = GetATR();
   if(GetSpreadPts() > InpMaxSpreadPts)  return; // Spread demasiado alto
   if(!IsSessionOpen())                  return; // Fuera de horario GMT
   if(atr < InpMinATR_Pts * _Point)      return; // Mercado demasiado plano
   if(atr > InpMaxATR_Pts * _Point)      return; // Volatilidad extrema (noticias)

   // ── 6. Triple confirmación de señal de entrada ─────────────────
   bool isBuy;
   if(!CrossDetected(isBuy)) return; // [1] Cruce EMA real
   if(!TrendAligned(isBuy))  return; // [2] Precio vs EMA 200
   if(!RSIOk(isBuy))         return; // [3] RSI no en zona extrema contraria

   // ── 7. Ejecutar entrada ────────────────────────────────────────
   OpenTrade(isBuy, atr);
}
//+------------------------------------------------------------------+
