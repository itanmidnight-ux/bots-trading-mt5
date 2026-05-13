//+------------------------------------------------------------------+
//|  XAUUSD QUANTUM QUEEN ULTIMATE v7.0 – PROFIT MAXIMIZER EDITION  |
//|  Sistema 1: Fractional Kelly Criterion (sizing matemático óptimo)|
//|  Sistema 2: MFE Dynamic TP (extensión de ganancias en vivo)     |
//|  Sistema 3: Compound Growth Accelerator (crecimiento compuesto)  |
//|  + Todo el núcleo v6: Regime, Recovery, 10-Layer Close           |
//|  Capital: $10 – Millones | Ejecución: M1/M5 | Análisis: D1-M15 |
//+------------------------------------------------------------------+
#property copyright "QQ Ultimate v7.0 – Profit Maximizer"
#property version   "7.00"
#property strict

#include <Trade/Trade.mqh>
CTrade trade;

//====================================================================
//  ENUMERACIONES
//====================================================================
enum ENUM_CAP_MODE  { CAP_NANO=0, CAP_MICRO=1, CAP_SMALL=2, CAP_MEDIUM=3, CAP_STANDARD=4 };
enum ENUM_MKT_REGIME{ REGIME_TREND=0, REGIME_RANGE=1, REGIME_VOLATILE=2 };
enum ENUM_RECOVERY  { REC_NONE=0, REC_REDUCE=1, REC_PAUSE=2, REC_COUNTER=3 };

//====================================================================
//  INPUTS
//====================================================================
input group "=== CAPITAL & RIESGO BASE ==="
input bool   InpAutoCapital      = true;
input double InpRiskPercent      = 1.0;    // % riesgo base (Kelly lo ajusta)
input int    InpMagic            = 5900;

input group "=== ★ SISTEMA 1: FRACTIONAL KELLY CRITERION ==="
input bool   InpKellyOn          = true;   // Activar Kelly adaptativo
input double InpKellyFraction    = 0.35;   // Fracción Kelly (0.25-0.50 recomendado)
input double InpKellyMinRisk     = 0.30;   // Riesgo mínimo aunque Kelly sea bajo
input double InpKellyMaxRisk     = 2.50;   // Riesgo máximo que Kelly puede dar
input int    InpKellySampleSize  = 30;     // Trades en historial para calcular Kelly

input group "=== ★ SISTEMA 2: MFE DYNAMIC TP ==="
input bool   InpMFEOn            = true;   // Activar extensión dinámica de TP
input double InpMFE_ExtendAt     = 0.70;   // Extender TP si alcanza 70% del TP original
input double InpMFE_ExtendMult   = 1.80;   // Nuevo TP = TP_original × 1.80
input double InpMFE_LockPct      = 0.50;   // Lock 50% de la ganancia al extender
input int    InpMFE_MaxExtensions= 2;      // Máx extensiones por trade
input bool   InpMFE_BreakEvenPlus= true;   // SL → BE+pequeño al extender

input group "=== ★ SISTEMA 3: COMPOUND GROWTH ACCELERATOR ==="
input bool   InpCompoundOn       = true;   // Activar acelerador compuesto
input double InpCompound_Trigger = 5.0;    // % ganancia del día para activar
input double InpCompound_Boost   = 1.40;   // Multiplicador de riesgo con ganancia
input double InpCompound_MaxBoost= 2.50;   // Boost máximo aunque gane mucho
input double InpCompound_DDReset = 2.0;    // % drawdown para resetear boost

input group "=== BREAKOUT ==="
input int    InpRangeHourStart   = 7;
input int    InpRangeHourEnd     = 8;
input int    InpBreakoutHourEnd  = 10;
input double InpRangeMinPts      = 1.5;
input double InpRangeMaxPts      = 12.0;
input double InpBreakoutOffset   = 0.20;

input group "=== EMA SCALPER ==="
input bool   InpScalperOn        = true;
input int    InpScalperHourStart = 8;
input int    InpScalperHourEnd   = 20;
input int    InpFastEMA          = 9;
input int    InpSlowEMA          = 21;
input int    InpTrendEMA         = 50;
input int    InpLongEMA          = 100;

input group "=== SL/TP BASE ==="
input double InpATR_SL_Mult      = 1.4;
input double InpATR_TP_Mult      = 2.8;
input double InpRR               = 2.2;

input group "=== PIRÁMIDE ==="
input bool   InpPyramidOn        = true;
input int    InpPyramidLevels    = 2;

input group "=== RECUPERACIÓN ==="
input bool   InpRecoveryOn       = true;
input int    InpConsecLossLimit  = 2;
input double InpRecoveryMult     = 1.5;
input int    InpMaxRecoveryTrades= 3;

input group "=== CIERRES ==="
input bool   InpTrailingOn       = true;
input bool   InpPartialClose     = true;
input bool   InpSmartExitOn      = true;
input bool   InpMomentumExitOn   = true;
input bool   InpRegimeExitOn     = true;

input group "=== PROTECCIONES ==="
input double InpMaxSpread        = 45.0;
input int    InpMinScoreBreakout = 7;
input int    InpMinScoreScalper  = 6;

input group "=== INDICADORES ==="
input int    InpBBPeriod         = 20;
input int    InpRSIPeriod        = 14;
input int    InpMFIPeriod        = 14;
input int    InpATRPeriod        = 14;
input int    InpADXPeriod        = 14;
input int    InpStochK           = 5;
input int    InpStochD           = 3;

input bool   InpShowPanel        = true;

//====================================================================
//  HANDLES
//====================================================================
int hEMA50_D1, hEMA200_D1, hATR_D1;
int hEMA50_H4, hATR_H4,    hADX_H4;
int hRSI_H1,   hATR_H1,    hEMA21_H1, hEMA50_H1;
int hATR_M15,  hBB_M15,    hADX_M15,  hRSI_M15;
int hBB_M5,    hRSI_M5,    hMFI_M5,   hATR_M5;
int hFastEMA_M5, hSlowEMA_M5, hTrendEMA_M5, hLongEMA_M5;
int hStoch_M5, hADX_M5;
int hFastEMA_M1, hSlowEMA_M1, hTrendEMA_M1, hRSI_M1, hATR_M1;

//====================================================================
//  VARIABLES DE CAPITAL
//====================================================================
ENUM_CAP_MODE    g_capMode       = CAP_NANO;
ENUM_MKT_REGIME  g_regime        = REGIME_TREND;
ENUM_RECOVERY    g_recoveryMode  = REC_NONE;

double g_riskPct, g_dailyLossUSD, g_dailyProfitUSD;
double g_minProfitLock, g_profitRetrace;
double g_pyramidTrig1, g_pyramidTrig2, g_pyramidLotMult;
double g_trailingMult, g_scalperRR;
int    g_maxTradesDay, g_maxBarsOpen, g_maxNegBars;
double g_partialAt1R, g_partialAt2R;

//====================================================================
//  ★ VARIABLES SISTEMA 1 – KELLY CRITERION
//====================================================================
double g_kellyRiskPct    = 1.0;   // Riesgo calculado por Kelly (% del balance)
double g_kellyWinRate    = 0.55;  // Winrate estimado (actualizado con historial)
double g_kellyAvgWin     = 0.0;   // Ganancia promedio en $
double g_kellyAvgLoss    = 0.0;   // Pérdida promedio en $
double g_kellyPF         = 0.0;   // Profit Factor dinámico
int    g_kellySamples    = 0;     // Trades en muestra
bool   g_kellyReady      = false; // True cuando hay suficientes muestras

//====================================================================
//  ★ VARIABLES SISTEMA 2 – MFE DYNAMIC TP
//====================================================================
struct MFETracker
{
   ulong  ticket;
   double entryPrice;
   double originalTP;
   double originalSL;
   double peakFav;       // Máxima excursión favorable en $
   double peakPrice;     // Precio en pico favorable
   int    extensions;    // Veces que se extendió el TP
   bool   isBuy;
   double lockedProfit;  // Ganancia asegurada por cierre parcial MFE
};
MFETracker g_mfeTrades[50];
int        g_mfeCount = 0;

//====================================================================
//  ★ VARIABLES SISTEMA 3 – COMPOUND GROWTH ACCELERATOR
//====================================================================
double g_compoundBoost      = 1.0;  // Multiplicador activo
double g_compoundPeakBal    = 0.0;  // Balance pico del día para DD check
double g_compoundDayGainPct = 0.0;  // % ganancia del día actual
bool   g_compoundActive     = false;

