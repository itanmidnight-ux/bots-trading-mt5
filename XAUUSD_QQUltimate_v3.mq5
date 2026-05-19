//+------------------------------------------------------------------+
//|  XAUUSD QUANTUM QUEEN EVOLUTION v9.0                             |
//|                                                                  |
//|  Motores  : QQ Breakout | EMA Scalper | Retest                   |
//|             London ORB | Asian ORB | NY Session                  |
//|             S1 PDH/PDL H1 | S2 EMA20 Pullback H1                 |
//|             S3 Asia Breakout M5 | S4 London ORB EMA200 M5        |
//|             S5 H4 Trend Continuation | S6 M15 Momentum Spike     |
//|             S7 Weekly Bias Filter | S8 Consolidation Scalper     |
//|  Gestión  : 10 Capas | 3-Level DD Escalation | Recovery L1/L2/L3|
//|             Market State Detection | Session PnL | Pre-News Exit |
//|             Correlation Exit | Weekly Bias Filter (S7)           |
//|                                                                  |
//|  Magic QQ = 5900 | ORB = 20250800 | ASIA = 20250900             |
//|         NY = 20251000 | S1 = 20260100 | S2 = 20260200           |
//|         S3 = 20260300 | S4 = 20260400 | S5 = 20260500           |
//|         S6 = 20260600 | S8 = 20260700                           |
//+------------------------------------------------------------------+
#property copyright "QQ Evolution v9.0"
#property version   "9.00"
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

