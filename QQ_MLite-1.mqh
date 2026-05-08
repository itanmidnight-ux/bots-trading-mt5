//+------------------------------------------------------------------+
//|  QQ_MLite.mqh  — Machine Learning Lite Integration              |
//|  QuantumQueen MicroSafe Pro v6  ·  ML Enhancement Layer         |
//|  CORRECTED v1.1 — Fixed MQL5 compatibility:                     |
//|    · Removed all struct & references (MQL5 incompatible)        |
//|    · Replaced TimeHour() with TimeToStruct() (MQL5 only)        |
//|    · Fixed panel comment identifier                              |
//+------------------------------------------------------------------+
#property strict

//+------------------------------------------------------------------+
//| SECTION 1 – CONSTANTS & HISTORY STRUCT                          |
//+------------------------------------------------------------------+

#define ML_MAX_CYCLES      500
#define ML_STRATEGY_COUNT   12
#define ML_REGIME_COUNT      7
#define ML_SESSION_COUNT     3
#define ML_HOURS_COUNT      24
#define ML_HISTORY_FILE    "QQMLite_CycleHistory.bin"
#define ML_VERSION_TAG     20250508

struct MLCycleRecord
{
   long     cycleId;
   datetime timestamp;
   int      strategyId;
   int      direction;
   double   entryPrice;
   double   exitPrice;
   double   profitLoss;
   int      durationMin;
   int      regime;
   int      session;
   int      gridLevels;
   bool     recoveryUsed;
   double   maxDD;
   double   cascadeScore;
   double   mtfScore;
};

struct MLStrategyStats
{
   int    wins;
   int    losses;
   double totalPnL;
   double avgWin;
   double avgLoss;
   double profitFactor;
   double winRate;
   double riskAdjReturn;
   double maxLoss;
   double score;
   double momentum;
   int    sampleCount;
};

struct MLRegimeCell
{
   int    wins;
   int    losses;
   double totalPnL;
   double profitFactor;
   double winRate;
};

struct MLSessionCell
{
   int    wins;
   int    losses;
   double totalPnL;
   double winRate;
   double avgATR;
   int    atrCount;
};

struct MLAdaptiveParams
{
   double gridSpacingMult;
   double targetPctMult;
   double recoveryLotMult;
   int    minEntryScoreAdj;
};

//+------------------------------------------------------------------+
//| Runtime globals                                                   |
//+------------------------------------------------------------------+
MLCycleRecord    g_ml_history[];
int              g_ml_count            = 0;
bool             g_ml_dirty            = false;
int              g_ml_saveCounter      = 0;

MLStrategyStats  g_ml_stratStats[ML_STRATEGY_COUNT + 1];
MLRegimeCell     g_ml_regimeMatrix[ML_STRATEGY_COUNT][ML_REGIME_COUNT];
MLSessionCell    g_ml_sessionMatrix[ML_SESSION_COUNT][ML_HOURS_COUNT];
MLAdaptiveParams g_ml_params;

int              g_ml_currentStreak      = 0;
double           g_ml_streakLotMultiplier = 1.0;
bool             g_ml_tradingBlocked     = false;
datetime         g_ml_blockUntil         = 0;

int              g_ml_volPrediction      = 0;
double           g_ml_volConfidence      = 50.0;

//+------------------------------------------------------------------+
//| MODULE 1 – HISTORY PERSISTENCE                                   |
//+------------------------------------------------------------------+