//====================================================================
//  VARIABLES DE ESTADO GENERALES
//====================================================================
double   g_rangeHigh = 0, g_rangeLow = 0;
int      g_rangeBars = 0;
bool     g_dayInvalid = false, g_initialized = false, g_triggered = false;
datetime g_breakoutTime = 0;
bool     g_sesgoUp = false, g_sesgoDn = false;
bool     g_h4Up    = false, g_h4Dn    = false;
bool     g_h1Up    = false, g_h1Dn    = false;
bool     g_m15Up   = false, g_m15Dn   = false;
int      g_tradesToday = 0;
double   g_dayStartBal = 0;
datetime g_lastDay = 0;
int      g_pyramidLevel = 0;
double   g_entry1Lot = 0, g_entry1Price = 0;
bool     g_partial1Done = false, g_partial2Done = false, g_partial3Done = false;
bool     g_beMoved = false;
double   g_peakProfit = 0, g_atr_cached = 0, g_bbMid_cached = 0, g_adxVal = 0;
double   g_atrRatio = 0;
int      g_consecLosses = 0, g_recoveryTrades = 0;
double   g_recoveryMult_state = 1.0;
datetime g_lastBarM5 = 0;

struct TradeInfo { ulong ticket; datetime openTime; double entryPrice; bool isBuy; };
TradeInfo g_openTrades[50];
int       g_openTradeCount = 0;

int    g_winsToday = 0,   g_lossesToday = 0;
int    g_totalWins = 0,   g_totalLosses = 0;
double g_totalWon  = 0,   g_totalLost   = 0;
double g_maxDrawdown = 0, g_equityPeak  = 0;

// Historial rolling para Kelly
double g_tradeHistory[100]; // + = ganancia, - = pérdida
int    g_histHead = 0, g_histCount = 0;

//====================================================================
//  OnInit
//====================================================================
int OnInit()
{
   hEMA50_D1    = iMA(_Symbol, PERIOD_D1,  50,  0, MODE_EMA, PRICE_CLOSE);
   hEMA200_D1   = iMA(_Symbol, PERIOD_D1,  200, 0, MODE_EMA, PRICE_CLOSE);
   hATR_D1      = iATR(_Symbol, PERIOD_D1, InpATRPeriod);
   hEMA50_H4    = iMA(_Symbol, PERIOD_H4,  50,  0, MODE_EMA, PRICE_CLOSE);
   hATR_H4      = iATR(_Symbol, PERIOD_H4, InpATRPeriod);
   hADX_H4      = iADX(_Symbol, PERIOD_H4, InpADXPeriod);
   hRSI_H1      = iRSI(_Symbol, PERIOD_H1, InpRSIPeriod, PRICE_CLOSE);
   hATR_H1      = iATR(_Symbol, PERIOD_H1, InpATRPeriod);
   hEMA21_H1    = iMA(_Symbol,  PERIOD_H1, 21, 0, MODE_EMA, PRICE_CLOSE);
   hEMA50_H1    = iMA(_Symbol,  PERIOD_H1, 50, 0, MODE_EMA, PRICE_CLOSE);
   hATR_M15     = iATR(_Symbol, PERIOD_M15, InpATRPeriod);
   hBB_M15      = iBands(_Symbol, PERIOD_M15, InpBBPeriod, 0, 2.0, PRICE_CLOSE);
   hADX_M15     = iADX(_Symbol, PERIOD_M15, InpADXPeriod);
   hRSI_M15     = iRSI(_Symbol, PERIOD_M15, InpRSIPeriod, PRICE_CLOSE);
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
   hFastEMA_M1  = iMA(_Symbol,  PERIOD_M1, InpFastEMA,  0, MODE_EMA, PRICE_CLOSE);
   hSlowEMA_M1  = iMA(_Symbol,  PERIOD_M1, InpSlowEMA,  0, MODE_EMA, PRICE_CLOSE);
   hTrendEMA_M1 = iMA(_Symbol,  PERIOD_M1, InpTrendEMA, 0, MODE_EMA, PRICE_CLOSE);
   hRSI_M1      = iRSI(_Symbol,  PERIOD_M1, InpRSIPeriod, PRICE_CLOSE);
   hATR_M1      = iATR(_Symbol,  PERIOD_M1, InpATRPeriod);

   bool ok = (hEMA50_D1!=INVALID_HANDLE && hEMA200_D1!=INVALID_HANDLE &&
              hADX_H4!=INVALID_HANDLE && hBB_M5!=INVALID_HANDLE &&
              hRSI_M5!=INVALID_HANDLE && hATR_M5!=INVALID_HANDLE &&
              hStoch_M5!=INVALID_HANDLE && hFastEMA_M1!=INVALID_HANDLE);
   if(!ok) { Alert("❌ Error handles"); return INIT_FAILED; }

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(10);
   g_dayStartBal  = AccountInfoDouble(ACCOUNT_BALANCE);
   g_equityPeak   = g_dayStartBal;
   g_compoundPeakBal = g_dayStartBal;

   // Cargar historial existente para Kelly
   LoadKellyHistory();
   DetectCapitalMode();
   DailyReset();
   Print("✅ QQ v7.0 | $",DoubleToString(g_dayStartBal,2),
         " | ",CapModeStr()," | Kelly:",InpKellyOn,"| MFE:",InpMFEOn," | Compound:",InpCompoundOn);
   return INIT_SUCCEEDED;
}

//====================================================================
//  OnDeinit
//====================================================================
void OnDeinit(const int reason)
{
   Comment("");
   int h[]={hEMA50_D1,hEMA200_D1,hATR_D1,hEMA50_H4,hATR_H4,hADX_H4,
            hRSI_H1,hATR_H1,hEMA21_H1,hEMA50_H1,hATR_M15,hBB_M15,
            hADX_M15,hRSI_M15,hBB_M5,hRSI_M5,hMFI_M5,hATR_M5,
            hFastEMA_M5,hSlowEMA_M5,hTrendEMA_M5,hLongEMA_M5,
            hStoch_M5,hADX_M5,hFastEMA_M1,hSlowEMA_M1,hTrendEMA_M1,
            hRSI_M1,hATR_M1};
   for(int i=0;i<ArraySize(h);i++) IndicatorRelease(h[i]);
}

//====================================================================
//  DETECCIÓN DE CAPITAL
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

   if(bal < 20.0)        // NANO: $10-$19
   {
      g_capMode=CAP_NANO; g_riskPct=1.2;
      g_dailyLossUSD=bal*0.07; g_dailyProfitUSD=bal*0.20;
      g_minProfitLock=bal*0.025; g_profitRetrace=bal*0.008;
      g_pyramidTrig1=3.0; g_pyramidTrig2=6.0; g_pyramidLotMult=0.50;
      g_trailingMult=0.60; g_scalperRR=2.5;
      g_maxTradesDay=2; g_maxBarsOpen=40; g_maxNegBars=6;
      g_partialAt1R=0.50; g_partialAt2R=0.40;
   }
   else if(bal < 50.0)   // MICRO: $20-$49
   {
      g_capMode=CAP_MICRO; g_riskPct=1.0;
      g_dailyLossUSD=bal*0.06; g_dailyProfitUSD=bal*0.18;
      g_minProfitLock=bal*0.020; g_profitRetrace=bal*0.008;
      g_pyramidTrig1=2.5; g_pyramidTrig2=5.0; g_pyramidLotMult=0.50;
      g_trailingMult=0.65; g_scalperRR=2.2;
      g_maxTradesDay=3; g_maxBarsOpen=50; g_maxNegBars=8;
      g_partialAt1R=0.45; g_partialAt2R=0.40;
   }
   else if(bal < 200.0)  // SMALL: $50-$199
   {
      g_capMode=CAP_SMALL; g_riskPct=0.9;
      g_dailyLossUSD=bal*0.05; g_dailyProfitUSD=bal*0.14;
      g_minProfitLock=bal*0.015; g_profitRetrace=bal*0.006;
      g_pyramidTrig1=1.8; g_pyramidTrig2=3.5; g_pyramidLotMult=0.60;
      g_trailingMult=0.75; g_scalperRR=2.0;
      g_maxTradesDay=4; g_maxBarsOpen=70; g_maxNegBars=12;
      g_partialAt1R=0.38; g_partialAt2R=0.40;
   }
   else if(bal < 1000.0) // MEDIUM: $200-$999
   {
      g_capMode=CAP_MEDIUM; g_riskPct=0.7;
      g_dailyLossUSD=bal*0.04; g_dailyProfitUSD=bal*0.10;
      g_minProfitLock=bal*0.012; g_profitRetrace=bal*0.005;
      g_pyramidTrig1=1.0; g_pyramidTrig2=2.0; g_pyramidLotMult=0.65;
      g_trailingMult=0.85; g_scalperRR=1.9;
      g_maxTradesDay=5; g_maxBarsOpen=90; g_maxNegBars=15;
      g_partialAt1R=0.32; g_partialAt2R=0.40;
   }
   else                   // STANDARD: $1000+
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
   if(g_capMode==CAP_NANO)     return "NANO(<$20)";
   if(g_capMode==CAP_MICRO)    return "MICRO($20-49)";
   if(g_capMode==CAP_SMALL)    return "SMALL($50-199)";
   if(g_capMode==CAP_MEDIUM)   return "MEDIUM($200-999)";
   return "STANDARD($1K+)";
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
   UpdateCompoundAccelerator(); // Sistema 3

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
   UpdateMFETracker();          // Sistema 2 – actualizar en cada tick
   TrackClosedTrades();
   UpdateKellyFromHistory();    // Sistema 1 – recalcular Kelly
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
   g_h4Up=false; g_h4Dn=false; g_h1Up=false; g_h1Dn=false;
   g_m15Up=false; g_m15Dn=false;
   g_tradesToday=0; g_peakProfit=0;
   g_pyramidLevel=0; g_entry1Lot=0; g_entry1Price=0;
   g_partial1Done=false; g_partial2Done=false; g_partial3Done=false;
   g_beMoved=false; g_openTradeCount=0; g_mfeCount=0;
   g_winsToday=0; g_lossesToday=0; g_totalWon=0; g_totalLost=0;
   // Sistema 3: resetear boost al inicio del día
   g_compoundBoost=1.0; g_compoundActive=false;
   g_compoundPeakBal=AccountInfoDouble(ACCOUNT_BALANCE);
   DetectCapitalMode();
}

