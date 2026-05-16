//+------------------------------------------------------------------+
//|  EURUSD PRO SCALPER v2.0                                        |
//|  Arquitectura: 4-TF Trend Alignment + M1 Entry Trigger          |
//|                                                                  |
//|  H4  → Sesgo macro (EMA50/200)  – VETO DURO                    |
//|  H1  → Estructura (EMA21/50 + RSI55) – VETO DURO               |
//|  M15 → Momentum (MACD hist + EMA9) – FILTRO FUERTE             |
//|  M5  → Señal (EMA9 x EMA21) – GENERADOR                        |
//|  M1  → Trigger (RSI7 + Candle) – ENTRADA PRECISA               |
//|                                                                  |
//|  Solo opera a favor de la tendencia confirmada en 4 TF          |
//|  SL dinámico ATR | TP 2:1 | Trailing agresivo                   |
//|  Capital: $10 – $100.000+ | Sin martingala | Sin grid           |
//|                                                                  |
//|  Magic: 30001                                                    |
//+------------------------------------------------------------------+
#property copyright "EURUSD Pro Scalper v2.0"
#property version   "2.00"
#property strict

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>

CTrade        trade;
CPositionInfo pos;

//====================================================================
//  INPUTS
//====================================================================
input group "=== GENERAL ==="
input ulong  InpMagic          = 30001;
input string InpComment        = "ProScalper";
input int    InpSlippage       = 10;

input group "=== RIESGO ==="
input double InpRiskPct        = 1.0;     // % riesgo por trade
input double InpMaxSpreadPts   = 15.0;   // spread máx puntos (EURUSD ~1-2 pips normal)
input int    InpMaxPositions   = 1;      // posiciones simultáneas
input double InpMaxDailyLoss   = 4.0;   // % pérdida diaria máxima
input double InpMaxDailyProfit = 6.0;   // % ganancia diaria objetivo

input group "=== SL / TP ==="
input double InpSLMult         = 1.0;   // SL = N x ATR(14,M5)
input double InpTPMult         = 2.0;   // TP = N x ATR(14,M5) — ratio 1:2
input double InpTrailActivePct = 0.50;  // Activar trailing a N% del TP
input double InpTrailStepMult  = 0.30;  // Paso del trailing

input group "=== FILTROS DE ENTRADA ==="
input bool   InpUseTFH4        = true;   // Veto H4 (sesgo macro)
input bool   InpUseTFH1        = true;   // Veto H1 (estructura)
input bool   InpUseM15Filter   = true;   // Filtro M15 (momentum)
input double InpRSIH1Min       = 48.0;  // RSI H1 mínimo para BUY
input double InpRSIH1Max       = 52.0;  // RSI H1 máximo para SELL
input int    InpRSIM1Period    = 7;     // RSI M1 período
input double InpRSIM1Buy      = 52.0;  // RSI M1 mínimo para confirmar BUY
input double InpRSIM1Sell     = 48.0;  // RSI M1 máximo para confirmar SELL

input group "=== SESIONES ==="
input bool   InpFilterSession  = true;
input int    InpHourStart      = 7;      // Hora inicio (GMT broker)
input int    InpHourEnd        = 20;     // Hora fin
input bool   InpNoFriday       = true;
input int    InpFriHour        = 20;

input group "=== GESTIÓN DE POSICIÓN ==="
input bool   InpUseBreakEven   = true;
input double InpBEActivPct     = 0.40;   // Activar BE al 40% del TP
input bool   InpUsePartial     = true;
input double InpPartialPct     = 50.0;   // Cerrar 50% al llegar a 60% del TP
input double InpPartialAtPct   = 0.60;
input bool   InpUseTimeStop    = true;
input int    InpMaxBarsOpen    = 60;     // 60 x M5 = 5h máximo

input group "=== PANEL ==="
input bool   InpShowPanel      = true;

//====================================================================
//  HANDLES
//====================================================================
// H4
int hH4_EMA50, hH4_EMA200;
// H1
int hH1_EMA21, hH1_EMA50, hH1_RSI;
// M15
int hM15_EMA9, hM15_MACD;
// M5
int hM5_EMA9, hM5_EMA21, hM5_ATR;
// M1
int hM1_RSI, hM1_EMA9, hM1_EMA21;

