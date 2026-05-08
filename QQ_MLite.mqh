//+------------------------------------------------------------------+
//|  QQ_MLite.mqh  —  Machine Learning Lite Integration             |
//|  QuantumQueen MicroSafe Pro v6  ·  ML Enhancement Layer         |
//|  7 Adaptive Modules: Persistence · Strategy · Regime ·          |
//|  Session · Volatility · LossStreak · ParameterAdaptation        |
//|  Target: Win Rate 72%→84% | Profit Factor 2.8→4.2              |
//|  Drawdown 8-12%→5-8% | Rating 72/100→90/100                    |
//+------------------------------------------------------------------+
#property strict

//+------------------------------------------------------------------+
//| SECTION 1 – CONSTANTS & HISTORY STRUCT                          |
//+------------------------------------------------------------------+

#define ML_MAX_CYCLES       500
#define ML_STRATEGY_COUNT    12
#define ML_REGIME_COUNT       7
#define ML_SESSION_COUNT      3
#define ML_HOURS_COUNT       24
#define ML_HISTORY_FILE     "QQMLite_CycleHistory.bin"
#define ML_VERSION_TAG      20250508

struct MLCycleRecord
{
   long     cycleId;
   datetime timestamp;
   int      strategyId;      // 1-12
   int      direction;       // +1 LONG, -1 SHORT
   double   entryPrice;
   double   exitPrice;
   double   profitLoss;
   int      durationMin;
   int      regime;          // ENUM_MARKET_REGIME value
   int      session;         // 1=Asia 2=London 3=NY
   int      gridLevels;
   bool     recoveryUsed;
   double   maxDD;
   double   cascadeScore;
   double   mtfScore;
};

// ─── Runtime storage ─────────────────────────────────────────────
MLCycleRecord g_ml_history[];
int           g_ml_count       = 0;
bool          g_ml_dirty       = false;   // needs saving
int           g_ml_saveCounter = 0;       // save every N new cycles

//+------------------------------------------------------------------+
//| SECTION 2 – MODULE 1: HISTORY PERSISTENCE                       |
//+------------------------------------------------------------------+

void MLite_LoadCycleHistory()
{
   ArrayResize(g_ml_history, ML_MAX_CYCLES);
   g_ml_count = 0;

   string path = TerminalInfoString(TERMINAL_DATA_PATH) + "\\MQL5\\Files\\" + ML_HISTORY_FILE;
   int fh = FileOpen(ML_HISTORY_FILE, FILE_READ | FILE_BIN | FILE_COMMON);
   if(fh == INVALID_HANDLE)
   {
      Print("MLite: No history file found — starting fresh");
      return;
   }

   uint tag = (uint)FileReadInteger(fh, 32);
   if(tag != ML_VERSION_TAG)
   {
      FileClose(fh);
      Print("MLite: History file version mismatch — starting fresh");
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
      r.recoveryUsed = (FileReadInteger(fh, 8) != 0);
      r.maxDD        = FileReadDouble(fh);
      r.cascadeScore = FileReadDouble(fh);
      r.mtfScore     = FileReadDouble(fh);
      g_ml_history[i] = r;
      g_ml_count++;
   }

   FileClose(fh);
   Print(StringFormat("MLite: Loaded %d cycles from history", g_ml_count));
}

void MLite_SaveCycleHistory()
{
   int fh = FileOpen(ML_HISTORY_FILE, FILE_WRITE | FILE_BIN | FILE_COMMON);
   if(fh == INVALID_HANDLE)
   {
      Print("MLite: Cannot open history file for writing");
      return;
   }

   FileWriteInteger(fh, ML_VERSION_TAG, 32);
   FileWriteInteger(fh, g_ml_count, 32);

   for(int i = 0; i < g_ml_count; i++)
   {
      MLCycleRecord r = g_ml_history[i];
      FileWriteLong(fh, r.cycleId);
      FileWriteLong(fh, (long)r.timestamp);
      FileWriteInteger(fh, r.strategyId, 32);
      FileWriteInteger(fh, r.direction, 32);
      FileWriteDouble(fh, r.entryPrice);
      FileWriteDouble(fh, r.exitPrice);
      FileWriteDouble(fh, r.profitLoss);
      FileWriteInteger(fh, r.durationMin, 32);
      FileWriteInteger(fh, r.regime, 32);
      FileWriteInteger(fh, r.session, 32);
      FileWriteInteger(fh, r.gridLevels, 32);
      FileWriteInteger(fh, (int)r.recoveryUsed, 8);
      FileWriteDouble(fh, r.maxDD);
      FileWriteDouble(fh, r.cascadeScore);
      FileWriteDouble(fh, r.mtfScore);
   }

   FileClose(fh);
   g_ml_dirty = false;
}