void CheckDayReset()
{
   datetime today=iTime(_Symbol,PERIOD_D1,0);
   if(today!=g_lastDay)
   { g_dayStartBal=AccountInfoDouble(ACCOUNT_BALANCE); g_lastDay=today; DailyReset(); }
}

//====================================================================
//  SESGO MULTI-TIMEFRAME
//====================================================================
void UpdateAllBias()
{
   double e50d1[1],e200d1[1];
   if(CopyBuffer(hEMA50_D1,0,0,1,e50d1)>0 && CopyBuffer(hEMA200_D1,0,0,1,e200d1)>0)
   { g_sesgoUp=e50d1[0]>e200d1[0]; g_sesgoDn=e50d1[0]<e200d1[0]; }

   double e50h4[1]; double cH4=iClose(_Symbol,PERIOD_H4,0);
   if(CopyBuffer(hEMA50_H4,0,0,1,e50h4)>0)
   { g_h4Up=cH4>e50h4[0]; g_h4Dn=cH4<e50h4[0]; }

   double e21h1[1],e50h1[1],rH1[1];
   if(CopyBuffer(hEMA21_H1,0,0,1,e21h1)>0 && CopyBuffer(hEMA50_H1,0,0,1,e50h1)>0 &&
      CopyBuffer(hRSI_H1,0,0,1,rH1)>0)
   { g_h1Up=(e21h1[0]>e50h1[0])&&(rH1[0]>50); g_h1Dn=(e21h1[0]<e50h1[0])&&(rH1[0]<50); }

   double rM15[1],axM15[1];
   if(CopyBuffer(hRSI_M15,0,0,1,rM15)>0 && CopyBuffer(hADX_M15,0,0,1,axM15)>0)
   { g_m15Up=(rM15[0]>52)&&(axM15[0]>20); g_m15Dn=(rM15[0]<48)&&(axM15[0]>20); }

   double aM5[1],aD1[1];
   if(CopyBuffer(hATR_M5,0,0,1,aM5)>0 && aM5[0]>0) g_atr_cached=aM5[0];
   if(CopyBuffer(hATR_D1,0,0,1,aD1)>0 && aD1[0]>0 && aM5[0]>0)
      g_atrRatio=aM5[0]/aD1[0];
}

//====================================================================
//  RÉGIMEN DE MERCADO
//====================================================================
void DetectMarketRegime()
{
   double axH4[1],axM5[1];
   bool hH4=(CopyBuffer(hADX_H4,0,0,1,axH4)>0);
   bool hM5=(CopyBuffer(hADX_M5,0,0,1,axM5)>0);
   double avg=0;
   if(hH4&&hM5) avg=(axH4[0]+axM5[0])/2.0;
   else if(hH4)  avg=axH4[0];
   else if(hM5)  avg=axM5[0];
   g_adxVal=avg;
   if(g_atrRatio>0.08)   g_regime=REGIME_VOLATILE;
   else if(avg>=25.0)    g_regime=REGIME_TREND;
   else                  g_regime=REGIME_RANGE;
}
string RegimeStr()
{ return g_regime==REGIME_TREND?"📈TREND":(g_regime==REGIME_RANGE?"↔RANGE":"⚡VOLATILE"); }

//====================================================================
//  SISTEMA DE RECUPERACIÓN
//====================================================================
void UpdateRecoveryState()
{
   if(!InpRecoveryOn) { g_recoveryMode=REC_NONE; g_recoveryMult_state=1.0; return; }
   if(g_consecLosses==0) { g_recoveryMode=REC_NONE; g_recoveryMult_state=1.0; g_recoveryTrades=0; }
   else if(g_consecLosses==1) { g_recoveryMode=REC_REDUCE; g_recoveryMult_state=0.80; }
   else if(g_consecLosses>=InpConsecLossLimit && g_consecLosses<InpConsecLossLimit+2)
   { g_recoveryMode=REC_PAUSE; g_recoveryMult_state=0.60; }
   else
   {
      bool strongAlign=(g_sesgoUp&&g_h4Up&&g_h1Up)||(g_sesgoDn&&g_h4Dn&&g_h1Dn);
      if(strongAlign && g_regime==REGIME_TREND && g_recoveryTrades<InpMaxRecoveryTrades)
      { g_recoveryMode=REC_COUNTER; g_recoveryMult_state=InpRecoveryMult; }
      else { g_recoveryMode=REC_PAUSE; g_recoveryMult_state=0.60; }
   }
}
string RecoveryStr()
{ return g_recoveryMode==REC_NONE?"NORMAL":(g_recoveryMode==REC_REDUCE?"⚠REDUCIDO":
         (g_recoveryMode==REC_PAUSE?"⏸PAUSA":"🔄RECUPERACIÓN")); }

//====================================================================
//  ★ SISTEMA 1: FRACTIONAL KELLY CRITERION
//====================================================================
void LoadKellyHistory()
{
   // Cargar hasta InpKellySampleSize trades del historial de deals
   HistorySelect(0, TimeCurrent());
   int total = HistoryDealsTotal();
   int loaded = 0;
   ArrayInitialize(g_tradeHistory, 0);

   for(int i = total - 1; i >= 0 && loaded < InpKellySampleSize; i--)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != InpMagic) continue;
      ENUM_DEAL_ENTRY ent = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY);
      if(ent != DEAL_ENTRY_OUT) continue;
      double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
      if(profit == 0) continue;
      int idx = (g_histHead + loaded) % 100;
      g_tradeHistory[idx] = profit;
      loaded++;
   }
   g_histCount = loaded;
   if(g_histCount >= 10) UpdateKellyFromHistory();
}

void AddToKellyHistory(double profit)
{
   g_tradeHistory[g_histHead] = profit;
   g_histHead = (g_histHead + 1) % 100;
   if(g_histCount < 100) g_histCount++;
}

void UpdateKellyFromHistory()
{
   if(!InpKellyOn || g_histCount < 10)
   {
      g_kellyRiskPct = g_riskPct;
      g_kellyReady = false;
      return;
   }

   double totalWins = 0, totalLosses = 0;
   double sumWins = 0, sumLosses = 0;
   int    wins = 0, losses = 0;

   for(int i = 0; i < g_histCount && i < 100; i++)
   {
      double p = g_tradeHistory[i];
      if(p > 0) { wins++; sumWins   += p; }
      else if(p < 0) { losses++; sumLosses += MathAbs(p); }
   }
   int total = wins + losses;
   if(total < 10 || losses == 0) { g_kellyRiskPct = g_riskPct; return; }

   g_kellyWinRate  = (double)wins / total;
   g_kellyAvgWin   = sumWins / MathMax(wins, 1);
   g_kellyAvgLoss  = sumLosses / MathMax(losses, 1);
   g_kellyPF       = (sumWins > 0 && sumLosses > 0) ? sumWins / sumLosses : 1.0;
   g_kellySamples  = total;
   g_kellyReady    = true;

   // Kelly Formula: f* = (p*b - q) / b
   // donde b = avgWin/avgLoss, p = winrate, q = 1-p
   double b = g_kellyAvgWin / MathMax(g_kellyAvgLoss, 0.01);
   double p = g_kellyWinRate;
   double q = 1.0 - p;
   double fullKelly = (p * b - q) / MathMax(b, 0.01);

   // Fractional Kelly (reduce volatilidad manteniendo 75% del crecimiento)
   double fracKelly = fullKelly * InpKellyFraction;

   // Convertir a % de balance (aproximado)
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   // Risk % = fracKelly × (avgLoss_como_pct_del_balance)
   double avgLossPct = (g_kellyAvgLoss / MathMax(bal, 1.0)) * 100.0;
   double kellyRisk  = fracKelly * 100.0; // Como % directo del Kelly

   // Clamping: jamás por debajo de mínimo ni por encima de máximo
   kellyRisk = MathMax(InpKellyMinRisk, MathMin(InpKellyMaxRisk, kellyRisk));

   // En NANO/MICRO: limitar adicionalmente
   if(g_capMode == CAP_NANO)  kellyRisk = MathMin(kellyRisk, 1.5);
   if(g_capMode == CAP_MICRO) kellyRisk = MathMin(kellyRisk, 1.3);

   g_kellyRiskPct = kellyRisk;
}

