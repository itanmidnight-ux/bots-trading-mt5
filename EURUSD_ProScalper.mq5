//+------------------------------------------------------------------+
//|  EURUSD PRO SCALPER v3.0                                         |
//|                                                                   |
//|  SEÑALES  : EMA Crossover en M1 (motor principal)                |
//|  FILTROS  : H4 sesgo macro | H1 estructura | M5 momentum         |
//|  SL       : ATR + Swing High/Low estructural                      |
//|  TP       : 2× distancia SL dinámica                             |
//|  TRAILING : Quantum-style multi-paso                              |
//|  RECOVERY : Anti-pérdida inteligente (sin martingala)            |
//|  PROTECCIÓN: Ningún trade cierra en su misma vela M1             |
//|                                                                   |
//|  Timeframe de ejecución: M1                                       |
//|  Magic: 30002                                                     |
//+------------------------------------------------------------------+
#property copyright "EURUSD Pro Scalper v3.0"
#property version   "3.00"
#property strict

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>

CTrade        trade;
CPositionInfo posInfo;

//====================================================================
//  INPUTS
//====================================================================
input group "=== GENERAL ==="
input ulong  InpMagic         = 30002;
input string InpComment       = "PS3";
input int    InpSlippage      = 10;

input group "=== EMA CROSSOVER M1 (MOTOR PRINCIPAL) ==="
input int    InpEmaFast       = 8;     // EMA rápida M1
input int    InpEmaSlow       = 21;    // EMA lenta M1
input int    InpEmaTrend      = 50;    // EMA tendencia M1 (filtro direccional)

input group "=== FILTROS MTF ==="
input bool   InpFilterH4      = true;
input int    InpH4_EmaFast    = 21;
input int    InpH4_EmaSlow    = 50;
input bool   InpFilterH1      = true;
input int    InpH1_EmaFast    = 21;
input int    InpH1_EmaSlow    = 50;
input bool   InpFilterM5      = true;
input int    InpM5_EmaFast    = 9;
input int    InpM5_EmaSlow    = 21;

input group "=== STOP LOSS PROFESIONAL (ATR + SWING) ==="
input int    InpATRPeriod     = 14;    // Período ATR M1
input double InpSL_ATR_Min   = 1.0;   // SL mínimo = N × ATR
input double InpSL_ATR_Max   = 2.5;   // SL máximo = N × ATR (clamp)
input double InpSL_SwingBuf  = 0.5;   // Buffer adicional al swing (× ATR)
input int    InpSwingLookback = 20;    // Barras atrás para buscar swing

input group "=== TAKE PROFIT ==="
input double InpTP_RR         = 2.0;  // Ratio TP/SL (mínimo 2:1)

input group "=== TRAILING STOP (QUANTUM STYLE) ==="
input bool   InpUseTrail      = true;
input double InpTrail1_At     = 1.0;  // Activar trailing1 al alcanzar N×SL de ganancia
input double InpTrail1_To     = 0.5;  // Mover SL a entrada+N×SL
input double InpTrail2_At     = 1.5;  // Trailing2
input double InpTrail2_Step   = 0.4;  // Paso trailing2 (× ATR)

input group "=== GESTIÓN DE POSICIÓN ==="
input bool   InpUseBreakEven  = true;
input double InpBE_At         = 0.8;  // Activar BE a N×SL de ganancia
input bool   InpUsePartial    = true;
input double InpPart_At       = 1.2;  // Parcial al 1.2×SL de ganancia
input double InpPart_Pct      = 50.0; // % a cerrar parcialmente
input int    InpMaxBarsOpen   = 120;  // Stop por tiempo (120 velas M1 = 2h)

input group "=== RIESGO ==="
input double InpRiskPct       = 0.8;  // % riesgo base por trade
input int    InpMaxPositions  = 2;    // Máx posiciones simultáneas
input double InpMaxSpread     = 15.0; // Spread máx en puntos EURUSD

input group "=== RECUPERACIÓN INTELIGENTE ==="
input bool   InpUseRecovery   = true;
input int    InpRecovMaxLoss  = 3;    // Activar recovery tras N pérdidas seguidas
input double InpRecovMult     = 1.3;  // Multiplicador de lote en recovery (1.3 = +30%)
input double InpRecovMaxMult  = 2.0;  // Tope máximo del multiplicador
input bool   InpReduceAfterWin= true; // Reducir lote gradualmente tras ganar

input group "=== PROTECCIÓN DIARIA ==="
input double InpMaxDailyLoss  = 3.5;  // % pérdida diaria máxima
input double InpMaxDailyProfit= 5.0;  // % target diario

input group "=== SESIÓN ==="
input bool   InpUseSession    = true;
input int    InpSessStart     = 7;
input int    InpSessEnd       = 20;
input bool   InpNoFriday      = true;
input int    InpFriEnd        = 20;

input group "=== PANEL ==="
input bool   InpShowPanel     = true;
input int    InpPanelX        = 12;
input int    InpPanelY        = 28;