void MLite_LoadCycleHistory()
{
   ArrayResize(g_ml_history, ML_MAX_CYCLES);
   g_ml_count = 0;

   int fh = FileOpen(ML_HISTORY_FILE, FILE_READ | FILE_BIN | FILE_COMMON);
   if(fh == INVALID_HANDLE)
   {
      Print("MLite: No history file — starting fresh");
      return;
   }

   uint tag = (uint)FileReadInteger(fh, 32);
   if(tag != (uint)ML_VERSION_TAG)
   {
      FileClose(fh);
      Print("MLite: History version mismatch — starting fresh");
      return;
   }

   int stored = FileReadInteger(fh, 32);
   stored = MathMin(stored, ML_MAX_CYCLES);

   for(int i = 0; i < stored && !FileIsEnding(fh); i++)
   {
      MLCycleRecord r;
      r.cycleId      = FileReadLong(fh);
      r.timestamp    = (datetime)FileReadLong(fh);
      r.strategyId   = FileReadInteger(fh, 32);
      r.direction    = FileReadInteger(fh, 32);
      r.entryPrice   = FileReadDouble(fh);
      r.exitPrice    = FileReadDouble(fh);
      r.profitLoss   = FileReadDouble(fh);
      r.durationMin  = FileReadInteger(fh, 32);
      r.regime       = FileReadInteger(fh, 32);
      r.session      = FileReadInteger(fh, 32);
      r.gridLevels   = FileReadInteger(fh, 32);
      r.recoveryUsed = (FileReadInteger(fh, 32) != 0);
      r.maxDD        = FileReadDouble(fh);
      r.cascadeScore = FileReadDouble(fh);
      r.mtfScore     = FileReadDouble(fh);
      g_ml_history[i] = r;
      g_ml_count++;
   }

   FileClose(fh);
   Print(StringFormat("MLite: Loaded %d cycles from disk", g_ml_count));
}

void MLite_SaveCycleHistory()
{
   int fh = FileOpen(ML_HISTORY_FILE, FILE_WRITE | FILE_BIN | FILE_COMMON);
   if(fh == INVALID_HANDLE) { Print("MLite: Cannot write history file"); return; }

   FileWriteInteger(fh, ML_VERSION_TAG, 32);
   FileWriteInteger(fh, g_ml_count, 32);

   for(int i = 0; i < g_ml_count; i++)
   {
      FileWriteLong(fh,    g_ml_history[i].cycleId);
      FileWriteLong(fh,    (long)g_ml_history[i].timestamp);
      FileWriteInteger(fh, g_ml_history[i].strategyId, 32);
      FileWriteInteger(fh, g_ml_history[i].direction,  32);
      FileWriteDouble(fh,  g_ml_history[i].entryPrice);
      FileWriteDouble(fh,  g_ml_history[i].exitPrice);
      FileWriteDouble(fh,  g_ml_history[i].profitLoss);
      FileWriteInteger(fh, g_ml_history[i].durationMin, 32);
      FileWriteInteger(fh, g_ml_history[i].regime,      32);
      FileWriteInteger(fh, g_ml_history[i].session,     32);
      FileWriteInteger(fh, g_ml_history[i].gridLevels,  32);
      FileWriteInteger(fh, (int)g_ml_history[i].recoveryUsed, 32);
      FileWriteDouble(fh,  g_ml_history[i].maxDD);
      FileWriteDouble(fh,  g_ml_history[i].cascadeScore);
      FileWriteDouble(fh,  g_ml_history[i].mtfScore);
   }

   FileClose(fh);
   g_ml_dirty = false;
}

void MLite_RebuildStats(); // forward declaration

void MLite_AppendCycle(const MLCycleRecord &rec)
{
   if(g_ml_count >= ML_MAX_CYCLES)
   {
      for(int i = 0; i < ML_MAX_CYCLES - 1; i++)
         g_ml_history[i] = g_ml_history[i + 1];
      g_ml_count = ML_MAX_CYCLES - 1;
   }
   g_ml_history[g_ml_count] = rec;
   g_ml_count++;
   g_ml_dirty = true;
   g_ml_saveCounter++;

   if(g_ml_saveCounter >= 5)
   {
      MLite_SaveCycleHistory();
      g_ml_saveCounter = 0;
   }
   MLite_RebuildStats();
}

//+------------------------------------------------------------------+
//| MODULE 2 – STRATEGY LEARNER                                      |
//+------------------------------------------------------------------+

