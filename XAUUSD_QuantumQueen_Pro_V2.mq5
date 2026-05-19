//+------------------------------------------------------------------+
//| XAUUSD QuantumQueen Pro V4                                       |
//| APEX Engine: Adaptive Profit Amplification & Extraction          |
//| Regime-Aware | Equity-Scaled | Structured Recovery-to-Profit     |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>
CTrade trade;

//============================================================
// INPUTS
//============================================================
input group "=== CAPITAL BASE ==="
input double BaseLot          = 0.01;
input int    MaxGridLayers    = 5;
input double MaxLotAbsolute   = 1.00;   // Techo duro absoluto de lote

input group "=== APEX: ADAPTIVE EXPOSURE ==="
input bool   UseAPEX          = true;   // Activar motor APEX (activo >= $100)
input double APEX_BalanceMin  = 100.0;  // Balance mínimo de activación
input double APEX_BaseRiskPct = 1.0;    // % base de riesgo por operación
input double APEX_MaxRiskPct  = 2.5;    // % máximo de riesgo (techo de confianza)
input double APEX_LayerDecay  = 0.85;   // Factor de reducción de lote por capa (< 1 = conservador)

input group "=== APEX: REGIME THRESHOLDS ==="
input double ATR_HighVolMul   = 2.0;    // ATR actual > media * este factor → HIGH_VOL
input double ATR_LowVolMul    = 0.6;    // ATR actual < media * este factor → LOW_VOL
input int    ATR_RegimePeriod = 50;     // Período de ATR medio para régimen

input group "=== APEX: BASKET PROFIT ENGINE ==="
input double BasketTP_Trend   = 3.5;    // Múltiplo ATR para TP en TREND
input double BasketTP_Range   = 1.8;    // Múltiplo ATR para TP en RANGE
input double BasketTP_HighVol = 2.5;    // Múltiplo ATR para TP en HIGH_VOL
input double BasketTP_LowVol  = 1.2;    // Múltiplo ATR para TP en LOW_VOL
input double BasketTrailMul   = 0.6;    // Trailing step = ATR * este factor
input double BasketTrailStart = 0.8;    // Trailing inicia cuando profit > ATR * este factor

input group "=== RECOVERY-TO-PROFIT ENGINE ==="
input bool   UseRecovery        = true;
input double RecoveryTriggerPct = 2.0;    // DD% que activa recovery
input double RecoverySpacingMul = 0.65;   // Espaciado recovery = ATR * GridFactor * mul
input int    MaxRecoveryLayers  = 3;
input double RecoveryProfitMul  = 1.2;    // Target de recovery = avg_price + ATR * mul (sobre BE)

input group "=== ENTRY STRUCTURE ==="
input int    FastEMA       = 9;
input int    SlowEMA       = 21;
input int    TrendEMA      = 50;
input int    RSI_Per       = 14;
input double RSI_OB        = 65.0;
input double RSI_OS        = 35.0;
input int    ATR_Per       = 14;

input group "=== MULTI-TIMEFRAME ==="
input ENUM_TIMEFRAMES TF_High  = PERIOD_H4;
input ENUM_TIMEFRAMES TF_Mid   = PERIOD_H1;
input ENUM_TIMEFRAMES TF_Entry = PERIOD_M15;

input group "=== GRID SPACING ==="
input double GridATR_Factor = 1.2;
input double MaxDrawdownPct = 5.0;

input group "=== HARD STOP / FILTROS ==="
input double HardSL_ATR  = 3.0;
input double MaxSpread    = 60;
input double MaxATR_Entry = 5.0;   // No entrar si ATR > media * este factor (spike filter)
input int    Magic        = 888;
input bool   DebugLog     = false;

//============================================================
// REGIME ENUM
//============================================================
enum ENUM_REGIME { REGIME_TREND=0, REGIME_RANGE=1, REGIME_HIGHVOL=2, REGIME_LOWVOL=3 };

