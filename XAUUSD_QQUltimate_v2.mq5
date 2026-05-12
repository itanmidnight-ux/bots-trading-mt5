//+------------------------------------------------------------------+
//|  XAUUSD QUANTUM QUEEN ULTIMATE v6.0 – MAXIMUM WINRATE EDITION   |
//|  Smart Capital | Recovery System | Market Regime Detection       |
//|  Multi-Layer Signal Scoring | 10-Layer Close System              |
//|  Ejecución: M1/M5 | Análisis: M15/H1/H4/D1                     |
//+------------------------------------------------------------------+
#property copyright "QQ Ultimate v6.0"
#property version   "6.00"
#property strict

#include <Trade/Trade.mqh>
CTrade trade;

//====================================================================
//  ENUMERACIONES
//====================================================================
enum ENUM_CAP_MODE  { CAP_MICRO=0, CAP_SMALL=1, CAP_MEDIUM=2, CAP_STANDARD=3 };
enum ENUM_MKT_REGIME{ REGIME_TREND=0, REGIME_RANGE=1, REGIME_VOLATILE=2 };
enum ENUM_RECOVERY  { REC_NONE=0, REC_REDUCE=1, REC_PAUSE=2, REC_COUNTER=3 };

//====================================================================
//  INPUTS
//====================================================================
input group "=== CAPITAL & RIESGO ==="
input bool   InpAutoCapital     = true;
input double InpRiskPercent     = 0.8;
input int    InpMagic           = 5900;

input group "=== BREAKOUT ==="
input int    InpRangeHourStart  = 7;
input int    InpRangeHourEnd    = 8;
input int    InpBreakoutHourEnd = 10;
input double InpRangeMinPts     = 1.5;
input double InpRangeMaxPts     = 12.0;
input double InpBreakoutOffset  = 0.20;

input group "=== EMA SCALPER M1/M5 ==="
input bool   InpScalperOn       = true;
input int    InpScalperHourStart= 8;
input int    InpScalperHourEnd  = 20;
input int    InpFastEMA         = 9;
input int    InpSlowEMA         = 21;
input int    InpTrendEMA        = 50;
input int    InpLongEMA         = 100;

input group "=== SL/TP ==="
input double InpATR_SL_Mult     = 1.4;
input double InpATR_TP_Mult     = 2.8;
input double InpRR              = 2.2;

input group "=== PIRÁMIDE ==="
input bool   InpPyramidOn       = true;
input int    InpPyramidLevels   = 2;

input group "=== SISTEMA DE RECUPERACIÓN ==="
input bool   InpRecoveryOn      = true;
input int    InpConsecLossLimit = 2;    // Pérdidas consecutivas antes de activar recuperación
input double InpRecoveryMult    = 1.5;  // Multiplicador de lote en modo recuperación
input int    InpMaxRecoveryTrades= 3;   // Máx trades en modo recuperación

input group "=== CIERRES AVANZADOS ==="
input bool   InpTrailingOn      = true;
input bool   InpPartialClose    = true;
input bool   InpSmartExitOn     = true;
input bool   InpMomentumExitOn  = true;
input bool   InpRegimeExitOn    = true; // Cierre si cambia régimen de mercado

input group "=== PROTECCIONES ==="
input double InpMaxSpread       = 45.0;
input int    InpMinScoreBreakout= 7;    // Score mínimo para breakout (de 10)
input int    InpMinScoreScalper = 6;    // Score mínimo para scalper (de 10)

input group "=== INDICADORES ==="
input int    InpBBPeriod        = 20;
input int    InpRSIPeriod       = 14;
input int    InpMFIPeriod       = 14;
input int    InpATRPeriod       = 14;
input int    InpADXPeriod       = 14;
input int    InpStochK          = 5;
input int    InpStochD          = 3;

input bool   InpShowPanel       = true;

//====================================================================
//  HANDLES
//====================================================================
// D1 – Sesgo macro
int hEMA50_D1, hEMA200_D1, hATR_D1;

// H4 – Tendencia intermedia
int hEMA50_H4, hATR_H4, hADX_H4;

// H1 – Dirección táctica
int hRSI_H1, hATR_H1, hEMA21_H1, hEMA50_H1;

// M15 – Contexto operativo
int hATR_M15, hBB_M15, hADX_M15, hRSI_M15;

// M5 – Principal
int hBB_M5, hRSI_M5, hMFI_M5, hATR_M5;
int hFastEMA_M5, hSlowEMA_M5, hTrendEMA_M5, hLongEMA_M5;
int hStoch_M5, hADX_M5;

// M1 – Timing fino
int hFastEMA_M1, hSlowEMA_M1, hTrendEMA_M1, hRSI_M1, hATR_M1;

//====================================================================
//  VARIABLES DE CAPITAL Y MODO
//====================================================================
ENUM_CAP_MODE    g_capMode         = CAP_MICRO;
ENUM_MKT_REGIME  g_regime          = REGIME_TREND;
ENUM_RECOVERY    g_recoveryMode    = REC_NONE;

double g_riskPct, g_dailyLossUSD, g_dailyProfitUSD;
double g_minProfitLock, g_profitRetrace;
double g_pyramidTrig1, g_pyramidTrig2, g_pyramidLotMult;
double g_trailingMult, g_scalperRR;
int    g_maxTradesDay, g_maxBarsOpen, g_maxNegBars;
double g_partialAt1R, g_partialAt2R;

//====================================================================
//  VARIABLES DE ESTADO
//====================================================================
double   g_rangeHigh = 0, g_rangeLow = 0;
int      g_rangeBars = 0;
bool     g_dayInvalid = false, g_initialized = false, g_triggered = false;
datetime g_breakoutTime = 0;

// Sesgo multi-TF
bool g_sesgoUp = false, g_sesgoDn = false;      // D1
bool g_h4Up    = false, g_h4Dn    = false;      // H4
bool g_h1Up    = false, g_h1Dn    = false;      // H1
bool g_m15Up   = false, g_m15Dn   = false;      // M15

// Gestión diaria
int      g_tradesToday = 0;
double   g_dayStartBal = 0;
datetime g_lastDay     = 0;

// Pirámide y parciales
int    g_pyramidLevel = 0;
double g_entry1Lot = 0, g_entry1Price = 0;
bool   g_partial1Done = false, g_partial2Done = false, g_partial3Done = false;
bool   g_beMoved = false;

// Gestión de riesgo
double   g_peakProfit    = 0;
double   g_atr_cached    = 0;
double   g_bbMid_cached  = 0;
double   g_adxVal        = 0;
double   g_atrRatio      = 0; // ATR M5 / ATR D1 (volatilidad relativa)

// Recuperación
int      g_consecLosses  = 0;
int      g_recoveryTrades= 0;
double   g_recoveryMult  = 1.0;
bool     g_lastWasLoss   = false;

// Tracking
datetime g_lastBarM5  = 0;
datetime g_lastBarM1  = 0;

struct TradeInfo { ulong ticket; datetime openTime; double entryPrice; bool isBuy; };
TradeInfo g_openTrades[50];
int       g_openTradeCount = 0;

// Estadísticas
int    g_winsToday = 0, g_lossesToday = 0;
int    g_totalWins = 0, g_totalLosses = 0;
double g_totalWon  = 0, g_totalLost   = 0;
double g_maxDrawdown = 0;
double g_equityPeak  = 0;

// Caché de señal para evitar recomputar
int    g_lastScoreCache = -1;
datetime g_lastScoreBar = 0;

