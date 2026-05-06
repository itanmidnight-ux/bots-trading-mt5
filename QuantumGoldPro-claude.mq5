//+------------------------------------------------------------------+
//| QuantumGold Pro v4.0                                            |
//| Inspirado en Quantum Queen MT5                                  |
//| Grid Inteligente + 6 Estrategias + Basket Management           |
//| XAUUSD | M1-M5-M15-H1 | FBS & Metaquotes-Demo                 |
//| Leverage 1:1000 compatible                                      |
//+------------------------------------------------------------------+
#property copyright "QuantumGold Pro v4"
#property version   "4.00"
#property strict
#property description "Grid inteligente multi-estrategia para XAUUSD"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

//--- Enumeraciones
enum ENUM_RISK_PROFILE
{
   RISK_CONSERVATIVE = 0,  // Conservative
   RISK_BALANCED     = 1,  // Balanced
   RISK_AGGRESSIVE   = 2,  // Aggressive
   RISK_EXTREME      = 3   // Extreme
};

enum ENUM_GRID_DIRECTION
{
   GRID_BOTH  = 0,  // Both (Buy & Sell)
   GRID_BUY   = 1,  // Buy Only
   GRID_SELL  = 2   // Sell Only
};

//=== INPUTS PRINCIPALES ===
input group "=== PERFIL DE RIESGO ==="
input ENUM_RISK_PROFILE RiskProfile   = RISK_BALANCED;  // Perfil de riesgo
input double            ManualRiskPct = 0.0;             // Riesgo % manual (0=auto por perfil)

input group "=== GRID SETTINGS ==="
input double   GridStep        = 150.0;   // Paso del grid en puntos
input int      MaxGridLevels   = 5;       // Niveles máximos del grid
input double   GridLotBase     = 0.01;    // Lote base del grid
input double   GridLotMulti    = 1.3;     // Multiplicador lotes por nivel
input ENUM_GRID_DIRECTION GridDir = GRID_BOTH; // Dirección del grid
input bool     UseSmartLots    = true;    // Smart lot sizing (proporcional al balance)

input group "=== BASKET MANAGEMENT ==="
input double   BasketTP_USD    = 10.0;   // Basket Take Profit en USD
input double   BasketTP_Pct    = 0.5;    // Basket TP en % del balance (0=desactivado)
input double   BasketSL_USD    = 50.0;   // Basket Stop Loss en USD (0=desactivado)
input bool     UsePartialBasket= true;   // Cierre parcial 50% en BasketTP/2
input bool     UseBasketTrail  = true;   // Trailing en basket

input group "=== ESTRATEGIAS DE ENTRADA ==="
input bool     S1_RSI_EMA    = true;    // S1: RSI+EMA200 mean reversion
input bool     S2_EMA_Cross  = true;    // S2: EMA9/21 cruce + EMA200
input bool     S3_Asian      = true;    // S3: Asian session breakout
input bool     S4_EMA_Bounce = true;    // S4: EMA200 bounce scalp
input bool     S5_Volume     = true;    // S5: High-volume impulse
input bool     S6_NY_Open    = true;    // S6: NY open momentum
input int      MinConfirm    = 2;       // Señales mínimas para abrir grid

input group "=== INDICADORES ==="
input int      RSI_Period    = 14;      // RSI periodo
input double   RSI_OS        = 35.0;    // RSI sobreventa
input double   RSI_OB        = 65.0;    // RSI sobrecompra
input int      EMA_Fast      = 9;       // EMA rápida
input int      EMA_Med       = 21;      // EMA media
input int      EMA_Slow      = 200;     // EMA lenta (filtro macro)
input int      ATR_Period    = 14;      // ATR periodo
input double   VOL_Mult      = 1.5;     // Multiplicador volumen impulso

input group "=== FILTROS ==="
input int      MaxSpread     = 50;      // Spread máximo permitido (puntos)
input double   MinATR        = 0.5;     // ATR mínimo para operar
input double   MaxATR        = 20.0;    // ATR máximo (evitar spikes)
input bool     UseSessionFilter = true; // Filtro de sesión
input int      SessionStart  = 1;       // Hora inicio UTC
input int      SessionEnd    = 22;      // Hora fin UTC

input group "=== SESIÓN ASIÁTICA (S3) ==="
input int      Asian_Start   = 0;       // Asia inicio UTC
input int      Asian_End     = 3;       // Asia fin UTC
input int      NY_Start      = 14;      // NY apertura UTC