//====================================================================
//  HANDLES
//====================================================================
int hM1_EmaFast, hM1_EmaSlow, hM1_EmaTrend, hM1_ATR, hM1_RSI;
int hM5_EmaFast, hM5_EmaSlow;
int hH1_EmaFast, hH1_EmaSlow;
int hH4_EmaFast, hH4_EmaSlow;

//====================================================================
//  ESTADO DE POSICIÓN ABIERTA
//====================================================================
struct PosData
{
   ulong    ticket;
   datetime openBar;   // Tiempo de la vela M1 en que se abrió
   double   slDist;    // Distancia SL original en precio
   bool     partial;   // Ya se hizo parcial
   bool     trail1;    // Trail fase 1 aplicado
   bool     trail2;    // Trail fase 2 aplicado
   bool     be;        // Break-even aplicado
};

PosData  g_pos[10];
int      g_posCount = 0;

//====================================================================
//  ESTADO GLOBAL
//====================================================================
double   g_dayStartBal  = 0;
datetime g_lastDay      = 0;
bool     g_dayBlocked   = false;

// Estadísticas
int      g_trades       = 0;
int      g_wins         = 0;
int      g_losses       = 0;
double   g_grossWin     = 0;
double   g_grossLoss    = 0;

// Recovery
int      g_consecLoss   = 0;
double   g_lotMult      = 1.0;

// Cache MTF
bool     g_h4Up=false, g_h4Dn=false;
bool     g_h1Up=false, g_h1Dn=false;
bool     g_m5Up=false, g_m5Dn=false;
double   g_atrM1        = 0;

// Control señal
datetime g_lastBuyBar   = 0;
datetime g_lastSellBar  = 0;

string   g_pfx          = "PS3_";

//====================================================================
//  OnInit
//====================================================================
int OnInit()
{
   if(StringFind(_Symbol,"EURUSD") < 0)
   { Alert("❌ Solo EURUSD. Símbolo actual: ", _Symbol); return INIT_PARAMETERS_INCORRECT; }

   // Filling mode
   ENUM_ORDER_TYPE_FILLING fill = ORDER_FILLING_RETURN;
   uint fm = (uint)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((fm & SYMBOL_FILLING_IOC) != 0)       fill = ORDER_FILLING_IOC;
   else if((fm & SYMBOL_FILLING_FOK) != 0)  fill = ORDER_FILLING_FOK;
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippage);
   trade.SetTypeFilling(fill);

   // Indicadores M1
   hM1_EmaFast  = iMA(_Symbol, PERIOD_M1, InpEmaFast,  0, MODE_EMA, PRICE_CLOSE);
   hM1_EmaSlow  = iMA(_Symbol, PERIOD_M1, InpEmaSlow,  0, MODE_EMA, PRICE_CLOSE);
   hM1_EmaTrend = iMA(_Symbol, PERIOD_M1, InpEmaTrend, 0, MODE_EMA, PRICE_CLOSE);
   hM1_ATR      = iATR(_Symbol,PERIOD_M1, InpATRPeriod);
   hM1_RSI      = iRSI(_Symbol,PERIOD_M1, 7, PRICE_CLOSE);

   // Indicadores M5
   hM5_EmaFast  = iMA(_Symbol, PERIOD_M5, InpM5_EmaFast, 0, MODE_EMA, PRICE_CLOSE);
   hM5_EmaSlow  = iMA(_Symbol, PERIOD_M5, InpM5_EmaSlow, 0, MODE_EMA, PRICE_CLOSE);

   // Indicadores H1
   hH1_EmaFast  = iMA(_Symbol, PERIOD_H1, InpH1_EmaFast, 0, MODE_EMA, PRICE_CLOSE);
   hH1_EmaSlow  = iMA(_Symbol, PERIOD_H1, InpH1_EmaSlow, 0, MODE_EMA, PRICE_CLOSE);

   // Indicadores H4
   hH4_EmaFast  = iMA(_Symbol, PERIOD_H4, InpH4_EmaFast, 0, MODE_EMA, PRICE_CLOSE);
   hH4_EmaSlow  = iMA(_Symbol, PERIOD_H4, InpH4_EmaSlow, 0, MODE_EMA, PRICE_CLOSE);

   // Verificar handles
   int h[11]={hM1_EmaFast,hM1_EmaSlow,hM1_EmaTrend,hM1_ATR,hM1_RSI,
              hM5_EmaFast,hM5_EmaSlow,hH1_EmaFast,hH1_EmaSlow,
              hH4_EmaFast,hH4_EmaSlow};
   for(int i=0;i<11;i++)
      if(h[i]==INVALID_HANDLE){ Alert("❌ Handle inválido #",i); return INIT_FAILED; }

   g_dayStartBal = AccountInfoDouble(ACCOUNT_BALANCE);
   g_lastDay     = iTime(_Symbol, PERIOD_D1, 0);
   g_posCount    = 0;
   g_lotMult     = 1.0;
   g_consecLoss  = 0;

   if(InpShowPanel) UpdatePanel();
   Print("✅ EURUSD Pro Scalper v3.0 | Bal=$",DoubleToString(g_dayStartBal,2),
         " | EMA(",InpEmaFast,"/",InpEmaSlow,"/",InpEmaTrend,") en M1");
   return INIT_SUCCEEDED;
}