//====================================================================
//  ★ SISTEMA 3: COMPOUND GROWTH ACCELERATOR
//====================================================================
void UpdateCompoundAccelerator()
{
   if(!InpCompoundOn) { g_compoundBoost=1.0; g_compoundActive=false; return; }

   double bal     = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double dayGain = (bal - g_dayStartBal);
   double dayGainPct = (g_dayStartBal > 0) ? (dayGain / g_dayStartBal) * 100.0 : 0;
   g_compoundDayGainPct = dayGainPct;

   // Actualizar pico del día
   if(bal > g_compoundPeakBal) g_compoundPeakBal = bal;

   // Verificar drawdown desde pico (resetear boost si DD excede umbral)
   double ddFromPeak = (g_compoundPeakBal > 0) ? (g_compoundPeakBal - equity) / g_compoundPeakBal * 100.0 : 0;
   if(ddFromPeak >= InpCompound_DDReset && g_compoundActive)
   {
      g_compoundBoost  = 1.0;
      g_compoundActive = false;
      Print("📉 Compound Boost RESETEADO por DD=",DoubleToString(ddFromPeak,2),"%");
      return;
   }

   // Activar boost si la ganancia del día supera el trigger
   if(dayGainPct >= InpCompound_Trigger)
   {
      // Boost crece proporcionalmente a la ganancia, con límite
      double boostRaw = 1.0 + (dayGainPct / InpCompound_Trigger - 1.0) * (InpCompound_Boost - 1.0);
      g_compoundBoost  = MathMin(InpCompound_MaxBoost, MathMax(1.0, boostRaw));
      g_compoundActive = true;
   }
   else
   {
      g_compoundBoost  = 1.0;
      g_compoundActive = false;
   }
}

//====================================================================
//  CÁLCULO DE LOT UNIFICADO (Kelly + Capital Mode + Compound)
//====================================================================
double CalcLot(double slPts, double riskMult)
{
   if(g_recoveryMode == REC_PAUSE) return 0;

   // Base: Kelly o riskPct normal
   double baseRisk = InpKellyOn && g_kellyReady ? g_kellyRiskPct : g_riskPct;

   // Aplicar modo de recuperación
   baseRisk *= g_recoveryMult_state;

   // Aplicar Compound Accelerator (solo si no estamos en recuperación)
   if(g_compoundActive && g_recoveryMode == REC_NONE)
      baseRisk *= g_compoundBoost;

   // Aplicar multiplicador de la entrada (scalper, retest, etc.)
   baseRisk *= riskMult;

   double bal  = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk = bal * (baseRisk / 100.0);
   double tv   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double ts   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(slPts<=0 || tv<=0 || ts<=0) return NormLot(0.01);
   double slMon = slPts / ts * tv;
   double lot   = (slMon > 0) ? risk / slMon : 0.01;

   // Límite absoluto en NANO/MICRO
   if(g_capMode==CAP_NANO)  lot=MathMin(lot, SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN)*1.5);
   if(g_capMode==CAP_MICRO) lot=MathMin(lot, SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN)*2.0);

   return NormLot(lot);
}

//====================================================================
//  SL/TP
//====================================================================
void CalcSLTP(bool isBuy, double entry, double atr, double &sl, double &tp, double customRR=0)
{
   double rrUse=(customRR>0)?customRR:InpRR;
   double slMult=InpATR_SL_Mult;
   if(g_regime==REGIME_VOLATILE) slMult*=1.20;
   if(g_capMode==CAP_NANO || g_capMode==CAP_MICRO) slMult*=1.15;
   double slD=atr*slMult;
   double tpD=slD*rrUse;
   sl=isBuy?entry-slD:entry+slD;
   tp=isBuy?entry+tpD:entry-tpD;
}

//====================================================================
//  LECTURA INDICADORES M5
//====================================================================
bool GetIndM5(double &bbU, double &bbD, double &bbM, double &rsi, double &mfi,
              double &atr, double &stK, double &adx,
              double &fE, double &sE, double &tE, double &lE)
{
   double b1[1],b2[1],b0[1],r[1],m[1],a[1],sk[1],ax[1],fe[1],se[1],te[1],le[1];
   if(CopyBuffer(hBB_M5,1,0,1,b1)<=0)  return false;
   if(CopyBuffer(hBB_M5,2,0,1,b2)<=0)  return false;
   if(CopyBuffer(hBB_M5,0,0,1,b0)<=0)  return false;
   if(CopyBuffer(hRSI_M5,0,0,1,r)<=0)  return false;
   if(CopyBuffer(hMFI_M5,0,0,1,m)<=0)  return false;
   if(CopyBuffer(hATR_M5,0,0,1,a)<=0)  return false;
   if(CopyBuffer(hStoch_M5,0,0,1,sk)<=0) return false;
   if(CopyBuffer(hADX_M5,0,0,1,ax)<=0) return false;
   if(CopyBuffer(hFastEMA_M5,0,0,1,fe)<=0)  return false;
   if(CopyBuffer(hSlowEMA_M5,0,0,1,se)<=0)  return false;
   if(CopyBuffer(hTrendEMA_M5,0,0,1,te)<=0) return false;
   if(CopyBuffer(hLongEMA_M5,0,0,1,le)<=0)  return false;
   bbU=b1[0];bbD=b2[0];bbM=b0[0];rsi=r[0];mfi=m[0];atr=a[0];
   stK=sk[0];adx=ax[0];fE=fe[0];sE=se[0];tE=te[0];lE=le[0];
   g_bbMid_cached=b0[0]; if(a[0]>0) g_atr_cached=a[0];
   return true;
}

//====================================================================
//  SCORE DE SEÑAL (0-12 puntos)
//====================================================================
int CalcScore(bool isBuy, double close, double bbM, double bbU, double bbD,
              double rsi, double mfi, double atr, double stK,
              double adx, double fE, double sE, double tE, double lE)
{
   int sc=0;
   if(isBuy&&g_sesgoUp) sc+=2; if(!isBuy&&g_sesgoDn) sc+=2;
   if(isBuy&&g_h4Up)    sc++;  if(!isBuy&&g_h4Dn)    sc++;
   if(isBuy&&g_h1Up)    sc++;  if(!isBuy&&g_h1Dn)    sc++;
   if(isBuy&&g_m15Up)   sc++;  if(!isBuy&&g_m15Dn)   sc++;
   if(isBuy&&fE>sE&&sE>tE&&tE>lE) sc++;
   if(!isBuy&&fE<sE&&sE<tE&&tE<lE) sc++;
   if(isBuy&&rsi>50&&rsi<72) sc++; if(!isBuy&&rsi<50&&rsi>28) sc++;
   if(isBuy&&stK>50&&stK<85) sc++; if(!isBuy&&stK<50&&stK>15) sc++;
   if(isBuy&&mfi>50) sc++; if(!isBuy&&mfi<50) sc++;
   if(adx>22) sc++;
   if(atr>=0.5*_Point*100) sc++;
   double spr=(double)SymbolInfoInteger(_Symbol,SYMBOL_SPREAD);
   double maxS=(g_capMode==CAP_NANO||g_capMode==CAP_MICRO)?30.0:InpMaxSpread;
   if(spr>maxS) sc-=2;
   if(g_regime==REGIME_VOLATILE&&(g_capMode==CAP_NANO||g_capMode==CAP_MICRO)) sc--;
   if(g_regime==REGIME_RANGE) sc--;
   return MathMax(0,MathMin(12,sc));
}

