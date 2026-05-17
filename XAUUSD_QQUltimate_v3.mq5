//+------------------------------------------------------------------+
//|  XAUUSD QUANTUM QUEEN EVOLUTION v10.0                            |
//|                                                                  |
//|  Motores  : QQ Breakout | EMA Scalper M1+M5 | Retest            |
//|             London ORB | Asian ORB | NY Session                  |
//|  v10.0 NEW: NANO mode (<$15) turbo | M1 bar trigger x5 speed    |
//|             D1/H1 bypass en NANO | 25 trades/día NANO            |
//|             CalcLot margin-based | MinScore dinámico NANO        |
//|  Gestión  : 10 Capas de Protección | Peak Lock | Smart Exit      |
//|                                                                  |
//|  Magic QQ = 5900 | ORB = 20250800 | ASIA = 20250900             |
//|         NY = 20251000                                            |
//+------------------------------------------------------------------+
#property copyright "QQ Evolution v10.0"
#property version   "10.00"
#property strict

#include <Trade/Trade.mqh>
CTrade trade;

//====================================================================
//  ENUMERACIONES
//====================================================================
enum ENUM_CAP_MODE
{
   CAP_MICRO    = 0,  // $1   – $24.99
   CAP_SMALL    = 1,  // $25  – $59.99
   CAP_MEDIUM   = 2,  // $60  – $119.99
   CAP_UPPER    = 3,  // $120 – $239.99
   CAP_STANDARD = 4   // $240+
};

//====================================================================
//  INPUTS – GESTIÓN DE CAPITAL
//====================================================================
input group "=== GESTIÓN DE CAPITAL ==="
input bool   InpAutoCapital      = true;   // Detectar capital en tiempo real
input double InpRiskPercent      = 0.8;    // % riesgo base por trade individual
input int    InpMagic            = 5900;   // Magic QQ (Breakout / Scalper / Retest)

//====================================================================
//  INPUTS – ESTRATEGIA QQ BREAKOUT
//====================================================================
input group "=== ESTRATEGIA QQ BREAKOUT ==="
input int    InpRangeHourStart   = 7;
input int    InpRangeHourEnd     = 8;
input int    InpBreakoutHourEnd  = 10;
input double InpRangeMinPts      = 1.5;
input double InpRangeMaxPts      = 12.0;
input double InpBreakoutOffset   = 0.20;
input double InpRR               = 2.2;

//====================================================================
//  INPUTS – EMA SCALPER
//====================================================================
input group "=== ESTRATEGIA EMA SCALPER ==="
input bool   InpScalperOn        = true;
input int    InpScalperHourStart = 8;
input int    InpScalperHourEnd   = 20;
input int    InpFastEMA          = 9;
input int    InpSlowEMA          = 21;
input int    InpTrendEMA         = 50;
input double InpScalperMinATRPts = 2.0;  // ATR mínimo en puntos para activar scalper (v9: bajado de 3.0)
input double InpScalperEMAGap    = 0.15; // Separación mínima 9/21 EMA en puntos (v9: bajado de 0.25)
input double InpScalperRSIBuy    = 50.0; // RSI mínimo para scalper BUY (v9: bajado de 52)
input double InpScalperRSISell   = 50.0; // RSI máximo para scalper SELL (v9: subido de 48)
input double InpScalperBBMaxPos  = 0.90; // Posición máxima en BB para BUY (v9: subido de 0.85)
input double InpScalperBBMinPos  = 0.10; // Posición mínima en BB para SELL (v9: bajado de 0.15)
input int    InpScalperMaxPos    = 2;    // Máx posiciones scalper simultáneas (v9: permite 2)
input int    InpScalperCooldownSec = 120; // Cooldown entre scalper mismo sentido en seg (v9: 120s vs 300s)
input bool   InpAllowOverboughtShort = true;  // v9: SHORT cuando RSI H1>68 aunque D1 sea alcista
input double InpOverboughtRSIH1  = 68.0; // Umbral RSI H1 para activar short contra-tendencia
input bool   InpUseFixedScalperLevels = true; // v9: usar TP/SL fijos por sesión (estilo QQ)
input double InpFixedScalperTPPts = 5.0;  // TP fijo scalper en puntos de precio
input double InpFixedScalperSLPts = 3.0;  // SL fijo scalper en puntos de precio

//====================================================================
//  INPUTS – LONDON ORB
//====================================================================
input group "=== ESTRATEGIA LONDON ORB (S2) ==="
input bool   InpLondonORBOn      = true;
input int    InpMagicORB         = 20250800;
input int    InpORBRangeHStart   = 7;
input int    InpORBTradeHStart   = 8;
input int    InpORBTradeHEnd     = 10;   // extendido a 10 (antes 9) para capturar más breakouts
input int    InpORBMaxMinutes    = 120;
input double InpORBRangeMinPts   = 2.0;
input double InpORBRangeMaxPts   = 10.0;
input int    InpORBMinBars       = 25;
input double InpORBBreakBuf      = 0.2;
input double InpORBSLBuffer      = 0.3;
input double InpORBRR            = 2.0;
input int    InpORBEmaFast       = 50;
input int    InpORBEmaSlow       = 200;
input int    InpORBMaxSpread     = 50;
input bool   InpORBUseRSI        = true;   // Confirmar señal ORB con RSI M5
input bool   InpORBBEOn          = true;   // Activar break-even en trades ORB
input double InpORBBELevel       = 0.80;   // R mínimo para activar BE en ORB
input bool   InpORBPartialMicro  = true;   // Cierre parcial también en MICRO/SMALL
input double InpORBMaxSlippage   = 2.0;    // Slippage máximo permitido en entrada ORB (pts precio)

//====================================================================
//  INPUTS – ASIAN ORB (SESIÓN ASIÁTICA)
//====================================================================
input group "=== ASIAN ORB ==="
input bool   InpAsianORBOn       = true;   // Activar Asian ORB
input int    InpMagicASIA        = 20250900;
input int    InpAsiaRangeHStart  = 22;     // Inicio rango Asia (hora servidor)
input int    InpAsiaTradeHStart  = 1;      // Inicio trading Asia (hora servidor)
input int    InpAsiaTradeHEnd    = 4;      // Fin trading Asia (hora servidor)
input double InpAsiaRangeMinPts  = 2.0;   // Tamaño mínimo rango Asia
input double InpAsiaRangeMaxPts  = 18.0;  // Tamaño máximo rango Asia
input int    InpAsiaMinBars      = 20;    // Barras mínimas en rango Asia
input double InpAsiaBreakBuf     = 0.30;  // Buffer de ruptura Asia
input double InpAsiaSLBuffer     = 0.30;  // Buffer SL Asia
input double InpAsiaRR           = 1.8;   // RR ratio sesión Asia
input int    InpAsiaMaxMinutes   = 180;   // Máx minutos open trade Asia

//====================================================================
//  INPUTS – NY SESSION
//====================================================================
input group "=== NY SESSION ==="
input bool   InpNYSessionOn      = true;   // Activar NY Session
input int    InpMagicNY          = 20251000;
input int    InpNYRangeHStart    = 12;     // Inicio rango NY (hora servidor)
input int    InpNYTradeHStart    = 13;     // Inicio trading NY
input int    InpNYTradeMinStart  = 30;     // Minuto inicio trading NY (13:30)
input int    InpNYTradeHEnd      = 17;     // Fin trading NY
input double InpNYRangeMinPts    = 2.0;   // Tamaño mínimo rango NY
input double InpNYRangeMaxPts    = 15.0;  // Tamaño máximo rango NY
input int    InpNYMinBars        = 15;    // Barras mínimas rango NY
input double InpNYBreakBuf       = 0.30;  // Buffer ruptura NY
input double InpNYSLBuffer       = 0.30;  // Buffer SL NY
input double InpNYRR             = 2.0;   // RR ratio sesión NY
input int    InpNYMaxMinutes     = 150;   // Máx minutos open trade NY

//====================================================================
//  INPUTS – SL/TP DINÁMICO
//====================================================================
input group "=== SL/TP DINÁMICO ==="
input double InpATR_SL_Mult      = 0.9;  // v9: reducido de 1.3 → menor drawdown
input double InpATR_TP_Mult      = 1.8;  // v9: reducido de 2.6 → TP más alcanzable
input double InpMinRR            = 1.5;   // RR mínimo real requerido (TP/SL) para abrir trade

//====================================================================
//  INPUTS – QQ ENHANCEMENT (ESCALA EN 1R, REEMPLAZA PIRÁMIDE)
//====================================================================
input group "=== QQ ENHANCEMENT ==="
input bool   InpEnhancementOn    = true;   // Scale-in a 1R en dirección del trade
input bool   InpSmartRecoveryOn  = false;  // Recovery trade a -1R (DESACTIVADO por defecto)

//====================================================================
//  INPUTS – CIERRES
//====================================================================
input group "=== CIERRES AUTOMÁTICOS ==="
input bool   InpTrailingOn       = true;
input bool   InpPartialClose     = true;
input bool   InpSmartExitOn      = true;
input bool   InpMomentumExitOn   = true;
input double InpMinProfitLock    = 0.30;

//====================================================================
//  INPUTS – PROTECCIONES
//====================================================================
input group "=== PROTECCIONES ==="
input double InpMaxSpread        = 45.0;
input double InpMaxDailyLossPct  = 3.0;
input double InpMaxEquityDropPct = 20.0;  // % máx caída equidad vs balance → cierra todo
input double InpMaxRiskPerTrade  = 5.0;   // % máx riesgo real por trade (v9: 12→5 evita margin call)
input double InpMinFreeMarginPct = 30.0;  // v9: margen libre mínimo % antes de abrir trade

//====================================================================
//  INPUTS – INDICADORES
//====================================================================
input group "=== INDICADORES ==="
input int    InpBBPeriod         = 20;
input int    InpRSIPeriod        = 14;
input int    InpMFIPeriod        = 14;
input int    InpATRPeriod        = 14;

input group "=== FILTRO NOTICIAS ==="
input bool   InpNewsFilterOn     = true;   // Bloquear entradas en ventanas de noticias
// Ventanas bloqueadas (hora servidor GMT):
// 13:25-13:45 → US data (CPI/NFP/PPI/Retail Sales)
// 18:55-19:15 → FOMC/Fed

input group "=== MÍNIMO DE BARRAS ANTES DE SALIDA ==="
input int    InpMinBarsBeforeExit = 5;     // Barras M1 mínimas antes de cualquier salida gestionada

input group "=== VETO D1 TEMPORAL ==="
input int    InpD1VetoMaxMin     = 60;     // Minutos máx de veto D1 (luego permite con score +2)

input group "=== MONITOREO ==="
input bool   InpShowPanel        = true;

//====================================================================
//  HANDLES – QQ ORIGINAL
//====================================================================
int hEMA50_D1,  hEMA200_D1;
int hRSI_H1,    hATR_H1;
int hBB_M5,     hRSI_M5,    hMFI_M5,    hATR_M5;
int hFastEMA_M5,hSlowEMA_M5,hTrendEMA_M5;
int hFastEMA_M1,hSlowEMA_M1,hTrendEMA_M1;
int hRSI_M1,    hATR_M1;

//====================================================================
//  HANDLES – LONDON ORB / ASIAN ORB / NY SESSION
//====================================================================
int hORB_EmaFast, hORB_EmaSlow;

//====================================================================
//  VARIABLES DE CAPITAL
//====================================================================
ENUM_CAP_MODE g_capMode          = CAP_MICRO;
double        g_riskPct          = 0.8;
double        g_dailyLossUSD     = 0;
double        g_dailyProfitUSD   = 0;
double        g_minProfitLock    = 0;
double        g_profitRetrace    = 0;
double        g_trailingMult     = 0;
double        g_scalperRR        = 0;
int           g_maxTradesDay     = 0;
int           g_maxBarsOpen      = 0;
int           g_maxNegBars       = 0;
double        g_partialAt1R      = 0;
double        g_partialAt2R      = 0;

// Protección de equidad y riesgo real
double        g_sessionStartEquity = 0;  // Equidad al inicio de sesión/día
double        g_maxEquityDropUSD   = 0;  // Umbral en USD para circuit breaker
double        g_microSLCapPts      = 0;  // SL máximo en unidades de precio para CAP_MICRO

// Filtro anti-simultáneo: evita múltiples trades en la misma dirección en poco tiempo
datetime      g_lastBuyTime        = 0;  // Timestamp del último LONG abierto por cualquier estrategia
datetime      g_lastSellTime       = 0;  // Timestamp del último SHORT abierto por cualquier estrategia

//====================================================================
//  ESTADO QQ
//====================================================================
double   g_rangeHigh    = 0, g_rangeLow = 0;
int      g_rangeBars    = 0;
bool     g_dayInvalid   = false;
bool     g_initialized  = false;
bool     g_triggered    = false;
datetime g_breakoutTime = 0;
bool     g_sesgoUp      = false, g_sesgoDn = false;
bool     g_h1Up         = false, g_h1Dn    = false;
int      g_tradesToday  = 0;
double   g_dayStartBal  = 0;
datetime g_lastDay      = 0;
bool     g_partial1Done = false, g_partial2Done = false, g_beMoved = false;
bool     g_enhanceDone  = false;   // QQ Enhancement ya activado este ciclo
double   g_peakProfit   = 0;
double   g_atr_cached   = 0, g_bbMid_cached = 0;
datetime g_lastBarM5    = 0;
datetime g_lastBarM1    = 0;   // v10: M1 bar tracker para scalper NANO/MICRO

// Veto D1 temporal
datetime g_d1VetoLongFiredAt  = 0;
datetime g_d1VetoShortFiredAt = 0;
bool     g_d1VetoRelaxedLong  = false;
bool     g_d1VetoRelaxedShort = false;

struct TradeInfo { ulong ticket; datetime openTime; bool enhanceDone; bool recoveryDone; };
TradeInfo g_openTrades[50];
int       g_openTradeCount = 0;

int    g_winsToday  = 0, g_lossesToday = 0;
double g_totalWon   = 0, g_totalLost   = 0;

//====================================================================
//  ESTADO LONDON ORB
//====================================================================
double   g_orbRangeHigh      = 0;
double   g_orbRangeLow       = DBL_MAX;
int      g_orbRangeBars      = 0;
bool     g_orbRangeBuilt     = false;
bool     g_orbTradeTriggered = false;
datetime g_orbLastResetDate  = 0;
datetime g_orbTradeOpenTime  = 0;
int      g_orbWinsToday      = 0, g_orbLossesToday = 0;
double   g_orbWonToday       = 0, g_orbLostToday   = 0;