//====================================================================
//  OnDeinit
//====================================================================
void OnDeinit(const int reason)
{
   Comment("");
   int h[11]={hM1_EmaFast,hM1_EmaSlow,hM1_EmaTrend,hM1_ATR,hM1_RSI,
              hM5_EmaFast,hM5_EmaSlow,hH1_EmaFast,hH1_EmaSlow,
              hH4_EmaFast,hH4_EmaSlow};
   for(int i=0;i<11;i++)
      if(h[i]!=INVALID_HANDLE) IndicatorRelease(h[i]);
   ObjectsDeleteAll(0, g_pfx);
   ChartRedraw();
}

//====================================================================
//  OnTick — ORQUESTADOR PRINCIPAL
//====================================================================
void OnTick()
{
   // Reset diario
   CheckDayReset();
   if(g_dayBlocked){ if(InpShowPanel) UpdatePanel(); return; }

   // Protección diaria
   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
   double pnl = eq - g_dayStartBal;
   if(pnl <= -(g_dayStartBal * InpMaxDailyLoss / 100.0))
   { CloseAll("MaxDailyLoss"); g_dayBlocked=true;
     Print("🛑 STOP DIARIO $",DoubleToString(pnl,2)); if(InpShowPanel) UpdatePanel(); return; }
   if(pnl >= (g_dayStartBal * InpMaxDailyProfit / 100.0))
   { CloseAll("DailyTarget"); g_dayBlocked=true;
     Print("🎯 TARGET DIARIO $",DoubleToString(pnl,2)); if(InpShowPanel) UpdatePanel(); return; }

   // Gestión de posiciones abiertas en cada tick
   ManagePositions();

   // Solo evaluar nueva entrada en vela M1 nueva
   if(!IsNewM1Bar()){ if(InpShowPanel) UpdatePanel(); return; }

   // Leer ATR
   double atrBuf[1];
   if(CopyBuffer(hM1_ATR,0,1,1,atrBuf)<1) return;
   g_atrM1 = atrBuf[0];
   if(g_atrM1<=0) return;

   // Filtros de sesión y spread
   if(InpUseSession && !ValidSession()) return;
   if((double)SymbolInfoInteger(_Symbol,SYMBOL_SPREAD) > InpMaxSpread) return;

   // Actualizar sesgo MTF
   UpdateMTF();

   // No abrir si ya tenemos máx posiciones
   if(CountMyPositions() >= InpMaxPositions) return;

   // Señal EMA cross en M1
   int sig = GetSignal();
   if(sig == 0) return;

   // Ejecutar
   if(sig == 1)  DoOpenBuy();
   if(sig == -1) DoOpenSell();

   if(InpShowPanel) UpdatePanel();
}

//====================================================================
//  NUEVA VELA M1
//====================================================================
bool IsNewM1Bar()
{
   static datetime lastBar = 0;
   datetime cur = iTime(_Symbol, PERIOD_M1, 0);
   if(cur == lastBar) return false;
   lastBar = cur;
   return true;
}

//====================================================================
//  ACTUALIZAR SESGO MTF
//====================================================================
void UpdateMTF()
{
   // H4
   if(InpFilterH4)
   { double f[1],s[1];
     if(CopyBuffer(hH4_EmaFast,0,1,1,f)>0 && CopyBuffer(hH4_EmaSlow,0,1,1,s)>0)
     { g_h4Up=(f[0]>s[0]); g_h4Dn=(f[0]<s[0]); } }
   else { g_h4Up=true; g_h4Dn=true; }

   // H1
   if(InpFilterH1)
   { double f[1],s[1];
     if(CopyBuffer(hH1_EmaFast,0,1,1,f)>0 && CopyBuffer(hH1_EmaSlow,0,1,1,s)>0)
     { g_h1Up=(f[0]>s[0]); g_h1Dn=(f[0]<s[0]); } }
   else { g_h1Up=true; g_h1Dn=true; }

   // M5
   if(InpFilterM5)
   { double f[1],s[1];
     if(CopyBuffer(hM5_EmaFast,0,1,1,f)>0 && CopyBuffer(hM5_EmaSlow,0,1,1,s)>0)
     { g_m5Up=(f[0]>s[0]); g_m5Dn=(f[0]<s[0]); } }
   else { g_m5Up=true; g_m5Dn=true; }
}