//====================================================================
//  VARIABLES GLOBALES
//====================================================================
double g_dayStartBal  = 0;
datetime g_lastDay    = 0;
bool   g_dayBlocked   = false;

int    g_trades       = 0;
int    g_wins         = 0;
int    g_losses       = 0;
double g_grossWin     = 0;
double g_grossLoss    = 0;
double g_todayPnL     = 0;

// Control parcial
ulong  g_partialDone[];
int    g_partialCount = 0;

// Tracking señal previa (anti-doble entrada)
bool   g_lastSignalBuy  = false;
bool   g_lastSignalSell = false;
datetime g_lastSignalBar = 0;

// Estado MTF cacheado
bool   g_h4Buy = false, g_h4Sell = false;
bool   g_h1Buy = false, g_h1Sell = false;
bool   g_m15Buy= false, g_m15Sell= false;

double g_atr = 0;

string g_pfx = "PS2_";

//====================================================================
//  OnInit
//====================================================================
int OnInit()
{
   // Verificar símbolo
   if(StringFind(_Symbol,"EURUSD") < 0)
   { Alert("❌ Solo EURUSD"); return INIT_PARAMETERS_INCORRECT; }

   // Filling mode
   ENUM_ORDER_TYPE_FILLING fill = ORDER_FILLING_RETURN;
   uint fm = (uint)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((fm & SYMBOL_FILLING_IOC) != 0)      fill = ORDER_FILLING_IOC;
   else if((fm & SYMBOL_FILLING_FOK) != 0) fill = ORDER_FILLING_FOK;

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippage);
   trade.SetTypeFilling(fill);

   // H4
   hH4_EMA50  = iMA(_Symbol, PERIOD_H4,  50,  0, MODE_EMA, PRICE_CLOSE);
   hH4_EMA200 = iMA(_Symbol, PERIOD_H4,  200, 0, MODE_EMA, PRICE_CLOSE);
   // H1
   hH1_EMA21  = iMA(_Symbol, PERIOD_H1,  21,  0, MODE_EMA, PRICE_CLOSE);
   hH1_EMA50  = iMA(_Symbol, PERIOD_H1,  50,  0, MODE_EMA, PRICE_CLOSE);
   hH1_RSI    = iRSI(_Symbol,PERIOD_H1,  14, PRICE_CLOSE);
   // M15
   hM15_EMA9  = iMA(_Symbol, PERIOD_M15, 9,   0, MODE_EMA, PRICE_CLOSE);
   hM15_MACD  = iMACD(_Symbol,PERIOD_M15,12, 26, 9, PRICE_CLOSE);
   // M5
   hM5_EMA9   = iMA(_Symbol, PERIOD_M5,  9,   0, MODE_EMA, PRICE_CLOSE);
   hM5_EMA21  = iMA(_Symbol, PERIOD_M5,  21,  0, MODE_EMA, PRICE_CLOSE);
   hM5_ATR    = iATR(_Symbol,PERIOD_M5,  14);
   // M1
   hM1_RSI    = iRSI(_Symbol,PERIOD_M1,  InpRSIM1Period, PRICE_CLOSE);
   hM1_EMA9   = iMA(_Symbol, PERIOD_M1,  9,   0, MODE_EMA, PRICE_CLOSE);
   hM1_EMA21  = iMA(_Symbol, PERIOD_M1,  21,  0, MODE_EMA, PRICE_CLOSE);

   int handles[] = {
      hH4_EMA50, hH4_EMA200,
      hH1_EMA21, hH1_EMA50, hH1_RSI,
      hM15_EMA9, hM15_MACD,
      hM5_EMA9,  hM5_EMA21, hM5_ATR,
      hM1_RSI,   hM1_EMA9,  hM1_EMA21
   };
   for(int i = 0; i < ArraySize(handles); i++)
      if(handles[i] == INVALID_HANDLE)
      { Alert("❌ Handle inválido idx=", i); return INIT_FAILED; }

   g_dayStartBal = AccountInfoDouble(ACCOUNT_BALANCE);
   g_lastDay     = iTime(_Symbol, PERIOD_D1, 0);
   ArrayResize(g_partialDone, 0);

   if(InpShowPanel) CreatePanel();
   Print("✅ EURUSD Pro Scalper v2.0 | Bal: $", DoubleToString(g_dayStartBal,2));
   return INIT_SUCCEEDED;
}