//====================================================================
//  OnInit
//====================================================================
int OnInit()
{
   // D1
   hEMA50_D1    = iMA(_Symbol, PERIOD_D1,  50,  0, MODE_EMA, PRICE_CLOSE);
   hEMA200_D1   = iMA(_Symbol, PERIOD_D1,  200, 0, MODE_EMA, PRICE_CLOSE);
   hATR_D1      = iATR(_Symbol, PERIOD_D1, InpATRPeriod);

   // H4
   hEMA50_H4    = iMA(_Symbol, PERIOD_H4,  50, 0, MODE_EMA, PRICE_CLOSE);
   hATR_H4      = iATR(_Symbol, PERIOD_H4, InpATRPeriod);
   hADX_H4      = iADX(_Symbol, PERIOD_H4, InpADXPeriod);

   // H1
   hRSI_H1      = iRSI(_Symbol, PERIOD_H1, InpRSIPeriod, PRICE_CLOSE);
   hATR_H1      = iATR(_Symbol, PERIOD_H1, InpATRPeriod);
   hEMA21_H1    = iMA(_Symbol, PERIOD_H1,  21, 0, MODE_EMA, PRICE_CLOSE);
   hEMA50_H1    = iMA(_Symbol, PERIOD_H1,  50, 0, MODE_EMA, PRICE_CLOSE);

   // M15
   hATR_M15     = iATR(_Symbol, PERIOD_M15, InpATRPeriod);
   hBB_M15      = iBands(_Symbol, PERIOD_M15, InpBBPeriod, 0, 2.0, PRICE_CLOSE);
   hADX_M15     = iADX(_Symbol, PERIOD_M15, InpADXPeriod);
   hRSI_M15     = iRSI(_Symbol, PERIOD_M15, InpRSIPeriod, PRICE_CLOSE);

   // M5
   hBB_M5       = iBands(_Symbol, PERIOD_M5, InpBBPeriod, 0, 2.0, PRICE_CLOSE);
   hRSI_M5      = iRSI(_Symbol,  PERIOD_M5, InpRSIPeriod, PRICE_CLOSE);
   hMFI_M5      = iMFI(_Symbol,  PERIOD_M5, InpMFIPeriod, VOLUME_TICK);
   hATR_M5      = iATR(_Symbol,  PERIOD_M5, InpATRPeriod);
   hFastEMA_M5  = iMA(_Symbol,  PERIOD_M5, InpFastEMA,  0, MODE_EMA, PRICE_CLOSE);
   hSlowEMA_M5  = iMA(_Symbol,  PERIOD_M5, InpSlowEMA,  0, MODE_EMA, PRICE_CLOSE);
   hTrendEMA_M5 = iMA(_Symbol,  PERIOD_M5, InpTrendEMA, 0, MODE_EMA, PRICE_CLOSE);
   hLongEMA_M5  = iMA(_Symbol,  PERIOD_M5, InpLongEMA,  0, MODE_EMA, PRICE_CLOSE);
   hStoch_M5    = iStochastic(_Symbol, PERIOD_M5, InpStochK, InpStochD, 3, MODE_SMA, STO_LOWHIGH);
   hADX_M5      = iADX(_Symbol,  PERIOD_M5, InpADXPeriod);

   // M1
   hFastEMA_M1  = iMA(_Symbol, PERIOD_M1, InpFastEMA,  0, MODE_EMA, PRICE_CLOSE);
   hSlowEMA_M1  = iMA(_Symbol, PERIOD_M1, InpSlowEMA,  0, MODE_EMA, PRICE_CLOSE);
   hTrendEMA_M1 = iMA(_Symbol, PERIOD_M1, InpTrendEMA, 0, MODE_EMA, PRICE_CLOSE);
   hRSI_M1      = iRSI(_Symbol, PERIOD_M1, InpRSIPeriod, PRICE_CLOSE);
   hATR_M1      = iATR(_Symbol, PERIOD_M1, InpATRPeriod);

   bool ok = (hEMA50_D1 != INVALID_HANDLE && hEMA200_D1 != INVALID_HANDLE &&
              hADX_H4   != INVALID_HANDLE && hBB_M5     != INVALID_HANDLE &&
              hRSI_M5   != INVALID_HANDLE && hATR_M5    != INVALID_HANDLE &&
              hStoch_M5 != INVALID_HANDLE && hADX_M5    != INVALID_HANDLE &&
              hFastEMA_M1 != INVALID_HANDLE);
   if(!ok) { Alert("❌ Error handles indicadores"); return INIT_FAILED; }

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(10);

   g_dayStartBal = AccountInfoDouble(ACCOUNT_BALANCE);
   g_equityPeak  = g_dayStartBal;

   DetectCapitalMode();
   DailyReset();
   Print("✅ QQ Ultimate v6.0 | $", DoubleToString(g_dayStartBal,2), " | ", CapModeStr());
   return INIT_SUCCEEDED;
}

//====================================================================
//  OnDeinit
//====================================================================
void OnDeinit(const int reason)
{
   Comment("");
   int handles[] = {hEMA50_D1,hEMA200_D1,hATR_D1,hEMA50_H4,hATR_H4,hADX_H4,
                    hRSI_H1,hATR_H1,hEMA21_H1,hEMA50_H1,hATR_M15,hBB_M15,
                    hADX_M15,hRSI_M15,hBB_M5,hRSI_M5,hMFI_M5,hATR_M5,
                    hFastEMA_M5,hSlowEMA_M5,hTrendEMA_M5,hLongEMA_M5,
                    hStoch_M5,hADX_M5,hFastEMA_M1,hSlowEMA_M1,hTrendEMA_M1,
                    hRSI_M1,hATR_M1};
   for(int i=0;i<ArraySize(handles);i++) IndicatorRelease(handles[i]);
}

//====================================================================
//  ★ DETECCIÓN AUTOMÁTICA DE CAPITAL
//====================================================================
void DetectCapitalMode()
{
   if(!InpAutoCapital)
   {
      g_capMode=CAP_STANDARD; g_riskPct=InpRiskPercent;
      g_dailyLossUSD=10; g_dailyProfitUSD=30;
      g_minProfitLock=0.30; g_profitRetrace=0.15;
      g_pyramidTrig1=1.0; g_pyramidTrig2=2.0; g_pyramidLotMult=0.70;
      g_trailingMult=1.0; g_scalperRR=1.8;
      g_maxTradesDay=6; g_maxBarsOpen=120; g_maxNegBars=20;
      g_partialAt1R=0.30; g_partialAt2R=0.40; return;
   }
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);

   if(bal < 50.0)
   {
      g_capMode=CAP_MICRO; g_riskPct=1.0;
      g_dailyLossUSD=bal*0.06; g_dailyProfitUSD=bal*0.18;
      g_minProfitLock=bal*0.02; g_profitRetrace=bal*0.008;
      g_pyramidTrig1=2.5; g_pyramidTrig2=5.0; g_pyramidLotMult=0.50;
      g_trailingMult=0.65; g_scalperRR=2.2;
      g_maxTradesDay=3; g_maxBarsOpen=50; g_maxNegBars=8;
      g_partialAt1R=0.45; g_partialAt2R=0.40;
   }
   else if(bal < 200.0)
   {
      g_capMode=CAP_SMALL; g_riskPct=0.9;
      g_dailyLossUSD=bal*0.05; g_dailyProfitUSD=bal*0.14;
      g_minProfitLock=bal*0.015; g_profitRetrace=bal*0.006;
      g_pyramidTrig1=1.8; g_pyramidTrig2=3.5; g_pyramidLotMult=0.60;
      g_trailingMult=0.75; g_scalperRR=2.0;
      g_maxTradesDay=4; g_maxBarsOpen=70; g_maxNegBars=12;
      g_partialAt1R=0.38; g_partialAt2R=0.40;
   }
   else if(bal < 1000.0)
   {
      g_capMode=CAP_MEDIUM; g_riskPct=0.7;
      g_dailyLossUSD=bal*0.04; g_dailyProfitUSD=bal*0.10;
      g_minProfitLock=bal*0.012; g_profitRetrace=bal*0.005;
      g_pyramidTrig1=1.0; g_pyramidTrig2=2.0; g_pyramidLotMult=0.65;
      g_trailingMult=0.85; g_scalperRR=1.9;
      g_maxTradesDay=5; g_maxBarsOpen=90; g_maxNegBars=15;
      g_partialAt1R=0.32; g_partialAt2R=0.40;
   }
   else
   {
      g_capMode=CAP_STANDARD; g_riskPct=InpRiskPercent;
      g_dailyLossUSD=bal*0.03; g_dailyProfitUSD=bal*0.08;
      g_minProfitLock=bal*0.010; g_profitRetrace=bal*0.004;
      g_pyramidTrig1=1.0; g_pyramidTrig2=2.0; g_pyramidLotMult=0.70;
      g_trailingMult=1.0; g_scalperRR=1.8;
      g_maxTradesDay=6; g_maxBarsOpen=120; g_maxNegBars=20;
      g_partialAt1R=0.30; g_partialAt2R=0.40;
   }
}