input group "=== MULTI-TIMEFRAME BIAS ==="
input ENUM_TIMEFRAMES HTF1   = PERIOD_H1;  // Timeframe alto 1
input ENUM_TIMEFRAMES HTF2   = PERIOD_H4;  // Timeframe alto 2
input bool     UseHTFBias    = true;        // Usar filtro multi-TF

input group "=== GENERAL ==="
input int      Magic         = 404040;  // Número mágico
input string   TradeComment  = "QGP4";  // Comentario de trades
input bool     ShowDashboard = true;    // Mostrar panel

//=== GLOBALES ===
CTrade         Trade;
CPositionInfo  PosInfo;
COrderInfo     OrdInfo;

// Handles indicadores TF actual
int h_rsi, h_ef, h_em, h_es, h_atr;
// Handles HTF para bias
int h_es_htf1, h_ef_htf1, h_es_htf2;

// Asian range
double   g_aHigh   = 0.0;
double   g_aLow    = 1e10;
datetime g_aDate   = 0;
bool     g_aReady  = false;

// Grid tracking
double   g_gridBase    = 0.0;   // Precio base del grid actual
bool     g_gridActive  = false; // Grid activo
int      g_gridDir     = 0;     // 1=bull -1=bear 0=ambos
datetime g_gridOpenTime= 0;

// Basket partial flag
bool     g_partialDone = false;
double   g_basketPeak  = -1e10;