//====================================================================
//  ESTADO ASIAN ORB
//====================================================================
double   g_asiaRangeHigh     = 0;
double   g_asiaRangeLow      = DBL_MAX;
int      g_asiaRangeBars     = 0;
bool     g_asiaRangeBuilt    = false;
bool     g_asiaTradeTriggered= false;
datetime g_asiaLastReset     = 0;
datetime g_asiaTradeOpenTime = 0;
int      g_asiaWinsToday     = 0, g_asiaLossesToday = 0;
double   g_asiaWonToday      = 0, g_asiaLostToday   = 0;

//====================================================================
//  ESTADO NY SESSION
//====================================================================
double   g_nyRangeHigh       = 0;
double   g_nyRangeLow        = DBL_MAX;
int      g_nyRangeBars       = 0;
bool     g_nyRangeBuilt      = false;
bool     g_nyTradeTriggered  = false;
datetime g_nyTradeOpenTime   = 0;
int      g_nyWinsToday       = 0, g_nyLossesToday = 0;
double   g_nyWonToday        = 0, g_nyLostToday   = 0;

//====================================================================
//  OnInit
//====================================================================
int OnInit()
{
   //---- QQ original ----
   hEMA50_D1    = iMA(_Symbol, PERIOD_D1, 50,  0, MODE_EMA, PRICE_CLOSE);
   hEMA200_D1   = iMA(_Symbol, PERIOD_D1, 200, 0, MODE_EMA, PRICE_CLOSE);
   hRSI_H1      = iRSI(_Symbol, PERIOD_H1, InpRSIPeriod, PRICE_CLOSE);
   hATR_H1      = iATR(_Symbol, PERIOD_H1, InpATRPeriod);
   hBB_M5       = iBands(_Symbol, PERIOD_M5, InpBBPeriod, 0, 2.0, PRICE_CLOSE);
   hRSI_M5      = iRSI(_Symbol,  PERIOD_M5, InpRSIPeriod, PRICE_CLOSE);
   hMFI_M5      = iMFI(_Symbol,  PERIOD_M5, InpMFIPeriod, VOLUME_TICK);
   hATR_M5      = iATR(_Symbol,  PERIOD_M5, InpATRPeriod);
   hFastEMA_M5  = iMA(_Symbol,  PERIOD_M5, InpFastEMA,   0, MODE_EMA, PRICE_CLOSE);
   hSlowEMA_M5  = iMA(_Symbol,  PERIOD_M5, InpSlowEMA,   0, MODE_EMA, PRICE_CLOSE);
   hTrendEMA_M5 = iMA(_Symbol,  PERIOD_M5, InpTrendEMA,  0, MODE_EMA, PRICE_CLOSE);
   hFastEMA_M1  = iMA(_Symbol,  PERIOD_M1, InpFastEMA,   0, MODE_EMA, PRICE_CLOSE);
   hSlowEMA_M1  = iMA(_Symbol,  PERIOD_M1, InpSlowEMA,   0, MODE_EMA, PRICE_CLOSE);
   hTrendEMA_M1 = iMA(_Symbol,  PERIOD_M1, InpTrendEMA,  0, MODE_EMA, PRICE_CLOSE);
   hRSI_M1      = iRSI(_Symbol,  PERIOD_M1, InpRSIPeriod, PRICE_CLOSE);
   hATR_M1      = iATR(_Symbol,  PERIOD_M1, InpATRPeriod);

   //---- ORB / Asian / NY ----
   hORB_EmaFast = iMA(_Symbol, PERIOD_M1, InpORBEmaFast, 0, MODE_EMA, PRICE_CLOSE);
   hORB_EmaSlow = iMA(_Symbol, PERIOD_M1, InpORBEmaSlow, 0, MODE_EMA, PRICE_CLOSE);

   // Verificar handles críticos
   int criticals[] = {
      hEMA50_D1, hEMA200_D1, hRSI_H1, hATR_H1,
      hBB_M5, hRSI_M5, hMFI_M5, hATR_M5, hFastEMA_M5, hSlowEMA_M5, hTrendEMA_M5,
      hFastEMA_M1, hSlowEMA_M1, hTrendEMA_M1, hRSI_M1, hATR_M1,
      hORB_EmaFast, hORB_EmaSlow
   };
   for(int i = 0; i < ArraySize(criticals); i++)
      if(criticals[i] == INVALID_HANDLE)
      { Alert("❌ QQ v7.0: Handle inválido #", i); return INIT_FAILED; }

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(10);
   trade.SetTypeFilling(ORDER_FILLING_FOK);

   g_dayStartBal = AccountInfoDouble(ACCOUNT_BALANCE);
   DetectCapitalMode();
   DailyReset();

   Print("✅ QQ Evolution v8.0 | Balance: $", DoubleToString(g_dayStartBal, 2),
         " | Modo: ", CapModeStr(),
         " | ORB:", InpMagicORB,
         " | Asia:", InpMagicASIA,
         " | NY:", InpMagicNY);
   return INIT_SUCCEEDED;
}

//====================================================================
//  OnDeinit
//====================================================================
void OnDeinit(const int reason)
{
   Comment("");
   int h[] = {
      hEMA50_D1, hEMA200_D1, hRSI_H1, hATR_H1,
      hBB_M5, hRSI_M5, hMFI_M5, hATR_M5,
      hFastEMA_M5, hSlowEMA_M5, hTrendEMA_M5,
      hFastEMA_M1, hSlowEMA_M1, hTrendEMA_M1, hRSI_M1, hATR_M1,
      hORB_EmaFast, hORB_EmaSlow
   };
   for(int i = 0; i < ArraySize(h); i++)
      if(h[i] != INVALID_HANDLE) IndicatorRelease(h[i]);
   ORBDeleteDrawings();
}

//====================================================================
//  DETECCIÓN DE CAPITAL EN TIEMPO REAL
//  Llamado en cada tick — capital siempre actualizado.
//====================================================================
void DetectCapitalMode()
{
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);

   // ── CAP_NANO (turbo): $1 – $14.99 — Modo agresivo para crecimiento rápido
   // Objetivo: $15 → $1000+ en días usando leverage 1:500 con compounding
   // Máxima frecuencia, filtros mínimos, target diario 35%
   if(bal < 15.0)
   {
      g_capMode        = CAP_MICRO;   // reutiliza enum MICRO
      g_riskPct        = 1.5;         // más agresivo: más lotaje calculado
      g_dailyLossUSD   = bal * 0.10;  g_dailyProfitUSD = bal * 0.35; // 35% target diario
      g_minProfitLock  = bal * 0.010; g_profitRetrace  = bal * 0.004;
      g_trailingMult   = 0.45;        // trailing muy ajustado
      g_scalperRR      = 2.5;         g_maxTradesDay   = 25; // 25 trades/día
      g_maxBarsOpen    = 25;          g_maxNegBars     = 5;  // cierra perdedores rápido
      g_partialAt1R    = 0.60;        g_partialAt2R    = 0.40;
   }
   // ── CAP_MICRO: $15 – $24.99 ──────────────────────────────────────
   // Prioridad: crecer rápido con riesgo moderado.
   else if(bal < 25.0)
   {
      g_capMode        = CAP_MICRO;
      g_riskPct        = 1.0;         // v10: más agresivo que 0.80
      g_dailyLossUSD   = bal * 0.07;  g_dailyProfitUSD = bal * 0.22; // 22% target
      g_minProfitLock  = bal * 0.015; g_profitRetrace  = bal * 0.006;
      g_trailingMult   = 0.55;
      g_scalperRR      = 2.2;         g_maxTradesDay   = 15; // v10: 15 (vs 4)
      g_maxBarsOpen    = 40;          g_maxNegBars     = 8;
      g_partialAt1R    = 0.55;        g_partialAt2R    = 0.35;
   }
   // ── CAP_SMALL: $25 – $59.99 ──────────────────────────────────────
   // Pirámide permitida solo nivel 1 y con equidad sana.
   // Multi-trade habilitado pero supervisado por equidad.
   else if(bal < 60.0)
   {
      g_capMode        = CAP_SMALL;
      g_riskPct        = 0.85;
      g_dailyLossUSD   = bal * 0.05;  g_dailyProfitUSD = bal * 0.12;
      g_minProfitLock  = bal * 0.015; g_profitRetrace  = bal * 0.006;
      g_trailingMult   = 0.75;
      g_scalperRR      = 2.0;         g_maxTradesDay   = 6;
      g_maxBarsOpen    = 70;          g_maxNegBars     = 12;
      g_partialAt1R    = 0.40;        g_partialAt2R    = 0.35;
   }
   // ── CAP_MEDIUM: $60 – $119.99 ────────────────────────────────────
   else if(bal < 120.0)
   {
      g_capMode        = CAP_MEDIUM;
      g_riskPct        = 0.80;
      g_dailyLossUSD   = bal * 0.045; g_dailyProfitUSD = bal * 0.11;
      g_minProfitLock  = bal * 0.014; g_profitRetrace  = bal * 0.006;
      g_trailingMult   = 0.90;
      g_scalperRR      = 1.8;         g_maxTradesDay   = 10;
      g_maxBarsOpen    = 100;         g_maxNegBars     = 18;
      g_partialAt1R    = 0.30;        g_partialAt2R    = 0.40;
   }
   // ── CAP_UPPER: $120 – $239.99 ────────────────────────────────────
   else if(bal < 240.0)
   {
      g_capMode        = CAP_UPPER;
      g_riskPct        = 0.75;
      g_dailyLossUSD   = bal * 0.040; g_dailyProfitUSD = bal * 0.10;
      g_minProfitLock  = bal * 0.012; g_profitRetrace  = bal * 0.005;
      g_trailingMult   = 0.95;
      g_scalperRR      = 1.8;         g_maxTradesDay   = 10;
      g_maxBarsOpen    = 110;         g_maxNegBars     = 20;
      g_partialAt1R    = 0.30;        g_partialAt2R    = 0.40;
   }
   // ── CAP_STANDARD: $240+ ──────────────────────────────────────────
   else
   {
      g_capMode        = CAP_STANDARD;
      g_riskPct        = 0.70;
      g_dailyLossUSD   = bal * 0.030; g_dailyProfitUSD = bal * 0.08;
      g_minProfitLock  = bal * 0.010; g_profitRetrace  = bal * 0.004;
      g_trailingMult   = 1.00;
      g_scalperRR      = 1.8;         g_maxTradesDay   = 12;
      g_maxBarsOpen    = 120;         g_maxNegBars     = 20;
      g_partialAt1R    = 0.30;        g_partialAt2R    = 0.40;
   }

   // ── Override de seguridad: límite manual siempre tiene prioridad ─
   double manualCap = bal * InpMaxDailyLossPct / 100.0;
   if(manualCap < g_dailyLossUSD) g_dailyLossUSD = manualCap;

   // ── Circuit breaker de equidad ───────────────────────────────────
   g_maxEquityDropUSD = bal * InpMaxEquityDropPct / 100.0;

   // ── SL cap en unidades de precio para CAP_MICRO ─────────────────
   // Garantiza que con lote mínimo la pérdida no supere InpMaxRiskPerTrade%
   // Fórmula: cap_pts = (bal * riskPct%) / (tickVal/tickSz * minLot)
   if(g_capMode == CAP_MICRO)
   {
      double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSz  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      double maxRisk = bal * InpMaxRiskPerTrade / 100.0;
      if(tickVal > 0 && tickSz > 0 && minLot > 0)
         g_microSLCapPts = maxRisk * tickSz / (tickVal * minLot);
      else
         g_microSLCapPts = 2.0;  // fallback seguro: 2 puntos
   }
   else
      g_microSLCapPts = 0;  // Sin cap duro para modos superiores
}

string CapModeStr()
{
   if(g_capMode == CAP_MICRO)    return "MICRO(<$25)";
   if(g_capMode == CAP_SMALL)    return "SMALL($25-59)";
   if(g_capMode == CAP_MEDIUM)   return "MEDIUM($60-119)";
   if(g_capMode == CAP_UPPER)    return "UPPER($120-239)";
   return "STANDARD($240+)";
}

//====================================================================
//  OnTick — Orquestador principal
//====================================================================
void OnTick()
{
   DetectCapitalMode();   // Capital actualizado antes de cualquier decisión
   CheckDayReset();
   UpdateMarketBias();

   if(!g_dayInvalid)
   {
      BuildRange();
      ValidateRange();
      SearchBreakout();
      SearchRetestEntry();
      if(InpScalperOn) RunScalperStrategy();
   }

   ManageOpenTrades();     // 10 capas para trades QQ individuales

   if(InpLondonORBOn)
   {
      RunLondonORB();
      ManageORBTrades();
   }

   if(InpAsianORBOn)
   {
      RunAsianORB();
      ManageAsianTrades();
   }

   if(InpNYSessionOn)
   {
      RunNYSession();
      ManageNYTrades();
   }

   TrackClosedTrades();
   DrawPanel();
}

//====================================================================
//  RESET DIARIO
//====================================================================
void DailyReset()
{
   g_rangeHigh     = 0;  g_rangeLow    = 0; g_rangeBars     = 0;
   g_dayInvalid    = false; g_initialized = false;
   g_triggered     = false; g_breakoutTime = 0;
   g_sesgoUp       = false; g_sesgoDn  = false;
   g_h1Up          = false; g_h1Dn     = false;
   g_tradesToday   = 0;  g_peakProfit   = 0;
   g_partial1Done  = false; g_partial2Done = false;
   g_beMoved       = false; g_enhanceDone  = false;
   g_openTradeCount= 0;
   g_winsToday     = 0;  g_lossesToday  = 0;
   g_totalWon      = 0;  g_totalLost    = 0;
   ORBDailyReset();
   NYReset();
   DetectCapitalMode();
   // Capturar equidad al inicio del día para el circuit breaker
   g_sessionStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   // Resetear filtro anti-simultáneo
   g_lastBuyTime  = 0;
   g_lastSellTime = 0;
}

void CheckDayReset()
{
   datetime day = iTime(_Symbol, PERIOD_D1, 0);
   if(day != g_lastDay)
   {
      g_dayStartBal = AccountInfoDouble(ACCOUNT_BALANCE);
      g_lastDay     = day;
      DailyReset();
   }
}

//====================================================================
//  SESGO D1/H1
//====================================================================
void UpdateMarketBias()
{
   double e50[1], e200[1];
   if(CopyBuffer(hEMA50_D1, 0,0,1,e50)   > 0 &&
      CopyBuffer(hEMA200_D1,0,0,1,e200)  > 0)
   { g_sesgoUp = (e50[0] > e200[0]); g_sesgoDn = (e50[0] < e200[0]); }

   double rH1[1];
   if(CopyBuffer(hRSI_H1,   0,0,1,rH1)   > 0)
   { g_h1Up = (rH1[0] > 53.0); g_h1Dn = (rH1[0] < 47.0); }
}