string CapModeStr()
{
   if(g_capMode==CAP_MICRO)  return "MICRO(<$50)";
   if(g_capMode==CAP_SMALL)  return "SMALL($50-199)";
   if(g_capMode==CAP_MEDIUM) return "MEDIUM($200-999)";
   return "STANDARD(>=$1000)";
}

//====================================================================
//  OnTick
//====================================================================
void OnTick()
{
   CheckDayReset();
   UpdateAllBias();
   DetectMarketRegime();
   UpdateRecoveryState();

   if(!g_dayInvalid)
   {
      BuildRange();
      ValidateRange();
      SearchBreakout();
      SearchRetestEntry();
      ManagePyramid();
      if(InpScalperOn) RunScalperStrategy();
   }

   ManageOpenTrades();
   TrackClosedTrades();
   UpdateDrawdown();
   DrawPanel();
}

//====================================================================
//  RESET DIARIO
//====================================================================
void DailyReset()
{
   g_rangeHigh=0; g_rangeLow=0; g_rangeBars=0;
   g_dayInvalid=false; g_initialized=false;
   g_triggered=false; g_breakoutTime=0;
   g_sesgoUp=false; g_sesgoDn=false;
   g_h4Up=false; g_h4Dn=false;
   g_h1Up=false; g_h1Dn=false;
   g_m15Up=false; g_m15Dn=false;
   g_tradesToday=0; g_peakProfit=0;
   g_pyramidLevel=0; g_entry1Lot=0; g_entry1Price=0;
   g_partial1Done=false; g_partial2Done=false; g_partial3Done=false;
   g_beMoved=false; g_openTradeCount=0;
   g_winsToday=0; g_lossesToday=0;
   g_totalWon=0; g_totalLost=0;
   DetectCapitalMode();
}

void CheckDayReset()
{
   datetime today = iTime(_Symbol, PERIOD_D1, 0);
   if(today != g_lastDay)
   {
      g_dayStartBal = AccountInfoDouble(ACCOUNT_BALANCE);
      g_lastDay = today;
      DailyReset();
   }
}

//====================================================================
//  ★ SESGO MULTI-TIMEFRAME COMPLETO (D1 / H4 / H1 / M15)
//====================================================================
void UpdateAllBias()
{
   // D1 – EMA50 vs EMA200 (Golden/Death Cross estructural)
   double e50d1[1], e200d1[1];
   if(CopyBuffer(hEMA50_D1,  0, 0, 1, e50d1)  > 0 &&
      CopyBuffer(hEMA200_D1, 0, 0, 1, e200d1) > 0)
   { g_sesgoUp = e50d1[0] > e200d1[0]; g_sesgoDn = e50d1[0] < e200d1[0]; }

   // H4 – Precio vs EMA50_H4
   double e50h4[1]; double closeH4 = iClose(_Symbol, PERIOD_H4, 0);
   if(CopyBuffer(hEMA50_H4, 0, 0, 1, e50h4) > 0)
   { g_h4Up = closeH4 > e50h4[0]; g_h4Dn = closeH4 < e50h4[0]; }

   // H1 – EMA21 vs EMA50 + RSI
   double e21h1[1], e50h1[1], rsiH1[1];
   if(CopyBuffer(hEMA21_H1, 0, 0, 1, e21h1) > 0 &&
      CopyBuffer(hEMA50_H1, 0, 0, 1, e50h1) > 0 &&
      CopyBuffer(hRSI_H1,   0, 0, 1, rsiH1) > 0)
   {
      g_h1Up = (e21h1[0] > e50h1[0]) && (rsiH1[0] > 50.0);
      g_h1Dn = (e21h1[0] < e50h1[0]) && (rsiH1[0] < 50.0);
   }

   // M15 – RSI y ADX
   double rsiM15[1], adxM15[1];
   if(CopyBuffer(hRSI_M15, 0, 0, 1, rsiM15) > 0 &&
      CopyBuffer(hADX_M15, 0, 0, 1, adxM15) > 0)
   {
      g_m15Up = (rsiM15[0] > 52.0) && (adxM15[0] > 20.0);
      g_m15Dn = (rsiM15[0] < 48.0) && (adxM15[0] > 20.0);
   }

   // Cachear ATR M5 y ATR D1 para ratio de volatilidad
   double aM5[1], aD1[1];
   if(CopyBuffer(hATR_M5, 0, 0, 1, aM5) > 0 && aM5[0] > 0) g_atr_cached = aM5[0];
   if(CopyBuffer(hATR_D1, 0, 0, 1, aD1) > 0 && aD1[0] > 0)
      g_atrRatio = (aM5[0] > 0 && aD1[0] > 0) ? aM5[0]/aD1[0] : 0;
}

//====================================================================
//  ★ DETECCIÓN DE RÉGIMEN DE MERCADO
//====================================================================
void DetectMarketRegime()
{
   double adxH4[1], adxM5[1];
   bool hAdxH4 = CopyBuffer(hADX_H4, 0, 0, 1, adxH4) > 0;
   bool hAdxM5 = CopyBuffer(hADX_M5, 0, 0, 1, adxM5) > 0;

   double adxAvg = 0;
   if(hAdxH4 && hAdxM5) adxAvg = (adxH4[0] + adxM5[0]) / 2.0;
   else if(hAdxH4)      adxAvg = adxH4[0];
   else if(hAdxM5)      adxAvg = adxM5[0];
   g_adxVal = adxAvg;

   // ATR ratio: si M5 ATR es muy alto vs D1 ATR → volátil
   if(g_atrRatio > 0.08)      g_regime = REGIME_VOLATILE;
   else if(adxAvg >= 25.0)    g_regime = REGIME_TREND;
   else                       g_regime = REGIME_RANGE;
}

string RegimeStr()
{
   if(g_regime==REGIME_TREND)    return "📈TREND";
   if(g_regime==REGIME_RANGE)    return "↔RANGE";
   return "⚡VOLATILE";
}

//====================================================================
//  ★ SISTEMA DE RECUPERACIÓN INTELIGENTE
//====================================================================
void UpdateRecoveryState()
{
   if(!InpRecoveryOn) { g_recoveryMode=REC_NONE; g_recoveryMult=1.0; return; }

   if(g_consecLosses == 0)
   {
      g_recoveryMode = REC_NONE;
      g_recoveryMult = 1.0;
      g_recoveryTrades = 0;
   }
   else if(g_consecLosses == 1)
   {
      // 1 pérdida: reducir riesgo 20%
      g_recoveryMode = REC_REDUCE;
      g_recoveryMult = 0.80;
   }
   else if(g_consecLosses >= InpConsecLossLimit && g_consecLosses < InpConsecLossLimit + 2)
   {
      // N pérdidas consecutivas: pausa + esperar señal de alta calidad
      g_recoveryMode = REC_PAUSE;
      g_recoveryMult = 0.60;
   }
   else if(g_consecLosses >= InpConsecLossLimit + 2)
   {
      // Muchas pérdidas: modo recuperación activo con lote incrementado (limitado)
      // Solo si el régimen es TREND y la alineación D1+H4+H1 es total
      bool strongAlign = (g_sesgoUp && g_h4Up && g_h1Up) || (g_sesgoDn && g_h4Dn && g_h1Dn);
      if(strongAlign && g_regime == REGIME_TREND && g_recoveryTrades < InpMaxRecoveryTrades)
      {
         g_recoveryMode = REC_COUNTER;
         g_recoveryMult = InpRecoveryMult;
      }
      else
      {
         // Sin condición favorable: seguir en pausa
         g_recoveryMode = REC_PAUSE;
         g_recoveryMult = 0.60;
      }
   }
}