//+------------------------------------------------------------------+
int OnInit()
{
   Trade.SetExpertMagicNumber(Magic);
   Trade.SetDeviationInPoints(50);
   Trade.SetTypeFilling(ORDER_FILLING_IOC);
   Trade.SetAsyncMode(false);

   ENUM_TIMEFRAMES tf = Period();
   h_rsi  = iRSI(_Symbol, tf, RSI_Period, PRICE_CLOSE);
   h_ef   = iMA (_Symbol, tf, EMA_Fast,  0, MODE_EMA, PRICE_CLOSE);
   h_em   = iMA (_Symbol, tf, EMA_Med,   0, MODE_EMA, PRICE_CLOSE);
   h_es   = iMA (_Symbol, tf, EMA_Slow,  0, MODE_EMA, PRICE_CLOSE);
   h_atr  = iATR(_Symbol, tf, ATR_Period);

   h_es_htf1 = iMA(_Symbol, HTF1, EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
   h_ef_htf1 = iMA(_Symbol, HTF1, EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
   h_es_htf2 = iMA(_Symbol, HTF2, EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);

   if(h_rsi==INVALID_HANDLE || h_ef==INVALID_HANDLE || h_em==INVALID_HANDLE ||
      h_es==INVALID_HANDLE  || h_atr==INVALID_HANDLE ||
      h_es_htf1==INVALID_HANDLE || h_ef_htf1==INVALID_HANDLE ||
      h_es_htf2==INVALID_HANDLE)
   {
      Alert("QGP4: Fallo al crear indicadores en ",_Symbol);
      return INIT_FAILED;
   }

   Print("QuantumGold Pro v4 iniciado | ",_Symbol," ",EnumToString(tf),
         " | Perfil: ",EnumToString(RiskProfile));
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(h_rsi);  IndicatorRelease(h_ef);
   IndicatorRelease(h_em);   IndicatorRelease(h_es);
   IndicatorRelease(h_atr);  IndicatorRelease(h_es_htf1);
   IndicatorRelease(h_ef_htf1); IndicatorRelease(h_es_htf2);
   Comment("");
}

//+------------------------------------------------------------------+
void OnTick()
{
   // 1. Actualizar rango asiático en cada tick
   UpdateAsianRange();

   // 2. Gestión de basket activo (trailing, cierre)
   ManageBasket();

   // 3. Nueva barra: generar señales
   static datetime lastBar = 0;
   datetime curBar = iTime(_Symbol, Period(), 0);
   if(curBar == lastBar) return;
   lastBar = curBar;

   // 4. Filtros globales
   if(!PassGlobalFilters()) return;

   // 5. Si ya hay grid activo, solo gestionar (no abrir nuevo)
   if(g_gridActive && CountMyPositions() > 0) return;

   // 6. Si el grid antiguo se cerró, resetear estado
   if(CountMyPositions() == 0)
   {
      g_gridActive   = false;
      g_gridBase     = 0.0;
      g_partialDone  = false;
      g_basketPeak   = -1e10;
   }

   // 7. Cargar indicadores
   double rsi[], ef[], em[], es[], atr[];
   ArraySetAsSeries(rsi,true); ArraySetAsSeries(ef,true);
   ArraySetAsSeries(em,true);  ArraySetAsSeries(es,true);
   ArraySetAsSeries(atr,true);

   if(CopyBuffer(h_rsi,0,0,3,rsi)<3) return;
   if(CopyBuffer(h_ef, 0,0,3,ef) <3) return;
   if(CopyBuffer(h_em, 0,0,3,em) <3) return;
   if(CopyBuffer(h_es, 0,0,3,es) <3) return;
   if(CopyBuffer(h_atr,0,0,3,atr)<3) return;

   double atrV = atr[1];
   if(atrV < MinATR || atrV > MaxATR) return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // 8. HTF Bias
   int htfBias = GetHTFBias();

   // 9. Contar señales por dirección
   int bSig = 0, sSig = 0;
   EvaluateStrategies(rsi,ef,em,es,atr,ask,bid,htfBias,bSig,sSig);

   int conf = MathMax(1, MathMin(MinConfirm, 6));

   // 10. Apertura de grid
   if(bSig >= conf && GridDir != GRID_SELL)
      OpenGrid(ORDER_TYPE_BUY, ask, bid, atrV);
   else if(sSig >= conf && GridDir != GRID_BUY)
      OpenGrid(ORDER_TYPE_SELL, ask, bid, atrV);

   // 11. Dashboard
   if(ShowDashboard) DrawDashboard(bSig, sSig, atrV, htfBias);
}

//+------------------------------------------------------------------+
// Filtros globales: spread, sesión, mercado abierto
bool PassGlobalFilters()
{
   // Spread
   long spreadPts = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spreadPts > MaxSpread) return false;

   // Sesión
   if(UseSessionFilter)
   {
      int h = GetHourUTC();
      if(h < SessionStart || h >= SessionEnd) return false;
   }

   return true;
}

//+------------------------------------------------------------------+
// HTF Bias: +1 alcista, -1 bajista, 0 neutral
int GetHTFBias()
{
   if(!UseHTFBias) return 0;

   double es1[], ef1[], es2[];
   ArraySetAsSeries(es1,true); ArraySetAsSeries(ef1,true);
   ArraySetAsSeries(es2,true);

   if(CopyBuffer(h_es_htf1,0,0,2,es1)<2) return 0;
   if(CopyBuffer(h_ef_htf1,0,0,2,ef1)<2) return 0;
   if(CopyBuffer(h_es_htf2,0,0,2,es2)<2) return 0;

   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   int vote = 0;
   if(price > es1[1]) vote++; else vote--;
   if(ef1[1] > es1[1]) vote++; else vote--;
   if(price > es2[1]) vote++; else vote--;

   if(vote >= 2)  return  1;
   if(vote <= -2) return -1;
   return 0;
}

//+------------------------------------------------------------------+
// Evalúa las 6 estrategias y acumula señales
void EvaluateStrategies(double &rsi[], double &ef[], double &em[],
                        double &es[], double &atr[], double ask, double bid,
                        int htfBias, int &bSig, int &sSig)
{
   double atrV = atr[1];
   int hUTC    = GetHourUTC();

   //--- S1: RSI mean reversion + EMA200
   if(S1_RSI_EMA)
   {
      if(rsi[1]<RSI_OS && bid>es[1] && htfBias>=0) bSig++;
      if(rsi[1]>RSI_OB && ask<es[1] && htfBias<=0) sSig++;
   }

   //--- S2: EMA9/21 crossover + EMA200 trend
   if(S2_EMA_Cross)
   {
      if(ef[2]<em[2] && ef[1]>=em[1] && bid>es[1]) bSig++;
      if(ef[2]>em[2] && ef[1]<=em[1] && ask<es[1]) sSig++;
   }

   //--- S3: Asian breakout en apertura Londres
   if(S3_Asian && g_aReady && g_aHigh>0.0 && g_aLow<1e9)
   {
      if(hUTC>=Asian_End && hUTC<London_StartHour()+2)
      {
         if(ask>g_aHigh) bSig++;
         if(bid<g_aLow)  sSig++;
      }
   }

   //--- S4: EMA200 bounce (precio dentro de 0.3 ATR de EMA200)
   if(S4_EMA_Bounce)
   {
      if(MathAbs(bid-es[1]) < 0.3*atrV)
      {
         if(bid>es[1] && ef[1]>em[1]) bSig++;
         if(ask<es[1] && ef[1]<em[1]) sSig++;
      }
   }

   //--- S5: High-volume impulse candle
   if(S5_Volume)
   {
      long vol[];
      ArraySetAsSeries(vol,true);
      if(CopyTickVolume(_Symbol,Period(),0,3,vol)==3)
      {
         double o1=iOpen(_Symbol,Period(),1);
         double c1=iClose(_Symbol,Period(),1);
         double b1=MathAbs(c1-o1);
         if(vol[1]>VOL_Mult*vol[2] && b1>atrV*0.5)
         {
            if(c1>o1) bSig++;
            if(c1<o1) sSig++;
         }
      }
   }

   //--- S6: NY open momentum
   if(S6_NY_Open && hUTC==NY_Start)
   {
      double o1=iOpen(_Symbol,Period(),1);
      double c1=iClose(_Symbol,Period(),1);
      double b1=MathAbs(c1-o1);
      if(b1>0.5*atrV)
      {
         if(c1>o1) bSig++;
         if(c1<o1) sSig++;
      }
   }
}

//+------------------------------------------------------------------+
// Abre el grid de órdenes alrededor del precio base
void OpenGrid(ENUM_ORDER_TYPE firstType, double ask, double bid, double atrV)
{
   double stepPts  = GridStep * SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   int    digs     = (int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   double riskPct  = GetRiskPct();

   // Calcular lote base con smart sizing
   double baseLot = GridLotBase;
   if(UseSmartLots)
   {
      double bal  = AccountInfoDouble(ACCOUNT_BALANCE);
      double tv   = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
      double ts   = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
      double slD  = stepPts * MaxGridLevels;
      if(tv>0.0 && ts>0.0 && slD>0.0)
      {
         double risk = bal * riskPct / 100.0;
         baseLot = risk / (slD / ts * tv);
         double vstep = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
         baseLot = MathFloor(baseLot/vstep)*vstep;
         baseLot = MathMax(0.01, MathMin(5.0, baseLot));
      }
   }

   double priceBase = (firstType==ORDER_TYPE_BUY) ? ask : bid;
   g_gridBase     = priceBase;
   g_gridActive   = true;
   g_gridOpenTime = TimeCurrent();
   g_partialDone  = false;
   g_basketPeak   = -1e10;

   // Nivel 0 (primera entrada inmediata)
   double lot0 = NormalizeDouble(baseLot, 2);
   PlaceOrder(firstType, lot0, priceBase, atrV, stepPts, digs, 0);

   // Niveles adicionales del grid en la misma dirección
   for(int lvl=1; lvl<MaxGridLevels; lvl++)
   {
      double lotLvl = NormalizeDouble(baseLot * MathPow(GridLotMulti, lvl), 2);
      lotLvl = MathMax(0.01, lotLvl);
      double priceLvl;
      if(firstType==ORDER_TYPE_BUY)
         priceLvl = NormalizeDouble(priceBase - stepPts*lvl, digs); // comprar más barato
      else
         priceLvl = NormalizeDouble(priceBase + stepPts*lvl, digs); // vender más caro

      PlaceOrder(firstType, lotLvl, priceLvl, atrV, stepPts, digs, lvl);
   }

   // Si grid bidireccional, poner nivel opuesto (hedge parcial)
   if(GridDir==GRID_BOTH)
   {
      ENUM_ORDER_TYPE opp = (firstType==ORDER_TYPE_BUY)?ORDER_TYPE_SELL:ORDER_TYPE_BUY;
      double oppPrice = (opp==ORDER_TYPE_SELL)?
                        NormalizeDouble(priceBase+stepPts,digs):
                        NormalizeDouble(priceBase-stepPts,digs);
      PlaceOrder(opp, lot0, oppPrice, atrV, stepPts, digs, 0);
   }

   Print("QGP4 Grid abierto | Dir:",EnumToString(firstType)," Base:",priceBase,
         " Niveles:",MaxGridLevels," LoteBase:",lot0);
}

//+------------------------------------------------------------------+
void PlaceOrder(ENUM_ORDER_TYPE ot, double lots, double price,
                double atrV, double stepPts, int digs, int lvl)
{
   double sl=0.0, tp=0.0;
   // SL global en niveles de grid más allá del máximo
   double slBuffer = stepPts*(MaxGridLevels+1);
   if(ot==ORDER_TYPE_BUY)
   {
      sl = NormalizeDouble(price - slBuffer, digs);
      tp = 0.0; // Gestión por basket, no TP individual
   }
   else
   {
      sl = NormalizeDouble(price + slBuffer, digs);
      tp = 0.0;
   }

   double ask = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol,SYMBOL_BID);
   string cmt = TradeComment+"_L"+IntegerToString(lvl);

   // Si el precio de la orden está cerca del mercado → orden de mercado
   // Si está lejos → orden límite
   double dist = MathAbs(price - ((ot==ORDER_TYPE_BUY)?ask:bid));
   double minDist = SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*
                    SymbolInfoDouble(_Symbol,SYMBOL_POINT);

   if(dist <= minDist*2)
   {
      // Orden de mercado en precio actual
      bool ok = (ot==ORDER_TYPE_BUY)?
                Trade.Buy (lots,_Symbol,ask,sl,tp,cmt):
                Trade.Sell(lots,_Symbol,bid,sl,tp,cmt);
      if(!ok) Print("QGP4 Error orden mercado L",lvl,": ",Trade.ResultRetcodeDescription());
   }
   else
   {
      // Orden pendiente
      ENUM_ORDER_TYPE pendType;
      if(ot==ORDER_TYPE_BUY)
         pendType = (price<ask) ? ORDER_TYPE_BUY_LIMIT  : ORDER_TYPE_BUY_STOP;
      else
         pendType = (price>bid) ? ORDER_TYPE_SELL_LIMIT : ORDER_TYPE_SELL_STOP;

      bool ok = Trade.OrderOpen(_Symbol,pendType,lots,0.0,price,sl,tp,
                                ORDER_TIME_GTC,0,cmt);
      if(!ok) Print("QGP4 Error orden pend L",lvl,": ",Trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
// Basket Management: trailing y cierre por profit global
void ManageBasket()
{
   if(!g_gridActive && CountMyPositions()==0) return;

   double totalProfit  = GetTotalProfit();
   double balance      = AccountInfoDouble(ACCOUNT_BALANCE);

   // TP por basket en USD
   double tpUSD = BasketTP_USD;
   // TP por % del balance (si activo)
   if(BasketTP_Pct > 0.0)
      tpUSD = MathMin(tpUSD, balance * BasketTP_Pct / 100.0);

   // Basket trailing: guardar peak
   if(totalProfit > g_basketPeak) g_basketPeak = totalProfit;

   // Cierre parcial al 50% del TP
   if(UsePartialBasket && !g_partialDone && totalProfit >= tpUSD*0.5 && totalProfit > 0)
   {
      ClosePartialBasket(50.0);
      g_partialDone = true;
      Print("QGP4 Cierre parcial basket 50% | Profit=",totalProfit);
   }

   // Basket trailing stop: si el profit cae más del 30% desde el peak → cerrar
   if(UseBasketTrail && g_basketPeak > tpUSD*0.3)
   {
      double trailSL = g_basketPeak * 0.7;
      if(totalProfit < trailSL && totalProfit > 0)
      {
         CloseAllPositions("BasketTrail");
         return;
      }
   }

   // Cierre total al TP
   if(totalProfit >= tpUSD)
   {
      CloseAllPositions("BasketTP");
      return;
   }

   // Basket SL (stop loss global)
   if(BasketSL_USD > 0.0 && totalProfit <= -BasketSL_USD)
   {
      CloseAllPositions("BasketSL");
      CancelPendingOrders();
      return;
   }
}

//+------------------------------------------------------------------+
double GetTotalProfit()
{
   double total = 0.0;
   for(int i=0; i<PositionsTotal(); i++)
      if(PosInfo.SelectByIndex(i) &&
         PosInfo.Magic()==Magic &&
         PosInfo.Symbol()==_Symbol)
         total += PosInfo.Profit() + PosInfo.Swap() + PosInfo.Commission();
   return total;
}

//+------------------------------------------------------------------+
void CloseAllPositions(string reason)
{
   Print("QGP4 Cerrando todas las posiciones | Razón: ",reason,
         " | Profit: ",GetTotalProfit());
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      if(PosInfo.SelectByIndex(i) &&
         PosInfo.Magic()==Magic &&
         PosInfo.Symbol()==_Symbol)
      {
         if(!Trade.PositionClose(PosInfo.Ticket()))
            Print("QGP4 Error cerrando ticket ",PosInfo.Ticket(),
                  ": ",Trade.ResultRetcodeDescription());
      }
   }
   CancelPendingOrders();
   g_gridActive  = false;
   g_gridBase    = 0.0;
   g_partialDone = false;
   g_basketPeak  = -1e10;
}

//+------------------------------------------------------------------+
void ClosePartialBasket(double pct)
{
   double vstep = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      if(!PosInfo.SelectByIndex(i)) continue;
      if(PosInfo.Magic()!=Magic||PosInfo.Symbol()!=_Symbol) continue;
      double cv = MathFloor(PosInfo.Volume()*pct/100.0/vstep)*vstep;
      cv = MathMax(vstep, cv);
      if(cv < PosInfo.Volume())
         Trade.PositionClosePartial(PosInfo.Ticket(), cv);
   }
}

//+------------------------------------------------------------------+
void CancelPendingOrders()
{
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      if(OrdInfo.SelectByIndex(i) &&
         OrdInfo.Magic()==Magic &&
         OrdInfo.Symbol()==_Symbol)
         Trade.OrderDelete(OrdInfo.Ticket());
   }
}

//+------------------------------------------------------------------+
void UpdateAsianRange()
{
   MqlDateTime dt;
   datetime gmt = TimeGMT();
   TimeToStruct(gmt, dt);
   datetime today = (datetime)(gmt - (long)dt.hour*3600L -
                               (long)dt.min*60L - (long)dt.sec);
   if(today != g_aDate)
   {
      g_aHigh=0.0; g_aLow=1e10; g_aDate=today; g_aReady=false;
   }
   if(dt.hour>=Asian_Start && dt.hour<Asian_End)
   {
      double hi = iHigh(_Symbol,PERIOD_CURRENT,0);
      double lo = iLow (_Symbol,PERIOD_CURRENT,0);
      if(hi>g_aHigh) g_aHigh=hi;
      if(lo<g_aLow)  g_aLow=lo;
   }
   else if(dt.hour>=Asian_End && g_aHigh>0.0 && g_aLow<1e9)
      g_aReady=true;
}

//+------------------------------------------------------------------+
double GetRiskPct()
{
   if(ManualRiskPct>0.0) return ManualRiskPct;
   switch(RiskProfile)
   {
      case RISK_CONSERVATIVE: return 0.5;
      case RISK_BALANCED:     return 1.0;
      case RISK_AGGRESSIVE:   return 2.0;
      case RISK_EXTREME:      return 4.0;
   }
   return 1.0;
}

//+------------------------------------------------------------------+
int CountMyPositions()
{
   int n=0;
   for(int i=0;i<PositionsTotal();i++)
      if(PosInfo.SelectByIndex(i)&&PosInfo.Magic()==Magic&&PosInfo.Symbol()==_Symbol) n++;
   return n;
}

//+------------------------------------------------------------------+
int GetHourUTC()
{
   MqlDateTime dt;
   TimeToStruct(TimeGMT(),dt);
   return dt.hour;
}

//+------------------------------------------------------------------+
int London_StartHour() { return 8; }

//+------------------------------------------------------------------+
void DrawDashboard(int bSig, int sSig, double atrV, int htfBias)
{
   string bias = (htfBias>0)?"ALCISTA ▲":(htfBias<0)?"BAJISTA ▼":"NEUTRAL ―";
   string grd  = g_gridActive?"ACTIVO":"INACTIVO";
   double pnl  = GetTotalProfit();
   string pnlStr = DoubleToString(pnl,2);

   string dash = "\n";
   dash += "══════════════════════════\n";
   dash += "  QuantumGold Pro v4.0   \n";
   dash += "══════════════════════════\n";
   dash += " Bias HTF  : "+bias+"\n";
   dash += " Grid      : "+grd+"\n";
   dash += " Señales B : "+IntegerToString(bSig)+" | S: "+IntegerToString(sSig)+"\n";
   dash += " ATR       : "+DoubleToString(atrV,2)+"\n";
   dash += " Posiciones: "+IntegerToString(CountMyPositions())+"\n";
   dash += " Profit    : $"+pnlStr+"\n";
   dash += " Perfil    : "+EnumToString(RiskProfile)+"\n";
   dash += "══════════════════════════\n";

   Comment(dash);
}
//+------------------------------------------------------------------+