//====================================================================
//  CONSTRUCCIÓN DE RANGO QQ
//====================================================================
void BuildRange()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   if(dt.hour != InpRangeHourStart) return;
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(g_rangeHigh == 0) g_rangeHigh = ask;
   if(g_rangeLow  == 0) g_rangeLow  = bid;
   g_rangeHigh = MathMax(g_rangeHigh, ask);
   g_rangeLow  = MathMin(g_rangeLow,  bid);
   g_rangeBars++;
}

void ValidateRange()
{
   if(g_initialized) return;
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   if(dt.hour != InpRangeHourEnd || dt.min != 0) return;
   double sz = g_rangeHigh - g_rangeLow;
   g_initialized = true;
   if(g_rangeBars < 25 || sz < InpRangeMinPts || sz > InpRangeMaxPts)
      Print("⚠️ Rango QQ inválido (sz=", sz, ") | Solo Scalper activo");
}

//====================================================================
//  LECTURA INDICADORES M5
//====================================================================
bool GetIndM5(double &bbU, double &bbD, double &bbM,
              double &rsi, double &mfi, double &atr)
{
   double bU[1],bD[1],bM[1],r[1],m[1],a[1];
   if(CopyBuffer(hBB_M5,  1,0,1,bU) <=0) return false;
   if(CopyBuffer(hBB_M5,  2,0,1,bD) <=0) return false;
   if(CopyBuffer(hBB_M5,  0,0,1,bM) <=0) return false;
   if(CopyBuffer(hRSI_M5, 0,0,1,r)  <=0) return false;
   if(CopyBuffer(hMFI_M5, 0,0,1,m)  <=0) return false;
   if(CopyBuffer(hATR_M5, 0,0,1,a)  <=0) return false;
   bbU=bU[0]; bbD=bD[0]; bbM=bM[0];
   rsi=r[0];  mfi=m[0];  atr=a[0];
   g_bbMid_cached = bM[0];
   g_atr_cached   = a[0];
   return true;
}

//====================================================================
//  FILTROS DE CALIDAD QQ (8 confirmaciones)
//====================================================================
bool FilterTrendD1(bool b)
{
   // v10: NANO (<$15) bypass filtro D1 — máxima frecuencia, el M1/M5 signal es suficiente
   if(AccountInfoDouble(ACCOUNT_BALANCE) < 15.0) return true;
   if(b) return g_sesgoUp;
   // v9 SHORT contra-tendencia: si D1 es alcista pero RSI H1 está sobrecomprado → permitir short
   if(!b && InpAllowOverboughtShort)
   {
      double rH1[1];
      if(CopyBuffer(hRSI_H1, 0, 0, 1, rH1) > 0 && rH1[0] >= InpOverboughtRSIH1)
         return true;  // Short permitido: mercado sobrecomprado en H1
   }
   return g_sesgoDn;
}
bool FilterMomentumH1(bool b)
{
   // v10: NANO (<$15) bypass filtro H1 — signal M1+M5 es suficiente
   if(AccountInfoDouble(ACCOUNT_BALANCE) < 15.0) return true;
   // CAP_MICRO: versión menos estricta — permite operar si H1 no está en contra explícita.
   if(g_capMode == CAP_MICRO)
      return b ? (!g_h1Dn) : (!g_h1Up);
   // v9 SHORT contra-tendencia: si RSI H1 >= umbral overbought, momentum favorece short
   if(!b && InpAllowOverboughtShort)
   {
      double rH1[1];
      if(CopyBuffer(hRSI_H1, 0, 0, 1, rH1) > 0 && rH1[0] >= InpOverboughtRSIH1)
         return true;
   }
   return b ? g_h1Up : g_h1Dn;
}
bool FilterRSI(double r, bool b)   { return b?(r>48&&r<72):(r<52&&r>28); }
bool FilterBBT(double c,double m,bool b) { return b?(c>m):(c<m); }
bool FilterMFI(double f,bool b)    { if(g_capMode==CAP_MICRO) return true; return b?(f>48):(f<52); }
bool FilterGold(double r,bool b)   { return b?(r>47||g_sesgoUp):(!g_sesgoUp&&r<50); }
bool FilterATR(double a)           { return a >= ((g_capMode==CAP_MICRO)?0.5:0.8)*_Point*100; }
bool FilterSpread()
{
   double sp=(double)SymbolInfoInteger(_Symbol,SYMBOL_SPREAD);
   return sp <= (g_capMode==CAP_MICRO?30.0:InpMaxSpread);
}

int SignalScore(bool b,double c,double m,double r,double f,double a)
{
   int s=0;
   if(FilterTrendD1(b))     s++;
   if(FilterMomentumH1(b))  s++;
   if(FilterRSI(r,b))       s++;
   if(FilterBBT(c,m,b))     s++;
   if(FilterMFI(f,b))       s++;
   if(FilterGold(r,b))      s++;
   if(FilterATR(a))         s++;
   if(FilterSpread())       s++;
   return s;
}
int MinScore(bool vetoRelaxed=false)
{
   // v10: NANO (<$15): score mínimo 4 (D1+H1 siempre true → 2pts garantizados, necesita 2 más)
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   int base = (bal < 15.0) ? 4 : (g_capMode <= CAP_SMALL) ? 5 : 6;
   return vetoRelaxed ? base + 1 : base;  // v10: penalidad veto reducida a +1 para NANO
}

//====================================================================
//  FILTRO DE NOTICIAS — Bloquea entradas en ventanas de alto impacto
//====================================================================
bool IsNewsTime()
{
   if(!InpNewsFilterOn) return false;
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   int m = dt.hour * 60 + dt.min;
   // US data releases: 13:25-13:45 GMT
   if(m >= 13*60+25 && m < 13*60+45) return true;
   // FOMC/Fed: 18:55-19:15 GMT
   if(m >= 18*60+55 && m < 19*60+15) return true;
   return false;
}

//====================================================================
//  TP DINÁMICO — Multiplica TP en días de alta volatilidad
//  Si ATR H1 actual > 2× promedio de 20 periodos → TP × 1.5
//====================================================================
double GetDynamicTPMult()
{
   double atrBuf[20];
   if(CopyBuffer(hATR_H1, 0, 0, 20, atrBuf) < 20) return 1.0;
   double avg = 0;
   for(int i = 1; i < 20; i++) avg += atrBuf[i];
   avg /= 19.0;
   if(avg <= 0) return 1.0;
   return (atrBuf[0] > avg * 2.0) ? 1.5 : 1.0;
}

//====================================================================
//  QQ ENHANCEMENT — Scale-in a 1R (reemplaza pirámide/multi-trade)
//  Cuando el trade maestro llega a 1R en ganancia:
//    1. Abre 1 trade adicional mismo sentido, SL=entry maestro, TP=mismo TP
//    2. Mueve SL del maestro a break-even
//  Riesgo adicional: 50% del lote del maestro. Solo 1 enhancement por ciclo.
//====================================================================
void TryQQEnhancement(ulong ticket, bool isBuy,
                       double openP, double curSL, double curTP)
{
   if(!InpEnhancementOn) return;
   if(g_enhanceDone) return;

   // Buscar el trade tracker
   int idx = FindTradeTracker(ticket);
   if(idx >= 0 && g_openTrades[idx].enhanceDone) return;

   // No abrir si ya hay otro trade activo además del maestro
   if(CountOpenPositions() > 1) return;

   // Seguridad de equidad
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq < bal * 0.95) return;  // Equidad bajo 95% → no escalar

   if(!PositionSelectByTicket(ticket)) return;
   double masterVol = PositionGetDouble(POSITION_VOLUME);
   double curP = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                       : SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // SL del enhancement = entrada del maestro (trade gratis si el maestro está en BE)
   double enhSL = isBuy ? openP - _Point : openP + _Point;
   double enhTP = curTP;

   if(!ValidateTradeRisk(curP, enhSL, "ENHANCE")) return;
   if(!ValidateMinRR(curP, enhSL, enhTP, "ENHANCE")) return;

   double enhLot = NormLot(masterVol * 0.50);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(enhLot < minLot) enhLot = minLot;

   bool ok = isBuy ? trade.Buy(enhLot, _Symbol, curP, enhSL, enhTP)
                   : trade.Sell(enhLot, _Symbol, curP, enhSL, enhTP);

   if(ok)
   {
      ulong enhTicket = trade.ResultOrder();
      RegisterTrade(enhTicket);
      g_enhanceDone = true;
      g_tradesToday++;
      if(idx >= 0) g_openTrades[idx].enhanceDone = true;
      // Mover SL del maestro a break-even
      if(!g_beMoved)
      {
         double nSL = isBuy ? openP + _Point : openP - _Point;
         trade.PositionModify(ticket, nSL, curTP);
         g_beMoved = true;
      }
      Print("🚀 QQ Enhancement @", DoubleToString(curP,2),
            " Lot=", enhLot, " SL=", DoubleToString(enhSL,2),
            " TP=", DoubleToString(enhTP,2));
   }
}

//====================================================================
//  SMART RECOVERY — Trade de recuperación a -1R (opcional, default OFF)
//  Abre 1 trade adicional con lote reducido cuando pérdida > 1R.
//  NO es martingala: no aumenta el lote, no repite.
//====================================================================
void TrySmartRecovery(ulong ticket, bool isBuy, double openP, double curSL, double curTP)
{
   if(!InpSmartRecoveryOn) return;
   int idx = FindTradeTracker(ticket);
   if(idx >= 0 && g_openTrades[idx].recoveryDone) return;
   if(CountOpenPositions() > 1) return;

   double curP = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                       : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double recLot = NormLot(CalcLot(MathAbs(curP - curSL), 0.40));
   if(recLot <= 0) return;

   // TP del recovery = entrada del trade original (cierra ambos en el maestro)
   double recTP = isBuy ? openP + _Point : openP - _Point;
   if(!ValidateTradeRisk(curP, curSL, "RECOVERY")) return;

   bool ok = isBuy ? trade.Buy(recLot, _Symbol, curP, curSL, recTP)
                   : trade.Sell(recLot, _Symbol, curP, curSL, recTP);

   if(ok)
   {
      RegisterTrade(trade.ResultOrder());
      g_tradesToday++;
      if(idx >= 0) g_openTrades[idx].recoveryDone = true;
      Print("🔄 Smart Recovery @", DoubleToString(curP,2),
            " Lot=", recLot, " TP=", DoubleToString(recTP,2));
   }
}

//====================================================================
//  CÁLCULO DE LOTE
//====================================================================
double CalcLot(double slPts, double riskMult)
{
   double riskPct = g_riskPct * riskMult;
   double bal     = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk    = bal * (riskPct / 100.0);
   double tv      = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double ts      = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(slPts <= 0 || tv <= 0 || ts <= 0) return NormLot(minLot);

   double slMoney = slPts / ts * tv;
   double lot     = (slMoney > 0) ? risk / slMoney : minLot;

   // MICRO/NANO: usar el mayor lote posible dentro del margen disponible
   if(g_capMode == CAP_MICRO)
   {
      double free    = AccountInfoDouble(ACCOUNT_FREEMARGIN);
      double mReq    = SymbolInfoDouble(_Symbol, SYMBOL_MARGIN_INITIAL); // por 1.0 lot
      double pctUse  = (bal < 15.0) ? 0.35 : 0.25; // NANO usa 35% margen, MICRO usa 25%
      double maxMgn  = (mReq > 0) ? NormLot(free * pctUse / mReq) : minLot;
      lot = MathMax(minLot, MathMin(lot, MathMax(maxMgn, minLot)));
   }
   // Cuentas SMALL: máximo 3x lote mínimo por trade base
   else if(g_capMode == CAP_SMALL)
      lot = MathMin(lot, minLot * 3.0);

   return NormLot(lot);
}

void CalcSLTP(bool isBuy, double entry, double atr,
              double &sl, double &tp, double rrMult=1.0, bool useFixed=false)
{
   double slD, tpD;

   // v9: modo TP/SL fijos por sesión (estilo QQ [T5/S3]) — mayor win rate por precisión
   if(useFixed && InpUseFixedScalperLevels)
   {
      slD = InpFixedScalperSLPts * _Point * 10;
      tpD = InpFixedScalperTPPts * _Point * 10;
   }
   else
   {
      slD = atr * InpATR_SL_Mult;
      double dynMult = GetDynamicTPMult();
      tpD = atr * InpATR_TP_Mult * rrMult * dynMult;

      if(g_capMode == CAP_MICRO)
      {
         slD *= 0.75;
         if(g_microSLCapPts > 0 && slD > g_microSLCapPts)
            slD = g_microSLCapPts;
         tpD = slD * (InpATR_TP_Mult / InpATR_SL_Mult) * rrMult;
      }
      else if(g_capMode == CAP_SMALL)
         slD *= 0.90;
   }

   sl = isBuy ? entry - slD : entry + slD;
   tp = isBuy ? entry + tpD : entry - tpD;
}

//====================================================================
//  VETO D1 TEMPORAL — Máx InpD1VetoMaxMin minutos de bloqueo.
//  Después del timeout: permite con MinScore+2 (score más estricto).
//  Nunca bloquea un día entero. Resetea cuando la condición D1 desaparece.
//====================================================================
bool IsD1VetoClear(bool isBuy)
{
   bool isAdverse = isBuy ? g_sesgoDn : g_sesgoUp;

   if(!isAdverse)
   {
      // Condición D1 favorable o neutral — resetear timer
      if(isBuy)  { g_d1VetoLongFiredAt  = 0; g_d1VetoRelaxedLong  = false; }
      else       { g_d1VetoShortFiredAt = 0; g_d1VetoRelaxedShort = false; }
      return true;
   }

   // D1 adverso — aplicar veto temporal
   datetime &fireTime = isBuy ? g_d1VetoLongFiredAt  : g_d1VetoShortFiredAt;
   bool     &relaxed  = isBuy ? g_d1VetoRelaxedLong  : g_d1VetoRelaxedShort;

   if(fireTime == 0) fireTime = TimeCurrent();
   int elapsedMin = (int)(TimeCurrent() - fireTime) / 60;

   if(elapsedMin < InpD1VetoMaxMin)
   {
      relaxed = false;
      return false;   // Bloqueo duro: aún dentro del timeout
   }

   // Timeout expirado → permite con score estricto (+2 en MinScore)
   relaxed = true;
   return true;
}

//====================================================================
//  FILTRO ANTI-SIMULTÁNEO — Evita múltiples trades en la misma dirección
//  dentro de una ventana de tiempo (cooldown). Previene el clustering de
//  entradas que infla exposición sin añadir valor informacional.
//====================================================================
bool FilterAntiSimultaneous(bool isBuy)
{
   // v9: cooldown configurable via InpScalperCooldownSec (default 120s vs 300s anterior)
   int cooldownSecs = InpScalperCooldownSec;
   datetime lastTime = isBuy ? g_lastBuyTime : g_lastSellTime;
   if(lastTime > 0 && (int)(TimeCurrent() - lastTime) < cooldownSecs)
   {
      Print("⏸️ Anti-simultáneo [", (isBuy ? "BUY" : "SELL"), "]: ",
            (int)(TimeCurrent() - lastTime), "s < cooldown ", cooldownSecs, "s");
      return false;
   }
   return true;
}