string RecoveryStr()
{
   if(g_recoveryMode==REC_NONE)    return "NORMAL";
   if(g_recoveryMode==REC_REDUCE)  return "⚠REDUCIDO";
   if(g_recoveryMode==REC_PAUSE)   return "⏸PAUSA";
   return "🔄RECUPERACIÓN";
}

//====================================================================
//  RANGO
//====================================================================
void BuildRange()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   if(dt.hour != InpRangeHourStart) return;
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   if(g_rangeHigh==0) g_rangeHigh=ask;
   if(g_rangeLow==0)  g_rangeLow=bid;
   g_rangeHigh=MathMax(g_rangeHigh,ask);
   g_rangeLow =MathMin(g_rangeLow, bid);
   g_rangeBars++;
}

void ValidateRange()
{
   if(g_initialized) return;
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   if(dt.hour!=InpRangeHourEnd || dt.min!=0) return;
   g_initialized=true;
   double sz=g_rangeHigh-g_rangeLow;
   if(g_rangeBars<25 || sz<InpRangeMinPts || sz>InpRangeMaxPts)
      Print("⚠️ Rango inválido sz=",sz," | Scalper activo");
}

//====================================================================
//  LECTURA INDICADORES M5
//====================================================================
bool GetIndM5(double &bbU, double &bbD, double &bbM, double &rsi,
              double &mfi, double &atr, double &stochK, double &adx,
              double &fastE, double &slowE, double &trendE, double &longE)
{
   double b1[1],b2[1],b0[1],r[1],m[1],a[1],sk[1],ax[1],fe[1],se[1],te[1],le[1];
   if(CopyBuffer(hBB_M5,       1,0,1,b1) <=0) return false;
   if(CopyBuffer(hBB_M5,       2,0,1,b2) <=0) return false;
   if(CopyBuffer(hBB_M5,       0,0,1,b0) <=0) return false;
   if(CopyBuffer(hRSI_M5,      0,0,1,r)  <=0) return false;
   if(CopyBuffer(hMFI_M5,      0,0,1,m)  <=0) return false;
   if(CopyBuffer(hATR_M5,      0,0,1,a)  <=0) return false;
   if(CopyBuffer(hStoch_M5,    0,0,1,sk) <=0) return false;
   if(CopyBuffer(hADX_M5,      0,0,1,ax) <=0) return false;
   if(CopyBuffer(hFastEMA_M5,  0,0,1,fe) <=0) return false;
   if(CopyBuffer(hSlowEMA_M5,  0,0,1,se) <=0) return false;
   if(CopyBuffer(hTrendEMA_M5, 0,0,1,te) <=0) return false;
   if(CopyBuffer(hLongEMA_M5,  0,0,1,le) <=0) return false;
   bbU=b1[0]; bbD=b2[0]; bbM=b0[0];
   rsi=r[0]; mfi=m[0]; atr=a[0];
   stochK=sk[0]; adx=ax[0];
   fastE=fe[0]; slowE=se[0]; trendE=te[0]; longE=le[0];
   g_bbMid_cached=b0[0];
   if(a[0]>0) g_atr_cached=a[0];
   return true;
}

//====================================================================
//  ★ SISTEMA DE PUNTUACIÓN DE SEÑAL (0-10) – MÁXIMO WINRATE
//====================================================================
int CalcSignalScore(bool isBuy, double close, double bbM, double bbU, double bbD,
                    double rsi, double mfi, double atr, double stochK,
                    double adx, double fastE, double slowE, double trendE, double longE)
{
   int score = 0;

   // [1] Sesgo D1 alineado (peso doble por ser estructural)
   if(isBuy  && g_sesgoUp) score += 2;
   if(!isBuy && g_sesgoDn) score += 2;

   // [2] H4 alineado
   if(isBuy  && g_h4Up) score++;
   if(!isBuy && g_h4Dn) score++;

   // [3] H1 alineado (EMA + RSI)
   if(isBuy  && g_h1Up) score++;
   if(!isBuy && g_h1Dn) score++;

   // [4] M15 alineado (ADX > 20 + RSI)
   if(isBuy  && g_m15Up) score++;
   if(!isBuy && g_m15Dn) score++;

   // [5] EMAs M5 alineadas (fast > slow > trend > long para buy)
   if(isBuy  && fastE > slowE && slowE > trendE && trendE > longE) score++;
   if(!isBuy && fastE < slowE && slowE < trendE && trendE < longE) score++;

   // [6] RSI M5 en zona de momentum no extremo
   if(isBuy  && rsi > 50.0 && rsi < 72.0) score++;
   if(!isBuy && rsi < 50.0 && rsi > 28.0) score++;

   // [7] Stochastic alineado
   if(isBuy  && stochK > 50.0 && stochK < 85.0) score++;
   if(!isBuy && stochK < 50.0 && stochK > 15.0) score++;

   // [8] MFI (volumen de dinero confirmado)
   if(isBuy  && mfi > 50.0) score++;
   if(!isBuy && mfi < 50.0) score++;

   // [9] ADX confirma trend M5
   if(adx > 22.0) score++;

   // [10] ATR mínimo (mercado en movimiento)
   double minATR = 0.5 * _Point * 100;
   if(atr >= minATR) score++;

   // Penalizaciones que restan puntos
   // Spread excesivo resta 2
   double spread = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   double maxSpr = (g_capMode==CAP_MICRO) ? 30.0 : InpMaxSpread;
   if(spread > maxSpr) score -= 2;

   // Régimen volátil en micro resta 1
   if(g_regime==REGIME_VOLATILE && g_capMode==CAP_MICRO) score--;

   // Regime range en breakout resta 1 (breakout falso probable)
   if(g_regime==REGIME_RANGE) score--;

   return MathMax(0, MathMin(12, score));
}

//====================================================================
//  LOT DINÁMICO
//====================================================================
double CalcLot(double slPts, double riskMult)
{
   // En modo pausa, no abrir nuevos trades
   if(g_recoveryMode == REC_PAUSE) return 0;

   double riskPct = g_riskPct * riskMult * g_recoveryMult;
   double bal     = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk    = bal * (riskPct / 100.0);
   double tv      = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double ts      = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(slPts<=0 || tv<=0 || ts<=0) return NormLot(0.01);
   double slMoney = slPts / ts * tv;
   double lot     = (slMoney > 0) ? risk / slMoney : 0.01;

   // Límite en micro: máx 2× lote mínimo
   if(g_capMode==CAP_MICRO)
      lot = MathMin(lot, SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN) * 2.0);

   return NormLot(lot);
}

//====================================================================
//  SL/TP DINÁMICO (ATR + régimen)
//====================================================================
void CalcSLTP(bool isBuy, double entry, double atr, double &sl, double &tp,
              double customRR = 0)
{
   double rrUse = (customRR > 0) ? customRR : InpRR;

   // En régimen volátil: ampliar SL para evitar stop hunting
   double slMult = InpATR_SL_Mult;
   if(g_regime == REGIME_VOLATILE) slMult *= 1.20;
   // En micro: ampliar SL adicionalmente
   if(g_capMode == CAP_MICRO) slMult *= 1.15;

   double slD = atr * slMult;
   double tpD = slD * rrUse;

   sl = isBuy ? entry - slD : entry + slD;
   tp = isBuy ? entry + tpD : entry - tpD;
}