//====================================================================
//  BREAKOUT
//====================================================================
void SearchBreakout()
{
   if(g_triggered||!g_initialized) return;
   if(g_rangeHigh==0||g_rangeLow==0) return;
   if(g_tradesToday>=g_maxTradesDay) return;
   if(g_recoveryMode==REC_PAUSE) return;
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   if(dt.hour<InpRangeHourEnd||dt.hour>=InpBreakoutHourEnd) return;
   double dayPnL=AccountInfoDouble(ACCOUNT_BALANCE)-g_dayStartBal;
   if(dayPnL<-g_dailyLossUSD||dayPnL>g_dailyProfitUSD) return;

   double bbU,bbD,bbM,rsi,mfi,atr,stK,adx,fE,sE,tE,lE;
   if(!GetIndM5(bbU,bbD,bbM,rsi,mfi,atr,stK,adx,fE,sE,tE,lE)) return;
   double close=iClose(_Symbol,PERIOD_M5,0);
   double offset=InpBreakoutOffset*_Point*10;

   if(close>g_rangeHigh+offset)
   {
      int sc=CalcScore(true,close,bbM,bbU,bbD,rsi,mfi,atr,stK,adx,fE,sE,tE,lE);
      if(sc<InpMinScoreBreakout) return;
      double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      double sl,tp; CalcSLTP(true,ask,atr,sl,tp);
      double lot=CalcLot(ask-sl,1.0); if(lot<=0) return;
      if(trade.Buy(lot,_Symbol,ask,sl,tp))
      {
         g_triggered=true; g_tradesToday++;
         g_entry1Lot=lot; g_entry1Price=ask;
         g_pyramidLevel=0; g_partial1Done=false; g_partial2Done=false;
         g_partial3Done=false; g_beMoved=false;
         g_breakoutTime=TimeCurrent();
         if(g_recoveryMode==REC_COUNTER) g_recoveryTrades++;
         ulong t=trade.ResultOrder();
         RegisterTrade(t,ask,true); RegisterMFE(t,ask,tp,sl,true);
         Print("🟢 BRK LONG @",ask," SL:",sl," TP:",tp," Lot:",lot," Sc:",sc);
      }
   }
   else if(close<g_rangeLow-offset)
   {
      int sc=CalcScore(false,close,bbM,bbU,bbD,rsi,mfi,atr,stK,adx,fE,sE,tE,lE);
      if(sc<InpMinScoreBreakout) return;
      double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
      double sl,tp; CalcSLTP(false,bid,atr,sl,tp);
      double lot=CalcLot(sl-bid,1.0); if(lot<=0) return;
      if(trade.Sell(lot,_Symbol,bid,sl,tp))
      {
         g_triggered=true; g_tradesToday++;
         g_entry1Lot=lot; g_entry1Price=bid;
         g_pyramidLevel=0; g_partial1Done=false; g_partial2Done=false;
         g_partial3Done=false; g_beMoved=false;
         g_breakoutTime=TimeCurrent();
         if(g_recoveryMode==REC_COUNTER) g_recoveryTrades++;
         ulong t=trade.ResultOrder();
         RegisterTrade(t,bid,false); RegisterMFE(t,bid,tp,sl,false);
         Print("🔴 BRK SHORT @",bid," SL:",sl," TP:",tp," Lot:",lot," Sc:",sc);
      }
   }
}

//====================================================================
//  RETEST
//====================================================================
void SearchRetestEntry()
{
   if(!g_triggered||g_tradesToday>=g_maxTradesDay) return;
   if(CountOpenPositions()>0) return;
   if(g_recoveryMode==REC_PAUSE) return;
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   if(dt.hour>=InpBreakoutHourEnd) return;
   if(g_breakoutTime>0&&(int)((TimeCurrent()-g_breakoutTime)/PeriodSeconds(PERIOD_M5))>25) return;

   double bbU,bbD,bbM,rsi,mfi,atr,stK,adx,fE,sE,tE,lE;
   if(!GetIndM5(bbU,bbD,bbM,rsi,mfi,atr,stK,adx,fE,sE,tE,lE)) return;
   double close=iClose(_Symbol,PERIOD_M5,0);
   double zone=0.5*_Point*10;

   if(g_sesgoUp&&g_h4Up&&g_h1Up && close<=g_rangeHigh+zone && close>=g_rangeHigh-zone)
   {
      int sc=CalcScore(true,close,bbM,bbU,bbD,rsi,mfi,atr,stK,adx,fE,sE,tE,lE);
      if(sc<InpMinScoreBreakout-1) return;
      double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      double sl,tp; CalcSLTP(true,ask,atr,sl,tp);
      double lot=CalcLot(ask-sl,0.70); if(lot<=0) return;
      if(trade.Buy(lot,_Symbol,ask,sl,tp))
      { g_tradesToday++;
        ulong t=trade.ResultOrder(); RegisterTrade(t,ask,true); RegisterMFE(t,ask,tp,sl,true);
        Print("🟢 RETEST LONG @",ask," Sc:",sc); }
   }
   else if(g_sesgoDn&&g_h4Dn&&g_h1Dn && close>=g_rangeLow-zone && close<=g_rangeLow+zone)
   {
      int sc=CalcScore(false,close,bbM,bbU,bbD,rsi,mfi,atr,stK,adx,fE,sE,tE,lE);
      if(sc<InpMinScoreBreakout-1) return;
      double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
      double sl,tp; CalcSLTP(false,bid,atr,sl,tp);
      double lot=CalcLot(sl-bid,0.70); if(lot<=0) return;
      if(trade.Sell(lot,_Symbol,bid,sl,tp))
      { g_tradesToday++;
        ulong t=trade.ResultOrder(); RegisterTrade(t,bid,false); RegisterMFE(t,bid,tp,sl,false);
        Print("🔴 RETEST SHORT @",bid," Sc:",sc); }
   }
}

//====================================================================
//  PIRÁMIDE
//====================================================================
void ManagePyramid()
{
   if(!InpPyramidOn||!g_triggered) return;
   if(g_pyramidLevel>=InpPyramidLevels) return;
   if(g_tradesToday>=g_maxTradesDay) return;
   if(g_capMode==CAP_NANO||g_capMode==CAP_MICRO) return;
   if(g_recoveryMode!=REC_NONE) return;
   if(g_regime!=REGIME_TREND) return;

   ulong mT=0; bool mBuy=false; double mP=0;
   for(int i=0;i<PositionsTotal();i++)
   {
      ulong t=PositionGetTicket(i);
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      mT=t; mBuy=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
      mP=PositionGetDouble(POSITION_PRICE_OPEN); break;
   }
   if(mT==0) return;

   double trig=(g_pyramidLevel==0)?g_pyramidTrig1*_Point*10:g_pyramidTrig2*_Point*10;
   double cur=mBuy?SymbolInfoDouble(_Symbol,SYMBOL_BID):SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double mv=mBuy?(cur-mP):(mP-cur);
   if(mv<trig) return;

   double pyrLot=NormLot(g_entry1Lot*MathPow(g_pyramidLotMult,g_pyramidLevel+1));
   double bbU,bbD,bbM,rsi,mfi,atr,stK,adx,fE,sE,tE,lE;
   if(!GetIndM5(bbU,bbD,bbM,rsi,mfi,atr,stK,adx,fE,sE,tE,lE)) return;

   if(mBuy)
   {
      double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      double sl=mP, tp=ask+atr*InpATR_TP_Mult*1.5;
      if(trade.Buy(pyrLot,_Symbol,ask,sl,tp))
      { g_pyramidLevel++; g_tradesToday++;
        ulong t=trade.ResultOrder(); RegisterTrade(t,ask,true); RegisterMFE(t,ask,tp,sl,true);
        Print("📈 PYR L",g_pyramidLevel," @",ask," Lot:",pyrLot); }
   }
   else
   {
      double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
      double sl=mP, tp=bid-atr*InpATR_TP_Mult*1.5;
      if(trade.Sell(pyrLot,_Symbol,bid,sl,tp))
      { g_pyramidLevel++; g_tradesToday++;
        ulong t=trade.ResultOrder(); RegisterTrade(t,bid,false); RegisterMFE(t,bid,tp,sl,false);
        Print("📉 PYR L",g_pyramidLevel," @",bid," Lot:",pyrLot); }
   }
}

