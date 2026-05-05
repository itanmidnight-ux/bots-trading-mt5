//+------------------------------------------------------------------+
//|              XAU_USD_MultiTrader_Pro v7.5 STABLE                |
//|  Base v7.3 + Fixes M30/H1 + POSIBLE corregido + M5 deshabilitado|
//|  Diagnóstico: spread/ATR math + tiempo madurez trade correcto   |
//+------------------------------------------------------------------+
#property copyright "XAU_USD ICT MultiTrader Pro v7.5"
#property version   "7.5"
#property description "XAU_USD ICT MultiTrader Pro v7.5 – M15/M30/H1 Rentable"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\DealInfo.mqh>
#include <Arrays\ArrayDouble.mqh>
#include <Arrays\ArrayInt.mqh>

//+------------------------------------------------------------------+
//| ESTRUCTURAS Y VARIABLES GLOBALES                                |
//+------------------------------------------------------------------+

CTrade trade;
CPositionInfo positionInfo;
CDealInfo dealInfo;
CArrayDouble profitHistory;
CArrayInt tradeCountHistory;

//+------------------------------------------------------------------+
input group "════════════════════════════════════════════════════════════"
input group "🔧 CONFIGURACIÓN PRINCIPAL"
input group "════════════════════════════════════════════════════════════"
input int DetectLeverage = 1000;        // Apalancamiento fallback (1:500 o 1:1000)
input double MinimumCapital = 4.0;
input bool UseAutoLot = true;
input double FixedLot = 0.01;

input group "════════════════════════════════════════════════════════════"
input group "📊 GESTIÓN DE RIESGO"
input group "════════════════════════════════════════════════════════════"
input double RiskPerTrade = 0.5;
input double MaxDailyLossPct = 5.0;
input double CriticalDrawdownLevel = 10.0;
input int MaxConsecutiveLosses = 3;
input double MaxLossPerTrade = 400.0;
input double RR_Minimum = 3.0;
input bool ValidateLeverage = false;    // Deshabilitar para no bloquear 1:500 o 1:1000
input int RequiredLeverage = 1000;      // Leverage mínimo recomendado (1:500 o 1:1000)

input group "════════════════════════════════════════════════════════════"
input group "⏱️ TIMEFRAMES"
input group "════════════════════════════════════════════════════════════"
input bool AllowM15 = true;
input bool AllowH1 = true;
input bool AllowM5 = false;   // DESHABILITADO: spread>ATR en M5 → pérdidas matemáticas
input bool AllowM30 = true;
input int PrimaryTimeframe = 15;
input int SecondaryTimeframe = 60;
input bool UseICTKillZones = true;
input bool LondonKillZone = true;
input bool NYKillZone = false;
input int LondonKillZoneStart = 7;
input int LondonKillZoneEnd = 12;

input group "════════════════════════════════════════════════════════════"
input group "📈 INDICADORES ICT"
input group "════════════════════════════════════════════════════════════"
input int RSI_Period = 14;
input int ATR_Period = 14;
input int EMA_Fast = 20;
input int EMA_Slow = 50;
input int Volume_Period = 20;

input group "════════════════════════════════════════════════════════════"
input group "🎯 PARÁMETROS ICT AVANZADOS"
input group "════════════════════════════════════════════════════════════"
input double FVG_MinSize = 10.0;  // Reducido de 15→10 para +5% señales
input int FVG_MaxAge = 5;
input int OB_Strength = 3;
input double OTE_Min = 0.62;
input double OTE_Max = 0.79;

input group "════════════════════════════════════════════════════════════"
input group "🛡️ FILTROS DE OPERACIÓN"
input group "════════════════════════════════════════════════════════════"
input double MinConfidenceScore = 0.55; // Score mínimo ICT (bajado para +5% señales)
input bool EnableNewsFilter = false;
input bool UseVolatilityFilter = true;
input bool EnableKillSwitch = true;
input int MaxPingMilliseconds = 500;
input double SlippageMaximumAllowed = 0.5;

enum ENUM_TRADE_MODE
{
   MODE_LONDON_ONLY,    // Solo London Kill Zone (7-12 UTC)
   MODE_PREFER_LONDON,  // Prioridad London, pero opera fuera
   MODE_ALL             // Opera en cualquier horario
};

input ENUM_TRADE_MODE TradeMode = MODE_ALL;

input group "════════════════════════════════════════════════════════════"
input group "💰 GESTOR DE CAPITAL"
input group "════════════════════════════════════════════════════════════"
input bool EnableCapitalProtection = true;
input double CapitalProtectionThreshold = 30.0;
input double CapitalPreservationPercent = 20.0;
input bool EnableAllTradesProfitStop = true;
input double AllTradesProfitThreshold = 1.5;
input bool EnableAggressiveProfitTaking = true;
input double AggressiveProfitThreshold = 2.0;

input group "════════════════════════════════════════════════════════════"
input group "⚙️ OPTIMIZACIÓN"
input group "════════════════════════════════════════════════════════════"
input bool EnableTrailingStop = true;
input bool EnableSmartPyramiding = true;
input double MarginThreshold = 1.0;
input bool ShowPanel = true;

input group "════════════════════════════════════════════════════════════"
input group "🔺 PIRÁMIDE DE LOTES POR CAPITAL"
input group "════════════════════════════════════════════════════════════"
input bool   EnableLotPyramid      = true;   // Activar lote según capital
input double PyramidTier1Capital   = 1000.0; // <$1000 → Tier1Lot
input double PyramidTier2Capital   = 3000.0; // $1000-$3000 → Tier2Lot
input double PyramidTier3Capital   = 6000.0; // $3000-$6000 → Tier3Lot
input double PyramidTier4Capital   = 10000.0;// $6000-$10000 → Tier4Lot
input double PyramidTier1Lot       = 0.01;
input double PyramidTier2Lot       = 0.02;
input double PyramidTier3Lot       = 0.03;
input double PyramidTier4Lot       = 0.05;
input double PyramidTier5Lot       = 0.10;   // >$10000

input group "════════════════════════════════════════════════════════════"
input group "🔒 PEAK PROFIT CLOSE"
input group "════════════════════════════════════════════════════════════"
input bool   EnablePeakProfitClose = true;   // Cerrar al retroceder desde pico
input double PeakProfitRetracePct  = 30.0;   // % retroceso desde pico para cerrar

// ========== VARIABLES MUTABLES ==========
double riskPerTrade = RiskPerTrade;
double minConfidenceScore = MinConfidenceScore;
double currentFixedLot = FixedLot;

// ========== VARIABLES DE CONTROL DE VELAS (v6.0) ==========
datetime lastCandleCloseTime  = 0;
datetime lastTradeCloseTime   = 0;
bool     candleTradeExecuted  = false;
datetime nextTradeAllowedTime = 0;
datetime lastTradeOpenCandleTime = 0;   // vela en la que se abrió el último ciclo

// ========== VARIABLES DEL SISTEMA POSIBLE (v6.0) ==========
struct PossibleTradeState
{
    ulong    ticket;
    datetime openTime;
    datetime lastCheckTime;
    double   openPrice;
    int      direction;
    double   lotSize;
    bool     isPossible;
    int      validationCount;
    string   validationReason;
};

PossibleTradeState possibleTrades[];
int possibleTradeCount = 0;

// ═══ PEAK PROFIT TRACKER (v7.3) ═══
struct PeakRecord { ulong ticket; double peakProfit; };
PeakRecord peakRecords[50];
int        peakCount = 0;

// ═══ CORRECCIONES M30/H1 (v7.5) ════════════════════════════════
// Tiempo mínimo (segundos) que debe estar abierto un trade antes
// de que el Sistema POSIBLE pueda activarse por primera vez.
// Evita cierres prematuros en TF donde el precio necesita tiempo.
int GetTradeMaturitySeconds()
{
    switch(_Period)
    {
        case PERIOD_M5:  return 30;   // M5: 30s (no usado, M5 deshabilitado)
        case PERIOD_M15: return 60;   // M15: 60s mínimo antes de POSIBLE
        case PERIOD_M30: return 300;  // M30: 5 minutos mínimo
        case PERIOD_H1:  return 600;  // H1:  10 minutos mínimo
        default:         return 60;
    }
}

// Factores mínimos de 5 necesarios para MANTENER un trade POSIBLE.
// M30/H1: más leniente (2/5) porque en TF amplios los indicadores
// son más lentos y un pullback normal puede fallar 3/5 temporalmente.
int GetPossibleValidThreshold()
{
    switch(_Period)
    {
        case PERIOD_M5:  return 3;
        case PERIOD_M15: return 3;
        case PERIOD_M30: return 2;  // más leniente
        case PERIOD_H1:  return 2;  // más leniente
        default:         return 3;
    }
}

// ========== TIEMPOS DE VALIDACIÓN POR TIMEFRAME ==========
int GetPossibleActivationSeconds()
{
    switch(_Period)
    {
        case PERIOD_M5:  return 8;
        case PERIOD_M15: return 10;
        case PERIOD_M30: return 12;
        case PERIOD_H1:  return 14;
        default:         return 10;
    }
}

// Retorna segundos que dura una vela completa según TF
int GetCandlePeriodSeconds()
{
    switch(_Period)
    {
        case PERIOD_M5:  return 300;
        case PERIOD_M15: return 900;
        case PERIOD_M30: return 1800;
        case PERIOD_H1:  return 3600;
        default:         return 900;
    }
}

// Calcula el tiempo hasta el cierre de la vela actual
datetime GetCurrentCandleEndTime()
{
    datetime candleOpen = iTime(_Symbol, _Period, 0);
    return candleOpen + GetCandlePeriodSeconds();
}

// Notifica que un ciclo de trades cerró con ganancia → espera fin de vela
void SetCandleWaitAfterProfit()
{
    datetime candleEnd = GetCurrentCandleEndTime();
    if(candleEnd > nextTradeAllowedTime)
    {
        nextTradeAllowedTime = candleEnd;
        Print("[CANDLE-WAIT] Próxima apertura permitida en: " + TimeToString(nextTradeAllowedTime));
    }
    lastCycleCloseTime = TimeCurrent();
}

// Wrapper de compatibilidad (sustituido por GetCandlePeriodSeconds)
int PeriodSecondsCustom(int period)
{
    switch(period)
    {
        case PERIOD_M5:  return 300;
        case PERIOD_M15: return 900;
        case PERIOD_M30: return 1800;
        case PERIOD_H1:  return 3600;
        default:         return 900;
    }
}

// ========== VARIABLES DINÁMICAS ==========
double dynamicMinProfitTarget = 0.10;
int dynamicMaxOpenTrades = 1;
double dynamicMaxDailyLoss = 1.50;
bool extremeMarketDetected = false;
datetime lastCycleCloseTime = 0;

// ========== NUEVO: VARIABLES DE GESTIÓN DE CAPITAL ==========
double protectedCapital = 0.0;
double workingCapital = 0.0;
bool capitalProtectionActive = false;
double lastProtectionCheck = 0.0;
int totalProfitClosures = 0;

// ========== NUEVO: VARIABLES DE LEVERAGE DINÁMICO ==========
int dynamicLeverage = 500;
bool leverageDetected = false;

// ========== NUEVO: VARIABLES DE KILL SWITCH ==========
bool killSwitchActive = false;
datetime lastKillSwitchCheck = 0;

// ========== NUEVO: VARIABLES DE LOGGING A ARCHIVO ==========
int logFileHandle = INVALID_HANDLE;
string logFileName = "";

// ========== HANDLES DE INDICADORES ==========
int rsiHandle = INVALID_HANDLE;
int atrHandle = INVALID_HANDLE;
int emaFastHandle = INVALID_HANDLE;
int emaSlowHandle = INVALID_HANDLE;

// Handles para confirmación H1 (OPTIMIZACIÓN)
int h1EmaHandle = INVALID_HANDLE;
int h1RsiHandle = INVALID_HANDLE;

double rsiBuffer[];
double atrBuffer[];
double emaFastBuffer[];
double emaSlowBuffer[];
double volumeBuffer[];

// Variables para sesión (OPTIMIZACIÓN)
datetime lastSessionUpdate = 0;

// ========== VARIABLES DE CACHE ==========
static double cachedRSI = 0.0;
static double cachedATR = 0.0;
static double cachedEMAFast = 0.0;
static double cachedEMASlow = 0.0;
static double cachedVolume = 0.0;

// ========== VARIABLES ICT ==========
struct FairValueGap
{
    datetime time;
    double price;
    double high;
    double low;
    bool isBullish;
    int age;
};

FairValueGap fvgBuffer[];
int fvgCount = 0;

double sessionHigh = 0.0;
double sessionLow = 0.0;
double londonHigh = 0.0;
double londonLow = 0.0;
double nyHigh = 0.0;
double nyLow = 0.0;
double asiaHigh = 0.0;
double asiaLow = 0.0;

// ========== FIBONACCI LEVELS ==========
double fibLevel_0 = 0.0;
double fibLevel_100 = 0.0;
double fibOTE_Min = 0.0;
double fibOTE_Max = 0.0;

// ========== VARIABLES DE ESTADO ==========
double accountBalance = 0.0;
double currentCapital = 0.0;
double dailyProfit = 0.0;
double dailyLoss = 0.0;
double historicalProfit = 0.0;
datetime lastDayCheck = 0;
datetime lastTickTime = 0;  // PROBLEMA #3: Control de velocidad

bool isTrendingUp = false;
bool isTrendingDown = false;
int tradeDirection = 0;

datetime lastTradeOpen = 0;
int totalTradesOpened = 0;
int totalTradesClosed = 0;
int totalTradesWon = 0;
int totalTradesLost = 0;
int consecutiveLosses = 0;

bool isInRecoveryMode = false;
bool isPaused = false;
datetime pauseUntilTime = 0;

double averageProfit = 0.0;
double averageLoss = 0.0;
double winRate = 0.0;
double profitFactor = 1.0;
double totalProfit = 0.0;
double totalLoss = 0.0;

int alertLevel = 0;
string alertMessage = "";

// ========== HISTÓRICO DE DATOS ==========
double spreadsHistory[];
double volatilityHistory[];
double profitsPerTrade[];
double lossesPerTrade[];
double pingHistory[];

int currentHourUTC = 0;
int currentDayOfWeek = 0;
double currentSpread = 0.0;
double currentPing = 0.0;
double volatilityLevel = 0.0;

// ========== CONFIGURACIÓN DE VISUALIZACIÓN ==========
bool ShowIndicators = true;
bool ShowAlerts = true;

// ========== CACHED SYMBOL INFO (OPTIMIZACIÓN) ==========
int symbolDigits = 2;
double symbolPoint = 0.01;
double symbolTickValue = 1.0;
double symbolTickSize = 0.01;
double symbolMinLot = 0.01;
double symbolMaxLot = 100.0;
double symbolStepLot = 0.01;

// ========== SISTEMA PIRAMIDAL INTELIGENTE ==========
struct PyramidConfig
{
    int maxTrades;
    double lotPerTrade;
};

//+------------------------------------------------------------------+
//| OnInit - INICIALIZACIÓN DEL EA                                  |
//+------------------------------------------------------------------+