//====================================================================
//  SEÑAL EMA CROSS M1
//  Retorna  1=BUY,  -1=SELL,  0=sin señal
//====================================================================
int GetSignal()
{
   // Necesitamos 3 barras: [0]=actual, [1]=anterior, [2]=antepenúltima
   double fast[3], slow[3], trend[1], rsi[1];
   ArraySetAsSeries(fast, true);
   ArraySetAsSeries(slow, true);

   if(CopyBuffer(hM1_EmaFast,  0,0,3,fast)  < 3) return 0;
   if(CopyBuffer(hM1_EmaSlow,  0,0,3,slow)  < 3) return 0;
   if(CopyBuffer(hM1_EmaTrend, 0,1,1,trend) < 1) return 0;
   if(CopyBuffer(hM1_RSI,      0,1,1,rsi)   < 1) return 0;

   // Cruce alcista: fast cruzó por encima de slow entre bar[2] y bar[1]
   bool crossUp = (fast[1] > slow[1]) && (fast[2] <= slow[2]);
   // Cruce bajista
   bool crossDn = (fast[1] < slow[1]) && (fast[2] >= slow[2]);

   // Confirmación adicional: precio sobre/bajo EMA trend
   double c1 = iClose(_Symbol, PERIOD_M1, 1);

   datetime curBar = iTime(_Symbol, PERIOD_M1, 0);

   // BUY
   if(crossUp)
   {
      if(curBar == g_lastBuyBar) return 0;           // Ya usé este cruce
      if(c1 < trend[0] * 0.9999) return 0;           // Precio debe estar sobre EMA trend
      if(rsi[0] < 45.0) return 0;                    // RSI confirma momentum alcista
      if(!g_h4Up && !g_h1Up) return 0;              // Ambos filtros en contra = veto
      if(!g_m5Up) return 0;                          // M5 debe acompañar
      return 1;
   }

   // SELL
   if(crossDn)
   {
      if(curBar == g_lastSellBar) return 0;
      if(c1 > trend[0] * 1.0001) return 0;           // Precio bajo EMA trend
      if(rsi[0] > 55.0) return 0;
      if(!g_h4Dn && !g_h1Dn) return 0;
      if(!g_m5Dn) return 0;
      return -1;
   }

   return 0;
}

//====================================================================
//  SL PROFESIONAL: ATR + SWING ESTRUCTURAL
//  Retorna la distancia SL en precio (siempre positiva)
//====================================================================
double CalcStructuralSL(bool isBuy)
{
   int dg  = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double atr = g_atrM1;
   double minSL = InpSL_ATR_Min * atr;
   double maxSL = InpSL_ATR_Max * atr;

   // Buscar swing en las últimas InpSwingLookback velas M1 (excluyendo la actual)
   double swingExtreme = 0;
   if(isBuy)
   {
      // Para BUY: buscamos el mínimo reciente (swing low)
      int  loIdx  = iLowest(_Symbol, PERIOD_M1, MODE_LOW, InpSwingLookback, 1);
      if(loIdx >= 1)
      {
         double swLow = iLow(_Symbol, PERIOD_M1, loIdx);
         double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double dist  = ask - swLow + InpSL_SwingBuf * atr;
         swingExtreme = NormalizeDouble(dist, dg);
      }
   }
   else
   {
      // Para SELL: buscamos el máximo reciente (swing high)
      int  hiIdx  = iHighest(_Symbol, PERIOD_M1, MODE_HIGH, InpSwingLookback, 1);
      if(hiIdx >= 1)
      {
         double swHigh = iHigh(_Symbol, PERIOD_M1, hiIdx);
         double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double dist   = swHigh - bid + InpSL_SwingBuf * atr;
         swingExtreme  = NormalizeDouble(dist, dg);
      }
   }

   // Tomar el mayor entre swing y mínimo ATR
   double sl = (swingExtreme > minSL) ? swingExtreme : minSL;
   // Clamp al máximo permitido
   sl = MathMin(sl, maxSL);
   return sl;
}

//====================================================================
//  CÁLCULO DE LOTE
//====================================================================
double CalcLot(double slDist)
{
   if(slDist <= 0) return 0;
   double bal   = AccountInfoDouble(ACCOUNT_BALANCE);
   double rPct  = InpRiskPct * g_lotMult;
   double risk  = bal * rPct / 100.0;
   double tv    = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double ts    = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double minV  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxV  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(tv<=0||ts<=0) return minV;
   double pipVal = (ts > 0) ? tv / ts * _Point : 0;
   if(pipVal <= 0) return minV;
   double lot = risk / ((slDist / _Point) * pipVal);
   // Micro capital: cap absoluto
   if(bal < 50.0)   lot = MathMin(lot, minV * 2.0);
   else if(bal < 200.0) lot = MathMin(lot, minV * 20.0);
   lot = MathFloor(lot / step) * step;
   lot = MathMax(minV, MathMin(maxV, lot));
   return NormalizeDouble(lot, 2);
}