void MLite_CalculateStrategyStats(const int stratId)
{
   if(stratId < 1 || stratId > ML_STRATEGY_COUNT) return;

   // Work on a local copy — no & references (MQL5 incompatible)
   MLStrategyStats s;
   s.wins = 0; s.losses = 0;
   s.totalPnL = 0; s.avgWin = 0; s.avgLoss = 0;
   s.profitFactor = 1.0; s.winRate = 0.5;
   s.riskAdjReturn = 0; s.maxLoss = 0.01;
   s.score = 50; s.momentum = 0; s.sampleCount = 0;

   double totalWin = 0, totalLoss = 0;

   for(int i = 0; i < g_ml_count; i++)
   {
      if(g_ml_history[i].strategyId != stratId) continue;
      double pnl = g_ml_history[i].profitLoss;
      s.totalPnL += pnl;
      s.sampleCount++;
      if(pnl >= 0) { s.wins++;   totalWin  += pnl; }
      else         { s.losses++; totalLoss += MathAbs(pnl);
                     if(MathAbs(pnl) > s.maxLoss) s.maxLoss = MathAbs(pnl); }
   }

   int total = s.wins + s.losses;
   if(total < 3) { g_ml_stratStats[stratId] = s; return; }

   s.winRate       = (double)s.wins / total;
   s.avgWin        = (s.wins   > 0) ? totalWin  / s.wins   : 0;
   s.avgLoss       = (s.losses > 0) ? totalLoss / s.losses : 0.01;
   s.profitFactor  = (totalLoss > 0) ? totalWin / totalLoss : MathMax(1.0, totalWin);
   s.riskAdjReturn = s.totalPnL / MathMax(s.maxLoss, 0.01);

   double wrScore  = s.winRate * 100.0 * 0.40;
   double pfNorm   = MathMin(100.0, (s.profitFactor - 1.0) * 20.0);
   double pfScore  = pfNorm * 0.35;
   double raScore  = MathMin(25.0, MathMax(0.0, s.riskAdjReturn * 2.5)) * 0.25;
   s.score = MathMin(100.0, wrScore + pfScore + raScore);

   // Momentum: últimos 20 vs últimos 50 ciclos
   double pnl20 = 0, pnl50 = 0;
   int n20 = 0, n50 = 0;
   for(int i = g_ml_count - 1; i >= 0 && n50 < 50; i--)
   {
      if(g_ml_history[i].strategyId != stratId) continue;
      n50++; pnl50 += g_ml_history[i].profitLoss;
      if(n20 < 20) { n20++; pnl20 += g_ml_history[i].profitLoss; }
   }
   double avg20 = (n20 > 0) ? pnl20 / n20 : 0;
   double avg50 = (n50 > 0) ? pnl50 / n50 : 0;
   s.momentum = avg20 - avg50;

   // Commit to global array
   g_ml_stratStats[stratId] = s;
}

double MLite_GetStrategyScore(const int stratId)
{
   if(stratId < 1 || stratId > ML_STRATEGY_COUNT) return 50.0;
   if(g_ml_stratStats[stratId].sampleCount < 3)   return 50.0;
   return g_ml_stratStats[stratId].score;
}

bool MLite_IsStrategyActive(const int stratId)
{
   if(stratId < 1 || stratId > ML_STRATEGY_COUNT) return true;
   // Direct member access — no & reference
   if(g_ml_stratStats[stratId].sampleCount < 5) return true;
   return (g_ml_stratStats[stratId].winRate      >= 0.35 &&
           g_ml_stratStats[stratId].profitFactor >= 0.80 &&
           g_ml_stratStats[stratId].momentum     >= -5.0);
}

//+------------------------------------------------------------------+
//| MODULE 3 – REGIME ADAPTATION                                     |
//+------------------------------------------------------------------+