//====================================================================
//  ★ BREAKOUT ENTRY (Score mínimo elevado)
//====================================================================
void SearchBreakout()
{
   if(g_triggered || !g_initialized) return;
   if(g_rangeHigh==0 || g_rangeLow==0) return;
   if(g_tradesToday >= g_maxTradesDay) return;
   if(g_recoveryMode == REC_PAUSE) return;

   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   if(dt.hour < InpRangeHourEnd || dt.hour >= InpBreakoutHourEnd) return;

   double dayPnL = AccountInfoDouble(ACCOUNT_BALANCE) - g_dayStartBal;
   if(dayPnL < -g_dailyLossUSD || dayPnL > g_dailyProfitUSD) return;

   double bbU,bbD,bbM,rsi,mfi,atr,stochK,adx,fE,sE,tE,lE;
   if(!GetIndM5(bbU,bbD,bbM,rsi,mfi,atr,stochK,adx,fE,sE,tE,lE)) return;

   double close  = iClose(_Symbol, PERIOD_M5, 0);
   double offset = InpBreakoutOffset * _Point * 10;
   int    minSc  = InpMinScoreBreakout;

   // LONG
   if(close > g_rangeHigh + offset)
   {
      int sc = CalcSignalScore(true,close,bbM,bbU,bbD,rsi,mfi,atr,stochK,adx,fE,sE,tE,lE);
      if(sc < minSc) { Print("⛔ LONG bloqueado score=",sc,"/",minSc); return; }

      double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      double sl,tp; CalcSLTP(true,ask,atr,sl,tp);
      double lot=CalcLot(ask-sl, 1.0);
      if(lot <= 0) return;

      if(trade.Buy(lot,_Symbol,ask,sl,tp))
      {
         g_triggered=true; g_tradesToday++;
         g_entry1Lot=lot; g_entry1Price=ask;
         g_pyramidLevel=0; g_partial1Done=false;
         g_partial2Done=false; g_partial3Done=false; g_beMoved=false;
         g_breakoutTime=TimeCurrent();
         if(g_recoveryMode==REC_COUNTER) g_recoveryTrades++;
         RegisterTrade(trade.ResultOrder(), ask, true);
         Print("🟢 BREAKOUT LONG @",ask," SL:",sl," TP:",tp," Lot:",lot," Score:",sc);
      }
   }
   // SHORT
   else if(close < g_rangeLow - offset)
   {
      int sc = CalcSignalScore(false,close,bbM,bbU,bbD,rsi,mfi,atr,stochK,adx,fE,sE,tE,lE);
      if(sc < minSc) { Print("⛔ SHORT bloqueado score=",sc,"/",minSc); return; }

      double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
      double sl,tp; CalcSLTP(false,bid,atr,sl,tp);
      double lot=CalcLot(sl-bid, 1.0);
      if(lot <= 0) return;

      if(trade.Sell(lot,_Symbol,bid,sl,tp))
      {
         g_triggered=true; g_tradesToday++;
         g_entry1Lot=lot; g_entry1Price=bid;
         g_pyramidLevel=0; g_partial1Done=false;
         g_partial2Done=false; g_partial3Done=false; g_beMoved=false;
         g_breakoutTime=TimeCurrent();
         if(g_recoveryMode==REC_COUNTER) g_recoveryTrades++;
         RegisterTrade(trade.ResultOrder(), bid, false);
         Print("🔴 BREAKOUT SHORT @",bid," SL:",sl," TP:",tp," Lot:",lot," Score:",sc);
      }
   }
}

//====================================================================
//  RETEST ENTRY
//====================================================================
void SearchRetestEntry()
{
   if(!g_triggered || g_tradesToday>=g_maxTradesDay) return;
   if(CountOpenPositions()>0) return;
   if(g_recoveryMode==REC_PAUSE) return;
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   if(dt.hour>=InpBreakoutHourEnd) return;

   if(g_breakoutTime>0)
   {
      int bars=(int)((TimeCurrent()-g_breakoutTime)/PeriodSeconds(PERIOD_M5));
      if(bars>25) return;
   }

   double bbU,bbD,bbM,rsi,mfi,atr,stochK,adx,fE,sE,tE,lE;
   if(!GetIndM5(bbU,bbD,bbM,rsi,mfi,atr,stochK,adx,fE,sE,tE,lE)) return;

   double close = iClose(_Symbol, PERIOD_M5, 0);
   double zone  = 0.50 * _Point * 10;
   int    minSc = InpMinScoreBreakout - 1;

   if(g_sesgoUp && g_h4Up && g_h1Up)
   {
      if(close <= g_rangeHigh+zone && close >= g_rangeHigh-zone)
      {
         int sc=CalcSignalScore(true,close,bbM,bbU,bbD,rsi,mfi,atr,stochK,adx,fE,sE,tE,lE);
         if(sc < minSc) return;
         double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
         double sl,tp; CalcSLTP(true,ask,atr,sl,tp);
         double lot=CalcLot(ask-sl,0.70);
         if(lot<=0) return;
         if(trade.Buy(lot,_Symbol,ask,sl,tp))
         { g_tradesToday++; RegisterTrade(trade.ResultOrder(),ask,true);
           Print("🟢 RETEST LONG @",ask," Score:",sc); }
      }
   }
   else if(g_sesgoDn && g_h4Dn && g_h1Dn)
   {
      if(close >= g_rangeLow-zone && close <= g_rangeLow+zone)
      {
         int sc=CalcSignalScore(false,close,bbM,bbU,bbD,rsi,mfi,atr,stochK,adx,fE,sE,tE,lE);
         if(sc < minSc) return;
         double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
         double sl,tp; CalcSLTP(false,bid,atr,sl,tp);
         double lot=CalcLot(sl-bid,0.70);
         if(lot<=0) return;
         if(trade.Sell(lot,_Symbol,bid,sl,tp))
         { g_tradesToday++; RegisterTrade(trade.ResultOrder(),bid,false);
           Print("🔴 RETEST SHORT @",bid," Score:",sc); }
      }
   }
}

//====================================================================
//  PIRÁMIDE (deshabilitada en micro y en modo recuperación)
//====================================================================
void ManagePyramid()
{
   if(!InpPyramidOn || !g_triggered) return;
   if(g_pyramidLevel >= InpPyramidLevels) return;
   if(g_tradesToday >= g_maxTradesDay) return;
   if(g_capMode == CAP_MICRO) return;
   if(g_recoveryMode != REC_NONE) return; // No piramidear en recuperación

   ulong  mTicket=0; bool mBuy=false; double mPrice=0;
   for(int i=0;i<PositionsTotal();i++)
   {
      ulong t=PositionGetTicket(i);
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      mTicket=t; mBuy=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
      mPrice=PositionGetDouble(POSITION_PRICE_OPEN); break;
   }
   if(mTicket==0) return;

   double trigPts=(g_pyramidLevel==0)? g_pyramidTrig1*_Point*10 : g_pyramidTrig2*_Point*10;
   double curP=mBuy? SymbolInfoDouble(_Symbol,SYMBOL_BID): SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double move=mBuy? (curP-mPrice): (mPrice-curP);
   if(move < trigPts) return;

   // Verificar que el régimen siga siendo TREND
   if(g_regime != REGIME_TREND) return;

   double pyrLot=NormLot(g_entry1Lot*MathPow(g_pyramidLotMult, g_pyramidLevel+1));
   double bbU,bbD,bbM,rsi,mfi,atr,stochK,adx,fE,sE,tE,lE;
   if(!GetIndM5(bbU,bbD,bbM,rsi,mfi,atr,stochK,adx,fE,sE,tE,lE)) return;

   if(mBuy)
   {
      double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      double sl=mPrice; // BE garantizado
      double tp=ask+atr*InpATR_TP_Mult*1.5;
      if(trade.Buy(pyrLot,_Symbol,ask,sl,tp))
      { g_pyramidLevel++; g_tradesToday++;
        RegisterTrade(trade.ResultOrder(),ask,true);
        Print("📈 PIRÁMIDE L",g_pyramidLevel," @",ask," Lot:",pyrLot); }
   }
   else
   {
      double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
      double sl=mPrice;
      double tp=bid-atr*InpATR_TP_Mult*1.5;
      if(trade.Sell(pyrLot,_Symbol,bid,sl,tp))
      { g_pyramidLevel++; g_tradesToday++;
        RegisterTrade(trade.ResultOrder(),bid,false);
        Print("📉 PIRÁMIDE L",g_pyramidLevel," @",bid," Lot:",pyrLot); }
   }
}