//====================================================================
//  ABRIR BUY
//====================================================================
void DoOpenBuy()
{
   int    dg  = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double slD = CalcStructuralSL(true);
   double sl  = NormalizeDouble(ask - slD, dg);
   double tp  = NormalizeDouble(ask + slD * InpTP_RR, dg);
   double lot = CalcLot(slD);
   if(lot <= 0) return;

   if(!trade.Buy(lot, _Symbol, ask, sl, tp, InpComment+"_B"))
   { Print("⚠️ BUY err: ", trade.ResultRetcodeDescription()); return; }

   ulong ticket = trade.ResultOrder();
   if(ticket == 0) return;

   AddPosTracker(ticket, iTime(_Symbol,PERIOD_M1,0), slD);
   g_lastBuyBar = iTime(_Symbol, PERIOD_M1, 0);
   Print("✅ BUY @",ask," SL=",sl," TP=",tp," lot=",lot,
         " slD=",DoubleToString(slD,5)," mult=",DoubleToString(g_lotMult,2),
         " | H4:",g_h4Up?"↑":"↓"," H1:",g_h1Up?"↑":"↓"," M5:",g_m5Up?"↑":"↓");
}

//====================================================================
//  ABRIR SELL
//====================================================================
void DoOpenSell()
{
   int    dg  = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double slD = CalcStructuralSL(false);
   double sl  = NormalizeDouble(bid + slD, dg);
   double tp  = NormalizeDouble(bid - slD * InpTP_RR, dg);
   double lot = CalcLot(slD);
   if(lot <= 0) return;

   if(!trade.Sell(lot, _Symbol, bid, sl, tp, InpComment+"_S"))
   { Print("⚠️ SELL err: ", trade.ResultRetcodeDescription()); return; }

   ulong ticket = trade.ResultOrder();
   if(ticket == 0) return;

   AddPosTracker(ticket, iTime(_Symbol,PERIOD_M1,0), slD);
   g_lastSellBar = iTime(_Symbol, PERIOD_M1, 0);
   Print("✅ SELL @",bid," SL=",sl," TP=",tp," lot=",lot,
         " slD=",DoubleToString(slD,5)," mult=",DoubleToString(g_lotMult,2),
         " | H4:",g_h4Dn?"↓":"↑"," H1:",g_h1Dn?"↓":"↑"," M5:",g_m5Dn?"↓":"↑");
}