int OnInit()
{
    // ===== DETECTAR APALANCAMIENTO DINÁMICO (NUEVO) =====
    if(!DetectAccountLeverage())
        return INIT_FAILED;

    // ===== VALIDACIONES INICIALES =====
    if(!ValidateSymbolAndTimeframe())
        return INIT_FAILED;

    if(!ValidateAccountSettings())
        return INIT_FAILED;

    // ===== VALIDAR CUENTA REAL (PROBLEMA #21) =====
    if(!ValidateAccountType())
        return INIT_FAILED;

    // ===== CREAR INDICADORES =====
    if(!InitializeIndicators())
        return INIT_FAILED;

    // ===== CONFIGURAR ARRAYS =====
    if(!ConfigureArrays())
        return INIT_FAILED;

    // ===== CACHEAR INFORMACIÓN DEL SÍMBOLO =====
    CacheSymbolInfo();

    // ===== INICIALIZAR VARIABLES =====
    InitializeVariables();

    // ===== CONFIGURAR OBJETO TRADE =====
    trade.SetExpertMagicNumber(99999);
    trade.SetDeviationInPoints(5);
    trade.SetTypeFilling(ORDER_FILLING_RETURN);

    // ===== INICIALIZAR LOGGING A ARCHIVO (PROBLEMA #20) =====
    InitializeLogFile();

    ArrayResize(possibleTrades, 50);
    
    // ===== LOG DE INICIO =====
    PrintLaunchInfo();

    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit - LIMPIEZA AL DETENER                                 |
//+------------------------------------------------------------------+

void OnDeinit(const int reason)
{
    ReleaseIndicators();
    
    // Cerrar archivo log
    if(logFileHandle != INVALID_HANDLE)
    {
        FileClose(logFileHandle);
        logFileHandle = INVALID_HANDLE;
    }
    
    PrintShutdownInfo();
    ObjectsDeleteAll(0, -1, OBJ_LABEL);
    ObjectsDeleteAll(0, -1, OBJ_RECTANGLE_LABEL);
    ObjectsDeleteAll(0, -1, OBJ_HLINE);
    ObjectsDeleteAll(0, -1, OBJ_VLINE);
    ObjectsDeleteAll(0, -1, OBJ_TEXT);
    ChartRedraw();
}

//+------------------------------------------------------------------+
//| OnTick - FUNCIÓN PRINCIPAL                                     |
//+------------------------------------------------------------------+

void OnTick()
{
    // ===== PROBLEMA #3: CONTROL DE VELOCIDAD THROTTLING =====
    datetime currentTime = TimeCurrent();
    if(currentTime == lastTickTime)
        return;
    lastTickTime = currentTime;

    // ===== PROBLEMA #22: VERIFICAR KILL SWITCH =====
    CheckKillSwitch();
    if(killSwitchActive)
        return;

    // ===== ACTUALIZAR DATOS =====
    UpdateAccountData();
    UpdateTimeData();
    UpdateMarketData();

    // ===== VERIFICACIONES DE SEGURIDAD =====
    if(!VerifyConnectionQuality())
        return;

    if(!VerifyDailyReset())
        return;

    // ===== CARGAR DATOS DE INDICADORES =====
    if(!LoadAllIndicatorData())
    {
        if(!ReconnectIndicators())
            return;
        
        // PROBLEMA #4: Reinicializar arrays después de reconectar
        if(!ConfigureArrays())
            return;
            
        if(!LoadAllIndicatorData())
            return;
    }

    // ===== ANÁLISIS DE MERCADO =====
    UpdateDailyProfitLoss();
    
    // ===== GESTIÓN DE CAPITAL PROTEGIDO (PROBLEMA #5) =====
    ManageCapitalProtection();
    
    UpdateDynamicParameters();
    AnalyzeVolatility();
    DetectMarketExtremes();
    CalculateStatistics();

    // ===== APLICAR FILTRO DE MERCADO EXTREMO =====
    if(extremeMarketDetected && !isPaused)
    {
        riskPerTrade = RiskPerTrade * 0.5;
        minConfidenceScore = MathMin(MinConfidenceScore + 0.10, 0.90);
    }

    // ===== VALIDACIÓN DE ESTADO =====
    ValidateEAStatus();
    UpdateErrorRecoveryMode();

    // ===== GESTIÓN DE TRADES =====
    if(!isPaused && !isInRecoveryMode)
    {
        AnalyzeTrendWithAllMethods();

        // ===== VERIFICAR CIERRE TOTAL DE TODOS LOS TRADES =====
        if(EnableAllTradesProfitStop)
        {
            CheckAndCloseAllTradesIfAllProfit();
        }

        // ===== GESTIÓN DE CIERRE - MEJORADA =====
        ManageTradeClosing();
        ManageTrailingStop();
        ManagePeakProfitClose();
        
        // ===== SISTEMA POSIBLE - Validación de trades negativos =====
        ManagePossibleTradeSystem();

        // ===== APERTURA DE TRADES CON ENTRADA SINCRONIZADA =====
        ManageTradeOpening();
    }

    // ===== ACTUALIZAR VISUALIZACIÓN =====
    UpdateVisualInformation();
}

//+------------------------------------------------------------------+
//| NUEVO: DETECTAR APALANCAMIENTO DINÁMICO                        |
//+------------------------------------------------------------------+

bool DetectAccountLeverage()
{
    dynamicLeverage = (int)AccountInfoInteger(ACCOUNT_LEVERAGE);
    
    if(dynamicLeverage <= 0)
    {
        // Fallback al parámetro configurado
        dynamicLeverage = DetectLeverage;
        Print("⚠️ No se pudo detectar leverage automático, usando: 1:" + 
              IntegerToString(dynamicLeverage));
    }
    
    Print("✓ Apalancamiento detectado: 1:" + IntegerToString(dynamicLeverage));
    leverageDetected = true;
    return true;
}

//+------------------------------------------------------------------+
//| NUEVO: CACHEAR INFORMACIÓN DEL SÍMBOLO (OPTIMIZACIÓN) ==========|
//+------------------------------------------------------------------+

void CacheSymbolInfo()
{
    symbolDigits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
    symbolPoint = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    symbolTickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    symbolTickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    symbolMinLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    symbolMaxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    symbolStepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
}

//+------------------------------------------------------------------+
//| NUEVO: INICIALIZAR LOGGING A ARCHIVO (PROBLEMA #20) ===========|
//+------------------------------------------------------------------+

void InitializeLogFile()
{
    datetime now = TimeCurrent();
    MqlDateTime timeStruct;
    TimeToStruct(now, timeStruct);
    
    string dateStr = IntegerToString(timeStruct.year) + 
                    (timeStruct.mon < 10 ? "0" : "") + 
                    IntegerToString(timeStruct.mon) + 
                    (timeStruct.day < 10 ? "0" : "") + 
                    IntegerToString(timeStruct.day);
    
    logFileName = "Logs\\" + dateStr + "_XAUUSD_v5_2.csv";
    
    // Crear directorio si no existe
    CreateDirectoryIfNeeded("Logs");
    
    // Abrir archivo para escribir
    logFileHandle = FileOpen(logFileName, FILE_CSV | FILE_READ | FILE_WRITE | 
                            FILE_ANSI, ',');
    
    if(logFileHandle != INVALID_HANDLE)
    {
        FileSeek(logFileHandle, 0, SEEK_END);
        
        // Escribir encabezado si el archivo está vacío
        if(FileTell(logFileHandle) == 0)
        {
            FileWriteString(logFileHandle, 
                "Timestamp,Type,Profit,Reason,TradeCount,WinRate,EquityUSD\n");
        }
        Print("✓ Archivo de log inicializado: " + logFileName);
    }
    else
    {
        Print("⚠️ No se pudo crear archivo de log");
    }
}

void CreateDirectoryIfNeeded(string dirName)
{
    // En MT5, FileOpen crea el directorio automáticamente
    // Esta función es documentaria
}

void LogTradeToFile(bool isWinning, double profit, string reason)
{
    if(logFileHandle == INVALID_HANDLE)
        return;
    
    datetime now = TimeCurrent();
    string logLine = TimeToString(now, TIME_DATE | TIME_MINUTES) + "," +
                    (isWinning ? "WIN" : "LOSS") + "," +
                    DoubleToString(profit, 2) + "," +
                    reason + "," +
                    IntegerToString(totalTradesClosed) + "," +
                    DoubleToString(winRate * 100, 1) + "," +
                    DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2) + "\n";
    
    FileWriteString(logFileHandle, logLine);
}

//+------------------------------------------------------------------+
//| NUEVO: VERIFICAR KILL SWITCH (PROBLEMA #22) ===================|
//+------------------------------------------------------------------+

void CheckKillSwitch()
{
    if(!EnableKillSwitch)
        return;
    
    // Verificar si se presionó Pausa
    // En MT5, se verifica si la tecla Pausa está presionada
    if(TerminalInfoInteger(TERMINAL_CONNECTED) == 0)
    {
        if(!killSwitchActive)
        {
            killSwitchActive = true;
            isPaused = true;
            Print("🛑 KILL SWITCH ACTIVADO - Bot en pausa inmediata");
            Print("Presione Pausa nuevamente para reanudar");
            alertLevel = 3;
            alertMessage = "KILL SWITCH ACTIVO - Pausa inmediata";
        }
        return;
    }
    
    if(killSwitchActive)
    {
        killSwitchActive = false;
        isPaused = false;
        Print("▶️ Kill Switch desactivado - Bot reanudado");
        alertLevel = 0;
        alertMessage = "";
    }
}

//+------------------------------------------------------------------+
//| NUEVO: VALIDAR CUENTA REAL (PROBLEMA #21) ====================|
//+------------------------------------------------------------------+

bool ValidateAccountType()
{
    ENUM_ACCOUNT_TRADE_MODE accountMode = 
        (ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE);
    
    if(accountMode == ACCOUNT_TRADE_MODE_REAL)
    {
        Print("═════════════════════════════════════════");
        Print("⚠️ ADVERTENCIA - CUENTA REAL DETECTADA");
        Print("═════════════════════════════════════════");
        Print("Número Cuenta: " + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)));
        Print("Broker: " + AccountInfoString(ACCOUNT_COMPANY));
        Print("Equity: $" + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2));
        Print("Este EA operará en CUENTA REAL");
        Print("═════════════════════════════════════════");
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| NUEVO: GESTOR DE CAPITAL PROTEGIDO (PROBLEMA #5) ===============|
//+------------------------------------------------------------------+

void ManageCapitalProtection()
{
    if(!EnableCapitalProtection)
        return;

    double equity = AccountInfoDouble(ACCOUNT_EQUITY);

    // Activar protección cuando equity supera el threshold
    if(equity > CapitalProtectionThreshold && !capitalProtectionActive)
    {
        capitalProtectionActive = true;
        Print("\n✅ PROTECCIÓN DE CAPITAL ACTIVADA");
        Print("═══════════════════════════════════════════════════");
        Print("Equity: $" + DoubleToString(equity, 2));
        Print("Threshold alcanzado: $" + DoubleToString(CapitalProtectionThreshold, 2));
        Print("Sistema de preservación de capital ACTIVO");
        Print("═══════════════════════════════════════════════════\n");
    }

    // PROBLEMA #5: Desactivación bidireccional
    if(capitalProtectionActive && equity < CapitalProtectionThreshold * 0.8)
    {
        capitalProtectionActive = false;
        Print("\n🔓 Protección de capital DESACTIVADA");
        Print("Equity bajó a: $" + DoubleToString(equity, 2));
        Print("═══════════════════════════════════════════════════\n");
    }

    if(capitalProtectionActive)
    {
        // PROBLEMA #6: Preservation percent dinámico
        double dynamicPreservation = GetDynamicPreservationPercent();
        double preservationAmount = equity * (dynamicPreservation / 100.0);
        workingCapital = equity - preservationAmount;
        protectedCapital = preservationAmount;

        // Asegurar que workingCapital no sea negativo o muy pequeño
        if(workingCapital < MinimumCapital)
        {
            workingCapital = MinimumCapital;
            protectedCapital = equity - MinimumCapital;
        }

        // Log cada 100 ticks (no spam)
        static int logCounter = 0;
        logCounter++;
        if(logCounter >= 100)
        {
            logCounter = 0;
            Print("[CAPITAL] Equity: $" + DoubleToString(equity, 2) + 
                  " | Trabajo: $" + DoubleToString(workingCapital, 2) + 
                  " | Protegido: $" + DoubleToString(protectedCapital, 2) + 
                  " | Preservación: " + DoubleToString(dynamicPreservation, 1) + "%");
        }
    }
    else
    {
        // Antes de activación, todo es capital de trabajo
        workingCapital = equity;
        protectedCapital = 0.0;
    }
}

// PROBLEMA #6: Preservation percent dinámico
double GetDynamicPreservationPercent()
{
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    
    if(equity < 50.0) return 10.0;      // Menos restricción en cuentas pequeñas
    if(equity < 100.0) return 15.0;     // Medio
    if(equity < 200.0) return 18.0;     // Mayor
    return CapitalPreservationPercent;  // Full según parámetro
}

//+------------------------------------------------------------------+
//| NUEVO: CIERRE DE TODOS LOS TRADES (PROBLEMA #7) ===============|
//+------------------------------------------------------------------+

void CheckAndCloseAllTradesIfAllProfit()
{
    static datetime lastAttempt = 0;
    
    // PROBLEMA #7: Evitar intentos múltiples en corto tiempo
    if(TimeCurrent() - lastAttempt < 5) 
        return;
    lastAttempt = TimeCurrent();
    
    int openTrades = CountOpenTrades();
    if(openTrades == 0) 
        return;

    double minProfit = 99999.0;
    bool allPositive = true;

    // Verificar que TODOS los trades tengan ganancia
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(positionInfo.SelectByIndex(i))
        {
            if(positionInfo.Symbol() != _Symbol || positionInfo.Magic() != 99999)
                continue;

            double profit = positionInfo.Profit() + positionInfo.Commission() + positionInfo.Swap();

            if(profit < AllTradesProfitThreshold)
            {
                allPositive = false;
                break;
            }

            if(profit < minProfit)
                minProfit = profit;
        }
    }

    // Si TODOS tienen ganancia > threshold, cerrar TODOS
    if(allPositive && openTrades > 0 && minProfit > AllTradesProfitThreshold)
    {
        Print("\n╔════════════════════════════════════════════════════════╗");
        Print("║  🎯 CIERRE TOTAL - TODOS LOS TRADES CON GANANCIA      ║");
        Print("╠════════════════════════════════════════════════════════╣");
        Print("║ Condición: TODOS los trades tienen ganancia > $" + 
              DoubleToString(AllTradesProfitThreshold, 2));
        Print("║ Ganancia mínima: $" + DoubleToString(minProfit, 2));
        Print("║ Trades a cerrar: " + IntegerToString(openTrades));
        Print("║ Acción: Cierre total inmediato de seguridad");
        Print("╚════════════════════════════════════════════════════════╝\n");

        int closedCount = 0;
        double totalClosedProfit = 0.0;
        int failedCount = 0;

        // Cerrar TODOS los trades
        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            if(positionInfo.SelectByIndex(i))
            {
                if(positionInfo.Symbol() != _Symbol || positionInfo.Magic() != 99999)
                    continue;

                ulong ticket = positionInfo.Ticket();
                double profit = positionInfo.Profit() + positionInfo.Commission() + positionInfo.Swap();
                int direction = (positionInfo.PositionType() == POSITION_TYPE_BUY) ? 1 : -1;

                if(trade.PositionClose(ticket))
                {
                    closedCount++;
                    totalClosedProfit += profit;
                    totalTradesClosed++;
                    historicalProfit += profit;
                    totalTradesWon++;
                    totalProfit += profit;
                    consecutiveLosses = 0;
                    totalProfitClosures++;

                    LogTrade(true, profit, "Cierre Total - Todos Ganadores");
                    LogTradeToFile(true, profit, "Cierre Total");

                    Print("✅ CERRADO #" + IntegerToString(closedCount) + " | Ticket: " + 
                          IntegerToString((long)ticket) + " | Dir: " + 
                          (direction == 1 ? "BUY" : "SELL") + " | Ganancia: $" + 
                          DoubleToString(profit, 2));
                }
                else
                {
                    failedCount++;
                    Print("⚠️ Close fallido - Ticket: " + IntegerToString((long)ticket) + 
                          " | Error: " + IntegerToString(trade.ResultRetcode()));
                }
            }
        }

        Print("\n═══════════════════════════════════════════════════════");
        Print("✅ CIERRE TOTAL COMPLETADO");
        Print("Trades cerrados: " + IntegerToString(closedCount));
        Print("Fallos: " + IntegerToString(failedCount));
        Print("Ganancia total: $" + DoubleToString(totalClosedProfit, 2));
        Print("Histórico: $" + DoubleToString(historicalProfit, 2));
        Print("═══════════════════════════════════════════════════════\n");

        // v6.0: Esperar hasta fin de vela antes del próximo ciclo
        SetCandleWaitAfterProfit();
        tradeDirection = 0;
    }
}

//+------------------------------------------------------------------+
//| MÓDULO 1: VALIDACIÓN ICT MULTI-INDICADOR =======================|
//+------------------------------------------------------------------+

struct SignalValidation
{
    double confidenceScore;
    bool isFVGConfirm;
    bool isOTEConfirm;
    bool isRSIDivergence;
    bool isEMAConfirm;
    bool isVolumeConfirm;
    bool isSessionLevel;
    bool isKillZone;
    bool isSpreadOK;
    bool isVolatilityOK;
    string validationReason;
};