//====================================================================
//  VALIDACIÓN DE RR MÍNIMO REAL
//  Verifica que la distancia TP/SL cumple el ratio mínimo configurado.
//  Previene abrir trades con RR real negativo o insuficiente causado
//  por SL capados que no tienen TP proporcionalmente ajustado.
//====================================================================
// v9: Verificar margen libre antes de abrir — evita el margin call del 99%
bool CheckFreeMargin(string context="")
{
   double equity     = AccountInfoDouble(ACCOUNT_EQUITY);
   double margin     = AccountInfoDouble(ACCOUNT_MARGIN);
   double freeMargin = AccountInfoDouble(ACCOUNT_FREEMARGIN);
   if(equity <= 0) return true;
   double freeMarginPct = (freeMargin / equity) * 100.0;
   if(freeMarginPct < InpMinFreeMarginPct)
   {
      Print("⛔ [", context, "] Margen libre insuficiente: ",
            DoubleToString(freeMarginPct, 1), "% < mínimo ",
            DoubleToString(InpMinFreeMarginPct, 1), "% | Equity=$",
            DoubleToString(equity, 2), " Margin=$", DoubleToString(margin, 2));
      return false;
   }
   return true;
}

bool ValidateMinRR(double entry, double sl, double tp, string context="")
{
   double slDist = MathAbs(entry - sl);
   double tpDist = MathAbs(entry - tp);
   if(slDist <= 0 || tpDist <= 0)
   {
      Print("⛔ [", context, "] RR inválido: SL=", DoubleToString(slDist,4),
            " TP=", DoubleToString(tpDist,4));
      return false;
   }
   double rr = tpDist / slDist;
   if(rr < InpMinRR)
   {
      Print("⛔ [", context, "] RR insuficiente: ", DoubleToString(rr,2),
            " < mínimo ", DoubleToString(InpMinRR,2),
            " | SL=", DoubleToString(slDist,2), " TP=", DoubleToString(tpDist,2));
      return false;
   }
   return true;
}

//====================================================================
//  VALIDACIÓN DE RIESGO REAL ANTES DE ABRIR UN TRADE
//
//  Lógica en 3 niveles:
//  1. NORMAL   : minLotLoss <= maxAllowed * (1 + tolerancia FP)  → permitido
//  2. EMERGENCIA: minLotLoss excede el límite pero estamos en
//                 CAP_MICRO o balance < umbral de emergencia     → permitido
//                 con lote mínimo + log claro en el journal
//  3. BLOQUEADO: balance suficiente pero el SL está tan lejos que
//                incluso 0.01 lot supera el máximo permitido      → rechazado
//
//  Razón de los 3 niveles: con $8-10 y XAUUSD el lote mínimo
//  (0.01) siempre arriesga ~$1+, pero 12% de $8 = $0.96.
//  Sin modo emergencia el bot quedaría bloqueado para siempre.
//====================================================================
bool ValidateTradeRisk(double entry, double sl, string context="")
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSz  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

   if(tickSz <= 0 || tickVal <= 0 || minLot <= 0 || balance <= 0) return true;

   double slPts       = MathAbs(entry - sl);
   if(slPts <= 0) return true;

   double lossPerUnit = slPts / tickSz * tickVal;   // pérdida en $ por 1 lote
   double minLotLoss  = lossPerUnit * minLot;        // pérdida con el lote mínimo
   double maxAllowed  = balance * InpMaxRiskPerTrade / 100.0;

   // ── Nivel 1: NORMAL (con tolerancia de 2% para errores de punto flotante) ──
   if(minLotLoss <= maxAllowed * 1.02)
      return true;

   // ── Nivel 2: MODO EMERGENCIA ─────────────────────────────────────────────
   // Activado cuando el balance es tan bajo que ningún SL pasa la validación
   // normal. Priorizamos supervivencia sobre el límite de riesgo estricto.
   // Umbral: CAP_MICRO O balance < 2× el costo de 1 minLot
   bool inEmergency = (g_capMode == CAP_MICRO) ||
                      (balance < minLotLoss * 2.0);

   if(inEmergency)
   {
      // Máximo absoluto de seguridad: si minLotLoss > 50% del balance
      // incluso el modo emergencia se niega (SL absurdamente amplio)
      if(minLotLoss > balance * 0.50)
      {
         Print("⛔ [", context, "] BLOQUEADO incluso en emergencia: SL demasiado amplio. "
               "Riesgo mínimo $", DoubleToString(minLotLoss, 2),
               " > 50% del balance $", DoubleToString(balance, 2));
         return false;
      }
      Print("⚠️ [", context, "] MODO EMERGENCIA activado – operando con lote mínimo. "
            "Riesgo $", DoubleToString(minLotLoss, 2),
            " > límite ideal $", DoubleToString(maxAllowed, 2),
            " (", DoubleToString(InpMaxRiskPerTrade, 1), "% de $",
            DoubleToString(balance, 2), "). "
            "Capital bajo – priorizando recuperación.");
      return true;  // permitido en emergencia
   }

   // ── Nivel 3: BLOQUEADO (balance suficiente, SL demasiado amplio) ─────────
   Print("⛔ [", context, "] Trade bloqueado: riesgo mínimo $",
         DoubleToString(minLotLoss, 2), " > máx permitido $",
         DoubleToString(maxAllowed, 2), " [",
         DoubleToString(InpMaxRiskPerTrade, 1), "% de $",
         DoubleToString(balance, 2), "] – ajusta InpMaxRiskPerTrade o SL.");
   return false;
}

//====================================================================
//  BREAKOUT QQ
//====================================================================
void SearchBreakout()
{
   if(g_triggered || !g_initialized) return;
   if(g_rangeHigh==0||g_rangeLow==0) return;
   if(g_tradesToday >= g_maxTradesDay) return;
   if(IsNewsTime()) return;
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   if(dt.hour < InpRangeHourEnd || dt.hour >= InpBreakoutHourEnd) return;
   double dayPnL = AccountInfoDouble(ACCOUNT_BALANCE) - g_dayStartBal;
   if(dayPnL<-g_dailyLossUSD || dayPnL>g_dailyProfitUSD) return;

   double close=iClose(_Symbol,PERIOD_M5,0);
   double bbU,bbD,bbM,rsi,mfi,atr;
   if(!GetIndM5(bbU,bbD,bbM,rsi,mfi,atr)) return;
   double off = InpBreakoutOffset*_Point*10;

   if(close>(g_rangeHigh+off))
   {
      if(!IsD1VetoClear(true)) return;
      if(!FilterAntiSimultaneous(true)) return;
      if(SignalScore(true,close,bbM,rsi,mfi,atr) < MinScore(g_d1VetoRelaxedLong)) return;
      if(!CheckFreeMargin("BRK-LONG")) return;
      double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK), sl, tp;
      CalcSLTP(true,ask,atr,sl,tp);
      if(!ValidateTradeRisk(ask,sl,"BRK-LONG")) return;
      if(!ValidateMinRR(ask,sl,tp,"BRK-LONG"))  return;
      double lot=CalcLot(ask-sl,1.0);
      if(trade.Buy(lot,_Symbol,ask,sl,tp))
      {
         ulong t=trade.ResultOrder();
         g_triggered=true; g_tradesToday++;
         g_partial1Done=false; g_partial2Done=false; g_beMoved=false;
         g_enhanceDone=false;
         g_breakoutTime=TimeCurrent();
         g_lastBuyTime=TimeCurrent();
         RegisterTrade(t);
         Print("🟢 BREAKOUT LONG @",ask," SL:",sl," TP:",tp," Lot:",lot);
      }
   }
   else if(close<(g_rangeLow-off))
   {
      if(!IsD1VetoClear(false)) return;
      if(!FilterAntiSimultaneous(false)) return;
      if(SignalScore(false,close,bbM,rsi,mfi,atr) < MinScore(g_d1VetoRelaxedShort)) return;
      if(!CheckFreeMargin("BRK-SHORT")) return;
      double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID), sl, tp;
      CalcSLTP(false,bid,atr,sl,tp);
      if(!ValidateTradeRisk(bid,sl,"BRK-SHORT")) return;
      if(!ValidateMinRR(bid,sl,tp,"BRK-SHORT"))  return;
      double lot=CalcLot(sl-bid,1.0);
      if(trade.Sell(lot,_Symbol,bid,sl,tp))
      {
         ulong t=trade.ResultOrder();
         g_triggered=true; g_tradesToday++;
         g_partial1Done=false; g_partial2Done=false; g_beMoved=false;
         g_enhanceDone=false;
         g_breakoutTime=TimeCurrent();
         g_lastSellTime=TimeCurrent();
         RegisterTrade(t);
         Print("🔴 BREAKOUT SHORT @",bid," SL:",sl," TP:",tp," Lot:",lot);
      }
   }
}

//====================================================================
//  RETEST QQ
//====================================================================
void SearchRetestEntry()
{
   if(!g_triggered || g_tradesToday>=g_maxTradesDay) return;
   if(CountOpenPositions()>0) return;
   if(IsNewsTime()) return;
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   if(dt.hour>=InpBreakoutHourEnd) return;
   if(g_breakoutTime>0 &&
      (int)((TimeCurrent()-g_breakoutTime)/PeriodSeconds(PERIOD_M5))>30) return;

   double close=iClose(_Symbol,PERIOD_M5,0);
   double bbU,bbD,bbM,rsi,mfi,atr;
   if(!GetIndM5(bbU,bbD,bbM,rsi,mfi,atr)) return;
   double zone=0.50*_Point*10;

   if(g_sesgoUp && g_h1Up &&
      close<=g_rangeHigh+zone && close>=g_rangeHigh-zone)
   {
      if(!IsD1VetoClear(true)) return;
      if(!FilterAntiSimultaneous(true)) return;
      if(SignalScore(true,close,bbM,rsi,mfi,atr) < MinScore(g_d1VetoRelaxedLong)) return;
      if(!CheckFreeMargin("RET-LONG")) return;
      double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK), sl, tp;
      CalcSLTP(true,ask,atr,sl,tp);
      if(!ValidateTradeRisk(ask,sl,"RET-LONG")) return;
      if(!ValidateMinRR(ask,sl,tp,"RET-LONG"))  return;
      double lot=CalcLot(ask-sl,0.70);
      if(trade.Buy(lot,_Symbol,ask,sl,tp))
      {
         ulong t=trade.ResultOrder();
         g_tradesToday++; g_enhanceDone=false;
         g_lastBuyTime=TimeCurrent();
         RegisterTrade(t);
         Print("🟢 RETEST LONG @",ask," Lot:",lot);
      }
   }
   else if(g_sesgoDn && g_h1Dn &&
           close>=g_rangeLow-zone && close<=g_rangeLow+zone)
   {
      if(!IsD1VetoClear(false)) return;
      if(!FilterAntiSimultaneous(false)) return;
      if(SignalScore(false,close,bbM,rsi,mfi,atr) < MinScore(g_d1VetoRelaxedShort)) return;
      double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID), sl, tp;
      CalcSLTP(false,bid,atr,sl,tp);
      if(!ValidateTradeRisk(bid,sl,"RET-SHORT")) return;
      if(!ValidateMinRR(bid,sl,tp,"RET-SHORT"))  return;
      double lot=CalcLot(sl-bid,0.70);
      if(trade.Sell(lot,_Symbol,bid,sl,tp))
      {
         ulong t=trade.ResultOrder();
         g_tradesToday++; g_enhanceDone=false;
         g_lastSellTime=TimeCurrent();
         RegisterTrade(t);
         Print("🔴 RETEST SHORT @",bid," Lot:",lot);
      }
   }
}

//====================================================================
//  FILTRO DE CALIDAD PARA EMA SCALPER
//  Criterios específicos para el scalper, más estrictos que SignalScore.
//  Retorna false si las condiciones de mercado no son aptas para scalping.
//====================================================================
bool FilterScalperQuality(bool isBuy, double fastEMA, double slowEMA,
                           double rsi, double mfi, double atr,
                           double close, double bbU, double bbD, double bbM)
{
   // 1. Separación mínima entre EMA rápida y lenta — filtra crossovers de ruido
   //    Si el gap es menor a X puntos, el mercado está choppy o en compresión
   double emaGap = MathAbs(fastEMA - slowEMA);
   if(emaGap < InpScalperEMAGap * _Point * 10)
   {
      Print("⚡ Scalper bloqueado: EMA gap=",DoubleToString(emaGap/_Point/10,2),
            "pts < mín ",InpScalperEMAGap," (mercado choppy)");
      return false;
   }

   // 2. ATR mínimo absoluto — sin volatilidad no hay scalping rentable
   double atrPts = atr / (_Point * 10);
   if(atrPts < InpScalperMinATRPts)
   {
      Print("⚡ Scalper bloqueado: ATR=",DoubleToString(atrPts,1),"pts < mín ",InpScalperMinATRPts);
      return false;
   }

   // 3. RSI y MFI estrictos para el scalper (aplica siempre, incluso en MICRO)
   //    El filtro general (FilterMFI) bypasea MFI para MICRO — aquí lo aplicamos
   if(isBuy)
   {
      if(rsi < InpScalperRSIBuy)
      { Print("⚡ Scalper BUY: RSI=",rsi," < ",InpScalperRSIBuy); return false; }
      if(mfi < 50.0)
      { Print("⚡ Scalper BUY: MFI=",mfi," < 50"); return false; }
   }
   else
   {
      if(rsi > InpScalperRSISell)
      { Print("⚡ Scalper SELL: RSI=",rsi," > ",InpScalperRSISell); return false; }
      if(mfi > 50.0)
      { Print("⚡ Scalper SELL: MFI=",mfi," > 50"); return false; }
   }

   // 4. Posición en BB — evitar entrar en el extremo opuesto de las bandas
   //    BUY cuando precio ya está en el 85%+ del rango BB = probable reversión
   //    SELL cuando precio está en el 15%- del rango BB = probable rebote
   double bbRange = bbU - bbD;
   if(bbRange > _Point)
   {
      double posInBB = (close - bbD) / bbRange;
      if(isBuy  && posInBB > InpScalperBBMaxPos)
      { Print("⚡ Scalper BUY bloqueado: precio en ",DoubleToString(posInBB*100,0),"% BB (overbought)"); return false; }
      if(!isBuy && posInBB < InpScalperBBMinPos)
      { Print("⚡ Scalper SELL bloqueado: precio en ",DoubleToString(posInBB*100,0),"% BB (oversold)"); return false; }
   }

   return true;
}