//====================================================================
//  ★ EMA SCALPER – M5/M1 con Score avanzado
//====================================================================
void RunScalperStrategy()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   if(dt.hour<InpScalperHourStart || dt.hour>=InpScalperHourEnd) return;
   if(g_tradesToday>=g_maxTradesDay) return;
   if(CountOpenPositions()>0) return;
   if(g_recoveryMode==REC_PAUSE) return;

   double dayPnL=AccountInfoDouble(ACCOUNT_BALANCE)-g_dayStartBal;
   if(dayPnL<-g_dailyLossUSD || dayPnL>g_dailyProfitUSD) return;

   // Solo ejecutar en nueva vela M5
   datetime barM5=iTime(_Symbol,PERIOD_M5,0);
   if(barM5==g_lastBarM5) return;

   // EMAs M5 (3 barras para detectar cruce)
   double fM5[3],sM5[3],tM5[3],lM5[2];
   ArraySetAsSeries(fM5,true); ArraySetAsSeries(sM5,true);
   ArraySetAsSeries(tM5,true); ArraySetAsSeries(lM5,true);
   if(CopyBuffer(hFastEMA_M5, 0,0,3,fM5) <=0) return;
   if(CopyBuffer(hSlowEMA_M5, 0,0,3,sM5) <=0) return;
   if(CopyBuffer(hTrendEMA_M5,0,0,3,tM5) <=0) return;
   if(CopyBuffer(hLongEMA_M5, 0,0,2,lM5) <=0) return;

   // EMAs M1 (confirmación)
   double fM1[2],sM1[2],tM1[2];
   ArraySetAsSeries(fM1,true); ArraySetAsSeries(sM1,true); ArraySetAsSeries(tM1,true);
   if(CopyBuffer(hFastEMA_M1, 0,0,2,fM1) <=0) return;
   if(CopyBuffer(hSlowEMA_M1, 0,0,2,sM1) <=0) return;
   if(CopyBuffer(hTrendEMA_M1,0,0,2,tM1) <=0) return;

   double bbU,bbD,bbM,rsi,mfi,atr,stochK,adx,fE,sE,tE,lE;
   if(!GetIndM5(bbU,bbD,bbM,rsi,mfi,atr,stochK,adx,fE,sE,tE,lE)) return;
   if(atr<=0) return;

   double close = iClose(_Symbol,PERIOD_M5,0);

   // Cruce nuevo de fast sobre slow M5
   bool crossUpM5 = (fM5[0]>sM5[0]) && (fM5[1]<=sM5[1]);
   bool crossDnM5 = (fM5[0]<sM5[0]) && (fM5[1]>=sM5[1]);

   // Tendencia M5 confirma (fast y slow sobre trend y long)
   bool trendUpM5 = (fM5[0]>tM5[0]) && (sM5[0]>tM5[0]) && (tM5[0]>lM5[0]);
   bool trendDnM5 = (fM5[0]<tM5[0]) && (sM5[0]<tM5[0]) && (tM5[0]<lM5[0]);

   // M1 confirma dirección
   bool alignUpM1 = (fM1[0]>sM1[0]) && (fM1[0]>tM1[0]);
   bool alignDnM1 = (fM1[0]<sM1[0]) && (fM1[0]<tM1[0]);

   bool sigBuy  = crossUpM5 && trendUpM5 && alignUpM1;
   bool sigSell = crossDnM5 && trendDnM5 && alignDnM1;

   if(!sigBuy && !sigSell) return;

   // Bloquear scalper en régimen volátil si cuenta micro
   if(g_regime==REGIME_VOLATILE && g_capMode==CAP_MICRO) return;

   if(sigBuy)
   {
      int sc=CalcSignalScore(true,close,bbM,bbU,bbD,rsi,mfi,atr,stochK,adx,fE,sE,tE,lE);
      if(sc < InpMinScoreScalper) return;

      g_lastBarM5=barM5;
      double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      double sl,tp; CalcSLTP(true,ask,atr,sl,tp, g_scalperRR);
      double lot=CalcLot(ask-sl, 0.80);
      if(lot<=0) return;
      if(trade.Buy(lot,_Symbol,ask,sl,tp))
      {
         g_tradesToday++;
         if(g_recoveryMode==REC_COUNTER) g_recoveryTrades++;
         RegisterTrade(trade.ResultOrder(),ask,true);
         Print("⚡ SCALPER BUY @",ask," SL:",sl," TP:",tp," Lot:",lot," Sc:",sc);
      }
   }
   else if(sigSell)
   {
      int sc=CalcSignalScore(false,close,bbM,bbU,bbD,rsi,mfi,atr,stochK,adx,fE,sE,tE,lE);
      if(sc < InpMinScoreScalper) return;

      g_lastBarM5=barM5;
      double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
      double sl,tp; CalcSLTP(false,bid,atr,sl,tp, g_scalperRR);
      double lot=CalcLot(sl-bid, 0.80);
      if(lot<=0) return;
      if(trade.Sell(lot,_Symbol,bid,sl,tp))
      {
         g_tradesToday++;
         if(g_recoveryMode==REC_COUNTER) g_recoveryTrades++;
         RegisterTrade(trade.ResultOrder(),bid,false);
         Print("⚡ SCALPER SELL @",bid," SL:",sl," TP:",tp," Lot:",lot," Sc:",sc);
      }
   }
}