//====================================================================
//  SCALPER
//====================================================================
void RunScalperStrategy()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   if(dt.hour<InpScalperHourStart||dt.hour>=InpScalperHourEnd) return;
   if(g_tradesToday>=g_maxTradesDay) return;
   if(CountOpenPositions()>0) return;
   if(g_recoveryMode==REC_PAUSE) return;
   double dayPnL=AccountInfoDouble(ACCOUNT_BALANCE)-g_dayStartBal;
   if(dayPnL<-g_dailyLossUSD||dayPnL>g_dailyProfitUSD) return;

   datetime bM5=iTime(_Symbol,PERIOD_M5,0);
   if(bM5==g_lastBarM5) return;

   double fM5[3],sM5[3],tM5[3],lM5[2];
   ArraySetAsSeries(fM5,true);ArraySetAsSeries(sM5,true);
   ArraySetAsSeries(tM5,true);ArraySetAsSeries(lM5,true);
   if(CopyBuffer(hFastEMA_M5,0,0,3,fM5)<=0) return;
   if(CopyBuffer(hSlowEMA_M5,0,0,3,sM5)<=0) return;
   if(CopyBuffer(hTrendEMA_M5,0,0,3,tM5)<=0) return;
   if(CopyBuffer(hLongEMA_M5,0,0,2,lM5)<=0) return;
   double fM1[2],sM1[2],tM1[2];
   ArraySetAsSeries(fM1,true);ArraySetAsSeries(sM1,true);ArraySetAsSeries(tM1,true);
   if(CopyBuffer(hFastEMA_M1,0,0,2,fM1)<=0) return;
   if(CopyBuffer(hSlowEMA_M1,0,0,2,sM1)<=0) return;
   if(CopyBuffer(hTrendEMA_M1,0,0,2,tM1)<=0) return;

   double bbU,bbD,bbM,rsi,mfi,atr,stK,adx,fE,sE,tE,lE;
   if(!GetIndM5(bbU,bbD,bbM,rsi,mfi,atr,stK,adx,fE,sE,tE,lE)) return;
   if(atr<=0) return;

   double close=iClose(_Symbol,PERIOD_M5,0);
   bool crossUp=(fM5[0]>sM5[0])&&(fM5[1]<=sM5[1]);
   bool crossDn=(fM5[0]<sM5[0])&&(fM5[1]>=sM5[1]);
   bool trUp=(fM5[0]>tM5[0])&&(sM5[0]>tM5[0])&&(tM5[0]>lM5[0]);
   bool trDn=(fM5[0]<tM5[0])&&(sM5[0]<tM5[0])&&(tM5[0]<lM5[0]);
   bool alUp=(fM1[0]>sM1[0])&&(fM1[0]>tM1[0]);
   bool alDn=(fM1[0]<sM1[0])&&(fM1[0]<tM1[0]);

   bool sigB=crossUp&&trUp&&alUp;
   bool sigS=crossDn&&trDn&&alDn;
   if(!sigB&&!sigS) return;
   if(g_regime==REGIME_VOLATILE&&(g_capMode==CAP_NANO||g_capMode==CAP_MICRO)) return;

   if(sigB)
   {
      int sc=CalcScore(true,close,bbM,bbU,bbD,rsi,mfi,atr,stK,adx,fE,sE,tE,lE);
      if(sc<InpMinScoreScalper) return;
      g_lastBarM5=bM5;
      double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      double sl,tp; CalcSLTP(true,ask,atr,sl,tp,g_scalperRR);
      double lot=CalcLot(ask-sl,0.80); if(lot<=0) return;
      if(trade.Buy(lot,_Symbol,ask,sl,tp))
      { g_tradesToday++;
        if(g_recoveryMode==REC_COUNTER) g_recoveryTrades++;
        ulong t=trade.ResultOrder(); RegisterTrade(t,ask,true); RegisterMFE(t,ask,tp,sl,true);
        Print("⚡ SCL BUY @",ask," Lot:",lot," Sc:",sc," Kelly:",DoubleToString(g_kellyRiskPct,2),"%"); }
   }
   else if(sigS)
   {
      int sc=CalcScore(false,close,bbM,bbU,bbD,rsi,mfi,atr,stK,adx,fE,sE,tE,lE);
      if(sc<InpMinScoreScalper) return;
      g_lastBarM5=bM5;
      double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
      double sl,tp; CalcSLTP(false,bid,atr,sl,tp,g_scalperRR);
      double lot=CalcLot(sl-bid,0.80); if(lot<=0) return;
      if(trade.Sell(lot,_Symbol,bid,sl,tp))
      { g_tradesToday++;
        if(g_recoveryMode==REC_COUNTER) g_recoveryTrades++;
        ulong t=trade.ResultOrder(); RegisterTrade(t,bid,false); RegisterMFE(t,bid,tp,sl,false);
        Print("⚡ SCL SELL @",bid," Lot:",lot," Sc:",sc," Kelly:",DoubleToString(g_kellyRiskPct,2),"%"); }
   }
}

//====================================================================
//  ★ SISTEMA 2: MFE DYNAMIC TP TRACKER
//====================================================================
void RegisterMFE(ulong ticket, double entry, double tp, double sl, bool isBuy)
{
   if(ticket==0||g_mfeCount>=50) return;
   g_mfeTrades[g_mfeCount].ticket      = ticket;
   g_mfeTrades[g_mfeCount].entryPrice  = entry;
   g_mfeTrades[g_mfeCount].originalTP  = tp;
   g_mfeTrades[g_mfeCount].originalSL  = sl;
   g_mfeTrades[g_mfeCount].peakFav     = 0;
   g_mfeTrades[g_mfeCount].peakPrice   = entry;
   g_mfeTrades[g_mfeCount].extensions  = 0;
   g_mfeTrades[g_mfeCount].isBuy       = isBuy;
   g_mfeTrades[g_mfeCount].lockedProfit= 0;
   g_mfeCount++;
}

void UpdateMFETracker()
{
   if(!InpMFEOn) return;
   for(int i=g_mfeCount-1;i>=0;i--)
   {
      ulong ticket=g_mfeTrades[i].ticket;
      if(!PositionSelectByTicket(ticket))
      {
         // Trade cerrado: remover
         for(int j=i;j<g_mfeCount-1;j++) g_mfeTrades[j]=g_mfeTrades[j+1];
         g_mfeCount--; continue;
      }

      bool isBuy=g_mfeTrades[i].isBuy;
      double curPrice=isBuy? SymbolInfoDouble(_Symbol,SYMBOL_BID)
                           : SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      double entry=g_mfeTrades[i].entryPrice;
      double origTP=g_mfeTrades[i].originalTP;
      double origSL=g_mfeTrades[i].originalSL;
      double curSL=PositionGetDouble(POSITION_SL);
      double curTP=PositionGetDouble(POSITION_TP);
      double vol  =PositionGetDouble(POSITION_VOLUME);
      double profit=PositionGetDouble(POSITION_PROFIT);

      // Actualizar pico favorable
      double favMove=isBuy?(curPrice-entry):(entry-curPrice);
      if(favMove > g_mfeTrades[i].peakFav)
      {
         g_mfeTrades[i].peakFav   = favMove;
         g_mfeTrades[i].peakPrice = curPrice;
      }

      // Verificar si se puede extender TP
      if(g_mfeTrades[i].extensions >= InpMFE_MaxExtensions) continue;
      double origTPDist=MathAbs(origTP-entry);
      if(origTPDist<=0) continue;

      double progressToTP=isBuy?(curPrice-entry)/origTPDist:(entry-curPrice)/origTPDist;
      if(progressToTP < InpMFE_ExtendAt) continue;

      // ── EXTENDER TP ──
      double newTPDist = origTPDist * InpMFE_ExtendMult;
      double newTP     = isBuy ? entry + newTPDist : entry - newTPDist;

      // Asegurar ganancia: cierre parcial 50% antes de extender
      double lockVol = NormLot(vol * InpMFE_LockPct);
      double minV    = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
      bool locked    = false;
      if(lockVol >= minV && vol - lockVol >= minV)
      {
         trade.PositionClosePartial(ticket, lockVol);
         g_mfeTrades[i].lockedProfit = profit * InpMFE_LockPct;
         locked = true;
      }

      // Mover SL a BE+ si se pide
      double newSL = curSL;
      if(InpMFE_BreakEvenPlus)
      {
         double bePlus = isBuy ? entry + (origTPDist * 0.10) : entry - (origTPDist * 0.10);
         if(isBuy  && bePlus > curSL) newSL = bePlus;
         if(!isBuy && bePlus < curSL) newSL = bePlus;
      }

      // Modificar posición con nuevo TP
      if(PositionSelectByTicket(ticket))
      {
         trade.PositionModify(ticket, newSL, newTP);
         g_mfeTrades[i].extensions++;
         g_mfeTrades[i].originalTP = newTP; // Nuevo TP se vuelve referencia
         Print("🎯 MFE TP EXTENDIDO x",g_mfeTrades[i].extensions,
               " NuevoTP:",newTP," Lock:",locked,"(",lockVol,")");
      }
   }
}

void RemoveMFETracker(ulong ticket)
{
   for(int i=0;i<g_mfeCount;i++)
   {
      if(g_mfeTrades[i].ticket==ticket)
      {
         for(int j=i;j<g_mfeCount-1;j++) g_mfeTrades[j]=g_mfeTrades[j+1];
         g_mfeCount--; return;
      }
   }
}

//====================================================================
//  RANGO
//====================================================================
void BuildRange()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   if(dt.hour!=InpRangeHourStart) return;
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
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   if(dt.hour!=InpRangeHourEnd||dt.min!=0) return;
   g_initialized=true;
   double sz=g_rangeHigh-g_rangeLow;
   if(g_rangeBars<25||sz<InpRangeMinPts||sz>InpRangeMaxPts)
      Print("⚠️ Rango inválido sz=",sz," | Scalper activo");
}