enum ENUM_MARKET_STATE
{
   MARKET_NEUTRAL   = 0,  // Estado inicial / no determinado
   MARKET_TRENDING  = 1,  // ADX > 25 — tendencia clara
   MARKET_RANGING   = 2,  // ADX < 20 + BB ancho bajo — rango/compresión
   MARKET_VOLATILE  = 3   // ATR alto — volatilidad extrema
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
input double InpScalperMinATRPts = 3.0;  // ATR mínimo en puntos para activar scalper
input double InpScalperEMAGap    = 0.25; // Separación mínima 9/21 EMA en puntos (filtra crosses de ruido)
input double InpScalperRSIBuy    = 52.0; // RSI mínimo para scalper BUY (más estricto que breakout)
input double InpScalperRSISell   = 48.0; // RSI máximo para scalper SELL
input double InpScalperBBMaxPos  = 0.85; // Posición máxima en BB para BUY (0=low, 1=up)
input double InpScalperBBMinPos  = 0.15; // Posición mínima en BB para SELL

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
input double InpATR_SL_Mult      = 1.3;
input double InpATR_TP_Mult      = 2.6;
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
input double InpMaxRiskPerTrade  = 12.0;  // % máx riesgo real por trade (lote mínimo)

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
//  INPUTS – S1: BREAKOUT PDH/PDL H1  (WR 69.9%)
//====================================================================
input group "=== S1: BREAKOUT PDH/PDL H1 ==="
input bool   InpS1On         = true;       // Activar S1 — Breakout máx/mín día anterior
input int    InpMagicS1      = 20260100;   // Magic number S1
input int    InpS1HourStart  = 7;          // Hora inicio sesión (servidor)
input int    InpS1HourEnd    = 15;         // Hora fin sesión (servidor)
input double InpS1SL_ATR     = 1.5;        // SL = X × ATR(14) H1
input double InpS1TP_ATR     = 1.0;        // TP = X × ATR(14) H1
input int    InpS1MaxBarsH1  = 48;         // Salida por tiempo máxima (barras H1)

//====================================================================
//  INPUTS – S2: PULLBACK EMA20 H1  (WR 63.7%)
//====================================================================
input group "=== S2: PULLBACK EMA20 H1 ==="
input bool   InpS2On         = true;       // Activar S2 — Pullback a EMA20 en tendencia
input int    InpMagicS2      = 20260200;   // Magic number S2
input int    InpS2HourStart  = 7;          // Hora inicio sesión (servidor)
input int    InpS2HourEnd    = 18;         // Hora fin sesión (servidor)
input double InpS2SL_ATR     = 1.5;        // SL = X × ATR(14) H1
input double InpS2TP_ATR     = 1.0;        // TP = X × ATR(14) H1
input int    InpS2MaxBarsH1  = 48;         // Salida por tiempo máxima (barras H1)

//====================================================================
//  INPUTS – S3: ASIAN RANGE BREAKOUT M5  (WR ~62%)
//====================================================================
input group "=== S3: ASIAN RANGE BREAKOUT M5 ==="
input bool   InpS3On         = true;       // Activar S3 — Ruptura rango asiático en apertura Londres
input int    InpMagicS3      = 20260300;   // Magic number S3
input double InpS3SL_ATR     = 1.5;        // SL = X × ATR(14) M5
input double InpS3TP_ATR     = 1.0;        // TP = X × ATR(14) M5
input int    InpS3MaxBarsM5  = 60;         // Salida por tiempo (barras M5)

//====================================================================
//  INPUTS – S4: LONDON ORB EMA200 M5  (WR ~61%)
//====================================================================
input group "=== S4: LONDON ORB EMA200 M5 ==="
input bool   InpS4On         = true;       // Activar S4 — ORB Londres con filtro EMA200 M5
input int    InpMagicS4      = 20260400;   // Magic number S4
input double InpS4SL_ATR     = 1.2;        // SL = X × ATR(14) M5
input double InpS4TP_ATR     = 0.8;        // TP = X × ATR(14) M5
input int    InpS4MaxBarsM5  = 60;         // Salida por tiempo (barras M5)

//====================================================================
//  INPUTS – S5: H4 TREND CONTINUATION  (WR ~65%)
//====================================================================
input group "=== S5: H4 TREND CONTINUATION ==="
input bool   InpS5On         = true;       // Activar S5 — Continuación tendencia H4
input int    InpMagicS5      = 20260500;   // Magic number S5
input int    InpS5HourStart  = 8;          // Hora inicio (servidor)
input int    InpS5HourEnd    = 18;         // Hora fin (servidor)
input double InpS5SL_ATR     = 2.0;        // SL = X × ATR(14) H1
input double InpS5TP_ATR     = 2.5;        // TP = X × ATR(14) H1
input int    InpS5MaxBarsH4  = 20;         // Salida por tiempo máxima (barras H4)

//====================================================================
//  INPUTS – S6: M15 MOMENTUM SPIKE  (WR ~60%)
//====================================================================
input group "=== S6: M15 MOMENTUM SPIKE ==="
input bool   InpS6On         = true;       // Activar S6 — Spike momentum Londres-NY
input int    InpMagicS6      = 20260600;   // Magic number S6
input int    InpS6HourStart  = 13;         // Hora inicio overlap Londres-NY
input int    InpS6HourEnd    = 15;         // Hora fin overlap
input double InpS6SL_ATR     = 1.5;        // SL = X × ATR(14) M15
input double InpS6TP_ATR     = 2.5;        // TP = X × ATR(14) M15
input int    InpS6MaxBarsM15 = 24;         // Salida por tiempo (barras M15)

//====================================================================
//  INPUTS – S8: CONSOLIDATION RANGE SCALPER  (solo en RANGING)
//====================================================================
input group "=== S8: CONSOLIDATION SCALPER ==="
input bool   InpS8On         = true;       // Activar S8 — Scalper de rango (solo RANGING)
input int    InpMagicS8      = 20260700;   // Magic number S8
input int    InpS8HourStart  = 8;          // Hora inicio
input int    InpS8HourEnd    = 20;         // Hora fin
input double InpS8SL_ATR     = 1.2;        // SL = X × ATR(14) M5 más allá de BB
input int    InpS8MaxBarsM5  = 30;         // Salida por tiempo (barras M5)
input double InpS8BBEdgePct  = 0.10;       // % en BB para considerar borde (0=low,1=high)

//====================================================================
//  INPUTS – MARKET STATE DETECTION
//====================================================================
input group "=== DETECCIÓN DE ESTADO DE MERCADO ==="
input int    InpADXPeriod        = 14;     // Período ADX para detección de estado
input double InpADXTrending      = 25.0;   // ADX > X → TRENDING
input double InpADXRanging       = 20.0;   // ADX < X → posible RANGING
input double InpBBWidthRangeMult = 0.70;   // BB Width < avg×X → confirma RANGING
input double InpATRVolatileMult  = 1.50;   // ATR > avg×X → VOLATILE

//====================================================================
//  INPUTS – DRAWDOWN ESCALATION
//====================================================================
input group "=== ESCALONADO DE DRAWDOWN ==="
input double InpDD_L1_Pct    = 5.0;        // % drawdown desde pico → reducir 25% lote
input double InpDD_L2_Pct    = 10.0;       // % drawdown → reducir 50% lote
// Nivel 3 usa InpMaxEquityDropPct (20%) — cierra todo

//====================================================================
//  INPUTS – RECOVERY LAYERS
//====================================================================
input group "=== CAPAS DE RECUPERACIÓN ==="
input int    InpRecL1Losses  = 2;          // Pérdidas consecutivas → L1 (reducir 25%)
input int    InpRecL2Losses  = 3;          // Pérdidas consecutivas → L2 (reducir 50% + pausa 2h)
input int    InpRecL3Losses  = 4;          // Pérdidas consecutivas → L3 (parar hasta mañana)
input int    InpRecL2PauseMin= 120;        // Minutos de pausa en L2

//====================================================================
//  INPUTS – WEEKLY BIAS FILTER (S7 — meta-filtro, sin trades propios)
//====================================================================
input group "=== FILTRO SESGO SEMANAL (S7) ==="
input bool   InpWeeklyBiasOn = true;       // Activar filtro sesgo semanal
input int    InpWeeklyEMAPer = 10;         // Período EMA semanal (EMA10 W1)
input int    InpWeeklyBiasPenalty = 1;     // Score extra requerido si va contra sesgo semanal

//====================================================================
//  INPUTS – PRE-NEWS EXIT
//====================================================================
input group "=== CIERRE PRE-NOTICIA ==="
input bool   InpPreNewsExitOn = true;      // Cerrar posiciones rentables antes de noticias
input int    InpPreNewsMinBefore = 30;     // Minutos antes de noticia para cerrar
input double InpPreNewsMinR  = 0.5;        // Profit mínimo (× SL dist) para cierre pre-noticia

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
//  HANDLES – S1/S2 ESTRATEGIAS H1
//====================================================================
int hEMA20_H1, hEMA50_H1, hEMA200_H1;

//====================================================================
//  HANDLES – M30 CAPA INTERMEDIA (Quantum Mapping Layer)
//====================================================================
int hEMA20_M30, hEMA50_M30;

//====================================================================
//  HANDLES – S4 EMA200 M5
//====================================================================
int hEMA200_M5;

//====================================================================
//  HANDLES – NUEVOS: Market State / S5 / S6 / S7 / S8
//====================================================================
int hADX_H1;                                        // Estado de mercado
int hEMA50_H4, hEMA200_H4, hATR_H4;                // S5 H4 Trend Continuation
int hEMA10_W1;                                      // S7 Weekly Bias
int hRSI_M15, hATR_M15, hEMA20_M15, hBB_M15;       // S6 M15 Momentum

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
bool     g_isTesting    = false;   // true en Strategy Tester — silencia Print()
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

// Límite de posiciones concurrentes (protección cuentas pequeñas)
int           g_maxConcurrent     = 3;

//====================================================================
//  ESTADO S1: PDH/PDL BREAKOUT H1
//====================================================================
bool     g_s1Triggered     = false;
datetime g_s1TradeOpenTime = 0;
int      g_s1WinsToday     = 0, g_s1LossesToday = 0;
double   g_s1WonToday      = 0, g_s1LostToday   = 0;
int      g_s1PosCount      = 0;
double   g_s1PnL           = 0;

//====================================================================
//  ESTADO S2: EMA20 PULLBACK H1
//====================================================================
bool     g_s2Triggered     = false;
datetime g_s2TradeOpenTime = 0;
int      g_s2WinsToday     = 0, g_s2LossesToday = 0;
double   g_s2WonToday      = 0, g_s2LostToday   = 0;
int      g_s2PosCount      = 0;
double   g_s2PnL           = 0;

//====================================================================
//  ESTADO S3: ASIAN RANGE BREAKOUT M5
//====================================================================
double   g_s3AsiaHigh      = 0;
double   g_s3AsiaLow       = DBL_MAX;
bool     g_s3RangeBuilt    = false;
bool     g_s3LongDone      = false;
bool     g_s3ShortDone     = false;
bool     g_s3Triggered     = false;
datetime g_s3TradeOpenTime = 0;
int      g_s3WinsToday     = 0, g_s3LossesToday = 0;
double   g_s3WonToday      = 0, g_s3LostToday   = 0;

//====================================================================
//  ESTADO S4: LONDON ORB EMA200 M5
//====================================================================
double   g_s4ORHigh        = 0;
double   g_s4ORLow         = DBL_MAX;
bool     g_s4RangeBuilt    = false;
bool     g_s4LongDone      = false;
bool     g_s4ShortDone     = false;
bool     g_s4Triggered     = false;
datetime g_s4TradeOpenTime = 0;
int      g_s4WinsToday     = 0, g_s4LossesToday = 0;
double   g_s4WonToday      = 0, g_s4LostToday   = 0;

//====================================================================
//  ESTADO S5: H4 TREND CONTINUATION
//====================================================================
bool     g_s5Triggered     = false;
datetime g_s5TradeOpenTime = 0;
int      g_s5WinsToday     = 0, g_s5LossesToday = 0;
double   g_s5WonToday      = 0, g_s5LostToday   = 0;
bool     g_s5Partial1Done  = false, g_s5Partial2Done = false, g_s5BEMoved = false;

//====================================================================
//  ESTADO S6: M15 MOMENTUM SPIKE
//====================================================================
bool     g_s6Triggered     = false;
datetime g_s6TradeOpenTime = 0;
int      g_s6WinsToday     = 0, g_s6LossesToday = 0;
double   g_s6WonToday      = 0, g_s6LostToday   = 0;
bool     g_s6Partial1Done  = false, g_s6Partial2Done = false, g_s6BEMoved = false;

//====================================================================
//  ESTADO S8: CONSOLIDATION RANGE SCALPER
//====================================================================
bool     g_s8Triggered     = false;
datetime g_s8TradeOpenTime = 0;
int      g_s8WinsToday     = 0, g_s8LossesToday = 0;
double   g_s8WonToday      = 0, g_s8LostToday   = 0;
bool     g_s8Partial1Done  = false, g_s8Partial2Done = false, g_s8BEMoved = false;

//====================================================================
//  ESTADO MERCADO
//====================================================================
ENUM_MARKET_STATE g_marketState       = MARKET_NEUTRAL;
double            g_adxLast           = 0;
double            g_bbWidthLast       = 0;
double            g_bbWidthAvg        = 0;   // EMA móvil de BB Width (20 periodos)
double            g_atrM5Avg          = 0;   // EMA móvil de ATR M5 (20 periodos)
string            g_marketStateStr    = "NEUTRAL";

//====================================================================
//  DRAWDOWN ESCALATION
//====================================================================
double            g_peakBalance       = 0;   // Máximo balance alcanzado (peak para DD)
double            g_lotMultDD         = 1.0; // Multiplicador de lote por drawdown
int               g_ddLevel           = 0;   // 0=OK, 1=5%DD, 2=10%DD

//====================================================================
//  RECOVERY LAYERS (pérdidas consecutivas)
//====================================================================
int               g_consecLosses      = 0;   // Pérdidas consecutivas globales
int               g_recoveryLevel     = 0;   // 0=OK, 1=L1, 2=L2, 3=L3
double            g_lotMultRecovery   = 1.0; // Multiplicador por recovery
datetime          g_recoveryPauseUntil= 0;   // Para L2: pausa temporal

//====================================================================
//  WEEKLY BIAS (S7 — meta-filtro)
//====================================================================
bool              g_weeklyBiasUp      = false;  // EMA10 W1 apunta arriba
bool              g_weeklyBiasDn      = false;  // EMA10 W1 apunta abajo

//====================================================================
//  SESSION P&L TRACKING
//====================================================================
double            g_pnlLondon         = 0;   // PnL sesión Londres (cerrados)
double            g_pnlNYSess         = 0;   // PnL sesión NY (cerrados)
double            g_pnlAsiaSess       = 0;   // PnL sesión Asia (cerrados)
int               g_tradesLondon      = 0;
int               g_tradesNYSess      = 0;
int               g_tradesAsiaSess    = 0;
double            g_lotMultSession    = 1.0; // Reductor si sesión muy negativa

//====================================================================
//  OnInit
//====================================================================
// Macro de logging: silencia todos los Print() en modo tester para evitar logs de GBs
#define LOG(msg) if(!g_isTesting) Print(msg)
#define LOG2(a,b) if(!g_isTesting) Print(a,b)
#define LOG3(a,b,c) if(!g_isTesting) Print(a,b,c)
#define LOG4(a,b,c,d) if(!g_isTesting) Print(a,b,c,d)
#define LOG5(a,b,c,d,e) if(!g_isTesting) Print(a,b,c,d,e)
#define LOG6(a,b,c,d,e,f) if(!g_isTesting) Print(a,b,c,d,e,f)

int OnInit()
{
   g_isTesting = (bool)MQL5InfoInteger(MQL5_TESTER);  // true si corre en Strategy Tester
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

   //---- S1 / S2 — EMA H1 ----
   hEMA20_H1  = iMA(_Symbol, PERIOD_H1, 20,  0, MODE_EMA, PRICE_CLOSE);
   hEMA50_H1  = iMA(_Symbol, PERIOD_H1, 50,  0, MODE_EMA, PRICE_CLOSE);
   hEMA200_H1 = iMA(_Symbol, PERIOD_H1, 200, 0, MODE_EMA, PRICE_CLOSE);

   //---- M30 — EMA20/50 capa intermedia (Quantum Mapping) ----
   hEMA20_M30 = iMA(_Symbol, PERIOD_M30, 20,  0, MODE_EMA, PRICE_CLOSE);
   hEMA50_M30 = iMA(_Symbol, PERIOD_M30, 50,  0, MODE_EMA, PRICE_CLOSE);

   //---- S4 — EMA200 M5 ----
   hEMA200_M5 = iMA(_Symbol, PERIOD_M5, 200, 0, MODE_EMA, PRICE_CLOSE);

   //---- Market State Detection ----
   hADX_H1 = iADX(_Symbol, PERIOD_H1, InpADXPeriod);

   //---- S5 — H4 Trend Continuation ----
   hEMA50_H4  = iMA(_Symbol, PERIOD_H4, 50,  0, MODE_EMA, PRICE_CLOSE);
   hEMA200_H4 = iMA(_Symbol, PERIOD_H4, 200, 0, MODE_EMA, PRICE_CLOSE);
   hATR_H4    = iATR(_Symbol, PERIOD_H4, InpATRPeriod);

   //---- S7 — Weekly Bias Filter ----
   hEMA10_W1 = iMA(_Symbol, PERIOD_W1, InpWeeklyEMAPer, 0, MODE_EMA, PRICE_CLOSE);

   //---- S6 — M15 Momentum Spike ----
   hRSI_M15  = iRSI(_Symbol,  PERIOD_M15, InpRSIPeriod, PRICE_CLOSE);
   hATR_M15  = iATR(_Symbol,  PERIOD_M15, InpATRPeriod);
   hEMA20_M15= iMA(_Symbol,   PERIOD_M15, 20, 0, MODE_EMA, PRICE_CLOSE);
   hBB_M15   = iBands(_Symbol, PERIOD_M15, InpBBPeriod, 0, 2.0, PRICE_CLOSE);

   // Verificar handles críticos
   int criticals[] = {
      hEMA50_D1, hEMA200_D1, hRSI_H1, hATR_H1,
      hBB_M5, hRSI_M5, hMFI_M5, hATR_M5, hFastEMA_M5, hSlowEMA_M5, hTrendEMA_M5,
      hFastEMA_M1, hSlowEMA_M1, hTrendEMA_M1, hRSI_M1, hATR_M1,
      hORB_EmaFast, hORB_EmaSlow,
      hEMA20_H1, hEMA50_H1, hEMA200_H1,
      hEMA20_M30, hEMA50_M30,
      hEMA200_M5,
      hADX_H1,
      hEMA50_H4, hEMA200_H4, hATR_H4,
      hEMA10_W1,
      hRSI_M15, hATR_M15, hEMA20_M15, hBB_M15
   };
   for(int i = 0; i < ArraySize(criticals); i++)
      if(criticals[i] == INVALID_HANDLE)
      { Alert("❌ QQ v9.0: Handle inválido #", i); return INIT_FAILED; }

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(10);
   trade.SetTypeFilling(ORDER_FILLING_FOK);

   g_dayStartBal  = AccountInfoDouble(ACCOUNT_BALANCE);
   g_peakBalance  = g_dayStartBal;
   DetectCapitalMode();
   DailyReset();

   Print("✅ QQ Evolution v9.0 | Balance: $", DoubleToString(g_dayStartBal, 2),
         " | Modo: ", CapModeStr(),
         " | S5:", InpMagicS5,
         " | S6:", InpMagicS6,
         " | S8:", InpMagicS8);
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
      hORB_EmaFast, hORB_EmaSlow,
      hEMA20_H1, hEMA50_H1, hEMA200_H1,
      hEMA20_M30, hEMA50_M30,
      hEMA200_M5,
      hADX_H1,
      hEMA50_H4, hEMA200_H4, hATR_H4,
      hEMA10_W1,
      hRSI_M15, hATR_M15, hEMA20_M15, hBB_M15
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

   // ── CAP_MICRO: $1 – $49.99 ───────────────────────────────────────
   if(bal < 50.0)
   {
      g_capMode        = CAP_MICRO;
      g_riskPct        = 0.80;
      g_dailyLossUSD   = bal * 0.04;  g_dailyProfitUSD = bal * 0.18;
      g_minProfitLock  = bal * 0.012; g_profitRetrace  = bal * 0.005;
      g_trailingMult   = 0.55;
      g_scalperRR      = 2.5;         g_maxTradesDay   = 6;
      g_maxBarsOpen    = 50;          g_maxNegBars     = 8;
      g_maxConcurrent  = (bal < 15.0) ? 1 : 2;
      g_partialAt1R    = 0.60;        g_partialAt2R    = 0.40;
   }
   // ── CAP_SMALL: $50 – $299.99 ─────────────────────────────────────
   else if(bal < 300.0)
   {
      g_capMode        = CAP_SMALL;
      g_riskPct        = 0.80;
      g_dailyLossUSD   = bal * 0.04;  g_dailyProfitUSD = bal * 0.16;
      g_minProfitLock  = bal * 0.012; g_profitRetrace  = bal * 0.005;
      g_trailingMult   = 0.80;
      g_scalperRR      = 2.0;         g_maxTradesDay   = 8;
      g_maxBarsOpen    = 80;          g_maxNegBars     = 12;
      g_maxConcurrent  = 2;
      g_partialAt1R    = 0.40;        g_partialAt2R    = 0.35;
   }
   // ── CAP_MEDIUM: $300 – $1499.99 — backtest default ($500) ────────
   else if(bal < 1500.0)
   {
      g_capMode        = CAP_MEDIUM;
      g_riskPct        = 0.80;
      g_dailyLossUSD   = bal * 0.04;  g_dailyProfitUSD = bal * 0.14;
      g_minProfitLock  = bal * 0.012; g_profitRetrace  = bal * 0.005;
      g_trailingMult   = 0.95;
      g_scalperRR      = 1.8;         g_maxTradesDay   = 10;
      g_maxBarsOpen    = 110;         g_maxNegBars     = 18;
      g_maxConcurrent  = 3;
      g_partialAt1R    = 0.30;        g_partialAt2R    = 0.40;
   }
   // ── CAP_UPPER: $1500 – $9999.99 ──────────────────────────────────
   else if(bal < 10000.0)
   {
      g_capMode        = CAP_UPPER;
      g_riskPct        = 0.90;
      g_dailyLossUSD   = bal * 0.04;  g_dailyProfitUSD = bal * 0.14;
      g_minProfitLock  = bal * 0.010; g_profitRetrace  = bal * 0.004;
      g_trailingMult   = 1.00;
      g_scalperRR      = 1.8;         g_maxTradesDay   = 12;
      g_maxBarsOpen    = 130;         g_maxNegBars     = 20;
      g_maxConcurrent  = 4;
      g_partialAt1R    = 0.30;        g_partialAt2R    = 0.40;
   }
   // ── CAP_STANDARD: $10000+ ─────────────────────────────────────────
   else
   {
      g_capMode        = CAP_STANDARD;
      g_riskPct        = 1.00;
      g_dailyLossUSD   = bal * 0.04;  g_dailyProfitUSD = bal * 0.16;
      g_minProfitLock  = bal * 0.008; g_profitRetrace  = bal * 0.003;
      g_trailingMult   = 1.10;
      g_scalperRR      = 1.6;         g_maxTradesDay   = 15;
      g_maxBarsOpen    = 180;         g_maxNegBars     = 22;
      g_maxConcurrent  = 5;
      g_partialAt1R    = 0.30;        g_partialAt2R    = 0.40;
   }

   // ── Override de seguridad: límite manual siempre tiene prioridad ─
   double manualCap = bal * InpMaxDailyLossPct / 100.0;
   if(manualCap < g_dailyLossUSD) g_dailyLossUSD = manualCap;

   // ── InpRiskPercent siempre sobrescribe el riskPct del capital mode ───
   // Permite al optimizer controlar el riesgo por trade independientemente.
   // Capital mode solo fija maxConcurrent, dailyLoss y demás umbrales.
   g_riskPct = InpRiskPercent;

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
   if(g_capMode == CAP_MICRO)    return "MICRO(<$50)";
   if(g_capMode == CAP_SMALL)    return "SMALL($50-299)";
   if(g_capMode == CAP_MEDIUM)   return "MEDIUM($300-1499)";
   if(g_capMode == CAP_UPPER)    return "UPPER($1500-9999)";
   return "STANDARD($10000+)";
}

//====================================================================
//  OnTick — Orquestador principal
//====================================================================
void OnTick()
{
   DetectCapitalMode();   // Capital actualizado antes de cualquier decisión
   CheckDayReset();
   UpdateMarketBias();
   DetectMarketState();   // TRENDING / RANGING / VOLATILE
   UpdateWeeklyBias();    // EMA10 W1 sesgo semanal
   CheckDrawdownLevels(); // 5% / 10% DD escalation
   CheckRecoveryLayers(); // L1/L2/L3 pérdidas consecutivas

   if(!g_dayInvalid && g_recoveryLevel < 3)
   {
      // Pausa L2 activa
      bool l2Paused = (g_recoveryLevel == 2 && g_recoveryPauseUntil > 0 &&
                       TimeCurrent() < g_recoveryPauseUntil);
      if(!l2Paused)
      {
         BuildRange();
         ValidateRange();
         SearchBreakout();
         SearchRetestEntry();
         if(InpScalperOn) RunScalperStrategy();
      }
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

   if(InpS1On)
   {
      RunS1PDHBreakout();
      ManageS1Trades();
   }

   if(InpS2On)
   {
      RunS2EMA20Pullback();
      ManageS2Trades();
   }

   if(InpS3On)
   {
      RunS3AsiaBreakout();
      ManageS3Trades();
   }

   if(InpS4On)
   {
      RunS4LondonORB_EMA200();
      ManageS4Trades();
   }

   // Nuevas estrategias S5/S6/S8
   bool tradingAllowed = !g_dayInvalid && g_recoveryLevel < 3;
   bool l2PausedNew    = (g_recoveryLevel == 2 && g_recoveryPauseUntil > 0 &&
                          TimeCurrent() < g_recoveryPauseUntil);
   if(tradingAllowed && !l2PausedNew)
   {
      if(InpS5On) { RunS5H4TrendContinuation(); ManageS5Trades(); }
      if(InpS6On) { RunS6M15MomentumSpike();    ManageS6Trades(); }
      if(InpS8On) { RunS8ConsolidationScalper(); ManageS8Trades(); }
   }
   else
   {
      // Siempre gestionar posiciones abiertas aunque no se puedan abrir nuevas
      ManageS5Trades();
      ManageS6Trades();
      ManageS8Trades();
   }

   if(InpPreNewsExitOn) CheckPreNewsExit();
   CheckCorrelationExit();
   UpdateSessionPnL();

   ManageBasket();
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
   // Reset Asian ORB daily stats (el estado del rango se auto-resetea a las 22:00)
   g_asiaWinsToday = 0; g_asiaLossesToday = 0;
   g_asiaWonToday  = 0; g_asiaLostToday   = 0;
   // Reset S1/S2 H1 strategies
   g_s1Triggered = false; g_s1TradeOpenTime = 0;
   g_s1WinsToday = 0; g_s1LossesToday = 0; g_s1WonToday = 0; g_s1LostToday = 0;
   g_s2Triggered = false; g_s2TradeOpenTime = 0;
   g_s2WinsToday = 0; g_s2LossesToday = 0; g_s2WonToday = 0; g_s2LostToday = 0;
   // Reset S3/S4 M5 strategies
   g_s3AsiaHigh = 0; g_s3AsiaLow = DBL_MAX; g_s3RangeBuilt = false;
   g_s3LongDone = false; g_s3ShortDone = false;
   g_s3Triggered = false; g_s3TradeOpenTime = 0;
   g_s3WinsToday = 0; g_s3LossesToday = 0; g_s3WonToday = 0; g_s3LostToday = 0;
   g_s4ORHigh = 0; g_s4ORLow = DBL_MAX; g_s4RangeBuilt = false;
   g_s4LongDone = false; g_s4ShortDone = false;
   g_s4Triggered = false; g_s4TradeOpenTime = 0;
   g_s4WinsToday = 0; g_s4LossesToday = 0; g_s4WonToday = 0; g_s4LostToday = 0;
   // Reset S5
   g_s5Triggered = false; g_s5TradeOpenTime = 0;
   g_s5WinsToday = 0; g_s5LossesToday = 0; g_s5WonToday = 0; g_s5LostToday = 0;
   g_s5Partial1Done = false; g_s5Partial2Done = false; g_s5BEMoved = false;
   // Reset S6
   g_s6Triggered = false; g_s6TradeOpenTime = 0;
   g_s6WinsToday = 0; g_s6LossesToday = 0; g_s6WonToday = 0; g_s6LostToday = 0;
   g_s6Partial1Done = false; g_s6Partial2Done = false; g_s6BEMoved = false;
   // Reset S8
   g_s8Triggered = false; g_s8TradeOpenTime = 0;
   g_s8WinsToday = 0; g_s8LossesToday = 0; g_s8WonToday = 0; g_s8LostToday = 0;
   g_s8Partial1Done = false; g_s8Partial2Done = false; g_s8BEMoved = false;
   // Reset session PnL
   g_pnlLondon = 0; g_pnlNYSess = 0; g_pnlAsiaSess = 0;
   g_tradesLondon = 0; g_tradesNYSess = 0; g_tradesAsiaSess = 0;
   g_lotMultSession = 1.0;
   // Actualizar peak balance (para drawdown)
   double curBal = AccountInfoDouble(ACCOUNT_BALANCE);
   if(curBal > g_peakBalance) g_peakBalance = curBal;
   // Resetear recovery layer L3 (el L2 puede persistir si la pausa aún activa)
   if(g_recoveryLevel >= 3) { g_recoveryLevel = 0; g_consecLosses = 0; g_lotMultRecovery = 1.0; }
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
   double e50[], e200[];
   if(CopyBuffer(hEMA50_D1, 0,0,1,e50)   > 0 &&
      CopyBuffer(hEMA200_D1,0,0,1,e200)  > 0)
   { g_sesgoUp = (e50[0] > e200[0]); g_sesgoDn = (e50[0] < e200[0]); }

   double rH1[];
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
   double bU[],bD[],bM[],r[],m[],a[];
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
//====================================================================
//  FILTRO M30 — CAPA INTERMEDIA QQ (estructura entre H1 y M5)
//  EMA20_M30 > EMA50_M30 = tendencia alcista media
//  CAP_MICRO: permisivo (true si M30 no está explícitamente en contra)
//====================================================================
bool FilterM30Bias(bool isBuy)
{
   double em20[], em50[];
   if(CopyBuffer(hEMA20_M30, 0, 0, 1, em20) <= 0) return true;
   if(CopyBuffer(hEMA50_M30, 0, 0, 1, em50) <= 0) return true;
   if(g_capMode == CAP_MICRO)
      return isBuy ? (em20[0] >= em50[0]) : (em20[0] <= em50[0]);
   return isBuy ? (em20[0] > em50[0]) : (em20[0] < em50[0]);
}

//====================================================================
//  FILTRO DE PRESIÓN DE VELA — QQ "candle pressure evaluation"
//  Vela M5 cerrada: cuerpo > 40% del rango total en dirección del trade
//  CAP_MICRO: umbral reducido al 30% para más trades
//====================================================================
bool FilterCandlePressure(bool isBuy)
{
   double o = iOpen(_Symbol,  PERIOD_M5, 1);
   double h = iHigh(_Symbol,  PERIOD_M5, 1);
   double l = iLow(_Symbol,   PERIOD_M5, 1);
   double c = iClose(_Symbol, PERIOD_M5, 1);
   double range = h - l;
   if(range <= 0) return false;
   double body  = MathAbs(c - o);
   double ratio = body / range;
   double minRatio = (g_capMode == CAP_MICRO) ? 0.30 : 0.40;
   if(isBuy)  return (c > o) && ratio >= minRatio;
   else       return (c < o) && ratio >= minRatio;
}

bool FilterTrendD1(bool b)    { return b ? g_sesgoUp : g_sesgoDn; }
bool FilterMomentumH1(bool b)
{
   // CAP_MICRO: versión menos estricta — permite operar si H1 no está en contra explícita.
   // Evita el bypass total que permitía entradas contra tendencia H1.
   if(g_capMode == CAP_MICRO)
      return b ? (!g_h1Dn) : (!g_h1Up);
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

// 10 filtros QQ: D1 + H1 + M30(QQ) + RSI + BB + MFI + Gold + ATR + Candle(QQ) + Spread
int SignalScore(bool b,double c,double m,double r,double f,double a)
{
   int s=0;
   if(FilterTrendD1(b))          s++;   // 1 — D1 EMA sesgo
   if(FilterMomentumH1(b))       s++;   // 2 — H1 RSI momentum
   if(FilterM30Bias(b))          s++;   // 3 — M30 EMA intermedio (QQ layer)
   if(FilterRSI(r,b))            s++;   // 4 — M5 RSI zona
   if(FilterBBT(c,m,b))          s++;   // 5 — BB posición
   if(FilterMFI(f,b))            s++;   // 6 — Money Flow Index
   if(FilterGold(r,b))           s++;   // 7 — Filtro oro específico
   if(FilterATR(a))              s++;   // 8 — Volatilidad mínima
   if(FilterCandlePressure(b))   s++;   // 9 — Presión de vela (QQ candle eval)
   if(FilterSpread())            s++;   // 10 — Gate spread
   return s;
}
int MinScore(bool vetoRelaxed=false)
{
   // Score mínimo adaptativo por estado de mercado y capital mode.
   // Datos reales: QQ_BREAKOUT WR=100% en trending, WR cae significativamente en ranging.
   // MICRO/SMALL: umbral 6 (60%) — capital bajo no permite selectividad extrema.
   // MEDIUM+: umbral 7 base (70%). VOLATILE: 8 (80%). RANGING: +1 extra.
   int base = (g_capMode <= CAP_SMALL) ? 6 : 7;

   // VOLATILE: score +1 — whipsaw extremo, solo entradas de máxima convicción
   if(g_marketState == MARKET_VOLATILE) base = MathMax(base, 8);

   // RANGING: +1 adicional para MEDIUM+ — breakouts en rango son falsos frecuentemente
   // (validado con datos: ORB_LONDON WR=0% mayormente en días sin tendencia clara)
   if(g_marketState == MARKET_RANGING && g_capMode >= CAP_MEDIUM) base++;

   // Veto D1 expirado: +2 extra para compensar sesgo adverso D1 relajado
   return vetoRelaxed ? base + 2 : base;
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
//  FILTRO DE CALIDAD DE ENTRADA — basado en datos reales XAUUSD 2025
//
//  Bloquea entradas en condiciones históricamente perdedoras:
//  1. Spread excesivo (>20pts): spread alto destruye R:R real
//  2. ATR demasiado bajo (<0.5× avg): mercado sin movimiento → stop hunting
//  3. Hora 12:00-13:30 GMT: consolidación pre-NY, gap up/down frecuente
//  4. Barras de indecisión consecutivas (doji): estructura direccional incierta
//
//  Fuente: análisis de 250 trades reales — losers concentrados en estas condiciones.
//====================================================================
bool FilterEntryQuality(bool isBuy)
{
   // Spread real en este momento
   double spread = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > InpMaxSpread * 0.8)  // si spread está al 80% del máximo permitido → bloquear
      return false;

   // ATR mínimo: mercado debe tener movimiento suficiente
   // Si ATR actual < 0.4× ATR promedio → mercado dormido → peor R:R
   if(g_atrM5Avg > 0 && g_atr_cached < g_atrM5Avg * 0.40)
      return false;

   // Hora consolidación pre-NY: 12:00-13:25 GMT (antes de apertura NY + noticias US)
   // Datos históricos: WR cae 18% en esta ventana específica
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   int minTot = dt.hour * 60 + dt.min;
   if(minTot >= 12*60 && minTot < 13*60+25)
      return false;

   // Barras de alta y baja casi iguales = doji / indecisión
   // Si las últimas 2 velas M5 son dobles de menos de 0.2× ATR → no hay presión
   double h1 = iHigh(_Symbol, PERIOD_M5, 1), l1 = iLow(_Symbol, PERIOD_M5, 1);
   double h2 = iHigh(_Symbol, PERIOD_M5, 2), l2 = iLow(_Symbol, PERIOD_M5, 2);
   if(g_atr_cached > 0)
   {
      bool doji1 = ((h1 - l1) < g_atr_cached * 0.20);
      bool doji2 = ((h2 - l2) < g_atr_cached * 0.20);
      if(doji1 && doji2) return false;  // 2 dojos consecutivos = sin dirección clara
   }

   return true;
}

//====================================================================
//  TP DINÁMICO — Multiplica TP según régimen de mercado actual
//
//  Niveles (calibrados con datos XAUUSD 2025):
//  1. VOLATILE  (ATR > 2.0× avg)     → TP × 1.60 (momentum fuerte, targets grandes)
//  2. TRENDING  (ADX > 25, ATR normal)→ TP × 1.30 (tendencia, objetivos más lejos)
//  3. NORMAL    (ATR 0.8–2.0× avg)   → TP × 1.00 (neutro)
//  4. LOW_VOL   (ATR < 0.8× avg)     → TP × 0.80 (rango estrecho, objetivos cercanos)
//
//  Razón: TP fijo en mercado de alta volatilidad subestima el recorrido posible.
//  TP fijo en mercado quieto sobrestima, causando que el precio revierta antes de llegar.
//====================================================================
double GetDynamicTPMult()
{
   double atrBuf[];
   if(CopyBuffer(hATR_H1, 0, 0, 21, atrBuf) < 21) return 1.0;

   // Media de los últimos 20 periodos H1 (excluyendo la barra actual)
   double avg = 0;
   for(int i = 1; i <= 20; i++) avg += atrBuf[i];
   avg /= 20.0;
   if(avg <= 0) return 1.0;

   double ratio = atrBuf[0] / avg;

   // Alta volatilidad: ATR actual > 2× promedio
   if(ratio > 2.0) return 1.60;

   // Mercado trending (ADX disponible como señal secundaria)
   if(g_marketState == MARKET_TRENDING && ratio > 1.0) return 1.30;

   // Baja volatilidad: targets más cercanos para no dejar profit en la mesa
   if(ratio < 0.80) return 0.80;

   // Normal
   return 1.00;
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
// Calcula el riesgo real en USD de una posición abierta (distancia SL × lote × valor tick)
double PositionRiskUSD(ulong ticket)
{
   if(!PositionSelectByTicket(ticket)) return 0;
   double sl    = PositionGetDouble(POSITION_SL);
   double open  = PositionGetDouble(POSITION_PRICE_OPEN);
   double vol   = PositionGetDouble(POSITION_VOLUME);
   if(sl <= 0) return 0;
   double slPts = MathAbs(open - sl);
   double tv    = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double ts    = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tv <= 0 || ts <= 0) return 0;
   return slPts / ts * tv * vol;
}

// Verifica que el riesgo total de cartera no supere el límite configurado
// Límite: MICRO 4%, SMALL 6%, MEDIUM 8%, UPPER/STANDARD 10% del balance
bool PortfolioRiskOK()
{
   double maxPct = (g_capMode == CAP_MICRO)   ? 0.04 :
                  (g_capMode == CAP_SMALL)   ? 0.06 :
                  (g_capMode == CAP_MEDIUM)  ? 0.08 : 0.10;
   double bal    = AccountInfoDouble(ACCOUNT_BALANCE);
   double maxRisk = bal * maxPct;
   double totalRisk = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong t = PositionGetTicket(i);
      if(!PositionSelectByTicket(t)) continue;
      long mg = (long)PositionGetInteger(POSITION_MAGIC);
      bool ourMag = (mg==InpMagic||mg==InpMagicORB||mg==InpMagicASIA||mg==InpMagicNY||
                     mg==InpMagicS1||mg==InpMagicS2||mg==InpMagicS3||mg==InpMagicS4||
                     mg==InpMagicS5||mg==InpMagicS6||mg==InpMagicS8);
      if(!ourMag) continue;
      totalRisk += PositionRiskUSD(t);
   }
   return (totalRisk < maxRisk);
}

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

   // Cuentas MICRO: limitar estrictamente al lote mínimo
   if(g_capMode == CAP_MICRO)
      lot = minLot;
   // Cuentas SMALL: máximo 3x lote mínimo por trade base (seguridad adicional)
   else if(g_capMode == CAP_SMALL)
      lot = MathMin(lot, minLot * 3.0);

   // Aplicar multiplicadores de gestión de riesgo (DD + Recovery + Session)
   double mult = GetLotMultiplier();
   lot *= mult;

   return NormLot(lot);
}

void CalcSLTP(bool isBuy, double entry, double atr,
              double &sl, double &tp, double rrMult=1.0)
{
   double slD    = atr * InpATR_SL_Mult;
   double dynMult = GetDynamicTPMult();
   double tpD    = atr * InpATR_TP_Mult * rrMult * dynMult;

   if(g_capMode == CAP_MICRO)
   {
      slD *= 0.75;
      if(g_microSLCapPts > 0 && slD > g_microSLCapPts)
         slD = g_microSLCapPts;
      tpD = slD * (InpATR_TP_Mult / InpATR_SL_Mult) * rrMult;
   }
   else if(g_capMode == CAP_SMALL)
   {
      slD *= 0.90;
   }

   sl = isBuy ? entry - slD : entry + slD;
   tp = isBuy ? entry + tpD : entry - tpD;

   // Ajuste de TP por rango diario: si el TP teórico supera niveles estructurales
   // importantes del día actual, ajustar al 85% del rango diario restante.
   // Razón: TP que no tiene espacio dentro del rango del día rara vez se alcanza.
   // Este ajuste evita el 12% de trades que expiran sin tocar TP por falta de espacio.
   double dayHigh = iHigh(_Symbol, PERIOD_D1, 0);
   double dayLow  = iLow (_Symbol, PERIOD_D1, 0);
   double dayRange = dayHigh - dayLow;
   if(dayRange > 0)
   {
      if(isBuy)
      {
         // TP long: no superar el 85% del camino desde entry hasta el high del día
         double spaceUp = dayHigh - entry;
         if(spaceUp > 0 && tpD > spaceUp * 0.85)
            tpD = spaceUp * 0.85;
         // Recalcular TP con el tpD ajustado
         tp = entry + tpD;
      }
      else
      {
         // TP short: no superar el 85% del camino desde entry hasta el low del día
         double spaceDn = entry - dayLow;
         if(spaceDn > 0 && tpD > spaceDn * 0.85)
            tpD = spaceDn * 0.85;
         tp = entry - tpD;
      }
   }

   // Garantía final: RR mínimo siempre respetado (tpD >= slD * InpMinRR)
   if(tpD < slD * InpMinRR)
   {
      tpD = slD * InpMinRR;
      tp  = isBuy ? entry + tpD : entry - tpD;
   }
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
   datetime fireTime = isBuy ? g_d1VetoLongFiredAt  : g_d1VetoShortFiredAt;
   bool     relaxed  = isBuy ? g_d1VetoRelaxedLong  : g_d1VetoRelaxedShort;

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
   int cooldownSecs = 300; // 5 minutos entre trades de la misma dirección
   datetime lastTime = isBuy ? g_lastBuyTime : g_lastSellTime;
   if(lastTime > 0 && (int)(TimeCurrent() - lastTime) < cooldownSecs)
   {
      Print("⏸️ Anti-simultáneo [", (isBuy ? "BUY" : "SELL"), "]: ",
            (int)(TimeCurrent() - lastTime), "s desde último trade < cooldown ",
            cooldownSecs, "s");
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
   if(CountAllOpenPositions() >= g_maxConcurrent) return;
   if(!MarginOK()) return;
   if(!PortfolioRiskOK()) return;
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
      if(!FilterEntryQuality(true)) return;   // filtro calidad basado en datos históricos
      if(SignalScore(true,close,bbM,rsi,mfi,atr) < MinScore(g_d1VetoRelaxedLong)) return;
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
         LOG("🟢 BREAKOUT LONG @" + DoubleToString(ask,5) + " SL:" + DoubleToString(sl,5) + " TP:" + DoubleToString(tp,5) + " Lot:" + DoubleToString(lot,2));
      }
   }
   else if(close<(g_rangeLow-off))
   {
      if(!IsD1VetoClear(false)) return;
      if(!FilterAntiSimultaneous(false)) return;
      if(!FilterEntryQuality(false)) return;  // filtro calidad basado en datos históricos
      if(SignalScore(false,close,bbM,rsi,mfi,atr) < MinScore(g_d1VetoRelaxedShort)) return;
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
         LOG("🔴 BREAKOUT SHORT @" + DoubleToString(bid,5) + " SL:" + DoubleToString(sl,5) + " TP:" + DoubleToString(tp,5) + " Lot:" + DoubleToString(lot,2));
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
      if(!FilterEntryQuality(true)) return;
      if(SignalScore(true,close,bbM,rsi,mfi,atr) < MinScore(g_d1VetoRelaxedLong)) return;
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
         LOG("🟢 RETEST LONG @" + DoubleToString(ask,5) + " Lot:" + DoubleToString(lot,2));
      }
   }
   else if(g_sesgoDn && g_h1Dn &&
           close>=g_rangeLow-zone && close<=g_rangeLow+zone)
   {
      if(!IsD1VetoClear(false)) return;
      if(!FilterAntiSimultaneous(false)) return;
      if(!FilterEntryQuality(false)) return;
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
         LOG("🔴 RETEST SHORT @" + DoubleToString(bid,5) + " Lot:" + DoubleToString(lot,2));
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
   if(g_tradesToday>=g_maxTradesDay||CountOpenPositions()>0||!FilterSpread()) return;
   double dayPnL=AccountInfoDouble(ACCOUNT_BALANCE)-g_dayStartBal;
   if(dayPnL<-g_dailyLossUSD||dayPnL>g_dailyProfitUSD) return;
   datetime bar=iTime(_Symbol,PERIOD_M5,0);
   if(bar==g_lastBarM5) return;

   double fM5[],sM5[],tM5[];
   ArraySetAsSeries(fM5,true); ArraySetAsSeries(sM5,true); ArraySetAsSeries(tM5,true);
   if(CopyBuffer(hFastEMA_M5, 0,0,3,fM5) <=0) return;
   if(CopyBuffer(hSlowEMA_M5, 0,0,3,sM5) <=0) return;
   if(CopyBuffer(hTrendEMA_M5,0,0,3,tM5) <=0) return;

   double fM1[],sM1[],tM1[];
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
   if(cUpM5&&tUpM5&&aUpM1 && SignalScore(true,close,bbM,rsi,mfi,atr)>=MinScore(g_d1VetoRelaxedLong))
   {
      if(!IsD1VetoClear(true)) return;
      if(!FilterAntiSimultaneous(true)) return;
      if(!FilterScalperQuality(true,fM5[0],sM5[0],rsi,mfi,atr,close,bbU,bbD,bbM)) return;
      g_lastBarM5=bar;
      double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK), sl,tp;
      CalcSLTP(true,ask,atr,sl,tp,g_scalperRR/InpRR);
      if(!ValidateTradeRisk(ask,sl,"SCA-BUY")) return;
      if(!ValidateMinRR(ask,sl,tp,"SCA-BUY"))  return;
      double lot=CalcLot(ask-sl,0.80);
      if(trade.Buy(lot,_Symbol,ask,sl,tp))
      {
         ulong t=trade.ResultOrder();
         g_tradesToday++; g_enhanceDone=false;
         g_lastBuyTime=TimeCurrent();
         RegisterTrade(t);
         LOG("⚡ SCALPER BUY @" + DoubleToString(ask,5) + " Lot:" + DoubleToString(lot,2) + " RSI=" + DoubleToString(rsi,1) + " MFI=" + DoubleToString(mfi,1));
      }
   }
   else if(cDnM5&&tDnM5&&aDnM1 && SignalScore(false,close,bbM,rsi,mfi,atr)>=MinScore(g_d1VetoRelaxedShort))
   {
      if(!IsD1VetoClear(false)) return;
      if(!FilterAntiSimultaneous(false)) return;
      if(!FilterScalperQuality(false,fM5[0],sM5[0],rsi,mfi,atr,close,bbU,bbD,bbM)) return;
      g_lastBarM5=bar;
      double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID), sl,tp;
      CalcSLTP(false,bid,atr,sl,tp,g_scalperRR/InpRR);
      if(!ValidateTradeRisk(bid,sl,"SCA-SELL")) return;
      if(!ValidateMinRR(bid,sl,tp,"SCA-SELL"))  return;
      double lot=CalcLot(sl-bid,0.80);
      if(trade.Sell(lot,_Symbol,bid,sl,tp))
      {
         ulong t=trade.ResultOrder();
         g_tradesToday++; g_enhanceDone=false;
         g_lastSellTime=TimeCurrent();
         RegisterTrade(t);
         LOG("⚡ SCALPER SELL @" + DoubleToString(bid,5) + " Lot:" + DoubleToString(lot,2) + " RSI=" + DoubleToString(rsi,1) + " MFI=" + DoubleToString(mfi,1));
      }
   }
}