void MLite_AppendCycle(const MLCycleRecord &rec)
{
   if(g_ml_count >= ML_MAX_CYCLES)
   {
      // Shift oldest out (ring buffer)
      for(int i = 0; i < ML_MAX_CYCLES - 1; i++)
         g_ml_history[i] = g_ml_history[i + 1];
      g_ml_count = ML_MAX_CYCLES - 1;
   }
   g_ml_history[g_ml_count] = rec;
   g_ml_count++;
   g_ml_dirty = true;
   g_ml_saveCounter++;

   // Persist every 5 cycles
   if(g_ml_saveCounter >= 5)
   {
      MLite_SaveCycleHistory();
      g_ml_saveCounter = 0;
   }

   // Refresh all derived stats
   MLite_RebuildStats();
}

//+------------------------------------------------------------------+
//| SECTION 3 – MODULE 2: STRATEGY LEARNER                          |
//+------------------------------------------------------------------+

struct MLStrategyStats
{
   int    wins;
   int    losses;
   double totalPnL;
   double avgWin;
   double avgLoss;
   double profitFactor;
   double winRate;       // 0-1
   double riskAdjReturn; // PnL / max loss observed
   double maxLoss;
   double score;         // 0-100
   double momentum;      // positive = improving, negative = declining
   int    sampleCount;
};

MLStrategyStats g_ml_stratStats[ML_STRATEGY_COUNT + 1]; // index 1..12

void MLite_CalculateStrategyStats(const int stratId)
{
   if(stratId < 1 || stratId > ML_STRATEGY_COUNT) return;

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
      if(pnl >= 0)
      {
         s.wins++;
         totalWin += pnl;
      }
      else
      {
         s.losses++;
         totalLoss += MathAbs(pnl);
         if(MathAbs(pnl) > s.maxLoss) s.maxLoss = MathAbs(pnl);
      }
   }

   int total = s.wins + s.losses;
   if(total < 3) { g_ml_stratStats[stratId] = s; return; } // need at least 3 samples

   s.winRate      = (double)s.wins / total;
   s.avgWin       = (s.wins > 0) ? totalWin / s.wins : 0;
   s.avgLoss      = (s.losses > 0) ? totalLoss / s.losses : 0.01;
   s.profitFactor = (totalLoss > 0) ? totalWin / totalLoss : MathMax(1.0, totalWin);
   s.riskAdjReturn = s.totalPnL / MathMax(s.maxLoss, 0.01);

   // Composite score: 40% winRate + 35% profitFactor (normalised) + 25% risk-adj
   double wrScore   = s.winRate * 100.0 * 0.40;
   double pfNorm    = MathMin(100.0, (s.profitFactor - 1.0) * 20.0); // PF 1→5 maps to 0→80
   double pfScore   = pfNorm * 0.35;
   double raScore   = MathMin(25.0, MathMax(0, s.riskAdjReturn * 2.5)) * 0.25;
   s.score = MathMin(100.0, wrScore + pfScore + raScore);

   // Momentum: compare last 20 vs last 50 cycles for this strategy
   double pnl20 = 0, pnl50 = 0;
   int n20 = 0, n50 = 0;
   for(int i = g_ml_count - 1; i >= 0 && n50 < 50; i--)
   {
      if(g_ml_history[i].strategyId != stratId) continue;
      n50++;
      pnl50 += g_ml_history[i].profitLoss;
      if(n20 < 20) { n20++; pnl20 += g_ml_history[i].profitLoss; }
   }
   double avg20 = (n20 > 0) ? pnl20 / n20 : 0;
   double avg50 = (n50 > 0) ? pnl50 / n50 : 0;
   s.momentum = avg20 - avg50; // positive = recent cycles better than average

   g_ml_stratStats[stratId] = s;
}