//====================================================================
//  GESTIÓN DE TRADES ABIERTOS (10 capas)
//====================================================================
void ManageOpenTrades()
{
   double totalPnL=0; int count=0;
   double dayPnL=AccountInfoDouble(ACCOUNT_BALANCE)-g_dayStartBal;
   if(dayPnL>=g_dailyProfitUSD) { CloseAllMagic(); g_dayInvalid=true;
      Print("🎯 TARGET $",dayPnL); return; }
   if(dayPnL<=-g_dailyLossUSD)  { CloseAllMagic(); g_dayInvalid=true;
      Print("🛑 STOP $",dayPnL); return; }

   double rM5[1],fM5[1],sM5[1],tM5[1],lM5[1],aM5[1],axM5[1];
   bool hR =(CopyBuffer(hRSI_M5,0,0,1,rM5)>0);
   bool hEm=(CopyBuffer(hFastEMA_M5,0,0,1,fM5)>0&&CopyBuffer(hSlowEMA_M5,0,0,1,sM5)>0&&
             CopyBuffer(hTrendEMA_M5,0,0,1,tM5)>0&&CopyBuffer(hLongEMA_M5,0,0,1,lM5)>0);
   bool hA =(CopyBuffer(hATR_M5,0,0,1,aM5)>0);
   bool hAx=(CopyBuffer(hADX_M5,0,0,1,axM5)>0);
   if(hA&&aM5[0]>0) g_atr_cached=aM5[0];

   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      double profit=PositionGetDouble(POSITION_PROFIT);
      double openP =PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL =PositionGetDouble(POSITION_SL);
      double curTP =PositionGetDouble(POSITION_TP);
      double vol   =PositionGetDouble(POSITION_VOLUME);
      bool isBuy   =(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
      datetime tOp =(datetime)PositionGetInteger(POSITION_TIME);
      double cur   =isBuy?SymbolInfoDouble(_Symbol,SYMBOL_BID):SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      totalPnL+=profit; count++;

      // C1: Tiempo + ganancia
      int bM1=(int)((TimeCurrent()-tOp)/PeriodSeconds(PERIOD_M1));
      if(bM1>=g_maxBarsOpen&&profit>0)
      { trade.PositionClose(ticket); RemoveTradeTracker(ticket); RemoveMFETracker(ticket);
        Print("⏱ Tiempo+gan: $",profit); continue; }

      // C2: Smart exit pérdida (triple conf.)
      if(InpSmartExitOn&&profit<0&&hEm&&hR)
      {
         bool tW=isBuy?(cur<tM5[0]):(cur>tM5[0]);
         bool mW=isBuy?(rM5[0]<35):(rM5[0]>65);
         bool eW=isBuy?(fM5[0]<sM5[0]):(fM5[0]>sM5[0]);
         if(tW&&mW&&eW) { trade.PositionClose(ticket); RemoveTradeTracker(ticket); RemoveMFETracker(ticket);
            Print("🧠 Smart exit: $",profit); continue; }
      }

      // C3: Momentum perdido EN GANANCIA
      if(InpMomentumExitOn&&profit>0&&hEm)
      {
         bool mL=isBuy?(fM5[0]<sM5[0]&&sM5[0]<tM5[0]):(fM5[0]>sM5[0]&&sM5[0]>tM5[0]);
         if(mL) { trade.PositionClose(ticket); RemoveTradeTracker(ticket); RemoveMFETracker(ticket);
            Print("⚡ Momentum perdido: $",profit); continue; }
      }

      // C4: Régimen volátil + ganancia
      if(InpRegimeExitOn&&profit>0&&g_regime==REGIME_VOLATILE)
      { trade.PositionClose(ticket); RemoveTradeTracker(ticket); RemoveMFETracker(ticket);
        Print("🌪 Régimen volátil: $",profit); continue; }

      // C5: Sesgo D1 invertido + tendencia adversa prolongada
      if(profit<0&&hEm)
      {
         bool sI=isBuy?g_sesgoDn:g_sesgoUp;
         bool tI=isBuy?(cur<lM5[0]):(cur>lM5[0]);
         if(sI&&tI)
         {
            int bM5n=(int)((TimeCurrent()-tOp)/PeriodSeconds(PERIOD_M5));
            if(bM5n>=5) { trade.PositionClose(ticket); RemoveTradeTracker(ticket); RemoveMFETracker(ticket);
               Print("🔄 Sesgo invertido: $",profit); continue; }
         }
      }

      // C6: Barras negativas + ADX cayendo
      if(profit<0&&g_maxNegBars>0)
      {
         int idx=FindTradeTracker(ticket);
         if(idx>=0)
         {
            int bM5n=(int)((TimeCurrent()-g_openTrades[idx].openTime)/PeriodSeconds(PERIOD_M5));
            bool adkW=hAx&&(axM5[0]<18);
            bool tA  =hEm&&(isBuy?(fM5[0]<tM5[0]):(fM5[0]>tM5[0]));
            if(bM5n>=g_maxNegBars&&adkW&&tA)
            { trade.PositionClose(ticket); RemoveTradeTracker(ticket); RemoveMFETracker(ticket);
              Print("⏰ Neg+ADX muerto: $",profit); continue; }
         }
      }

      // C7: BB Mid adverso en ganancia
      if(profit>0&&g_bbMid_cached>0)
      {
         bool adv=isBuy?(cur<g_bbMid_cached&&openP>g_bbMid_cached):(cur>g_bbMid_cached&&openP<g_bbMid_cached);
         if(adv) { trade.PositionClose(ticket); RemoveTradeTracker(ticket); RemoveMFETracker(ticket);
            Print("🔀 BB Mid adverso: $",profit); continue; }
      }

      // C8: Cierre parcial 3 niveles
      if(InpPartialClose&&ticket==GetOldestMagicTicket())
      {
         double slD=MathAbs(openP-curSL);
         double mvR=(slD>0)?MathAbs(cur-openP)/slD:0;
         double minV=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
         if(!g_partial1Done&&mvR>=1.0)
         {
            double cv=NormLot(vol*g_partialAt1R);
            if(cv>=minV) trade.PositionClosePartial(ticket,cv);
            if(!g_beMoved){ double nSL=isBuy?openP+_Point:openP-_Point;
               trade.PositionModify(ticket,nSL,curTP); g_beMoved=true; }
            g_partial1Done=true; Print("💰 Parcial1 @1R BE ON");
         }
         if(!g_partial2Done&&mvR>=2.0&&g_partial1Done)
         { double cv=NormLot(vol*g_partialAt2R); double minV2=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
           if(cv>=minV2) trade.PositionClosePartial(ticket,cv);
           g_partial2Done=true; Print("💰 Parcial2 @2R"); }
         if(!g_partial3Done&&mvR>=3.0&&g_partial2Done)
         { double cv=NormLot(vol*0.80); double minV3=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
           if(cv>=minV3) trade.PositionClosePartial(ticket,cv);
           g_partial3Done=true; Print("💰 Parcial3 @3R (80%)"); }
      }

      // C9: Trailing ATR inteligente
      if(InpTrailingOn) ApplyTrailingATR(ticket,isBuy);

      // C10: Expansión SL en régimen volátil con ganancia
      if(profit>0&&g_regime==REGIME_VOLATILE&&hA)
      {
         double dSL=isBuy?cur-aM5[0]*InpATR_SL_Mult*1.5:cur+aM5[0]*InpATR_SL_Mult*1.5;
         if(isBuy&&dSL>curSL&&dSL>openP-_Point) trade.PositionModify(ticket,dSL,curTP);
         if(!isBuy&&dSL<curSL&&dSL<openP+_Point) trade.PositionModify(ticket,dSL,curTP);
      }
   }

   // Peak Profit Lock
   if(count>0)
   {
      if(totalPnL>g_peakProfit) g_peakProfit=totalPnL;
      if(g_peakProfit>=g_minProfitLock&&totalPnL<(g_peakProfit-g_profitRetrace))
      { CloseAllMagic(); Print("💰 Peak Lock Peak=$",g_peakProfit); }
   }
   else g_peakProfit=0;
}

//====================================================================
//  TRAILING
//====================================================================
void ApplyTrailingATR(ulong ticket, bool isBuy)
{
   if(!PositionSelectByTicket(ticket)) return;
   double curSL =PositionGetDouble(POSITION_SL);
   double curTP =PositionGetDouble(POSITION_TP);
   double cur   =PositionGetDouble(POSITION_PRICE_CURRENT);
   double openP =PositionGetDouble(POSITION_PRICE_OPEN);
   double atr   =(g_atr_cached>0)?g_atr_cached:10*_Point*10;
   double slD   =MathAbs(cur-openP);
   double tFact =(slD>atr*2)?0.80:g_trailingMult;
   double trail =atr*tFact;
   if(isBuy)
   { if(cur<=openP) return;
     double nSL=cur-trail;
     if(nSL>curSL+_Point&&nSL>=openP-_Point) trade.PositionModify(ticket,nSL,curTP); }
   else
   { if(cur>=openP) return;
     double nSL=cur+trail;
     if((nSL<curSL-_Point||curSL==0)&&nSL<=openP+_Point) trade.PositionModify(ticket,nSL,curTP); }
}