//====================================================================
//  EMA SCALPER QQ
//====================================================================
void RunScalperStrategy()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   if(dt.hour<InpScalperHourStart||dt.hour>=InpScalperHourEnd) return;
   // v9: permite hasta InpScalperMaxPos posiciones simultáneas (antes bloqueaba si >0)
   int openNow = CountOpenPositions();
   if(g_tradesToday>=g_maxTradesDay||openNow>=InpScalperMaxPos||!FilterSpread()) return;
   double dayPnL=AccountInfoDouble(ACCOUNT_BALANCE)-g_dayStartBal;
   if(dayPnL<-g_dailyLossUSD||dayPnL>g_dailyProfitUSD) return;
   // v10: NANO/MICRO usan barra M1 (5x más señales/día); resto usa M5
   bool    isNano  = (AccountInfoDouble(ACCOUNT_BALANCE) < 25.0);
   ENUM_TIMEFRAMES tfBar = isNano ? PERIOD_M1 : PERIOD_M5;
   datetime bar    = iTime(_Symbol, tfBar, 0);
   if(isNano) { if(bar == g_lastBarM1) return; }
   else        { if(bar == g_lastBarM5) return; }

   double fM5[3],sM5[3],tM5[3];
   ArraySetAsSeries(fM5,true); ArraySetAsSeries(sM5,true); ArraySetAsSeries(tM5,true);
   if(CopyBuffer(hFastEMA_M5, 0,0,3,fM5) <=0) return;
   if(CopyBuffer(hSlowEMA_M5, 0,0,3,sM5) <=0) return;
   if(CopyBuffer(hTrendEMA_M5,0,0,3,tM5) <=0) return;

   double fM1[2],sM1[2],tM1[2];
   ArraySetAsSeries(fM1,true); ArraySetAsSeries(sM1,true); ArraySetAsSeries(tM1,true);
   if(CopyBuffer(hFastEMA_M1, 0,0,2,fM1) <=0) return;
   if(CopyBuffer(hSlowEMA_M1, 0,0,2,sM1) <=0) return;
   if(CopyBuffer(hTrendEMA_M1,0,0,2,tM1) <=0) return;

   double bbU,bbD,bbM,rsi,mfi,atr;
   if(!GetIndM5(bbU,bbD,bbM,rsi,mfi,atr)||atr<=0) return;
   double close=iClose(_Symbol,PERIOD_M5,0);

   bool cUpM5=(fM5[0]>sM5[0])&&(fM5[1]<=sM5[1]);
   bool cDnM5=(fM5[0]<sM5[0])&&(fM5[1]>=sM5[1]);
   bool tUpM5=(fM5[0]>tM5[0]), tDnM5=(fM5[0]<tM5[0]);
   bool aUpM1=(fM1[0]>sM1[0]&&fM1[0]>tM1[0]);
   bool aDnM1=(fM1[0]<sM1[0]&&fM1[0]<tM1[0]);

   if(IsNewsTime()) return;
   // v10: En NANO/MICRO usamos señal M1 (EMA crossover en M1) como trigger primario
   bool useM1signal = isNano;
   bool cUpFinal = useM1signal ? (fM1[0]>sM1[0] && fM1[1]<=sM1[1] && fM1[0]>tM1[0]) : (cUpM5&&tUpM5&&aUpM1);
   bool cDnFinal = useM1signal ? (fM1[0]<sM1[0] && fM1[1]>=sM1[1] && fM1[0]<tM1[0]) : (cDnM5&&tDnM5&&aDnM1);

   if(cUpFinal && SignalScore(true,close,bbM,rsi,mfi,atr)>=MinScore(g_d1VetoRelaxedLong))
   {
      if(!IsD1VetoClear(true)) return;
      if(!FilterAntiSimultaneous(true)) return;
      if(!FilterScalperQuality(true,fM5[0],sM5[0],rsi,mfi,atr,close,bbU,bbD,bbM)) return;
      // v10: actualizar tracker correcto según modo
      if(isNano) g_lastBarM1=bar; else g_lastBarM5=bar;
      double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK), sl,tp;
      CalcSLTP(true,ask,atr,sl,tp,g_scalperRR/InpRR,true);
      if(!ValidateTradeRisk(ask,sl,"SCA-BUY")) return;
      if(!ValidateMinRR(ask,sl,tp,"SCA-BUY"))  return;
      double lot=CalcLot(ask-sl,0.80);
      string tagBuy=StringFormat("QQv10[T%.0fS%.0f]",InpFixedScalperTPPts,InpFixedScalperSLPts);
      if(trade.Buy(lot,_Symbol,ask,sl,tp,tagBuy))
      {
         ulong t=trade.ResultOrder();
         g_tradesToday++; g_enhanceDone=false;
         g_lastBuyTime=TimeCurrent();
         RegisterTrade(t);
         Print("⚡ SCALPER BUY @",ask," Lot:",lot," SL:",sl," TP:",tp,
               " RSI=",DoubleToString(rsi,1)," M1=",useM1signal?"M1":"M5");
      }
   }
   else if(cDnFinal && SignalScore(false,close,bbM,rsi,mfi,atr)>=MinScore(g_d1VetoRelaxedShort))
   {
      if(!IsD1VetoClear(false)) return;
      if(!FilterAntiSimultaneous(false)) return;
      if(!FilterScalperQuality(false,fM5[0],sM5[0],rsi,mfi,atr,close,bbU,bbD,bbM)) return;
      if(isNano) g_lastBarM1=bar; else g_lastBarM5=bar;
      double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID), sl,tp;
      CalcSLTP(false,bid,atr,sl,tp,g_scalperRR/InpRR,true);
      if(!ValidateTradeRisk(bid,sl,"SCA-SELL")) return;
      if(!ValidateMinRR(bid,sl,tp,"SCA-SELL"))  return;
      double lot=CalcLot(sl-bid,0.80);
      string tagSell=StringFormat("QQv10[T%.0fS%.0f]",InpFixedScalperTPPts,InpFixedScalperSLPts);
      if(trade.Sell(lot,_Symbol,bid,sl,tp,tagSell))
      {
         ulong t=trade.ResultOrder();
         g_tradesToday++; g_enhanceDone=false;
         g_lastSellTime=TimeCurrent();
         RegisterTrade(t);
         Print("⚡ SCALPER SELL @",bid," Lot:",lot," SL:",sl," TP:",tp,
               " RSI=",DoubleToString(rsi,1)," MFI=",DoubleToString(mfi,1));
      }
   }
}

//====================================================================
//  GESTIÓN QQ — SISTEMA 10 CAPAS
//====================================================================
void ManageOpenTrades()
{
   double dayPnL=AccountInfoDouble(ACCOUNT_BALANCE)-g_dayStartBal;

   // Capa 0: Stop/Target diario global
   if(dayPnL>=g_dailyProfitUSD)
   { CloseAllMagic(); CloseAllORB("Target diario"); g_dayInvalid=true;
     Print("🎯 TARGET DIARIO $",dayPnL); return; }
   if(dayPnL<=-g_dailyLossUSD)
   { CloseAllMagic(); CloseAllORB("Stop diario"); g_dayInvalid=true;
     Print("🛑 STOP DIARIO $",dayPnL); return; }

   // Capa 0B: Circuit breaker de equidad — cierra todo si la equidad
   // cae más de InpMaxEquityDropPct% respecto al balance actual.
   // Crítico para cuentas micro donde el flotante puede destruir la cuenta.
   {
      double balance  = AccountInfoDouble(ACCOUNT_BALANCE);
      double equity   = AccountInfoDouble(ACCOUNT_EQUITY);
      double eqDrop   = balance - equity;
      if(g_maxEquityDropUSD > 0 && eqDrop >= g_maxEquityDropUSD && equity < balance)
      {
         CloseAllMagic();
         CloseAllORB("EQ-Breaker");
         g_dayInvalid = true;
         Print("🚨 EQUITY CIRCUIT BREAKER: Bal=$", DoubleToString(balance,2),
               " Eq=$", DoubleToString(equity,2),
               " Caída=$", DoubleToString(eqDrop,2),
               " (", DoubleToString(eqDrop/balance*100.0,1), "%) > umbral $",
               DoubleToString(g_maxEquityDropUSD,2));
         return;
      }
   }

   double rsiM5[1],fM5[1],sM5[1],tM5[1],atrM5[1];
   bool hR=(CopyBuffer(hRSI_M5,    0,0,1,rsiM5)>0);
   bool hE=(CopyBuffer(hFastEMA_M5,0,0,1,fM5)  >0 &&
            CopyBuffer(hSlowEMA_M5,0,0,1,sM5)  >0 &&
            CopyBuffer(hTrendEMA_M5,0,0,1,tM5) >0);
   bool hA=(CopyBuffer(hATR_M5,    0,0,1,atrM5)>0);
   if(hA&&atrM5[0]>0) g_atr_cached=atrM5[0];

   double totalPnL=0; int count=0;

   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;

      double profit   =PositionGetDouble(POSITION_PROFIT);
      double openP    =PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL    =PositionGetDouble(POSITION_SL);
      double curTP    =PositionGetDouble(POSITION_TP);
      double vol      =PositionGetDouble(POSITION_VOLUME);
      bool   isBuy    =(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
      datetime tOpen  =(datetime)PositionGetInteger(POSITION_TIME);
      double curP     =isBuy?SymbolInfoDouble(_Symbol,SYMBOL_BID)
                            :SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      totalPnL+=profit; count++;

      // Barrera mínima: no gestionar salida hasta InpMinBarsBeforeExit barras M1
      int barsM1=(int)((TimeCurrent()-tOpen)/PeriodSeconds(PERIOD_M1));
      if(barsM1 < InpMinBarsBeforeExit) continue;

      // Enhancement QQ a 1R profit
      double slD0=MathAbs(openP-curSL);
      double mR0=(slD0>0)?MathAbs(curP-openP)/slD0:0;
      if(mR0>=1.0 && profit>0)
         TryQQEnhancement(ticket,isBuy,openP,curSL,curTP);
      // Smart Recovery a -1R flotante
      if(mR0>=1.0 && profit<0)
         TrySmartRecovery(ticket,isBuy,openP,curSL,curTP);

      // Capa 1: Tiempo + ganancia
      if(barsM1>=g_maxBarsOpen&&profit>0)
      { trade.PositionClose(ticket); RemoveTradeTracker(ticket);
        Print("⏱️ Cierre tiempo(",barsM1,"b): $",profit); continue; }

      // Capa 2: Tendencia+RSI adversos en pérdida
      // Requisito adicional: la posición debe llevar al menos 0.20R en contra
      // para filtrar el ruido inicial normal de cualquier trade
      if(InpSmartExitOn && profit < 0)
      {
         bool tW = hE && (isBuy ? (curP < tM5[0]) : (curP > tM5[0]));
         bool mW = hR && (isBuy ? (rsiM5[0] < 38)  : (rsiM5[0] > 62));
         if(tW && mW)
         {
            double slDist = MathAbs(openP - curSL);
            double mR     = (slDist > 0) ? MathAbs(curP - openP) / slDist : 0;
            if(mR >= 0.20)
            {
               trade.PositionClose(ticket); RemoveTradeTracker(ticket);
               Print("🧠 Smart exit pérdida @", DoubleToString(mR,2), "R: $", profit);
               continue;
            }
         }
      }

      // Capa 3: Pérdida de momentum — solo cerrar si ganancia ≥ 0.30R
      // Evita cierres prematuros en $0.02 que inflan winrate sin valor real
      if(InpMomentumExitOn && profit > 0 && hE)
      {
         bool mL = isBuy ? (fM5[0] < sM5[0]) : (fM5[0] > sM5[0]);
         if(mL)
         {
            double slDist = MathAbs(openP - curSL);
            double mR     = (slDist > 0) ? MathAbs(curP - openP) / slDist : 0;
            if(mR >= 0.30)
            {
               trade.PositionClose(ticket); RemoveTradeTracker(ticket);
               Print("⚡ Momentum perdido @", DoubleToString(mR,2), "R: $", profit);
               continue;
            }
         }
      }

      // Capa 4: BB Mid adverso en ganancia
      if(profit>0&&g_bbMid_cached>0)
      {
         bool adv=isBuy?(curP<g_bbMid_cached&&openP>g_bbMid_cached)
                       :(curP>g_bbMid_cached&&openP<g_bbMid_cached);
         if(adv)
         { trade.PositionClose(ticket); RemoveTradeTracker(ticket);
           Print("🔀 BB Mid adverso: $",profit); continue; }
      }

      // Capa 5: Barras negativas + tendencia adversa
      if(profit<0&&g_maxNegBars>0)
      {
         int idx=FindTradeTracker(ticket);
         if(idx>=0)
         {
            int bM5n=(int)((TimeCurrent()-g_openTrades[idx].openTime)/PeriodSeconds(PERIOD_M5));
            if(bM5n>=g_maxNegBars&&hE)
            {
               bool tA=isBuy?(fM5[0]<tM5[0]):(fM5[0]>tM5[0]);
               if(tA)
               { trade.PositionClose(ticket); RemoveTradeTracker(ticket);
                 Print("⏰ Neg prolongado(",bM5n,"b): $",profit); continue; }
            }
         }
      }

      // Capa 6: Cierre parcial progresivo
      if(InpPartialClose&&ticket==GetOldestMagicTicket())
      {
         double slD=MathAbs(openP-curSL);
         double mR=(slD>0)?MathAbs(curP-openP)/slD:0;
         if(!g_partial1Done&&mR>=1.0)
         {
            double cv=NormLot(vol*g_partialAt1R);
            double minV=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
            if(cv>=minV) trade.PositionClosePartial(ticket,cv);
            if(!g_beMoved)
            { double nSL=isBuy?openP+_Point:openP-_Point;
              trade.PositionModify(ticket,nSL,curTP); g_beMoved=true; }
            g_partial1Done=true;
            Print("💰 Parcial 1 @1R | BE activado");
         }
         if(!g_partial2Done&&mR>=2.0&&g_partial1Done)
         {
            double cv2=NormLot(vol*g_partialAt2R);
            double minV=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
            if(cv2>=minV) trade.PositionClosePartial(ticket,cv2);
            g_partial2Done=true;
            Print("💰 Parcial 2 @2R");
         }
      }

      // Capa 7: Trailing Stop ATR
      if(InpTrailingOn) ApplyTrailing(ticket,isBuy);

      // Capa 8: Break-even anticipado a 0.5R con señal de reversión
      if(!g_beMoved&&hE&&hR&&curSL>0)
      {
         double slD=MathAbs(openP-curSL);
         double mR=(slD>0)?MathAbs(curP-openP)/slD:0;
         bool rev=isBuy?(fM5[0]<sM5[0]&&rsiM5[0]<50):(fM5[0]>sM5[0]&&rsiM5[0]>50);
         if(mR>=0.5&&rev)
         {
            double nSL=isBuy?openP+_Point:openP-_Point;
            if((isBuy&&nSL>curSL)||(!isBuy&&(nSL<curSL||curSL==0)))
            { trade.PositionModify(ticket,nSL,curTP); g_beMoved=true;
              Print("🛡️ BE anticipado @0.5R"); }
         }
      }

      // Capa 9: RSI extremo en ganancia
      if(InpSmartExitOn&&profit>0&&hR)
      {
         bool ext=isBuy?(rsiM5[0]>78):(rsiM5[0]<22);
         if(ext)
         { trade.PositionClose(ticket); RemoveTradeTracker(ticket);
           Print("🔥 RSI extremo: $",profit); continue; }
      }
   }

   // Capa 10: Peak Profit Lock global
   if(count>0)
   {
      if(totalPnL>g_peakProfit) g_peakProfit=totalPnL;
      if(g_peakProfit>=g_minProfitLock&&totalPnL<(g_peakProfit-g_profitRetrace))
      { CloseAllMagic(); Print("💰 Peak Lock: Peak=$",g_peakProfit," PnL=$",totalPnL); }
   }
   else g_peakProfit=0;
}