double MLite_GetStrategyScore(const int stratId)
{
   if(stratId < 1 || stratId > ML_STRATEGY_COUNT) return 50.0;
   if(g_ml_stratStats[stratId].sampleCount < 3)   return 50.0; // neutral if no data
   return g_ml_stratStats[stratId].score;
}

bool MLite_IsStrategyActive(const int stratId)
{
   if(stratId < 1 || stratId > ML_STRATEGY_COUNT) return true; // allow if unknown
   MLStrategyStats &s = g_ml_stratStats[stratId];
   if(s.sampleCount < 5) return true; // too few data - don't block
   return (s.winRate >= 0.35 && s.profitFactor >= 0.80 && s.momentum >= -5.0);
}

//+------------------------------------------------------------------+
//| SECTION 4 – MODULE 3: REGIME ADAPTATION                         |
//+------------------------------------------------------------------+

struct MLRegimeCell
{
   int    wins;
   int    losses;
   double totalPnL;
   double profitFactor;
   double winRate;
};

// [strategyId 0..11][regime 0..6]
MLRegimeCell g_ml_regimeMatrix[ML_STRATEGY_COUNT][ML_REGIME_COUNT];

void MLite_CalculateRegimeStats()
{
   // Reset
   for(int s = 0; s < ML_STRATEGY_COUNT; s++)
      for(int r = 0; r < ML_REGIME_COUNT; r++)
      {
         g_ml_regimeMatrix[s][r].wins = 0;
         g_ml_regimeMatrix[s][r].losses = 0;
         g_ml_regimeMatrix[s][r].totalPnL = 0;
         g_ml_regimeMatrix[s][r].profitFactor = 1.0;
         g_ml_regimeMatrix[s][r].winRate = 0.5;
      }

   // Use last 100 cycles
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
         MLRegimeCell &c = g_ml_regimeMatrix[s][r];
         int total = c.wins + c.losses;
         if(total < 2) { c.winRate = 0.5; c.profitFactor = 1.0; continue; }
         c.winRate = (double)c.wins / total;
         double totalLoss = c.losses * 1.0; // approximation
         c.profitFactor = (totalLoss > 0) ? (c.wins * 1.0) / totalLoss : MathMax(1.0, c.wins);
      }
}

// Returns score multiplier 0.85-1.15
double MLite_AdjustScoreByRegime(const int stratId, const int regime, const double baseScore)
{
   int sIdx = stratId - 1;
   int rIdx = regime;
   if(sIdx < 0 || sIdx >= ML_STRATEGY_COUNT) return baseScore;
   if(rIdx < 0 || rIdx >= ML_REGIME_COUNT)   return baseScore;

   MLRegimeCell &c = g_ml_regimeMatrix[sIdx][rIdx];
   int total = c.wins + c.losses;
   if(total < 3) return baseScore; // not enough data

   // Modulate ±15% based on win rate vs expected 50%
   double adjustment = (c.winRate - 0.50) * 0.30; // ±15% max
   adjustment = MathMax(-0.15, MathMin(0.15, adjustment));
   return baseScore * (1.0 + adjustment);
}

bool MLite_IsRegimeOptimalForStrategy(const int stratId, const int regime)
{
   int sIdx = stratId - 1;
   int rIdx = regime;
   if(sIdx < 0 || sIdx >= ML_STRATEGY_COUNT || rIdx < 0 || rIdx >= ML_REGIME_COUNT)
      return true;
   MLRegimeCell &c = g_ml_regimeMatrix[sIdx][rIdx];
   int total = c.wins + c.losses;
   if(total < 5) return true;
   return (c.winRate >= 0.40 && c.profitFactor >= 0.75);
}

//+------------------------------------------------------------------+
//| SECTION 5 – MODULE 4: SESSION OPTIMIZER                         |
//+------------------------------------------------------------------+

struct MLSessionCell
{
   int    wins;
   int    losses;
   double totalPnL;
   double winRate;
   double avgATR; // accumulated for normalisation
   int    atrCount;
};