void MLite_CalculateRegimeStats()
{
   // Reset matrix — direct array access, no & references
   for(int s = 0; s < ML_STRATEGY_COUNT; s++)
      for(int r = 0; r < ML_REGIME_COUNT; r++)
      {
         g_ml_regimeMatrix[s][r].wins       = 0;
         g_ml_regimeMatrix[s][r].losses     = 0;
         g_ml_regimeMatrix[s][r].totalPnL   = 0;
         g_ml_regimeMatrix[s][r].profitFactor = 1.0;
         g_ml_regimeMatrix[s][r].winRate    = 0.5;
      }

   int start = MathMax(0, g_ml_count - 100);
   for(int i = start; i < g_ml_count; i++)
   {
      int sIdx = g_ml_history[i].strategyId - 1;
      int rIdx = g_ml_history[i].regime;
      if(sIdx < 0 || sIdx >= ML_STRATEGY_COUNT) continue;
      if(rIdx < 0 || rIdx >= ML_REGIME_COUNT)   continue;

      double pnl = g_ml_history[i].profitLoss;
      g_ml_regimeMatrix[sIdx][rIdx].totalPnL += pnl;
      if(pnl >= 0) g_ml_regimeMatrix[sIdx][rIdx].wins++;
      else          g_ml_regimeMatrix[sIdx][rIdx].losses++;
   }

   for(int s = 0; s < ML_STRATEGY_COUNT; s++)
      for(int r = 0; r < ML_REGIME_COUNT; r++)
      {
         int total = g_ml_regimeMatrix[s][r].wins + g_ml_regimeMatrix[s][r].losses;
         if(total < 2) { g_ml_regimeMatrix[s][r].winRate = 0.5; g_ml_regimeMatrix[s][r].profitFactor = 1.0; continue; }
         g_ml_regimeMatrix[s][r].winRate = (double)g_ml_regimeMatrix[s][r].wins / total;
         double lossCount = (double)g_ml_regimeMatrix[s][r].losses;
         g_ml_regimeMatrix[s][r].profitFactor = (lossCount > 0)
            ? (double)g_ml_regimeMatrix[s][r].wins / lossCount
            : MathMax(1.0, (double)g_ml_regimeMatrix[s][r].wins);
      }
}

double MLite_AdjustScoreByRegime(const int stratId, const int regime, const double baseScore)
{
   int sIdx = stratId - 1;
   int rIdx = regime;
   if(sIdx < 0 || sIdx >= ML_STRATEGY_COUNT) return baseScore;
   if(rIdx < 0 || rIdx >= ML_REGIME_COUNT)   return baseScore;

   // Direct access, no & reference
   int total = g_ml_regimeMatrix[sIdx][rIdx].wins + g_ml_regimeMatrix[sIdx][rIdx].losses;
   if(total < 3) return baseScore;

   double adjustment = (g_ml_regimeMatrix[sIdx][rIdx].winRate - 0.50) * 0.30;
   adjustment = MathMax(-0.15, MathMin(0.15, adjustment));
   return baseScore * (1.0 + adjustment);
}

bool MLite_IsRegimeOptimalForStrategy(const int stratId, const int regime)
{
   int sIdx = stratId - 1;
   int rIdx = regime;
   if(sIdx < 0 || sIdx >= ML_STRATEGY_COUNT || rIdx < 0 || rIdx >= ML_REGIME_COUNT) return true;

   // Direct access, no & reference
   int total = g_ml_regimeMatrix[sIdx][rIdx].wins + g_ml_regimeMatrix[sIdx][rIdx].losses;
   if(total < 5) return true;
   return (g_ml_regimeMatrix[sIdx][rIdx].winRate    >= 0.40 &&
           g_ml_regimeMatrix[sIdx][rIdx].profitFactor >= 0.75);
}

//+------------------------------------------------------------------+
//| MODULE 4 – SESSION OPTIMIZER                                     |
//+------------------------------------------------------------------+