//====================================================================
//  TRAILING STOP ATR
//====================================================================
void ApplyTrailing(ulong ticket, bool isBuy)
{
   if(!PositionSelectByTicket(ticket)) return;
   double cSL=PositionGetDouble(POSITION_SL);
   double cTP=PositionGetDouble(POSITION_TP);
   double cP =PositionGetDouble(POSITION_PRICE_CURRENT);
   double oP =PositionGetDouble(POSITION_PRICE_OPEN);
   double atr=(g_atr_cached>0)?g_atr_cached:10*_Point*10;
   double tr =atr*g_trailingMult;

   if(isBuy)
   { if(cP<=oP) return;
     double nSL=cP-tr;
     if(nSL>cSL+_Point&&nSL>=oP-_Point) trade.PositionModify(ticket,nSL,cTP); }
   else
   { if(cP>=oP) return;
     double nSL=cP+tr;
     if((nSL<cSL-_Point||cSL==0)&&nSL<=oP+_Point) trade.PositionModify(ticket,nSL,cTP); }
}

//====================================================================
//  MOTOR LONDON ORB
//====================================================================
void ORBDailyReset()
{
   g_orbRangeHigh=0; g_orbRangeLow=DBL_MAX; g_orbRangeBars=0;
   g_orbRangeBuilt=false; g_orbTradeTriggered=false; g_orbTradeOpenTime=0;
   g_orbWinsToday=0; g_orbLossesToday=0; g_orbWonToday=0; g_orbLostToday=0;
   ORBDeleteDrawings();
   Print("ORB: Reset diario.");
}

void RunLondonORB()
{
   static datetime lastBarORB=0;
   datetime cb=iTime(_Symbol,PERIOD_M1,0);
   if(cb==lastBarORB) return;
   lastBarORB=cb;

   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   datetime today=StringToTime(TimeToString(TimeCurrent(),TIME_DATE));
   if(today!=g_orbLastResetDate){ ORBDailyReset(); g_orbLastResetDate=today; }

   if(dt.hour==InpORBRangeHStart&&dt.min>=0&&dt.min<=59)
   {
      double hi=iHigh(_Symbol,PERIOD_M1,1), lo=iLow(_Symbol,PERIOD_M1,1);
      if(hi>g_orbRangeHigh) g_orbRangeHigh=hi;
      if(lo<g_orbRangeLow)  g_orbRangeLow=lo;
      g_orbRangeBars++;
   }

   if(dt.hour==InpORBTradeHStart&&dt.min==0&&!g_orbRangeBuilt&&g_orbRangeBars>0)
   {
      double sz=g_orbRangeHigh-g_orbRangeLow;
      if(g_orbRangeBars<InpORBMinBars||sz<InpORBRangeMinPts||sz>InpORBRangeMaxPts)
      { Print("ORB: Rango inválido sz=",sz," bars=",g_orbRangeBars); return; }
      g_orbRangeBuilt=true;
      Print("ORB: Rango OK H=",g_orbRangeHigh," L=",g_orbRangeLow," sz=",sz);
      ORBDrawRangeLines();
   }

   if(!g_orbRangeBuilt||g_orbTradeTriggered) return;
   if(dt.hour<InpORBTradeHStart||dt.hour>InpORBTradeHEnd) return;
   double dayPnL=AccountInfoDouble(ACCOUNT_BALANCE)-g_dayStartBal;
   if(dayPnL<=-g_dailyLossUSD) return;
   if(SymbolInfoInteger(_Symbol,SYMBOL_SPREAD)>InpORBMaxSpread) return;

   double ef[1],es[1]; ArraySetAsSeries(ef,true); ArraySetAsSeries(es,true);
   if(CopyBuffer(hORB_EmaFast,0,1,1,ef)<=0) return;
   if(CopyBuffer(hORB_EmaSlow,0,1,1,es)<=0) return;

   double closeM1=iClose(_Symbol,PERIOD_M1,1);

   // Confirmación RSI M5 opcional (filtra entradas contra momentum real)
   double bbU_m5,bbD_m5,bbM_m5,rsi_m5,mfi_m5,atr_m5;
   bool   hasM5 = GetIndM5(bbU_m5,bbD_m5,bbM_m5,rsi_m5,mfi_m5,atr_m5);

   if(closeM1>g_orbRangeHigh+InpORBBreakBuf&&ef[0]>es[0]&&(g_sesgoUp||!g_sesgoDn))
   {
      // RSI debe confirmar momentum alcista (>45); MFI debe mostrar compra (>45)
      if(InpORBUseRSI && hasM5 && (rsi_m5 < 45.0 || mfi_m5 < 45.0))
      { Print("ORB LONG bloqueado: RSI=",rsi_m5," MFI=",mfi_m5," sin momentum"); return; }

      double en=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      if(en > g_orbRangeHigh + InpORBBreakBuf + InpORBMaxSlippage)
      { Print("ORB LONG bloqueado: slippage en=",en," max=",g_orbRangeHigh+InpORBBreakBuf+InpORBMaxSlippage); return; }
      double sl=g_orbRangeLow-InpORBSLBuffer;

      // Cap de SL para cuentas micro: no arriesgar más de lo que permite el capital
      if(g_capMode==CAP_MICRO && g_microSLCapPts>0)
      {
         double slDistPts = en - sl;
         if(slDistPts > g_microSLCapPts)
         { sl = en - g_microSLCapPts;
           Print("ORB LONG: SL acotado a ",g_microSLCapPts," pts para MICRO"); }
      }

      double risk=en-sl; if(risk<=0) return;
      double tp=en+risk*InpORBRR;
      if(!ValidateTradeRisk(en,sl,"ORB-LONG")) return;
      if(!ValidateMinRR(en,sl,tp,"ORB-LONG"))  return;
      double lots=ORBCalcLots(risk); if(lots<=0) return;
      trade.SetExpertMagicNumber(InpMagicORB);
      if(trade.Buy(lots,_Symbol,en,sl,tp,"S2_LondonORB"))
      { g_orbTradeTriggered=true; g_orbTradeOpenTime=TimeCurrent();
        g_lastBuyTime=TimeCurrent();
        Print("✅ ORB LONG @",en," SL=",sl," TP=",tp," lots=",lots,
              " RSI=",DoubleToString(rsi_m5,1)," MFI=",DoubleToString(mfi_m5,1));
        ORBDrawEntryLines(en,sl,tp,true); }
      trade.SetExpertMagicNumber(InpMagic);
   }
   else if(closeM1<g_orbRangeLow-InpORBBreakBuf&&ef[0]<es[0]&&(g_sesgoDn||!g_sesgoUp))
   {
      // RSI debe confirmar momentum bajista (<55); MFI debe mostrar venta (<55)
      if(InpORBUseRSI && hasM5 && (rsi_m5 > 55.0 || mfi_m5 > 55.0))
      { Print("ORB SHORT bloqueado: RSI=",rsi_m5," MFI=",mfi_m5," sin momentum"); return; }

      double en=SymbolInfoDouble(_Symbol,SYMBOL_BID);
      if(en < g_orbRangeLow - InpORBBreakBuf - InpORBMaxSlippage)
      { Print("ORB SHORT bloqueado: slippage en=",en," min=",g_orbRangeLow-InpORBBreakBuf-InpORBMaxSlippage); return; }
      double sl=g_orbRangeHigh+InpORBSLBuffer;

      // Cap de SL para cuentas micro
      if(g_capMode==CAP_MICRO && g_microSLCapPts>0)
      {
         double slDistPts = sl - en;
         if(slDistPts > g_microSLCapPts)
         { sl = en + g_microSLCapPts;
           Print("ORB SHORT: SL acotado a ",g_microSLCapPts," pts para MICRO"); }
      }

      double risk=sl-en; if(risk<=0) return;
      double tp=en-risk*InpORBRR;
      if(!ValidateTradeRisk(en,sl,"ORB-SHORT")) return;
      if(!ValidateMinRR(en,sl,tp,"ORB-SHORT"))  return;
      double lots=ORBCalcLots(risk); if(lots<=0) return;
      trade.SetExpertMagicNumber(InpMagicORB);
      if(trade.Sell(lots,_Symbol,en,sl,tp,"S2_LondonORB"))
      { g_orbTradeTriggered=true; g_orbTradeOpenTime=TimeCurrent();
        g_lastSellTime=TimeCurrent();
        Print("✅ ORB SHORT @",en," SL=",sl," TP=",tp," lots=",lots,
              " RSI=",DoubleToString(rsi_m5,1)," MFI=",DoubleToString(mfi_m5,1));
        ORBDrawEntryLines(en,sl,tp,false); }
      trade.SetExpertMagicNumber(InpMagic);
   }
}

void ManageORBTrades()
{
   if(!g_orbTradeTriggered) return;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i);
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=InpMagicORB) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;

      double profit =PositionGetDouble(POSITION_PROFIT);
      double cSL    =PositionGetDouble(POSITION_SL);
      double cTP    =PositionGetDouble(POSITION_TP);
      double oP     =PositionGetDouble(POSITION_PRICE_OPEN);
      double vol    =PositionGetDouble(POSITION_VOLUME);
      bool   isBuy  =(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
      double cP     =isBuy?SymbolInfoDouble(_Symbol,SYMBOL_BID)
                          :SymbolInfoDouble(_Symbol,SYMBOL_ASK);

      if(g_orbTradeOpenTime>0&&
         (int)((TimeCurrent()-g_orbTradeOpenTime)/60)>=InpORBMaxMinutes)
      { trade.SetExpertMagicNumber(InpMagicORB);
        trade.PositionClose(t);
        trade.SetExpertMagicNumber(InpMagic);
        Print("ORB: Cierre tiempo: $",profit); continue; }

      if(InpTrailingOn&&g_atr_cached>0&&profit>0)
      {
         double tr=g_atr_cached*g_trailingMult;
         trade.SetExpertMagicNumber(InpMagicORB);
         if(isBuy){ double nSL=cP-tr; if(nSL>cSL+_Point&&nSL>=oP-_Point) trade.PositionModify(t,nSL,cTP); }
         else     { double nSL=cP+tr; if((nSL<cSL-_Point||cSL==0)&&nSL<=oP+_Point) trade.PositionModify(t,nSL,cTP); }
         trade.SetExpertMagicNumber(InpMagic);
      }

      // ── Break-even ORB: mover SL a entrada cuando se alcanza InpORBBELevel R ──
      // Protege el trade de revertir a pérdida después de un movimiento favorable
      if(InpORBBEOn && cSL > 0)
      {
         double slD = MathAbs(oP - cSL);
         double mR  = (slD > 0) ? MathAbs(cP - oP) / slD : 0;
         bool   beNotDone = isBuy ? (cSL < oP - _Point) : (cSL > oP + _Point);
         if(mR >= InpORBBELevel && beNotDone)
         {
            double nSL = isBuy ? oP + _Point : oP - _Point;
            trade.SetExpertMagicNumber(InpMagicORB);
            if(trade.PositionModify(t, nSL, cTP))
               Print("🛡️ ORB BE @", DoubleToString(InpORBBELevel, 1),
                     "R | profit=$", DoubleToString(profit, 2));
            trade.SetExpertMagicNumber(InpMagic);
         }
      }

      // ── Cierre parcial ORB mejorado: aplica a TODAS las cuentas ──
      // CAP_MEDIUM+: trigger a 1.0R (comportamiento original)
      // CAP_MICRO/SMALL: trigger a 1.2R (umbral más alto, SL ya está acotado)
      bool   canPartial  = InpPartialClose && cSL > 0 &&
                           (g_capMode >= CAP_MEDIUM || InpORBPartialMicro);
      double partialTrig = (g_capMode < CAP_MEDIUM) ? 1.20 : 1.00;

      if(canPartial)
      {
         double slD = MathAbs(oP - cSL);
         double mR  = (slD > 0) ? MathAbs(cP - oP) / slD : 0;
         if(mR >= partialTrig)
         {
            double minV = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
            double hV   = NormLot(vol * 0.50);
            if(hV >= minV)
            {
               static datetime lPB = 0; datetime cb = iTime(_Symbol, PERIOD_M5, 0);
               if(cb != lPB)
               {
                  trade.SetExpertMagicNumber(InpMagicORB);
                  trade.PositionClosePartial(t, hV);
                  // Mover SL a BE si aún no se movió
                  double nSL = isBuy ? oP + _Point : oP - _Point;
                  bool   beNeeded = isBuy ? (cSL < oP - _Point) : (cSL > oP + _Point);
                  if(beNeeded) trade.PositionModify(t, nSL, cTP);
                  trade.SetExpertMagicNumber(InpMagic);
                  lPB = cb;
                  Print("💰 ORB Parcial 50% @", DoubleToString(partialTrig, 1),
                        "R | profit=$", DoubleToString(profit, 2));
               }
            }
         }
      }
   }
}

double ORBCalcLots(double riskPts)
{
   double bal=AccountInfoDouble(ACCOUNT_BALANCE);
   double rf=(CountOpenPositions()>0)?0.50:1.0;
   double ra=bal*g_riskPct/100.0*rf;
   double tv=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   double ts=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   double pv=tv/ts*_Point;
   if(pv<=0||riskPts<=0) return 0;
   double lots=ra/((riskPts/_Point)*pv);
   if(g_capMode==CAP_MICRO) lots=MathMin(lots,SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN)*2.0);
   return NormLot(lots);
}