//============================================================
// GLOBALS
//============================================================
int hFast_E, hSlow_E, hTrend_E, hRSI_E, hATR_E, hATR_Slow;
int hFast_M, hSlow_M, hTrend_M;
int hTrend_H;

datetime      lastBarEntry  = 0;
double        globalPeak    = 0;
bool          waitConfirm   = false;
int           pendingDir    = 0;
int           confirmCount  = 0;
int           recoveryCount = 0;
ENUM_REGIME   currentRegime = REGIME_TREND;
double        lastConfScore = 0.5;
const int     CONFIRMS_NEEDED = 2;

//============================================================
// OnInit
//============================================================
int OnInit()
{
   hFast_E  = iMA(_Symbol, TF_Entry, FastEMA,  0, MODE_EMA, PRICE_CLOSE);
   hSlow_E  = iMA(_Symbol, TF_Entry, SlowEMA,  0, MODE_EMA, PRICE_CLOSE);
   hTrend_E = iMA(_Symbol, TF_Entry, TrendEMA, 0, MODE_EMA, PRICE_CLOSE);
   hRSI_E   = iRSI(_Symbol, TF_Entry, RSI_Per, PRICE_CLOSE);
   hATR_E   = iATR(_Symbol, TF_Entry, ATR_Per);
   hATR_Slow= iATR(_Symbol, TF_Entry, ATR_RegimePeriod);  // ATR medio para régimen
   hFast_M  = iMA(_Symbol, TF_Mid, FastEMA,  0, MODE_EMA, PRICE_CLOSE);
   hSlow_M  = iMA(_Symbol, TF_Mid, SlowEMA,  0, MODE_EMA, PRICE_CLOSE);
   hTrend_M = iMA(_Symbol, TF_Mid, TrendEMA, 0, MODE_EMA, PRICE_CLOSE);
   hTrend_H = iMA(_Symbol, TF_High, TrendEMA, 0, MODE_EMA, PRICE_CLOSE);

   if(hFast_E==INVALID_HANDLE||hSlow_E==INVALID_HANDLE||hTrend_E==INVALID_HANDLE||
      hRSI_E==INVALID_HANDLE||hATR_E==INVALID_HANDLE||hATR_Slow==INVALID_HANDLE||
      hFast_M==INVALID_HANDLE||hSlow_M==INVALID_HANDLE||hTrend_M==INVALID_HANDLE||
      hTrend_H==INVALID_HANDLE)
   { Print("APEX: Handle error on init"); return INIT_FAILED; }

   trade.SetExpertMagicNumber(Magic);
   Print("QuantumQueen Pro V4 [APEX Engine] initialized. Bal=$",
         AccountInfoDouble(ACCOUNT_BALANCE));
   return INIT_SUCCEEDED;
}

//============================================================
// HELPERS BÁSICOS
//============================================================
double Buf(int handle, int shift=0)
{
   double arr[];
   ArraySetAsSeries(arr, true);
   if(CopyBuffer(handle, 0, shift, 1, arr) <= 0) return 0.0;
   return arr[0];
}

double GetATR()     { return Buf(hATR_E, 1); }
double GetATRSlow() { return Buf(hATR_Slow, 1); }
double GetBal()     { return AccountInfoDouble(ACCOUNT_BALANCE); }
double GetEq()      { return AccountInfoDouble(ACCOUNT_EQUITY); }
double GetDDPct()
{
   double b = GetBal();
   if(b <= 0) return 0.0;
   return ((b - GetEq()) / b) * 100.0;
}

double NormLot(double lot)
{
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0) step = 0.01;
   lot = MathFloor(lot / step) * step;
   lot = MathMax(lot, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN));
   lot = MathMin(lot, MathMin(MaxLotAbsolute, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX)));
   return NormalizeDouble(lot, 2);
}

bool SpreadOK()
{
   return ((SymbolInfoDouble(_Symbol,SYMBOL_ASK) -
            SymbolInfoDouble(_Symbol,SYMBOL_BID)) / _Point <= MaxSpread);
}