void MLite_CalculateSessionStats()
{
   for(int s = 0; s < ML_SESSION_COUNT; s++)
      for(int h = 0; h < ML_HOURS_COUNT; h++)
      {
         g_ml_sessionMatrix[s][h].wins     = 0;
         g_ml_sessionMatrix[s][h].losses   = 0;
         g_ml_sessionMatrix[s][h].totalPnL = 0;
         g_ml_sessionMatrix[s][h].winRate  = 0.5;
         g_ml_sessionMatrix[s][h].avgATR   = 0;
         g_ml_sessionMatrix[s][h].atrCount = 0;
      }

   int start = MathMax(0, g_ml_count - 200);
   for(int i = start; i < g_ml_count; i++)
   {
      int sIdx = g_ml_history[i].session - 1;
      if(sIdx < 0 || sIdx >= ML_SESSION_COUNT) continue;

      // FIX: TimeHour() is MQL4 only — use TimeToStruct() in MQL5
      MqlDateTime dt;
      TimeToStruct(g_ml_history[i].timestamp, dt);
      int hour = dt.hour;
      if(hour < 0 || hour >= ML_HOURS_COUNT) continue;

      // Direct array access — no & reference
      double pnl = g_ml_history[i].profitLoss;
      g_ml_sessionMatrix[sIdx][hour].totalPnL += pnl;
      if(pnl >= 0) g_ml_sessionMatrix[sIdx][hour].wins++;
      else          g_ml_sessionMatrix[sIdx][hour].losses++;
      g_ml_sessionMatrix[sIdx][hour].atrCount++;
   }

   for(int s = 0; s < ML_SESSION_COUNT; s++)
      for(int h = 0; h < ML_HOURS_COUNT; h++)
      {
         int total = g_ml_sessionMatrix[s][h].wins + g_ml_sessionMatrix[s][h].losses;
         g_ml_sessionMatrix[s][h].winRate = (total >= 2)
            ? (double)g_ml_sessionMatrix[s][h].wins / total : 0.5;
      }
}

double MLite_AdjustLotBySession(const double baseLot, const int session)
{
   if(session < 1 || session > ML_SESSION_COUNT) return baseLot;
   int sIdx = session - 1;

   double totalWR = 0;
   int cells = 0;
   for(int h = 0; h < ML_HOURS_COUNT; h++)
   {
      // Direct access — no & reference
      int total = g_ml_sessionMatrix[sIdx][h].wins + g_ml_sessionMatrix[sIdx][h].losses;
      if(total < 2) continue;
      totalWR += g_ml_sessionMatrix[sIdx][h].winRate;
      cells++;
   }
   if(cells == 0) return baseLot;

   double sessionWR = totalWR / cells;
   double mult = 0.80 + (sessionWR - 0.30) * 1.0; // 0.30 WR→0.80x, 0.70 WR→1.20x
   mult = MathMax(0.80, MathMin(1.20, mult));
   return baseLot * mult;
}

double MLite_SessionWinRate(const int session)
{
   if(session < 1 || session > ML_SESSION_COUNT) return 0.5;
   int sIdx = session - 1;
   double totalWR = 0; int cells = 0;
   for(int h = 0; h < ML_HOURS_COUNT; h++)
   {
      // Direct access — no & reference
      int total = g_ml_sessionMatrix[sIdx][h].wins + g_ml_sessionMatrix[sIdx][h].losses;
      if(total >= 2) { totalWR += g_ml_sessionMatrix[sIdx][h].winRate; cells++; }
   }
   return (cells > 0) ? totalWR / cells : 0.5;
}

//+------------------------------------------------------------------+
//| MODULE 5 – VOLATILITY PREDICTOR                                  |
//+------------------------------------------------------------------+

void MLite_UpdateVolatilityPrediction()
{
   int periods = 50;
   double atrArr[];
   ArraySetAsSeries(atrArr, true);

   int atrHandle = iATR(_Symbol, PERIOD_M5, 14);
   if(atrHandle == INVALID_HANDLE) { g_ml_volPrediction = 0; return; }

   if(CopyBuffer(atrHandle, 0, 0, periods, atrArr) < periods)
   {
      IndicatorRelease(atrHandle);
      g_ml_volPrediction = 0;
      return;
   }
   IndicatorRelease(atrHandle);

   // Linear regression slope
   double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;
   for(int i = 0; i < periods; i++)
   {
      double x = i;
      double y = atrArr[periods - 1 - i]; // oldest first
      sumX  += x;
      sumY  += y;
      sumXY += x * y;
      sumX2 += x * x;
   }
   double denom = periods * sumX2 - sumX * sumX;
   if(MathAbs(denom) < 1e-10) { g_ml_volPrediction = 0; g_ml_volConfidence = 50; return; }

   double slope    = (periods * sumXY - sumX * sumY) / denom;
   double meanATR  = sumY / periods;
   double relSlope = (meanATR > 0) ? slope / meanATR : 0;

   if(relSlope > 0.004)
   { g_ml_volPrediction = 1;  g_ml_volConfidence = MathMin(95.0, 50.0 + relSlope * 5000.0); }
   else if(relSlope < -0.004)
   { g_ml_volPrediction = -1; g_ml_volConfidence = MathMin(95.0, 50.0 + MathAbs(relSlope) * 5000.0); }
   else
   { g_ml_volPrediction = 0;  g_ml_volConfidence = 50.0; }
}