// [session 0..2][hour 0..23]
MLSessionCell g_ml_sessionMatrix[ML_SESSION_COUNT][ML_HOURS_COUNT];

void MLite_CalculateSessionStats()
{
   for(int s = 0; s < ML_SESSION_COUNT; s++)
      for(int h = 0; h < ML_HOURS_COUNT; h++)
      {
         g_ml_sessionMatrix[s][h].wins = 0;
         g_ml_sessionMatrix[s][h].losses = 0;
         g_ml_sessionMatrix[s][h].totalPnL = 0;
         g_ml_sessionMatrix[s][h].winRate = 0.5;
         g_ml_sessionMatrix[s][h].avgATR = 0;
         g_ml_sessionMatrix[s][h].atrCount = 0;
      }

   // Use last 200 cycles
   int start = MathMax(0, g_ml_count - 200);
   for(int i = start; i < g_ml_count; i++)
   {
      int sIdx = g_ml_history[i].session - 1;
      if(sIdx < 0 || sIdx >= ML_SESSION_COUNT) continue;
      int hour = TimeHour(g_ml_history[i].timestamp);
      if(hour < 0 || hour >= ML_HOURS_COUNT) continue;

      MLSessionCell &c = g_ml_sessionMatrix[sIdx][hour];
      double pnl = g_ml_history[i].profitLoss;
      c.totalPnL += pnl;
      if(pnl >= 0) c.wins++;
      else          c.losses++;
      c.atrCount++;
   }

   for(int s = 0; s < ML_SESSION_COUNT; s++)
      for(int h = 0; h < ML_HOURS_COUNT; h++)
      {
         MLSessionCell &c = g_ml_sessionMatrix[s][h];
         int total = c.wins + c.losses;
         c.winRate = (total >= 2) ? (double)c.wins / total : 0.5;
      }
}

// Returns lot multiplier 0.80-1.20
double MLite_AdjustLotBySession(const double baseLot, const int session)
{
   if(session < 1 || session > ML_SESSION_COUNT) return baseLot;
   int sIdx = session - 1;

   // Aggregate win rate across hours for this session
   double totalWR = 0;
   int cells = 0;
   for(int h = 0; h < ML_HOURS_COUNT; h++)
   {
      MLSessionCell &c = g_ml_sessionMatrix[sIdx][h];
      if(c.wins + c.losses < 2) continue;
      totalWR += c.winRate;
      cells++;
   }
   if(cells == 0) return baseLot;

   double sessionWR = totalWR / cells;
   // Win rate 0.3→0.7 maps to lot multiplier 0.80→1.20
   double mult = 0.80 + (sessionWR - 0.30) * (0.40 / 0.40);
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
      MLSessionCell &c = g_ml_sessionMatrix[sIdx][h];
      if(c.wins + c.losses >= 2) { totalWR += c.winRate; cells++; }
   }
   return (cells > 0) ? totalWR / cells : 0.5;
}

//+------------------------------------------------------------------+
//| SECTION 6 – MODULE 5: VOLATILITY PREDICTOR                      |
//+------------------------------------------------------------------+

int    g_ml_volPrediction    = 0;     // 1=rising -1=falling 0=stable
double g_ml_volConfidence    = 50.0;  // 0-100

void MLite_UpdateVolatilityPrediction()
{
   // Use ATR(M5) slope over last 50 bars
   int periods = 50;
   double atrArr[];
   ArraySetAsSeries(atrArr, true);
   int atrHandle = iATR(_Symbol, PERIOD_M5, 14);
   if(atrHandle == INVALID_HANDLE) { g_ml_volPrediction = 0; return; }
   if(CopyBuffer(atrHandle, 0, 0, periods, atrArr) < periods)
   { IndicatorRelease(atrHandle); g_ml_volPrediction = 0; return; }
   IndicatorRelease(atrHandle);

   // Linear regression slope via simple least-squares
   double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;
   int n = periods;
   for(int i = 0; i < n; i++)
   {
      sumX  += i;
      sumY  += atrArr[n - 1 - i];  // oldest first
      sumXY += i * atrArr[n - 1 - i];
      sumX2 += i * i;
   }
   double denom = n * sumX2 - sumX * sumX;
   if(MathAbs(denom) < 1e-10) { g_ml_volPrediction = 0; g_ml_volConfidence = 50; return; }
   double slope = (n * sumXY - sumX * sumY) / denom;

   // Normalise slope against mean ATR
   double meanATR = sumY / n;
   double relSlope = (meanATR > 0) ? slope / meanATR : 0;

   if(relSlope > 0.004)       { g_ml_volPrediction = 1;  g_ml_volConfidence = MathMin(95.0, 50 + relSlope * 5000); }
   else if(relSlope < -0.004) { g_ml_volPrediction = -1; g_ml_volConfidence = MathMin(95.0, 50 + MathAbs(relSlope) * 5000); }
   else                        { g_ml_volPrediction = 0;  g_ml_volConfidence = 50; }
}