bool DrawdownOK()
{
   return GetDDPct() < MaxDrawdownPct;
}

//============================================================
// ── APEX BLOQUE 1: REGIME DETECTOR ──────────────────────────
// Detecta el régimen de mercado usando ATR relativo + EMA slope
// Regímenes: TREND / RANGE / HIGH_VOL / LOW_VOL
//============================================================
ENUM_REGIME DetectRegime()
{
   double atr  = GetATR();
   double atrS = GetATRSlow();
   if(atr <= 0 || atrS <= 0) return REGIME_TREND;

   double ratio = atr / atrS;

   // Volatilidad extrema → prioridad máxima
   if(ratio >= ATR_HighVolMul)  return REGIME_HIGHVOL;
   if(ratio <= ATR_LowVolMul)   return REGIME_LOWVOL;

   // Distinguir TREND vs RANGE usando slope del TrendEMA en TF_Entry
   double tE0 = Buf(hTrend_E, 1);
   double tE3 = Buf(hTrend_E, 4);   // 3 velas atrás
   if(tE0 <= 0 || tE3 <= 0) return REGIME_TREND;

   double slope = MathAbs(tE0 - tE3) / atr;   // slope normalizado por ATR
   return (slope >= 0.5) ? REGIME_TREND : REGIME_RANGE;
}

//============================================================
// ── APEX BLOQUE 2: CONFIDENCE SCORE ─────────────────────────
// Score 0.0–1.0 basado en: MTF alignment, RSI position,
// candle quality, EMA spread, volatility normality
//============================================================
double CalcConfidenceScore(int dir)
{
   double score = 0.0;

   // 1. MTF alignment (máx 0.40)
   double price = iClose(_Symbol, TF_Entry, 1);
   double tH    = Buf(hTrend_H, 1);
   double fM    = Buf(hFast_M,  1);
   double sM    = Buf(hSlow_M,  1);
   double tM    = Buf(hTrend_M, 1);
   double fE    = Buf(hFast_E,  1);
   double sE    = Buf(hSlow_E,  1);

   if(dir ==  1) {
      if(price > tH) score += 0.15;
      if(fM > sM && price > tM) score += 0.15;
      if(fE > sE) score += 0.10;
   } else {
      if(price < tH) score += 0.15;
      if(fM < sM && price < tM) score += 0.15;
      if(fE < sE) score += 0.10;
   }

   // 2. RSI position (máx 0.20)
   double rsi = Buf(hRSI_E, 1);
   if(dir ==  1 && rsi >= 40 && rsi <= 62) score += 0.20;
   if(dir == -1 && rsi >= 38 && rsi <= 60) score += 0.20;

   // 3. Candle quality (máx 0.25)
   double o   = iOpen(_Symbol, TF_Entry, 1);
   double c   = iClose(_Symbol, TF_Entry, 1);
   double h   = iHigh(_Symbol, TF_Entry, 1);
   double l   = iLow(_Symbol, TF_Entry, 1);
   double atr = GetATR();
   if(atr > 0) {
      double body  = MathAbs(c - o);
      double range = h - l;
      double bodyRatio = (range > 0) ? body / range : 0;
      double impulse   = body / atr;
      // Cuerpo sólido con buen impulso
      if(bodyRatio >= 0.5 && impulse >= 0.4) score += 0.15;
      if(impulse >= 0.7)                     score += 0.10;
      if(dir == 1  && c > o)                score += 0.00;  // bonus ya incluido en body
      if(dir == -1 && c < o)                score += 0.00;
   }

   // 4. ATR normalidad (máx 0.15) — penalizar volatilidad extrema
   double atrS = GetATRSlow();
   if(atr > 0 && atrS > 0) {
      double ratio = atr / atrS;
      if(ratio >= 0.5 && ratio <= 1.8) score += 0.15;   // volatilidad normal
      else if(ratio < ATR_HighVolMul)  score += 0.07;   // algo elevada
   }

   return MathMax(0.0, MathMin(1.0, score));
}