//====================================================================
//  GESTIÓN DE POSICIONES ABIERTAS
//====================================================================
void ManagePositions()
{
   datetime curBarM1 = iTime(_Symbol, PERIOD_M1, 0);
   if(curBarM1 == 0) return;

   int dg = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double pt = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != _Symbol || posInfo.Magic() != InpMagic) continue;

      ulong  ticket  = posInfo.Ticket();
      bool   isBuy   = (posInfo.PositionType() == POSITION_TYPE_BUY);
      double openP   = posInfo.PriceOpen();
      double curSL   = posInfo.StopLoss();
      double curTP   = posInfo.TakeProfit();
      double vol     = posInfo.Volume();
      double profit  = posInfo.Profit();
      datetime tOpen = (datetime)posInfo.Time();
      double curP    = isBuy ? SymbolInfoDouble(_Symbol,SYMBOL_BID)
                             : SymbolInfoDouble(_Symbol,SYMBOL_ASK);

      // Buscar datos del tracker
      int idx = FindPosTracker(ticket);
      if(idx < 0) { AddPosTracker(ticket, tOpen, MathAbs(openP - curSL)); idx=FindPosTracker(ticket); }
      if(idx < 0) continue;

      double slDist = g_pos[idx].slDist;
      if(slDist <= 0) slDist = g_atrM1 * InpSL_ATR_Min;

      double movFav = isBuy ? (curP - openP) : (openP - curP);

      // === REGLA PRINCIPAL: NO cerrar en la misma vela de apertura ===
      bool sameCandle = (curBarM1 == g_pos[idx].openBar);

      // 1) Time stop (nunca en misma vela)
      if(!sameCandle && InpMaxBarsOpen > 0)
      {
         int barsOpen = Bars(_Symbol, PERIOD_M1, tOpen, TimeCurrent()) - 1;
         if(barsOpen >= InpMaxBarsOpen)
         { if(trade.PositionClose(ticket))
           { Print("⏱️ TimeStop ticket=",ticket," profit=$",DoubleToString(profit,2));
             RemovePosTracker(ticket); } continue; }
      }

      // 2) Cierre por reversión MTF fuerte (solo con ganancia y no en misma vela)
      if(!sameCandle && profit > 0)
      {
         bool mtfRev = isBuy ? (!g_h1Up && g_h1Dn && !g_m5Up)
                             : (!g_h1Dn && g_h1Up && !g_m5Dn);
         if(mtfRev)
         { if(trade.PositionClose(ticket))
           { Print("🔀 Reversión MTF ticket=",ticket," $",DoubleToString(profit,2));
             RemovePosTracker(ticket); } continue; }
      }

      // --- A partir de aquí: modificaciones de SL/TP (no cierre) ---

      // 3) Break Even (puede aplicarse incluso en misma vela si el mercado voló)
      if(InpUseBreakEven && !g_pos[idx].be && slDist > 0)
      {
         if(movFav >= InpBE_At * slDist)
         {
            double nSL; bool doMove = false;
            if(isBuy)  { nSL=NormalizeDouble(openP+pt,dg); doMove=(nSL>curSL+pt); }
            else       { nSL=NormalizeDouble(openP-pt,dg); doMove=(curSL==0||nSL<curSL-pt); }
            if(doMove)
            { if(trade.PositionModify(ticket,nSL,curTP))
              { g_pos[idx].be=true; Print("🛡️ BE ticket=",ticket); } }
         }
      }

      // 4) Cierre parcial (no en misma vela)
      if(!sameCandle && InpUsePartial && !g_pos[idx].partial && slDist > 0)
      {
         if(movFav >= InpPart_At * slDist)
         {
            double minV  = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
            double step  = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
            double cLot  = MathFloor(vol * InpPart_Pct/100.0 / step) * step;
            if(cLot >= minV && cLot < vol)
            { if(trade.PositionClosePartial(ticket,cLot))
              { g_pos[idx].partial=true;
                Print("💰 Parcial ",DoubleToString(InpPart_Pct,0),"% ticket=",ticket); } }
         }
      }

      // 5) Trailing fase 1 (Quantum style: SL a entrada + N×slDist)
      if(InpUseTrail && slDist > 0)
      {
         if(!g_pos[idx].trail1 && movFav >= InpTrail1_At * slDist)
         {
            double nSL; bool doMove=false;
            if(isBuy)  { nSL=NormalizeDouble(openP+InpTrail1_To*slDist,dg); doMove=(nSL>curSL+pt); }
            else       { nSL=NormalizeDouble(openP-InpTrail1_To*slDist,dg); doMove=(curSL==0||nSL<curSL-pt); }
            if(doMove && trade.PositionModify(ticket,nSL,curTP))
            { g_pos[idx].trail1=true; Print("📌 Trail1 ticket=",ticket," nSL=",NormalizeDouble(nSL,dg)); }
         }

         // Trailing fase 2 (dinámico, sigue al precio)
         if(g_pos[idx].trail1 && movFav >= InpTrail2_At * slDist)
         {
            double step2 = InpTrail2_Step * g_atrM1;
            double nSL; bool doMove=false;
            if(isBuy)  { nSL=NormalizeDouble(curP-step2,dg); doMove=(nSL>curSL+pt); }
            else       { nSL=NormalizeDouble(curP+step2,dg); doMove=(curSL==0||nSL<curSL-pt); }
            if(doMove) trade.PositionModify(ticket,nSL,curTP);
         }
      }
   }
}

//====================================================================
//  TRACKER DE POSICIONES
//====================================================================
void AddPosTracker(ulong ticket, datetime openBar, double slDist)
{
   if(g_posCount >= 10) return;
   g_pos[g_posCount].ticket  = ticket;
   g_pos[g_posCount].openBar = openBar;
   g_pos[g_posCount].slDist  = slDist;
   g_pos[g_posCount].partial = false;
   g_pos[g_posCount].trail1  = false;
   g_pos[g_posCount].trail2  = false;
   g_pos[g_posCount].be      = false;
   g_posCount++;
}

int FindPosTracker(ulong ticket)
{ for(int i=0;i<g_posCount;i++) if(g_pos[i].ticket==ticket) return i; return -1; }

void RemovePosTracker(ulong ticket)
{
   for(int i=0;i<g_posCount;i++)
   { if(g_pos[i].ticket==ticket)
     { for(int j=i;j<g_posCount-1;j++) g_pos[j]=g_pos[j+1];
       g_posCount--; return; } }
}