void CloseAllORB(string reason)
{
   trade.SetExpertMagicNumber(InpMagicORB);
   for(int i=PositionsTotal()-1;i>=0;i--)
   { ulong t=PositionGetTicket(i);
     if(!PositionSelectByTicket(t)) continue;
     if(PositionGetInteger(POSITION_MAGIC)==InpMagicORB&&
        PositionGetString(POSITION_SYMBOL)==_Symbol) trade.PositionClose(t); }
   trade.SetExpertMagicNumber(InpMagic);
   Print("ORB cerrado: ",reason);
}

//====================================================================
//  MOTOR ASIAN ORB  (rango 22:00-01:00, trades 01:00-04:00)
//====================================================================
void RunAsianORB()
{
   if(!InpAsianORBOn) return;
   static datetime lastBarAsia=0;
   datetime cb=iTime(_Symbol,PERIOD_M1,0);
   if(cb==lastBarAsia) return;
   lastBarAsia=cb;

   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   datetime today=StringToTime(TimeToString(TimeCurrent(),TIME_DATE));

   // Reset diario a las 22:00
   if(dt.hour==InpAsiaRangeHStart && dt.min==0 &&
      (g_asiaLastReset==0 || g_asiaLastReset < today))
   {
      g_asiaRangeHigh=0; g_asiaRangeLow=DBL_MAX; g_asiaRangeBars=0;
      g_asiaRangeBuilt=false; g_asiaTradeTriggered=false; g_asiaTradeOpenTime=0;
      g_asiaLastReset=TimeCurrent();
      g_asiaWinsToday=0; g_asiaLossesToday=0; g_asiaWonToday=0; g_asiaLostToday=0;
      Print("AsiaORB: Reset");
   }

   // Construir rango 22:00-01:00
   int h=dt.hour;
   bool inRange = (h>=InpAsiaRangeHStart || h<InpAsiaTradeHStart);
   if(inRange && !g_asiaRangeBuilt)
   {
      double hi=iHigh(_Symbol,PERIOD_M1,1), lo=iLow(_Symbol,PERIOD_M1,1);
      if(hi>g_asiaRangeHigh) g_asiaRangeHigh=hi;
      if(lo<g_asiaRangeLow)  g_asiaRangeLow=lo;
      g_asiaRangeBars++;
   }

   // Validar y marcar rango listo al inicio de la ventana de trading
   if(h==InpAsiaTradeHStart && dt.min==0 && !g_asiaRangeBuilt && g_asiaRangeBars>0)
   {
      double sz=g_asiaRangeHigh-g_asiaRangeLow;
      if(g_asiaRangeBars<InpAsiaMinBars||sz<InpAsiaRangeMinPts||sz>InpAsiaRangeMaxPts)
      { Print("AsiaORB: Rango inválido sz=",sz," bars=",g_asiaRangeBars); return; }
      g_asiaRangeBuilt=true;
      Print("AsiaORB: Rango OK H=",g_asiaRangeHigh," L=",g_asiaRangeLow," sz=",sz);
   }

   if(!g_asiaRangeBuilt || g_asiaTradeTriggered) return;
   if(h<InpAsiaTradeHStart || h>=InpAsiaTradeHEnd) return;
   if(IsNewsTime()) return;

   double dayPnL=AccountInfoDouble(ACCOUNT_BALANCE)-g_dayStartBal;
   if(dayPnL<=-g_dailyLossUSD) return;
   if(SymbolInfoInteger(_Symbol,SYMBOL_SPREAD)>InpORBMaxSpread) return;

   double closeM1=iClose(_Symbol,PERIOD_M1,1);

   if(closeM1 > g_asiaRangeHigh+InpAsiaBreakBuf)
   {
      double en=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      if(en > g_asiaRangeHigh+InpAsiaBreakBuf+InpORBMaxSlippage)
      { Print("AsiaORB LONG bloqueado: slippage"); return; }
      double sl=g_asiaRangeLow-InpAsiaSLBuffer;
      double risk=en-sl; if(risk<=0) return;
      double tp=en+risk*InpAsiaRR;
      if(!ValidateTradeRisk(en,sl,"ASIA-LONG")) return;
      if(!ValidateMinRR(en,sl,tp,"ASIA-LONG"))  return;
      double lots=ORBCalcLots(risk); if(lots<=0) return;
      trade.SetExpertMagicNumber(InpMagicASIA);
      if(trade.Buy(lots,_Symbol,en,sl,tp,"AsiaORB"))
      { g_asiaTradeTriggered=true; g_asiaTradeOpenTime=TimeCurrent();
        Print("✅ AsiaORB LONG @",en," SL=",sl," TP=",tp," lots=",lots); }
      trade.SetExpertMagicNumber(InpMagic);
   }
   else if(closeM1 < g_asiaRangeLow-InpAsiaBreakBuf)
   {
      double en=SymbolInfoDouble(_Symbol,SYMBOL_BID);
      if(en < g_asiaRangeLow-InpAsiaBreakBuf-InpORBMaxSlippage)
      { Print("AsiaORB SHORT bloqueado: slippage"); return; }
      double sl=g_asiaRangeHigh+InpAsiaSLBuffer;
      double risk=sl-en; if(risk<=0) return;
      double tp=en-risk*InpAsiaRR;
      if(!ValidateTradeRisk(en,sl,"ASIA-SHORT")) return;
      if(!ValidateMinRR(en,sl,tp,"ASIA-SHORT"))  return;
      double lots=ORBCalcLots(risk); if(lots<=0) return;
      trade.SetExpertMagicNumber(InpMagicASIA);
      if(trade.Sell(lots,_Symbol,en,sl,tp,"AsiaORB"))
      { g_asiaTradeTriggered=true; g_asiaTradeOpenTime=TimeCurrent();
        Print("✅ AsiaORB SHORT @",en," SL=",sl," TP=",tp," lots=",lots); }
      trade.SetExpertMagicNumber(InpMagic);
   }
}

void ManageAsianTrades()
{
   if(!InpAsianORBOn || !g_asiaTradeTriggered) return;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i);
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=InpMagicASIA) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;

      double profit=PositionGetDouble(POSITION_PROFIT);
      double cSL   =PositionGetDouble(POSITION_SL);
      double cTP   =PositionGetDouble(POSITION_TP);
      double oP    =PositionGetDouble(POSITION_PRICE_OPEN);
      bool   isBuy =(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
      double cP    =isBuy?SymbolInfoDouble(_Symbol,SYMBOL_BID):SymbolInfoDouble(_Symbol,SYMBOL_ASK);

      if(g_asiaTradeOpenTime>0 &&
         (int)((TimeCurrent()-g_asiaTradeOpenTime)/60)>=InpAsiaMaxMinutes)
      { trade.SetExpertMagicNumber(InpMagicASIA);
        trade.PositionClose(t);
        trade.SetExpertMagicNumber(InpMagic);
        Print("AsiaORB: Cierre tiempo $",profit); continue; }

      if(InpTrailingOn && g_atr_cached>0 && profit>0)
      {
         double tr=g_atr_cached*g_trailingMult;
         trade.SetExpertMagicNumber(InpMagicASIA);
         if(isBuy){ double nSL=cP-tr; if(nSL>cSL+_Point&&nSL>=oP-_Point) trade.PositionModify(t,nSL,cTP); }
         else     { double nSL=cP+tr; if((nSL<cSL-_Point||cSL==0)&&nSL<=oP+_Point) trade.PositionModify(t,nSL,cTP); }
         trade.SetExpertMagicNumber(InpMagic);
      }
   }
}

//====================================================================
//  MOTOR NY SESSION  (rango 12:00-13:30, trades 13:30-17:00)
//====================================================================
void NYReset()
{
   g_nyRangeHigh=0; g_nyRangeLow=DBL_MAX; g_nyRangeBars=0;
   g_nyRangeBuilt=false; g_nyTradeTriggered=false; g_nyTradeOpenTime=0;
   g_nyWinsToday=0; g_nyLossesToday=0; g_nyWonToday=0; g_nyLostToday=0;
   Print("NYSession: Reset diario.");
}

void RunNYSession()
{
   if(!InpNYSessionOn) return;
   static datetime lastBarNY=0;
   datetime cb=iTime(_Symbol,PERIOD_M1,0);
   if(cb==lastBarNY) return;
   lastBarNY=cb;

   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   datetime today=StringToTime(TimeToString(TimeCurrent(),TIME_DATE));
   static datetime nyLastReset=0;
   if(dt.hour==InpNYRangeHStart && dt.min==0 && nyLastReset < today)
   { NYReset(); nyLastReset=TimeCurrent(); }

   // Construir rango 12:00-13:30
   if(dt.hour==InpNYRangeHStart ||
      (dt.hour==InpNYTradeHStart && dt.min < InpNYTradeMinStart))
   {
      if(!g_nyRangeBuilt)
      {
         double hi=iHigh(_Symbol,PERIOD_M1,1), lo=iLow(_Symbol,PERIOD_M1,1);
         if(hi>g_nyRangeHigh) g_nyRangeHigh=hi;
         if(lo<g_nyRangeLow)  g_nyRangeLow=lo;
         g_nyRangeBars++;
      }
   }

   // Validar rango a las 13:30
   if(dt.hour==InpNYTradeHStart && dt.min==InpNYTradeMinStart && !g_nyRangeBuilt && g_nyRangeBars>0)
   {
      double sz=g_nyRangeHigh-g_nyRangeLow;
      if(g_nyRangeBars<InpNYMinBars||sz<InpNYRangeMinPts||sz>InpNYRangeMaxPts)
      { Print("NYSession: Rango inválido sz=",sz," bars=",g_nyRangeBars); return; }
      g_nyRangeBuilt=true;
      Print("NYSession: Rango OK H=",g_nyRangeHigh," L=",g_nyRangeLow," sz=",sz);
   }

   if(!g_nyRangeBuilt || g_nyTradeTriggered) return;
   if(dt.hour<InpNYTradeHStart ||(dt.hour==InpNYTradeHStart&&dt.min<InpNYTradeMinStart)) return;
   if(dt.hour>=InpNYTradeHEnd) return;
   if(IsNewsTime()) return;

   double dayPnL=AccountInfoDouble(ACCOUNT_BALANCE)-g_dayStartBal;
   if(dayPnL<=-g_dailyLossUSD) return;
   if(SymbolInfoInteger(_Symbol,SYMBOL_SPREAD)>InpORBMaxSpread) return;

   double closeM1=iClose(_Symbol,PERIOD_M1,1);

   if(closeM1 > g_nyRangeHigh+InpNYBreakBuf)
   {
      double en=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      if(en > g_nyRangeHigh+InpNYBreakBuf+InpORBMaxSlippage)
      { Print("NYSession LONG bloqueado: slippage"); return; }
      double sl=g_nyRangeLow-InpNYSLBuffer;
      double risk=en-sl; if(risk<=0) return;
      double tp=en+risk*InpNYRR;
      if(!ValidateTradeRisk(en,sl,"NY-LONG")) return;
      if(!ValidateMinRR(en,sl,tp,"NY-LONG"))  return;
      double lots=ORBCalcLots(risk); if(lots<=0) return;
      trade.SetExpertMagicNumber(InpMagicNY);
      if(trade.Buy(lots,_Symbol,en,sl,tp,"NYSession"))
      { g_nyTradeTriggered=true; g_nyTradeOpenTime=TimeCurrent();
        Print("✅ NYSession LONG @",en," SL=",sl," TP=",tp," lots=",lots); }
      trade.SetExpertMagicNumber(InpMagic);
   }
   else if(closeM1 < g_nyRangeLow-InpNYBreakBuf)
   {
      double en=SymbolInfoDouble(_Symbol,SYMBOL_BID);
      if(en < g_nyRangeLow-InpNYBreakBuf-InpORBMaxSlippage)
      { Print("NYSession SHORT bloqueado: slippage"); return; }
      double sl=g_nyRangeHigh+InpNYSLBuffer;
      double risk=sl-en; if(risk<=0) return;
      double tp=en-risk*InpNYRR;
      if(!ValidateTradeRisk(en,sl,"NY-SHORT")) return;
      if(!ValidateMinRR(en,sl,tp,"NY-SHORT"))  return;
      double lots=ORBCalcLots(risk); if(lots<=0) return;
      trade.SetExpertMagicNumber(InpMagicNY);
      if(trade.Sell(lots,_Symbol,en,sl,tp,"NYSession"))
      { g_nyTradeTriggered=true; g_nyTradeOpenTime=TimeCurrent();
        Print("✅ NYSession SHORT @",en," SL=",sl," TP=",tp," lots=",lots); }
      trade.SetExpertMagicNumber(InpMagic);
   }
}

void ManageNYTrades()
{
   if(!InpNYSessionOn || !g_nyTradeTriggered) return;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i);
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=InpMagicNY) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;

      double profit=PositionGetDouble(POSITION_PROFIT);
      double cSL   =PositionGetDouble(POSITION_SL);
      double cTP   =PositionGetDouble(POSITION_TP);
      double oP    =PositionGetDouble(POSITION_PRICE_OPEN);
      bool   isBuy =(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
      double cP    =isBuy?SymbolInfoDouble(_Symbol,SYMBOL_BID):SymbolInfoDouble(_Symbol,SYMBOL_ASK);

      if(g_nyTradeOpenTime>0 &&
         (int)((TimeCurrent()-g_nyTradeOpenTime)/60)>=InpNYMaxMinutes)
      { trade.SetExpertMagicNumber(InpMagicNY);
        trade.PositionClose(t);
        trade.SetExpertMagicNumber(InpMagic);
        Print("NYSession: Cierre tiempo $",profit); continue; }

      if(InpTrailingOn && g_atr_cached>0 && profit>0)
      {
         double tr=g_atr_cached*g_trailingMult;
         trade.SetExpertMagicNumber(InpMagicNY);
         if(isBuy){ double nSL=cP-tr; if(nSL>cSL+_Point&&nSL>=oP-_Point) trade.PositionModify(t,nSL,cTP); }
         else     { double nSL=cP+tr; if((nSL<cSL-_Point||cSL==0)&&nSL<=oP+_Point) trade.PositionModify(t,nSL,cTP); }
         trade.SetExpertMagicNumber(InpMagic);
      }
   }
}