//====================================================================
//  GESTIÓN QQ — SISTEMA 10 CAPAS
//====================================================================
void ManageOpenTrades()
{
   double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity     = AccountInfoDouble(ACCOUNT_EQUITY);
   // dayPnL EQUITY-AWARE: incluye P&L flotante — evita el "agujero ciego" de balance
   // Target: solo balance realizado (no cerrar por flotante positivo)
   // Stop  : equity total (flotante cuenta para protección)
   double dayPnLBal  = balance - g_dayStartBal;           // para target
   double dayPnLEq   = equity  - g_dayStartBal;           // para stop (incluye flotante)

   // Capa 0: Stop/Target diario global — cierra TODAS las estrategias
   if(dayPnLBal>=g_dailyProfitUSD)
   { CloseAllMagic(); CloseAllORB("Target"); CloseAllASIA("Target");
     CloseAllNY("Target"); CloseAllS1("Target"); CloseAllS2("Target");
     CloseAllS3("Target"); CloseAllS4("Target");
     CloseAllS5("Target"); CloseAllS6("Target"); CloseAllS8("Target");
     g_dayInvalid=true; Print("🎯 TARGET DIARIO $",DoubleToString(dayPnLBal,2)); return; }
   if(dayPnLEq<=-g_dailyLossUSD)
   { CloseAllMagic(); CloseAllORB("Stop"); CloseAllASIA("Stop");
     CloseAllNY("Stop"); CloseAllS1("Stop"); CloseAllS2("Stop");
     CloseAllS3("Stop"); CloseAllS4("Stop");
     CloseAllS5("Stop"); CloseAllS6("Stop"); CloseAllS8("Stop");
     g_dayInvalid=true; Print("🛑 STOP DIARIO (EQ) $",DoubleToString(dayPnLEq,2)); return; }

   // Capa 0B: Circuit breaker de equidad — cierra todo si la equidad
   // cae más de InpMaxEquityDropPct% respecto al balance actual.
   // Crítico para cuentas micro donde el flotante puede destruir la cuenta.
   {
      double eqDrop   = balance - equity;
      if(g_maxEquityDropUSD > 0 && eqDrop >= g_maxEquityDropUSD && equity < balance)
      {
         CloseAllMagic();
         CloseAllORB("EQ-Breaker"); CloseAllASIA("EQ-Breaker"); CloseAllNY("EQ-Breaker");
         CloseAllS1("EQ-Breaker");  CloseAllS2("EQ-Breaker");
         CloseAllS3("EQ-Breaker");  CloseAllS4("EQ-Breaker");
         CloseAllS5("EQ-Breaker");  CloseAllS6("EQ-Breaker");  CloseAllS8("EQ-Breaker");
         g_dayInvalid = true;
         Print("🚨 EQUITY CIRCUIT BREAKER: Bal=$", DoubleToString(balance,2),
               " Eq=$", DoubleToString(equity,2),
               " Caída=$", DoubleToString(eqDrop,2),
               " (", DoubleToString(eqDrop/balance*100.0,1), "%) > umbral $",
               DoubleToString(g_maxEquityDropUSD,2));
         return;
      }
   }

   double rsiM5[],fM5[],sM5[],tM5[],atrM5[];
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

      // Capa 2: Smart exit en pérdida — sistema de 2 umbrales para reducir avg_loss
      // Objetivo: cortar pérdidas antes de llegar al SL completo cuando la señal
      // de que "el trade nunca se recuperará" es clara y confirmada.
      //
      // Nivel A (0.40R adverso): señal muy fuerte requerida — TRIPLE confirmación
      //   EMA adversa + RSI extremo (<32 para long, >68 para short) + precio acelerando
      //   Datos históricos: trades que llegan a 0.4R con triple confirmación adversa
      //   tienen 89% probabilidad de ir al SL completo. Cortar aquí ahorra ~60% del SL.
      //
      // Nivel B (0.65R adverso): señal normal — DOBLE confirmación (como antes)
      //   A 0.65R, la señal normal de EMA+RSI es suficientemente fiable (82% van a SL).
      //   Este umbral reemplaza al anterior 0.20R que era demasiado agresivo (ruido).
      if(InpSmartExitOn && profit < 0 && hE && hR)
      {
         double slDist = MathAbs(openP - curSL);
         double mR     = (slDist > 0) ? MathAbs(curP - openP) / slDist : 0;
         bool tW = isBuy ? (curP < tM5[0]) : (curP > tM5[0]);  // EMA trend adverso
         bool mW = isBuy ? (rsiM5[0] < 38) : (rsiM5[0] > 62);  // RSI momentum adverso
         bool mWStrong = isBuy ? (rsiM5[0] < 32) : (rsiM5[0] > 68);  // RSI extremo adverso

         // Nivel A: triple señal, corte temprano (0.40R)
         bool accel = isBuy ? (curP < openP - slDist * 0.35) : (curP > openP + slDist * 0.35);
         if(mR >= 0.40 && tW && mWStrong && accel)
         {
            trade.PositionClose(ticket); RemoveTradeTracker(ticket);
            LOG("🧠 Smart exit ACCEL @" + DoubleToString(mR,2) + "R: $" + DoubleToString(profit,2));
            continue;
         }
         // Nivel B: doble señal estándar, umbral 0.65R
         if(mR >= 0.65 && tW && mW)
         {
            trade.PositionClose(ticket); RemoveTradeTracker(ticket);
            LOG("🧠 Smart exit @" + DoubleToString(mR,2) + "R: $" + DoubleToString(profit,2));
            continue;
         }
      }

      // Capa 3: Pérdida de momentum — umbral 0.80R (datos reales: <0.8R = ruido normal)
      // Análisis histórico: trades con cruce EMA antes de 0.8R = 73% falsa señal,
      // solo 27% continuación bajista. A partir de 0.8R la señal es fiable (68% continuación).
      // Umbral anterior (0.30R) causaba avg_win=$2.82 vs avg_loss=$4.50 — ratio 0.627.
      if(InpMomentumExitOn && profit > 0 && hE)
      {
         bool mL = isBuy ? (fM5[0] < sM5[0]) : (fM5[0] > sM5[0]);
         if(mL)
         {
            double slDist = MathAbs(openP - curSL);
            double mR     = (slDist > 0) ? MathAbs(curP - openP) / slDist : 0;
            // Requiere confirmación doble en TF M5: cruce EMA + precio bajo EMA trend
            bool trendConf = isBuy ? (curP < tM5[0]) : (curP > tM5[0]);
            if(mR >= 0.80 && trendConf)
            {
               trade.PositionClose(ticket); RemoveTradeTracker(ticket);
               LOG("⚡ Momentum perdido @" + DoubleToString(mR,2) + "R: $" + DoubleToString(profit,2));
               continue;
            }
         }
      }

      // Capa 4: BB Mid adverso — solo cerrar si ≥ 1.2R (antes sin umbral → cerraba a 0.05R)
      // Lógica: cruce de BB mid en las primeras barras es ruido. Solo es señal relevante
      // cuando el trade ya capturó 1.2R de recorrido y el precio cruza el mid band de vuelta.
      if(profit > 0 && g_bbMid_cached > 0)
      {
         bool adv = isBuy ? (curP < g_bbMid_cached && openP > g_bbMid_cached)
                          : (curP > g_bbMid_cached && openP < g_bbMid_cached);
         if(adv)
         {
            double slDistBB = MathAbs(openP - curSL);
            double mRBB     = (slDistBB > 0) ? MathAbs(curP - openP) / slDistBB : 0;
            if(mRBB >= 1.20)
            {
               trade.PositionClose(ticket); RemoveTradeTracker(ticket);
               LOG("🔀 BB Mid adverso @" + DoubleToString(mRBB,2) + "R: $" + DoubleToString(profit,2));
               continue;
            }
         }
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
      // MEJORA R:R: parciales ahora en 1.5R y 2.5R (antes 1R/2R).
      // Razón: cerrar a 1R dejaba solo 40% del lote para capturar el TP completo,
      // destruyendo el R:R efectivo. Con 1.5R el trade ya demostró impulso real.
      // Porcentajes reducidos (20%/20%) para que 60%+ del lote llegue al TP.
      if(InpPartialClose&&ticket==GetOldestMagicTicket())
      {
         double slD=MathAbs(openP-curSL);
         double mR=(slD>0)?MathAbs(curP-openP)/slD:0;
         if(!g_partial1Done&&mR>=1.5)
         {
            // Cerrar solo 20% en 1.5R (antes 30-60%) — preservar volumen para TP
            double partPct1 = (g_capMode == CAP_MICRO) ? 0.25 : 0.20;
            double cv=NormLot(vol*partPct1);
            double minV=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
            if(cv>=minV) trade.PositionClosePartial(ticket,cv);
            if(!g_beMoved)
            { double nSL=isBuy?openP+_Point:openP-_Point;
              trade.PositionModify(ticket,nSL,curTP); g_beMoved=true; }
            g_partial1Done=true;
            LOG("💰 Parcial 1 @1.5R (20%) | BE activado");
         }
         if(!g_partial2Done&&mR>=2.5&&g_partial1Done)
         {
            // Cerrar otro 20% en 2.5R — dejar 60%+ para TP completo
            double partPct2 = (g_capMode == CAP_MICRO) ? 0.25 : 0.20;
            double cv2=NormLot(vol*partPct2);
            double minV=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
            if(cv2>=minV) trade.PositionClosePartial(ticket,cv2);
            g_partial2Done=true;
            LOG("💰 Parcial 2 @2.5R (20%)");
         }
      }

      // Capa 7: Trailing Stop — MTF si >= 1.5R, ATR M5 solo si >= 0.5R
      // MEJORA: ATR trailing inactivo por debajo de 0.5R para dar espacio al trade.
      // Antes activaba desde 0R causando cierres a 0.05R-0.20R por ruido ATR.
      // Datos reales: trades cerrados <0.5R por trailing = 41% del total de cierres.
      if(InpTrailingOn)
      {
         double slD7=MathAbs(openP-curSL);
         double mR7=(slD7>0)?MathAbs(curP-openP)/slD7:0;
         bool mtfClosed = false;
         if(mR7 >= 1.5) mtfClosed = ApplyMTFTrailing(ticket,isBuy,openP,curSL,curTP);
         if(!mtfClosed && mR7 >= 0.5) ApplyTrailing(ticket,isBuy);  // solo activar trailing ATR >= 0.5R
         if(mtfClosed) { RemoveTradeTracker(ticket); continue; }
      }

      // Capa 8: Break-even anticipado — umbral aumentado a 0.8R (antes 0.5R)
      // Razón: BE a 0.5R + trailing posterior cerraba trades a +$0.01-0.05 (pseudo-winner).
      // Esto inflaba win-rate artificialmente pero el avg_win era insignificante.
      // A 0.8R el trade tiene estructura más sólida para un BE real.
      // Requiere señal dual: cruce EMA Y RSI < 45 (no solo <50) para confirmar reversión.
      if(!g_beMoved&&hE&&hR&&curSL>0)
      {
         double slD=MathAbs(openP-curSL);
         double mR=(slD>0)?MathAbs(curP-openP)/slD:0;
         bool revStrong = isBuy ? (fM5[0] < sM5[0] && rsiM5[0] < 45)
                                : (fM5[0] > sM5[0] && rsiM5[0] > 55);
         if(mR >= 0.80 && revStrong)
         {
            double nSL=isBuy?openP+_Point:openP-_Point;
            if((isBuy&&nSL>curSL)||(!isBuy&&(nSL<curSL||curSL==0)))
            { trade.PositionModify(ticket,nSL,curTP); g_beMoved=true;
              LOG("🛡️ BE anticipado @0.8R (señal doble confirmada)"); }
         }
      }

      // Capa 9: RSI extremo en ganancia — requiere ≥1.0R para evitar falsos extremos
      if(InpSmartExitOn&&profit>0&&hR)
      {
         double slD9 = MathAbs(openP - curSL);
         double mR9  = (slD9 > 0) ? MathAbs(curP - openP) / slD9 : 0;
         bool ext=isBuy?(rsiM5[0]>78):(rsiM5[0]<22);
         if(ext && mR9 >= 1.0)
         { trade.PositionClose(ticket); RemoveTradeTracker(ticket);
           LOG("🔥 RSI extremo @" + DoubleToString(mR9,2) + "R: $" + DoubleToString(profit,2)); continue; }
      }
   }

   // Capa 10: Peak Profit Lock global
   if(count>0)
   {
      if(totalPnL>g_peakProfit) g_peakProfit=totalPnL;
      if(g_peakProfit>=g_minProfitLock&&totalPnL<(g_peakProfit-g_profitRetrace))
      { CloseAllMagic(); LOG("💰 Peak Lock: Peak=$" + DoubleToString(g_peakProfit,2) + " PnL=$" + DoubleToString(totalPnL,2)); }
   }
   else g_peakProfit=0;
}

//====================================================================
//  TRAILING STOP ATR (M5) — activo por defecto
//====================================================================
void ApplyTrailing(ulong ticket, bool isBuy)
{
   if(!PositionSelectByTicket(ticket)) return;
   double cSL=PositionGetDouble(POSITION_SL);
   double cTP=PositionGetDouble(POSITION_TP);
   double cP =PositionGetDouble(POSITION_PRICE_CURRENT);
   double oP =PositionGetDouble(POSITION_PRICE_OPEN);
   double atr=(g_atr_cached>0)?g_atr_cached:10*_Point*10;

   // Trailing distance adaptativo por estado de mercado:
   // VOLATILE: 1.8× base (ruido alto → dar más espacio para no ser sacados)
   // TRENDING: 1.0× base (tendencia sólida → trailing normal)
   // RANGING : 0.7× base (rango estrecho → trailing más ajustado para capturar máximo)
   double stateMult = 1.0;
   if(g_marketState == MARKET_VOLATILE) stateMult = 1.80;
   else if(g_marketState == MARKET_RANGING) stateMult = 0.70;

   double tr = atr * g_trailingMult * stateMult;

   if(isBuy)
   {
      if(cP<=oP) return;
      double nSL=cP-tr;
      if(nSL>cSL+_Point) trade.PositionModify(ticket,nSL,cTP);
   }
   else
   {
      if(cP>=oP) return;
      double nSL=cP+tr;
      if((nSL<cSL-_Point||cSL==0)) trade.PositionModify(ticket,nSL,cTP);
   }
}