//====================================================================
//  OnTradeTransaction — ESTADÍSTICAS + RECOVERY
//====================================================================
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest     &req,
                        const MqlTradeResult      &res)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   ulong deal = trans.deal; if(!deal) return;
   if(!HistoryDealSelect(deal)) return;
   if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal,DEAL_ENTRY) != DEAL_ENTRY_OUT) return;
   if(HistoryDealGetInteger(deal,DEAL_MAGIC) != (long)InpMagic) return;

   ulong posId = (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID);
   RemovePosTracker(posId);

   double pnl = HistoryDealGetDouble(deal,DEAL_PROFIT)
              + HistoryDealGetDouble(deal,DEAL_SWAP)
              + HistoryDealGetDouble(deal,DEAL_COMMISSION);
   g_trades++;

   if(pnl >= 0)
   {
      g_wins++; g_grossWin += pnl;
      g_consecLoss = 0;
      // Reducción gradual tras ganancia
      if(InpReduceAfterWin && g_lotMult > 1.0)
      { g_lotMult = MathMax(1.0, g_lotMult - 0.1);
        Print("📉 Recovery reducido a x",DoubleToString(g_lotMult,2)); }
   }
   else
   {
      g_losses++; g_grossLoss += MathAbs(pnl);
      g_consecLoss++;
      // Activar recovery
      if(InpUseRecovery && g_consecLoss >= InpRecovMaxLoss)
      { g_lotMult = MathMin(InpRecovMaxMult, 1.0 + (g_consecLoss - InpRecovMaxLoss + 1) * (InpRecovMult - 1.0));
        Print("🔄 Recovery activado x",DoubleToString(g_lotMult,2)," (pérdidas seguidas: ",g_consecLoss,")"); }
   }

   double wr = (g_trades > 0) ? (double)g_wins / g_trades * 100.0 : 0;
   double pf = (g_grossLoss > 0) ? g_grossWin / g_grossLoss : 0;
   string icon = (pnl >= 0) ? "✅" : "❌";
   Print(icon," CIERRE $",DoubleToString(pnl,2)," | WR:",DoubleToString(wr,1),
         "% PF:",DoubleToString(pf,2)," LotMult:x",DoubleToString(g_lotMult,2));
}

//====================================================================
//  HELPERS
//====================================================================
void CheckDayReset()
{
   datetime day = iTime(_Symbol, PERIOD_D1, 0);
   if(day != g_lastDay && day > 0)
   { g_lastDay=day; g_dayStartBal=AccountInfoDouble(ACCOUNT_BALANCE);
     g_dayBlocked=false; g_posCount=0;
     Print("📅 Nuevo día | Bal=$",DoubleToString(g_dayStartBal,2)); }
}

bool ValidSession()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   if(InpNoFriday && dt.day_of_week==5 && dt.hour>=InpFriEnd) return false;
   return (dt.hour>=InpSessStart && dt.hour<InpSessEnd);
}

int CountMyPositions()
{
   int n=0;
   for(int i=0;i<PositionsTotal();i++)
   { ulong t=PositionGetTicket(i);
     if(!PositionSelectByTicket(t)) continue;
     if(PositionGetString(POSITION_SYMBOL)==_Symbol &&
        PositionGetInteger(POSITION_MAGIC)==(long)InpMagic) n++; }
   return n;
}

void CloseAll(string reason)
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   { if(!posInfo.SelectByIndex(i)) continue;
     if(posInfo.Symbol()!=_Symbol||posInfo.Magic()!=InpMagic) continue;
     trade.PositionClose(posInfo.Ticket());
     RemovePosTracker(posInfo.Ticket()); }
   Print("[",reason,"] Posiciones cerradas.");
}

//====================================================================
//  PANEL
//====================================================================
void LabelSet(string id,int x,int y,string txt,color cl,int sz=9)
{
   string n=g_pfx+id;
   if(ObjectFind(0,n)<0)
   { ObjectCreate(0,n,OBJ_LABEL,0,0,0);
     ObjectSetInteger(0,n,OBJPROP_CORNER,CORNER_LEFT_UPPER);
     ObjectSetInteger(0,n,OBJPROP_SELECTABLE,false);
     ObjectSetInteger(0,n,OBJPROP_HIDDEN,true);
     ObjectSetInteger(0,n,OBJPROP_BACK,false); }
   ObjectSetInteger(0,n,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,n,OBJPROP_YDISTANCE,y);
   ObjectSetString (0,n,OBJPROP_TEXT,txt);
   ObjectSetInteger(0,n,OBJPROP_COLOR,cl);
   ObjectSetInteger(0,n,OBJPROP_FONTSIZE,sz);
   ObjectSetString (0,n,OBJPROP_FONT,"Consolas");
}