//============================================================
// ── APEX BLOQUE 3: ADAPTIVE EXPOSURE SCALING ─────────────────
// LotSize = BaseRisk × EquityFactor × ConfidenceFactor
//         × RegimeFactor × VolatilityAdj × SafetyCoeff
// Activo solo si Balance >= APEX_BalanceMin
//============================================================
double APEX_CalcLot(int layer, bool isRecovery, double confScore, ENUM_REGIME regime)
{
   double bal = GetBal();

   // Bajo el umbral → lote fijo conservador
   if(!UseAPEX || bal < APEX_BalanceMin)
      return NormLot(BaseLot);

   // --- Factor base: riesgo monetario / riesgo por lote del SL ---
   double atr      = GetATR();
   double tickVal  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double slPts    = atr * HardSL_ATR;

   if(atr <= 0 || tickVal <= 0 || tickSize <= 0 || slPts <= 0)
      return NormLot(BaseLot);

   double slMoneyPerLot = (slPts / tickSize) * tickVal;
   if(slMoneyPerLot <= 0) return NormLot(BaseLot);

   // 1. EQUITY FACTOR: crece con el equity (compounding controlado)
   double eq          = GetEq();
   double equityFactor= eq / bal;   // >1 si en profit flotante, <1 si en DD
   equityFactor       = MathMax(0.5, MathMin(1.3, equityFactor));

   // 2. CONFIDENCE FACTOR: escala el riesgo según calidad del setup
   // confScore 0→1 mapea a riskPct base→max
   double riskPct      = APEX_BaseRiskPct + (APEX_MaxRiskPct - APEX_BaseRiskPct) * confScore;
   double riskAmt      = bal * (riskPct / 100.0);
   double baseLot      = riskAmt / slMoneyPerLot;

   // 3. REGIME FACTOR: comportamiento según régimen de mercado
   double regimeFactor = 1.0;
   if(regime == REGIME_TREND)   regimeFactor = 1.0;    // participación completa
   if(regime == REGIME_RANGE)   regimeFactor = 0.7;    // reducida — más ruido
   if(regime == REGIME_HIGHVOL) regimeFactor = 0.5;    // extracción controlada
   if(regime == REGIME_LOWVOL)  regimeFactor = 0.6;    // selectivo

   // 4. VOLATILITY ADJUSTMENT: normalizar por ATR relativo
   double atrSlow     = GetATRSlow();
   double volRatio    = (atrSlow > 0) ? atr / atrSlow : 1.0;
   double volAdj      = 1.0 / MathMax(0.5, MathMin(2.0, volRatio));   // inverso: más ATR → menos lote

   // 5. SAFETY COEFFICIENT: penaliza si el DD ya está elevado
   double ddPct       = GetDDPct();
   double safetyCo    = 1.0;
   if(ddPct > 1.0) safetyCo = 1.0 - ((ddPct - 1.0) / (MaxDrawdownPct - 1.0)) * 0.5;
   safetyCo           = MathMax(0.3, safetyCo);

   // 6. LAYER DECAY: cada capa subsiguiente reduce el lote (conservador por diseño)
   double layerFactor = MathPow(APEX_LayerDecay, layer);

   // 7. RECOVERY ADJUSTMENT: si es recovery, lote un poco mayor para mejorar avg rápido
   double recFactor   = isRecovery ? 1.25 : 1.0;

   // Fórmula final
   double finalLot = baseLot * equityFactor * regimeFactor * volAdj * safetyCo * layerFactor * recFactor;

   if(DebugLog)
      PrintFormat("[APEX Lot] conf=%.2f reg=%d eq=%.2f vol=%.2f safe=%.2f layer=%.2f → lot=%.3f",
         confScore, (int)regime, equityFactor, volAdj, safetyCo, layerFactor, finalLot);

   return NormLot(finalLot);
}