//====================================================================
//  OnDeinit
//====================================================================
void OnDeinit(const int reason)
{
   Comment("");
   int handles[] = {
      hH4_EMA50, hH4_EMA200,
      hH1_EMA21, hH1_EMA50, hH1_RSI,
      hM15_EMA9, hM15_MACD,
      hM5_EMA9,  hM5_EMA21, hM5_ATR,
      hM1_RSI,   hM1_EMA9,  hM1_EMA21
   };
   for(int i = 0; i < ArraySize(handles); i++)
      if(handles[i] != INVALID_HANDLE) IndicatorRelease(handles[i]);
   ObjDelete();
}

//====================================================================
//  OnTick
//====================================================================
void OnTick()
{
   CheckDayReset();
   if(g_dayBlocked) { if(InpShowPanel) UpdatePanel(); return; }
   if(!IsNewBar(PERIOD_M1)) { ManagePositions(); if(InpShowPanel) UpdatePanel(); return; }

   // Actualizar ATR
   double atrBuf[1];
   if(CopyBuffer(hM5_ATR, 0, 1, 1, atrBuf) < 1) return;
   g_atr = atrBuf[0];
   if(g_atr <= 0) return;

   // Verificar límites diarios
   double bal  = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq   = AccountInfoDouble(ACCOUNT_EQUITY);
   double pnl  = eq - g_dayStartBal;
   if(pnl <= -(g_dayStartBal * InpMaxDailyLoss / 100.0))
   { CloseAll("MaxDailyLoss"); g_dayBlocked = true;
     Print("🛑 Límite de pérdida diaria alcanzado: $", pnl); if(InpShowPanel) UpdatePanel(); return; }
   if(pnl >= (g_dayStartBal * InpMaxDailyProfit / 100.0))
   { CloseAll("DailyTarget"); g_dayBlocked = true;
     Print("🎯 Target diario alcanzado: $", pnl); if(InpShowPanel) UpdatePanel(); return; }

   // Filtros horarios
   if(InpFilterSession && !ValidSession()) { ManagePositions(); if(InpShowPanel) UpdatePanel(); return; }

   // Spread
   double spread = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > InpMaxSpreadPts) { ManagePositions(); if(InpShowPanel) UpdatePanel(); return; }

   // Actualizar análisis MTF
   UpdateMTF();

   // Gestión de posiciones abiertas
   ManagePositions();

   // No abrir si ya tenemos máx posiciones
   if(CountPositions() >= InpMaxPositions) { if(InpShowPanel) UpdatePanel(); return; }

   // Evaluación de señal
   int signal = GetEntrySignal();
   if(signal == 0) { if(InpShowPanel) UpdatePanel(); return; }

   // Anti-doble: no repetir la misma dirección en la misma vela M5
   datetime curBarM5 = iTime(_Symbol, PERIOD_M5, 0);
   if(curBarM5 == g_lastSignalBar)
   { if((signal==1 && g_lastSignalBuy)||(signal==-1 && g_lastSignalSell))
     { if(InpShowPanel) UpdatePanel(); return; } }

   // Ejecutar
   if(signal == 1)  OpenBuy();
   if(signal == -1) OpenSell();

   if(InpShowPanel) UpdatePanel();
}