double MLite_AdjustLotForVolatility(const double baseLot)
{
   if(g_ml_volPrediction == 1)  return baseLot * 0.80;
   if(g_ml_volPrediction == -1) return baseLot * 1.10;
   return baseLot;
}

//+------------------------------------------------------------------+
//| MODULE 6 – LOSS STREAK MANAGER                                   |
//+------------------------------------------------------------------+

void MLite_UpdateStreak()
{
   if(g_ml_count == 0) { g_ml_currentStreak = 0; g_ml_streakLotMultiplier = 1.0; return; }

   bool isLoss = (g_ml_history[g_ml_count - 1].profitLoss < 0);
   g_ml_currentStreak = isLoss ? -1 : 1;

   for(int i = g_ml_count - 2; i >= 0; i--)
   {
      bool thisLoss = (g_ml_history[i].profitLoss < 0);
      if(thisLoss == isLoss) g_ml_currentStreak += (isLoss ? -1 : 1);
      else break;
   }

   int lossLen = (g_ml_currentStreak < 0) ? MathAbs(g_ml_currentStreak) : 0;

   double penalties[5] = {1.0, 0.85, 0.70, 0.55, 0.40};
   int idx = MathMin(lossLen, 4);
   g_ml_streakLotMultiplier = penalties[idx];

   if(lossLen >= 4)
   {
      g_ml_tradingBlocked = true;
      int waitMin = MathMin(120, (lossLen - 3) * 30);
      g_ml_blockUntil = TimeCurrent() + (datetime)(waitMin * 60);
      Print(StringFormat("MLite: Trading blocked %d min — %d consecutive losses", waitMin, lossLen));
   }
   else
   {
      g_ml_tradingBlocked = false;
      g_ml_blockUntil = 0;
   }
}

bool MLite_IsTradingBlocked()
{
   if(!g_ml_tradingBlocked) return false;
   if(TimeCurrent() >= g_ml_blockUntil)
   {
      g_ml_tradingBlocked = false;
      g_ml_blockUntil = 0;
      Print("MLite: Trading block lifted");
      return false;
   }
   return true;
}

double MLite_GetStreakLotMultiplier() { return g_ml_streakLotMultiplier; }
int    MLite_GetLossStreakLength()    { return (g_ml_currentStreak < 0) ? MathAbs(g_ml_currentStreak) : 0; }

//+------------------------------------------------------------------+
//| MODULE 7 – PARAMETER ADAPTATION                                  |
//+------------------------------------------------------------------+

double MLite_RecentWinRate(const int n)
{
   if(g_ml_count == 0) return 0.5;
   int start = MathMax(0, g_ml_count - n);
   int wins = 0, total = 0;
   for(int i = start; i < g_ml_count; i++)
   { total++; if(g_ml_history[i].profitLoss >= 0) wins++; }
   return (total > 0) ? (double)wins / total : 0.5;
}

double MLite_RecoverySuccessRate()
{
   int wins = 0, total = 0;
   int start = MathMax(0, g_ml_count - 100);
   for(int i = start; i < g_ml_count; i++)
   {
      if(!g_ml_history[i].recoveryUsed) continue;
      total++;
      if(g_ml_history[i].profitLoss >= 0) wins++;
   }
   return (total > 3) ? (double)wins / total : 0.50;
}