//============================================================
// ── APEX BLOQUE 4: DYNAMIC BASKET PROFIT TARGET ──────────────
// TP del basket se adapta a régimen + ATR + trend strength
//============================================================
double APEX_BasketTarget(int dir, ENUM_REGIME regime)
{
   double atr = GetATR();
   if(atr <= 0) return 0.0;

   double tpMul = BasketTP_Trend;   // default
   if(regime == REGIME_RANGE)   tpMul = BasketTP_Range;
   if(regime == REGIME_HIGHVOL) tpMul = BasketTP_HighVol;
   if(regime == REGIME_LOWVOL)  tpMul = BasketTP_LowVol;

   // Ajuste por trend strength: slope normalizado del TrendEMA
   double tE0    = Buf(hTrend_E, 1);
   double tE5    = Buf(hTrend_E, 6);
   double slope  = (tE0 > 0 && tE5 > 0 && atr > 0) ? MathAbs(tE0-tE5)/atr : 1.0;
   double tsMul  = MathMax(0.8, MathMin(1.4, 0.8 + slope * 0.3));   // 0.8 – 1.4

   double avgP   = BasketAvgPrice(dir);
   double target = avgP;

   if(dir ==  1) target = avgP + atr * tpMul * tsMul;
   if(dir == -1) target = avgP - atr * tpMul * tsMul;

   return target;
}

//============================================================
// MTF DIRECTION
//============================================================
int MTF_Direction()
{
   double price = iClose(_Symbol, TF_Entry, 1);
   double tH    = Buf(hTrend_H, 1);
   double fM    = Buf(hFast_M,  1);
   double sM    = Buf(hSlow_M,  1);
   double tM    = Buf(hTrend_M, 1);
   double fE    = Buf(hFast_E,  1);
   double sE    = Buf(hSlow_E,  1);
   double tE    = Buf(hTrend_E, 1);
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
// CANDLE CONFIRM
//============================================================
bool CandleConfirms(int dir)
{
   double o   = iOpen(_Symbol, TF_Entry, 1);
   double c   = iClose(_Symbol, TF_Entry, 1);
   double atr = GetATR();
   if(atr <= 0) return false;
   if(MathAbs(c-o) < atr * 0.3) return false;
   if(dir ==  1) return c > o;
   if(dir == -1) return c < o;
   return false;
}

//============================================================
// RSI FILTER
//============================================================
bool RSI_OK(int dir)
{
   double rsi = Buf(hRSI_E, 1);
   if(rsi <= 0) return false;
   if(dir ==  1) return rsi < RSI_OB;
   if(dir == -1) return rsi > RSI_OS;
   return false;
}

//============================================================
// ── APEX BLOQUE 7: CAPITAL PRESERVATION FILTERS ──────────────
// Todos los filtros de entrada consolidados en una función
//============================================================
bool EntryFiltersOK(int dir)
{
   // 1. Spread
   if(!SpreadOK()) return false;

   // 2. Drawdown global
   if(!DrawdownOK()) return false;

   // 3. ATR spike filter — no entrar en expansiones extremas
   double atr  = GetATR();
   double atrS = GetATRSlow();
   if(atr > 0 && atrS > 0 && (atr / atrS) >= MaxATR_Entry) return false;

   // 4. ATR mínimo — no operar en mercado muerto
   if(atr <= 0) return false;

   // 5. Liquidez mínima: no operar en primeras/últimas velas de sesión
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(dt.hour < 1 || dt.hour >= 22) return false;   // Fuera de sesión útil

   // 6. No operar si confidence score muy baja (setup de mala calidad)
   if(lastConfScore < 0.30) return false;

   // 7. Regime avoidance: HIGH_VOL muy extremo → no nuevas entradas iniciales
   if(currentRegime == REGIME_HIGHVOL && CountPositions() == 0)
   {
      double ratio = (atrS > 0) ? atr / atrS : 1.0;
      if(ratio >= ATR_HighVolMul * 1.3) return false;   // solo bloquea spikes extremos
   }

   return true;
}

//============================================================
// COUNT POSITIONS
//============================================================
int CountPositions(int dir=-99)
{
   int cnt = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(!PositionSelectByTicket(tk)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != Magic) continue;
      if(dir == -99) { cnt++; continue; }
      int pt = (int)PositionGetInteger(POSITION_TYPE);
      if(dir ==  1 && pt == POSITION_TYPE_BUY)  cnt++;
      if(dir == -1 && pt == POSITION_TYPE_SELL) cnt++;
   }
   return cnt;
}