//====================================================================
//  ★ GESTIÓN DE TRADES – 10 CAPAS DE CIERRE
//====================================================================
void ManageOpenTrades()
{
   double totalPnL=0; int count=0;
   double dayPnL=AccountInfoDouble(ACCOUNT_BALANCE)-g_dayStartBal;

   // Stop diario y target
   if(dayPnL >= g_dailyProfitUSD) { CloseAllMagic(); g_dayInvalid=true;
      Print("🎯 TARGET DIARIO $",dayPnL); return; }
   if(dayPnL <= -g_dailyLossUSD)  { CloseAllMagic(); g_dayInvalid=true;
      Print("🛑 STOP DIARIO $",dayPnL); return; }

   // Indicadores en caché para esta pasada
   double rsiM5[1],fM5[1],sM5[1],tM5[1],lM5[1],atrM5[1],adxM5[1];
   bool hR =(CopyBuffer(hRSI_M5,     0,0,1,rsiM5)>0);
   bool hEm=(CopyBuffer(hFastEMA_M5, 0,0,1,fM5)  >0 &&
             CopyBuffer(hSlowEMA_M5, 0,0,1,sM5)  >0 &&
             CopyBuffer(hTrendEMA_M5,0,0,1,tM5)  >0 &&
             CopyBuffer(hLongEMA_M5, 0,0,1,lM5)  >0);
   bool hA =(CopyBuffer(hATR_M5,     0,0,1,atrM5)>0);
   bool hAx=(CopyBuffer(hADX_M5,     0,0,1,adxM5)>0);
   if(hA && atrM5[0]>0) g_atr_cached=atrM5[0];

   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;

      double profit   =PositionGetDouble(POSITION_PROFIT);
      double openPrice=PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL    =PositionGetDouble(POSITION_SL);
      double curTP    =PositionGetDouble(POSITION_TP);
      double volume   =PositionGetDouble(POSITION_VOLUME);
      bool   isBuy    =(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
      datetime tOpen  =(datetime)PositionGetInteger(POSITION_TIME);
      double curPrice =isBuy ? SymbolInfoDouble(_Symbol,SYMBOL_BID)
                             : SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      totalPnL+=profit; count++;

      // ── CAPA 1: Tiempo + en ganancia ──
      int bM1=(int)((TimeCurrent()-tOpen)/PeriodSeconds(PERIOD_M1));
      if(bM1>=g_maxBarsOpen && profit>0)
      { trade.PositionClose(ticket); RemoveTradeTracker(ticket);
        Print("⏱ Tiempo+ganancia: ",bM1,"M1 $",profit); continue; }

      // ── CAPA 2: Cierre inteligente pérdida (triple confirmación) ──
      if(InpSmartExitOn && profit<0 && hEm && hR)
      {
         bool tW=isBuy ? (curPrice<tM5[0]) : (curPrice>tM5[0]);
         bool mW=isBuy ? (rsiM5[0]<35.0)  : (rsiM5[0]>65.0);
         bool eW=isBuy ? (fM5[0]<sM5[0])  : (fM5[0]>sM5[0]);
         if(tW && mW && eW)
         { trade.PositionClose(ticket); RemoveTradeTracker(ticket);
           Print("🧠 Cierre smart (3 confirmaciones): $",profit); continue; }
      }

      // ── CAPA 3: Momentum perdido EN GANANCIA (protege profits) ──
      if(InpMomentumExitOn && profit>0 && hEm)
      {
         bool mLost=isBuy ? (fM5[0]<sM5[0] && sM5[0]<tM5[0])
                          : (fM5[0]>sM5[0] && sM5[0]>tM5[0]);
         if(mLost)
         { trade.PositionClose(ticket); RemoveTradeTracker(ticket);
           Print("⚡ Momentum perdido (ganancia): $",profit); continue; }
      }

      // ── CAPA 4: Cambio de régimen adverso en ganancia ──
      if(InpRegimeExitOn && profit>0)
      {
         bool regimeAdverse = (g_regime==REGIME_VOLATILE);
         if(regimeAdverse)
         { trade.PositionClose(ticket); RemoveTradeTracker(ticket);
           Print("🌪 Cierre cambio régimen (volátil): $",profit); continue; }
      }

      // ── CAPA 5: Sesgo D1 invertido con pérdida ──
      if(profit<0 && hEm)
      {
         bool sesgInv = isBuy ? g_sesgoDn : g_sesgoUp;
         bool trendInv= isBuy ? (curPrice<lM5[0]) : (curPrice>lM5[0]);
         if(sesgInv && trendInv)
         {
            int bM5n=(int)((TimeCurrent()-tOpen)/PeriodSeconds(PERIOD_M5));
            if(bM5n >= 5) // Dar al menos 5 velas M5
            { trade.PositionClose(ticket); RemoveTradeTracker(ticket);
              Print("🔄 Cierre sesgo D1 invertido: $",profit); continue; }
         }
      }

      // ── CAPA 6: Barras negativas + ADX cayendo (trend muriendo) ──
      if(profit<0 && g_maxNegBars>0)
      {
         int idx=FindTradeTracker(ticket);
         if(idx>=0)
         {
            int bM5n=(int)((TimeCurrent()-g_openTrades[idx].openTime)/PeriodSeconds(PERIOD_M5));
            bool adxWeak = hAx && (adxM5[0] < 18.0);
            bool tAdv    = hEm && (isBuy ? fM5[0]<tM5[0] : fM5[0]>tM5[0]);
            if(bM5n>=g_maxNegBars && adxWeak && tAdv)
            { trade.PositionClose(ticket); RemoveTradeTracker(ticket);
              Print("⏰ Cierre neg prolongado+ADX muerto: $",profit); continue; }
         }
      }

      // ── CAPA 7: BB Mid adverso en ganancia (VWAP proxy) ──
      if(profit>0 && g_bbMid_cached>0)
      {
         bool adv=isBuy ? (curPrice<g_bbMid_cached && openPrice>g_bbMid_cached)
                        : (curPrice>g_bbMid_cached && openPrice<g_bbMid_cached);
         if(adv)
         { trade.PositionClose(ticket); RemoveTradeTracker(ticket);
           Print("🔀 Cierre BB Mid (VWAP): $",profit); continue; }
      }

      // ── CAPA 8: Cierre parcial progresivo 3 niveles ──
      if(InpPartialClose && ticket==GetOldestMagicTicket())
      {
         double slD =MathAbs(openPrice-curSL);
         double moveR=(slD>0) ? MathAbs(curPrice-openPrice)/slD : 0;
         double minV =SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);

         if(!g_partial1Done && moveR>=1.0)
         {
            double cv=NormLot(volume*g_partialAt1R);
            if(cv>=minV) trade.PositionClosePartial(ticket,cv);
            if(!g_beMoved)
            { double nSL=isBuy ? openPrice+_Point : openPrice-_Point;
              trade.PositionModify(ticket,nSL,curTP); g_beMoved=true; }
            g_partial1Done=true;
            Print("💰 Parcial1 (",g_partialAt1R*100,"%) @1R | BE ON");
         }
         if(!g_partial2Done && moveR>=2.0 && g_partial1Done)
         {
            double cv=NormLot(volume*g_partialAt2R);
            if(cv>=minV) trade.PositionClosePartial(ticket,cv);
            g_partial2Done=true;
            Print("💰 Parcial2 (",g_partialAt2R*100,"%) @2R");
         }
         if(!g_partial3Done && moveR>=3.0 && g_partial2Done)
         {
            // Cerrar 80% del resto al 3R
            double cv=NormLot(volume*0.80);
            if(cv>=minV) trade.PositionClosePartial(ticket,cv);
            g_partial3Done=true;
            Print("💰 Parcial3 (80%) @3R");
         }
      }

      // ── CAPA 9: Trailing Stop ATR (activado solo en ganancia) ──
      if(InpTrailingOn) ApplyTrailingATR(ticket, isBuy);

      // ── CAPA 10: SL dinámico por régimen (ampliar en volátil si hay ganancia) ──
      if(profit > 0 && g_regime==REGIME_VOLATILE && hA)
      {
         // En régimen volátil con ganancia, ampliar SL para capturar más
         double dynSL = isBuy ? curPrice - atrM5[0]*InpATR_SL_Mult*1.5
                              : curPrice + atrM5[0]*InpATR_SL_Mult*1.5;
         if(isBuy  && dynSL > curSL && dynSL > openPrice-_Point)
            trade.PositionModify(ticket, dynSL, curTP);
         if(!isBuy && dynSL < curSL && dynSL < openPrice+_Point)
            trade.PositionModify(ticket, dynSL, curTP);
      }
   }

   // Peak Profit Lock global
   if(count>0)
   {
      if(totalPnL>g_peakProfit) g_peakProfit=totalPnL;
      if(g_peakProfit>=g_minProfitLock && totalPnL<(g_peakProfit-g_profitRetrace))
      { CloseAllMagic();
        Print("💰 Peak Profit Lock Peak=$",g_peakProfit," PnL=$",totalPnL); }
   }
   else g_peakProfit=0;
}

//====================================================================
//  TRAILING ATR INTELIGENTE
//====================================================================
void ApplyTrailingATR(ulong ticket, bool isBuy)
{
   if(!PositionSelectByTicket(ticket)) return;
   double curSL    =PositionGetDouble(POSITION_SL);
   double curTP    =PositionGetDouble(POSITION_TP);
   double curPrice =PositionGetDouble(POSITION_PRICE_CURRENT);
   double openPrice=PositionGetDouble(POSITION_PRICE_OPEN);
   double atr      =(g_atr_cached>0) ? g_atr_cached : 10*_Point*10;

   // Trail más ajustado cerca de BE, más amplio lejos
   double slDist = MathAbs(curPrice - openPrice);
   double trailFactor = (slDist > atr*2) ? 0.8 : g_trailingMult;
   double trail = atr * trailFactor;

   if(isBuy)
   {
      if(curPrice<=openPrice) return;
      double nSL=curPrice-trail;
      if(nSL>curSL+_Point && nSL>=openPrice-_Point)
         trade.PositionModify(ticket,nSL,curTP);
   }
   else
   {
      if(curPrice>=openPrice) return;
      double nSL=curPrice+trail;
      if((nSL<curSL-_Point || curSL==0) && nSL<=openPrice+_Point)
         trade.PositionModify(ticket,nSL,curTP);
   }
}