void UpdatePanel()
{
   if(!InpShowPanel) return;
   int x=InpPanelX, y=InpPanelY, lh=15;
   color cT=clrWhite,cH=clrDeepSkyBlue,cG=clrLimeGreen,cR=clrTomato,cB=clrSilver,cGr=clrDimGray,cY=clrGold;

   double bal  = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq   = AccountInfoDouble(ACCOUNT_EQUITY);
   double dayP = eq - g_dayStartBal;
   double wr   = g_trades>0?(double)g_wins/g_trades*100.0:0;
   double pf   = g_grossLoss>0?g_grossWin/g_grossLoss:0;
   int    npos = CountMyPositions();
   double spread=(double)SymbolInfoInteger(_Symbol,SYMBOL_SPREAD);

   // Señal actual
   double fast[3],slow[3];
   ArraySetAsSeries(fast,true); ArraySetAsSeries(slow,true);
   bool crossUpNow=false, crossDnNow=false;
   if(CopyBuffer(hM1_EmaFast,0,0,3,fast)>=3 && CopyBuffer(hM1_EmaSlow,0,0,3,slow)>=3)
   { crossUpNow=(fast[1]>slow[1])&&(fast[2]<=slow[2]);
     crossDnNow=(fast[1]<slow[1])&&(fast[2]>=slow[2]); }
   bool m1Up=(fast[0]>slow[0]), m1Dn=(fast[0]<slow[0]);

   string sig="━ SIN SEÑAL";
   color sigC=cB;
   if(crossUpNow){sig="🟢 CRUCE BUY M1";sigC=cG;}
   else if(crossDnNow){sig="🔴 CRUCE SELL M1";sigC=cR;}
   else if(m1Up&&g_h1Up&&g_m5Up){sig="↑ BUY ALINEADO";sigC=cG;}
   else if(m1Dn&&g_h1Dn&&g_m5Dn){sig="↓ SELL ALINEADO";sigC=cR;}

   int n=0;
   LabelSet("T",  x,y+lh*n,"══ EURUSD PRO SCALPER v3.0 ══",cT,10);n++;
   LabelSet("D0", x,y+lh*n,"━━━━━━━━━━━━━━━━━━━━━━━━━━━",cGr,8);n++;
   LabelSet("SIG",x,y+lh*n,StringFormat("Señal M1  : %s",sig),sigC,9);n++;
   LabelSet("SP", x,y+lh*n,StringFormat("Spread    : %.0f pts | ATR: %.5f",spread,g_atrM1),
            spread<=InpMaxSpread?cG:cR,9);n++;
   LabelSet("D1", x,y+lh*n,"━━━━━━━━━━━━━━━━━━━━━━━━━━━",cGr,8);n++;
   LabelSet("H4", x,y+lh*n,StringFormat("H4 EMA%d/%d : %s",InpH4_EmaFast,InpH4_EmaSlow,g_h4Up?"📈 ALCISTA":(g_h4Dn?"📉 BAJISTA":"━")),cB,9);n++;
   LabelSet("H1", x,y+lh*n,StringFormat("H1 EMA%d/%d : %s",InpH1_EmaFast,InpH1_EmaSlow,g_h1Up?"📈 ALCISTA":(g_h1Dn?"📉 BAJISTA":"━")),cB,9);n++;
   LabelSet("M5", x,y+lh*n,StringFormat("M5 EMA%d/%d  : %s",InpM5_EmaFast,InpM5_EmaSlow,g_m5Up?"📈 ALCISTA":(g_m5Dn?"📉 BAJISTA":"━")),cB,9);n++;
   LabelSet("M1e",x,y+lh*n,StringFormat("M1 EMA%d/%d : %s",InpEmaFast,InpEmaSlow,m1Up?"↑ SOBRE EMA":(m1Dn?"↓ BAJO EMA":"━")),cB,9);n++;
   LabelSet("D2", x,y+lh*n,"━━━━━━━━━━━━━━━━━━━━━━━━━━━",cGr,8);n++;
   LabelSet("BA", x,y+lh*n,StringFormat("Balance   : $%.2f",bal),cB,9);n++;
   LabelSet("EQ", x,y+lh*n,StringFormat("Equity    : $%.2f",eq),eq>=bal?cG:cY,9);n++;
   LabelSet("DP", x,y+lh*n,StringFormat("PnL día   : %+.2f$",dayP),dayP>=0?cG:cR,9);n++;
   LabelSet("D3", x,y+lh*n,"━━━━━━━━━━━━━━━━━━━━━━━━━━━",cGr,8);n++;
   LabelSet("TR", x,y+lh*n,StringFormat("Trades    : %d  W:%d L:%d",g_trades,g_wins,g_losses),cB,9);n++;
   LabelSet("WR", x,y+lh*n,StringFormat("Win Rate  : %.1f%%",wr),wr>=60?cG:(wr>=50?cY:cR),9);n++;
   LabelSet("PF", x,y+lh*n,StringFormat("Prof.Fac  : %.2f",pf),pf>=1.5?cG:(pf>=1.0?cY:cR),9);n++;
   LabelSet("RC", x,y+lh*n,StringFormat("Recovery  : x%.2f  (pérd.seguidas:%d)",g_lotMult,g_consecLoss),
            g_lotMult>1.0?cY:cG,9);n++;
   LabelSet("PO", x,y+lh*n,StringFormat("Posiciones: %d / %d",npos,InpMaxPositions),cB,9);n++;
   LabelSet("ST", x,y+lh*n,StringFormat("Estado    : %s",g_dayBlocked?"🔴 BLOQUEADO DÍA":"🟢 ACTIVO"),
            g_dayBlocked?cR:cG,9);n++;

   string comTxt=StringFormat("PS3 | %s | Spr:%.0f | W:%d L:%d WR:%.0f%% PF:%.2f | Recov:x%.2f",
                              sig,spread,g_wins,g_losses,wr,pf,g_lotMult);
   Comment(comTxt);
   ChartRedraw();
}
//+------------------------------------------------------------------+
//  FIN — EURUSD Pro Scalper v3.0
//+------------------------------------------------------------------+
