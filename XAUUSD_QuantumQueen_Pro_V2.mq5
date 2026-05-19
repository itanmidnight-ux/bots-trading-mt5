//+------------------------------------------------------------------+
//| XAUUSD QuantumQueen Pro V2                                       |
//| Trend-Following Grid | MTF Structure | ATR Adaptive | Hybrid Exit |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>
CTrade trade;

//============================================================
// INPUTS
//============================================================
input group "=== CAPITAL ==="
input double BaseLot      = 0.01;
input int    MaxGridLayers= 5;
input double LotMultiplier= 1.0;   // multiplicador por capa (1.0 = flat)

input group "=== ENTRY STRUCTURE ==="
input int    FastEMA      = 9;
input int    SlowEMA      = 21;
input int    TrendEMA     = 50;
input int    RSI_Per      = 14;
input double RSI_OB       = 65.0;
input double RSI_OS       = 35.0;
input int    ATR_Per      = 14;

input group "=== MULTI-TIMEFRAME ==="
input ENUM_TIMEFRAMES TF_High  = PERIOD_H4;   // Marco de tendencia
input ENUM_TIMEFRAMES TF_Mid   = PERIOD_H1;   // Marco de estructura
input ENUM_TIMEFRAMES TF_Entry = PERIOD_M15;  // Marco de entrada

input group "=== GRID SPACING (ATR-based) ==="
input double GridATR_Factor  = 1.2;   // Espacio entre capas = ATR * factor
input double MaxDrawdownPct  = 3.0;   // % máx drawdown sobre balance

input group "=== TRAILING / EXIT ==="
input double TrailStartATR   = 1.5;   // Inicia trailing tras X*ATR de profit
input double TrailStepATR    = 0.5;   // Paso del trailing
input double HardSL_ATR      = 3.0;   // SL duro en ATR
input double TP_ATR          = 4.0;   // TP parcial en ATR (primera capa)

input group "=== FILTROS ==="
input double MaxSpread       = 60;
input int    Magic           = 888;
input bool   DebugLog        = false;

//============================================================
// GLOBALS
//============================================================
int    hFast_E, hSlow_E, hTrend_E, hRSI_E, hATR_E;   // Entry TF
int    hFast_M, hSlow_M, hTrend_M;                    // Mid TF
int    hTrend_H;                                       // High TF
datetime lastBarEntry = 0;
double   globalPeak   = 0;
bool     waitConfirm  = false;   // bandera espera estructural
int      pendingDir   = 0;       // 1=buy -1=sell
int      confirmCount = 0;       // velas de confirmación acumuladas
int      CONFIRMS_NEEDED = 2;    // velas consecutivas confirmando

//============================================================
int OnInit()
{
   // Entry TF handles
   hFast_E  = iMA(_Symbol, TF_Entry, FastEMA,  0, MODE_EMA, PRICE_CLOSE);
   hSlow_E  = iMA(_Symbol, TF_Entry, SlowEMA,  0, MODE_EMA, PRICE_CLOSE);
   hTrend_E = iMA(_Symbol, TF_Entry, TrendEMA, 0, MODE_EMA, PRICE_CLOSE);
   hRSI_E   = iRSI(_Symbol, TF_Entry, RSI_Per, PRICE_CLOSE);
   hATR_E   = iATR(_Symbol, TF_Entry, ATR_Per);
   // Mid TF handles
   hFast_M  = iMA(_Symbol, TF_Mid, FastEMA,  0, MODE_EMA, PRICE_CLOSE);
   hSlow_M  = iMA(_Symbol, TF_Mid, SlowEMA,  0, MODE_EMA, PRICE_CLOSE);
   hTrend_M = iMA(_Symbol, TF_Mid, TrendEMA, 0, MODE_EMA, PRICE_CLOSE);
   // High TF handle
   hTrend_H = iMA(_Symbol, TF_High, TrendEMA, 0, MODE_EMA, PRICE_CLOSE);

   if(hFast_E==INVALID_HANDLE||hSlow_E==INVALID_HANDLE||hTrend_E==INVALID_HANDLE||
      hRSI_E==INVALID_HANDLE||hATR_E==INVALID_HANDLE||
      hFast_M==INVALID_HANDLE||hSlow_M==INVALID_HANDLE||hTrend_M==INVALID_HANDLE||
      hTrend_H==INVALID_HANDLE) { Print("Handle error"); return INIT_FAILED; }

   trade.SetExpertMagicNumber(Magic);
   Print("QuantumQueen Pro V2 initialized.");
   return INIT_SUCCEEDED;
}