// Returns lot multiplier: rising vol → reduce; falling vol → increase slightly
double MLite_AdjustLotForVolatility(const double baseLot)
{
   if(g_ml_volPrediction == 1)  return baseLot * 0.80;  // -20% if vol rising
   if(g_ml_volPrediction == -1) return baseLot * 1.10;  // +10% if vol falling
   return baseLot;
}

//+------------------------------------------------------------------+
//| SECTION 7 – MODULE 6: LOSS STREAK MANAGER                       |
//+------------------------------------------------------------------+

int    g_ml_currentStreak      = 0; // positive = win streak, negative = loss streak
double g_ml_streakLotMultiplier = 1.0;
bool   g_ml_tradingBlocked     = false;
datetime g_ml_blockUntil       = 0;

void MLite_UpdateStreak()
{
   if(g_ml_count == 0) { g_ml_currentStreak = 0; return; }

   // Scan backwards for consecutive same-sign PnL
   double lastPnL = g_ml_history[g_ml_count - 1].profitLoss;
   bool isLoss = (lastPnL < 0);
   g_ml_currentStreak = isLoss ? -1 : 1;

   for(int i = g_ml_count - 2; i >= 0; i--)
   {
      bool thisLoss = (g_ml_history[i].profitLoss < 0);
      if(thisLoss == isLoss)
         g_ml_currentStreak += (isLoss ? -1 : 1);
      else
         break;
   }

   int lossLen = (g_ml_currentStreak < 0) ? MathAbs(g_ml_currentStreak) : 0;

   // Lot penalty table: 0→1.0, 1→0.85, 2→0.70, 3→0.55, 4+→0.40
   double penalties[] = {1.0, 0.85, 0.70, 0.55, 0.40};
   int idx = MathMin(lossLen, 4);
   g_ml_streakLotMultiplier = penalties[idx];

   // Block trading after 4+ consecutive losses
   if(lossLen >= 4)
   {
      g_ml_tradingBlocked = true;
      // Wait time: 30 min per loss beyond 3, max 120 min
      int waitMin = MathMin(120, (lossLen - 3) * 30);
      g_ml_blockUntil = TimeCurrent() + waitMin * 60;
      Print(StringFormat("MLite: Trading blocked for %d minutes after %d consecutive losses", waitMin, lossLen));
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
      Print("MLite: Trading block lifted after cooldown");
      return false;
   }
   return true;
}

double MLite_GetStreakLotMultiplier()
{
   return g_ml_streakLotMultiplier;
}

int MLite_GetLossStreakLength()
{
   return (g_ml_currentStreak < 0) ? MathAbs(g_ml_currentStreak) : 0;
}

//+------------------------------------------------------------------+
//| SECTION 8 – MODULE 7: PARAMETER ADAPTATION                      |
//+------------------------------------------------------------------+

struct MLAdaptiveParams
{
   double gridSpacingMult;    // 0.75 – 1.25
   double targetPctMult;      // 0.85 – 1.20
   double recoveryLotMult;    // 0.70 – 1.30
   int    minEntryScoreAdj;   // additive adjustment to InpMinEntryScore: -1 to +3
};

MLAdaptiveParams g_ml_params;