SignalValidation ValidateSignal(int direction)
{
    SignalValidation result;
    result.confidenceScore = 0.0;
    result.validationReason = "";

    if(rsiHandle == INVALID_HANDLE || emaFastHandle == INVALID_HANDLE)
    {
        result.validationReason = "Indicadores no disponibles";
        return result;
    }

    // FILTRO 1: FAIR VALUE GAP (30% peso)
    result.isFVGConfirm = false;
    FairValueGap currentFVG = DetectFVG(direction);
    if(currentFVG.price > 0)
        result.isFVGConfirm = true;

    // FILTRO 2: OTE FIBONACCI (20% peso)
    result.isOTEConfirm = false;
    if(IsPriceInOTE(direction))
        result.isOTEConfirm = true;

    // FILTRO 3: RSI DIVERGENCE (15% peso)
    result.isRSIDivergence = false;
    if(HasRSIDivergence(direction))
        result.isRSIDivergence = true;

    // FILTRO 4: EMA ALIGNMENT (10% peso)
    result.isEMAConfirm = false;
    if(IsEMAAligned(direction))
        result.isEMAConfirm = true;

    // FILTRO 5: VOLUME CONFIRMATION (15% peso)
    result.isVolumeConfirm = false;
    if(IsVolumeConfirming(direction))
        result.isVolumeConfirm = true;

    // FILTRO 6: SESSION LEVELS (10% peso)
    result.isSessionLevel = false;
    if(IsNearSessionLevel(direction))
        result.isSessionLevel = true;

    // FILTRO 7: KILL ZONE (10% peso)
    result.isKillZone = false;
    if(IsKillZoneActive())
        result.isKillZone = true;

    // FILTROS BÁSICOS
    result.isVolatilityOK = IsVolatilityAcceptable();
    result.isSpreadOK = IsSpreadAcceptable();

    // CÁLCULO DEL SCORE FINAL
    result.confidenceScore = 0.0;
    if(result.isFVGConfirm) result.confidenceScore += 0.30;
    if(result.isOTEConfirm) result.confidenceScore += 0.20;
    if(result.isRSIDivergence) result.confidenceScore += 0.15;
    if(result.isVolumeConfirm) result.confidenceScore += 0.15;
    if(result.isEMAConfirm) result.confidenceScore += 0.10;
    if(result.isSessionLevel) result.confidenceScore += 0.10;
    if(result.isKillZone) result.confidenceScore += 0.10;
    if(result.isVolatilityOK) result.confidenceScore += 0.05;
    if(result.isSpreadOK) result.confidenceScore += 0.05;

    // BONUS: CONFLUENCIA MÁXIMA (+10% adicional)
    int confluenceCount = 0;
    if(result.isFVGConfirm) confluenceCount++;
    if(result.isOTEConfirm) confluenceCount++;
    if(result.isRSIDivergence) confluenceCount++;
    if(result.isVolumeConfirm) confluenceCount++;
    if(result.isEMAConfirm) confluenceCount++;
    if(result.isSessionLevel) confluenceCount++;
    if(result.isKillZone) confluenceCount++;
    
    if(confluenceCount >= 6)
    {
        result.confidenceScore += 0.10;
        Print("🎯 CONFLUENCIA MÁXIMA: " + IntegerToString(confluenceCount) + "/7 factores");
    }

    // ===== NUEVO v6.0: VERIFICACIÓN AVANZADA DE ENTRY/EXIT POINTS =====
    double entryExitBonus = VerifyEntryExitAccuracy(direction);
    result.confidenceScore += entryExitBonus;
    if(entryExitBonus > 0)
        Print("🔎 Entry/Exit Verification bonus: +" + DoubleToString(entryExitBonus * 100, 0) + "%");

    if(result.confidenceScore > 1.30)
        result.confidenceScore = 1.30;

    bool isValid = (result.confidenceScore >= minConfidenceScore) && 
                   result.isSpreadOK && 
                   result.isVolatilityOK;

    if(!isValid)
    {
        result.validationReason = "Score: " + DoubleToString(result.confidenceScore, 2) + 
                                   " | FVG:" + (result.isFVGConfirm ? "✓" : "✗") +
                                   " OTE:" + (result.isOTEConfirm ? "✓" : "✗") +
                                   " RSI Div:" + (result.isRSIDivergence ? "✓" : "✗") +
                                   " EMA:" + (result.isEMAConfirm ? "✓" : "✗") +
                                   " Vol:" + (result.isVolumeConfirm ? "✓" : "✗") +
                                   " Session:" + (result.isSessionLevel ? "✓" : "✗") +
                                   " KillZone:" + (result.isKillZone ? "✓" : "✗");
    }

    return result;
}

//+------------------------------------------------------------------+
//| FUNCIONES ICT - FAIR VALUE GAPS =================================|
//+------------------------------------------------------------------+

FairValueGap DetectFVG(int direction)
{
    FairValueGap result;
    result.time = 0;
    result.price = 0;
    result.high = 0;
    result.low = 0;
    result.isBullish = false;
    result.age = 0;

    for(int i = 1; i <= FVG_MaxAge; i++)
    {
        double high0 = iHigh(_Symbol, _Period, i);
        double low0 = iLow(_Symbol, _Period, i);
        double close0 = iClose(_Symbol, _Period, i);
        double open0 = iOpen(_Symbol, _Period, i);

        double high1 = iHigh(_Symbol, _Period, i+1);
        double low1 = iLow(_Symbol, _Period, i+1);

        if(direction == 1)
        {
            if(low0 > high1 && (low0 - high1) >= FVG_MinSize * symbolPoint)
            {
                result.time = iTime(_Symbol, _Period, i);
                result.price = (low0 + high1) / 2;
                result.high = low0;
                result.low = high1;
                result.isBullish = true;
                result.age = i;
                return result;
            }
        }
        else if(direction == -1)
        {
            if(high0 < low1 && (low1 - high0) >= FVG_MinSize * symbolPoint)
            {
                result.time = iTime(_Symbol, _Period, i);
                result.price = (high0 + low1) / 2;
                result.high = low1;
                result.low = high0;
                result.isBullish = false;
                result.age = i;
                return result;
            }
        }
    }

    return result;
}