//============================================================
// HELPERS: leer buffer seguro
//============================================================
double Buf(int handle, int shift=0)
{
   double arr[];
   ArraySetAsSeries(arr, true);
   if(CopyBuffer(handle, 0, shift, 1, arr) <= 0) return 0;
   return arr[0];
}

double GetATR() { return Buf(hATR_E, 1); }

//============================================================
// SPREAD CHECK
//============================================================
bool SpreadOK()
{
   return ((SymbolInfoDouble(_Symbol,SYMBOL_ASK)-SymbolInfoDouble(_Symbol,SYMBOL_BID))/_Point <= MaxSpread);
}

//============================================================
// DRAWDOWN CHECK
//============================================================
bool DrawdownOK()
{
   double bal  = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq   = AccountInfoDouble(ACCOUNT_EQUITY);
   if(bal <= 0) return false;
   return (((bal - eq) / bal) * 100.0 < MaxDrawdownPct);
}

//============================================================
// MTF TREND DIRECTION
// Returns  1 = bullish alignment
//         -1 = bearish alignment
//          0 = mixed / no trade
//============================================================
int MTF_Direction()
{
   double price  = iClose(_Symbol, TF_Entry, 1);
   double tH     = Buf(hTrend_H, 1);
   double fM     = Buf(hFast_M,  1);
   double sM     = Buf(hSlow_M,  1);
   double tM     = Buf(hTrend_M, 1);
   double fE     = Buf(hFast_E,  1);
   double sE     = Buf(hSlow_E,  1);
   double tE     = Buf(hTrend_E, 1);
   if(tH==0||tM==0||tE==0) return 0;

   bool bullH = price > tH;
   bool bullM = fM > sM && price > tM;
   bool bullE = fE > sE && price > tE;
   bool bearH = price < tH;
   bool bearM = fM < sM && price < tM;
   bool bearE = fE < sE && price < tE;

   if(bullH && bullM && bullE) return  1;
   if(bearH && bearM && bearE) return -1;
   return 0;
}

//============================================================
// STRUCTURE CONFIRMATION (candle logic)
// Returns true when candle confirms direction
//============================================================
bool CandleConfirms(int dir)
{
   double o = iOpen (_Symbol, TF_Entry, 1);
   double c = iClose(_Symbol, TF_Entry, 1);
   double atr = GetATR();
   if(atr <= 0) return false;
   double body = MathAbs(c - o);
   // Cuerpo mínimo 30% del ATR para confirmar impulso
   if(body < atr * 0.3) return false;
   if(dir ==  1) return c > o;   // vela alcista
   if(dir == -1) return c < o;   // vela bajista
   return false;
}

//============================================================
// RSI FILTER
//============================================================
bool RSI_OK(int dir)
{
   double rsi = Buf(hRSI_E, 1);
   if(rsi <= 0) return false;
   if(dir ==  1) return rsi < RSI_OB;   // no sobrecomprado
   if(dir == -1) return rsi > RSI_OS;   // no sobrevendido
   return false;
}

//============================================================
// COUNT ACTIVE POSITIONS BY DIRECTION
//============================================================
int CountPositions(int dir=-99)   // -99 = todos
{
   int cnt = 0;
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(!PositionSelectByTicket(tk)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != Magic) continue;
      if(dir == -99) { cnt++; continue; }
      int pt = (int)PositionGetInteger(POSITION_TYPE);
      if(dir == 1 && pt == POSITION_TYPE_BUY)  cnt++;
      if(dir ==-1 && pt == POSITION_TYPE_SELL) cnt++;
   }
   return cnt;
}