//============================================================
// BASKET AVERAGE PRICE
//============================================================
double BasketAvgPrice(int dir)
{
   double totLot = 0.0, totW = 0.0;
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(!PositionSelectByTicket(tk)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != Magic) continue;
      int pt = (int)PositionGetInteger(POSITION_TYPE);
      if(dir ==  1 && pt != POSITION_TYPE_BUY)  continue;
      if(dir == -1 && pt != POSITION_TYPE_SELL) continue;
      double lot  = PositionGetDouble(POSITION_VOLUME);
      totW  += lot * PositionGetDouble(POSITION_PRICE_OPEN);
      totLot += lot;
   }
   return (totLot > 0) ? totW / totLot : 0.0;
}

//============================================================
// LAST OPEN PRICE
//============================================================
double LastOpenPrice(int dir)
{
   double   lastP = 0.0;
   datetime lastT = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(!PositionSelectByTicket(tk)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != Magic) continue;
      int pt = (int)PositionGetInteger(POSITION_TYPE);
      if(dir ==  1 && pt != POSITION_TYPE_BUY)  continue;
      if(dir == -1 && pt != POSITION_TYPE_SELL) continue;
      datetime ot = (datetime)PositionGetInteger(POSITION_TIME);
      if(ot > lastT) { lastT = ot; lastP = PositionGetDouble(POSITION_PRICE_OPEN); }
   }
   return lastP;
}

//============================================================
// GRID LAYER CHECK
//============================================================
bool NeedsGridLayer(int dir)
{
   if(CountPositions(dir) >= MaxGridLayers) return false;
   double spacing = GetATR() * GridATR_Factor;
   double price   = (dir==1) ? SymbolInfoDouble(_Symbol,SYMBOL_ASK)
                              : SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double lop = LastOpenPrice(dir);
   if(lop <= 0) return false;
   if(dir ==  1) return (lop - price) >= spacing;
   if(dir == -1) return (price - lop) >= spacing;
   return false;
}

//============================================================
// RECOVERY LAYER CHECK
//============================================================
bool NeedsRecoveryLayer(int dir)
{
   if(!UseRecovery) return false;
   if(recoveryCount >= MaxRecoveryLayers) return false;
   if(CountPositions(dir) == 0) return false;
   if(GetDDPct() < RecoveryTriggerPct) return false;

   double spacing = GetATR() * GridATR_Factor * RecoverySpacingMul;
   double price   = (dir==1) ? SymbolInfoDouble(_Symbol,SYMBOL_ASK)
                              : SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double lop = LastOpenPrice(dir);
   if(lop <= 0) return false;
   if(dir ==  1) return (lop - price) >= spacing;
   if(dir == -1) return (price - lop) >= spacing;
   return false;
}