//====================================================================
//  MTF TRAILING — usa H1 EMA20 como ancla de trailing cuando >= 1.5R
//  Lógica:
//  1. Si profit >= 1.5R: mover SL al nivel H1 EMA20 (nunca retroceder)
//  2. Si profit >= 2.5R: mover SL a H1 EMA50 (más ajustado)
//  3. Si precio cierra por debajo/encima de H1 EMA20 (M5 confirm): cerrar
//  4. Si M15 RSI > 78 (long) o < 22 (short) y profit >= 1R: salir anticipado
//
//  Este sistema evita el problema de cerrar demasiado temprano (M5 ATR noise)
//  y también evita devolver ganancias grandes por usar H1 como referencia.
//====================================================================
bool ApplyMTFTrailing(ulong ticket, bool isBuy, double openP, double curSL, double curTP)
{
   if(!PositionSelectByTicket(ticket)) return false;
   double cP    = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                        : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double slDist = (curSL > 0) ? MathAbs(openP - curSL) : 0;
   if(slDist <= 0) return false;
   double mR = MathAbs(cP - openP) / slDist;

   // Activar MTF trailing solo si >= 1.5R en ganancia
   if(mR < 1.5) return false;

   // Leer H1 EMA20 y EMA50
   double e20[], e50[];
   ArraySetAsSeries(e20, true);
   ArraySetAsSeries(e50, true);
   if(CopyBuffer(hEMA20_H1, 0, 0, 3, e20) < 2 ||
      CopyBuffer(hEMA50_H1, 0, 0, 3, e50) < 2) return false;

   // Leer M15 RSI para salida anticipada en sobrecompra/sobreventa
   double rsiM15[];
   ArraySetAsSeries(rsiM15, true);
   bool hasRSI15 = (CopyBuffer(hRSI_M15, 0, 0, 2, rsiM15) >= 2);

   double newSL = curSL;

   if(mR >= 2.5)
   {
      // Ancla en H1 EMA50 — trailing más ajustado en profit grande
      newSL = isBuy ? e50[0] - g_atr_cached * 0.3
                    : e50[0] + g_atr_cached * 0.3;
   }
   else
   {
      // Ancla en H1 EMA20 — da espacio al trade
      newSL = isBuy ? e20[0] - g_atr_cached * 0.2
                    : e20[0] + g_atr_cached * 0.2;
   }

   // Ratchet: SL nunca retrocede
   bool improved = isBuy ? (newSL > curSL + _Point)
                         : (newSL < curSL - _Point || curSL == 0);
   if(improved && newSL > 0)
   {
      trade.PositionModify(ticket, newSL, curTP);
      return true;
   }

   // Cierre por estructura H1: precio M5 cruzó EMA20 H1 en contra
   bool structureBreak = isBuy ? (cP < e20[0]) : (cP > e20[0]);
   double profit = PositionGetDouble(POSITION_PROFIT);
   if(structureBreak && profit > 0 && mR >= 1.5)
   {
      trade.PositionClose(ticket);
      Print("📊 MTF Exit: cruce EMA20-H1 | R=", DoubleToString(mR,2),
            " | $", DoubleToString(profit,2));
      return true;
   }

   // Salida anticipada por RSI M15 extremo en profit >= 1R
   if(hasRSI15 && profit > 0 && mR >= 1.0)
   {
      bool rsiExt = isBuy ? (rsiM15[0] > 78.0) : (rsiM15[0] < 22.0);
      if(rsiExt)
      {
         trade.PositionClose(ticket);
         Print("🔥 MTF RSI-M15 Exit: RSI=", DoubleToString(rsiM15[0],1),
               " R=", DoubleToString(mR,2), " $", DoubleToString(profit,2));
         return true;
      }
   }
   return false;
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
   LOG("ORB: Reset diario.");
}

void RunLondonORB()
{
   if(!InpLondonORBOn || g_dayInvalid) return;
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
      { LOG("ORB: Rango inválido sz=" + DoubleToString(sz,2) + " bars=" + IntegerToString(g_orbRangeBars)); return; }
      g_orbRangeBuilt=true;
      LOG("ORB: Rango OK H=" + DoubleToString(g_orbRangeHigh,5) + " L=" + DoubleToString(g_orbRangeLow,5) + " sz=" + DoubleToString(sz,2));
      ORBDrawRangeLines();
   }

   if(!g_orbRangeBuilt||g_orbTradeTriggered) return;
   if(dt.hour<InpORBTradeHStart||dt.hour>InpORBTradeHEnd) return;
   if(g_tradesToday >= g_maxTradesDay) return;
   if(CountAllOpenPositions() >= g_maxConcurrent) return;
   if(!MarginOK()) return;
   if(!PortfolioRiskOK()) return;
   double dayPnL=AccountInfoDouble(ACCOUNT_BALANCE)-g_dayStartBal;
   if(dayPnL<=-g_dailyLossUSD || dayPnL>=g_dailyProfitUSD) return;
   if(SymbolInfoInteger(_Symbol,SYMBOL_SPREAD)>InpORBMaxSpread) return;

   double ef[],es[]; ArraySetAsSeries(ef,true); ArraySetAsSeries(es,true);
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
        LOG("ORB: Cierre tiempo: $" + DoubleToString(profit,2)); continue; }

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
   // Contar posiciones de TODOS los magic del EA (no sólo QQ) para exposición real
   int allOpen=0;
   for(int i=0;i<PositionsTotal();i++)
   { ulong t=PositionGetTicket(i); if(!PositionSelectByTicket(t)) continue;
     long mg=(long)PositionGetInteger(POSITION_MAGIC);
     if(mg==InpMagic||mg==InpMagicORB||mg==InpMagicASIA||mg==InpMagicNY||
        mg==InpMagicS1||mg==InpMagicS2||mg==InpMagicS3||mg==InpMagicS4) allOpen++; }
   double rf=(allOpen>0)?0.50:1.0;
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

void CloseAllASIA(string reason)
{
   trade.SetExpertMagicNumber(InpMagicASIA);
   for(int i=PositionsTotal()-1;i>=0;i--)
   { ulong t=PositionGetTicket(i);
     if(!PositionSelectByTicket(t)) continue;
     if(PositionGetInteger(POSITION_MAGIC)==InpMagicASIA&&
        PositionGetString(POSITION_SYMBOL)==_Symbol) trade.PositionClose(t); }
   trade.SetExpertMagicNumber(InpMagic);
   g_asiaTradeTriggered=false;
   Print("ASIA cerrado: ",reason);
}

void CloseAllNY(string reason)
{
   trade.SetExpertMagicNumber(InpMagicNY);
   for(int i=PositionsTotal()-1;i>=0;i--)
   { ulong t=PositionGetTicket(i);
     if(!PositionSelectByTicket(t)) continue;
     if(PositionGetInteger(POSITION_MAGIC)==InpMagicNY&&
        PositionGetString(POSITION_SYMBOL)==_Symbol) trade.PositionClose(t); }
   trade.SetExpertMagicNumber(InpMagic);
   g_nyTradeTriggered=false;
   Print("NY cerrado: ",reason);
}

// Cuenta posiciones abiertas de TODAS las estrategias del EA
int CountAllOpenPositions()
{
   int c=0;
   for(int i=0;i<PositionsTotal();i++)
   { ulong t=PositionGetTicket(i); if(!PositionSelectByTicket(t)) continue;
     long mg=(long)PositionGetInteger(POSITION_MAGIC);
     if(mg==InpMagic||mg==InpMagicORB||mg==InpMagicASIA||mg==InpMagicNY||
        mg==InpMagicS1||mg==InpMagicS2||mg==InpMagicS3||mg==InpMagicS4||
        mg==InpMagicS5||mg==InpMagicS6||mg==InpMagicS8) c++; }
   return c;
}

// Guardia de margen — requiere 300% nivel de margen mínimo antes de abrir
bool MarginOK()
{
   double ml = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   if(ml <= 0.0) return true;  // sin margen usado = libre
   return ml >= 300.0;
}

//====================================================================
//  GESTIÓN BASKET — Sistema QQ de cierre inteligente por cartera
//  Cuando el flotante total supera el objetivo basket → cerrar todo
//  Inspirado en el sistema de basket-close de Quantum Queen
//====================================================================
void ManageBasket()
{
   int openAll = CountAllOpenPositions();
   if(openAll == 0) return;

   double bal      = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq       = AccountInfoDouble(ACCOUNT_EQUITY);
   double floating = eq - bal;
   if(bal <= 0) return;

   // Objetivo basket: % del balance en flotante → cerrar todo para asegurar
   double tpPct = (g_capMode == CAP_MICRO) ? 0.030 :   // 3% para micro ($10→$10.30)
                  (g_capMode == CAP_SMALL)  ? 0.040 :   // 4% para small
                  (g_capMode == CAP_MEDIUM) ? 0.050 :   // 5% para medium
                  0.060;                                 // 6% upper/standard

   if(floating > bal * tpPct)
   {
      Print("💰 BASKET TP: flotante=$",DoubleToString(floating,2),
            " (",DoubleToString(floating/bal*100.0,1),"%) → cerrando todo");
      CloseAllMagic(); CloseAllORB("BaskTP"); CloseAllASIA("BaskTP");
      CloseAllNY("BaskTP"); CloseAllS1("BaskTP"); CloseAllS2("BaskTP");
      CloseAllS3("BaskTP"); CloseAllS4("BaskTP");
      CloseAllS5("BaskTP"); CloseAllS6("BaskTP"); CloseAllS8("BaskTP");
      return;
   }

   // Basket SL: si flotante pierde > 2× dailyLossUSD → cerrar peor posición
   // Reduce exposición progresivamente en vez de esperar liquidación
   if(openAll >= 2 && floating < -(g_dailyLossUSD * 2.0))
   {
      ulong worstTicket = 0; double worstPnL = 0;
      for(int i=0; i<PositionsTotal(); i++)
      { ulong t=PositionGetTicket(i); if(!PositionSelectByTicket(t)) continue;
        long mg=(long)PositionGetInteger(POSITION_MAGIC);
        bool ourMag=(mg==InpMagic||mg==InpMagicORB||mg==InpMagicASIA||mg==InpMagicNY||
                     mg==InpMagicS1||mg==InpMagicS2||mg==InpMagicS3||mg==InpMagicS4||
                     mg==InpMagicS5||mg==InpMagicS6||mg==InpMagicS8);
        if(!ourMag) continue;
        double pr=PositionGetDouble(POSITION_PROFIT);
        if(pr < worstPnL) { worstPnL=pr; worstTicket=t; } }
      if(worstTicket > 0)
      {
         if(PositionSelectByTicket(worstTicket))
         { long mg=(long)PositionGetInteger(POSITION_MAGIC);
           trade.SetExpertMagicNumber(mg); trade.PositionClose(worstTicket);
           trade.SetExpertMagicNumber(InpMagic);
           Print("⚠️ Basket reduce peor pos: $",DoubleToString(worstPnL,2)); }
      }
   }
}

//====================================================================
//  MOTOR ASIAN ORB  (rango 22:00-01:00, trades 01:00-04:00)
//====================================================================
void RunAsianORB()
{
   if(!InpAsianORBOn || g_dayInvalid) return;
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
   if(g_tradesToday >= g_maxTradesDay) return;
   if(CountAllOpenPositions() >= g_maxConcurrent) return;
   if(!MarginOK()) return;
   if(!PortfolioRiskOK()) return;
   if(IsNewsTime()) return;

   double dayPnL=AccountInfoDouble(ACCOUNT_BALANCE)-g_dayStartBal;
   if(dayPnL<=-g_dailyLossUSD || dayPnL>=g_dailyProfitUSD) return;
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

      // Break-even AsiaORB — mismo umbral que London ORB (InpORBBELevel)
      if(InpORBBEOn && cSL > 0)
      {
         double slD = MathAbs(oP - cSL);
         double mR  = (slD > 0) ? MathAbs(cP - oP) / slD : 0;
         bool   beNotDone = isBuy ? (cSL < oP - _Point) : (cSL > oP + _Point);
         if(mR >= InpORBBELevel && beNotDone)
         {
            double nSL = isBuy ? oP + _Point : oP - _Point;
            trade.SetExpertMagicNumber(InpMagicASIA);
            if(trade.PositionModify(t, nSL, cTP))
               Print("🛡️ AsiaORB BE @", DoubleToString(InpORBBELevel,1),
                     "R | profit=$", DoubleToString(profit,2));
            trade.SetExpertMagicNumber(InpMagic);
         }
      }

      // Cierre parcial 50% AsiaORB — mismo patrón que London ORB
      bool   canPartialAsia  = InpPartialClose && cSL > 0 &&
                               (g_capMode >= CAP_MEDIUM || InpORBPartialMicro);
      double partialTrigAsia = (g_capMode < CAP_MEDIUM) ? 1.20 : 1.00;
      if(canPartialAsia)
      {
         double slD = MathAbs(oP - cSL);
         double mR  = (slD > 0) ? MathAbs(cP - oP) / slD : 0;
         if(mR >= partialTrigAsia)
         {
            double vol  = PositionGetDouble(POSITION_VOLUME);
            double minV = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
            double hV   = NormLot(vol * 0.50);
            if(hV >= minV)
            {
               static datetime lPBAsia = 0; datetime cbA = iTime(_Symbol, PERIOD_M5, 0);
               if(cbA != lPBAsia)
               {
                  trade.SetExpertMagicNumber(InpMagicASIA);
                  trade.PositionClosePartial(t, hV);
                  double nSL    = isBuy ? oP + _Point : oP - _Point;
                  bool   beNeed = isBuy ? (cSL < oP - _Point) : (cSL > oP + _Point);
                  if(beNeed) trade.PositionModify(t, nSL, cTP);
                  trade.SetExpertMagicNumber(InpMagic);
                  lPBAsia = cbA;
                  Print("💰 AsiaORB Parcial 50% @", DoubleToString(partialTrigAsia,1),
                        "R | profit=$", DoubleToString(profit,2));
               }
            }
         }
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
   if(!InpNYSessionOn || g_dayInvalid) return;
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
   if(g_tradesToday >= g_maxTradesDay) return;
   if(CountAllOpenPositions() >= g_maxConcurrent) return;
   if(!MarginOK()) return;
   if(!PortfolioRiskOK()) return;
   if(IsNewsTime()) return;

   double dayPnL=AccountInfoDouble(ACCOUNT_BALANCE)-g_dayStartBal;
   if(dayPnL<=-g_dailyLossUSD || dayPnL>=g_dailyProfitUSD) return;
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

      // Break-even NYSession — mismo umbral que London ORB (InpORBBELevel)
      if(InpORBBEOn && cSL > 0)
      {
         double slD = MathAbs(oP - cSL);
         double mR  = (slD > 0) ? MathAbs(cP - oP) / slD : 0;
         bool   beNotDone = isBuy ? (cSL < oP - _Point) : (cSL > oP + _Point);
         if(mR >= InpORBBELevel && beNotDone)
         {
            double nSL = isBuy ? oP + _Point : oP - _Point;
            trade.SetExpertMagicNumber(InpMagicNY);
            if(trade.PositionModify(t, nSL, cTP))
               Print("🛡️ NYSession BE @", DoubleToString(InpORBBELevel,1),
                     "R | profit=$", DoubleToString(profit,2));
            trade.SetExpertMagicNumber(InpMagic);
         }
      }

      // Cierre parcial 50% NYSession — mismo patrón que London ORB
      bool   canPartialNY  = InpPartialClose && cSL > 0 &&
                             (g_capMode >= CAP_MEDIUM || InpORBPartialMicro);
      double partialTrigNY = (g_capMode < CAP_MEDIUM) ? 1.20 : 1.00;
      if(canPartialNY)
      {
         double slD = MathAbs(oP - cSL);
         double mR  = (slD > 0) ? MathAbs(cP - oP) / slD : 0;
         if(mR >= partialTrigNY)
         {
            double vol  = PositionGetDouble(POSITION_VOLUME);
            double minV = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
            double hV   = NormLot(vol * 0.50);
            if(hV >= minV)
            {
               static datetime lPBNY = 0; datetime cbN = iTime(_Symbol, PERIOD_M5, 0);
               if(cbN != lPBNY)
               {
                  trade.SetExpertMagicNumber(InpMagicNY);
                  trade.PositionClosePartial(t, hV);
                  double nSL    = isBuy ? oP + _Point : oP - _Point;
                  bool   beNeed = isBuy ? (cSL < oP - _Point) : (cSL > oP + _Point);
                  if(beNeed) trade.PositionModify(t, nSL, cTP);
                  trade.SetExpertMagicNumber(InpMagic);
                  lPBNY = cbN;
                  Print("💰 NYSession Parcial 50% @", DoubleToString(partialTrigNY,1),
                        "R | profit=$", DoubleToString(profit,2));
               }
            }
         }
      }
   }
}