//============================================================
// GRID: ¿Necesita nueva capa?
// Verifica si el precio se alejó lo suficiente (ATR-based)
//============================================================
bool NeedsGridLayer(int dir)
{
   if(CountPositions(dir) >= MaxGridLayers) return false;
   double atr    = GetATR();
   double spacing= atr * GridATR_Factor;
   double price  = (dir==1) ? SymbolInfoDouble(_Symbol,SYMBOL_ASK)
                             : SymbolInfoDouble(_Symbol,SYMBOL_BID);
   // Buscar el precio de apertura más reciente en esa dirección
   double lastOpen = 0;
   datetime lastTime = 0;
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(!PositionSelectByTicket(tk)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != Magic) continue;
      int pt = (int)PositionGetInteger(POSITION_TYPE);
      if(dir==1 && pt!=POSITION_TYPE_BUY)  continue;
      if(dir==-1&& pt!=POSITION_TYPE_SELL) continue;
      datetime ot = (datetime)PositionGetInteger(POSITION_TIME);
      if(ot > lastTime) { lastTime=ot; lastOpen=PositionGetDouble(POSITION_PRICE_OPEN); }
   }
   if(lastOpen <= 0) return false;
   // BUY grid: precio bajó lo suficiente (pullback en tendencia alcista)
   if(dir ==  1) return (lastOpen - price) >= spacing;
   // SELL grid: precio subió lo suficiente
   if(dir == -1) return (price - lastOpen) >= spacing;
   return false;
}

//============================================================
// ABRIR POSICIÓN (inicial o capa grid)
//============================================================
void OpenPosition(int dir, bool isGrid=false)
{
   if(!SpreadOK() || !DrawdownOK()) return;
   int layer    = CountPositions(dir);
   double lot   = NormalizeDouble(BaseLot * MathPow(LotMultiplier, layer), 2);
   double atr   = GetATR();
   if(lot < SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN))
      lot = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);

   double sl_pts = atr * HardSL_ATR;
   double tp_pts = atr * TP_ATR;

   if(dir == 1)
   {
      double ask = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      double sl  = ask - sl_pts;
      double tp  = isGrid ? 0 : ask + tp_pts;   // grid layers sin TP fijo
      trade.Buy(lot, _Symbol, ask, sl, tp);
   }
   else
   {
      double bid = SymbolInfoDouble(_Symbol,SYMBOL_BID);
      double sl  = bid + sl_pts;
      double tp  = isGrid ? 0 : bid - tp_pts;
      trade.Sell(lot, _Symbol, bid, sl, tp);
   }
   if(DebugLog)
      PrintFormat("[%s] Layer %d | dir=%d | lot=%.2f | ATR=%.2f", isGrid?"GRID":"ENTRY", layer+1, dir, lot, atr);
}

//============================================================
// TRAILING STOP HÍBRIDO
// Mueve SL a favor cuando profit supera TrailStartATR
//============================================================
void ManageTrailing()
{
   double atr = GetATR();
   if(atr <= 0) return;
   double trailStart = atr * TrailStartATR;
   double trailStep  = atr * TrailStepATR;

   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(!PositionSelectByTicket(tk)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != Magic) continue;

      int    pt      = (int)PositionGetInteger(POSITION_TYPE);
      double open    = PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL   = PositionGetDouble(POSITION_SL);
      double bid     = SymbolInfoDouble(_Symbol,SYMBOL_BID);
      double ask     = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      double newSL   = 0;

      if(pt == POSITION_TYPE_BUY)
      {
         double profit_pts = bid - open;
         if(profit_pts < trailStart) continue;
         newSL = bid - trailStep;
         if(newSL > curSL + _Point) trade.PositionModify(tk, newSL, PositionGetDouble(POSITION_TP));
      }
      else
      {
         double profit_pts = open - ask;
         if(profit_pts < trailStart) continue;
         newSL = ask + trailStep;
         if(curSL == 0 || newSL < curSL - _Point) trade.PositionModify(tk, newSL, PositionGetDouble(POSITION_TP));
      }
   }
}