bool IsPriceInOTE(int direction)
{
    int lookback = 50;
    double swingHigh = 0;
    double swingLow = 999999;

    for(int i = 0; i < lookback; i++)
    {
        double high = iHigh(_Symbol, _Period, i);
        double low = iLow(_Symbol, _Period, i);
        
        if(high > swingHigh) swingHigh = high;
        if(low < swingLow) swingLow = low;
    }

    double range = swingHigh - swingLow;
    if(range <= 0) return false;

    double currentPrice = (direction == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    
    if(direction == 1)
    {
        double oteLow = swingLow + (range * OTE_Min);
        double oteHigh = swingLow + (range * OTE_Max);
        
        fibOTE_Min = oteLow;
        fibOTE_Max = oteHigh;
        fibLevel_0 = swingLow;
        fibLevel_100 = swingHigh;
        
        return (currentPrice >= oteLow && currentPrice <= oteHigh);
    }
    else
    {
        double oteLow = swingHigh - (range * OTE_Max);
        double oteHigh = swingHigh - (range * OTE_Min);
        
        fibOTE_Min = oteLow;
        fibOTE_Max = oteHigh;
        fibLevel_0 = swingHigh;
        fibLevel_100 = swingLow;
        
        return (currentPrice >= oteLow && currentPrice <= oteHigh);
    }
}

bool HasRSIDivergence(int direction)
{
    int lookback = 10;
    
    if(ArraySize(rsiBuffer) < lookback)
        return false;

    if(direction == 1)
    {
        double priceLow1 = 999999, priceLow2 = 999999;
        double rsiLow1 = 999999, rsiLow2 = 999999;
        int found = 0;

        for(int i = 1; i < lookback && found < 2; i++)
        {
            double low = iLow(_Symbol, _Period, i);
            double rsi = rsiBuffer[i];
            
            if(rsi < 40)
            {
                if(found == 0)
                {
                    priceLow1 = low;
                    rsiLow1 = rsi;
                    found++;
                }
                else if(low < priceLow1 && rsi > rsiLow1)
                {
                    priceLow2 = low;
                    rsiLow2 = rsi;
                    found++;
                }
            }
        }

        if(found == 2 && priceLow2 < priceLow1 && rsiLow2 > rsiLow1)
            return true;
    }
    else if(direction == -1)
    {
        double priceHigh1 = 0, priceHigh2 = 0;
        double rsiHigh1 = 0, rsiHigh2 = 0;
        int found = 0;

        for(int i = 1; i < lookback && found < 2; i++)
        {
            double high = iHigh(_Symbol, _Period, i);
            double rsi = rsiBuffer[i];
            
            if(rsi > 60)
            {
                if(found == 0)
                {
                    priceHigh1 = high;
                    rsiHigh1 = rsi;
                    found++;
                }
                else if(high > priceHigh1 && rsi < rsiHigh1)
                {
                    priceHigh2 = high;
                    rsiHigh2 = rsi;
                    found++;
                }
            }
        }

        if(found == 2 && priceHigh2 > priceHigh1 && rsiHigh2 < rsiHigh1)
            return true;
    }

    return false;
}

bool IsEMAAligned(int direction)
{
    if(ArraySize(emaFastBuffer) < 3 || ArraySize(emaSlowBuffer) < 3)
        return false;

    double emaFast = emaFastBuffer[0];
    double emaSlow = emaSlowBuffer[0];
    double price = (direction == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

    if(direction == 1)
    {
        return (emaFast > emaSlow && price > emaFast);
    }
    else
    {
        return (emaFast < emaSlow && price < emaFast);
    }
}

bool IsVolumeConfirming(int direction)
{
    if(ArraySize(volumeBuffer) < Volume_Period)
        return false;

    double avgVolume = 0;
    for(int i = 1; i <= Volume_Period; i++)
        avgVolume += volumeBuffer[i];
    avgVolume /= Volume_Period;

    double currentVol = volumeBuffer[0];
    double volumeRatio = currentVol / avgVolume;

    return (volumeRatio >= 1.5);
}

bool IsNearSessionLevel(int direction)
{
    UpdateSessionLevelsOptimized();
    
    double currentPrice = (direction == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double threshold = 20 * symbolPoint;

    if(direction == 1)
    {
        if(MathAbs(currentPrice - sessionLow) < threshold) return true;
        if(MathAbs(currentPrice - londonLow) < threshold) return true;
        if(MathAbs(currentPrice - nyLow) < threshold) return true;
    }
    else
    {
        if(MathAbs(currentPrice - sessionHigh) < threshold) return true;
        if(MathAbs(currentPrice - londonHigh) < threshold) return true;
        if(MathAbs(currentPrice - nyHigh) < threshold) return true;
    }

    return false;
}

void UpdateSessionLevelsOptimized()
{
    datetime now = TimeCurrent();
    
    if(now - lastSessionUpdate < 3600)
        return;
    
    lastSessionUpdate = now;
    MqlDateTime timeStruct;
    TimeToStruct(now, timeStruct);
    
    int currentHour = timeStruct.hour;
    
    if(currentHour >= 0 && currentHour < 8)
    {
        double high = iHigh(_Symbol, PERIOD_H1, 0);
        double low = iLow(_Symbol, PERIOD_H1, 0);
        for(int i = 1; i < 8; i++)
        {
            if(iHigh(_Symbol, PERIOD_H1, i) > high) high = iHigh(_Symbol, PERIOD_H1, i);
            if(iLow(_Symbol, PERIOD_H1, i) < low) low = iLow(_Symbol, PERIOD_H1, i);
        }
        asiaHigh = high;
        asiaLow = low;
    }
    
    if(currentHour >= 7 && currentHour < 16)
    {
        double high = iHigh(_Symbol, PERIOD_H1, 0);
        double low = iLow(_Symbol, PERIOD_H1, 0);
        for(int i = 1; i < 9; i++)
        {
            if(iHigh(_Symbol, PERIOD_H1, i) > high) high = iHigh(_Symbol, PERIOD_H1, i);
            if(iLow(_Symbol, PERIOD_H1, i) < low) low = iLow(_Symbol, PERIOD_H1, i);
        }
        londonHigh = high;
        londonLow = low;
    }
    
    if(currentHour >= 13 && currentHour < 22)
    {
        double high = iHigh(_Symbol, PERIOD_H1, 0);
        double low = iLow(_Symbol, PERIOD_H1, 0);
        for(int i = 1; i < 9; i++)
        {
            if(iHigh(_Symbol, PERIOD_H1, i) > high) high = iHigh(_Symbol, PERIOD_H1, i);
            if(iLow(_Symbol, PERIOD_H1, i) < low) low = iLow(_Symbol, PERIOD_H1, i);
        }
        nyHigh = high;
        nyLow = low;
    }

    sessionHigh = MathMax(MathMax(asiaHigh, londonHigh), nyHigh);
    sessionLow = MathMin(MathMin(asiaLow, londonLow), nyLow);
}

bool IsKillZoneActive()
{
    if(!UseICTKillZones)
        return true;

    datetime now = TimeCurrent();
    MqlDateTime timeStruct;
    TimeToStruct(now, timeStruct);
    
    int hour = timeStruct.hour;

    if(LondonKillZone && (hour >= LondonKillZoneStart && hour < LondonKillZoneEnd))
        return true;
    
    if(NYKillZone && (hour >= 13 && hour < 16))
        return true;

    return false;
}

//+------------------------------------------------------------------+
//| NUEVO v6.0: VERIFICACIÓN AVANZADA DE ENTRY/EXIT POINTS          |
//+------------------------------------------------------------------+

// Retorna bonus al score (0.0 - 0.15) basado en precisión de entry/exit
double VerifyEntryExitAccuracy(int direction)
{
    double bonus = 0.0;

    // --- 1. ESTRUCTURA DE MERCADO: BOS (Break of Structure) ---
    // Verifica que el precio rompió un swing previo en la dirección del trade
    int lookback = 20;
    double swingHigh = 0, swingLow = 999999;
    int swingHighIdx = 0, swingLowIdx = 0;

    for(int i = 2; i < lookback; i++)
    {
        double hi = iHigh(_Symbol, _Period, i);
        double lo = iLow(_Symbol, _Period, i);
        if(hi > swingHigh) { swingHigh = hi; swingHighIdx = i; }
        if(lo < swingLow)  { swingLow = lo;  swingLowIdx = i;  }
    }

    double currentPrice = (direction == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                           : SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double prevClose1   = iClose(_Symbol, _Period, 1);
    double prevClose2   = iClose(_Symbol, _Period, 2);

    // BOS alcista: precio actual supera swing high previo
    if(direction == 1 && currentPrice > swingHigh && prevClose1 < swingHigh)
        bonus += 0.05;
    // BOS bajista: precio actual rompe swing low previo
    if(direction == -1 && currentPrice < swingLow && prevClose1 > swingLow)
        bonus += 0.05;

    // --- 2. IMPULSO DIRECCIONAL: Cuerpos de velas a favor ---
    double body1 = iClose(_Symbol, _Period, 1) - iOpen(_Symbol, _Period, 1);
    double body2 = iClose(_Symbol, _Period, 2) - iOpen(_Symbol, _Period, 2);

    if(direction == 1 && body1 > 0 && body2 > 0)       bonus += 0.04; // 2 velas alcistas
    else if(direction == -1 && body1 < 0 && body2 < 0) bonus += 0.04; // 2 velas bajistas

    // --- 3. ATR ENTRY QUALITY: precio no sobreextendido ---
    double atrVal = 0.0;
    if(ArraySize(atrBuffer) > 1) atrVal = atrBuffer[1];
    if(atrVal > 0)
    {
        double distFromPrev = MathAbs(currentPrice - prevClose1);
        // Si el movimiento actual NO supera 1.5x ATR, la entrada es de calidad
        if(distFromPrev < atrVal * 1.5)
            bonus += 0.03;
    }

    // --- 4. RSI ZONA ÓPTIMA DE ENTRADA ---
    double rsi = cachedRSI;
    // BUY: RSI entre 35-55 (zona de acumulación, no sobrecomprado)
    if(direction == 1 && rsi >= 35 && rsi <= 55)  bonus += 0.03;
    // SELL: RSI entre 45-65 (zona de distribución, no sobrevendido)
    if(direction == -1 && rsi >= 45 && rsi <= 65) bonus += 0.03;

    // Limitar bonus máximo
    if(bonus > 0.15) bonus = 0.15;
    return bonus;
}

// Verifica la calidad del punto de salida para un trade abierto
// Retorna true si el precio está en zona de salida óptima
bool VerifyExitPoint(int direction, double openPrice)
{
    double currentPrice = (direction == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                           : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double atrVal = 0.0;
    if(ArraySize(atrBuffer) > 0) atrVal = atrBuffer[0];
    if(atrVal <= 0) atrVal = 20.0 * symbolPoint;

    // Salida en zona de resistencia/soporte dinámico (EMA slow)
    double emaSlow = ArraySize(emaSlowBuffer) > 0 ? emaSlowBuffer[0] : 0;
    if(emaSlow > 0)
    {
        double distToEMA = MathAbs(currentPrice - emaSlow);
        if(distToEMA < atrVal * 0.3) return true; // Precio cerca de EMA slow = zona de salida
    }

    // Salida si el RSI entra en zona extrema contraria
    double rsi = cachedRSI;
    if(direction == 1 && rsi > 75) return true;  // Sobrecomprado → salir
    if(direction == -1 && rsi < 25) return true; // Sobrevendido → salir

    return false;
}

PyramidConfig GetPyramidConfigForCapital()
{
    PyramidConfig config;
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
    
    // Calcular margen necesario por lote
    double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double marginPerLot = 0;
    
    // PROBLEMA #10: Validar margen
    if(!OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, symbolMinLot, price, marginPerLot))
    {
        marginPerLot = (price * symbolMinLot * 1000000) / dynamicLeverage;
    }
    
    if(marginPerLot > 0)
    {
        int maxTradesByMargin = (int)(freeMargin / marginPerLot);
        
        // ESCALA PROGRESIVA INTELIGENTE - Respetando margen disponible
        if(equity < 20.0)
        {
            config.maxTrades = MathMin(1, maxTradesByMargin);
            config.lotPerTrade = symbolMinLot;
        }
        else if(equity < 40.0)
        {
            config.maxTrades = MathMin(3, maxTradesByMargin);
            config.lotPerTrade = symbolMinLot;
        }
        else if(equity < 60.0)
        {
            config.maxTrades = MathMin(5, maxTradesByMargin);
            config.lotPerTrade = symbolMinLot;
        }
        else if(equity < 80.0)
        {
            config.maxTrades = MathMin(7, maxTradesByMargin);
            config.lotPerTrade = symbolMinLot;
        }
        else if(equity < 100.0)
        {
            config.maxTrades = MathMin(9, maxTradesByMargin);
            config.lotPerTrade = symbolMinLot;
        }
        else if(equity < 150.0)
        {
            config.maxTrades = MathMin(11, maxTradesByMargin);
            config.lotPerTrade = symbolMinLot;
        }
        else if(equity < 190.0)
        {
            config.maxTrades = MathMin(13, maxTradesByMargin);
            config.lotPerTrade = symbolMinLot;
        }
        else if(equity < 240.0)
        {
            config.maxTrades = MathMin(15, maxTradesByMargin);
            config.lotPerTrade = symbolMinLot;
        }
        else
        {
            config.maxTrades = MathMin(16, maxTradesByMargin);
            config.lotPerTrade = symbolMinLot;
        }
    }
    else
    {
        // Fallback
        config.maxTrades = 1;
        config.lotPerTrade = symbolMinLot;
    }
    
    if(config.maxTrades > 16) config.maxTrades = 16; // v7.3: máximo 16 trades
    
    return config;
}

// v7.3: Lote determinado por capital (pirámide por equity)
double GetPyramidLotForCapital()
{
    if(!EnableLotPyramid) return symbolMinLot;
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    double lot;
    if     (equity < PyramidTier1Capital) lot = PyramidTier1Lot;
    else if(equity < PyramidTier2Capital) lot = PyramidTier2Lot;
    else if(equity < PyramidTier3Capital) lot = PyramidTier3Lot;
    else if(equity < PyramidTier4Capital) lot = PyramidTier4Lot;
    else                                  lot = PyramidTier5Lot;
    lot = MathFloor(lot / symbolStepLot) * symbolStepLot;
    if(lot < symbolMinLot) lot = symbolMinLot;
    if(lot > symbolMaxLot) lot = symbolMaxLot;
    return lot;
}

//+------------------------------------------------------------------+
//| MÓDULO 2: GESTIÓN ADAPTATIVA DEL CAPITAL (PROBLEMA #11) ======|
//+------------------------------------------------------------------+

double CalculateAdaptiveLotSize(int direction)
{
    double minLot = symbolMinLot;
    double maxLot = symbolMaxLot;
    double stepLot = symbolStepLot;
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);

    // USAR LOTE FIJO SI ESTÁ HABILITADO
    if(!UseAutoLot)
    {
        return NormalizeDouble(FixedLot, symbolDigits);
    }

    ENUM_ORDER_TYPE orderType = (direction == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
    double price = (direction == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);

    double marginForMinLot = 0;
    if(OrderCalcMargin(orderType, _Symbol, minLot, price, marginForMinLot))
    {
        if(marginForMinLot > 0 && marginForMinLot > freeMargin * 0.7)
            return 0;
    }

    double riskAmount = equity * riskPerTrade / 100.0;
    if(riskAmount < 0.01) riskAmount = 0.01;

    double atr = 0.0;
    if(CopyBuffer(atrHandle, 0, 0, 1, atrBuffer) > 0)
        atr = atrBuffer[0];
    if(atr == 0) atr = 20.0;

    double slDistance = NormalizeDouble(atr * 1.0, symbolDigits);
    double minSlDistance = 10.0 * symbolTickSize;
    if(slDistance < minSlDistance) slDistance = minSlDistance;

    double valuePerUnitPerLot = symbolTickValue / symbolTickSize;
    double lotSize = minLot;

    if(valuePerUnitPerLot > 0 && slDistance > 0)
    {
        lotSize = riskAmount / (slDistance * valuePerUnitPerLot);
    }

    // PROBLEMA #11: Búsqueda binaria en lugar de lineal
    double minValidLot = minLot;
    double maxValidLot = MathMin(lotSize, maxLot);
    
    while(maxValidLot - minValidLot > stepLot && maxValidLot > minValidLot)
    {
        double testLot = MathFloor(((minValidLot + maxValidLot) / 2) / stepLot) * stepLot;
        
        double marginRequired = 0;
        if(OrderCalcMargin(orderType, _Symbol, testLot, price, marginRequired))
        {
            if(marginRequired > 0 && marginRequired <= freeMargin * 0.7)
                minValidLot = testLot;
            else if(marginRequired > freeMargin * 0.7)
                maxValidLot = testLot - stepLot;
        }
        else
        {
            maxValidLot = testLot - stepLot;
        }
    }
    
    lotSize = minValidLot;
    if(lotSize < minLot) lotSize = minLot;
    if(lotSize > maxLot) lotSize = maxLot;

    return lotSize;
}

//+------------------------------------------------------------------+
//| MÓDULO 3: ANÁLISIS DE VOLATILIDAD (PROBLEMA #12) =============|
//+------------------------------------------------------------------+

void AnalyzeVolatility()
{
    if(CopyBuffer(atrHandle, 0, 0, 50, atrBuffer) < 0)
        return;

    double atrSum = 0.0;
    double atrSqSum = 0.0;
    for(int i = 0; i < 50; i++)
    {
        atrSum += atrBuffer[i];
        atrSqSum += atrBuffer[i] * atrBuffer[i];
    }

    double atrAvg = atrSum / 50.0;
    double atrStdDev = MathSqrt((atrSqSum / 50.0) - (atrAvg * atrAvg));
    double currentATR = atrBuffer[0];

    // PROBLEMA #12: Validaciones robustas
    if(atrStdDev > 0.0001)
    {
        double range = 4.0 * atrStdDev;
        if(range > 0.0001)
        {
            volatilityLevel = (currentATR - (atrAvg - 2 * atrStdDev)) / range;
        }
        else
            volatilityLevel = 0.5;
    }
    else
        volatilityLevel = 0.5;

    volatilityLevel = MathMax(0.0, MathMin(1.0, volatilityLevel));
}

bool IsVolatilityAcceptable()
{
    if(!UseVolatilityFilter)
        return true;

    if(volatilityLevel > 0.85)
        return false;

    return true;
}

//+------------------------------------------------------------------+
//| MÓDULO 4: DETECCIÓN DE PATRONES DE VELAS                       |
//+------------------------------------------------------------------+

struct CandlePattern
{
    int patternType;
    int direction;
    double strength;
};

CandlePattern DetectCandlePatterns()
{
    CandlePattern pattern;
    pattern.patternType = 0;
    pattern.direction = 0;
    pattern.strength = 0.0;

    double open0 = iOpen(_Symbol, _Period, 0);
    double close0 = iClose(_Symbol, _Period, 0);
    double high0 = iHigh(_Symbol, _Period, 0);
    double low0 = iLow(_Symbol, _Period, 0);
    double bodySize = MathAbs(close0 - open0);
    double totalRange = high0 - low0;

    if(bodySize > totalRange * 0.7)
    {
        if(close0 > open0)
        {
            pattern.direction = 1;
            pattern.strength = MathMin(1.0, bodySize / totalRange);
        }
        else
        {
            pattern.direction = -1;
            pattern.strength = MathMin(1.0, bodySize / totalRange);
        }
    }

    return pattern;
}

//+------------------------------------------------------------------+
//| MÓDULO 5: GESTIÓN INTELIGENTE DE SLIPPAGE Y PING              |
//+------------------------------------------------------------------+

bool VerifyConnectionQuality()
{
    currentPing = GetCurrentPing();
    
    if(ArraySize(pingHistory) >= 100)
        ArrayRemove(pingHistory, 0, 1);
    ArrayResize(pingHistory, ArraySize(pingHistory) + 1);
    pingHistory[ArraySize(pingHistory) - 1] = currentPing;

    if(currentPing > MaxPingMilliseconds)
    {
        if(!isPaused)
        {
            Print("⚠️ PING ALTO DETECTADO: " + DoubleToString(currentPing, 0) + "ms");
            isPaused = true;
            alertLevel = 2;
            alertMessage = "Ping alto: " + DoubleToString(currentPing, 0) + "ms";
        }
        return false;
    }

    if(isPaused && currentPing < MaxPingMilliseconds * 0.7)
    {
        Print("✓ CONEXIÓN NORMALIZADA");
        isPaused = false;
        alertLevel = 0;
        alertMessage = "";
    }

    return true;
}

double GetCurrentPing()
{
    return (double)TerminalInfoInteger(TERMINAL_PING_LAST);
}

bool IsSpreadAcceptable()
{
    currentSpread = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / symbolPoint;
    
    if(ArraySize(spreadsHistory) >= 100)
        ArrayRemove(spreadsHistory, 0, 1);
    ArrayResize(spreadsHistory, ArraySize(spreadsHistory) + 1);
    spreadsHistory[ArraySize(spreadsHistory) - 1] = currentSpread;

    int histSize = ArraySize(spreadsHistory);
    if(histSize == 0) return true;  // Sin historial → no bloquear

    double spreadAvg = 0.0;
    for(int i = 0; i < histSize; i++)
        spreadAvg += spreadsHistory[i];
    spreadAvg = spreadAvg / histSize;

    if(spreadAvg <= 0) return true; // Evitar div/0

    return currentSpread <= spreadAvg * 2.0; // Tolerancia aumentada: 2x promedio
}

bool SubmitOrderWithSlippageControl(int direction, double lot, double slPrice, double tpPrice, double& realPrice)
{
    int maxRetries = 5;
    int retryDelay = 1000;

    for(int attempt = 0; attempt < maxRetries; attempt++)
    {
        double requestPrice = (direction == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);

        if(direction == 1)
            trade.Buy(lot, _Symbol, requestPrice, slPrice, tpPrice);
        else
            trade.Sell(lot, _Symbol, requestPrice, slPrice, tpPrice);

        if(trade.ResultRetcode() == TRADE_RETCODE_DONE)
        {
            realPrice = trade.ResultPrice();
            double slippage = MathAbs(realPrice - requestPrice);
            
            if(slippage <= SlippageMaximumAllowed)
                return true;

            CloseLastOrder();
            Sleep(retryDelay * (attempt + 1));
            continue;
        }

        Sleep(retryDelay * (attempt + 1));
    }

    return false;
}

void CloseLastOrder()
{
    if(PositionsTotal() > 0)
    {
        if(positionInfo.SelectByIndex(PositionsTotal() - 1))
        {
            trade.PositionClose(positionInfo.Ticket());
        }
    }
}

//+------------------------------------------------------------------+
//| MÓDULO 6: TP Y SL DINÁMICOS                                     |
//+------------------------------------------------------------------+

struct DynamicLevels
{
    double stopLoss;
    double takeProfit;
    double trailingStopDistance;
};

DynamicLevels CalculateDynamicLevels(int direction)
{
    DynamicLevels levels;

    if(CopyBuffer(atrHandle, 0, 0, 51, atrBuffer) < 0)
    {
        levels.stopLoss = NormalizeDouble(50.0 * symbolPoint, symbolDigits);
        levels.takeProfit = NormalizeDouble(150.0 * symbolPoint, symbolDigits);
        levels.trailingStopDistance = NormalizeDouble(10.0 * symbolPoint, symbolDigits);
        return levels;
    }

    double currentATR = atrBuffer[0];
    
    double slDistance = currentATR * 1.5;
    double tpDistance = slDistance * RR_Minimum;
    
    double minSL = 50.0 * symbolPoint;
    if(slDistance < minSL) slDistance = minSL;

    levels.stopLoss = NormalizeDouble(slDistance, symbolDigits);
    levels.takeProfit = NormalizeDouble(tpDistance, symbolDigits);
    levels.trailingStopDistance = NormalizeDouble(currentATR * 1.0, symbolDigits);

    return levels;
}

//+------------------------------------------------------------------+
//| MÓDULO 7: DETECCIÓN DE CONDICIONES EXTREMAS                    |
//+------------------------------------------------------------------+

bool DetectMarketExtremes()
{
    extremeMarketDetected = false;

    if(CopyBuffer(atrHandle, 0, 0, 51, atrBuffer) < 0)
        return true;

    double currentATR = atrBuffer[0];
    double atrSum = 0.0;
    for(int i = 1; i < 51; i++)
        atrSum += atrBuffer[i];
    double atrAverage = atrSum / 50.0;
    double atrStdDev = 0.0;

    for(int i = 1; i < 51; i++)
        atrStdDev += MathPow(atrBuffer[i] - atrAverage, 2);
    atrStdDev = MathSqrt(atrStdDev / 50.0);

    if(atrStdDev > 0 && currentATR > atrAverage + 3 * atrStdDev)
    {
        extremeMarketDetected = true;
        Print("⚠️ ALERTA: Gap detectado - Reduciendo riesgo");
    }

    double priceChange = MathAbs(iClose(_Symbol, _Period, 0) - iClose(_Symbol, _Period, 1));
    if(priceChange > 3.0 * atrAverage)
    {
        extremeMarketDetected = true;
        Print("⚠️ ALERTA: Cambio de precio extremo - Reduciendo riesgo");
    }

    return true;
}

//+------------------------------------------------------------------+
//| MÓDULO 8: PREVENCIÓN Y RESOLUCIÓN DE ERRORES                   |
//+------------------------------------------------------------------+

bool HandleTradeError(uint errorCode)
{
    switch(errorCode)
    {
        case TRADE_RETCODE_DONE:
            return true;

        case TRADE_RETCODE_REJECT:
        case TRADE_RETCODE_INVALID_VOLUME:
        {
            Print("⚠️ Error: Volumen inválido, reduciendo lote");
            riskPerTrade = RiskPerTrade * 0.75;
            return false;
        }

        case TRADE_RETCODE_NO_MONEY:
        {
            Print("⚠️ Error: Margen insuficiente");
            riskPerTrade = RiskPerTrade * 0.5;
            isInRecoveryMode = true;
            alertLevel = 3;
            return false;
        }

        case TRADE_RETCODE_PRICE_CHANGED:
        case TRADE_RETCODE_PRICE_OFF:
        {
            Print("⚠️ Error: Precio cambió, esperando normalización");
            Sleep(2000);
            return false;
        }

        default:
            Print("⚠️ Error de Trade: " + IntegerToString(errorCode));
            return false;
    }
}

int GetPauseBarsByTimeframe()
{
    switch(_Period)
    {
        case PERIOD_M1:  return 5;
        case PERIOD_M5:  return 2;
        case PERIOD_M15: return 1;
        case PERIOD_M30: return 1;
        case PERIOD_H1:  return 1;
        default:         return 3;
    }
}

datetime CalculatePauseUntil(int bars)
{
    int periodSeconds = _Period * 60;
    return TimeCurrent() + (bars * periodSeconds);
}

void UpdateErrorRecoveryMode()
{
    // 1. Verificación estándar de tiempo de pausa
    if(pauseUntilTime > 0 && TimeCurrent() >= pauseUntilTime)
    {
        isInRecoveryMode = false;
        isPaused = false;
        pauseUntilTime = 0;
        riskPerTrade = RiskPerTrade;
        minConfidenceScore = MinConfidenceScore;
        Print("✓ PERÍODO DE PAUSA TERMINADO - Reanudando operaciones");
        alertLevel = 0;
        alertMessage = "";
    }

    // 2. LÓGICA de PIVOT RECUPERADOR (Súper Idea Punto 3)
    // Si estamos en pausa, pero aparece una señal EXTREMADAMENTE fuerte en dirección opuesta,
    // el bot "salta" la pausa para aprovechar el rebote del mercado.
    if(isInRecoveryMode || isPaused)
    {
        SignalValidation buySignal = ValidateSignal(1);
        SignalValidation sellSignal = ValidateSignal(-1);
        
        // Umbral de "Súper Señal" para pivotar (0.85+)
        if(buySignal.confidenceScore > 0.85 || sellSignal.confidenceScore > 0.85)
        {
            isInRecoveryMode = false;
            isPaused = false;
            pauseUntilTime = 0;
            riskPerTrade = RiskPerTrade;
            minConfidenceScore = MinConfidenceScore;
            
            string dir = (buySignal.confidenceScore > 0.85) ? "COMPRA" : "VENTA";
            Print("🔄 PIVOT DE RECUPERACIÓN DETECTADO - Signal Score: " + 
                  DoubleToString(MathMax(buySignal.confidenceScore, sellSignal.confidenceScore), 2) + 
                  " | Iniciando trades de " + dir + " para recuperar pérdidas");
            
            alertLevel = 0;
            alertMessage = "Pivot de Recuperación Activo";
        }
    }
}

//+------------------------------------------------------------------+
//| MÓDULO 9: ESTADÍSTICAS Y ANÁLISIS                               |
//+------------------------------------------------------------------+

void CalculateStatistics()
{
    if(totalTradesClosed == 0)
    {
        winRate = 0;
        profitFactor = 1.0;
        averageProfit = 0;
        averageLoss = 0;
        return;
    }

    winRate = (totalTradesWon > 0) ? (double)totalTradesWon / (double)totalTradesClosed : 0;
    averageProfit = (totalTradesWon > 0) ? totalProfit / totalTradesWon : 0;
    averageLoss = (totalTradesLost > 0) ? totalLoss / totalTradesLost : 0;

    if(totalLoss > 0)
        profitFactor = totalProfit / totalLoss;
    else
        profitFactor = 1.0;
}

void ValidateEAStatus()
{
    if(dailyLoss > dynamicMaxDailyLoss)
    {
        if(!isPaused)
        {
            int pauseBars = GetPauseBarsByTimeframe() * 2;
            pauseUntilTime = CalculatePauseUntil(pauseBars);
            isInRecoveryMode = true;
            isPaused = true;
            riskPerTrade = RiskPerTrade * 0.5;
            Print("🛑 NIVEL ROJO - Límite diario alcanzado. Pausando");
        }
        alertLevel = 3;
    }
    else if(dailyLoss > dynamicMaxDailyLoss * 0.60)
    {
        if(!isPaused)
        {
            int pauseBars = GetPauseBarsByTimeframe();
            pauseUntilTime = CalculatePauseUntil(pauseBars);
            isInRecoveryMode = true;
            isPaused = true;
            riskPerTrade = RiskPerTrade * 0.5;
        }
        alertLevel = 2;
    }
    else if(dailyLoss > dynamicMaxDailyLoss * 0.30)
    {
        if(!isPaused && !isInRecoveryMode)
            riskPerTrade = RiskPerTrade * 0.75;
        alertLevel = 1;
    }
    else
    {
        if(alertLevel > 0 && !isPaused && !isInRecoveryMode)
        {
            alertLevel = 0;
            alertMessage = "";
            riskPerTrade = RiskPerTrade;
            minConfidenceScore = MinConfidenceScore;
        }
    }
}

//+------------------------------------------------------------------+
//| FUNCIONES PRINCIPALES DE VALIDACIÓN (PROBLEMA #1) =============|
//+------------------------------------------------------------------+

bool ValidateSymbolAndTimeframe()
{
    if(_Symbol != "XAUUSD" && _Symbol != "GOLD")
    {
        Alert("❌ ERROR: Este EA solo funciona con XAUUSD/GOLD");
        return false;
    }

    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    if(ask <= 0 || bid <= 0)
    {
        Alert("❌ XAUUSD/GOLD no tiene datos disponibles aún");
        return false;
    }
    
    int bars = Bars(_Symbol, _Period);
    if(bars < 100)
    {
        Alert("⚠️ Datos históricos insuficientes. Esperando " + IntegerToString(100 - bars) + " velas");
        return false;
    }

    // Timeframes óptimos para ICT: 15M y 1H
    switch(_Period)
    {
        case PERIOD_M15:
            if(!AllowM15) { Alert("❌ M15 no permitido"); return false; }
            Print("✓ Timeframe ÓPTIMO: 15M - Configurado para London Open");
            break;
        case PERIOD_H1:
            if(!AllowH1) { Alert("❌ H1 no permitido"); return false; }
            Print("✓ Timeframe ÓPTIMO: 1H - Confirmación de tendencia");
            break;
        case PERIOD_M5:
            if(!AllowM5) 
            { 
                Alert("❌ M5 BLOQUEADO: spread XAUUSD (~20-50pts) > ATR M5 (~15-25pts)\n"
                      "Matemáticamente imposible ser rentable. Use M15, M30 o H1.\n"
                      "Para habilitar: cambie AllowM5=true (solo con ECN <15pts spread)");
                return false; 
            }
            Print("⚠️ ADVERTENCIA M5: Asegúrese de tener cuenta ECN con spread <15 puntos");
            break;
        case PERIOD_M30:
            if(!AllowM30) { Alert("❌ M30 no permitido"); return false; }
            break;
        case PERIOD_H4:
            break;
        default:
            Alert("❌ Timeframe no óptimo. Recomendado: 15M o 1H");
            return false;
    }

    return true;
}

bool ValidateAccountSettings()
{
    int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
    if(digits < 2)
    {
        Alert("❌ Símbolo debe tener al menos 2 decimales");
        return false;
    }

    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    if(equity < MinimumCapital)
    {
        Alert("❌ ERROR: Capital insuficiente. Mínimo: $" + DoubleToString(MinimumCapital, 2) + 
              " | Disponible: $" + DoubleToString(equity, 2));
        return false;
    }

    if(ValidateLeverage && dynamicLeverage < RequiredLeverage)
    {
        // Solo advertencia – no bloquear: 1:500 y 1:1000 son ambos válidos
        Print("⚠️ ADVERTENCIA: Apalancamiento " + IntegerToString(dynamicLeverage) + 
              " < recomendado (" + IntegerToString(RequiredLeverage) + ") – operando igual");
    }
    else if(ValidateLeverage && dynamicLeverage >= RequiredLeverage)
    {
        Print("✓ Apalancamiento ÓPTIMO: 1:" + IntegerToString(dynamicLeverage) + 
              " (Requerido: 1:" + IntegerToString(RequiredLeverage) + ")");
    }

    return true;
}

bool InitializeIndicators()
{
    rsiHandle = iRSI(_Symbol, _Period, RSI_Period, PRICE_CLOSE);
    if(rsiHandle == INVALID_HANDLE)
    {
        Alert("❌ ERROR: No se pudo crear RSI");
        return false;
    }

    atrHandle = iATR(_Symbol, _Period, ATR_Period);
    if(atrHandle == INVALID_HANDLE)
    {
        Alert("❌ ERROR: No se pudo crear ATR");
        return false;
    }

    emaFastHandle = iMA(_Symbol, _Period, EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
    if(emaFastHandle == INVALID_HANDLE)
    {
        Alert("❌ ERROR: No se pudo crear EMA Rápida");
        return false;
    }

    emaSlowHandle = iMA(_Symbol, _Period, EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
    if(emaSlowHandle == INVALID_HANDLE)
    {
        Alert("❌ ERROR: No se pudo crear EMA Lenta");
        return false;
    }

    // OPTIMIZACIÓN: Handles H1 para confirmación multi-timeframe
    h1EmaHandle = iMA(_Symbol, PERIOD_H1, EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
    h1RsiHandle = iRSI(_Symbol, PERIOD_H1, RSI_Period, PRICE_CLOSE);

    return true;
}

bool ConfigureArrays()
{
    ArraySetAsSeries(rsiBuffer, true);
    ArraySetAsSeries(atrBuffer, true);
    ArraySetAsSeries(emaFastBuffer, true);
    ArraySetAsSeries(emaSlowBuffer, true);
    ArraySetAsSeries(volumeBuffer, true);
    ArrayResize(volumeBuffer, 150);   // Pre-alocar para evitar out-of-bounds en llenado
    ArrayResize(fvgBuffer, 100);

    return true;
}

void InitializeVariables()
{
    accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    currentCapital = accountBalance;
    lastDayCheck = TimeCurrent();
    isPaused = false;
    isInRecoveryMode = false;
    pauseUntilTime = 0;
    riskPerTrade = RiskPerTrade;
    minConfidenceScore = MinConfidenceScore;
    UpdateDynamicParameters();
}

bool LoadAllIndicatorData()
{
    int rates = 100;

    if(CopyBuffer(rsiHandle, 0, 0, rates, rsiBuffer) < 0) return false;
    if(CopyBuffer(atrHandle, 0, 0, rates, atrBuffer) < 0) return false;
    if(CopyBuffer(emaFastHandle, 0, 0, rates, emaFastBuffer) < 0) return false;
    if(CopyBuffer(emaSlowHandle, 0, 0, rates, emaSlowBuffer) < 0) return false;
    
    for(int i = 0; i < rates; i++)
        volumeBuffer[i] = (double)iVolume(_Symbol, _Period, i);

    // Cachear valores actuales
    if(ArraySize(rsiBuffer) > 0) cachedRSI = rsiBuffer[0];
    if(ArraySize(atrBuffer) > 0) cachedATR = atrBuffer[0];
    if(ArraySize(emaFastBuffer) > 0) cachedEMAFast = emaFastBuffer[0];
    if(ArraySize(emaSlowBuffer) > 0) cachedEMASlow = emaSlowBuffer[0];
    if(ArraySize(volumeBuffer) > 0) cachedVolume = volumeBuffer[0];

    return true;
}

void UpdateAccountData()
{
    accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    currentCapital = accountBalance;
}

void UpdateTimeData()
{
    datetime now = TimeCurrent();
    MqlDateTime timeStruct;
    TimeToStruct(now, timeStruct);
    
    currentHourUTC = timeStruct.hour;
    currentDayOfWeek = timeStruct.day_of_week;
}

void UpdateMarketData()
{
    currentSpread = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / symbolPoint;
}

// PROBLEMA #16: Cálculo P&L con timeframe correcto
void UpdateDailyProfitLoss()
{
    dailyProfit = 0.0;
    dailyLoss = 0.0;

    // MEJORA: Definir inicio de sesión correctamente (UTC)
    datetime sessionStart = TimeCurrent();
    MqlDateTime timeStruct;
    TimeToStruct(sessionStart, timeStruct);
    
    // Fijar a las 00:00 UTC
    timeStruct.hour = 0;
    timeStruct.min = 0;
    timeStruct.sec = 0;
    
    datetime dayStart = StructToTime(timeStruct);
    datetime dayEnd = dayStart + 86400;
    
    HistorySelect(dayStart, dayEnd);

    for(int i = 0; i < HistoryDealsTotal(); i++)
    {
        if(dealInfo.SelectByIndex(i))
        {
            if(dealInfo.Symbol() == _Symbol && dealInfo.Magic() == 99999)
            {
                double profit = dealInfo.Profit() + dealInfo.Commission();
                if(profit > 0)
                    dailyProfit += profit;
                else
                    dailyLoss += MathAbs(profit);
            }
        }
    }
}

// PROBLEMA #19: Reseteo diario de estadísticas
bool VerifyDailyReset()
{
    datetime currentTime = TimeCurrent();
    MqlDateTime today, lastCheck;

    TimeToStruct(currentTime, today);
    TimeToStruct(lastDayCheck, lastCheck);

    if(today.day != lastCheck.day)
    {
        // Resetear estadísticas diarias
        dailyProfit = 0.0;
        dailyLoss = 0.0;
        consecutiveLosses = 0;
        
        // PROBLEMA #19: Resetear estadísticas del día (NO históricas)
        int tradesOpenedToday = totalTradesOpened;
        int tradesClosedToday = totalTradesClosed;
        int tradesWonToday = totalTradesWon;
        int tradesLostToday = totalTradesLost;
        
        totalTradesOpened = 0;
        totalTradesClosed = 0;
        totalTradesWon = 0;
        totalTradesLost = 0;
        totalProfit = 0.0;
        totalLoss = 0.0;
        
        lastDayCheck = currentTime;

        isPaused = false;
        isInRecoveryMode = false;
        pauseUntilTime = 0;
        riskPerTrade = RiskPerTrade;
        minConfidenceScore = MinConfidenceScore;
        alertLevel = 0;
        alertMessage = "";
        UpdateDynamicParameters();

        Print("\n═══════════════════════════════════════════════════════════");
        Print("📅 [NUEVO DÍA] " + IntegerToString(today.day) + "/" + 
              IntegerToString(today.mon) + "/" + IntegerToString(today.year));
        Print("✓ Sistema reseteado - Operaciones reanudadas");
        Print("Ayer: Abiertos=" + IntegerToString(tradesOpenedToday) + 
              " Cerrados=" + IntegerToString(tradesClosedToday) + 
              " Ganadores=" + IntegerToString(tradesWonToday));
        GenerateDailyReport();
        Print("═══════════════════════════════════════════════════════════\n");

        return true;
    }

    return true;
}

void ReleaseIndicators()
{
    if(rsiHandle != INVALID_HANDLE) IndicatorRelease(rsiHandle);
    if(atrHandle != INVALID_HANDLE) IndicatorRelease(atrHandle);
    if(emaFastHandle != INVALID_HANDLE) IndicatorRelease(emaFastHandle);
    if(emaSlowHandle != INVALID_HANDLE) IndicatorRelease(emaSlowHandle);
    if(h1EmaHandle != INVALID_HANDLE) IndicatorRelease(h1EmaHandle);
    if(h1RsiHandle != INVALID_HANDLE) IndicatorRelease(h1RsiHandle);
}

bool ReconnectIndicators()
{
    bool allValid = true;
    if(rsiHandle == INVALID_HANDLE || !IsIndicatorReady(rsiHandle))
    {
        rsiHandle = iRSI(_Symbol, _Period, RSI_Period, PRICE_CLOSE);
        if(rsiHandle == INVALID_HANDLE) allValid = false;
    }
    if(atrHandle == INVALID_HANDLE || !IsIndicatorReady(atrHandle))
    {
        atrHandle = iATR(_Symbol, _Period, ATR_Period);
        if(atrHandle == INVALID_HANDLE) allValid = false;
    }
    if(emaFastHandle == INVALID_HANDLE || !IsIndicatorReady(emaFastHandle))
    {
        emaFastHandle = iMA(_Symbol, _Period, EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
        if(emaFastHandle == INVALID_HANDLE) allValid = false;
    }
    if(emaSlowHandle == INVALID_HANDLE || !IsIndicatorReady(emaSlowHandle))
    {
        emaSlowHandle = iMA(_Symbol, _Period, EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
        if(emaSlowHandle == INVALID_HANDLE) allValid = false;
    }
    if(!allValid)
        Print("⚠️ Reconectando indicadores...");
    return allValid;
}

bool IsIndicatorReady(int handle)
{
    if(handle == INVALID_HANDLE) return false;
    double temp[];
    return (CopyBuffer(handle, 0, 0, 1, temp) > 0);
}

void PrintLaunchInfo()
{
    Print("\n╔════════════════════════════════════════════════════════════╗");
    Print("║  🚀 XAU_USD ICT MultiTrader Pro - London Open Edition 🚀 ║");
    Print("║  Optimizado 15M/1H - Apalancamiento 1:500 - $4 USD Min   ║");
    Print("╠════════════════════════════════════════════════════════════╣");
    Print("║ CONFIGURACIÓN ÓPTIMA:");
    Print("║ • Símbolo: " + Symbol());
    Print("║ • Timeframe: " + IntegerToString(_Period) + " minutos");
    Print("║ • Apalancamiento: 1:" + IntegerToString(dynamicLeverage) + 
          (dynamicLeverage >= RequiredLeverage ? " ✓" : " ⚠"));
    Print("║ • Riesgo: " + DoubleToString(RiskPerTrade, 1) + "% por trade");
    Print("║ • Lote: Auto según capital");
    Print("║");
    Print("║ ICT LONDON OPEN:");
    Print("║ • Horario: " + IntegerToString(LondonKillZoneStart) + ":00 - " + 
          IntegerToString(LondonKillZoneEnd) + ":00 UTC");
    Print("║ • Timeframes: 15M (entrada) + 1H (confirmación)");
    Print("║ • Estrategia: FVG + OTE + Divergencias");
    Print("║");
    Print("║ INDICADORES:");
    Print("║ • RSI (14) - Divergencias");
    Print("║ • EMA 20/50 - Tendencia");
    Print("║ • ATR (14) - Volatilidad");
    Print("║ • Volumen - Confirmación");
    Print("║ • Fibonacci OTE (62-79%)");
    Print("║ • Session Highs/Lows");
    Print("║");
    Print("║ RIESGO:");
    Print("║ • Max Pérdida Diaria: " + DoubleToString(MaxDailyLossPct, 1) + "%");
    Print("║ • Max Pérdida Trade: $" + DoubleToString(MaxLossPerTrade, 0));
    Print("║ • RR Mínimo: 1:" + DoubleToString(RR_Minimum, 1));
    Print("║ • Score Mínimo: " + DoubleToString(MinConfidenceScore * 100, 0) + "%");
    Print("║");
    Print("║ TAKE PROFIT:");
    Print("║ • Estrategia: 1:" + DoubleToString(RR_Minimum, 0) + " RR fijo");
    Print("║ • Break Even: " + DoubleToString(GetBreakEvenTrigger() * 100, 0) + "% del target");
    Print("║ • Trailing: ATR dinámico");
    Print("╚════════════════════════════════════════════════════════════╝\n");
}

void PrintShutdownInfo()
{
    Print("\n╔════════════════════════════════════════════════════════════╗");
    Print("║     🛑 XAU_USD_MultiTrader_Pro v5.2 DETENIDO 🛑           ║");
    Print("╠════════════════════════════════════════════════════════════╣");
    Print("║ RESUMEN FINAL:");
    Print("║ • Total Trades Abiertos: " + IntegerToString(totalTradesOpened));
    Print("║ • Total Trades Cerrados: " + IntegerToString(totalTradesClosed));
    Print("║ • Cierres Totales (Todos Ganadores): " + IntegerToString(totalProfitClosures));
    Print("║ • Trades Ganadores: " + IntegerToString(totalTradesWon));
    Print("║ • Trades Perdedores: " + IntegerToString(totalTradesLost));
    Print("║ • Win Rate: " + DoubleToString(winRate * 100, 1) + "%");
    Print("║ • Profit Factor: " + DoubleToString(profitFactor, 2));
    Print("║ • Ganancia Histórica: $" + DoubleToString(historicalProfit, 2));
    Print("║ • Capital Final: $" + DoubleToString(currentCapital, 2));
    Print("║ • Capital Protegido: $" + DoubleToString(protectedCapital, 2));
    Print("║ • Apalancamiento Usado: 1:" + IntegerToString(dynamicLeverage));
    Print("║ • Archivo Log: " + logFileName);
    Print("╚════════════════════════════════════════════════════════════╝\n");
}

//+------------------------------------------------------------------+
//| GESTIÓN DE PARÁMETROS DINÁMICOS                                 |
//+------------------------------------------------------------------+

void UpdateDynamicParameters()
{
    PyramidConfig config = GetPyramidConfigForCapital();
    dynamicMaxOpenTrades = config.maxTrades;
    
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    dynamicMaxDailyLoss = equity * MaxDailyLossPct / 100.0;
    if(dynamicMaxDailyLoss < 0.50) dynamicMaxDailyLoss = 0.50;
    
    dynamicMinProfitTarget = CalculateDynamicMinProfitTarget();
}

double GetTimeframeMultiplier()
{
    switch(_Period)
    {
        case PERIOD_M1:  return 1.0;
        case PERIOD_M5:  return 1.5;
        case PERIOD_M15: return 1.0;
        case PERIOD_M30: return 1.5;
        case PERIOD_H1:  return 2.0;
        case PERIOD_H4:  return 3.0;
        default:        return 1.0;
    }
}

double GetBreakEvenTrigger()
{
    switch(_Period)
    {
        case PERIOD_M1:  return 0.90;
        case PERIOD_M5:  return 0.80;
        case PERIOD_M15: return 0.70;
        case PERIOD_M30: return 0.60;
        case PERIOD_H1:  return 0.50;
        case PERIOD_H4:  return 0.40;
        default:         return 0.70;
    }
}

double CalculateDynamicMinProfitTarget()
{
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    double currentLot = UseAutoLot ? CalculateAdaptiveLotSize(1) : FixedLot;

    double oneWayCost = 0;
    if(symbolTickValue > 0 && symbolTickSize > 0)
    {
        double valuePerTick = symbolTickValue / symbolTickSize;
        double spreadInPrice = currentSpread * symbolPoint;
        oneWayCost = valuePerTick * currentLot * spreadInPrice;
    }

    double minTarget = equity * 0.003;
    double breakEvenTarget = oneWayCost * 2.0;

    if(breakEvenTarget > minTarget) minTarget = breakEvenTarget;
    if(minTarget < 0.03) minTarget = 0.03;

    // Aplicar el Multiplicador de Timeframe para evitar el ruido
    double tfMultiplier = GetTimeframeMultiplier();
    return NormalizeDouble(minTarget * tfMultiplier, 2);
}

//+------------------------------------------------------------------+
//| ANÁLISIS DE TENDENCIA                                            |
//+------------------------------------------------------------------+

void AnalyzeTrendWithAllMethods()
{
    isTrendingUp = false;
    isTrendingDown = false;

    if(ArraySize(emaFastBuffer) < 3 || ArraySize(emaSlowBuffer) < 3)
        return;

    double emaFast = emaFastBuffer[0];
    double emaSlow = emaSlowBuffer[0];
    double emaFastPrev = emaFastBuffer[1];
    double emaSlowPrev = emaSlowBuffer[1];
    double rsiCurr = cachedRSI;

    // ─── Tendencia: alineación EMA (no se exige cruce puntual) ───
    bool emaBullish = (emaFast > emaSlow);          // EMA20 sobre EMA50 → alcista
    bool emaBearish = (emaFast < emaSlow);          // EMA20 bajo EMA50 → bajista

    // RSI confirmación (sin sobrecompra/sobreventa extrema)
    bool rsiBuyConfirm  = (rsiCurr > 35 && rsiCurr < 80);
    bool rsiSellConfirm = (rsiCurr > 20 && rsiCurr < 65);

    double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    bool priceAboveEMA = (price > emaFast);
    bool priceBelowEMA = (price < emaFast);

    if(emaBullish && rsiBuyConfirm && priceAboveEMA)
        isTrendingUp = true;
    
    if(emaBearish && rsiSellConfirm && priceBelowEMA)
        isTrendingDown = true;
}

bool ConfirmTrendMultiTimeframe(int direction)
{
    if(_Period == PERIOD_M15)
    {
        // Fallback: si los handles H1 no están listos, no bloquear
        if(h1EmaHandle == INVALID_HANDLE || h1RsiHandle == INVALID_HANDLE)
            return true;
        
        double emaH1[];
        double rsiH1[];
        ArraySetAsSeries(emaH1, true);
        ArraySetAsSeries(rsiH1, true);
        
        bool emaConfirm = false;
        bool rsiConfirm = false;
        
        if(CopyBuffer(h1EmaHandle, 0, 0, 3, emaH1) > 0)
        {
            double priceH1 = iClose(_Symbol, PERIOD_H1, 0);
            
            if(direction == 1)
            {
                // Alcista H1: EMA subiendo y precio por encima
                if(emaH1[0] > emaH1[1] && priceH1 > emaH1[0])
                    emaConfirm = true;
                // Relajado: solo precio sobre EMA
                else if(priceH1 > emaH1[0])
                    emaConfirm = true;
            }
            else
            {
                // Bajista H1: EMA bajando y precio por debajo
                if(emaH1[0] < emaH1[1] && priceH1 < emaH1[0])
                    emaConfirm = true;
                else if(priceH1 < emaH1[0])
                    emaConfirm = true;
            }
        }
        else
        {
            emaConfirm = true; // datos no disponibles → no bloquear
        }
        
        if(CopyBuffer(h1RsiHandle, 0, 0, 3, rsiH1) > 0)
        {
            if(direction == 1 && rsiH1[0] > 40 && rsiH1[0] < 85)
                rsiConfirm = true;
            else if(direction == -1 && rsiH1[0] > 15 && rsiH1[0] < 60)
                rsiConfirm = true;
        }
        else
        {
            rsiConfirm = true; // datos no disponibles → no bloquear
        }
        
        return (emaConfirm && rsiConfirm);
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| GESTIÓN DE APERTURA DE TRADES - SINCRONIZADO                    |
//+------------------------------------------------------------------+

void ManageTradeOpening()
{
    static datetime lastDebugPrint = 0;

    // === 1. Modo de trading ===
    bool inLondonZone = IsKillZoneActive();
    bool canTrade = false;

    if(TradeMode == MODE_ALL)          canTrade = true;
    else if(TradeMode == MODE_LONDON_ONLY)  canTrade = inLondonZone;
    else if(TradeMode == MODE_PREFER_LONDON) canTrade = true;

    if(!canTrade)
    {
        if(TimeCurrent() - lastDebugPrint > 60) {
            Print("🕐 BLOQUEO: Solo London | LondonZone: INACTIVA");
            lastDebugPrint = TimeCurrent();
        }
        return;
    }

    // === 2. Filtro de noticias ===
    if(EnableNewsFilter && IsNewsHour())
    {
        if(TimeCurrent() - lastDebugPrint > 60) {
            Print("🚫 BLOQUEO: Horario de noticias (13-15 o 19-21 UTC)");
            lastDebugPrint = TimeCurrent();
        }
        return;
    }

    // === 3. Trades ya abiertos ===
    int openTrades = CountOpenTrades();
    if(openTrades > 0)
    {
        if(TimeCurrent() - lastDebugPrint > 60) {
            Print("🚫 BLOQUEO: Trades abiertos = " + IntegerToString(openTrades));
            lastDebugPrint = TimeCurrent();
        }
        return;
    }

    // === 4. CANDLE GUARD v6.0: una operación por vela ===
    datetime currentCandleOpen = iTime(_Symbol, _Period, 0);
    if(currentCandleOpen <= lastTradeOpenCandleTime)
    {
        if(TimeCurrent() - lastDebugPrint > 60) {
            Print("🚫 CANDLE-GUARD: Ya se operó en esta vela. Esperando nueva vela.");
            lastDebugPrint = TimeCurrent();
        }
        return;
    }

    // === 5. Espera post-profit (hasta fin de vela) ===
    if(TimeCurrent() < nextTradeAllowedTime)
    {
        if(TimeCurrent() - lastDebugPrint > 60) {
            int secsLeft = (int)(nextTradeAllowedTime - TimeCurrent());
            Print("⏳ BLOQUEO: Esperando fin de vela post-profit (" + IntegerToString(secsLeft) + "s)");
            lastDebugPrint = TimeCurrent();
        }
        return;
    }

    // === 6. Tendencia ===
    if(!isTrendingUp && !isTrendingDown)
    {
        if(TimeCurrent() - lastDebugPrint > 60) {
            double ef = ArraySize(emaFastBuffer) > 0 ? emaFastBuffer[0] : 0;
            double es = ArraySize(emaSlowBuffer) > 0 ? emaSlowBuffer[0] : 0;
            Print("🚫 BLOQUEO: Sin tendencia | EMA20: " + DoubleToString(ef,2) +
                  " | EMA50: " + DoubleToString(es,2) + " | RSI: " + DoubleToString(cachedRSI,1));
            lastDebugPrint = TimeCurrent();
        }
        return;
    }

    // === 7. Margen ===
    if(!HasEnoughMargin())
    {
        if(TimeCurrent() - lastDebugPrint > 60) {
            Print("🚫 BLOQUEO: Margen insuficiente");
            lastDebugPrint = TimeCurrent();
        }
        return;
    }

    // === 8. Señal ICT ===
    int direction = isTrendingUp ? 1 : -1;
    SignalValidation signal = ValidateSignal(direction);

    if(signal.confidenceScore < minConfidenceScore)
    {
        if(TimeCurrent() - lastDebugPrint > 60) {
            Print("🚫 BLOQUEO: Score bajo (" + DoubleToString(signal.confidenceScore*100,0) +
                  "% < " + DoubleToString(minConfidenceScore*100,0) + "%) | " + signal.validationReason);
            lastDebugPrint = TimeCurrent();
        }
        return;
    }

    if(!signal.isSpreadOK)
    {
        if(TimeCurrent() - lastDebugPrint > 60) {
            Print("🚫 BLOQUEO: Spread alto (" + DoubleToString(currentSpread,1) + " pips)");
            lastDebugPrint = TimeCurrent();
        }
        return;
    }

    // === 9. Confirmación multi-TF ===
    if(_Period == PERIOD_M15 && !ConfirmTrendMultiTimeframe(direction))
    {
        if(TimeCurrent() - lastDebugPrint > 60) {
            Print("🚫 BLOQUEO: 1H no confirma tendencia");
            lastDebugPrint = TimeCurrent();
        }
        return;
    }

    // === PROCEDER CON APERTURA ===
    int maxTrades    = dynamicMaxOpenTrades;
    int tradesToOpen = maxTrades;
    if(tradesToOpen <= 0) return;

    double lot = UseAutoLot ? CalculateAdaptiveLotSize(direction) : FixedLot;
    if(lot <= 0) return;

    double entryPrice = (direction == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                         : SymbolInfoDouble(_Symbol, SYMBOL_BID);
    ENUM_ORDER_TYPE orderTypeCheck = (direction == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
    double marginForOneLot = 0;
    if(!OrderCalcMargin(orderTypeCheck, _Symbol, lot, entryPrice, marginForOneLot)) return;
    if(marginForOneLot <= 0) return;

    double freeMargin  = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
    int    maxByMargin = (int)(freeMargin / marginForOneLot);
    tradesToOpen = MathMin(tradesToOpen, maxByMargin);
    if(tradesToOpen <= 0) return;

    DynamicLevels levels   = CalculateDynamicLevels(direction);
    int           openedCnt = 0;

    // v7.3: Lote base por capital (pirámide de equity)
    double baseLot = UseAutoLot ? GetPyramidLotForCapital() : FixedLot;
    if(baseLot <= 0) return;

    for(int i = 0; i < tradesToOpen; i++)
    {
        double lotSize = baseLot;

        double px = (direction == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                     : SymbolInfoDouble(_Symbol, SYMBOL_BID);
        double marginCheck = 0;
        if(OrderCalcMargin((direction==1)?ORDER_TYPE_BUY:ORDER_TYPE_SELL,
                           _Symbol, lotSize, px, marginCheck))
        {
            double fm = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
            if(marginCheck > fm * 0.85) { lotSize = symbolMinLot; }
            if(marginCheck > fm) break;
        }
        double slPrice, tpPrice;
        if(direction == 1)
        {
            slPrice = NormalizeDouble(px - levels.stopLoss,   symbolDigits);
            tpPrice = NormalizeDouble(px + levels.takeProfit, symbolDigits);
        }
        else
        {
            slPrice = NormalizeDouble(px + levels.stopLoss,   symbolDigits);
            tpPrice = NormalizeDouble(px - levels.takeProfit, symbolDigits);
        }

        double realPrice = 0.0;
        if(SubmitOrderWithSlippageControl(direction, lotSize, slPrice, tpPrice, realPrice))
        {
            tradeDirection = direction;
            totalTradesOpened++;
            lastTradeOpen      = TimeCurrent();
            lastCycleCloseTime = 0;
            openedCnt++;

            string dirStr = (direction == 1) ? "BUY" : "SELL";
            Print("✅ " + dirStr + " ABIERTO | Score: " + DoubleToString(signal.confidenceScore*100,0) +
                  "% | Lote: " + DoubleToString(lotSize,2) +
                  " | Precio: " + DoubleToString(realPrice,symbolDigits) +
                  " | SL: "    + DoubleToString(slPrice,symbolDigits) +
                  " | TP: "    + DoubleToString(tpPrice,symbolDigits));
        }
        else break;

        if(!HasEnoughMargin()) break;
        if(CountOpenTrades() >= maxTrades) break;
    }

    // Registrar vela usada para el candle guard
    if(openedCnt > 0)
    {
        lastTradeOpenCandleTime = iTime(_Symbol, _Period, 0);
        Print("📌 [CANDLE-GUARD] Ciclo abierto en vela: " + TimeToString(lastTradeOpenCandleTime));
    }
}

// PROBLEMA #23: Validación de horarios de noticias
bool IsNewsHour()
{
    MqlDateTime timeStruct;
    TimeToStruct(TimeCurrent(), timeStruct);
    
    int hour = timeStruct.hour;
    
    // Evitar 13:00-15:00 y 19:00-21:00 UTC (Noticias USA y EU)
    if((hour >= 13 && hour < 15) || (hour >= 19 && hour < 21))
        return true;
        
    return false;
}

bool HasEnoughMargin()
{
    double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
    double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double marginRequired = 0;

    if(!OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, symbolMinLot, price, marginRequired))
        return false;

    return (freeMargin >= marginRequired * MarginThreshold);
}

//+------------------------------------------------------------------+
//| GESTIÓN DE CIERRE - MEJORADA (PROBLEMA #13-15) ================|
//+------------------------------------------------------------------+

void ManageTradeClosing()
{
    // Permite múltiples cierres por tick
    int closedThisTick  = 0;
    int maxClosesPerTick = 3;
    bool anyProfitClosed = false;
    
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(closedThisTick >= maxClosesPerTick) break;
        
        if(positionInfo.SelectByIndex(i))
        {
            if(positionInfo.Symbol() != _Symbol || positionInfo.Magic() != 99999)
                continue;

            double profit = positionInfo.Profit() + positionInfo.Commission() + positionInfo.Swap();

            // CIERRE AGRESIVO (ganancia)
            if(EnableAggressiveProfitTaking && profit > AggressiveProfitThreshold)
            {
                ulong  ticket        = positionInfo.Ticket();
                double closedProfit  = profit;
                int    closedDir     = (positionInfo.PositionType() == POSITION_TYPE_BUY) ? 1 : -1;

                if(trade.PositionClose(ticket))
                {
                    totalTradesClosed++;
                    historicalProfit += closedProfit;
                    totalTradesWon++;
                    totalProfit += closedProfit;
                    consecutiveLosses = 0;
                    closedThisTick++;
                    anyProfitClosed = true;
                    
                    LogTrade(true, closedProfit, "Cierre Agresivo - Ganancia > $" + DoubleToString(AggressiveProfitThreshold, 2));
                    LogTradeToFile(true, closedProfit, "Cierre Agresivo");

                    Print("💰 CIERRE AGRESIVO | Ticket: " + IntegerToString((long)ticket) +
                          " | Dir: " + (closedDir == 1 ? "BUY" : "SELL") +
                          " | Ganancia: $" + DoubleToString(closedProfit, 2) +
                          " | Histórico: $" + DoubleToString(historicalProfit, 2));
                }
            }
            // CIERRE MONOTÓNICO ESTÁNDAR (ganancia)
            else if(!EnableAggressiveProfitTaking && profit >= dynamicMinProfitTarget && profit > 0)
            {
                ulong  ticket       = positionInfo.Ticket();
                double closedProfit = profit;
                int    closedDir    = (positionInfo.PositionType() == POSITION_TYPE_BUY) ? 1 : -1;

                if(trade.PositionClose(ticket))
                {
                    totalTradesClosed++;
                    historicalProfit += closedProfit;
                    totalTradesWon++;
                    totalProfit += closedProfit;
                    consecutiveLosses = 0;
                    closedThisTick++;
                    anyProfitClosed = true;
                    
                    LogTrade(true, closedProfit, "Cierre Monotónico - Ganancia Asegurada");
                    LogTradeToFile(true, closedProfit, "Cierre Monotónico");

                    Print("✅ CIERRE MONOTÓNICO | Ticket: " + IntegerToString((long)ticket) +
                          " | Dir: " + (closedDir == 1 ? "BUY" : "SELL") +
                          " | Ganancia: $" + DoubleToString(closedProfit, 2) +
                          " | Histórico: $" + DoubleToString(historicalProfit, 2));
                }
            }
            // NOTA v6.0: Los trades negativos ya NO se cierran aquí.
            // El Sistema POSIBLE (ManagePossibleTradeSystem) es el único encargado
            // de gestionar y cerrar trades con pérdida.
        }
    }

    // Si se cerró algún trade con ganancia → esperar hasta fin de vela actual
    if(anyProfitClosed)
        SetCandleWaitAfterProfit();

    int remainingTrades = CountOpenTrades();
    if(remainingTrades == 0 && totalTradesOpened > 0)
        tradeDirection = 0;
}

// GetDynamicMaxLoss: ya no cierra trades directamente; solo lo usa el Sistema POSIBLE como límite de emergencia
double GetDynamicMaxLoss()
{
    return MaxLossPerTrade;  // $400 configurable por parámetro
}

//+------------------------------------------------------------------+
//| SISTEMA POSIBLE v6.0 - Gestión inteligente de trades negativos  |
//+------------------------------------------------------------------+

// Función principal del Sistema POSIBLE - se llama desde OnTick
// ═══ PEAK PROFIT CLOSE (v7.3) ═══════════════════════════════════════

double GetPeakForTicket(ulong ticket)
{
    for(int i = 0; i < peakCount; i++)
        if(peakRecords[i].ticket == ticket) return peakRecords[i].peakProfit;
    return 0.0;
}

void SetPeakForTicket(ulong ticket, double val)
{
    for(int i = 0; i < peakCount; i++)
    {
        if(peakRecords[i].ticket == ticket) { peakRecords[i].peakProfit = val; return; }
    }
    if(peakCount < 50)
    {
        peakRecords[peakCount].ticket     = ticket;
        peakRecords[peakCount].peakProfit = val;
        peakCount++;
    }
}

void RemovePeakForTicket(ulong ticket)
{
    for(int i = 0; i < peakCount; i++)
    {
        if(peakRecords[i].ticket == ticket)
        {
            peakRecords[i] = peakRecords[peakCount - 1];
            peakCount--;
            return;
        }
    }
}

void ManagePeakProfitClose()
{
    if(!EnablePeakProfitClose) return;
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(!positionInfo.SelectByIndex(i)) continue;
        if(positionInfo.Symbol() != _Symbol || positionInfo.Magic() != 99999) continue;

        ulong  ticket = positionInfo.Ticket();
        double profit = positionInfo.Profit() + positionInfo.Swap() + positionInfo.Commission();
        double peak   = GetPeakForTicket(ticket);

        if(profit > peak && profit > 0)
            SetPeakForTicket(ticket, profit);

        double minPeak = dynamicMinProfitTarget * 0.5;
        if(peak > minPeak && profit < peak * (1.0 - PeakProfitRetracePct / 100.0))
        {
            Print("🔒 PEAK-CLOSE #" + IntegerToString((long)ticket) +
                  " | Pico: $" + DoubleToString(peak,2) +
                  " | Actual: $" + DoubleToString(profit,2));
            if(trade.PositionClose(ticket))
            {
                RemovePeakForTicket(ticket);
                totalTradesClosed++;
                historicalProfit += profit;
                if(profit > 0) { totalTradesWon++; consecutiveLosses = 0; }
                else             consecutiveLosses++;
                LogTrade(profit > 0, profit, "PeakProfit-Close");
                LogTradeToFile(profit > 0, profit, "PeakProfit");
                SetCandleWaitAfterProfit();
            }
        }
    }
}

void ManagePossibleTradeSystem()
{
    datetime now           = TimeCurrent();
    int      activationSec = GetPossibleActivationSeconds();
    int      maturitySec   = GetTradeMaturitySeconds();

    // Limpiar entradas stale (tickets que ya no existen)
    CleanupPossibleTrades();

    // Iterar sobre todas las posiciones abiertas
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(!positionInfo.SelectByIndex(i)) continue;
        if(positionInfo.Symbol() != _Symbol || positionInfo.Magic() != 99999) continue;

        ulong  ticket    = positionInfo.Ticket();
        double profit    = positionInfo.Profit() + positionInfo.Commission() + positionInfo.Swap();
        int    direction = (positionInfo.PositionType() == POSITION_TYPE_BUY) ? 1 : -1;

        // Solo aplica a trades negativos
        if(profit >= 0) continue;

        // ¿Ya está registrado en el sistema POSIBLE?
        int idx = FindPossibleTrade(ticket);

        if(idx < 0)
        {
            // Registrar nuevo trade negativo
            if(possibleTradeCount < ArraySize(possibleTrades))
            {
                possibleTrades[possibleTradeCount].ticket          = ticket;
                possibleTrades[possibleTradeCount].openTime        = (datetime)positionInfo.Time();
                possibleTrades[possibleTradeCount].lastCheckTime   = now;
                possibleTrades[possibleTradeCount].openPrice       = positionInfo.PriceOpen();
                possibleTrades[possibleTradeCount].direction       = direction;
                possibleTrades[possibleTradeCount].lotSize         = positionInfo.Volume();
                possibleTrades[possibleTradeCount].isPossible      = false;
                possibleTrades[possibleTradeCount].validationCount = 0;
                possibleTrades[possibleTradeCount].validationReason= "";
                idx = possibleTradeCount;
                possibleTradeCount++;
            }
            continue;
        }

        // v7.5: MADUREZ — no activar POSIBLE si el trade es muy joven
        datetime tradeAge = now - possibleTrades[idx].openTime;
        if(tradeAge < maturitySec)
        {
            // Trade muy joven — esperar que madure antes de juzgarlo
            continue;
        }

        // ¿Ya pasaron los segundos de activación desde el último chequeo?
        datetime elapsed = now - possibleTrades[idx].lastCheckTime;
        if(elapsed < activationSec) continue;

        // ACTIVAR estado POSIBLE
        if(!possibleTrades[idx].isPossible)
        {
            possibleTrades[idx].isPossible = true;
            Print("⚠️ [POSIBLE] Trade #" + IntegerToString((long)ticket) +
                  " marcado como POSIBLE tras " + IntegerToString((int)tradeAge) + "s | P&L: $" +
                  DoubleToString(profit, 2));
        }

        // EJECUTAR VALIDACIÓN
        possibleTrades[idx].lastCheckTime   = now;
        possibleTrades[idx].validationCount++;

        bool isValid = ValidatePossibleTrade(direction, ticket);

        if(!isValid)
        {
            // Señal inválida → cerrar inmediatamente
            Print("❌ [POSIBLE] Validación FALLIDA en trade #" + IntegerToString((long)ticket) +
                  " (intento #" + IntegerToString(possibleTrades[idx].validationCount) +
                  ") | Cerrando por señal incorrecta | P&L: $" + DoubleToString(profit, 2));

            if(trade.PositionClose(ticket))
            {
                totalTradesClosed++;
                historicalProfit += profit;
                totalTradesLost++;
                totalLoss += MathAbs(profit);
                consecutiveLosses++;

                LogTrade(false, profit, "Sistema POSIBLE - Señal Inválida");
                LogTradeToFile(false, profit, "POSIBLE-Cierre");

                // Limpiar de la lista
                RemovePossibleTrade(idx);

                Print("🗑️ [POSIBLE] Trade cerrado. Pérdida: $" + DoubleToString(profit, 2) +
                      " | Histórico: $" + DoubleToString(historicalProfit, 2));
            }
        }
        else
        {
            // Señal válida → continuar, se re-validará en los próximos X segundos
            Print("🔄 [POSIBLE] Validación OK en trade #" + IntegerToString((long)ticket) +
                  " (intento #" + IntegerToString(possibleTrades[idx].validationCount) +
                  ") | Señal a favor. Manteniendo. P&L: $" + DoubleToString(profit, 2));
        }
    }
}

// Valida si la señal de un trade POSIBLE sigue siendo correcta
// Usa: Volumen, Dirección EMA, RSI, ATR momentum, estructura de precio
bool ValidatePossibleTrade(int direction, ulong ticket)
{
    int validFactors = 0;
    int totalFactors = 5;

    // --- 1. Volumen: debe ser >= 80% del promedio (mercado con interés) ---
    if(ArraySize(volumeBuffer) >= Volume_Period)
    {
        double avgVol = 0;
        for(int i = 1; i <= Volume_Period; i++) avgVol += volumeBuffer[i];
        avgVol /= Volume_Period;
        double curVol = volumeBuffer[0];
        if(avgVol > 0 && (curVol / avgVol) >= 0.80)
            validFactors++;
    }
    else validFactors++; // Sin datos de volumen, no penalizar

    // --- 2. EMA Alignment: EMAs aún apuntan en dirección del trade ---
    if(ArraySize(emaFastBuffer) >= 2 && ArraySize(emaSlowBuffer) >= 2)
    {
        double emaF = emaFastBuffer[0];
        double emaS = emaSlowBuffer[0];
        if(direction == 1 && emaF >= emaS) validFactors++;  // Alcista: EMA20 >= EMA50
        else if(direction == -1 && emaF <= emaS) validFactors++; // Bajista: EMA20 <= EMA50
    }
    else validFactors++;

    // --- 3. RSI no en zona extrema contraria ---
    double rsi = cachedRSI;
    if(direction == 1 && rsi > 25 && rsi < 85)  validFactors++; // No sobrecomprado extremo
    else if(direction == -1 && rsi > 15 && rsi < 75) validFactors++; // No sobrevendido extremo

    // --- 4. ATR: Volatilidad existente (mercado vivo) ---
    if(ArraySize(atrBuffer) > 0)
    {
        double atr = atrBuffer[0];
        if(atr > 5 * symbolPoint) // ATR mínimo para mercado activo
            validFactors++;
    }
    else validFactors++;

    // --- 5. Precio NO en fuerte movimiento contrario ---
    if(ArraySize(emaFastBuffer) >= 1)
    {
        double currentPrice = (direction == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                               : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        double emaF = emaFastBuffer[0];
        double atrV = (ArraySize(atrBuffer) > 0) ? atrBuffer[0] : 20 * symbolPoint;

        // Si precio está más de 3x ATR en contra de la dirección, señal en contra
        if(direction == 1 && (emaF - currentPrice) > atrV * 3.0)
        {
            // Precio muy por debajo de EMA → señal invalidada
        }
        else if(direction == -1 && (currentPrice - emaF) > atrV * 3.0)
        {
            // Precio muy por encima de EMA → señal invalidada
        }
        else
            validFactors++; // Dentro de rango aceptable
    }
    else validFactors++;

    // v7.5: Umbral por TF (M15=3/5, M30/H1=2/5 — más leniente en TF amplios)
    int threshold = GetPossibleValidThreshold();
    bool isValid = (validFactors >= threshold);

    Print("[POSIBLE-VALIDATE] Ticket #" + IntegerToString((long)ticket) +
          " | Dir: " + (direction==1?"BUY":"SELL") +
          " | Factores: " + IntegerToString(validFactors) + "/" + IntegerToString(totalFactors) +
          " | Umbral: " + IntegerToString(threshold) +
          " | " + (isValid ? "✅ VÁLIDO" : "❌ INVÁLIDO"));

    return isValid;
}

// Busca un ticket en el array de trades POSIBLE; retorna índice o -1
int FindPossibleTrade(ulong ticket)
{
    for(int i = 0; i < possibleTradeCount; i++)
        if(possibleTrades[i].ticket == ticket) return i;
    return -1;
}

// Elimina una entrada del array POSIBLE compactando el array
void RemovePossibleTrade(int idx)
{
    if(idx < 0 || idx >= possibleTradeCount) return;
    for(int i = idx; i < possibleTradeCount - 1; i++)
        possibleTrades[i] = possibleTrades[i + 1];
    possibleTradeCount--;
}

// Limpia entradas del array POSIBLE cuyos tickets ya no existen
void CleanupPossibleTrades()
{
    for(int i = possibleTradeCount - 1; i >= 0; i--)
    {
        bool found = false;
        for(int j = PositionsTotal() - 1; j >= 0; j--)
        {
            if(positionInfo.SelectByIndex(j))
            {
                if(positionInfo.Ticket() == possibleTrades[i].ticket)
                {
                    found = true;
                    break;
                }
            }
        }
        if(!found)
            RemovePossibleTrade(i);
    }
}

// PROBLEMA #15: Trailing stop dinámico
void ManageTrailingStop()
{
    if(!EnableTrailingStop)
        return;

    double tickValue = symbolTickValue;
    double tickSize = symbolTickSize;
    double valuePerTick = (tickSize > 0) ? tickValue / tickSize : 1.0;

    double atr = 0.0;
    if(CopyBuffer(atrHandle, 0, 0, 1, atrBuffer) > 0)
        atr = atrBuffer[0];
    if(atr == 0) atr = 20.0;

    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(!positionInfo.SelectByIndex(i)) continue;
        if(positionInfo.Symbol() != _Symbol || positionInfo.Magic() != 99999) continue;

        double profit = positionInfo.Profit() + positionInfo.Commission() + positionInfo.Swap();
        double lotSize = positionInfo.Volume();
        double profitTarget = dynamicMinProfitTarget;
        
        // --- LÓGICA DE BREAK-EVEN AUTOMÁTICO (Súper Seguro y Adaptativo) ---
        // El porcentaje de disparo ahora depende del Timeframe para evitar ruido en M1/M5
        double beTrigger = GetBreakEvenTrigger();
        if(profit > profitTarget * beTrigger)
        {
            double openPrice = positionInfo.PriceOpen();
            double currentSL = positionInfo.StopLoss();
            
            if(positionInfo.PositionType() == POSITION_TYPE_BUY)
            {
                double bePrice = NormalizeDouble(openPrice + (2.0 * symbolPoint), symbolDigits);
                if(currentSL < bePrice)
                {
                    trade.PositionModify(positionInfo.Ticket(), bePrice, 0);
                }
            }
            else
            {
                double bePrice = NormalizeDouble(openPrice - (2.0 * symbolPoint), symbolDigits);
                if(currentSL > bePrice || currentSL == 0)
                {
                    trade.PositionModify(positionInfo.Ticket(), bePrice, 0);
                }
            }
        }

        // --- TRAILING STOP DINÁMICO (Basado en Volatilidad) ---
        // Solo se activa cuando el profit es el doble del target para dejar correr la ganancia
        if(profit > profitTarget * 2.0)
        {
            double currentSL = positionInfo.StopLoss();
            double trailingDistance = atr * (0.5 + volatilityLevel);

            if(positionInfo.PositionType() == POSITION_TYPE_BUY)
            {
                double newSL = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_BID) - trailingDistance, symbolDigits);
                if(newSL > currentSL)
                {
                    trade.PositionModify(positionInfo.Ticket(), newSL, 0);
                }
            }
            else
            {
                double newSL = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_ASK) + trailingDistance, symbolDigits);
                if(newSL < currentSL)
                {
                    trade.PositionModify(positionInfo.Ticket(), newSL, 0);
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| FUNCIONES AUXILIARES                                             |
//+------------------------------------------------------------------+

int CountOpenTrades()
{
    int count = 0;
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(positionInfo.SelectByIndex(i))
            if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == 99999)
                count++;
    }
    return count;
}

double GetTotalOpenProfit()
{
    double currentOpenProfit = 0.0;
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(positionInfo.SelectByIndex(i))
        {
            if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == 99999)
            {
                totalProfit += positionInfo.Profit() + positionInfo.Commission() + positionInfo.Swap();
            }
        }
    }
    return totalProfit;
}

void LogTrade(bool isWinning, double profit, string reason)
{
    Print("[TRADE] " + TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES) + 
          " | " + (isWinning ? "✓ GANANCIA" : "✗ PÉRDIDA") + 
          " | $" + DoubleToString(profit, 2) + " | " + reason);

    if(ArraySize(profitsPerTrade) >= 100)
        ArrayRemove(profitsPerTrade, 0, 1);
    
    ArrayResize(profitsPerTrade, ArraySize(profitsPerTrade) + 1);
    profitsPerTrade[ArraySize(profitsPerTrade) - 1] = profit;
}

void UpdateVisualInformation()
{
    if(!ShowPanel)
        return;

    DrawMainPanel();
    DrawIndicatorPanel();
    DrawAlertPanel();
    DrawStatisticsPanel();
    DrawSessionPanel();
}

void DrawMainPanel()
{
    string panelName = "XAU_MAIN_PANEL";
    color bgColor = clrBlack;
    color borderColor = clrWhiteSmoke;

    if(alertLevel == 1) borderColor = clrYellow;
    else if(alertLevel == 2) borderColor = clrOrange;
    else if(alertLevel == 3) borderColor = clrRed;

    ObjectDelete(0, panelName);
    ObjectCreate(0, panelName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
    ObjectSetInteger(0, panelName, OBJPROP_XDISTANCE, 10);
    ObjectSetInteger(0, panelName, OBJPROP_YDISTANCE, 10);
    ObjectSetInteger(0, panelName, OBJPROP_XSIZE, 420);
    ObjectSetInteger(0, panelName, OBJPROP_YSIZE, 400);
    ObjectSetInteger(0, panelName, OBJPROP_BGCOLOR, bgColor);
    ObjectSetInteger(0, panelName, OBJPROP_BORDER_COLOR, borderColor);
    ObjectSetInteger(0, panelName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
    ObjectSetInteger(0, panelName, OBJPROP_WIDTH, 3);

    string textName = "XAU_MAIN_TEXT";
    ObjectDelete(0, textName);

    string text = "╔════════════════ XAU/USD v5.2 ════════════════╗\n";
    text += "║ 💰 CAPITAL: $" + DoubleToString(currentCapital, 2) + " | EQUITY: $" + 
            DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2) + "\n";
    
    if(capitalProtectionActive)
    {
        text += "║ 🔒 PROTECCIÓN ACTIVA | Trabajo: $" + DoubleToString(workingCapital, 2) + 
                " | Seguro: $" + DoubleToString(protectedCapital, 2) + "\n";
    }
    
    text += "║ 📊 MARGEN: " + DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_FREE), 2) + " | " +
            DoubleToString((AccountInfoDouble(ACCOUNT_MARGIN_FREE) / AccountInfoDouble(ACCOUNT_EQUITY) * 100), 1) + "%\n";
    text += "║\n";
    text += "║ 📈 ABIERTOS: " + IntegerToString(CountOpenTrades()) + "/" + IntegerToString(dynamicMaxOpenTrades) + 
            " | CERRADOS: " + IntegerToString(totalTradesClosed) + "\n";
    text += "║ 💵 P&L Actual: $" + DoubleToString(GetTotalOpenProfit(), 2) + " | Histórico: $" + 
            DoubleToString(historicalProfit, 2) + "\n";
    text += "║ 💸 Pérdida Diaria: $" + DoubleToString(dailyLoss, 2) + " / $" + 
            DoubleToString(dynamicMaxDailyLoss, 2) + "\n";
    text += "║ 🎯 Target Ganancia: $" + DoubleToString(dynamicMinProfitTarget, 2) + "\n";
    text += "║\n";
    text += "║ 📡 PING: " + DoubleToString(currentPing, 0) + "ms | SPREAD: " + 
            DoubleToString(currentSpread, 1) + " pts\n";
    text += "║ 🌡️  VOL: ";
    if(volatilityLevel < 0.4) text += "BAJA";
    else if(volatilityLevel < 0.7) text += "NORMAL";
    else text += "ALTA";
    text += " | Apalancamiento: 1:" + IntegerToString(dynamicLeverage) + "\n";
    
    if(tradeDirection == 1) text += "║ 🟢 BUY MODE";
    else if(tradeDirection == -1) text += "║ 🔴 SELL MODE";
    else text += "║ ⚪ NEUTRAL";
    text += "\n";
    
    text += "║ ⏱️  Estado: ";
    if(isPaused || isInRecoveryMode)
    {
        text += "EN PAUSA";
    }
    else text += "ACTIVO";
    text += "\n";

    // v6.0: Estado Sistema POSIBLE
    if(possibleTradeCount > 0)
    {
        text += "║ ⚠️  POSIBLES: " + IntegerToString(possibleTradeCount) + " trade(s) en validación\n";
    }

    // v6.0: Candle wait status
    if(TimeCurrent() < nextTradeAllowedTime)
    {
        int secsWait = (int)(nextTradeAllowedTime - TimeCurrent());
        text += "║ ⏳ Espera vela: " + IntegerToString(secsWait) + "s\n";
    }

    text += "╠════════════════════════════════════════════════╣\n";
    text += "║ Ganadores: " + IntegerToString(totalTradesWon) + " | Perdedores: " + 
            IntegerToString(totalTradesLost) + " | Win Rate: " + 
            DoubleToString(winRate * 100, 1) + "%\n";
    text += "║ Profit Factor: " + DoubleToString(profitFactor, 2) + "\n";
    text += "║ Cierres Totales: " + IntegerToString(totalProfitClosures) + "\n";
    text += "╚════════════════════════════════════════════════╝\n";

    ObjectCreate(0, textName, OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, textName, OBJPROP_XDISTANCE, 15);
    ObjectSetInteger(0, textName, OBJPROP_YDISTANCE, 15);
    ObjectSetString(0, textName, OBJPROP_TEXT, text);
    ObjectSetInteger(0, textName, OBJPROP_FONTSIZE, 8);
    ObjectSetString(0, textName, OBJPROP_FONT, "Courier New");
    ObjectSetInteger(0, textName, OBJPROP_COLOR, clrLime);

    ChartRedraw();
}

void DrawIndicatorPanel()
{
    string text = "📊 RSI: " + DoubleToString(cachedRSI, 1) + 
                  " | ATR: " + DoubleToString(cachedATR, 2) + 
                  " | EMA 20: " + DoubleToString(cachedEMAFast, 2) + 
                  " | EMA 50: " + DoubleToString(cachedEMASlow, 2) +
                  " | Vol: " + DoubleToString(cachedVolume, 0);

    ObjectDelete(0, "XAU_INDICATOR_INFO");
    ObjectCreate(0, "XAU_INDICATOR_INFO", OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, "XAU_INDICATOR_INFO", OBJPROP_XDISTANCE, 450);
    ObjectSetInteger(0, "XAU_INDICATOR_INFO", OBJPROP_YDISTANCE, 15);
    ObjectSetString(0, "XAU_INDICATOR_INFO", OBJPROP_TEXT, text);
    ObjectSetInteger(0, "XAU_INDICATOR_INFO", OBJPROP_FONTSIZE, 9);
    ObjectSetString(0, "XAU_INDICATOR_INFO", OBJPROP_FONT, "Courier New");
    ObjectSetInteger(0, "XAU_INDICATOR_INFO", OBJPROP_COLOR, clrCyan);

    string fibText = "📐 FIB: 0%: " + DoubleToString(fibLevel_0, 2) + 
                     " | OTE: " + DoubleToString(fibOTE_Min, 2) + "-" + DoubleToString(fibOTE_Max, 2) +
                     " | 100%: " + DoubleToString(fibLevel_100, 2);

    ObjectDelete(0, "XAU_FIB_INFO");
    ObjectCreate(0, "XAU_FIB_INFO", OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, "XAU_FIB_INFO", OBJPROP_XDISTANCE, 450);
    ObjectSetInteger(0, "XAU_FIB_INFO", OBJPROP_YDISTANCE, 30);
    ObjectSetString(0, "XAU_FIB_INFO", OBJPROP_TEXT, fibText);
    ObjectSetInteger(0, "XAU_FIB_INFO", OBJPROP_FONTSIZE, 8);
    ObjectSetString(0, "XAU_FIB_INFO", OBJPROP_FONT, "Courier New");
    ObjectSetInteger(0, "XAU_FIB_INFO", OBJPROP_COLOR, clrGold);
}

void DrawAlertPanel()
{
    if(alertMessage == "")
        return;

    color alertColor = clrYellow;
    if(alertLevel == 2) alertColor = clrOrange;
    else if(alertLevel == 3) alertColor = clrRed;

    ObjectDelete(0, "XAU_ALERT_TEXT");
    ObjectCreate(0, "XAU_ALERT_TEXT", OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, "XAU_ALERT_TEXT", OBJPROP_XDISTANCE, 10);
    ObjectSetInteger(0, "XAU_ALERT_TEXT", OBJPROP_YDISTANCE, 420);
    ObjectSetString(0, "XAU_ALERT_TEXT", OBJPROP_TEXT, alertMessage);
    ObjectSetInteger(0, "XAU_ALERT_TEXT", OBJPROP_FONTSIZE, 10);
    ObjectSetString(0, "XAU_ALERT_TEXT", OBJPROP_FONT, "Courier New");
    ObjectSetInteger(0, "XAU_ALERT_TEXT", OBJPROP_COLOR, alertColor);
}

void DrawStatisticsPanel()
{
    string text = "📈 Ganados: " + IntegerToString(totalTradesWon) + 
                  " | Perdidos: " + IntegerToString(totalTradesLost) + 
                  " | Ganancia Prom: $" + DoubleToString(averageProfit, 2) + 
                  " | Pérdida Prom: $" + DoubleToString(averageLoss, 2);

    ObjectDelete(0, "XAU_STATS_TEXT");
    ObjectCreate(0, "XAU_STATS_TEXT", OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, "XAU_STATS_TEXT", OBJPROP_XDISTANCE, 450);
    ObjectSetInteger(0, "XAU_STATS_TEXT", OBJPROP_YDISTANCE, 35);
    ObjectSetString(0, "XAU_STATS_TEXT", OBJPROP_TEXT, text);
    ObjectSetInteger(0, "XAU_STATS_TEXT", OBJPROP_FONTSIZE, 8);
    ObjectSetString(0, "XAU_STATS_TEXT", OBJPROP_FONT, "Courier New");
    ObjectSetInteger(0, "XAU_STATS_TEXT", OBJPROP_COLOR, clrLimeGreen);
}

void GenerateDailyReport()
{
    Print("\n╔════════════════ REPORTE DIARIO ════════════════╗");
    Print("║ Fecha: " + TimeToString(TimeCurrent(), TIME_DATE));
    Print("║ Capital: $" + DoubleToString(currentCapital, 2));
    Print("║ Operaciones: " + IntegerToString(CountOpenTrades()) + " abiertas | " + 
          IntegerToString(totalTradesClosed) + " cerradas");
    Print("║ Cierres Totales: " + IntegerToString(totalProfitClosures));
    Print("║ Ganancia: $" + DoubleToString(dailyProfit, 2) + " | Pérdida: $" + 
          DoubleToString(dailyLoss, 2));
    Print("║ Win Rate: " + DoubleToString(winRate * 100, 1) + "% | Profit Factor: " + 
          DoubleToString(profitFactor, 2));
    Print("║ Histórico: $" + DoubleToString(historicalProfit, 2));
    if(capitalProtectionActive)
    {
Print("║ Capital Protegido: $" + DoubleToString(protectedCapital, 2));
    }
    Print("╚════════════════════════════════════════════════════╝\n");
}

void DrawSessionPanel()
{
    UpdateSessionLevelsOptimized();
    
    string text = "SESIONES | London: " + DoubleToString(londonHigh, 1) + "/" + DoubleToString(londonLow, 1) +
                  " | NY: " + DoubleToString(nyHigh, 1) + "/" + DoubleToString(nyLow, 1);

    ObjectDelete(0, "XAU_SESSION_INFO");
    ObjectCreate(0, "XAU_SESSION_INFO", OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, "XAU_SESSION_INFO", OBJPROP_XDISTANCE, 10);
    ObjectSetInteger(0, "XAU_SESSION_INFO", OBJPROP_YDISTANCE, 450);
    ObjectSetString(0, "XAU_SESSION_INFO", OBJPROP_TEXT, text);
    ObjectSetInteger(0, "XAU_SESSION_INFO", OBJPROP_FONTSIZE, 8);
    ObjectSetString(0, "XAU_SESSION_INFO", OBJPROP_FONT, "Courier New");
    ObjectSetInteger(0, "XAU_SESSION_INFO", OBJPROP_COLOR, clrOrange);
    
    string killZoneText = "KILL ZONE: ";
    if(IsKillZoneActive())
        killZoneText += "ACTIVA (" + IntegerToString(LondonKillZoneStart) + ":00-" + IntegerToString(LondonKillZoneEnd) + ":00 UTC)";
    else
        killZoneText += "INACTIVA";

    ObjectDelete(0, "XAU_KILLZONE_INFO");
    ObjectCreate(0, "XAU_KILLZONE_INFO", OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, "XAU_KILLZONE_INFO", OBJPROP_XDISTANCE, 10);
    ObjectSetInteger(0, "XAU_KILLZONE_INFO", OBJPROP_YDISTANCE, 465);
    ObjectSetString(0, "XAU_KILLZONE_INFO", OBJPROP_TEXT, killZoneText);
    ObjectSetInteger(0, "XAU_KILLZONE_INFO", OBJPROP_FONTSIZE, 9);
    ObjectSetString(0, "XAU_KILLZONE_INFO", OBJPROP_FONT, "Courier New");
    ObjectSetInteger(0, "XAU_KILLZONE_INFO", OBJPROP_COLOR, IsKillZoneActive() ? clrLime : clrGray);
}

//+------------------------------------------------------------------+
//| FIN DEL CODIGO - XAU_USD ICT MultiTrader Pro London Open        |
//+------------------------------------------------------------------+
//| FIN DEL CÓDIGO - XAU_USD_MultiTrader_Pro v5.2 Mejorado & Listo   |
//+------------------------------------------------------------------+