void MLite_UpdateAdaptiveParams()
{
   // Defaults
   g_ml_params.gridSpacingMult   = 1.0;
   g_ml_params.targetPctMult     = 1.0;
   g_ml_params.recoveryLotMult   = 1.0;
   g_ml_params.minEntryScoreAdj  = 0;

   if(g_ml_count < 5) return; // need some data

   // --- Grid spacing adaptation ---
   // Wider spacing in high-vol or loss streak; tighter in calm winning periods
   int lossLen = MLite_GetLossStreakLength();
   if(g_ml_volPrediction == 1)           g_ml_params.gridSpacingMult += 0.15; // rising vol → wider
   if(g_ml_volPrediction == -1)          g_ml_params.gridSpacingMult -= 0.10; // falling vol → tighter
   if(lossLen >= 2)                       g_ml_params.gridSpacingMult += lossLen * 0.05; // streak → wider
   g_ml_params.gridSpacingMult = MathMax(0.75, MathMin(1.25, g_ml_params.gridSpacingMult));

   // --- Target percent adaptation ---
   // Better recent win rate → allow slightly higher target
   double recentWR = MLite_RecentWinRate(30);
   if(recentWR >= 0.75)      g_ml_params.targetPctMult = 1.15;
   else if(recentWR >= 0.65) g_ml_params.targetPctMult = 1.05;
   else if(recentWR < 0.45)  g_ml_params.targetPctMult = 0.90;
   else if(recentWR < 0.35)  g_ml_params.targetPctMult = 0.85;

   // --- Recovery lot adaptation ---
   // Based on historical recovery success rate
   double recSuccess = MLite_RecoverySuccessRate();
   if(recSuccess >= 0.70)      g_ml_params.recoveryLotMult = 1.20;
   else if(recSuccess >= 0.55) g_ml_params.recoveryLotMult = 1.05;
   else if(recSuccess < 0.40)  g_ml_params.recoveryLotMult = 0.85;
   else if(recSuccess < 0.30)  g_ml_params.recoveryLotMult = 0.70;

   // --- Min entry score adjustment ---
   if(lossLen >= 3)         g_ml_params.minEntryScoreAdj = 2;  // raise bar after losses
   else if(lossLen >= 2)    g_ml_params.minEntryScoreAdj = 1;
   else if(recentWR >= 0.78) g_ml_params.minEntryScoreAdj = -1; // lower bar in hot streak
}

// Helper: win rate over last N cycles
double MLite_RecentWinRate(const int n)
{
   if(g_ml_count == 0) return 0.5;
   int start = MathMax(0, g_ml_count - n);
   int wins = 0, total = 0;
   for(int i = start; i < g_ml_count; i++)
   {
      total++;
      if(g_ml_history[i].profitLoss >= 0) wins++;
   }
   return (total > 0) ? (double)wins / total : 0.5;
}

// Helper: success rate of cycles where recoveryUsed == true
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

// Public accessors for main bot
double MLite_GetAdaptiveGridMult()       { return g_ml_params.gridSpacingMult; }
double MLite_GetAdaptiveTargetMult()     { return g_ml_params.targetPctMult; }
double MLite_GetAdaptiveRecoveryMult()   { return g_ml_params.recoveryLotMult; }
int    MLite_GetAdaptiveMinScoreAdj()    { return g_ml_params.minEntryScoreAdj; }

//+------------------------------------------------------------------+
//| SECTION 9 – COMBINED SCORE: STRATEGY + REGIME BOOST             |
//+------------------------------------------------------------------+

// Call this from QQSelectMatrixStrategy() to get ML-adjusted score boost
// Returns additive boost to apply to s.score (can be negative)
double MLite_GetEntryScoreBoost(const int stratId, const int regime)
{
   if(g_ml_count < 10) return 0.0; // not enough data to influence

   double baseStratScore = MLite_GetStrategyScore(stratId); // 0-100
   double neutralised = baseStratScore - 50.0; // centre at 0
   double boost = neutralised * 0.04; // ±2.0 points to entry score

   // Regime layer
   double regimeAdj = 0.0;
   int sIdx = stratId - 1;
   int rIdx = regime;
   if(sIdx >= 0 && sIdx < ML_STRATEGY_COUNT && rIdx >= 0 && rIdx < ML_REGIME_COUNT)
   {
      MLRegimeCell &c = g_ml_regimeMatrix[sIdx][rIdx];
      if(c.wins + c.losses >= 3)
         regimeAdj = (c.winRate - 0.50) * 2.0; // ±1.0 point
   }

   // Momentum layer
   double momentum = (stratId >= 1 && stratId <= ML_STRATEGY_COUNT)
                     ? g_ml_stratStats[stratId].momentum : 0;
   double momBoost = MathMax(-0.5, MathMin(0.5, momentum * 0.05));

   double total = boost + regimeAdj + momBoost;
   return MathMax(-3.0, MathMin(3.0, total)); // cap influence
}