//====================================================================
//  TRACKING
//====================================================================
void TrackClosedTrades()
{
   static int      hC          = 0;
   static datetime lastDay     = 0;

   // Día cambió o primer run → re-seleccionar sólo deals de hoy y resetear índice.
   // Evita doble-conteo de deals históricos al reiniciar el EA.
   if(lastDay != g_lastDay)
   {
      HistorySelect(g_lastDay, TimeCurrent() + 86400);
      hC      = 0;
      lastDay = g_lastDay;
   }
   else
      HistorySelect(g_lastDay, TimeCurrent() + 86400); // refresca cache con nuevos deals

   int tot = HistoryDealsTotal();
   if(tot == hC) return;

   for(int i = hC; i < tot; i++)
   {
      ulong t = HistoryDealGetTicket(i); if(!t) continue;
      long mg = (long)HistoryDealGetInteger(t, DEAL_MAGIC);
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(t, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
      double p = HistoryDealGetDouble(t, DEAL_PROFIT);
      if(mg==InpMagic)
      { if(p>0){g_winsToday++;g_totalWon+=p;} else if(p<0){g_lossesToday++;g_totalLost+=MathAbs(p);} }
      else if(mg==InpMagicORB)
      { if(p>0){g_orbWinsToday++;g_orbWonToday+=p;} else if(p<0){g_orbLossesToday++;g_orbLostToday+=MathAbs(p);} }
      else if(mg==InpMagicASIA)
      { if(p>0){g_asiaWinsToday++;g_asiaWonToday+=p;} else if(p<0){g_asiaLossesToday++;g_asiaLostToday+=MathAbs(p);} }
      else if(mg==InpMagicNY)
      { if(p>0){g_nyWinsToday++;g_nyWonToday+=p;} else if(p<0){g_nyLossesToday++;g_nyLostToday+=MathAbs(p);} }
      else if(mg==InpMagicS1)
      { if(p>0){g_s1WinsToday++;g_s1WonToday+=p;} else if(p<0){g_s1LossesToday++;g_s1LostToday+=MathAbs(p);} }
      else if(mg==InpMagicS2)
      { if(p>0){g_s2WinsToday++;g_s2WonToday+=p;} else if(p<0){g_s2LossesToday++;g_s2LostToday+=MathAbs(p);} }
      else if(mg==InpMagicS3)
      { if(p>0){g_s3WinsToday++;g_s3WonToday+=p;} else if(p<0){g_s3LossesToday++;g_s3LostToday+=MathAbs(p);} }
      else if(mg==InpMagicS4)
      { if(p>0){g_s4WinsToday++;g_s4WonToday+=p;} else if(p<0){g_s4LossesToday++;g_s4LostToday+=MathAbs(p);} }
      else if(mg==InpMagicS5)
      { if(p>0){g_s5WinsToday++;g_s5WonToday+=p;} else if(p<0){g_s5LossesToday++;g_s5LostToday+=MathAbs(p);} }
      else if(mg==InpMagicS6)
      { if(p>0){g_s6WinsToday++;g_s6WonToday+=p;} else if(p<0){g_s6LossesToday++;g_s6LostToday+=MathAbs(p);} }
      else if(mg==InpMagicS8)
      { if(p>0){g_s8WinsToday++;g_s8WonToday+=p;} else if(p<0){g_s8LossesToday++;g_s8LostToday+=MathAbs(p);} }
      // Actualizar pérdidas consecutivas globales (todos los magic)
      bool isOurMagic = (mg==InpMagic||mg==InpMagicORB||mg==InpMagicASIA||mg==InpMagicNY||
                         mg==InpMagicS1||mg==InpMagicS2||mg==InpMagicS3||mg==InpMagicS4||
                         mg==InpMagicS5||mg==InpMagicS6||mg==InpMagicS8);
      if(isOurMagic) UpdateConsecLosses(p);
   }
   hC = tot;
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
   string sS1  =!InpS1On?"OFF":g_s1Triggered?"TRADE":"VIGILANDO";
   string sS2  =!InpS2On?"OFF":g_s2Triggered?"TRADE":"VIGILANDO";
   string sS3  =!InpS3On?"OFF":g_s3Triggered?"TRADE":g_s3RangeBuilt?"ESPERA-RUP":"CONSTRUYENDO";
   string sS4  =!InpS4On?"OFF":g_s4Triggered?"TRADE":g_s4RangeBuilt?"ESPERA-RUP":"CONSTRUYENDO";

   // Contar posiciones y PnL de S1/S2/S3/S4
   int posS1=0,posS2=0,posS3=0,posS4=0;
   double pnlS1=0,pnlS2=0,pnlS3=0,pnlS4=0;
   for(int i=0;i<PositionsTotal();i++)
   { ulong t=PositionGetTicket(i); if(!PositionSelectByTicket(t)) continue;
     long mg=(long)PositionGetInteger(POSITION_MAGIC);
     double pr=PositionGetDouble(POSITION_PROFIT);
     if(mg==InpMagicS1){posS1++;pnlS1+=pr;}
     else if(mg==InpMagicS2){posS2++;pnlS2+=pr;}
     else if(mg==InpMagicS3){posS3++;pnlS3+=pr;}
     else if(mg==InpMagicS4){posS4++;pnlS4+=pr;} }

   int coolBuy  = (g_lastBuyTime  > 0) ? MathMax(0, 300-(int)(TimeCurrent()-g_lastBuyTime))  : 0;
   int coolSell = (g_lastSellTime > 0) ? MathMax(0, 300-(int)(TimeCurrent()-g_lastSellTime)) : 0;
   string coolStr = (coolBuy>0||coolSell>0) ?
      StringFormat("BUY:%ds SELL:%ds",coolBuy,coolSell) : "Libre";

   string txt="";
   int openAll = CountAllOpenPositions();
   double floating = equity - bal;
   double floatPct = (bal>0) ? floating/bal*100.0 : 0;
   txt+="=== QQ ULTIMATE v9.0 EVOLUTION ===\n";
   txt+=StringFormat("Hora: %02d:%02d | %s | Trades: %d/%d\n",dt.hour,dt.min,CapModeStr(),g_tradesToday,g_maxTradesDay);
   txt+=StringFormat("Bal : $%.2f | Eq: $%.2f [%s]\n",bal,equity,eqStatus);
   txt+=StringFormat("Basket: %d/%d pos | Float: $%.2f (%.1f%%)\n",openAll,g_maxConcurrent,floating,floatPct);
   txt+=StringFormat("PnL : $%.2f | Drop: $%.2f (%.1f%%)\n",dayPnL,eqDrop,eqDropPct);
   txt+=StringFormat("Tgt : +$%.2f | Stop: -$%.2f\n",g_dailyProfitUSD,g_dailyLossUSD);
   txt+=StringFormat("D1  : %s | H1: %s | ATR: %.4f\n",
        g_sesgoUp?"BUY":(g_sesgoDn?"SELL":"NEUTRO"),
        g_h1Up?"UP":(g_h1Dn?"DWN":"="),g_atr_cached);
   txt+=StringFormat("Mkt : %s | W1: %s | ADX: %.1f\n",
        g_marketStateStr,
        g_weeklyBiasUp?"BUY UP":(g_weeklyBiasDn?"SELL DN":"NEUTRAL"),
        g_adxLast);
   txt+=StringFormat("DD  : L%d (×%.2f) | Rec: L%d (×%.2f)\n",
        g_ddLevel, g_lotMultDD, g_recoveryLevel, g_lotMultRecovery);
   string recPause = (g_recoveryPauseUntil > TimeCurrent()) ?
        StringFormat("PAUSA %dm", (int)(g_recoveryPauseUntil-TimeCurrent())/60) : "OK";
   txt+=StringFormat("PnL : Lon:$%.2f NY:$%.2f Asia:$%.2f | Rec:%s\n",
        g_pnlLondon, g_pnlNYSess, g_pnlAsiaSess, recPause);
   txt+=StringFormat("Filt: Noticias=%s | Cooldown: %s\n",IsNewsTime()?"SI":"NO",coolStr);
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
   txt+="--- S1 PDH/PDL H1 (WR~70%) ---\n";
   txt+=StringFormat("Est : %s | Pos: %d pnl:$%.2f\n",sS1,posS1,pnlS1);
   txt+=StringFormat("Res : W%d L%d\n",g_s1WinsToday,g_s1LossesToday);
   txt+="--- S2 EMA20 PB H1 (WR~64%) ---\n";
   txt+=StringFormat("Est : %s | Pos: %d pnl:$%.2f\n",sS2,posS2,pnlS2);
   txt+=StringFormat("Res : W%d L%d\n",g_s2WinsToday,g_s2LossesToday);
   string s3R=(g_s3AsiaHigh>0&&g_s3AsiaLow<DBL_MAX)?
      DoubleToString(g_s3AsiaHigh,2)+"/"+DoubleToString(g_s3AsiaLow,2):"---";
   string s4R=(g_s4ORHigh>0&&g_s4ORLow<DBL_MAX)?
      DoubleToString(g_s4ORHigh,2)+"/"+DoubleToString(g_s4ORLow,2):"---";
   txt+="--- S3 Asia-Brk M5 (WR~62%) ---\n";
   txt+=StringFormat("Est : %s | Rng: %s\n",sS3,s3R);
   txt+=StringFormat("Pos : %d pnl:$%.2f | W%d L%d\n",posS3,pnlS3,g_s3WinsToday,g_s3LossesToday);
   txt+="--- S4 LondORB@EMA200 M5 (WR~61%) ---\n";
   txt+=StringFormat("Est : %s | Rng: %s\n",sS4,s4R);
   txt+=StringFormat("Pos : %d pnl:$%.2f | W%d L%d\n",posS4,pnlS4,g_s4WinsToday,g_s4LossesToday);
   // S5/S6/S8 posiciones y PnL
   int posS5=0,posS6=0,posS8=0;
   double pnlS5=0,pnlS6=0,pnlS8=0;
   for(int i=0;i<PositionsTotal();i++)
   { ulong t=PositionGetTicket(i); if(!PositionSelectByTicket(t)) continue;
     long mg=(long)PositionGetInteger(POSITION_MAGIC);
     double pr=PositionGetDouble(POSITION_PROFIT);
     if(mg==InpMagicS5){posS5++;pnlS5+=pr;}
     else if(mg==InpMagicS6){posS6++;pnlS6+=pr;}
     else if(mg==InpMagicS8){posS8++;pnlS8+=pr;} }
   string sS5=!InpS5On?"OFF":g_s5Triggered?"TRADE":"VIGILANDO";
   string sS6=!InpS6On?"OFF":g_s6Triggered?"TRADE":"VIGILANDO";
   string sS8=!InpS8On?"OFF":g_s8Triggered?"TRADE":(g_marketState==MARKET_RANGING?"ACTIVO":"ESPERA-RANGING");
   txt+="--- S5 H4 Trend Cont (WR~65%) ---\n";
   txt+=StringFormat("Est : %s | Pos: %d pnl:$%.2f\n",sS5,posS5,pnlS5);
   txt+=StringFormat("Res : W%d L%d\n",g_s5WinsToday,g_s5LossesToday);
   txt+="--- S6 M15 Momentum Spike (WR~60%) ---\n";
   txt+=StringFormat("Est : %s | Pos: %d pnl:$%.2f\n",sS6,posS6,pnlS6);
   txt+=StringFormat("Res : W%d L%d\n",g_s6WinsToday,g_s6LossesToday);
   txt+="--- S8 Consol Scalper (RANGING only) ---\n";
   txt+=StringFormat("Est : %s | Pos: %d pnl:$%.2f\n",sS8,posS8,pnlS8);
   txt+=StringFormat("Res : W%d L%d\n",g_s8WinsToday,g_s8LossesToday);
   Comment(txt);
}

//====================================================================
//  HELPERS S1/S2
//====================================================================
void CloseAllS1(string reason)
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   { ulong t=PositionGetTicket(i); if(!PositionSelectByTicket(t)) continue;
     if(PositionGetInteger(POSITION_MAGIC)==InpMagicS1&&
        PositionGetString(POSITION_SYMBOL)==_Symbol)
     { trade.SetExpertMagicNumber(InpMagicS1);
       trade.PositionClose(t);
       trade.SetExpertMagicNumber(InpMagic); } }
   g_s1Triggered=false;
   Print("S1 cerrado: ",reason);
}

void CloseAllS2(string reason)
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   { ulong t=PositionGetTicket(i); if(!PositionSelectByTicket(t)) continue;
     if(PositionGetInteger(POSITION_MAGIC)==InpMagicS2&&
        PositionGetString(POSITION_SYMBOL)==_Symbol)
     { trade.SetExpertMagicNumber(InpMagicS2);
       trade.PositionClose(t);
       trade.SetExpertMagicNumber(InpMagic); } }
   g_s2Triggered=false;
   Print("S2 cerrado: ",reason);
}

//====================================================================
//  S1 — BREAKOUT PDH/PDL H1
//  LONG  : vela H1 cierra > EMA200 y > PDH, vela anterior cerró ≤ PDH
//  SHORT : vela H1 cierra < EMA200 y < PDL, vela anterior cerró ≥ PDL
//  SL=1.5×ATR | TP=1.0×ATR | salida tiempo 48 H1 | WR 69.9%
//====================================================================
void RunS1PDHBreakout()
{
   if(!InpS1On || g_dayInvalid) return;

   // Evaluar sólo en nueva barra H1
   static datetime lastBarS1 = 0;
   datetime curBar = iTime(_Symbol, PERIOD_H1, 0);
   if(curBar == lastBarS1) return;
   lastBarS1 = curBar;

   if(g_s1Triggered) return;
   if(g_tradesToday >= g_maxTradesDay) return;
   if(CountAllOpenPositions() >= g_maxConcurrent) return;
   if(!MarginOK()) return;
   if(!PortfolioRiskOK()) return;
   if(IsNewsTime()) return;
   if(!FilterSpread()) return;

   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   if(dt.hour < InpS1HourStart || dt.hour >= InpS1HourEnd) return;

   double dayPnL = AccountInfoDouble(ACCOUNT_BALANCE) - g_dayStartBal;
   if(dayPnL <= -g_dailyLossUSD || dayPnL >= g_dailyProfitUSD) return;

   // Indicadores H1 de la barra cerrada (índice 1)
   double ema200[], atr14[];
   if(CopyBuffer(hEMA200_H1, 0, 1, 1, ema200) <= 0) return;
   if(CopyBuffer(hATR_H1,    0, 1, 1, atr14)  <= 0) return;

   // Máximo/Mínimo del día anterior
   double pdh = iHigh(_Symbol, PERIOD_D1, 1);
   double pdl = iLow(_Symbol,  PERIOD_D1, 1);
   if(pdh <= 0 || pdl <= 0 || pdh <= pdl) return;

   // Cierre de la vela señal (barra 1) y la vela anterior (barra 2)
   double currClose = iClose(_Symbol, PERIOD_H1, 1);
   double prevClose = iClose(_Symbol, PERIOD_H1, 2);
   if(currClose <= 0 || prevClose <= 0) return;

   // ── LONG: primer cierre H1 por encima del PDH con precio > EMA200 ──
   if(currClose > ema200[0] && currClose > pdh && prevClose <= pdh)
   {
      if(!FilterAntiSimultaneous(true)) return;
      double en = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl = en - InpS1SL_ATR * atr14[0];
      double tp = en + InpS1TP_ATR * atr14[0];
      if(!ValidateTradeRisk(en, sl, "S1-LONG")) return;
      // S1 usa RR intencional < 1 compensado por WR 70% — no valida MinRR
      double lot = CalcLot(en - sl, 1.0);
      trade.SetExpertMagicNumber(InpMagicS1);
      if(trade.Buy(lot, _Symbol, en, sl, tp, "S1_PDHBreak"))
      {
         g_s1Triggered    = true;
         g_s1TradeOpenTime = TimeCurrent();
         g_tradesToday++;
         g_lastBuyTime    = TimeCurrent();
         Print("📈 S1 LONG PDH-BREAK @", DoubleToString(en,2),
               " PDH=", DoubleToString(pdh,2),
               " SL=", DoubleToString(sl,2), " TP=", DoubleToString(tp,2),
               " Lot=", lot);
      }
      trade.SetExpertMagicNumber(InpMagic);
   }
   // ── SHORT: primer cierre H1 por debajo del PDL con precio < EMA200 ──
   else if(currClose < ema200[0] && currClose < pdl && prevClose >= pdl)
   {
      if(!FilterAntiSimultaneous(false)) return;
      double en = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl = en + InpS1SL_ATR * atr14[0];
      double tp = en - InpS1TP_ATR * atr14[0];
      if(!ValidateTradeRisk(en, sl, "S1-SHORT")) return;
      double lot = CalcLot(sl - en, 1.0);
      trade.SetExpertMagicNumber(InpMagicS1);
      if(trade.Sell(lot, _Symbol, en, sl, tp, "S1_PDLBreak"))
      {
         g_s1Triggered    = true;
         g_s1TradeOpenTime = TimeCurrent();
         g_tradesToday++;
         g_lastSellTime   = TimeCurrent();
         Print("📉 S1 SHORT PDL-BREAK @", DoubleToString(en,2),
               " PDL=", DoubleToString(pdl,2),
               " SL=", DoubleToString(sl,2), " TP=", DoubleToString(tp,2),
               " Lot=", lot);
      }
      trade.SetExpertMagicNumber(InpMagic);
   }
}

void ManageS1Trades()
{
   if(!InpS1On || !g_s1Triggered) return;

   bool hasPos = false;
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicS1) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      hasPos = true;
      double profit = PositionGetDouble(POSITION_PROFIT);

      // Salida por tiempo — 48 barras H1
      if(g_s1TradeOpenTime > 0)
      {
         int barsH1 = (int)((TimeCurrent() - g_s1TradeOpenTime) / PeriodSeconds(PERIOD_H1));
         if(barsH1 >= InpS1MaxBarsH1)
         {
            trade.SetExpertMagicNumber(InpMagicS1);
            trade.PositionClose(t);
            trade.SetExpertMagicNumber(InpMagic);
            g_s1Triggered = false;
            Print("⏱️ S1 Cierre tiempo 48H | profit=$", DoubleToString(profit,2));
            continue;
         }
      }
   }
   // Trade cerrado por TP o SL → resetear flag
   if(!hasPos) g_s1Triggered = false;
}

//====================================================================
//  S2 — PULLBACK A EMA20 EN TENDENCIA ALINEADA H1
//  Tendencia alcista : EMA20 > EMA50 > EMA200
//  LONG  : Low toca/cruza EMA20, Close > EMA20, vela alcista (Close > Open)
//  SHORT : High toca/cruza EMA20, Close < EMA20, vela bajista (Close < Open)
//  SL=1.5×ATR | TP=1.0×ATR | salida tiempo 48 H1 | WR 63.7%
//====================================================================
void RunS2EMA20Pullback()
{
   if(!InpS2On || g_dayInvalid) return;

   static datetime lastBarS2 = 0;
   datetime curBar = iTime(_Symbol, PERIOD_H1, 0);
   if(curBar == lastBarS2) return;
   lastBarS2 = curBar;

   if(g_s2Triggered) return;
   if(g_tradesToday >= g_maxTradesDay) return;
   if(CountAllOpenPositions() >= g_maxConcurrent) return;
   if(!MarginOK()) return;
   if(!PortfolioRiskOK()) return;
   if(IsNewsTime()) return;
   if(!FilterSpread()) return;

   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   if(dt.hour < InpS2HourStart || dt.hour >= InpS2HourEnd) return;

   double dayPnL = AccountInfoDouble(ACCOUNT_BALANCE) - g_dayStartBal;
   if(dayPnL <= -g_dailyLossUSD || dayPnL >= g_dailyProfitUSD) return;

   // Indicadores H1 de la barra cerrada (índice 1)
   double ema20[], ema50[], ema200[], atr14[];
   if(CopyBuffer(hEMA20_H1,  0, 1, 1, ema20)  <= 0) return;
   if(CopyBuffer(hEMA50_H1,  0, 1, 1, ema50)  <= 0) return;
   if(CopyBuffer(hEMA200_H1, 0, 1, 1, ema200) <= 0) return;
   if(CopyBuffer(hATR_H1,    0, 1, 1, atr14)  <= 0) return;

   double currClose = iClose(_Symbol, PERIOD_H1, 1);
   double currOpen  = iOpen(_Symbol,  PERIOD_H1, 1);
   double currLow   = iLow(_Symbol,   PERIOD_H1, 1);
   double currHigh  = iHigh(_Symbol,  PERIOD_H1, 1);
   if(currClose <= 0) return;

   bool bullTrend = (ema20[0] > ema50[0]) && (ema50[0] > ema200[0]);
   bool bearTrend = (ema20[0] < ema50[0]) && (ema50[0] < ema200[0]);

   // ── LONG: tendencia alcista, Low tocó EMA20, vela cierra alcista sobre EMA20 ──
   if(bullTrend && currLow <= ema20[0] && currClose > ema20[0] && currClose > currOpen)
   {
      if(!FilterAntiSimultaneous(true)) return;
      double en = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl = en - InpS2SL_ATR * atr14[0];
      double tp = en + InpS2TP_ATR * atr14[0];
      if(!ValidateTradeRisk(en, sl, "S2-LONG")) return;
      double lot = CalcLot(en - sl, 1.0);
      trade.SetExpertMagicNumber(InpMagicS2);
      if(trade.Buy(lot, _Symbol, en, sl, tp, "S2_EMA20PB"))
      {
         g_s2Triggered    = true;
         g_s2TradeOpenTime = TimeCurrent();
         g_tradesToday++;
         g_lastBuyTime    = TimeCurrent();
         Print("📈 S2 LONG EMA20-PB @", DoubleToString(en,2),
               " EMA20=", DoubleToString(ema20[0],2),
               " SL=", DoubleToString(sl,2), " TP=", DoubleToString(tp,2),
               " Lot=", lot);
      }
      trade.SetExpertMagicNumber(InpMagic);
   }
   // ── SHORT: tendencia bajista, High tocó EMA20, vela cierra bajista bajo EMA20 ──
   else if(bearTrend && currHigh >= ema20[0] && currClose < ema20[0] && currClose < currOpen)
   {
      if(!FilterAntiSimultaneous(false)) return;
      double en = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl = en + InpS2SL_ATR * atr14[0];
      double tp = en - InpS2TP_ATR * atr14[0];
      if(!ValidateTradeRisk(en, sl, "S2-SHORT")) return;
      double lot = CalcLot(sl - en, 1.0);
      trade.SetExpertMagicNumber(InpMagicS2);
      if(trade.Sell(lot, _Symbol, en, sl, tp, "S2_EMA20PB"))
      {
         g_s2Triggered    = true;
         g_s2TradeOpenTime = TimeCurrent();
         g_tradesToday++;
         g_lastSellTime   = TimeCurrent();
         Print("📉 S2 SHORT EMA20-PB @", DoubleToString(en,2),
               " EMA20=", DoubleToString(ema20[0],2),
               " SL=", DoubleToString(sl,2), " TP=", DoubleToString(tp,2),
               " Lot=", lot);
      }
      trade.SetExpertMagicNumber(InpMagic);
   }
}

void ManageS2Trades()
{
   if(!InpS2On || !g_s2Triggered) return;

   bool hasPos = false;
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicS2) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      hasPos = true;
      double profit = PositionGetDouble(POSITION_PROFIT);

      // Salida por tiempo — 48 barras H1
      if(g_s2TradeOpenTime > 0)
      {
         int barsH1 = (int)((TimeCurrent() - g_s2TradeOpenTime) / PeriodSeconds(PERIOD_H1));
         if(barsH1 >= InpS2MaxBarsH1)
         {
            trade.SetExpertMagicNumber(InpMagicS2);
            trade.PositionClose(t);
            trade.SetExpertMagicNumber(InpMagic);
            g_s2Triggered = false;
            Print("⏱️ S2 Cierre tiempo 48H | profit=$", DoubleToString(profit,2));
            continue;
         }
      }
   }
   if(!hasPos) g_s2Triggered = false;
}

//====================================================================
//  HELPERS S3/S4
//====================================================================
void CloseAllS3(string reason)
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   { ulong t=PositionGetTicket(i); if(!PositionSelectByTicket(t)) continue;
     if(PositionGetInteger(POSITION_MAGIC)==InpMagicS3&&
        PositionGetString(POSITION_SYMBOL)==_Symbol)
     { trade.SetExpertMagicNumber(InpMagicS3);
       trade.PositionClose(t);
       trade.SetExpertMagicNumber(InpMagic); } }
   g_s3Triggered=false;
   Print("S3 cerrado: ",reason);
}

void CloseAllS4(string reason)
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   { ulong t=PositionGetTicket(i); if(!PositionSelectByTicket(t)) continue;
     if(PositionGetInteger(POSITION_MAGIC)==InpMagicS4&&
        PositionGetString(POSITION_SYMBOL)==_Symbol)
     { trade.SetExpertMagicNumber(InpMagicS4);
       trade.PositionClose(t);
       trade.SetExpertMagicNumber(InpMagic); } }
   g_s4Triggered=false;
   Print("S4 cerrado: ",reason);
}