//============================================================
// OPEN POSITION
//============================================================
void OpenPosition(int dir, bool isGrid, bool isRecovery)
{
   if(!DrawdownOK()) return;
   if(!SpreadOK())   return;

   int    layer = CountPositions(dir);
   double lot   = APEX_CalcLot(layer, isRecovery, lastConfScore, currentRegime);
   double atr   = GetATR();
   if(atr <= 0) return;

   double slPts = atr * HardSL_ATR;
   // TP individual: solo para capa inicial en régimen TREND (resto usa basket management)
   double tpPts = ((!isGrid && !isRecovery) && currentRegime == REGIME_TREND)
                  ? atr * BasketTP_Trend : 0.0;

   if(dir == 1)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if(trade.Buy(lot, _Symbol, ask, ask - slPts, (tpPts > 0) ? ask + tpPts : 0.0))
      {
         if(isRecovery) recoveryCount++;
         if(DebugLog)
            PrintFormat("[%s] BUY L%d lot=%.3f sl=%.2f conf=%.2f reg=%d",
               isRecovery?"REC":isGrid?"GRID":"ENTRY",
               layer+1, lot, ask-slPts, lastConfScore, (int)currentRegime);
      }
   }
   else
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(trade.Sell(lot, _Symbol, bid, bid + slPts, (tpPts > 0) ? bid - tpPts : 0.0))
      {
         if(isRecovery) recoveryCount++;
         if(DebugLog)
            PrintFormat("[%s] SELL L%d lot=%.3f sl=%.2f conf=%.2f reg=%d",
               isRecovery?"REC":isGrid?"GRID":"ENTRY",
               layer+1, lot, bid+slPts, lastConfScore, (int)currentRegime);
      }
   }
}

//============================================================
// ── APEX BLOQUE 5: MANAGE BASKET (Trailing + Profit Capture) ─
// Gestión del basket orientada a profit extraction, no solo BE
//============================================================
void APEX_ManageBasket(int dir)
{
   if(CountPositions(dir) == 0) return;

   double atr    = GetATR();
   if(atr <= 0) return;

   double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double avgP   = BasketAvgPrice(dir);
   double target = APEX_BasketTarget(dir, currentRegime);
   double profitRef = (dir == 1) ? bid : ask;
   double profitPts = (dir == 1) ? (bid - avgP) : (avgP - ask);

   // Trailing del basket: aplica a cada posición cuando el basket está en profit > umbral
   double trailStart = atr * BasketTrailStart;
   double trailStep  = atr * BasketTrailMul;

   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(!PositionSelectByTicket(tk)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != Magic) continue;
      int pt = (int)PositionGetInteger(POSITION_TYPE);
      if(dir ==  1 && pt != POSITION_TYPE_BUY)  continue;
      if(dir == -1 && pt != POSITION_TYPE_SELL) continue;

      double curSL = PositionGetDouble(POSITION_SL);
      double curTP = PositionGetDouble(POSITION_TP);

      // Actualizar TP dinámico del basket (regime-aware)
      double newTP = target;

      if(dir == 1 && profitPts >= trailStart)
      {
         double newSL = profitRef - trailStep;
         // SL: nunca retroceder (solo avanzar a favor)
         if(newSL > curSL + _Point)
            trade.PositionModify(tk, newSL, (newTP > 0) ? newTP : curTP);
      }
      else if(dir == -1 && profitPts >= trailStart)
      {
         double newSL = profitRef + trailStep;
         if(curSL == 0.0 || newSL < curSL - _Point)
            trade.PositionModify(tk, newSL, (newTP > 0 && newTP < profitRef) ? newTP : curTP);
      }
      else
      {
         // Sin trailing aún: actualizar solo el TP dinámico si cambió
         if(newTP > 0 && MathAbs(newTP - curTP) > _Point * 2)
            trade.PositionModify(tk, curSL, newTP);
      }
   }

   // ── RECOVERY-TO-PROFIT: cuando el basket alcanzó avg y supera el objetivo ──
   // Cerrar todo cuando el precio supera el target de recovery (no solo BE)
   if(UseRecovery && recoveryCount > 0 && profitPts > 0)
   {
      double recTarget = atr * RecoveryProfitMul;   // ganancia neta sobre avg
      if(profitPts >= recTarget)
      {
         if(DebugLog) PrintFormat("[APEX] Recovery-to-Profit triggered. profitPts=%.2f target=%.2f",
            profitPts, recTarget);
         CloseAll();
         return;
      }
   }
}