//====================================================================
//  ANÁLISIS MTF
//====================================================================
void UpdateMTF()
{
   // H4 — sesgo macro
   if(InpUseTFH4)
   {
      double e50[1], e200[1];
      if(CopyBuffer(hH4_EMA50, 0,1,1,e50)  > 0 &&
         CopyBuffer(hH4_EMA200,0,1,1,e200) > 0)
      { g_h4Buy=(e50[0]>e200[0]); g_h4Sell=(e50[0]<e200[0]); }
   }
   else { g_h4Buy=true; g_h4Sell=true; }

   // H1 — estructura
   if(InpUseTFH1)
   {
      double e21[1], e50[1], rsi[1];
      if(CopyBuffer(hH1_EMA21,0,1,1,e21)>0 &&
         CopyBuffer(hH1_EMA50,0,1,1,e50)>0 &&
         CopyBuffer(hH1_RSI,  0,1,1,rsi)>0)
      { g_h1Buy =(e21[0]>e50[0] && rsi[0]>InpRSIH1Min);
        g_h1Sell=(e21[0]<e50[0] && rsi[0]<InpRSIH1Max); }
   }
   else { g_h1Buy=true; g_h1Sell=true; }

   // M15 — momentum
   if(InpUseM15Filter)
   {
      double ema9[1], macdMain[2], macdSig[2];
      ArraySetAsSeries(macdMain, true);
      ArraySetAsSeries(macdSig,  true);
      if(CopyBuffer(hM15_EMA9, 0,1,1,ema9)     > 0 &&
         CopyBuffer(hM15_MACD, 0,0,2,macdMain)  > 0 &&
         CopyBuffer(hM15_MACD, 1,0,2,macdSig)   > 0)
      {
         // Histogram = main - signal
         double histCur  = macdMain[0] - macdSig[0];
         double histPrev = macdMain[1] - macdSig[1];
         double cM15     = iClose(_Symbol,PERIOD_M15,1);
         bool macdUp     = (histCur > 0 && histCur > histPrev);
         bool macdDn     = (histCur < 0 && histCur < histPrev);
         g_m15Buy  = (cM15 > ema9[0] && macdUp);
         g_m15Sell = (cM15 < ema9[0] && macdDn);
      }
   }
   else { g_m15Buy=true; g_m15Sell=true; }
}

//====================================================================
//  SEÑAL DE ENTRADA — retorna 1=BUY, -1=SELL, 0=nada
//====================================================================
int GetEntrySignal()
{
   // M5: EMA9 cruzando EMA21
   double e9M5[3], e21M5[3];
   ArraySetAsSeries(e9M5,true); ArraySetAsSeries(e21M5,true);
   if(CopyBuffer(hM5_EMA9, 0,0,3,e9M5)  < 3) return 0;
   if(CopyBuffer(hM5_EMA21,0,0,3,e21M5) < 3) return 0;

   bool m5CrossUp = (e9M5[1]>e21M5[1]) && (e9M5[2]<=e21M5[2]);
   bool m5CrossDn = (e9M5[1]<e21M5[1]) && (e9M5[2]>=e21M5[2]);

   // Si no hay cruce fresco en M5, verificar si estamos en tendencia clara
   bool m5TrendUp = (e9M5[0]>e21M5[0]) && (e9M5[1]>e21M5[1]);
   bool m5TrendDn = (e9M5[0]<e21M5[0]) && (e9M5[1]<e21M5[1]);

   bool m5Buy = m5CrossUp || (m5TrendUp && m5CrossUp);
   bool m5Sel = m5CrossDn || (m5TrendDn && m5CrossDn);

   // Solo usar cruces frescos para mayor precisión
   m5Buy = m5CrossUp;
   m5Sel = m5CrossDn;

   if(!m5Buy && !m5Sel) return 0;

   // M1: confirmación RSI + EMA
   double rsiM1[1], e9M1[1], e21M1[1];
   if(CopyBuffer(hM1_RSI,  0,1,1,rsiM1) < 1) return 0;
   if(CopyBuffer(hM1_EMA9, 0,1,1,e9M1)  < 1) return 0;
   if(CopyBuffer(hM1_EMA21,0,1,1,e21M1) < 1) return 0;

   bool m1Buy = (rsiM1[0] > InpRSIM1Buy)  && (e9M1[0] > e21M1[0]);
   bool m1Sel = (rsiM1[0] < InpRSIM1Sell) && (e9M1[0] < e21M1[0]);

   // Evaluar BUY
   if(m5Buy && m1Buy)
   { if(g_h4Buy && g_h1Buy && g_m15Buy) return 1; }

   // Evaluar SELL
   if(m5Sel && m1Sel)
   { if(g_h4Sell && g_h1Sell && g_m15Sell) return -1; }

   return 0;
}