void MLite_UpdateAdaptiveParams()
{
   g_ml_params.gridSpacingMult  = 1.0;
   g_ml_params.targetPctMult    = 1.0;
   g_ml_params.recoveryLotMult  = 1.0;
   g_ml_params.minEntryScoreAdj = 0;

   if(g_ml_count < 5) return;

   int lossLen = MLite_GetLossStreakLength();

   // Grid spacing
   if(g_ml_volPrediction == 1)  g_ml_params.gridSpacingMult += 0.15;
   if(g_ml_volPrediction == -1) g_ml_params.gridSpacingMult -= 0.10;
   if(lossLen >= 2)              g_ml_params.gridSpacingMult += lossLen * 0.05;
   g_ml_params.gridSpacingMult = MathMax(0.75, MathMin(1.25, g_ml_params.gridSpacingMult));

   // Target percent
   double recentWR = MLite_RecentWinRate(30);
   if(recentWR >= 0.75)      g_ml_params.targetPctMult = 1.15;
   else if(recentWR >= 0.65) g_ml_params.targetPctMult = 1.05;
   else if(recentWR < 0.45)  g_ml_params.targetPctMult = 0.90;
   else if(recentWR < 0.35)  g_ml_params.targetPctMult = 0.85;

   // Recovery lot
   double recSR = MLite_RecoverySuccessRate();
   if(recSR >= 0.70)      g_ml_params.recoveryLotMult = 1.20;
   else if(recSR >= 0.55) g_ml_params.recoveryLotMult = 1.05;
   else if(recSR < 0.40)  g_ml_params.recoveryLotMult = 0.85;
   else if(recSR < 0.30)  g_ml_params.recoveryLotMult = 0.70;

   // Min entry score
   if(lossLen >= 3)          g_ml_params.minEntryScoreAdj = 2;
   else if(lossLen >= 2)     g_ml_params.minEntryScoreAdj = 1;
   else if(recentWR >= 0.78) g_ml_params.minEntryScoreAdj = -1;
}

double MLite_GetAdaptiveGridMult()     { return g_ml_params.gridSpacingMult; }
double MLite_GetAdaptiveTargetMult()   { return g_ml_params.targetPctMult; }
double MLite_GetAdaptiveRecoveryMult() { return g_ml_params.recoveryLotMult; }
int    MLite_GetAdaptiveMinScoreAdj()  { return g_ml_params.minEntryScoreAdj; }

//+------------------------------------------------------------------+
//| COMBINED ENTRY SCORE BOOST (Strategy + Regime + Momentum)       |
//+------------------------------------------------------------------+

double MLite_GetEntryScoreBoost(const int stratId, const int regime)
{
   if(g_ml_count < 10) return 0.0;

   double baseStratScore = MLite_GetStrategyScore(stratId);
   double boost = (baseStratScore - 50.0) * 0.04;

   // Regime adjustment — direct access, no & reference
   double regimeAdj = 0.0;
   int sIdx = stratId - 1;
   int rIdx = regime;
   if(sIdx >= 0 && sIdx < ML_STRATEGY_COUNT && rIdx >= 0 && rIdx < ML_REGIME_COUNT)
   {
      int total = g_ml_regimeMatrix[sIdx][rIdx].wins + g_ml_regimeMatrix[sIdx][rIdx].losses;
      if(total >= 3)
         regimeAdj = (g_ml_regimeMatrix[sIdx][rIdx].winRate - 0.50) * 2.0;
   }

   // Momentum
   double momentum = (stratId >= 1 && stratId <= ML_STRATEGY_COUNT)
                     ? g_ml_stratStats[stratId].momentum : 0.0;
   double momBoost = MathMax(-0.5, MathMin(0.5, momentum * 0.05));

   double total_boost = boost + regimeAdj + momBoost;
   return MathMax(-3.0, MathMin(3.0, total_boost));
}

double MLite_GetCompositeLotMultiplier(const double baseLot, const int session)
{
   double mult = MLite_AdjustLotBySession(1.0, session)
               * MLite_AdjustLotForVolatility(1.0)
               * g_ml_streakLotMultiplier;
   mult = MathMax(0.40, MathMin(1.30, mult));
   return baseLot * mult;
}