//============================================================
// GESTIÓN GLOBAL DE PROFIT (peak / retrace)
//============================================================
void ManagePeak()
{
   double totalPnL = 0;
   int cnt = 0;
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(!PositionSelectByTicket(tk)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != Magic) continue;
      totalPnL += PositionGetDouble(POSITION_PROFIT);
      cnt++;
   }
   if(cnt == 0) { globalPeak = 0; return; }
   if(totalPnL > globalPeak) globalPeak = totalPnL;

   // Retrace del 30% sobre el pico acumulado (mínimo $0.30)
   double retraceThr = MathMax(globalPeak * 0.30, 0.30);
   if(globalPeak > 0.50 && (globalPeak - totalPnL) >= retraceThr)
   {
      if(DebugLog) PrintFormat("Peak %.2f | PnL %.2f | Closing all", globalPeak, totalPnL);
      CloseAll();
      globalPeak = 0;
   }
}

//============================================================
void CloseAll()
{
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(PositionSelectByTicket(tk) && PositionGetInteger(POSITION_MAGIC)==Magic)
         trade.PositionClose(tk);
   }
}

//============================================================
// MAIN TICK
//============================================================
void OnTick()
{
   if(!SpreadOK()) return;

   // --- Gestión continua (trailing + peak) en cada tick ---
   ManageTrailing();
   ManagePeak();

   // --- Lógica de nueva barra (entry TF) ---
   datetime barTime = iTime(_Symbol, TF_Entry, 0);
   if(barTime == lastBarEntry) return;
   lastBarEntry = barTime;

   // --- Análisis MTF ---
   int dir = MTF_Direction();

   // --- MÁQUINA DE ESPERA ESTRUCTURAL ---
   // Si no hay señal alineada, resetear espera
   if(dir == 0 || (waitConfirm && dir != pendingDir))
   {
      waitConfirm  = false;
      pendingDir   = 0;
      confirmCount = 0;
      // Intentar añadir capa grid si hay posición abierta
      if(CountPositions() > 0)
      {
         int activeDir = 0;
         for(int i=PositionsTotal()-1; i>=0; i--)
         {
            ulong tk = PositionGetTicket(i);
            if(!PositionSelectByTicket(tk)) continue;
            if(PositionGetInteger(POSITION_MAGIC)!=Magic) continue;
            activeDir = (PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY) ? 1 : -1;
            break;
         }
         if(activeDir != 0 && NeedsGridLayer(activeDir)) OpenPosition(activeDir, true);
      }
      return;
   }

   // --- Si dirección válida, acumular confirmaciones ---
   if(!waitConfirm)
   {
      waitConfirm  = true;
      pendingDir   = dir;
      confirmCount = 0;
   }

   // Confirmar vela en dirección
   if(CandleConfirms(dir) && RSI_OK(dir))
      confirmCount++;
   else
      confirmCount = MathMax(0, confirmCount - 1);   // paciencia: no romper todo si falla 1 vela

   // --- ENTRADA: solo cuando hay confirmación suficiente y no hay posición en misma dirección ---
   if(confirmCount >= CONFIRMS_NEEDED)
   {
      if(CountPositions(dir) == 0 && DrawdownOK())
      {
         OpenPosition(dir, false);
         confirmCount = 0;   // resetear para siguiente entrada grid
      }
      else if(CountPositions(dir) > 0 && NeedsGridLayer(dir) && DrawdownOK())
      {
         OpenPosition(dir, true);
         confirmCount = 0;
      }
   }

   // --- Si hay posición activa en distinta dirección, revisar grid ---
   if(CountPositions() > 0)
   {
      int activeDir = 0;
      for(int i=PositionsTotal()-1; i>=0; i--)
      {
         ulong tk = PositionGetTicket(i);
         if(!PositionSelectByTicket(tk)) continue;
         if(PositionGetInteger(POSITION_MAGIC)!=Magic) continue;
         activeDir = (PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY) ? 1 : -1;
         break;
      }
      if(activeDir != 0 && NeedsGridLayer(activeDir) && DrawdownOK())
         OpenPosition(activeDir, true);
   }
}
//+------------------------------------------------------------------+