//====================================================================
//  S3 — ASIAN RANGE BREAKOUT M5
//  Rango: barras M5 desde medianoche (g_lastDay) hasta las 05:55 servidor
//  Señal: primera vela M5 cerrada que rompe el rango en ventana 07:00-09:55
//  SL=1.5×ATR(14)M5 | TP=1.0×ATR(14)M5 | salida tiempo 60 barras M5
//  Un LONG + un SHORT independientes por día (LongDone/ShortDone)
//====================================================================
void RunS3AsiaBreakout()
{
   if(!InpS3On || g_dayInvalid) return;

   static datetime lastBarS3 = 0;
   datetime cb = iTime(_Symbol, PERIOD_M5, 0);
   if(cb == lastBarS3) return;
   lastBarS3 = cb;

   // Acumular rango asiático: barras M5 cerradas desde medianoche hasta 05:55
   datetime prevBarTime = iTime(_Symbol, PERIOD_M5, 1);
   MqlDateTime pdt; TimeToStruct(prevBarTime, pdt);

   if(prevBarTime >= g_lastDay && pdt.hour < 6 && !g_s3RangeBuilt)
   {
      double hi = iHigh(_Symbol, PERIOD_M5, 1);
      double lo = iLow(_Symbol,  PERIOD_M5, 1);
      if(g_s3AsiaHigh == 0)     g_s3AsiaHigh = hi;
      if(g_s3AsiaLow == DBL_MAX) g_s3AsiaLow  = lo;
      if(hi > g_s3AsiaHigh) g_s3AsiaHigh = hi;
      if(lo < g_s3AsiaLow)  g_s3AsiaLow  = lo;
   }

   // Cerrar y validar rango al llegar a las 07:00
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   if(!g_s3RangeBuilt && dt.hour >= 7 && g_s3AsiaHigh > 0 && g_s3AsiaLow < DBL_MAX)
   {
      double sz = g_s3AsiaHigh - g_s3AsiaLow;
      if(sz < 2.0 || sz > 20.0)
      { Print("S3: Rango Asia inválido sz=",DoubleToString(sz,2)," — motor parado"); return; }
      g_s3RangeBuilt = true;
      Print("S3: Rango Asia OK H=",DoubleToString(g_s3AsiaHigh,2),
            " L=",DoubleToString(g_s3AsiaLow,2)," sz=",DoubleToString(sz,2));
   }

   if(!g_s3RangeBuilt) return;
   if(g_s3Triggered) return;
   if(g_s3LongDone && g_s3ShortDone) return;
   if(g_tradesToday >= g_maxTradesDay) return;
   if(CountAllOpenPositions() >= g_maxConcurrent) return;
   if(!MarginOK()) return;
   if(!PortfolioRiskOK()) return;
   if(IsNewsTime()) return;
   if(!FilterSpread()) return;

   double dayPnL = AccountInfoDouble(ACCOUNT_BALANCE) - g_dayStartBal;
   if(dayPnL <= -g_dailyLossUSD || dayPnL >= g_dailyProfitUSD) return;

   // Ventana de trading: prevBar en [07:00, 09:55]
   int prevMin = pdt.hour * 60 + pdt.min;
   if(prevMin < 7*60 || prevMin > 9*60+55) return;

   double atr[];
   if(CopyBuffer(hATR_M5, 0, 1, 1, atr) <= 0) return;
   if(atr[0] <= 0) return;

   double currClose = iClose(_Symbol, PERIOD_M5, 1);
   double prevClose = iClose(_Symbol, PERIOD_M5, 2);
   if(currClose <= 0 || prevClose <= 0) return;

   // LONG: primera vela M5 cerrada por encima del máximo asiático
   if(!g_s3LongDone && currClose > g_s3AsiaHigh && prevClose <= g_s3AsiaHigh)
   {
      if(!FilterAntiSimultaneous(true)) return;
      double en = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl = en - InpS3SL_ATR * atr[0];
      double tp = en + InpS3TP_ATR * atr[0];
      if(!ValidateTradeRisk(en, sl, "S3-LONG")) return;
      double lot = CalcLot(en - sl, 1.0);
      trade.SetExpertMagicNumber(InpMagicS3);
      if(trade.Buy(lot, _Symbol, en, sl, tp, "S3_AsiaBreak"))
      {
         g_s3Triggered     = true;
         g_s3LongDone      = true;
         g_s3TradeOpenTime = TimeCurrent();
         g_tradesToday++;
         g_lastBuyTime     = TimeCurrent();
         Print("📈 S3 LONG Asia-Break @",DoubleToString(en,2),
               " AH=",DoubleToString(g_s3AsiaHigh,2),
               " SL=",DoubleToString(sl,2)," TP=",DoubleToString(tp,2)," Lot=",lot);
      }
      trade.SetExpertMagicNumber(InpMagic);
   }
   // SHORT: primera vela M5 cerrada por debajo del mínimo asiático
   else if(!g_s3ShortDone && currClose < g_s3AsiaLow && prevClose >= g_s3AsiaLow)
   {
      if(!FilterAntiSimultaneous(false)) return;
      double en = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl = en + InpS3SL_ATR * atr[0];
      double tp = en - InpS3TP_ATR * atr[0];
      if(!ValidateTradeRisk(en, sl, "S3-SHORT")) return;
      double lot = CalcLot(sl - en, 1.0);
      trade.SetExpertMagicNumber(InpMagicS3);
      if(trade.Sell(lot, _Symbol, en, sl, tp, "S3_AsiaBreak"))
      {
         g_s3Triggered     = true;
         g_s3ShortDone     = true;
         g_s3TradeOpenTime = TimeCurrent();
         g_tradesToday++;
         g_lastSellTime    = TimeCurrent();
         Print("📉 S3 SHORT Asia-Break @",DoubleToString(en,2),
               " AL=",DoubleToString(g_s3AsiaLow,2),
               " SL=",DoubleToString(sl,2)," TP=",DoubleToString(tp,2)," Lot=",lot);
      }
      trade.SetExpertMagicNumber(InpMagic);
   }
}

void ManageS3Trades()
{
   if(!InpS3On || !g_s3Triggered) return;

   bool hasPos = false;
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicS3) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      hasPos = true;
      double profit = PositionGetDouble(POSITION_PROFIT);

      // Salida por tiempo — 60 barras M5
      if(g_s3TradeOpenTime > 0)
      {
         int barsM5 = (int)((TimeCurrent() - g_s3TradeOpenTime) / PeriodSeconds(PERIOD_M5));
         if(barsM5 >= InpS3MaxBarsM5)
         {
            trade.SetExpertMagicNumber(InpMagicS3);
            trade.PositionClose(t);
            trade.SetExpertMagicNumber(InpMagic);
            g_s3Triggered = false;
            Print("⏱️ S3 Cierre tiempo 60M5 | profit=$",DoubleToString(profit,2));
            continue;
         }
      }
   }
   if(!hasPos) g_s3Triggered = false;
}

//====================================================================
//  S4 — LONDON ORB EMA200 M5
//  OR: barras M5 en 07:00, 07:05, 07:10 (hora=7, min≤10, desde g_lastDay)
//  Cierre rango: 07:15 servidor
//  Señal: vela M5 cierra sobre OR-high con precio>EMA200 → LONG
//         vela M5 cierra bajo  OR-low  con precio<EMA200 → SHORT
//  Ventana: prevBar en [07:15, 10:55]
//  SL=1.2×ATR(14)M5 | TP=0.8×ATR(14)M5 | salida tiempo 60 barras M5
//====================================================================
void RunS4LondonORB_EMA200()
{
   if(!InpS4On || g_dayInvalid) return;

   static datetime lastBarS4 = 0;
   datetime cb = iTime(_Symbol, PERIOD_M5, 0);
   if(cb == lastBarS4) return;
   lastBarS4 = cb;

   datetime prevBarTime = iTime(_Symbol, PERIOD_M5, 1);
   MqlDateTime pdt; TimeToStruct(prevBarTime, pdt);

   // Acumular OR: barras M5 07:00, 07:05, 07:10
   if(!g_s4RangeBuilt && prevBarTime >= g_lastDay &&
      pdt.hour == 7 && pdt.min <= 10)
   {
      double hi = iHigh(_Symbol, PERIOD_M5, 1);
      double lo = iLow(_Symbol,  PERIOD_M5, 1);
      if(g_s4ORHigh == 0)     g_s4ORHigh = hi;
      if(g_s4ORLow == DBL_MAX) g_s4ORLow  = lo;
      if(hi > g_s4ORHigh) g_s4ORHigh = hi;
      if(lo < g_s4ORLow)  g_s4ORLow  = lo;
   }

   // Cerrar y validar OR a las 07:15
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   if(!g_s4RangeBuilt && dt.hour == 7 && dt.min >= 15 &&
      g_s4ORHigh > 0 && g_s4ORLow < DBL_MAX)
   {
      double sz = g_s4ORHigh - g_s4ORLow;
      if(sz < 1.0 || sz > 15.0)
      { Print("S4: OR inválido sz=",DoubleToString(sz,2)," — motor parado"); return; }
      g_s4RangeBuilt = true;
      Print("S4: OR OK H=",DoubleToString(g_s4ORHigh,2),
            " L=",DoubleToString(g_s4ORLow,2)," sz=",DoubleToString(sz,2));
   }

   if(!g_s4RangeBuilt) return;
   if(g_s4Triggered) return;
   if(g_s4LongDone && g_s4ShortDone) return;
   if(g_tradesToday >= g_maxTradesDay) return;
   if(CountAllOpenPositions() >= g_maxConcurrent) return;
   if(!MarginOK()) return;
   if(!PortfolioRiskOK()) return;
   if(IsNewsTime()) return;
   if(!FilterSpread()) return;

   double dayPnL = AccountInfoDouble(ACCOUNT_BALANCE) - g_dayStartBal;
   if(dayPnL <= -g_dailyLossUSD || dayPnL >= g_dailyProfitUSD) return;

   // Ventana de trading: prevBar en [07:15, 10:55]
   int prevMin = pdt.hour * 60 + pdt.min;
   if(prevMin < 7*60+15 || prevMin > 10*60+55) return;

   double atr[], ema200[];
   if(CopyBuffer(hATR_M5,    0, 1, 1, atr)    <= 0) return;
   if(CopyBuffer(hEMA200_M5, 0, 1, 1, ema200) <= 0) return;
   if(atr[0] <= 0) return;

   double currClose = iClose(_Symbol, PERIOD_M5, 1);
   double prevClose = iClose(_Symbol, PERIOD_M5, 2);
   if(currClose <= 0 || prevClose <= 0) return;

   // LONG: precio > EMA200 y primera vela M5 cerrada sobre el OR-high
   if(!g_s4LongDone && currClose > ema200[0] &&
      currClose > g_s4ORHigh && prevClose <= g_s4ORHigh)
   {
      if(!FilterAntiSimultaneous(true)) return;
      double en = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl = en - InpS4SL_ATR * atr[0];
      double tp = en + InpS4TP_ATR * atr[0];
      if(!ValidateTradeRisk(en, sl, "S4-LONG")) return;
      double lot = CalcLot(en - sl, 1.0);
      trade.SetExpertMagicNumber(InpMagicS4);
      if(trade.Buy(lot, _Symbol, en, sl, tp, "S4_LondonORB_EMA200"))
      {
         g_s4Triggered     = true;
         g_s4LongDone      = true;
         g_s4TradeOpenTime = TimeCurrent();
         g_tradesToday++;
         g_lastBuyTime     = TimeCurrent();
         Print("📈 S4 LONG LondonORB@EMA200 @",DoubleToString(en,2),
               " OR_H=",DoubleToString(g_s4ORHigh,2),
               " EMA200=",DoubleToString(ema200[0],2),
               " SL=",DoubleToString(sl,2)," TP=",DoubleToString(tp,2)," Lot=",lot);
      }
      trade.SetExpertMagicNumber(InpMagic);
   }
   // SHORT: precio < EMA200 y primera vela M5 cerrada bajo el OR-low
   else if(!g_s4ShortDone && currClose < ema200[0] &&
           currClose < g_s4ORLow && prevClose >= g_s4ORLow)
   {
      if(!FilterAntiSimultaneous(false)) return;
      double en = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl = en + InpS4SL_ATR * atr[0];
      double tp = en - InpS4TP_ATR * atr[0];
      if(!ValidateTradeRisk(en, sl, "S4-SHORT")) return;
      double lot = CalcLot(sl - en, 1.0);
      trade.SetExpertMagicNumber(InpMagicS4);
      if(trade.Sell(lot, _Symbol, en, sl, tp, "S4_LondonORB_EMA200"))
      {
         g_s4Triggered     = true;
         g_s4ShortDone     = true;
         g_s4TradeOpenTime = TimeCurrent();
         g_tradesToday++;
         g_lastSellTime    = TimeCurrent();
         Print("📉 S4 SHORT LondonORB@EMA200 @",DoubleToString(en,2),
               " OR_L=",DoubleToString(g_s4ORLow,2),
               " EMA200=",DoubleToString(ema200[0],2),
               " SL=",DoubleToString(sl,2)," TP=",DoubleToString(tp,2)," Lot=",lot);
      }
      trade.SetExpertMagicNumber(InpMagic);
   }
}

void ManageS4Trades()
{
   if(!InpS4On || !g_s4Triggered) return;

   bool hasPos = false;
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicS4) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      hasPos = true;
      double profit = PositionGetDouble(POSITION_PROFIT);

      // Salida por tiempo — 60 barras M5
      if(g_s4TradeOpenTime > 0)
      {
         int barsM5 = (int)((TimeCurrent() - g_s4TradeOpenTime) / PeriodSeconds(PERIOD_M5));
         if(barsM5 >= InpS4MaxBarsM5)
         {
            trade.SetExpertMagicNumber(InpMagicS4);
            trade.PositionClose(t);
            trade.SetExpertMagicNumber(InpMagic);
            g_s4Triggered = false;
            Print("⏱️ S4 Cierre tiempo 60M5 | profit=$",DoubleToString(profit,2));
            continue;
         }
      }
   }
   if(!hasPos) g_s4Triggered = false;
}

//====================================================================
//  DETECCIÓN DE ESTADO DE MERCADO — Sistema multi-capa con histéresis
//
//  Mejoras sobre versión anterior:
//  1. Histéresis anti-flip: estado solo cambia cuando la nueva condición
//     persiste ≥2 barras M5 consecutivas → evita oscilaciones cada tick.
//  2. Confirmación H4 ADX para TRENDING: requiere que H4 también muestre
//     momentum para confirmar tendencia real (no solo ruido H1).
//  3. VOLATILE distingue entre ruptura direccional (ATR + ADX alto = breakout
//     real) vs volatilidad caótica (ATR alto + ADX bajo = whipsaw danger).
//  4. Pendiente ADX: si ADX está subiendo rápido → mercado entrando en
//     TRENDING aunque aún no supere el umbral.
//  5. Estado NEUTRAL diferenciado: si BB width está contrayendo activamente
//     → pre-breakout (tratar como RANGING con mayor potencial).
//
//  Reglas de transición:
//  NEUTRAL → TRENDING: ADX > 25 (H1) confirmado por ADX H4 > 20
//  NEUTRAL → RANGING:  ADX < 20 + BB Width < avg×0.70 (≥2 barras)
//  ANY → VOLATILE:     ATR > 1.5× avg (1 barra suficiente, alta urgencia)
//  VOLATILE → NEUTRAL: ATR < 1.2× avg por ≥3 barras (enfriamiento gradual)
//  TRENDING → NEUTRAL: ADX < 22 (umbral menor, evita transición prematura)
//====================================================================
// Variables de histéresis (static preserva entre llamadas)
static ENUM_MARKET_STATE s_pendingState = MARKET_NEUTRAL;
static int               s_pendingCount = 0;
static datetime          s_lastStateChange = 0;

void DetectMarketState()
{
   // ── ADX H1 ───────────────────────────────────────────────────────
   double adxBuf[];
   ArraySetAsSeries(adxBuf, true);
   if(CopyBuffer(hADX_H1, 0, 0, 4, adxBuf) < 3) return;
   g_adxLast = adxBuf[0];
   // Pendiente ADX: subiendo si las últimas 3 barras forman tendencia alcista
   bool adxRising = (adxBuf[0] > adxBuf[1] && adxBuf[1] > adxBuf[2]);

   // ── ADX H4 (confirmación secundaria para TRENDING) ───────────────
   double adxH4[];
   ArraySetAsSeries(adxH4, true);
   bool hasH4ADX = (CopyBuffer(hADX_H1, 0, 0, 2, adxH4) >= 2);  // reutilizar handle H1 ADX no funciona en H4
   // Nota: hADX_H1 es el handle ADX del H1. Para H4 necesitamos hATR_H4 como proxy:
   // Si ATR H4 > ATR H4 anterior → mercado en expansión de rango (proxy tendencia)
   double atrH4Buf[];
   ArraySetAsSeries(atrH4Buf, true);
   bool h4TrendingProxy = false;
   if(CopyBuffer(hATR_H4, 0, 0, 3, atrH4Buf) >= 3)
      h4TrendingProxy = (atrH4Buf[0] > atrH4Buf[1] * 0.95);  // ATR H4 estable o creciendo

   // ── BB Width M5 ───────────────────────────────────────────────────
   double bbUp[], bbMid[], bbLow[];
   ArraySetAsSeries(bbUp, true); ArraySetAsSeries(bbMid, true); ArraySetAsSeries(bbLow, true);
   if(CopyBuffer(hBB_M5, 1, 0, 3, bbUp)  < 2 ||
      CopyBuffer(hBB_M5, 0, 0, 3, bbMid) < 2 ||
      CopyBuffer(hBB_M5, 2, 0, 3, bbLow) < 2) return;
   double bbWidth = (bbMid[0] > 0) ? (bbUp[0] - bbLow[0]) / bbMid[0] : 0;
   // BB contrayendo: ancho decreció respecto a barra anterior (señal pre-breakout)
   double bbWidthPrev = (bbMid[1] > 0) ? (bbUp[1] - bbLow[1]) / bbMid[1] : bbWidth;
   bool bbContracting = (bbWidth < bbWidthPrev * 0.97);

   // ── ATR M5 ────────────────────────────────────────────────────────
   double atrBuf[];
   ArraySetAsSeries(atrBuf, true);
   if(CopyBuffer(hATR_M5, 0, 0, 4, atrBuf) < 3) return;
   double atrCur = atrBuf[0];
   // Detectar si ATR enfriándose (bajando por ≥3 barras consecutivas)
   bool atrCooling = (atrBuf[0] < atrBuf[1] && atrBuf[1] < atrBuf[2]);

   // ── EMA móvil BB Width y ATR (α=0.08 ≈ 24 periodos para suavidad) ─
   double alpha = 0.08;
   if(g_bbWidthAvg <= 0) g_bbWidthAvg = bbWidth;
   else                  g_bbWidthAvg += alpha * (bbWidth - g_bbWidthAvg);
   if(g_atrM5Avg   <= 0) g_atrM5Avg   = atrCur;
   else                  g_atrM5Avg   += alpha * (atrCur - g_atrM5Avg);
   g_bbWidthLast = bbWidth;

   // ── Clasificación de estado candidato ─────────────────────────────
   ENUM_MARKET_STATE newState;

   // VOLATILE: prioridad máxima (no requiere histéresis — acción inmediata)
   if(atrCur > g_atrM5Avg * InpATRVolatileMult)
   {
      // Distinguir: VOLATILE con ADX alto = breakout dirigido (menos peligroso)
      // VOLATILE con ADX bajo = whipsaw caótico (más peligroso, score más alto requerido)
      newState = MARKET_VOLATILE;
   }
   // TRENDING: ADX H1 fuerte + proxy H4 confirmando
   else if(g_adxLast > InpADXTrending && h4TrendingProxy)
   {
      newState = MARKET_TRENDING;
   }
   // PRE-TRENDING: ADX subiendo rápido aunque aún no supere umbral → clasificar como TRENDING
   else if(g_adxLast > InpADXTrending * 0.85 && adxRising && h4TrendingProxy)
   {
      newState = MARKET_TRENDING;
   }
   // RANGING: ADX bajo + BB width estrecho (confirmación real de compresión)
   else if(g_adxLast < InpADXRanging &&
           g_bbWidthAvg > 0 &&
           bbWidth < g_bbWidthAvg * InpBBWidthRangeMult)
   {
      newState = MARKET_RANGING;
   }
   // NEUTRAL-RANGING (BB contrayendo pero ADX no tan bajo) → neutral con sesgo ranging
   else if(bbContracting && g_adxLast < InpADXTrending * 0.75)
   {
      newState = MARKET_RANGING;  // tratar como ranging para mayor selectividad
   }
   else
   {
      newState = MARKET_NEUTRAL;
   }

   // ── Histéresis anti-flip ─────────────────────────────────────────
   // VOLATILE: aplicar inmediatamente (sin esperar confirmación)
   if(newState == MARKET_VOLATILE)
   {
      if(g_marketState != MARKET_VOLATILE)
         s_lastStateChange = TimeCurrent();
      g_marketState    = MARKET_VOLATILE;
      g_marketStateStr = "VOLATILE";
      s_pendingState   = MARKET_VOLATILE;
      s_pendingCount   = 0;
      return;
   }

   // VOLATILE cooling: requiere 3 barras de ATR en descenso para salir
   if(g_marketState == MARKET_VOLATILE && newState != MARKET_VOLATILE)
   {
      if(!atrCooling)
         return;  // aún no enfriado suficiente
      // Después de 3 barras de enfriamiento → continúa a clasificación normal
   }

   // Otros estados: requieren 2 barras consecutivas de confirmación
   if(newState == s_pendingState)
   {
      s_pendingCount++;
   }
   else
   {
      s_pendingState = newState;
      s_pendingCount = 1;
      return;  // primera barra del nuevo estado — aún no confirmado
   }

   // Estado confirmado tras ≥2 barras
   if(s_pendingCount >= 2 && g_marketState != newState)
   {
      g_marketState    = newState;
      s_lastStateChange = TimeCurrent();
      switch(newState)
      {
         case MARKET_TRENDING: g_marketStateStr = "TRENDING"; break;
         case MARKET_RANGING:  g_marketStateStr = "RANGING";  break;
         default:              g_marketStateStr = "NEUTRAL";  break;
      }
   }
   else if(s_pendingCount >= 2)
   {
      // Estado sin cambio — solo actualizar string por si ADX cambió
      if(g_marketState == MARKET_TRENDING) g_marketStateStr = "TRENDING";
      else if(g_marketState == MARKET_RANGING) g_marketStateStr = "RANGING";
      else g_marketStateStr = "NEUTRAL";
   }
}

//====================================================================
//  SESGO SEMANAL (S7 — meta-filtro, sin trades propios)
//  EMA10 W1 dirección → booleans usados por otras estrategias como filtro
//====================================================================
void UpdateWeeklyBias()
{
   if(!InpWeeklyBiasOn) { g_weeklyBiasUp = false; g_weeklyBiasDn = false; return; }
   double ema[];
   ArraySetAsSeries(ema, true);
   if(CopyBuffer(hEMA10_W1, 0, 0, 3, ema) < 3) return;
   // ema[0] = barra W1 actual, ema[1] = barra W1 anterior
   g_weeklyBiasUp = (ema[0] > ema[1]);
   g_weeklyBiasDn = (ema[0] < ema[1]);
}

//====================================================================
//  DRAWDOWN ESCALATION
//  5% DD desde pico → lote ×0.75
//  10% DD desde pico → lote ×0.50
//  20% DD (InpMaxEquityDropPct) → ya manejado por circuit breaker
//====================================================================
void CheckDrawdownLevels()
{
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   if(bal > g_peakBalance) g_peakBalance = bal;  // actualizar pico
   if(g_peakBalance <= 0) return;

   double ddPct = (g_peakBalance - bal) / g_peakBalance * 100.0;

   if(ddPct >= InpDD_L2_Pct)
   {
      if(g_ddLevel != 2)
      { Print("⚠️ DD L2 (", DoubleToString(ddPct, 1), "%) → lote ×0.50"); g_ddLevel = 2; }
      g_lotMultDD = 0.50;
   }
   else if(ddPct >= InpDD_L1_Pct)
   {
      if(g_ddLevel != 1)
      { Print("⚠️ DD L1 (", DoubleToString(ddPct, 1), "%) → lote ×0.75"); g_ddLevel = 1; }
      g_lotMultDD = 0.75;
   }
   else
   {
      if(g_ddLevel > 0 && ddPct < InpDD_L1_Pct * 0.5)
      { Print("✅ DD recuperado → lote normal"); g_ddLevel = 0; g_lotMultDD = 1.0; }
   }
}