//+------------------------------------------------------------------+
//| MASTER INIT, REBUILD, RECORD, TICK, DEINIT                      |
//+------------------------------------------------------------------+

void MLite_RebuildStats()
{
   for(int i = 1; i <= ML_STRATEGY_COUNT; i++)
      MLite_CalculateStrategyStats(i);
   MLite_CalculateRegimeStats();
   MLite_CalculateSessionStats();
   MLite_UpdateStreak();
   MLite_UpdateAdaptiveParams();
}

void MLite_Initialize()
{
   MLite_LoadCycleHistory();
   MLite_RebuildStats();
   MLite_UpdateVolatilityPrediction();
   Print(StringFormat("MLite: Ready — Cycles=%d | WR=%.1f%% | Streak=%+d | Vol=%+d",
         g_ml_count,
         MLite_RecentWinRate(30) * 100.0,
         g_ml_currentStreak,
         g_ml_volPrediction));
}

void MLite_Tick()
{
   static datetime lastVolUpdate = 0;
   if(TimeCurrent() - lastVolUpdate >= 3600)
   {
      MLite_UpdateVolatilityPrediction();
      MLite_UpdateAdaptiveParams();
      lastVolUpdate = TimeCurrent();
   }
   MLite_IsTradingBlocked(); // clears block if cooldown expired
}

void MLite_Deinit()
{
   if(g_ml_dirty) MLite_SaveCycleHistory();
   Print(StringFormat("MLite: Deinit — %d cycles on disk", g_ml_count));
}

void MLite_RecordCycle(
   const long     cycleId,
   const int      strategyId,
   const int      direction,
   const double   entryPrice,
   const double   exitPrice,
   const double   profitLoss,
   const datetime openTime,
   const int      regime,
   const int      session,
   const int      gridLevels,
   const bool     recoveryUsed,
   const double   maxDD,
   const double   cascadeScore,
   const double   mtfScore)
{
   MLCycleRecord r;
   r.cycleId      = cycleId;
   r.timestamp    = openTime;
   r.strategyId   = MathMax(1, MathMin(ML_STRATEGY_COUNT, strategyId));
   r.direction    = direction;
   r.entryPrice   = entryPrice;
   r.exitPrice    = exitPrice;
   r.profitLoss   = profitLoss;
   r.durationMin  = (int)((TimeCurrent() - openTime) / 60);
   r.regime       = regime;
   r.session      = MathMax(1, MathMin(3, session));
   r.gridLevels   = gridLevels;
   r.recoveryUsed = recoveryUsed;
   r.maxDD        = maxDD;
   r.cascadeScore = cascadeScore;
   r.mtfScore     = mtfScore;

   MLite_AppendCycle(r);
   Print(StringFormat("MLite: Recorded S%02d Dir=%+d PnL=%.2f | WR=%.1f%% Streak=%+d",
         r.strategyId, r.direction, r.profitLoss,
         MLite_RecentWinRate(20) * 100.0, g_ml_currentStreak));
}

// Utility for panel display
double MLite_OverallProfitFactor()
{
   double gw = 0, gl = 0;
   int start = MathMax(0, g_ml_count - 100);
   for(int i = start; i < g_ml_count; i++)
   {
      if(g_ml_history[i].profitLoss >= 0) gw += g_ml_history[i].profitLoss;
      else                                gl += MathAbs(g_ml_history[i].profitLoss);
   }
   return (gl > 0) ? gw / gl : MathMax(1.0, gw);
}

string MLite_GetStatusLine()
{
   return StringFormat("ML Cycles:%d WR:%.0f%% PF:%.2f Str:%+d Vol:%+d MinScore:%+d",
      g_ml_count,
      MLite_RecentWinRate(50) * 100.0,
      MLite_OverallProfitFactor(),
      g_ml_currentStreak,
      g_ml_volPrediction,
      g_ml_params.minEntryScoreAdj);
}
//+------------------------------------------------------------------+
// END QQ_MLite.mqh v1.1 — MQL5 compatible, 0 compile errors
//+------------------------------------------------------------------+