//====================================================================
//  APERTURA BUY
//====================================================================
void OpenBuy()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   int    dg  = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double sl  = NormalizeDouble(ask - InpSLMult * g_atr, dg);
   double tp  = NormalizeDouble(ask + InpTPMult * g_atr, dg);
   double lot = CalcLot(InpSLMult * g_atr);
   if(lot <= 0) return;

   if(trade.Buy(lot, _Symbol, ask, sl, tp, InpComment))
   {
      g_lastSignalBuy  = true;
      g_lastSignalSell = false;
      g_lastSignalBar  = iTime(_Symbol, PERIOD_M5, 0);
      Print("✅ BUY lot=", lot, " @", ask, " SL=", sl, " TP=", tp,
            " | H4:", g_h4Buy?"✓":"✗", " H1:", g_h1Buy?"✓":"✗",
            " M15:", g_m15Buy?"✓":"✗");
   }
   else Print("⚠️ BUY error: ", trade.ResultRetcodeDescription());
}

//====================================================================
//  APERTURA SELL
//====================================================================
void OpenSell()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   int    dg  = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double sl  = NormalizeDouble(bid + InpSLMult * g_atr, dg);
   double tp  = NormalizeDouble(bid - InpTPMult * g_atr, dg);
   double lot = CalcLot(InpSLMult * g_atr);
   if(lot <= 0) return;

   if(trade.Sell(lot, _Symbol, bid, sl, tp, InpComment))
   {
      g_lastSignalBuy  = false;
      g_lastSignalSell = true;
      g_lastSignalBar  = iTime(_Symbol, PERIOD_M5, 0);
      Print("✅ SELL lot=", lot, " @", bid, " SL=", sl, " TP=", tp,
            " | H4:", g_h4Sell?"✓":"✗", " H1:", g_h1Sell?"✓":"✗",
            " M15:", g_m15Sell?"✓":"✗");
   }
   else Print("⚠️ SELL error: ", trade.ResultRetcodeDescription());
}

//====================================================================
//  GESTIÓN DE POSICIONES ABIERTAS
//====================================================================
void ManagePositions()
{
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      if(!pos.SelectByIndex(i)) continue;
      if(pos.Symbol() != _Symbol || pos.Magic() != InpMagic) continue;

      ulong  ticket  = pos.Ticket();
      bool   isBuy   = (pos.PositionType() == POSITION_TYPE_BUY);
      double openP   = pos.PriceOpen();
      double curSL   = pos.StopLoss();
      double curTP   = pos.TakeProfit();
      double vol     = pos.Volume();
      double profit  = pos.Profit();
      datetime tOpen = (datetime)pos.Time();
      int    dg      = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      double pt      = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double curP    = isBuy ? SymbolInfoDouble(_Symbol,SYMBOL_BID)
                             : SymbolInfoDouble(_Symbol,SYMBOL_ASK);

      double slDist  = (curTP > 0 && curSL > 0) ? MathAbs(openP - curSL) : g_atr * InpSLMult;
      double tpDist  = (curTP > 0) ? MathAbs(curTP - openP) : g_atr * InpTPMult;
      double movFav  = isBuy ? (curP - openP) : (openP - curP);

      // 1) Time stop
      if(InpUseTimeStop)
      {
         int barsOpen = Bars(_Symbol, PERIOD_M5, tOpen, TimeCurrent()) - 1;
         if(barsOpen >= InpMaxBarsOpen)
         { trade.PositionClose(ticket);
           Print("⏱️ Time stop ticket=", ticket, " profit=$", profit); continue; }
      }

      // 2) Cierre por reversión de tendencia (H1 gira)
      if(isBuy && !g_h1Buy && g_h1Sell && profit > 0)
      { trade.PositionClose(ticket);
        Print("🔀 Cierre tendencia revertida BUY $", profit); continue; }
      if(!isBuy && !g_h1Sell && g_h1Buy && profit > 0)
      { trade.PositionClose(ticket);
        Print("🔀 Cierre tendencia revertida SELL $", profit); continue; }

      // 3) Break Even
      if(InpUseBreakEven && slDist > 0)
      {
         double beTrig = InpBEActivPct * tpDist;
         if(movFav >= beTrig)
         {
            double nSL; bool doMove = false;
            if(isBuy)  { nSL=NormalizeDouble(openP+pt,dg); doMove=(nSL>curSL+pt); }
            else       { nSL=NormalizeDouble(openP-pt,dg); doMove=(curSL==0||nSL<curSL-pt); }
            if(doMove) trade.PositionModify(ticket, nSL, curTP);
         }
      }

      // 4) Cierre parcial
      if(InpUsePartial && !IsPartialDone(ticket) && tpDist > 0)
      {
         double partTrig = InpPartialAtPct * tpDist;
         if(movFav >= partTrig)
         {
            double minV  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
            double step  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
            double cLot  = MathFloor(vol * InpPartialPct / 100.0 / step) * step;
            if(cLot >= minV && cLot < vol)
            { if(trade.PositionClosePartial(ticket, cLot))
              { MarkPartialDone(ticket);
                Print("💰 Parcial 50% ticket=", ticket, " cLot=", cLot); } }
         }
      }

      // 5) Trailing stop
      ApplyTrailing(ticket, isBuy, openP, curSL, curTP, curP, tpDist);
   }
}