//============================================================
// PEAK / RETRACE GLOBAL
//============================================================
void ManagePeak()
{
   double pnl = 0.0;
   int    cnt = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(!PositionSelectByTicket(tk)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != Magic) continue;
      pnl += PositionGetDouble(POSITION_PROFIT);
      cnt++;
   }
   if(cnt == 0) { globalPeak = 0; recoveryCount = 0; return; }
   if(pnl > globalPeak) globalPeak = pnl;

   // En RANGE y LOW_VOL: profit harvesting más agresivo (retrace 25%)
   double retracePct = (currentRegime == REGIME_RANGE || currentRegime == REGIME_LOWVOL)
                       ? 0.25 : 0.30;
   double retraceThr = MathMax(globalPeak * retracePct, 0.25);

   if(globalPeak > 0.40 && (globalPeak - pnl) >= retraceThr)
   {
      if(DebugLog) PrintFormat("[APEX] Peak=%.2f PnL=%.2f → CloseAll", globalPeak, pnl);
      CloseAll();
   }
}

//============================================================
void CloseAll()
{
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(PositionSelectByTicket(tk) && PositionGetInteger(POSITION_MAGIC)==Magic)
         trade.PositionClose(tk);
   }
   globalPeak    = 0;
   recoveryCount = 0;
}

//============================================================
int ActiveDir()
{
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(!PositionSelectByTicket(tk)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != Magic) continue;
      return ((int)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
   }
   return 0;
}

//============================================================
// MAIN TICK
//============================================================
void OnTick()
{
   if(!SpreadOK()) return;

   // ── Actualizar estado global cada tick ──
   currentRegime = DetectRegime();

   // ── Gestión del basket activo ──
   int ad = ActiveDir();
   if(ad != 0)
   {
      APEX_ManageBasket(ad);
      ManagePeak();
      // Recovery layer si condiciones lo justifican
      if(NeedsRecoveryLayer(ad))
         OpenPosition(ad, true, true);
   }
   else
   {
      ManagePeak();
   }

   // ── Lógica de nueva barra ──
   datetime barTime = iTime(_Symbol, TF_Entry, 0);
   if(barTime == lastBarEntry) return;
   lastBarEntry = barTime;

   int dir = MTF_Direction();

   // Actualizar confidence score y regime una vez por barra
   lastConfScore = (dir != 0) ? CalcConfidenceScore(dir) : 0.0;
   currentRegime = DetectRegime();

   // Reset espera estructural si dirección cambia o desaparece
   if(dir == 0 || (waitConfirm && dir != pendingDir))
   {
      waitConfirm  = false;
      pendingDir   = 0;
      confirmCount = 0;
      // Grid extension sobre basket existente (no requiere confirmación nueva)
      if(ad != 0 && NeedsGridLayer(ad) && DrawdownOK())
         OpenPosition(ad, true, false);
      return;
   }

   // Acumular confirmaciones estructurales
   if(!waitConfirm) { waitConfirm = true; pendingDir = dir; confirmCount = 0; }

   if(CandleConfirms(dir) && RSI_OK(dir))
      confirmCount++;
   else
      confirmCount = MathMax(0, confirmCount - 1);

   // ── ENTRADA: solo con filtros completos + confirmación ──
   if(confirmCount >= CONFIRMS_NEEDED)
   {
      if(CountPositions(dir) == 0 && EntryFiltersOK(dir))
      {
         OpenPosition(dir, false, false);
         confirmCount = 0;
      }
      else if(CountPositions(dir) > 0 && NeedsGridLayer(dir) && DrawdownOK())
      {
         OpenPosition(dir, true, false);
         confirmCount = 0;
      }
   }

   // Grid extension contextual si el basket sigue válido
   if(ad != 0 && ad == dir && NeedsGridLayer(ad) && DrawdownOK())
      OpenPosition(ad, true, false);
}
//+------------------------------------------------------------------+