//====================================================================
//  TRACKING TRADES CERRADOS
//====================================================================
void TrackClosedTrades()
{
   static int hC=0;
   HistorySelect(0,TimeCurrent());
   int total=HistoryDealsTotal();
   if(total==hC) return;
   for(int i=hC;i<total;i++)
   {
      ulong t=HistoryDealGetTicket(i);
      if(t==0) continue;
      if(HistoryDealGetInteger(t,DEAL_MAGIC)!=InpMagic) continue;
      ENUM_DEAL_ENTRY ent=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(t,DEAL_ENTRY);
      if(ent!=DEAL_ENTRY_OUT) continue;
      double profit=HistoryDealGetDouble(t,DEAL_PROFIT);
      if(profit>0) { g_winsToday++;g_totalWins++;g_totalWon+=profit;g_consecLosses=0;
         AddToKellyHistory(profit); }
      else if(profit<0) { g_lossesToday++;g_totalLosses++;g_totalLost+=MathAbs(profit);g_consecLosses++;
         AddToKellyHistory(profit);
         Print("⚠️ Pérdida #",g_consecLosses,": $",profit); }
   }
   hC=total;
}

void UpdateDrawdown()
{
   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq>g_equityPeak) g_equityPeak=eq;
   double dd=(g_equityPeak>0)?(g_equityPeak-eq)/g_equityPeak*100.0:0;
   if(dd>g_maxDrawdown) g_maxDrawdown=dd;
}

//====================================================================
//  HELPERS
//====================================================================
void RegisterTrade(ulong ticket, double entry, bool isBuy)
{
   if(ticket==0||g_openTradeCount>=50) return;
   g_openTrades[g_openTradeCount].ticket    =ticket;
   g_openTrades[g_openTradeCount].openTime  =TimeCurrent();
   g_openTrades[g_openTradeCount].entryPrice=entry;
   g_openTrades[g_openTradeCount].isBuy     =isBuy;
   g_openTradeCount++;
}
int FindTradeTracker(ulong ticket)
{ for(int i=0;i<g_openTradeCount;i++) if(g_openTrades[i].ticket==ticket) return i; return -1; }
void RemoveTradeTracker(ulong ticket)
{
   for(int i=0;i<g_openTradeCount;i++)
   { if(g_openTrades[i].ticket==ticket)
     { for(int j=i;j<g_openTradeCount-1;j++) g_openTrades[j]=g_openTrades[j+1];
       g_openTradeCount--; return; } }
}
int CountOpenPositions()
{ int c=0; for(int i=0;i<PositionsTotal();i++)
  { ulong t=PositionGetTicket(i);
    if(PositionSelectByTicket(t)&&PositionGetInteger(POSITION_MAGIC)==InpMagic) c++; }
  return c; }
ulong GetOldestMagicTicket()
{ ulong o=0; datetime ot=TimeCurrent();
  for(int i=0;i<PositionsTotal();i++)
  { ulong t=PositionGetTicket(i);
    if(!PositionSelectByTicket(t)) continue;
    if(PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
    datetime tt=(datetime)PositionGetInteger(POSITION_TIME);
    if(o==0||tt<ot){o=t;ot=tt;} }
  return o; }
void CloseAllMagic()
{ for(int i=PositionsTotal()-1;i>=0;i--)
  { ulong t=PositionGetTicket(i);
    if(PositionSelectByTicket(t)&&PositionGetInteger(POSITION_MAGIC)==InpMagic)
    { trade.PositionClose(t); RemoveTradeTracker(t); RemoveMFETracker(t); } } }
double NormLot(double lot)
{ double mn=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
  double mx=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
  double st=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
  lot=MathFloor(lot/st)*st;
  return MathMax(mn,MathMin(mx,lot)); }

//====================================================================
//  PANEL
//====================================================================
void DrawPanel()
{
   if(!InpShowPanel) return;
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   int pos=0; double pnlO=0,vol=0;
   for(int i=0;i<PositionsTotal();i++)
   { ulong t=PositionGetTicket(i);
     if(!PositionSelectByTicket(t)) continue;
     if(PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
     pos++; pnlO+=PositionGetDouble(POSITION_PROFIT); vol+=PositionGetDouble(POSITION_VOLUME); }

   double dayPnL =AccountInfoDouble(ACCOUNT_BALANCE)-g_dayStartBal;
   double balance=AccountInfoDouble(ACCOUNT_BALANCE);
   double equity =AccountInfoDouble(ACCOUNT_EQUITY);
   int    total  =g_winsToday+g_lossesToday;
   double wr     =total>0?100.0*g_winsToday/total:0;
   double pf     =g_totalLost>0?g_totalWon/g_totalLost:0;
   double dayPct =g_dayStartBal>0?dayPnL/g_dayStartBal*100.0:0;

   string est=g_dayInvalid?"❌PAUSADO":(!g_initialized?"⏳CONSTRUYENDO":(g_triggered?"✅OPERANDO":"🎯VIGILANDO"));
   string ali=""; ali+=(g_sesgoUp?"D1↑":(g_sesgoDn?"D1↓":"D1="));
   ali+=(g_h4Up?" H4↑":(g_h4Dn?" H4↓":" H4="));
   ali+=(g_h1Up?" H1↑":(g_h1Dn?" H1↓":" H1="));
   ali+=(g_m15Up?" M15↑":(g_m15Dn?" M15↓":" M15="));

   string txt="";
   txt+="╔══ QQ ULTIMATE v7.0 – PROFIT MAX ══╗\n";
   txt+=StringFormat("║ %02d:%02d | %s | %s\n",dt.hour,dt.min,est,RegimeStr());
   txt+=StringFormat("║ Capital: %s | %s\n",CapModeStr(),RecoveryStr());
   txt+=StringFormat("║ Balance: $%.2f | Equity: $%.2f\n",balance,equity);
   txt+=StringFormat("║ PnL Día: $%.2f (%.2f%%) T:$%.2f\n",dayPnL,dayPct,g_dailyProfitUSD);
   txt+=StringFormat("║ ADX: %.1f | ATR: %.4f | Ratio: %.4f\n",g_adxVal,g_atr_cached,g_atrRatio);
   txt+="╠══ ALINEACIÓN ══╣\n";
   txt+=StringFormat("║ %s\n",ali);
   txt+=StringFormat("║ Rango: H=%.2f L=%.2f\n",g_rangeHigh,g_rangeLow);
   txt+="╠══ ★ KELLY CRITERION ══╣\n";
   txt+=StringFormat("║ Kelly Risk: %.2f%% | PF: %.2f\n",g_kellyRiskPct,g_kellyPF);
   txt+=StringFormat("║ WR: %.1f%% | AvgW: $%.2f AvgL: $%.2f\n",g_kellyWinRate*100,g_kellyAvgWin,g_kellyAvgLoss);
   txt+=StringFormat("║ Muestras: %d | Listo: %s\n",g_kellySamples,g_kellyReady?"✅":"⏳");
   txt+="╠══ ★ COMPOUND ACCELERATOR ══╣\n";
   txt+=StringFormat("║ Boost: x%.2f | Activo: %s\n",g_compoundBoost,g_compoundActive?"✅":"⬜");
   txt+=StringFormat("║ Ganancia día: %.2f%% | Trigger: %.1f%%\n",g_compoundDayGainPct,InpCompound_Trigger);
   txt+="╠══ ★ MFE DYNAMIC TP ══╣\n";
   txt+=StringFormat("║ Trades MFE activos: %d\n",g_mfeCount);
   txt+="╠══ TRADES ══╣\n";
   txt+=StringFormat("║ Pos: %d | Vol: %.2f | PnL: $%.2f\n",pos,vol,pnlO);
   txt+=StringFormat("║ Hoy: %d/%d | PYR: +%d\n",g_tradesToday,g_maxTradesDay,g_pyramidLevel);
   txt+=StringFormat("║ BE:%s P1:%s P2:%s P3:%s\n",
        g_beMoved?"✅":"⬜",g_partial1Done?"✅":"⬜",g_partial2Done?"✅":"⬜",g_partial3Done?"✅":"⬜");
   txt+="╠══ ESTADÍSTICAS ══╣\n";
   txt+=StringFormat("║ W:%d L:%d | WR: %.1f%% | PF: %.2f\n",g_winsToday,g_lossesToday,wr,pf);
   txt+=StringFormat("║ Ganado: $%.2f | MaxDD: %.1f%%\n",g_totalWon,g_maxDrawdown);
   txt+=StringFormat("║ Pérd.Consec: %d | PeakLock: $%.2f\n",g_consecLosses,g_peakProfit);
   txt+=StringFormat("║ Total Global: W%d L%d\n",g_totalWins,g_totalLosses);
   txt+="╚═══════════════════════════════════╝";
   Comment(txt);
}
//+------------------------------------------------------------------+
//  FIN – QQ ULTIMATE v7.0 PROFIT MAXIMIZER
//+------------------------------------------------------------------+