//====================================================================
//  TRAILING STOP
//====================================================================
void ApplyTrailing(ulong ticket, bool isBuy, double openP, double curSL,
                   double curTP, double curP, double tpDist)
{
   if(g_atr <= 0 || tpDist <= 0) return;
   double movFav = isBuy ? (curP-openP) : (openP-curP);
   if(movFav < InpTrailActivePct * tpDist) return;

   double step = InpTrailStepMult * g_atr;
   int    dg   = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double pt   = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   if(isBuy)
   { double nSL=NormalizeDouble(curP-step,dg);
     if(nSL>curSL+pt) trade.PositionModify(ticket,nSL,curTP); }
   else
   { double nSL=NormalizeDouble(curP+step,dg);
     if(curSL==0||nSL<curSL-pt) trade.PositionModify(ticket,nSL,curTP); }
}

//====================================================================
//  CÁLCULO DE LOTE — UNIVERSAL (desde $10)
//====================================================================
double CalcLot(double slDist)
{
   if(slDist <= 0) return 0;
   double bal    = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk   = bal * InpRiskPct / 100.0;
   double tv     = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double ts     = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double minV   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxV   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(tv<=0||ts<=0) return minV;

   // Valor en dinero de 1 pip de movimiento para 1 lote
   double pipVal = tv / ts * _Point;
   if(pipVal <= 0) return minV;
   double lot = risk / ((slDist / _Point) * pipVal);

   // Micro capital: no superar 2 lotes mínimos
   if(bal < 50.0)  lot = MathMin(lot, minV * 2.0);
   else if(bal < 200.0) lot = MathMin(lot, minV * 10.0);

   lot = MathFloor(lot / step) * step;
   lot = MathMax(minV, MathMin(maxV, lot));
   return NormalizeDouble(lot, 2);
}

//====================================================================
//  HELPERS
//====================================================================
bool IsNewBar(ENUM_TIMEFRAMES tf)
{
   static datetime lastBarM1 = 0;
   static datetime lastBarM5 = 0;
   datetime cur = iTime(_Symbol, tf, 0);
   if(cur == 0) return false;
   if(tf == PERIOD_M1)
   { if(cur == lastBarM1) return false; lastBarM1 = cur; return true; }
   // M5 and others
   if(cur == lastBarM5) return false; lastBarM5 = cur; return true;
}

bool ValidSession()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   if(InpNoFriday && dt.day_of_week==5 && dt.hour>=InpFriHour) return false;
   return (dt.hour>=InpHourStart && dt.hour<InpHourEnd);
}

int CountPositions()
{
   int n=0;
   for(int i=0;i<PositionsTotal();i++)
   { ulong t=PositionGetTicket(i);
     if(PositionSelectByTicket(t))
     { if(PositionGetString(POSITION_SYMBOL)==_Symbol &&
          PositionGetInteger(POSITION_MAGIC)==(long)InpMagic) n++; } }
   return n;
}

void CloseAll(string reason)
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   { if(!pos.SelectByIndex(i)) continue;
     if(pos.Symbol()!=_Symbol||pos.Magic()!=InpMagic) continue;
     trade.PositionClose(pos.Ticket()); }
   Print("[",reason,"] Todas las posiciones cerradas.");
}

