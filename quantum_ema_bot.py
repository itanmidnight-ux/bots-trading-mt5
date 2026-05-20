#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
╔══════════════════════════════════════════════════════════════════════════╗
║          QUANTUM EMA BOT v3.0 — Professional Algorithmic Trading        ║
║                                                                          ║
║   Strategy  : EMA 9/26 Crossover + 1-Candle Confirmation               ║
║   SL/TP     : Quantum Smart Stop (ATR-based, adaptive trailing)         ║
║   Markets   : Forex · Indices · Crypto · Commodities                    ║
║   Leverage  : 1:500 — 1:1000 (small accounts optimized)                ║
║   Platform  : MetaTrader 5                                               ║
║                                                                          ║
║   RISK WARNING: Trading involves substantial risk of loss.               ║
║   Only trade with capital you can afford to lose.                        ║
╚══════════════════════════════════════════════════════════════════════════╝
"""

import MetaTrader5 as mt5
import pandas as pd
import numpy as np
from datetime import datetime, timedelta
import time
import logging
import os
import json
import sys
from dataclasses import dataclass, field
from typing import Optional, Dict, List, Tuple
from enum import Enum


# ╔══════════════════════════════════════════════════════════════════════════╗
# ║                          CONFIGURATION                                  ║
# ╚══════════════════════════════════════════════════════════════════════════╝

class Signal(Enum):
    BUY  = "BUY"
    SELL = "SELL"
    NONE = "NONE"


@dataclass
class BotConfig:
    # ─── Account Credentials ────────────────────────────────────────────────
    login:    int = 0       # Your MT5 account number
    password: str = ""      # Your MT5 password
    server:   str = ""      # Broker server (e.g. "ICMarkets-Live01")

    # ─── Trading Symbols ────────────────────────────────────────────────────
    symbols: List[str] = field(default_factory=lambda: [
        "EURUSD", "GBPUSD", "USDJPY", "AUDUSD",   # Forex majors
        "XAUUSD",                                    # Gold
        "BTCUSD", "ETHUSD",                         # Crypto
        "US30", "NAS100",                            # Indices
    ])

    # ─── EMA Strategy ───────────────────────────────────────────────────────
    ema_fast:  int = 9
    ema_slow:  int = 26
    timeframe: int = mt5.TIMEFRAME_H1  # Recommended: H1 or H4

    # ─── Risk Management ────────────────────────────────────────────────────
    risk_per_trade:       float = 0.01   # 1 % of balance per trade
    max_daily_loss_pct:   float = 0.05   # Stop trading after 5 % daily drawdown
    max_concurrent_trades: int  = 3      # Never open more than 3 at once
    max_spread_pips:      float = 3.0    # Skip if spread is too wide

    # ─── Quantum Smart Stop Settings ────────────────────────────────────────
    atr_period:               int   = 14   # ATR lookback
    atr_sl_multiplier:        float = 1.5  # SL distance = 1.5 × ATR
    min_rr_ratio:             float = 2.0  # Minimum reward : risk (1 : 2)
    min_candles_before_trail: int   = 3    # Never touch SL before 3 candles
    breakeven_rr_trigger:     float = 0.5  # Move to breakeven at 0.5 RR
    trail_activation_rr:      float = 1.0  # Start trailing at 1 : 1 RR
    trail_step_atr_mult:      float = 0.3  # Trail step = 0.3 × ATR
    profit_lock_rr:           float = 2.0  # Lock 1:1 profit at 2:1 RR
    max_rr_target:            float = 5.0  # Max TP extension (5 : 1)

    # ─── Execution Safety ───────────────────────────────────────────────────
    magic_number: int = 20250520
    slippage:     int = 3


# ╔══════════════════════════════════════════════════════════════════════════╗
# ║                         LOGGING ENGINE                                  ║
# ╚══════════════════════════════════════════════════════════════════════════╝

def setup_logger(name: str = "QuantumEMA") -> logging.Logger:
    os.makedirs("logs", exist_ok=True)
    date_str = datetime.now().strftime("%Y%m%d")
    log_file = f"logs/quantum_ema_{date_str}.log"

    fmt = logging.Formatter(
        "%(asctime)s │ %(levelname)-8s │ %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S"
    )

    logger = logging.getLogger(name)
    logger.setLevel(logging.DEBUG)
    logger.handlers.clear()

    fh = logging.FileHandler(log_file, encoding="utf-8")
    fh.setLevel(logging.DEBUG)
    fh.setFormatter(fmt)
    logger.addHandler(fh)

    ch = logging.StreamHandler(sys.stdout)
    ch.setLevel(logging.INFO)
    ch.setFormatter(fmt)
    logger.addHandler(ch)

    return logger


log = setup_logger()


# ╔══════════════════════════════════════════════════════════════════════════╗
# ║                       INDICATOR ENGINE                                  ║
# ╚══════════════════════════════════════════════════════════════════════════╝

class Indicators:
    """Pure, vectorised indicator calculations."""

    @staticmethod
    def ema(series: pd.Series, period: int) -> pd.Series:
        return series.ewm(span=period, adjust=False).mean()

    @staticmethod
    def atr(df: pd.DataFrame, period: int = 14) -> pd.Series:
        h, l, c = df["high"], df["low"], df["close"]
        prev_c = c.shift(1)
        tr = pd.concat(
            [h - l, (h - prev_c).abs(), (l - prev_c).abs()], axis=1
        ).max(axis=1)
        return tr.ewm(span=period, adjust=False).mean()

    @staticmethod
    def get_crossover_signal(df: pd.DataFrame,
                              fast: int = 9,
                              slow: int = 26) -> Tuple[Signal, pd.Timestamp]:
        """
        Detect EMA crossover on the LAST CONFIRMED (closed) candle.

        Returns (Signal, crossover_bar_timestamp).
        Only fires once per candle (idempotent for same bar_time).
        """
        ema_f = Indicators.ema(df["close"], fast)
        ema_s = Indicators.ema(df["close"], slow)

        # Index -1 = forming candle (excluded)
        # Index -2 = last confirmed candle  ← crossover detection
        # Index -3 = candle before that      ← previous state

        f_prev = ema_f.iloc[-3]
        s_prev = ema_s.iloc[-3]
        f_curr = ema_f.iloc[-2]
        s_curr = ema_s.iloc[-2]
        bar_ts = df.index[-2]

        if f_prev <= s_prev and f_curr > s_curr:
            return Signal.BUY, bar_ts

        if f_prev >= s_prev and f_curr < s_curr:
            return Signal.SELL, bar_ts

        return Signal.NONE, bar_ts


# ╔══════════════════════════════════════════════════════════════════════════╗
# ║                      RISK MANAGER                                       ║
# ╚══════════════════════════════════════════════════════════════════════════╝

class RiskManager:
    def __init__(self, cfg: BotConfig):
        self.cfg = cfg
        self._reset_date: datetime.date = datetime.now().date()
        self._daily_realised_loss: float = 0.0

    # ── Daily loss tracking ─────────────────────────────────────────────────
    def _check_date_rollover(self):
        today = datetime.now().date()
        if today != self._reset_date:
            self._daily_realised_loss = 0.0
            self._reset_date = today
            log.info("📅 Daily PnL counter reset.")

    def record_closed_trade_profit(self, profit: float):
        self._check_date_rollover()
        if profit < 0:
            self._daily_realised_loss += abs(profit)

    def is_daily_kill_switch_active(self) -> bool:
        self._check_date_rollover()
        acc = mt5.account_info()
        if not acc:
            return True
        threshold = acc.balance * self.cfg.max_daily_loss_pct
        if self._daily_realised_loss >= threshold:
            log.critical(
                f"🚨 DAILY KILL SWITCH ACTIVE │ Loss={self._daily_realised_loss:.2f} ≥ "
                f"Threshold={threshold:.2f}"
            )
            return True
        return False

    # ── Spread filter ───────────────────────────────────────────────────────
    def is_spread_acceptable(self, symbol: str) -> bool:
        tick = mt5.symbol_info_tick(symbol)
        info = mt5.symbol_info(symbol)
        if not tick or not info:
            return False
        pip = info.point * (10 if info.digits in (3, 5) else 1)
        spread_pips = (tick.ask - tick.bid) / pip
        if spread_pips > self.cfg.max_spread_pips:
            log.warning(f"⚠️  Spread too wide │ {symbol} │ {spread_pips:.1f} pips")
            return False
        return True

    # ── Lot size calculator ─────────────────────────────────────────────────
    def compute_lot(self, symbol: str, sl_distance: float) -> float:
        """
        Risk-based position sizing:
            Lot = (Balance × RiskPct) / (SL_distance_in_money_per_lot)
        """
        acc  = mt5.account_info()
        info = mt5.symbol_info(symbol)
        if not acc or not info or sl_distance <= 0:
            return info.volume_min if info else 0.01

        risk_money = acc.balance * self.cfg.risk_per_trade

        tick_value = info.trade_tick_value   # money per tick per 1 lot
        tick_size  = info.trade_tick_size    # price movement per tick

        if tick_size <= 0 or tick_value <= 0:
            return info.volume_min

        # money at risk per lot for this SL distance
        loss_per_lot = (sl_distance / tick_size) * tick_value

        if loss_per_lot <= 0:
            return info.volume_min

        raw_lot  = risk_money / loss_per_lot
        step     = info.volume_step
        raw_lot  = round(raw_lot / step) * step          # snap to step grid
        lot      = max(info.volume_min, min(raw_lot, info.volume_max))
        lot      = round(lot, 2)

        log.debug(
            f"💰 Lot │ {symbol} │ risk={risk_money:.2f} │ SL_dist={sl_distance:.5f} │ "
            f"loss/lot={loss_per_lot:.2f} │ → {lot}"
        )
        return lot

    # ── Margin level guard ──────────────────────────────────────────────────
    @staticmethod
    def margin_level_ok(threshold: float = 150.0) -> bool:
        acc = mt5.account_info()
        if not acc:
            return False
        if acc.margin == 0:
            return True                # No positions open
        ml = acc.margin_level
        if ml < threshold:
            log.critical(f"🚨 MARGIN LEVEL DANGER │ {ml:.1f}% < {threshold}%!")
            return False
        return True


# ╔══════════════════════════════════════════════════════════════════════════╗
# ║               QUANTUM SMART STOP — Adaptive SL/TP Engine               ║
# ║                                                                          ║
# ║  Phases:                                                                 ║
# ║    0. Entry → Fixed ATR stop, minimum 3 candles protection              ║
# ║    1. After 3 candles + 0.5 RR → move to break-even                    ║
# ║    2. At 1:1 RR → activate dynamic trailing stop                        ║
# ║    3. At 2:1 RR → lock in 1:1 profit permanently                       ║
# ║    4. Trailing follows highest point; step = 0.3 × ATR                  ║
# ╚══════════════════════════════════════════════════════════════════════════╝

@dataclass
class TradeState:
    ticket:        int
    symbol:        str
    direction:     Signal
    entry:         float
    initial_sl:    float
    current_sl:    float
    tp:            float
    candles_open:  int   = 0
    last_bar_time: Optional[pd.Timestamp] = None
    peak_price:    float = 0.0   # Highest (BUY) or lowest (SELL) price seen
    phase:         int   = 0     # 0=initial, 1=breakeven, 2=trailing, 3=locked


class QuantumSmartStop:
    """
    Quantum Smart Stop — inspired by Quantum Queen Bot adaptive exit logic.

    Key rules:
    - NEVER modify SL before 3 confirmed candles have closed.
    - NEVER move SL against the trade direction (no widening).
    - Break-even after 3 candles if floating ≥ 0.5 R.
    - Trailing starts at 1 R — follows peak with ATR-based step.
    - Profit lock at 2 R — SL cemented at +1 R (guaranteed win).
    """

    def __init__(self, cfg: BotConfig):
        self.cfg    = cfg
        self.states: Dict[int, TradeState] = {}

    def register(self, ticket: int, symbol: str, direction: Signal,
                 entry: float, sl: float, tp: float):
        self.states[ticket] = TradeState(
            ticket=ticket, symbol=symbol, direction=direction,
            entry=entry, initial_sl=sl, current_sl=sl, tp=tp,
            peak_price=entry
        )
        log.info(
            f"⚙️  SmartStop registered │ #{ticket} {direction.value} {symbol} │ "
            f"Entry={entry:.5f} SL={sl:.5f} TP={tp:.5f}"
        )

    def update(self, ticket: int, df: pd.DataFrame) -> Optional[float]:
        """
        Called every bot cycle for each open position.
        Returns the new SL price to set, or None if no change needed.
        """
        st = self.states.get(ticket)
        if st is None:
            return None

        info = mt5.symbol_info(st.symbol)
        tick = mt5.symbol_info_tick(st.symbol)
        if not info or not tick:
            return None

        # ── Count confirmed candles ─────────────────────────────────────────
        bar_ts = df.index[-2]
        if st.last_bar_time != bar_ts:
            st.candles_open  += 1
            st.last_bar_time  = bar_ts
            log.debug(f"   #{ticket} candle #{st.candles_open} confirmed")

        # ── Current price & ATR ─────────────────────────────────────────────
        cur_price = tick.bid if st.direction == Signal.BUY else tick.ask
        atr       = Indicators.atr(df, self.cfg.atr_period).iloc[-2]

        # ── Track peak (best price reached) ────────────────────────────────
        if st.direction == Signal.BUY:
            st.peak_price = max(st.peak_price, cur_price)
        else:
            if st.peak_price == st.entry:          # init for SELL
                st.peak_price = cur_price
            st.peak_price = min(st.peak_price, cur_price)

        # ── Current R-multiple ──────────────────────────────────────────────
        initial_risk = abs(st.entry - st.initial_sl)
        if initial_risk <= 0:
            return None

        if st.direction == Signal.BUY:
            floating_profit = cur_price - st.entry
        else:
            floating_profit = st.entry - cur_price

        r_now = floating_profit / initial_risk

        # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        # PHASE 0 → 1: Break-even guard (min 3 candles + 0.5 R)
        # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        new_sl: Optional[float] = None

        if (st.phase == 0
                and st.candles_open >= self.cfg.min_candles_before_trail
                and r_now >= self.cfg.breakeven_rr_trigger):

            buffer = info.point * 2        # 2 points above entry
            if st.direction == Signal.BUY:
                candidate = st.entry + buffer
                if candidate > st.current_sl:
                    new_sl   = candidate
                    st.phase = 1
                    log.info(f"   #{ticket} → Phase 1 │ Break-even SL={new_sl:.5f} │ R={r_now:.2f}")
            else:
                candidate = st.entry - buffer
                if candidate < st.current_sl:
                    new_sl   = candidate
                    st.phase = 1
                    log.info(f"   #{ticket} → Phase 1 │ Break-even SL={new_sl:.5f} │ R={r_now:.2f}")

        # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        # PHASE 1 → 2: Activate trailing at 1:1 R
        # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        if st.phase >= 1 and r_now >= self.cfg.trail_activation_rr:
            if st.phase == 1:
                st.phase = 2
                log.info(f"   #{ticket} → Phase 2 │ Trailing activated │ R={r_now:.2f}")

        # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        # PHASE 2: Dynamic trailing stop following peak price
        # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        if st.phase == 2:
            trail_dist  = atr * self.cfg.atr_sl_multiplier
            step        = atr * self.cfg.trail_step_atr_mult

            if st.direction == Signal.BUY:
                trail_sl = st.peak_price - trail_dist
                if trail_sl > st.current_sl + step:
                    new_sl = trail_sl
                    log.info(
                        f"   #{ticket} Trailing ↑ │ peak={st.peak_price:.5f} │ "
                        f"new_SL={trail_sl:.5f} │ R={r_now:.2f}"
                    )
            else:
                trail_sl = st.peak_price + trail_dist
                if trail_sl < st.current_sl - step:
                    new_sl = trail_sl
                    log.info(
                        f"   #{ticket} Trailing ↓ │ peak={st.peak_price:.5f} │ "
                        f"new_SL={trail_sl:.5f} │ R={r_now:.2f}"
                    )

        # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        # PHASE 3: Profit lock at 2:1 R — SL ≥ entry + 1 R
        # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        if st.phase >= 2 and r_now >= self.cfg.profit_lock_rr and st.phase < 3:
            st.phase = 3
            if st.direction == Signal.BUY:
                lock_sl = st.entry + initial_risk  # +1 R guaranteed
                if lock_sl > st.current_sl:
                    new_sl = lock_sl
            else:
                lock_sl = st.entry - initial_risk
                if lock_sl < st.current_sl:
                    new_sl = lock_sl

            log.info(
                f"   #{ticket} → Phase 3 │ PROFIT LOCKED │ lock_SL={new_sl:.5f} │ R={r_now:.2f}"
            )

        # ── Apply new SL ────────────────────────────────────────────────────
        if new_sl is not None:
            new_sl = round(new_sl, info.digits)
            st.current_sl = new_sl

        return new_sl

    def remove(self, ticket: int):
        if ticket in self.states:
            del self.states[ticket]
            log.debug(f"   SmartStop │ state removed for #{ticket}")


# ╔══════════════════════════════════════════════════════════════════════════╗
# ║                       ORDER MANAGER                                     ║
# ╚══════════════════════════════════════════════════════════════════════════╝

class OrderManager:
    def __init__(self, cfg: BotConfig, risk: RiskManager):
        self.cfg  = cfg
        self.risk = risk

    # ── Helpers ─────────────────────────────────────────────────────────────
    def _bot_positions(self, symbol: Optional[str] = None) -> list:
        pos = mt5.positions_get(symbol=symbol) if symbol else mt5.positions_get()
        if pos is None:
            return []
        return [p for p in pos if p.magic == self.cfg.magic_number]

    def has_position(self, symbol: str) -> bool:
        return len(self._bot_positions(symbol)) > 0

    def total_open(self) -> int:
        return len(self._bot_positions())

    # ── Ensure symbol is visible ─────────────────────────────────────────────
    @staticmethod
    def _ensure_symbol(symbol: str) -> Optional[object]:
        info = mt5.symbol_info(symbol)
        if info and not info.visible:
            mt5.symbol_select(symbol, True)
            info = mt5.symbol_info(symbol)
        return info

    # ── Open trade ───────────────────────────────────────────────────────────
    def open_trade(self, symbol: str, direction: Signal,
                   atr_value: float) -> Optional[int]:
        """
        Place a market order with ATR-based SL and RR-based TP.
        Returns ticket number on success, None on failure.
        """
        # Safety gates
        if not self.risk.is_spread_acceptable(symbol):
            return None
        if self.risk.is_daily_kill_switch_active():
            return None
        if not self.risk.margin_level_ok():
            return None
        if self.total_open() >= self.cfg.max_concurrent_trades:
            log.warning(f"⛔ Max concurrent trades reached ({self.cfg.max_concurrent_trades})")
            return None
        if self.has_position(symbol):
            return None

        info = self._ensure_symbol(symbol)
        if not info:
            log.error(f"❌ Cannot get info for {symbol}")
            return None

        tick = mt5.symbol_info_tick(symbol)
        if not tick:
            return None

        digits      = info.digits
        point       = info.point
        min_stop_pt = info.trade_stops_level * point  # broker minimum SL distance

        sl_dist = max(atr_value * self.cfg.atr_sl_multiplier, min_stop_pt * 1.2)
        tp_dist = sl_dist * self.cfg.min_rr_ratio

        if direction == Signal.BUY:
            entry  = tick.ask
            sl     = entry - sl_dist
            tp     = entry + tp_dist
            mt5_tp = mt5.ORDER_TYPE_BUY
        else:
            entry  = tick.bid
            sl     = entry + sl_dist
            tp     = entry - tp_dist
            mt5_tp = mt5.ORDER_TYPE_SELL

        entry = round(entry, digits)
        sl    = round(sl, digits)
        tp    = round(tp, digits)
        lot   = self.risk.compute_lot(symbol, sl_dist)

        request = {
            "action":      mt5.TRADE_ACTION_DEAL,
            "symbol":      symbol,
            "volume":      lot,
            "type":        mt5_tp,
            "price":       entry,
            "sl":          sl,
            "tp":          tp,
            "deviation":   self.cfg.slippage,
            "magic":       self.cfg.magic_number,
            "comment":     f"QEMA_{direction.value}",
            "type_time":   mt5.ORDER_TIME_GTC,
            "type_filling": mt5.ORDER_FILLING_IOC,
        }

        result = mt5.order_send(request)
        if result.retcode != mt5.TRADE_RETCODE_DONE:
            log.error(
                f"❌ Order failed │ {symbol} {direction.value} │ "
                f"code={result.retcode} │ {result.comment}"
            )
            return None

        ticket = result.order
        log.info(
            f"✅ OPENED │ {direction.value} {symbol} │ #{ticket} │ "
            f"entry={entry} sl={sl} tp={tp} lot={lot}"
        )
        return ticket

    # ── Modify stop loss ─────────────────────────────────────────────────────
    def modify_sl(self, position, new_sl: float) -> bool:
        info = mt5.symbol_info(position.symbol)
        if not info:
            return False

        new_sl = round(new_sl, info.digits)
        request = {
            "action":   mt5.TRADE_ACTION_SLTP,
            "symbol":   position.symbol,
            "position": position.ticket,
            "sl":       new_sl,
            "tp":       position.tp,
        }
        result = mt5.order_send(request)
        if result.retcode == mt5.TRADE_RETCODE_DONE:
            log.info(f"🔄 SL updated │ #{position.ticket} │ → {new_sl}")
            return True
        log.warning(
            f"⚠️  SL modify failed │ #{position.ticket} │ {result.comment}"
        )
        return False


# ╔══════════════════════════════════════════════════════════════════════════╗
# ║                         MAIN BOT ENGINE                                 ║
# ╚══════════════════════════════════════════════════════════════════════════╝

class QuantumEMABot:
    """
    Main orchestrator.

    Flow per symbol:
    ┌─────────────────────────────────────────────────────────┐
    │  1. Fetch OHLCV data                                    │
    │  2. Manage open positions → Quantum Smart Stop update   │
    │  3. Check 1-candle delayed pending signal               │
    │     └─ If new candle opened → execute trade             │
    │  4. Scan for new EMA crossover signal                   │
    │     └─ Store pending signal (execute on next candle)    │
    └─────────────────────────────────────────────────────────┘
    """

    def __init__(self, cfg: BotConfig):
        self.cfg         = cfg
        self.risk        = RiskManager(cfg)
        self.orders      = OrderManager(cfg, self.risk)
        self.smart_stop  = QuantumSmartStop(cfg)
        self.pending: Dict[str, dict] = {}   # {symbol: {signal, bar_time}}
        self.running     = False

    # ── MT5 Connection ──────────────────────────────────────────────────────
    def connect(self) -> bool:
        if not mt5.initialize():
            log.critical(f"❌ MT5 init failed │ {mt5.last_error()}")
            return False

        if self.cfg.login:
            ok = mt5.login(self.cfg.login, self.cfg.password, self.cfg.server)
            if not ok:
                log.critical(f"❌ Login failed │ {mt5.last_error()}")
                return False

        acc = mt5.account_info()
        if not acc:
            log.critical("❌ Account info unavailable.")
            return False

        log.info("═" * 70)
        log.info("   🤖  QUANTUM EMA BOT v3.0 — CONNECTED")
        log.info(f"   Account  : #{acc.login} │ Server : {acc.server}")
        log.info(f"   Balance  : {acc.balance:,.2f} {acc.currency}")
        log.info(f"   Equity   : {acc.equity:,.2f} {acc.currency}")
        log.info(f"   Leverage : 1:{acc.leverage}")
        log.info(f"   Strategy : EMA {self.cfg.ema_fast}/{self.cfg.ema_slow} │ "
                 f"TF={self._tf_name(self.cfg.timeframe)}")
        log.info(f"   Symbols  : {', '.join(self.cfg.symbols)}")
        log.info(f"   Risk/Trd : {self.cfg.risk_per_trade*100:.1f}% │ "
                 f"MaxDailyLoss={self.cfg.max_daily_loss_pct*100:.0f}%")
        log.info("═" * 70)
        return True

    @staticmethod
    def _tf_name(tf: int) -> str:
        mapping = {
            mt5.TIMEFRAME_M1: "M1", mt5.TIMEFRAME_M5: "M5",
            mt5.TIMEFRAME_M15: "M15", mt5.TIMEFRAME_M30: "M30",
            mt5.TIMEFRAME_H1: "H1", mt5.TIMEFRAME_H4: "H4",
            mt5.TIMEFRAME_D1: "D1",
        }
        return mapping.get(tf, str(tf))

    # ── Data ────────────────────────────────────────────────────────────────
    def fetch_candles(self, symbol: str, count: int = 150) -> Optional[pd.DataFrame]:
        rates = mt5.copy_rates_from_pos(symbol, self.cfg.timeframe, 0, count)
        if rates is None or len(rates) < 60:
            return None
        df = pd.DataFrame(rates)
        df["time"] = pd.to_datetime(df["time"], unit="s")
        df.set_index("time", inplace=True)
        return df

    # ── Core symbol processing ───────────────────────────────────────────────
    def process_symbol(self, symbol: str):
        df = self.fetch_candles(symbol)
        if df is None or df.empty:
            log.warning(f"   No data for {symbol}")
            return

        atr_now = Indicators.atr(df, self.cfg.atr_period).iloc[-2]

        # ── 1. Update Quantum Smart Stop on all open positions ──────────────
        positions = self.orders._bot_positions(symbol)
        active_tickets = set()

        for pos in positions:
            active_tickets.add(pos.ticket)
            # Ensure state is registered (edge case after bot restart)
            if pos.ticket not in self.smart_stop.states:
                direction = Signal.BUY if pos.type == mt5.ORDER_TYPE_BUY else Signal.SELL
                self.smart_stop.register(
                    pos.ticket, symbol, direction,
                    pos.price_open, pos.sl, pos.tp
                )
            new_sl = self.smart_stop.update(pos.ticket, df)
            if new_sl is not None:
                self.orders.modify_sl(pos, new_sl)

        # Clean up closed positions from smart stop state
        for t in list(self.smart_stop.states.keys()):
            if (self.smart_stop.states[t].symbol == symbol
                    and t not in active_tickets):
                self.smart_stop.remove(t)

        # ── 2. Don't open new trades if already positioned ─────────────────
        if self.orders.has_position(symbol):
            return

        # ── 3. Pending signal: 1-candle delay rule ──────────────────────────
        current_bar = df.index[-2]   # Last CONFIRMED candle timestamp

        if symbol in self.pending:
            pend = self.pending[symbol]

            if current_bar != pend["bar_time"]:
                # New candle confirmed → execute pending signal
                direction = pend["signal"]
                log.info(
                    f"🎯 Executing {direction.value} on {symbol} "
                    f"(1-candle delayed confirmation)"
                )
                ticket = self.orders.open_trade(symbol, direction, atr_now)

                if ticket:
                    positions = self.orders._bot_positions(symbol)
                    if positions:
                        pos = positions[0]
                        sl_dist = abs(pos.price_open - pos.sl)
                        tp_dist = abs(pos.tp - pos.price_open)
                        self.smart_stop.register(
                            ticket, symbol, direction,
                            pos.price_open, pos.sl, pos.tp
                        )

                del self.pending[symbol]
                return

        # ── 4. Scan for fresh EMA crossover ────────────────────────────────
        signal, bar_ts = Indicators.get_crossover_signal(
            df, self.cfg.ema_fast, self.cfg.ema_slow
        )

        if signal != Signal.NONE:
            if (symbol not in self.pending or
                    self.pending[symbol]["bar_time"] != bar_ts):
                self.pending[symbol] = {"signal": signal, "bar_time": bar_ts}
                log.info(
                    f"📡 {signal.value} signal │ {symbol} │ "
                    f"bar={bar_ts} │ → waiting next candle"
                )

    # ── Main loop ───────────────────────────────────────────────────────────
    def run(self, poll_seconds: int = 30):
        if not self.connect():
            return

        self.running = True
        log.info(f"🚀 Bot running │ poll every {poll_seconds}s │ Press Ctrl+C to stop")

        cycle = 0
        while self.running:
            try:
                cycle += 1
                log.debug(f"── Cycle #{cycle} │ {datetime.now():%H:%M:%S} ──")

                for symbol in self.cfg.symbols:
                    try:
                        self.process_symbol(symbol)
                    except Exception as e:
                        log.error(f"❌ {symbol} processing error: {e}", exc_info=True)

                self._log_account_summary()
                time.sleep(poll_seconds)

            except KeyboardInterrupt:
                log.info("⛔ Stopping bot (Ctrl+C received)…")
                self.running = False

            except Exception as e:
                log.critical(f"💥 Unhandled exception: {e}", exc_info=True)
                time.sleep(60)   # Back-off to avoid error loops

        mt5.shutdown()
        log.info("👋 MT5 disconnected. Bot stopped.")

    def stop(self):
        self.running = False

    # ── Account health summary ───────────────────────────────────────────────
    @staticmethod
    def _log_account_summary():
        acc = mt5.account_info()
        if not acc:
            return
        pos = mt5.positions_get() or []
        floating = sum(p.profit for p in pos)
        ml = acc.margin_level if acc.margin > 0 else 9999
        log.info(
            f"📊 Bal={acc.balance:,.2f} │ Eq={acc.equity:,.2f} │ "
            f"Float={floating:+.2f} │ ML={ml:.1f}% │ "
            f"Pos={len(pos)}"
        )


# ╔══════════════════════════════════════════════════════════════════════════╗
# ║                       ENTRY POINT                                       ║
# ╚══════════════════════════════════════════════════════════════════════════╝

if __name__ == "__main__":

    # ═══════════════════════════════════════════════════════════════════
    #   >>>  CONFIGURE YOUR SETTINGS BELOW  <<<
    # ═══════════════════════════════════════════════════════════════════

    cfg = BotConfig()

    # ── Account (leave login=0 to use already-connected MT5 terminal) ──
    cfg.login    = 0            # e.g. 12345678
    cfg.password = ""           # e.g. "MyPass123"
    cfg.server   = ""           # e.g. "ICMarkets-Live01"

    # ── Symbols to trade ───────────────────────────────────────────────
    cfg.symbols = [
        "EURUSD", "GBPUSD", "USDJPY",   # Forex majors
        "XAUUSD",                         # Gold
    ]

    # ── Timeframe ──────────────────────────────────────────────────────
    cfg.timeframe = mt5.TIMEFRAME_M15     # 15-minute recommended for EMA 9/26
    # Other options: mt5.TIMEFRAME_H1, TIMEFRAME_H4, TIMEFRAME_D1

    # ── Risk parameters ────────────────────────────────────────────────
    cfg.risk_per_trade      = 0.01    # 1% balance per trade
    cfg.max_daily_loss_pct  = 0.05    # 5% daily stop
    cfg.max_concurrent_trades = 3

    # ── Leverage (informational — set on your broker account) ──────────
    # Supported range: 1:500 — 1:1000
    # Recommended for small accounts: 1:500
    # Aggressive: 1:1000 (only if you understand the risks)

    # ── Smart Stop tuning ──────────────────────────────────────────────
    cfg.atr_sl_multiplier        = 1.5   # SL = 1.5 × ATR (conservative)
    cfg.min_rr_ratio             = 2.0   # TP = 2 × SL
    cfg.min_candles_before_trail = 3     # Wait 3 candles before touching SL
    cfg.trail_activation_rr      = 1.0   # Start trailing at breakeven+1
    cfg.profit_lock_rr           = 2.0   # Lock profit at 2:1

    # ═══════════════════════════════════════════════════════════════════

    bot = QuantumEMABot(cfg)
    bot.run(poll_seconds=30)