//====================================================================
//  TRACKING TRADES CERRADOS + ACTUALIZAR RECUPERACIÓN
//====================================================================
void TrackClosedTrades()
{
   static int histCount=0;
   HistorySelect(0, TimeCurrent());
   int total=HistoryDealsTotal();
   if(total==histCount) return;

   for(int i=histCount; i<total; i++)
   {
      ulong ticket=HistoryDealGetTicket(i);
      if(ticket==0) continue;
      if(HistoryDealGetInteger(ticket,DEAL_MAGIC)!=InpMagic) continue;
      ENUM_DEAL_ENTRY ent=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket,DEAL_ENTRY);
      if(ent!=DEAL_ENTRY_OUT) continue;

      double profit=HistoryDealGetDouble(ticket,DEAL_PROFIT);
      if(profit > 0)
      {
         g_winsToday++; g_totalWins++; g_totalWon+=profit;
         g_consecLosses=0;   // Reset pérdidas consecutivas
         g_lastWasLoss=false;
      }
      else if(profit < 0)
      {
         g_lossesToday++; g_totalLosses++; g_totalLost+=MathAbs(profit);
         g_consecLosses++;
         g_lastWasLoss=true;
         Print("⚠️ Pérdida #",g_consecLosses," consecutiva: $",profit,
               " | Modo recuperación próximo: ",g_consecLosses>=InpConsecLossLimit ? "ACTIVO":"espera");
      }
   }
   histCount=total;
}

void UpdateDrawdown()
{
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity>g_equityPeak) g_equityPeak=equity;
   double dd=(g_equityPeak>0) ? (g_equityPeak-equity)/g_equityPeak*100.0 : 0;
   if(dd>g_maxDrawdown) g_maxDrawdown=dd;
}

//====================================================================
//  HELPERS
//====================================================================
void RegisterTrade(ulong ticket, double entry, bool isBuy)
{
   if(ticket==0 || g_openTradeCount>=50) return;
   g_openTrades[g_openTradeCount].ticket    =ticket;
   g_openTrades[g_openTradeCount].openTime  =TimeCurrent();
   g_openTrades[g_openTradeCount].entryPrice=entry;
   g_openTrades[g_openTradeCount].isBuy     =isBuy;
   g_openTradeCount++;
}
int FindTradeTracker(ulong ticket)
{
   for(int i=0;i<g_openTradeCount;i++) if(g_openTrades[i].ticket==ticket) return i;
   return -1;
}
void RemoveTradeTracker(ulong ticket)
{
   for(int i=0;i<g_openTradeCount;i++)
   {
      if(g_openTrades[i].ticket==ticket)
      {
         for(int j=i;j<g_openTradeCount-1;j++) g_openTrades[j]=g_openTrades[j+1];
         g_openTradeCount--; return;
      }
   }
}
int CountOpenPositions()
{
   int c=0;
   for(int i=0;i<PositionsTotal();i++)
   {
      ulong t=PositionGetTicket(i);
      if(PositionSelectByTicket(t) && PositionGetInteger(POSITION_MAGIC)==InpMagic) c++;
   }
   return c;
}
ulong GetOldestMagicTicket()
{
   ulong oldest=0; datetime ot=TimeCurrent();
   for(int i=0;i<PositionsTotal();i++)
   {
      ulong t=PositionGetTicket(i);
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      datetime tt=(datetime)PositionGetInteger(POSITION_TIME);
      if(oldest==0||tt<ot){oldest=t;ot=tt;}
   }
   return oldest;
}
void CloseAllMagic()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i);
      if(PositionSelectByTicket(t) && PositionGetInteger(POSITION_MAGIC)==InpMagic)
      { trade.PositionClose(t); RemoveTradeTracker(t); }
   }
}
double NormLot(double lot)
{
   double mn=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double mx=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double st=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   lot=MathFloor(lot/st)*st;
   return MathMax(mn,MathMin(mx,lot));
}

//====================================================================
//  PANEL MEJORADO
//====================================================================
void DrawPanel()
{
   if(!InpShowPanel) return;
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);

   int pos=0; double pnlO=0,vol=0;
   for(int i=0;i<PositionsTotal();i++)
   {
      ulong t=PositionGetTicket(i);
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      pos++; pnlO+=PositionGetDouble(POSITION_PROFIT);
      vol +=PositionGetDouble(POSITION_VOLUME);
   }

   double dayPnL =AccountInfoDouble(ACCOUNT_BALANCE)-g_dayStartBal;
   double balance=AccountInfoDouble(ACCOUNT_BALANCE);
   double equity =AccountInfoDouble(ACCOUNT_EQUITY);
   int    total  =g_winsToday+g_lossesToday;
   double wr     =total>0 ? 100.0*g_winsToday/total : 0;
   double pf     =g_totalLost>0 ? g_totalWon/g_totalLost : 0;

   string estado=g_dayInvalid    ? "❌PAUSADO"      :
                 !g_initialized  ? "⏳CONSTRUYENDO" :
                 g_triggered     ? "✅OPERANDO"     : "🎯VIGILANDO";

   string alineacion="";
   alineacion += g_sesgoUp ? "D1↑" : (g_sesgoDn ? "D1↓" : "D1=");
   alineacion += g_h4Up    ? " H4↑" : (g_h4Dn    ? " H4↓" : " H4=");
   alineacion += g_h1Up    ? " H1↑" : (g_h1Dn    ? " H1↓" : " H1=");
   alineacion += g_m15Up   ? " M15↑": (g_m15Dn   ? " M15↓": " M15=");

   string txt="";
   txt+="╔══ QUANTUM QUEEN ULTIMATE v6.0 ══╗\n";
   txt+=StringFormat("║ %02d:%02d | %s\n",dt.hour,dt.min,estado);
   txt+=StringFormat("║ Capital: %s | %s\n",CapModeStr(),RecoveryStr());
   txt+=StringFormat("║ Balance: $%.2f | Equity: $%.2f\n",balance,equity);
   txt+=StringFormat("║ PnL Día: $%.2f | Target: $%.2f\n",dayPnL,g_dailyProfitUSD);
   txt+=StringFormat("║ Stop:    $%.2f | Pérd.Consec: %d\n",g_dailyLossUSD,g_consecLosses);
   txt+="╠══ ANÁLISIS MERCADO ══╣\n";
   txt+=StringFormat("║ %s\n",alineacion);
   txt+=StringFormat("║ Régimen: %s | ADX: %.1f\n",RegimeStr(),g_adxVal);
   txt+=StringFormat("║ ATR: %.4f | ATR Ratio: %.4f\n",g_atr_cached,g_atrRatio);
   txt+=StringFormat("║ Rango: H=%.2f L=%.2f\n",g_rangeHigh,g_rangeLow);
   txt+="╠══ TRADES ══╣\n";
   txt+=StringFormat("║ Abiertos: %d | Vol: %.2f | PnL: $%.2f\n",pos,vol,pnlO);
   txt+=StringFormat("║ Hoy: %d/%d | Pirámide: +%d\n",g_tradesToday,g_maxTradesDay,g_pyramidLevel);
   txt+=StringFormat("║ BE:%s P1:%s P2:%s P3:%s\n",
        g_beMoved?"✅":"⬜",g_partial1Done?"✅":"⬜",
        g_partial2Done?"✅":"⬜",g_partial3Done?"✅":"⬜");
   txt+="╠══ ESTADÍSTICAS ══╣\n";
   txt+=StringFormat("║ W:%d L:%d | WR: %.1f%%\n",g_winsToday,g_lossesToday,wr);
   txt+=StringFormat("║ Ganado: $%.2f | PF: %.2f\n",g_totalWon,pf);
   txt+=StringFormat("║ Peak Profit: $%.2f | DD máx: %.1f%%\n",g_peakProfit,g_maxDrawdown);
   txt+=StringFormat("║ Total W:%d L:%d (global)\n",g_totalWins,g_totalLosses);
   txt+="╚══════════════════════════════╝";

   Comment(txt);
}

//+------------------------------------------------------------------+
//  FIN – QUANTUM QUEEN ULTIMATE v6.0
//+------------------------------------------------------------------+