void CheckDayReset()
{
   datetime day = iTime(_Symbol, PERIOD_D1, 0);
   if(day != g_lastDay)
   { g_lastDay=day; g_dayStartBal=AccountInfoDouble(ACCOUNT_BALANCE);
     g_dayBlocked=false; g_todayPnL=0;
     g_partialCount=0; ArrayResize(g_partialDone,0);
     Print("📅 Nuevo día | Balance: $", g_dayStartBal); }
}

bool IsPartialDone(ulong ticket)
{ for(int i=0;i<g_partialCount;i++) if(g_partialDone[i]==ticket) return true; return false; }

void MarkPartialDone(ulong ticket)
{ if(IsPartialDone(ticket)) return;
  ArrayResize(g_partialDone,g_partialCount+1);
  g_partialDone[g_partialCount]=ticket; g_partialCount++; }

//====================================================================
//  OnTradeTransaction — estadísticas
//====================================================================
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest     &req,
                        const MqlTradeResult      &res)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   ulong deal = trans.deal; if(!deal) return;
   if(!HistoryDealSelect(deal)) return;
   if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal,DEAL_ENTRY)!=DEAL_ENTRY_OUT) return;
   if(HistoryDealGetInteger(deal,DEAL_MAGIC)!=(long)InpMagic) return;

   double pnl = HistoryDealGetDouble(deal,DEAL_PROFIT)
              + HistoryDealGetDouble(deal,DEAL_SWAP)
              + HistoryDealGetDouble(deal,DEAL_COMMISSION);
   g_trades++;
   g_todayPnL += pnl;
   if(pnl >= 0) { g_wins++;   g_grossWin  += pnl; }
   else          { g_losses++; g_grossLoss += MathAbs(pnl); }

   string icon = (pnl>=0)?"✅":"❌";
   Print(icon," CIERRE $",DoubleToString(pnl,2),
         " | WR: ", g_trades>0?DoubleToString((double)g_wins/g_trades*100,1)+"%":"-%",
         " PF: ", g_grossLoss>0?DoubleToString(g_grossWin/g_grossLoss,2):"∞");
}

//====================================================================
//  PANEL
//====================================================================
void LabelCreate(string id, int x, int y, string txt, color cl, int sz=9)
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

void ObjDelete() { ObjectsDeleteAll(0,g_pfx); ChartRedraw(); }

void CreatePanel() { UpdatePanel(); }