// Lot multiplier combining all ML factors (call from CalculateDynamicLot)
double MLite_GetCompositeLotMultiplier(const double baseLot, const int session)
{
   double mult = 1.0;

   // Session factor
   double sessionAdj = MLite_AdjustLotBySession(1.0, session);
   mult *= sessionAdj;

   // Volatility factor
   double volAdj = MLite_AdjustLotForVolatility(1.0);
   mult *= volAdj;

   // Loss streak factor
   mult *= g_ml_streakLotMultiplier;

   // Clamp to safe range
   mult = MathMax(0.40, MathMin(1.30, mult));
   return baseLot * mult;
}

//+------------------------------------------------------------------+
//| SECTION 10 – MASTER INIT, REBUILD & RECORD                      |
//+------------------------------------------------------------------+

void MLite_Initialize()
{
   MLite_LoadCycleHistory();
   MLite_RebuildStats();
   MLite_UpdateVolatilityPrediction();
   Print(StringFormat("MLite: Initialized. Cycles=%d | Recent WR=%.1f%% | StreakLen=%d",
         g_ml_count,
         MLite_RecentWinRate(30) * 100.0,
         MLite_GetLossStreakLength()));
}

void MLite_RebuildStats()
{
   for(int i = 1; i <= ML_STRATEGY_COUNT; i++)
      MLite_CalculateStrategyStats(i);
   MLite_CalculateRegimeStats();
   MLite_CalculateSessionStats();
   MLite_UpdateStreak();
   MLite_UpdateAdaptiveParams();
}

// Call this from CloseBasket(), before ResetBasket()
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

   Print(StringFormat("MLite: Cycle recorded — S%02d | Dir=%+d | PnL=%.2f | Regime=%d | WR=%.1f%%",
         r.strategyId, r.direction, r.profitLoss,
         r.regime, MLite_RecentWinRate(20) * 100.0));
}

// Call on OnTimer() or OnTick() periodically — refreshes vol prediction
void MLite_Tick()
{
   static datetime lastVolUpdate = 0;
   if(TimeCurrent() - lastVolUpdate >= 3600) // update every hour
   {
      MLite_UpdateVolatilityPrediction();
      MLite_UpdateAdaptiveParams();
      lastVolUpdate = TimeCurrent();
   }

   // Release block if cooldown expired
   MLite_IsTradingBlocked(); // side-effect: clears block if time passed
}

// Deinit: flush pending saves
void MLite_Deinit()
{
   if(g_ml_dirty) MLite_SaveCycleHistory();
   Print(StringFormat("MLite: Deinit complete. %d cycles saved.", g_ml_count));
}

// Panel info string for dashboard
string MLite_GetStatusLine()
{
   return StringFormat(
      "ML| Cycles:%d WR:%.0f%% PF:%.2f Streak:%+d Vol:%+d Score_Adj:%+d",
      g_ml_count,
      MLite_RecentWinRate(50) * 100.0,
      MLite_OverallProfitFactor(),
      g_ml_currentStreak,
      g_ml_volPrediction,
      g_ml_params.minEntryScoreAdj);
}

double MLite_OverallProfitFactor()
{
   double grossWin = 0, grossLoss = 0;
   int start = MathMax(0, g_ml_count - 100);
   for(int i = start; i < g_ml_count; i++)
   {
      if(g_ml_history[i].profitLoss >= 0) grossWin  += g_ml_history[i].profitLoss;
      else                                grossLoss  += MathAbs(g_ml_history[i].profitLoss);
   }
   return (grossLoss > 0) ? grossWin / grossLoss : MathMax(1.0, grossWin);
}
//+------------------------------------------------------------------+
// END OF QQ_MLite.mqh
//+------------------------------------------------------------------+