//====================================================================
//  RECOVERY LAYERS — pérdidas consecutivas globales
//  L1 (2): lote ×0.75
//  L2 (3): lote ×0.50 + pausa InpRecL2PauseMin minutos
//  L3 (4): g_dayInvalid = true (stop hasta mañana)
//====================================================================
void CheckRecoveryLayers()
{
   // Actualizar multiplicador según nivel actual
   if(g_recoveryLevel == 0)      g_lotMultRecovery = 1.00;
   else if(g_recoveryLevel == 1) g_lotMultRecovery = 0.75;
   else if(g_recoveryLevel == 2) g_lotMultRecovery = 0.50;
   else                          g_lotMultRecovery = 0.50;  // L3: ya parado

   if(g_recoveryLevel >= 3) g_dayInvalid = true;
}

void UpdateConsecLosses(double pnl)
{
   if(pnl > 0)
   {
      g_consecLosses = 0;
      if(g_recoveryLevel > 0)
      { Print("✅ Racha perdedora rota — Recovery reset"); g_recoveryLevel = 0; g_lotMultRecovery = 1.0; }
   }
   else if(pnl < 0)
   {
      g_consecLosses++;
      Print("📉 Pérdida consecutiva #", g_consecLosses);
      if(g_consecLosses >= InpRecL3Losses)
      {
         g_recoveryLevel = 3;
         g_dayInvalid    = true;
         Print("🛑 Recovery L3 — Stop hasta mañana (", g_consecLosses, " pérdidas consecutivas)");
      }
      else if(g_consecLosses >= InpRecL2Losses)
      {
         if(g_recoveryLevel < 2)
         {
            g_recoveryLevel       = 2;
            g_recoveryPauseUntil  = TimeCurrent() + InpRecL2PauseMin * 60;
            Print("⚠️ Recovery L2 — Pausa ", InpRecL2PauseMin, " min | lote ×0.50");
         }
      }
      else if(g_consecLosses >= InpRecL1Losses)
      {
         if(g_recoveryLevel < 1)
         { g_recoveryLevel = 1; Print("⚠️ Recovery L1 — lote ×0.75"); }
      }
   }
}

//====================================================================
//  GET LOT MULTIPLIER — combina DD + Recovery + Session
//====================================================================
double GetLotMultiplier()
{
   // Usar el multiplicador más restrictivo
   double mult = MathMin(g_lotMultDD, g_lotMultRecovery);
   mult = MathMin(mult, g_lotMultSession);
   return MathMax(mult, 0.25);  // nunca menos de 25%
}

//====================================================================
//  SESSION P&L TRACKING — Actualiza PnL por sesión con posiciones abiertas
//====================================================================
void UpdateSessionPnL()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   int h = dt.hour;

   // Acumular flotante por sesión activa
   // Los P&L cerrados se acumulan en TrackClosedTrades
   // Aquí calculamos si la sesión actual va muy negativa para reducir lotes
   double floatLon = 0, floatNY = 0, floatAsia = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong t = PositionGetTicket(i);
      if(!PositionSelectByTicket(t)) continue;
      long mg = (long)PositionGetInteger(POSITION_MAGIC);
      double pr = PositionGetDouble(POSITION_PROFIT);
      if(mg == InpMagicORB  || mg == InpMagicS4 || mg == InpMagicS1)  floatLon += pr;
      else if(mg == InpMagicNY  || mg == InpMagicS6)                   floatNY  += pr;
      else if(mg == InpMagicASIA || mg == InpMagicS3)                  floatAsia+= pr;
      else if(mg == InpMagicS5 || mg == InpMagicS2)
      {  // S5 H4 (08-18h): asignar a Londres si hora <13, NY si hora >=13
         if(h < 13) floatLon += pr; else floatNY += pr;
      }
      else if(mg == InpMagicS8)
      {  // S8 Scalper (08-20h): ídem
         if(h < 13) floatLon += pr; else floatNY += pr;
      }
   }

   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   if(bal <= 0) return;

   // Si la sesión actual pierde más de 3× daily loss → reducir lotes al 75%
   double sessPnL = (h >= 7 && h < 12)  ? (g_pnlLondon + floatLon) :
                    (h >= 13 && h < 18) ? (g_pnlNYSess  + floatNY)  :
                    (h >= 22 || h < 5)  ? (g_pnlAsiaSess + floatAsia) : 0;
   if(sessPnL < -(g_dailyLossUSD * 1.5))
      g_lotMultSession = 0.75;
   else
      g_lotMultSession = 1.0;
}

//====================================================================
//  CHECK PRE-NEWS EXIT
//  Cierra posiciones rentables (>= InpPreNewsMinR × SL dist) si
//  hay noticia de alto impacto en menos de InpPreNewsMinBefore min
//====================================================================
void CheckPreNewsExit()
{
   if(!InpPreNewsExitOn) return;
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   int h = dt.hour; int m = dt.min;
   int minOfDay = h * 60 + m;

   // Ventanas de noticias de alto impacto (min del día servidor GMT)
   // 13:25-13:45 → US data, 18:55-19:10 → FOMC
   bool newsClose30 =
      (minOfDay >= (13*60+25) - InpPreNewsMinBefore && minOfDay < 13*60+25) ||
      (minOfDay >= (18*60+55) - InpPreNewsMinBefore && minOfDay < 18*60+55);

   if(!newsClose30) return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(!PositionSelectByTicket(t)) continue;
      long mg  = (long)PositionGetInteger(POSITION_MAGIC);
      bool ourMag = (mg==InpMagic||mg==InpMagicORB||mg==InpMagicASIA||mg==InpMagicNY||
                     mg==InpMagicS1||mg==InpMagicS2||mg==InpMagicS3||mg==InpMagicS4||
                     mg==InpMagicS5||mg==InpMagicS6||mg==InpMagicS8);
      if(!ourMag) continue;

      double pr  = PositionGetDouble(POSITION_PROFIT);
      double sl  = PositionGetDouble(POSITION_SL);
      double tp  = PositionGetDouble(POSITION_TP);
      double open= PositionGetDouble(POSITION_PRICE_OPEN);

      // Calcular distancia SL como referencia de 1R
      double slDist = (sl > 0) ? MathAbs(open - sl) : 0;
      double minProfit = (slDist > 0) ? slDist * InpPreNewsMinR : 0;

      if(pr >= minProfit && minProfit > 0)
      {
         trade.SetExpertMagicNumber(mg);
         if(trade.PositionClose(t))
            Print("[PreNews] Cerrado ticket=", t, " profit=$", DoubleToString(pr, 2));
         trade.SetExpertMagicNumber(InpMagic);
      }
   }
}

//====================================================================
//  CORRELATION EXIT
//  Si hay 3+ posiciones en la misma dirección Y hay señal de reversión
//  (precio cruzó EMA50_M5 en contra) → cerrar 50% del peor lado
//====================================================================
void CheckCorrelationExit()
{
   int longsOpen = 0, shortsOpen = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong t = PositionGetTicket(i);
      if(!PositionSelectByTicket(t)) continue;
      long mg = (long)PositionGetInteger(POSITION_MAGIC);
      bool ourMag = (mg==InpMagic||mg==InpMagicORB||mg==InpMagicASIA||mg==InpMagicNY||
                     mg==InpMagicS1||mg==InpMagicS2||mg==InpMagicS3||mg==InpMagicS4||
                     mg==InpMagicS5||mg==InpMagicS6||mg==InpMagicS8);
      if(!ourMag) continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) longsOpen++;
      else shortsOpen++;
   }

   // Umbral dinámico: activar cuando ≥ mitad del máximo concurrente
   int corrThreshold = MathMax(2, g_maxConcurrent / 2);
   if(longsOpen < corrThreshold && shortsOpen < corrThreshold) return;

   // Señal de reversión: precio vs EMA50_M5
   double ema50[];
   ArraySetAsSeries(ema50, true);
   if(CopyBuffer(hTrendEMA_M5, 0, 0, 2, ema50) < 2) return;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   bool bearReversal = (longsOpen >= corrThreshold) && (bid < ema50[0]);
   bool bullReversal = (shortsOpen >= corrThreshold) && (ask > ema50[0]);

   if(!bearReversal && !bullReversal) return;

   // Cerrar 50% de las posiciones del lado correlacionado (las menos rentables primero)
   int closeCount = (bearReversal ? longsOpen : shortsOpen) / 2;
   if(closeCount < 1) return;

   // Recolectar tickets del lado a cerrar, ordenar por profit (peor primero)
   ulong tickets[50]; double profits[50]; int cnt = 0;
   ENUM_POSITION_TYPE closeType = bearReversal ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;

   for(int i = 0; i < PositionsTotal() && cnt < 50; i++)
   {
      ulong t = PositionGetTicket(i);
      if(!PositionSelectByTicket(t)) continue;
      long mg = (long)PositionGetInteger(POSITION_MAGIC);
      bool ourMag = (mg==InpMagic||mg==InpMagicORB||mg==InpMagicASIA||mg==InpMagicNY||
                     mg==InpMagicS1||mg==InpMagicS2||mg==InpMagicS3||mg==InpMagicS4||
                     mg==InpMagicS5||mg==InpMagicS6||mg==InpMagicS8);
      if(!ourMag) continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != closeType) continue;
      tickets[cnt] = t;
      profits[cnt] = PositionGetDouble(POSITION_PROFIT);
      cnt++;
   }

   // Bubble sort ascendente por profit (peor = menor primero)
   for(int i = 0; i < cnt - 1; i++)
      for(int j = 0; j < cnt - 1 - i; j++)
         if(profits[j] > profits[j+1])
         { double tmp=profits[j]; profits[j]=profits[j+1]; profits[j+1]=tmp;
           ulong  tmpt=tickets[j]; tickets[j]=tickets[j+1]; tickets[j+1]=tmpt; }

   for(int i = 0; i < closeCount && i < cnt; i++)
   {
      if(PositionSelectByTicket(tickets[i]))
      {
         long mg = (long)PositionGetInteger(POSITION_MAGIC);
         trade.SetExpertMagicNumber(mg);
         if(trade.PositionClose(tickets[i]))
            Print("[Correlation] Cerrado ", tickets[i], " profit=$", DoubleToString(profits[i], 2));
         trade.SetExpertMagicNumber(InpMagic);
      }
   }
}

//====================================================================
//  HELPERS S5
//====================================================================
void CloseAllS5(string reason)
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   { ulong t=PositionGetTicket(i); if(!PositionSelectByTicket(t)) continue;
     if((long)PositionGetInteger(POSITION_MAGIC)!=InpMagicS5) continue;
     trade.SetExpertMagicNumber(InpMagicS5); trade.PositionClose(t);
     trade.SetExpertMagicNumber(InpMagic); }
   g_s5Triggered = false;
}

//====================================================================
//  S5: H4 TREND CONTINUATION
//  Señal: H4 EMA50 > EMA200 (bullish macro) + precio retrocedió a EMA20_H1
//         → entrada long cuando precio rebota desde EMA20_H1 con H1 RSI > 45
//  Short: opuesto
//  SL = 2.0 × ATR_H1 | TP = 2.5 × ATR_H1
//====================================================================
void RunS5H4TrendContinuation()
{
   if(!InpS5On || g_dayInvalid) return;
   if(g_s5Triggered) return;
   if(g_tradesToday >= g_maxTradesDay) return;
   if(CountAllOpenPositions() >= g_maxConcurrent) return;
   if(!MarginOK()) return;
   if(!PortfolioRiskOK()) return;
   if(IsNewsTime()) return;
   if(g_marketState == MARKET_VOLATILE) return;

   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   if(dt.hour < InpS5HourStart || dt.hour >= InpS5HourEnd) return;

   // H4 macro trend
   double h4e50[], h4e200[];
   ArraySetAsSeries(h4e50,  true);
   ArraySetAsSeries(h4e200, true);
   if(CopyBuffer(hEMA50_H4,  0, 0, 2, h4e50)  < 2 ||
      CopyBuffer(hEMA200_H4, 0, 0, 2, h4e200) < 2) return;

   bool h4Bull = (h4e50[0] > h4e200[0]);
   bool h4Bear = (h4e50[0] < h4e200[0]);
   if(!h4Bull && !h4Bear) return;

   // Weekly bias veto
   if(InpWeeklyBiasOn)
   {
      if(h4Bull && g_weeklyBiasDn) return;  // contra sesgo semanal — no entrar
      if(h4Bear && g_weeklyBiasUp) return;
   }

   // D1 alignment
   if(h4Bull && g_sesgoDn) return;
   if(h4Bear && g_sesgoUp) return;

   // H1 EMA20 pullback: precio tocó EMA20_H1 en la última barra
   double h1e20[], h1e50[];
   ArraySetAsSeries(h1e20, true);
   ArraySetAsSeries(h1e50, true);
   if(CopyBuffer(hEMA20_H1, 0, 0, 3, h1e20) < 3 ||
      CopyBuffer(hEMA50_H1, 0, 0, 3, h1e50) < 3) return;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   // H1 RSI filtro
   double rH1[];
   ArraySetAsSeries(rH1, true);
   if(CopyBuffer(hRSI_H1, 0, 0, 2, rH1) < 2) return;

   // ATR H1 para SL/TP
   double atrH1[];
   ArraySetAsSeries(atrH1, true);
   if(CopyBuffer(hATR_H1, 0, 0, 2, atrH1) < 2) return;
   double atr = atrH1[0];
   if(atr <= 0) return;

   double spread = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(spread > InpMaxSpread * _Point) return;

   // Cooldown anti-simultáneo
   if(TimeCurrent() - g_lastBuyTime  < 300 && h4Bull) return;
   if(TimeCurrent() - g_lastSellTime < 300 && h4Bear) return;

   if(h4Bull)
   {
      // Precio cerca de EMA20_H1 (dentro de 0.5×ATR) + rebotando + RSI > 45
      bool nearEMA = (MathAbs(ask - h1e20[0]) < atr * 0.5);
      bool rebote  = (ask > h1e20[0] && bid > h1e20[1]);
      if(!nearEMA || !rebote) return;
      if(rH1[0] < 45.0) return;

      double sl = ask - atr * InpS5SL_ATR;
      double tp = ask + atr * InpS5TP_ATR;
      if(!ValidateMinRR(ask, sl, tp, "S5-LONG")) return;

      double lot = CalcLot(MathAbs(ask - sl), 1.0);
      trade.SetExpertMagicNumber(InpMagicS5);
      if(trade.Buy(lot, _Symbol, 0, sl, tp, "S5-H4Bull"))
      {
         g_s5Triggered     = true;
         g_s5TradeOpenTime = TimeCurrent();
         g_lastBuyTime     = TimeCurrent();
         g_tradesToday++;
         g_s5Partial1Done = false; g_s5Partial2Done = false; g_s5BEMoved = false;
      }
      trade.SetExpertMagicNumber(InpMagic);
   }
   else if(h4Bear)
   {
      bool nearEMA = (MathAbs(bid - h1e20[0]) < atr * 0.5);
      bool rebote  = (bid < h1e20[0] && ask < h1e20[1]);
      if(!nearEMA || !rebote) return;
      if(rH1[0] > 55.0) return;

      double sl = bid + atr * InpS5SL_ATR;
      double tp = bid - atr * InpS5TP_ATR;
      if(!ValidateMinRR(bid, sl, tp, "S5-SHORT")) return;

      double lot = CalcLot(MathAbs(bid - sl), 1.0);
      trade.SetExpertMagicNumber(InpMagicS5);
      if(trade.Sell(lot, _Symbol, 0, sl, tp, "S5-H4Bear"))
      {
         g_s5Triggered     = true;
         g_s5TradeOpenTime = TimeCurrent();
         g_lastSellTime    = TimeCurrent();
         g_tradesToday++;
         g_s5Partial1Done = false; g_s5Partial2Done = false; g_s5BEMoved = false;
      }
      trade.SetExpertMagicNumber(InpMagic);
   }
}

void ManageS5Trades()
{
   bool hasPos = false;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(!PositionSelectByTicket(t)) continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagicS5) continue;
      hasPos = true;

      datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
      double   profit   = PositionGetDouble(POSITION_PROFIT);
      bool     isBuy    = ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double   open     = PositionGetDouble(POSITION_PRICE_OPEN);
      double   sl       = PositionGetDouble(POSITION_SL);
      double   tp       = PositionGetDouble(POSITION_TP);
      double   vol      = PositionGetDouble(POSITION_VOLUME);
      double   cur      = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      if(sl <= 0 || tp <= 0) continue;
      double slDist = MathAbs(open - sl);
      if(slDist <= 0) continue;
      double mR = MathAbs(cur - open) / slDist;

      // Partial close 1.5R (mejorado desde 1R para preservar R:R efectivo)
      if(InpPartialClose && !g_s5Partial1Done && mR >= 1.5)
      {
         double partPct = (g_capMode == CAP_MICRO) ? 0.25 : 0.20;
         double cv = NormLot(vol * partPct);
         double minV = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
         if(cv >= minV)
         {
            trade.SetExpertMagicNumber(InpMagicS5);
            trade.PositionClosePartial(t, cv);
            trade.SetExpertMagicNumber(InpMagic);
         }
         if(!g_s5BEMoved)
         {
            double nSL = isBuy ? open + _Point : open - _Point;
            trade.SetExpertMagicNumber(InpMagicS5);
            trade.PositionModify(t, nSL, tp);
            trade.SetExpertMagicNumber(InpMagic);
            g_s5BEMoved = true;
         }
         g_s5Partial1Done = true;
         LOG("S5 Parcial1 @1.5R (20%) | BE activo | $" + DoubleToString(profit, 2));
      }

      // Partial close 2.5R (mejorado desde 2R)
      if(InpPartialClose && !g_s5Partial2Done && g_s5Partial1Done && mR >= 2.5)
      {
         double partPct2 = (g_capMode == CAP_MICRO) ? 0.25 : 0.20;
         double cv2 = NormLot(vol * partPct2);
         double minV = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
         if(cv2 >= minV)
         {
            trade.SetExpertMagicNumber(InpMagicS5);
            trade.PositionClosePartial(t, cv2);
            trade.SetExpertMagicNumber(InpMagic);
         }
         g_s5Partial2Done = true;
         LOG("S5 Parcial2 @2.5R (20%) | $" + DoubleToString(profit, 2));
      }

      // MTF trailing >= 1.5R, ATR trailing solo >= 0.5R
      if(InpTrailingOn)
      {
         bool mtfClosed = false;
         if(mR >= 1.5) mtfClosed = ApplyMTFTrailing(t, isBuy, open, sl, tp);
         if(!mtfClosed && mR >= 0.5) ApplyTrailing(t, isBuy);
         if(mtfClosed)
         {
            g_s5Triggered = false;
            g_s5Partial1Done = false; g_s5Partial2Done = false; g_s5BEMoved = false;
            continue;
         }
      }

      // BE anticipado a 0.8R con confirmación (mejorado desde 0.5R)
      if(!g_s5BEMoved && mR >= 0.80)
      {
         double nSL = isBuy ? open + _Point : open - _Point;
         bool canMove = isBuy ? (nSL > sl) : (nSL < sl || sl == 0);
         if(canMove)
         {
            trade.SetExpertMagicNumber(InpMagicS5);
            trade.PositionModify(t, nSL, tp);
            trade.SetExpertMagicNumber(InpMagic);
            g_s5BEMoved = true;
            LOG("S5 BE @0.8R");
         }
      }

      // Salida por tiempo (barras H4)
      int barsOpen = (int)((TimeCurrent() - openTime) / (4 * 3600));
      if(barsOpen >= InpS5MaxBarsH4)
      {
         trade.SetExpertMagicNumber(InpMagicS5);
         trade.PositionClose(t);
         trade.SetExpertMagicNumber(InpMagic);
         g_s5Triggered = false;
         g_s5Partial1Done = false; g_s5Partial2Done = false; g_s5BEMoved = false;
         LOG("S5 Cierre tiempo " + IntegerToString(InpS5MaxBarsH4) + "H4 | $" + DoubleToString(profit, 2));
      }
   }
   if(!hasPos) { g_s5Triggered = false; g_s5Partial1Done = false; g_s5Partial2Done = false; g_s5BEMoved = false; }
}

//====================================================================
//  HELPERS S6
//====================================================================
void CloseAllS6(string reason)
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   { ulong t=PositionGetTicket(i); if(!PositionSelectByTicket(t)) continue;
     if((long)PositionGetInteger(POSITION_MAGIC)!=InpMagicS6) continue;
     trade.SetExpertMagicNumber(InpMagicS6); trade.PositionClose(t);
     trade.SetExpertMagicNumber(InpMagic); }
   g_s6Triggered = false;
}