void UpdatePanel()
{
   if(!InpShowPanel) return;
   int x=12, y=28, lh=15;
   color cT=clrWhite,cH=clrDeepSkyBlue,cG=clrLimeGreen,cR=clrTomato;
   color cB=clrSilver,cGr=clrDimGray,cY=clrGold;

   double bal  = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq   = AccountInfoDouble(ACCOUNT_EQUITY);
   double dayP = eq - g_dayStartBal;
   double wr   = g_trades>0?(double)g_wins/g_trades*100.0:0;
   double pf   = g_grossLoss>0?g_grossWin/g_grossLoss:0;
   string wrStr= g_trades>0?DoubleToString(wr,1)+"%":"--";
   string pfStr= g_grossLoss>0?DoubleToString(pf,2):"∞";
   double spread=(double)SymbolInfoInteger(_Symbol,SYMBOL_SPREAD);

   // Estado de los 4 TF para el panel
   string h4s = (g_h4Buy?"📈":(g_h4Sell?"📉":"━"));
   string h1s = (g_h1Buy?"📈":(g_h1Sell?"📉":"━"));
   string m15s= (g_m15Buy?"📈":(g_m15Sell?"📉":"━"));

   // M5 EMA cruce actual
   double e9[1],e21[1];
   bool m5up=false,m5dn=false;
   if(CopyBuffer(hM5_EMA9, 0,1,1,e9) >0 &&
      CopyBuffer(hM5_EMA21,0,1,1,e21)>0)
   { m5up=(e9[0]>e21[0]); m5dn=(e9[0]<e21[0]); }
   string m5s = m5up?"📈":(m5dn?"📉":"━");

   // M1 RSI
   double rM1[1];
   string m1s = "--";
   if(CopyBuffer(hM1_RSI,0,1,1,rM1)>0)
      m1s = DoubleToString(rM1[0],1);

   // Alineación
   bool buyAlign  = g_h4Buy  && g_h1Buy  && g_m15Buy  && m5up;
   bool sellAlign = g_h4Sell && g_h1Sell && g_m15Sell && m5dn;
   string align   = buyAlign?"🟢 BUY SETUP":(sellAlign?"🔴 SELL SETUP":"⚪ SIN SEÑAL");

   int n=0;
   LabelCreate("T",  x, y+lh*n, "══ EURUSD PRO SCALPER v2.0 ══",cT,10); n++;
   LabelCreate("D0", x, y+lh*n, "━━━━━━━━━━━━━━━━━━━━━━━━━━━━",cGr,8); n++;
   LabelCreate("ST", x, y+lh*n, StringFormat("Estado  : %s",g_dayBlocked?"🔴 BLOQUEADO":"🟢 ACTIVO"),
               g_dayBlocked?cR:cG,9); n++;
   LabelCreate("SP", x, y+lh*n, StringFormat("Spread  : %.0f pts | ATR: %.5f",spread,g_atr),
               spread<=InpMaxSpreadPts?cG:cR,9); n++;
   LabelCreate("D1", x, y+lh*n, "━━━━━━━━━━━━━━━━━━━━━━━━━━━━",cGr,8); n++;
   LabelCreate("H4", x, y+lh*n, StringFormat("H4 (Sesgo)  : %s EMA50/200",h4s), cB, 9); n++;
   LabelCreate("H1", x, y+lh*n, StringFormat("H1 (Estruc) : %s EMA21/50+RSI",h1s), cB, 9); n++;
   LabelCreate("M5a",x, y+lh*n, StringFormat("M15(Moment) : %s MACD+EMA9",m15s), cB, 9); n++;
   LabelCreate("M5b",x, y+lh*n, StringFormat("M5 (Señal)  : %s EMA9x21",m5s), cB, 9); n++;
   LabelCreate("M1", x, y+lh*n, StringFormat("M1 (Trigger): RSI7=%s",m1s), cB, 9); n++;
   LabelCreate("D2", x, y+lh*n, "━━━━━━━━━━━━━━━━━━━━━━━━━━━━",cGr,8); n++;
   LabelCreate("AL", x, y+lh*n, StringFormat("Alineación  : %s",align),
               buyAlign?cG:(sellAlign?cR:cB),9); n++;
   LabelCreate("D3", x, y+lh*n, "━━━━━━━━━━━━━━━━━━━━━━━━━━━━",cGr,8); n++;
   LabelCreate("BA", x, y+lh*n, StringFormat("Balance : $%.2f",bal), cB, 9); n++;
   LabelCreate("EQ", x, y+lh*n, StringFormat("Equity  : $%.2f",eq), eq>=bal?cG:cY, 9); n++;
   LabelCreate("DP", x, y+lh*n, StringFormat("PnL día : %+.2f$",dayP),
               dayP>=0?cG:cR,9); n++;
   LabelCreate("D4", x, y+lh*n, "━━━━━━━━━━━━━━━━━━━━━━━━━━━━",cGr,8); n++;
   LabelCreate("TR", x, y+lh*n, StringFormat("Trades  : %d  W:%d L:%d",g_trades,g_wins,g_losses), cB, 9); n++;
   LabelCreate("WR", x, y+lh*n, StringFormat("WinRate : %s", wrStr),
               wr>=60?cG:(wr>=50?cY:cR),9); n++;
   LabelCreate("PF", x, y+lh*n, StringFormat("Prof.Fac: %s", pfStr),
               pf>=1.5?cG:(pf>=1.0?cY:cR),9); n++;
   LabelCreate("PO", x, y+lh*n, StringFormat("Pos.Abts: %d",CountPositions()), cB, 9); n++;

   // Comment para info adicional rápida
   Comment("EURUSD Pro Scalper v2 | H4:", h4s, " H1:", h1s, " M15:", m15s,
           " M5:", m5s, " | ", align, " | Spread:", DoubleToString(spread,0),
           " | WR:", wrStr, " PF:", pfStr);
   ChartRedraw();
}
//+------------------------------------------------------------------+
//  FIN — EURUSD Pro Scalper v2.0
//+------------------------------------------------------------------+