//====================================================================
//  TRACKING
//====================================================================
void TrackClosedTrades()
{
   static int hC=0; int tot=HistoryDealsTotal();
   if(tot==hC) return;
   for(int i=hC;i<tot;i++)
   {
      ulong t=HistoryDealGetTicket(i); if(!t) continue;
      long mg=(long)HistoryDealGetInteger(t,DEAL_MAGIC);
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(t,DEAL_ENTRY)!=DEAL_ENTRY_OUT) continue;
      double p=HistoryDealGetDouble(t,DEAL_PROFIT);
      if(mg==InpMagic)
      { if(p>0){g_winsToday++;g_totalWon+=p;} else if(p<0){g_lossesToday++;g_totalLost+=MathAbs(p);} }
      else if(mg==InpMagicORB)
      { if(p>0){g_orbWinsToday++;g_orbWonToday+=p;} else if(p<0){g_orbLossesToday++;g_orbLostToday+=MathAbs(p);} }
      else if(mg==InpMagicASIA)
      { if(p>0){g_asiaWinsToday++;g_asiaWonToday+=p;} else if(p<0){g_asiaLossesToday++;g_asiaLostToday+=MathAbs(p);} }
      else if(mg==InpMagicNY)
      { if(p>0){g_nyWinsToday++;g_nyWonToday+=p;} else if(p<0){g_nyLossesToday++;g_nyLostToday+=MathAbs(p);} }
   }
   hC=tot;
}

//====================================================================
//  HELPERS
//====================================================================
void RegisterTrade(ulong t)
{ if(!t||g_openTradeCount>=50) return;
  g_openTrades[g_openTradeCount].ticket=t;
  g_openTrades[g_openTradeCount].openTime=TimeCurrent();
  g_openTradeCount++; }

int FindTradeTracker(ulong t)
{ for(int i=0;i<g_openTradeCount;i++) if(g_openTrades[i].ticket==t) return i; return -1; }

void RemoveTradeTracker(ulong t)
{ for(int i=0;i<g_openTradeCount;i++)
  { if(g_openTrades[i].ticket==t)
    { for(int j=i;j<g_openTradeCount-1;j++) g_openTrades[j]=g_openTrades[j+1];
      g_openTradeCount--; return; } } }

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
    if(!o||tt<ot){o=t;ot=tt;} }
  return o; }

void CloseAllMagic()
{ for(int i=PositionsTotal()-1;i>=0;i--)
  { ulong t=PositionGetTicket(i);
    if(PositionSelectByTicket(t)&&PositionGetInteger(POSITION_MAGIC)==InpMagic)
    { trade.PositionClose(t); RemoveTradeTracker(t); } } }

double NormLot(double lot)
{ double mn=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
  double mx=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
  double st=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
  lot=MathFloor(lot/st)*st;
  return MathMax(mn,MathMin(mx,lot)); }

//====================================================================
//  GRÁFICOS ORB
//====================================================================
void ORBDrawRangeLines()
{
   ObjectDelete(0,"ORB_HIGH"); ObjectDelete(0,"ORB_LOW");
   ObjectDelete(0,"ORB_BULL"); ObjectDelete(0,"ORB_BEAR");
   ObjectCreate(0,"ORB_HIGH",OBJ_HLINE,0,0,g_orbRangeHigh);
   ObjectSetInteger(0,"ORB_HIGH",OBJPROP_COLOR,clrDodgerBlue);
   ObjectSetInteger(0,"ORB_HIGH",OBJPROP_STYLE,STYLE_DASH);
   ObjectSetString(0, "ORB_HIGH",OBJPROP_TEXT,"ORB H:"+DoubleToString(g_orbRangeHigh,2));
   ObjectCreate(0,"ORB_LOW",OBJ_HLINE,0,0,g_orbRangeLow);
   ObjectSetInteger(0,"ORB_LOW",OBJPROP_COLOR,clrOrangeRed);
   ObjectSetInteger(0,"ORB_LOW",OBJPROP_STYLE,STYLE_DASH);
   ObjectSetString(0, "ORB_LOW",OBJPROP_TEXT,"ORB L:"+DoubleToString(g_orbRangeLow,2));
   ObjectCreate(0,"ORB_BULL",OBJ_HLINE,0,0,g_orbRangeHigh+InpORBBreakBuf);
   ObjectSetInteger(0,"ORB_BULL",OBJPROP_COLOR,clrLimeGreen);
   ObjectSetInteger(0,"ORB_BULL",OBJPROP_STYLE,STYLE_DOT);
   ObjectSetString(0, "ORB_BULL",OBJPROP_TEXT,"LONG TRIGGER");
   ObjectCreate(0,"ORB_BEAR",OBJ_HLINE,0,0,g_orbRangeLow-InpORBBreakBuf);
   ObjectSetInteger(0,"ORB_BEAR",OBJPROP_COLOR,clrRed);
   ObjectSetInteger(0,"ORB_BEAR",OBJPROP_STYLE,STYLE_DOT);
   ObjectSetString(0, "ORB_BEAR",OBJPROP_TEXT,"SHORT TRIGGER");
   ChartRedraw();
}

void ORBDrawEntryLines(double en,double sl,double tp,bool isLong)
{
   string p=isLong?"LONG":"SHORT";
   ObjectDelete(0,"ORB_ENTRY"); ObjectDelete(0,"ORB_SL"); ObjectDelete(0,"ORB_TP");
   ObjectCreate(0,"ORB_ENTRY",OBJ_HLINE,0,0,en);
   ObjectSetInteger(0,"ORB_ENTRY",OBJPROP_COLOR,clrGold);
   ObjectSetInteger(0,"ORB_ENTRY",OBJPROP_WIDTH,2);
   ObjectSetString(0, "ORB_ENTRY",OBJPROP_TEXT,p+" ENTRY:"+DoubleToString(en,2));
   ObjectCreate(0,"ORB_SL",OBJ_HLINE,0,0,sl);
   ObjectSetInteger(0,"ORB_SL",OBJPROP_COLOR,clrRed);
   ObjectSetInteger(0,"ORB_SL",OBJPROP_WIDTH,2);
   ObjectSetString(0, "ORB_SL",OBJPROP_TEXT,"SL:"+DoubleToString(sl,2));
   ObjectCreate(0,"ORB_TP",OBJ_HLINE,0,0,tp);
   ObjectSetInteger(0,"ORB_TP",OBJPROP_COLOR,clrLimeGreen);
   ObjectSetInteger(0,"ORB_TP",OBJPROP_WIDTH,2);
   ObjectSetString(0, "ORB_TP",OBJPROP_TEXT,"TP:"+DoubleToString(tp,2));
   ChartRedraw();
}

void ORBDeleteDrawings()
{ string n[]={"ORB_HIGH","ORB_LOW","ORB_BULL","ORB_BEAR","ORB_ENTRY","ORB_SL","ORB_TP"};
  for(int i=0;i<ArraySize(n);i++) ObjectDelete(0,n[i]); ChartRedraw(); }

//====================================================================
//  PANEL UNIFICADO v7.0
//====================================================================
void DrawPanel()
{
   if(!InpShowPanel) return;
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);

   int posQQ=0,posORB=0,posAsia=0,posNY=0;
   double pnlQQ=0,pnlORB=0,pnlAsia=0,pnlNY=0,volQQ=0;

   for(int i=0;i<PositionsTotal();i++)
   { ulong t=PositionGetTicket(i);
     if(!PositionSelectByTicket(t)) continue;
     long mg=(long)PositionGetInteger(POSITION_MAGIC);
     double pr=PositionGetDouble(POSITION_PROFIT);
     if(mg==InpMagic)      {posQQ++;  pnlQQ +=pr; volQQ+=PositionGetDouble(POSITION_VOLUME);}
     else if(mg==InpMagicORB) {posORB++; pnlORB+=pr;}
     else if(mg==InpMagicASIA){posAsia++;pnlAsia+=pr;}
     else if(mg==InpMagicNY)  {posNY++;  pnlNY+=pr;} }

   double dayPnL=AccountInfoDouble(ACCOUNT_BALANCE)-g_dayStartBal;
   double bal   =AccountInfoDouble(ACCOUNT_BALANCE);
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   int    tQQ   =g_winsToday+g_lossesToday;
   double wrQQ  =tQQ>0?(100.0*g_winsToday/tQQ):0;
   double pfQQ  =g_totalLost>0?g_totalWon/g_totalLost:0;
   int    tORB  =g_orbWinsToday+g_orbLossesToday;
   double wrORB =tORB>0?(100.0*g_orbWinsToday/tORB):0;
   double eqDrop    = bal - equity;
   double eqDropPct = (bal > 0) ? eqDrop / bal * 100.0 : 0;
   string eqStatus  = (eqDropPct < 10) ? "OK" : (eqDropPct < 15) ? "ATENTO" : "PELIGRO";

   string orbR=(g_orbRangeHigh>0&&g_orbRangeLow<DBL_MAX)?
      DoubleToString(g_orbRangeHigh,2)+"/"+DoubleToString(g_orbRangeLow,2):"---";
   string asiaR=(g_asiaRangeHigh>0&&g_asiaRangeLow<DBL_MAX)?
      DoubleToString(g_asiaRangeHigh,2)+"/"+DoubleToString(g_asiaRangeLow,2):"---";
   string nyR=(g_nyRangeHigh>0&&g_nyRangeLow<DBL_MAX)?
      DoubleToString(g_nyRangeHigh,2)+"/"+DoubleToString(g_nyRangeLow,2):"---";

   string sQQ  =g_dayInvalid?"PAUSADO":!g_initialized?"CONSTRUYENDO":g_triggered?"OPERANDO":"VIGILANDO";
   string sORB =!InpLondonORBOn?"OFF":g_orbTradeTriggered?"TRADE":g_orbRangeBuilt?"ESPERA-RUP":"CONSTRUYENDO";
   string sAsia=!InpAsianORBOn?"OFF":g_asiaTradeTriggered?"TRADE":g_asiaRangeBuilt?"ESPERA-RUP":"CONSTRUYENDO";
   string sNY  =!InpNYSessionOn?"OFF":g_nyTradeTriggered?"TRADE":g_nyRangeBuilt?"ESPERA-RUP":"CONSTRUYENDO";
   string enh  =InpEnhancementOn?(g_enhanceDone?"HECHO":"LISTO"):"OFF";

   int coolBuy  = (g_lastBuyTime  > 0) ? MathMax(0, 300-(int)(TimeCurrent()-g_lastBuyTime))  : 0;
   int coolSell = (g_lastSellTime > 0) ? MathMax(0, 300-(int)(TimeCurrent()-g_lastSellTime)) : 0;
   string coolStr = (coolBuy>0||coolSell>0) ?
      StringFormat("BUY:%ds SELL:%ds",coolBuy,coolSell) : "Libre";

   string txt="";
   txt+="=== QQ ULTIMATE v9.0 EVOLUTION ===\n";
   txt+=StringFormat("Hora: %02d:%02d | %s | Trades: %d/%d\n",dt.hour,dt.min,CapModeStr(),g_tradesToday,g_maxTradesDay);
   txt+=StringFormat("Bal : $%.2f | Eq: $%.2f [%s]\n",bal,equity,eqStatus);
   txt+=StringFormat("PnL : $%.2f | Drop: $%.2f (%.1f%%)\n",dayPnL,eqDrop,eqDropPct);
   txt+=StringFormat("Tgt : +$%.2f | Stop: -$%.2f\n",g_dailyProfitUSD,g_dailyLossUSD);
   txt+=StringFormat("D1  : %s | H1: %s | ATR: %.4f\n",
        g_sesgoUp?"BUY":(g_sesgoDn?"SELL":"NEUTRO"),
        g_h1Up?"UP":(g_h1Dn?"DWN":"="),g_atr_cached);
   double fmPct = (AccountInfoDouble(ACCOUNT_EQUITY)>0) ?
      AccountInfoDouble(ACCOUNT_FREEMARGIN)/AccountInfoDouble(ACCOUNT_EQUITY)*100.0 : 0;
   txt+=StringFormat("Filt: Noticias=%s | Cooldown: %s | Margen libre: %.1f%%\n",
        IsNewsTime()?"SI":"NO", coolStr, fmPct);
   txt+=StringFormat("v9  : CTShort=%s | FixedTP=%s [T%.0f/S%.0f] | MaxPos=%d\n",
        InpAllowOverboughtShort?"ON":"OFF",
        InpUseFixedScalperLevels?"ON":"OFF",
        InpFixedScalperTPPts, InpFixedScalperSLPts, InpScalperMaxPos);
   txt+="--- QQ Breakout / Scalper ---\n";
   txt+=StringFormat("Est : %s | Enhancement: %s\n",sQQ,enh);
   txt+=StringFormat("Rng : H=%.2f L=%.2f\n",g_rangeHigh,g_rangeLow);
   txt+=StringFormat("Pos : %d vol:%.2f pnl:$%.2f\n",posQQ,volQQ,pnlQQ);
   txt+=StringFormat("Res : W%d L%d WR:%.1f%% PF:%.2f\n",g_winsToday,g_lossesToday,wrQQ,pfQQ);
   txt+=StringFormat("Prot: BE%s P1%s P2%s Peak:$%.2f\n",
        g_beMoved?"Y":"N",g_partial1Done?"Y":"N",g_partial2Done?"Y":"N",g_peakProfit);
   txt+="--- London ORB ---\n";
   txt+=StringFormat("Est : %s | Rng: %s (%db)\n",sORB,orbR,g_orbRangeBars);
   txt+=StringFormat("Pos : %d pnl:$%.2f | W%d L%d WR:%.1f%%\n",posORB,pnlORB,g_orbWinsToday,g_orbLossesToday,wrORB);
   txt+="--- Asian ORB ---\n";
   txt+=StringFormat("Est : %s | Rng: %s\n",sAsia,asiaR);
   txt+=StringFormat("Pos : %d pnl:$%.2f | W%d L%d\n",posAsia,pnlAsia,g_asiaWinsToday,g_asiaLossesToday);
   txt+="--- NY Session ---\n";
   txt+=StringFormat("Est : %s | Rng: %s\n",sNY,nyR);
   txt+=StringFormat("Pos : %d pnl:$%.2f | W%d L%d\n",posNY,pnlNY,g_nyWinsToday,g_nyLossesToday);
   Comment(txt);
}

//====================================================================
//  OnTradeTransaction
//====================================================================
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &req,
                        const MqlTradeResult  &res)
{
   if(trans.type==TRADE_TRANSACTION_DEAL_ADD&&HistoryDealSelect(trans.deal))
   {
      long mg  =(long)HistoryDealGetInteger(trans.deal,DEAL_MAGIC);
      long en  =(long)HistoryDealGetInteger(trans.deal,DEAL_ENTRY);
      double p =HistoryDealGetDouble(trans.deal,DEAL_PROFIT);
      if(en==DEAL_ENTRY_OUT)
      {
         string src=(mg==InpMagicORB)?"[ORB]":
                    (mg==InpMagicASIA)?"[ASIA]":
                    (mg==InpMagicNY)?"[NY]":"[QQ]";
         Print(src," CIERRE $",DoubleToString(p,2),p>=0?" ✅":" ❌");
      }
   }
}

//+------------------------------------------------------------------+
//  FIN – QQ ULTIMATE v9.0 EVOLUTION
//+------------------------------------------------------------------+