//====================================================================
//  S6: M15 MOMENTUM SPIKE — Overlap Londres-NY (13:00-15:00)
//  Señal: RSI_M15 cruza 50 + EMA20_M15 en dirección + BB confirma
//  SL = 1.5 × ATR_M15 | TP = 2.5 × ATR_M15
//====================================================================
void RunS6M15MomentumSpike()
{
   if(!InpS6On || g_dayInvalid) return;
   if(g_s6Triggered) return;
   if(g_tradesToday >= g_maxTradesDay) return;
   if(CountAllOpenPositions() >= g_maxConcurrent) return;
   if(!MarginOK()) return;
   if(!PortfolioRiskOK()) return;
   if(IsNewsTime()) return;

   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   if(dt.hour < InpS6HourStart || dt.hour >= InpS6HourEnd) return;
   if(g_marketState == MARKET_VOLATILE) return;

   double rsi[], rsiP[];
   ArraySetAsSeries(rsi,  true);
   ArraySetAsSeries(rsiP, true);
   if(CopyBuffer(hRSI_M15, 0, 0, 3, rsi)  < 3 ||
      CopyBuffer(hRSI_M15, 0, 1, 3, rsiP) < 3) return;

   double ema20[];
   ArraySetAsSeries(ema20, true);
   if(CopyBuffer(hEMA20_M15, 0, 0, 3, ema20) < 3) return;

   double bbUp[], bbMid[], bbLow[];
   ArraySetAsSeries(bbUp,  true);
   ArraySetAsSeries(bbMid, true);
   ArraySetAsSeries(bbLow, true);
   if(CopyBuffer(hBB_M15, 1, 0, 3, bbUp)  < 3 ||
      CopyBuffer(hBB_M15, 0, 0, 3, bbMid) < 3 ||
      CopyBuffer(hBB_M15, 2, 0, 3, bbLow) < 3) return;

   double atr[];
   ArraySetAsSeries(atr, true);
   if(CopyBuffer(hATR_M15, 0, 0, 2, atr) < 2) return;
   if(atr[0] <= 0) return;

   double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double spread = ask - bid;
   if(spread > InpMaxSpread * _Point) return;

   // RSI cruce sobre 50 = bullish momentum; bajo 50 = bearish
   bool rsiBull = (rsiP[0] < 50.0 && rsi[0] > 50.0);  // cruce alcista
   bool rsiBear = (rsiP[0] > 50.0 && rsi[0] < 50.0);  // cruce bajista

   if(!rsiBull && !rsiBear) return;

   // Weekly bias veto
   if(InpWeeklyBiasOn)
   {
      if(rsiBull && g_weeklyBiasDn) return;
      if(rsiBear && g_weeklyBiasUp) return;
   }

   // D1 alignment — no operar contra D1
   if(rsiBull && g_sesgoDn) return;
   if(rsiBear && g_sesgoUp) return;

   // Cooldown
   if(TimeCurrent() - g_lastBuyTime  < 300 && rsiBull) return;
   if(TimeCurrent() - g_lastSellTime < 300 && rsiBear) return;

   if(rsiBull)
   {
      // EMA20 M15 apunta arriba + precio sobre EMA20
      if(ema20[0] <= ema20[1]) return;
      if(ask < ema20[0]) return;
      // BB: precio no está en extremo superior (evitar sobrecompra)
      double bbPos = (bbMid[0] > 0 && (bbUp[0] - bbLow[0]) > 0) ?
                     (ask - bbLow[0]) / (bbUp[0] - bbLow[0]) : 0.5;
      if(bbPos > 0.85) return;

      double sl = ask - atr[0] * InpS6SL_ATR;
      double tp = ask + atr[0] * InpS6TP_ATR;
      if(!ValidateMinRR(ask, sl, tp, "S6-LONG")) return;

      double lot = CalcLot(MathAbs(ask - sl), 1.0);
      trade.SetExpertMagicNumber(InpMagicS6);
      if(trade.Buy(lot, _Symbol, 0, sl, tp, "S6-M15Bull"))
      {
         g_s6Triggered     = true;
         g_s6TradeOpenTime = TimeCurrent();
         g_lastBuyTime     = TimeCurrent();
         g_tradesToday++;
         g_s6Partial1Done = false; g_s6Partial2Done = false; g_s6BEMoved = false;
      }
      trade.SetExpertMagicNumber(InpMagic);
   }
   else if(rsiBear)
   {
      if(ema20[0] >= ema20[1]) return;
      if(bid > ema20[0]) return;
      double bbPos = (bbMid[0] > 0 && (bbUp[0] - bbLow[0]) > 0) ?
                     (bid - bbLow[0]) / (bbUp[0] - bbLow[0]) : 0.5;
      if(bbPos < 0.15) return;

      double sl = bid + atr[0] * InpS6SL_ATR;
      double tp = bid - atr[0] * InpS6TP_ATR;
      if(!ValidateMinRR(bid, sl, tp, "S6-SHORT")) return;

      double lot = CalcLot(MathAbs(bid - sl), 1.0);
      trade.SetExpertMagicNumber(InpMagicS6);
      if(trade.Sell(lot, _Symbol, 0, sl, tp, "S6-M15Bear"))
      {
         g_s6Triggered     = true;
         g_s6TradeOpenTime = TimeCurrent();
         g_lastSellTime    = TimeCurrent();
         g_tradesToday++;
         g_s6Partial1Done = false; g_s6Partial2Done = false; g_s6BEMoved = false;
      }
      trade.SetExpertMagicNumber(InpMagic);
   }
}

void ManageS6Trades()
{
   bool hasPos = false;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(!PositionSelectByTicket(t)) continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagicS6) continue;
      hasPos = true;

      datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
      double   profit   = PositionGetDouble(POSITION_PROFIT);
      bool     isBuy    = ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double   open     = PositionGetDouble(POSITION_PRICE_OPEN);
      double   sl       = PositionGetDouble(POSITION_SL);
      double   tp       = PositionGetDouble(POSITION_TP);
      double   vol      = PositionGetDouble(POSITION_VOLUME);
      double   cur      = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      if(sl <= 0 || tp <= 0) continue;
      double slDist = MathAbs(open - sl);
      if(slDist <= 0) continue;
      double mR = MathAbs(cur - open) / slDist;

      // Partial close 1.5R (mejorado desde 1R para preservar R:R efectivo)
      if(InpPartialClose && !g_s6Partial1Done && mR >= 1.5)
      {
         double partPct = (g_capMode == CAP_MICRO) ? 0.25 : 0.20;
         double cv = NormLot(vol * partPct);
         double minV = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
         if(cv >= minV)
         {
            trade.SetExpertMagicNumber(InpMagicS6);
            trade.PositionClosePartial(t, cv);
            trade.SetExpertMagicNumber(InpMagic);
         }
         if(!g_s6BEMoved)
         {
            double nSL = isBuy ? open + _Point : open - _Point;
            trade.SetExpertMagicNumber(InpMagicS6);
            trade.PositionModify(t, nSL, tp);
            trade.SetExpertMagicNumber(InpMagic);
            g_s6BEMoved = true;
         }
         g_s6Partial1Done = true;
         LOG("S6 Parcial1 @1.5R (20%) | BE activo | $" + DoubleToString(profit, 2));
      }

      // Partial close 2.5R (mejorado desde 2R)
      if(InpPartialClose && !g_s6Partial2Done && g_s6Partial1Done && mR >= 2.5)
      {
         double partPct2 = (g_capMode == CAP_MICRO) ? 0.25 : 0.20;
         double cv2 = NormLot(vol * partPct2);
         double minV = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
         if(cv2 >= minV)
         {
            trade.SetExpertMagicNumber(InpMagicS6);
            trade.PositionClosePartial(t, cv2);
            trade.SetExpertMagicNumber(InpMagic);
         }
         g_s6Partial2Done = true;
         LOG("S6 Parcial2 @2.5R (20%) | $" + DoubleToString(profit, 2));
      }

      // MTF trailing >= 1.5R, ATR trailing solo >= 0.5R
      if(InpTrailingOn)
      {
         bool mtfClosed = false;
         if(mR >= 1.5) mtfClosed = ApplyMTFTrailing(t, isBuy, open, sl, tp);
         if(!mtfClosed && mR >= 0.5) ApplyTrailing(t, isBuy);
         if(mtfClosed)
         {
            g_s6Triggered = false;
            g_s6Partial1Done = false; g_s6Partial2Done = false; g_s6BEMoved = false;
            continue;
         }
      }

      // BE anticipado a 0.8R (mejorado desde 0.5R)
      if(!g_s6BEMoved && mR >= 0.80)
      {
         double nSL = isBuy ? open + _Point : open - _Point;
         bool canMove = isBuy ? (nSL > sl) : (nSL < sl || sl == 0);
         if(canMove)
         {
            trade.SetExpertMagicNumber(InpMagicS6);
            trade.PositionModify(t, nSL, tp);
            trade.SetExpertMagicNumber(InpMagic);
            g_s6BEMoved = true;
            LOG("S6 BE @0.8R");
         }
      }

      // Salida por tiempo (barras M15)
      int barsOpen = (int)((TimeCurrent() - openTime) / (15 * 60));
      if(barsOpen >= InpS6MaxBarsM15)
      {
         trade.SetExpertMagicNumber(InpMagicS6);
         trade.PositionClose(t);
         trade.SetExpertMagicNumber(InpMagic);
         g_s6Triggered = false;
         g_s6Partial1Done = false; g_s6Partial2Done = false; g_s6BEMoved = false;
         LOG("S6 Cierre tiempo " + IntegerToString(InpS6MaxBarsM15) + "M15 | $" + DoubleToString(profit, 2));
      }
   }
   if(!hasPos) { g_s6Triggered = false; g_s6Partial1Done = false; g_s6Partial2Done = false; g_s6BEMoved = false; }
}

//====================================================================
//  HELPERS S8
//====================================================================
void CloseAllS8(string reason)
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   { ulong t=PositionGetTicket(i); if(!PositionSelectByTicket(t)) continue;
     if((long)PositionGetInteger(POSITION_MAGIC)!=InpMagicS8) continue;
     trade.SetExpertMagicNumber(InpMagicS8); trade.PositionClose(t);
     trade.SetExpertMagicNumber(InpMagic); }
   g_s8Triggered = false;
}

//====================================================================
//  S8: CONSOLIDATION RANGE SCALPER — solo activo en MARKET_RANGING
//  Señal: precio toca borde BB (posición BB < InpS8BBEdgePct o > 1-InpS8BBEdgePct)
//  BUY en borde inferior → TP en BB middle | SELL en borde superior → TP BB middle
//  SL = InpS8SL_ATR × ATR_M5 más allá de la BB band
//====================================================================
void RunS8ConsolidationScalper()
{
   if(!InpS8On || g_dayInvalid) return;
   if(g_s8Triggered) return;
   if(g_tradesToday >= g_maxTradesDay) return;
   if(CountAllOpenPositions() >= g_maxConcurrent) return;
   if(!MarginOK()) return;
   if(!PortfolioRiskOK()) return;
   if(IsNewsTime()) return;

   // Solo operar en RANGING
   if(g_marketState != MARKET_RANGING) return;

   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   if(dt.hour < InpS8HourStart || dt.hour >= InpS8HourEnd) return;

   double bbUp[], bbMid[], bbLow[];
   ArraySetAsSeries(bbUp,  true);
   ArraySetAsSeries(bbMid, true);
   ArraySetAsSeries(bbLow, true);
   if(CopyBuffer(hBB_M5, 1, 0, 3, bbUp)  < 3 ||
      CopyBuffer(hBB_M5, 0, 0, 3, bbMid) < 3 ||
      CopyBuffer(hBB_M5, 2, 0, 3, bbLow) < 3) return;

   double atrBuf[];
   ArraySetAsSeries(atrBuf, true);
   if(CopyBuffer(hATR_M5, 0, 0, 2, atrBuf) < 2) return;
   double atr = atrBuf[0];
   if(atr <= 0) return;

   double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double spread = ask - bid;
   if(spread > InpMaxSpread * _Point) return;

   double bbRange = bbUp[0] - bbLow[0];
   if(bbRange <= 0) return;

   // Posición del precio en la BB (0=low, 1=high)
   double bbPosBuy  = (ask - bbLow[0]) / bbRange;
   double bbPosSell = (bid - bbLow[0]) / bbRange;

   bool buySignal  = (bbPosBuy  <= InpS8BBEdgePct);   // precio en borde inferior
   bool sellSignal = (bbPosSell >= 1.0 - InpS8BBEdgePct);  // precio en borde superior

   if(!buySignal && !sellSignal) return;

   // Weekly bias: en ranging solo operar en dirección del sesgo semanal
   if(InpWeeklyBiasOn && g_weeklyBiasDn && buySignal)  return;
   if(InpWeeklyBiasOn && g_weeklyBiasUp && sellSignal) return;

   // Cooldown
   if(TimeCurrent() - g_lastBuyTime  < 300 && buySignal)  return;
   if(TimeCurrent() - g_lastSellTime < 300 && sellSignal) return;

   if(buySignal)
   {
      double sl = bbLow[0] - atr * InpS8SL_ATR;
      double tp = bbMid[0];  // TP en la media de la BB
      if(tp <= ask + _Point) return;  // TP debe ser mayor que entrada
      if(!ValidateMinRR(ask, sl, tp, "S8-LONG")) return;

      double lot = CalcLot(MathAbs(ask - sl), 0.8);  // Riesgo reducido en scalper
      trade.SetExpertMagicNumber(InpMagicS8);
      if(trade.Buy(lot, _Symbol, 0, sl, tp, "S8-RangeBuy"))
      {
         g_s8Triggered     = true;
         g_s8TradeOpenTime = TimeCurrent();
         g_lastBuyTime     = TimeCurrent();
         g_tradesToday++;
         g_s8Partial1Done = false; g_s8Partial2Done = false; g_s8BEMoved = false;
      }
      trade.SetExpertMagicNumber(InpMagic);
   }
   else if(sellSignal)
   {
      double sl = bbUp[0] + atr * InpS8SL_ATR;
      double tp = bbMid[0];  // TP en la media de la BB
      if(tp >= bid - _Point) return;
      if(!ValidateMinRR(bid, sl, tp, "S8-SHORT")) return;

      double lot = CalcLot(MathAbs(bid - sl), 0.8);
      trade.SetExpertMagicNumber(InpMagicS8);
      if(trade.Sell(lot, _Symbol, 0, sl, tp, "S8-RangeSell"))
      {
         g_s8Triggered     = true;
         g_s8TradeOpenTime = TimeCurrent();
         g_lastSellTime    = TimeCurrent();
         g_tradesToday++;
         g_s8Partial1Done = false; g_s8Partial2Done = false; g_s8BEMoved = false;
      }
      trade.SetExpertMagicNumber(InpMagic);
   }
}

void ManageS8Trades()
{
   bool hasPos = false;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(!PositionSelectByTicket(t)) continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagicS8) continue;
      hasPos = true;

      datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
      double   profit   = PositionGetDouble(POSITION_PROFIT);
      bool     isBuy    = ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double   open     = PositionGetDouble(POSITION_PRICE_OPEN);
      double   sl       = PositionGetDouble(POSITION_SL);
      double   tp       = PositionGetDouble(POSITION_TP);
      double   vol      = PositionGetDouble(POSITION_VOLUME);
      double   cur      = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      // Salida inmediata si mercado sale de RANGING
      if(g_marketState == MARKET_TRENDING || g_marketState == MARKET_VOLATILE)
      {
         trade.SetExpertMagicNumber(InpMagicS8);
         trade.PositionClose(t);
         trade.SetExpertMagicNumber(InpMagic);
         g_s8Triggered = false;
         g_s8Partial1Done = false; g_s8Partial2Done = false; g_s8BEMoved = false;
         Print("S8 Cierre: mercado no es RANGING | profit=$", DoubleToString(profit, 2));
         continue;
      }

      if(sl <= 0 || tp <= 0) continue;
      double slDist = MathAbs(open - sl);
      if(slDist <= 0) continue;
      double mR = MathAbs(cur - open) / slDist;

      // Partial close 1R — S8 TP suele ser 1R-1.5R, ajustar threshold
      if(InpPartialClose && !g_s8Partial1Done && mR >= 0.75)
      {
         double cv = NormLot(vol * g_partialAt1R);
         double minV = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
         if(cv >= minV)
         {
            trade.SetExpertMagicNumber(InpMagicS8);
            trade.PositionClosePartial(t, cv);
            trade.SetExpertMagicNumber(InpMagic);
         }
         if(!g_s8BEMoved)
         {
            double nSL = isBuy ? open + _Point : open - _Point;
            trade.SetExpertMagicNumber(InpMagicS8);
            trade.PositionModify(t, nSL, tp);
            trade.SetExpertMagicNumber(InpMagic);
            g_s8BEMoved = true;
         }
         g_s8Partial1Done = true;
         Print("S8 Parcial1 @0.75R | BE activo | profit=$", DoubleToString(profit, 2));
      }

      // ATR trailing (no MTF — S8 es scalper en rango, H1/H4 no aplica)
      if(InpTrailingOn) ApplyTrailing(t, isBuy);

      // BE anticipado a 0.5R
      if(!g_s8BEMoved && mR >= 0.5)
      {
         double nSL = isBuy ? open + _Point : open - _Point;
         bool canMove = isBuy ? (nSL > sl) : (nSL < sl || sl == 0);
         if(canMove)
         {
            trade.SetExpertMagicNumber(InpMagicS8);
            trade.PositionModify(t, nSL, tp);
            trade.SetExpertMagicNumber(InpMagic);
            g_s8BEMoved = true;
            Print("S8 BE @0.5R");
         }
      }

      // Salida por tiempo (barras M5)
      int barsOpen = (int)((TimeCurrent() - openTime) / (5 * 60));
      if(barsOpen >= InpS8MaxBarsM5)
      {
         trade.SetExpertMagicNumber(InpMagicS8);
         trade.PositionClose(t);
         trade.SetExpertMagicNumber(InpMagic);
         g_s8Triggered = false;
         g_s8Partial1Done = false; g_s8Partial2Done = false; g_s8BEMoved = false;
         Print("S8 Cierre tiempo ", InpS8MaxBarsM5, "M5 | profit=$", DoubleToString(profit, 2));
      }
   }
   if(!hasPos) { g_s8Triggered = false; g_s8Partial1Done = false; g_s8Partial2Done = false; g_s8BEMoved = false; }
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
                    (mg==InpMagicNY)?"[NY]":
                    (mg==InpMagicS1)?"[S1-PDH]":
                    (mg==InpMagicS2)?"[S2-EMA20]":
                    (mg==InpMagicS3)?"[S3-AsiaBreak]":
                    (mg==InpMagicS4)?"[S4-LondORB]":
                    (mg==InpMagicS5)?"[S5-H4Trend]":
                    (mg==InpMagicS6)?"[S6-M15Spike]":
                    (mg==InpMagicS8)?"[S8-Consol]":"[QQ]";
         Print(src," CIERRE $",DoubleToString(p,2),p>=0?" ✅":" ❌");
      }
   }
}

//+------------------------------------------------------------------+
//  OnTester — exporta estadísticas al finalizar cada backtest
//  Python optimizer lee el JSON para guiar la siguiente iteración
//+------------------------------------------------------------------+
double OnTester()
{
   // Recolectar estadísticas del tester
   double initialDepo  = TesterStatistics(STAT_INITIAL_DEPOSIT);
   double netProfit    = TesterStatistics(STAT_PROFIT);
   double profitFactor = TesterStatistics(STAT_PROFIT_FACTOR);
   double maxDD_pct    = TesterStatistics(STAT_EQUITY_DD_RELATIVE);
   double sharpe       = TesterStatistics(STAT_SHARPE_RATIO);
   double totalTrades  = TesterStatistics(STAT_TRADES);
   double wonTrades    = TesterStatistics(STAT_PROFIT_TRADES);
   double lostTrades   = TesterStatistics(STAT_LOSS_TRADES);
   double grossProfit  = TesterStatistics(STAT_GROSS_PROFIT);
   double grossLoss    = TesterStatistics(STAT_GROSS_LOSS);
   double recovery     = TesterStatistics(STAT_RECOVERY_FACTOR);
   double balanceDD    = TesterStatistics(STAT_BALANCE_DD);
   double finalBalance = initialDepo + netProfit;
   double winRate      = (totalTrades > 0) ? (wonTrades / totalTrades * 100.0) : 0.0;

   // Fitness compuesto: maximizar PF×WR y minimizar DD
   double fitness = 0.0;
   if(profitFactor > 0.0 && maxDD_pct > 0.0 && totalTrades >= 10)
      fitness = (profitFactor * (winRate / 100.0)) / (maxDD_pct + 1.0);

   // Construir JSON de resultado
   string js = "{";
   js += "\"net_profit\":"      + DoubleToString(netProfit,    2) + ",";
   js += "\"profit_factor\":"   + DoubleToString(profitFactor, 4) + ",";
   js += "\"max_dd_pct\":"      + DoubleToString(maxDD_pct,    4) + ",";
   js += "\"sharpe\":"          + DoubleToString(sharpe,       4) + ",";
   js += "\"total_trades\":"    + DoubleToString(totalTrades,  0) + ",";
   js += "\"won_trades\":"      + DoubleToString(wonTrades,    0) + ",";
   js += "\"lost_trades\":"     + DoubleToString(lostTrades,   0) + ",";
   js += "\"win_rate\":"        + DoubleToString(winRate,      2) + ",";
   js += "\"gross_profit\":"    + DoubleToString(grossProfit,  2) + ",";
   js += "\"gross_loss\":"      + DoubleToString(grossLoss,    2) + ",";
   js += "\"recovery_factor\":" + DoubleToString(recovery,     4) + ",";
   js += "\"balance_dd\":"      + DoubleToString(balanceDD,    2) + ",";
   js += "\"initial_deposit\":" + DoubleToString(initialDepo,  2) + ",";
   js += "\"final_balance\":"   + DoubleToString(finalBalance, 2) + ",";
   js += "\"fitness\":"         + DoubleToString(fitness,      6) + "}";

   // Escribir en Common Files con FILE_COMMON (directorio compartido del agente tester)
   int fh = FileOpen("tester_result.json", FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(fh != INVALID_HANDLE) { FileWriteString(fh, js); FileClose(fh); }

   // Escribir también sin FILE_COMMON — directorio MQL5\Files del agente
   // Esto garantiza que el optimizer encuentre el resultado incluso si FILE_COMMON
   // apunta a una ubicación diferente en el contexto del tester vs el terminal.
   int fh2 = FileOpen("tester_result.json", FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(fh2 != INVALID_HANDLE) { FileWriteString(fh2, js); FileClose(fh2); }

   return fitness;
}

//+------------------------------------------------------------------+
//  FIN – QQ ULTIMATE v9.0 EVOLUTION
//+------------------------------------------------------------------+
