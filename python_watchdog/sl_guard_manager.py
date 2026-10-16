#!/usr/bin/env python3
"""
SL Guard Manager for Erik MT5 Cent Account (#263332955)
Automatically manages and enforces Stop Loss on scalping positions (0.03 lot):
1. Calculates hard SL at exactly -40.0 USC max loss ($13.33 move in Gold).
   - For SELL: SL = Open Price + 13.333
   - For BUY:  SL = Open Price - 13.333
2. Registers hard SL directly to the broker server via TRADE_ACTION_SLTP.
3. Automatically monitors positions and executes emergency market-close if loss exceeds -40.0 USC.
"""

import sys
import MetaTrader5 as mt5

MAX_LOSS_USC = 30.0 # User directive: minus 30 di SL aja (30 cent ketat)
TARGET_VOLUME = 0.03
SYMBOL = "XAUUSDc"

def run_sl_guard(close_exceeded=False):
    if not mt5.initialize(path=r"D:\MT5-Akun2\terminal64.exe", portable=True):
        return {"status": "error", "message": "Gagal terhubung ke MT5."}

    tick = mt5.symbol_info_tick(SYMBOL)
    if not tick:
        mt5.shutdown()
        return {"status": "error", "message": "Gagal membaca tick harga XAUUSDc."}

    positions = mt5.positions_get(symbol=SYMBOL) or []
    scalp_positions = [p for p in positions if abs(p.volume - TARGET_VOLUME) < 0.001]

    results = {
        "status": "success",
        "current_bid": tick.bid,
        "current_ask": tick.ask,
        "sl_updated": [],
        "sl_failed": [],
        "exceeded_positions": [],
        "closed_exceeded": []
    }

    # 1. Delta calculation: for 0.03 lot, 1 USD move = 3.0 USC
    # Delta = 30.0 / (0.03 * 100) = 10.000
    delta_points = MAX_LOSS_USC / (TARGET_VOLUME * 100.0)

    for p in scalp_positions:
        p_loss = p.profit + p.swap
        is_sell = (p.type == 1)
        
        # Calculate ideal SL price
        if is_sell:
            target_sl = round(p.price_open + delta_points, 2)
            can_set_broker_sl = (tick.ask < target_sl)
        else:
            # For BUY, only apply to recent active scalpers (ignore legacy stuck buys > 4250)
            if p.price_open > 4250.0:
                continue
            target_sl = round(p.price_open - delta_points, 2)
            can_set_broker_sl = (tick.bid > target_sl)

        # A. If broker SL is not set or differs significantly, try to set it
        if abs(p.sl - target_sl) > 0.05 and can_set_broker_sl:
            req = {
                "action": mt5.TRADE_ACTION_SLTP,
                "position": p.ticket,
                "symbol": SYMBOL,
                "sl": target_sl,
                "tp": p.tp,
            }
            res = mt5.order_send(req)
            if res and res.retcode == mt5.TRADE_RETCODE_DONE:
                results["sl_updated"].append({
                    "ticket": p.ticket,
                    "type": "SELL" if is_sell else "BUY",
                    "price_open": p.price_open,
                    "sl": target_sl,
                    "retcode": res.retcode
                })
            else:
                results["sl_failed"].append({
                    "ticket": p.ticket,
                    "target_sl": target_sl,
                    "retcode": res.retcode if res else None,
                    "comment": res.comment if res else "No response"
                })

        # B. Check if position loss exceeds -40.0 USC
        if p_loss <= -MAX_LOSS_USC:
            exceeded_info = {
                "ticket": p.ticket,
                "type": "SELL" if is_sell else "BUY",
                "price_open": p.price_open,
                "current_loss": p_loss,
                "magic": p.magic
            }
            results["exceeded_positions"].append(exceeded_info)

            # If close_exceeded flag is True, market close it now
            if close_exceeded:
                close_type = mt5.ORDER_TYPE_BUY if is_sell else mt5.ORDER_TYPE_SELL
                close_price = tick.ask if is_sell else tick.bid
                close_req = {
                    "action": mt5.TRADE_ACTION_DEAL,
                    "position": p.ticket,
                    "symbol": SYMBOL,
                    "volume": p.volume,
                    "type": close_type,
                    "price": close_price,
                    "deviation": 25,
                    "magic": p.magic,
                    "comment": f"SL_GUARD_{int(MAX_LOSS_USC)}",
                    "type_time": mt5.ORDER_TIME_GTC,
                    "type_filling": mt5.ORDER_FILLING_IOC,
                }
                c_res = mt5.order_send(close_req)
                if c_res and c_res.retcode == mt5.TRADE_RETCODE_DONE:
                    results["closed_exceeded"].append({
                        "ticket": p.ticket,
                        "profit_realized": p_loss,
                        "retcode": c_res.retcode
                    })

    mt5.shutdown()
    return results

if __name__ == "__main__":
    close_flag = "--close-now" in sys.argv
    res = run_sl_guard(close_exceeded=close_flag)
    print("SL Guard Result:", res)
