# execute_trading_action.py
import MetaTrader5 as mt5
import sys

def execute_action(action_type):
    if not mt5.initialize(path=r"D:\MT5-Akun2\terminal64.exe", portable=True):
        return {"status": "error", "message": "Gagal terhubung ke MT5."}

    symbol = "XAUUSDc"
    tick = mt5.symbol_info_tick(symbol)
    positions = mt5.positions_get(symbol=symbol) or []
    buys = [p for p in positions if p.type == 0]
    sells = [p for p in positions if p.type == 1]

    if action_type.upper() in ["TRIM", "PAIR_TRIM"]:
        # Exclude invest 0.10 from trimming
        scalp_buys = [p for p in buys if abs(p.volume - 0.10) > 0.001 and "INVEST" not in p.comment.upper()]
        profitable_buys = [p for p in scalp_buys if p.profit > 0]
        if not profitable_buys or not sells:
            mt5.shutdown()
            return {"status": "noop", "message": "Tidak ada pasangan BUY cuan dan SELL minus yang memenuhi syarat."}

        best_buy = max(profitable_buys, key=lambda p: p.profit)
        worst_sell = min(sells, key=lambda p: p.profit)
        net_pl = best_buy.profit + worst_sell.profit

        # Close best_buy
        req_b = {
            "action": mt5.TRADE_ACTION_DEAL,
            "position": best_buy.ticket,
            "symbol": symbol,
            "volume": best_buy.volume,
            "type": mt5.ORDER_TYPE_SELL,
            "price": tick.bid,
            "deviation": 20,
            "magic": 27270062,
            "comment": "HERMES_TRIM_B",
            "type_time": mt5.ORDER_TIME_GTC,
            "type_filling": mt5.ORDER_FILLING_IOC,
        }
        res_b = mt5.order_send(req_b)

        # Close worst_sell
        req_s = {
            "action": mt5.TRADE_ACTION_DEAL,
            "position": worst_sell.ticket,
            "symbol": symbol,
            "volume": worst_sell.volume,
            "type": mt5.ORDER_TYPE_BUY,
            "price": tick.ask,
            "deviation": 20,
            "magic": 27270062,
            "comment": "HERMES_TRIM_S",
            "type_time": mt5.ORDER_TIME_GTC,
            "type_filling": mt5.ORDER_FILLING_IOC,
        }
        res_s = mt5.order_send(req_s)

        mt5.shutdown()
        return {
            "status": "success",
            "action": "PAIR_TRIM",
            "buy_ticket": best_buy.ticket,
            "buy_pl": best_buy.profit,
            "sell_ticket": worst_sell.ticket,
            "sell_pl": worst_sell.profit,
            "net_pl": net_pl,
            "res_b": res_b.retcode if res_b else None,
            "res_s": res_s.retcode if res_s else None
        }

    elif action_type.upper() in ["RECOVERY_PANEN"] or (action_type.upper() in ["PANEN", "HARVEST_INVEST"] and tick.bid >= 4195.0):
        # If price reaches recovery zone ($4,195+), run auto_recovery_trim protocol
        import auto_recovery_trim
        recovery_res = auto_recovery_trim.run_recovery(dry_run=False, force=True)
        mt5.shutdown()
        return {
            "status": "success",
            "action": "AUTO_RECOVERY_PANEN",
            "details": recovery_res
        }

    elif action_type.upper() in ["PANEN", "HARVEST_INVEST"]:
        # Aksi 2 Watchdog: Panen Invest Runner 0.10 jika Cuan Tebal
        invest_buys = [p for p in buys if abs(p.volume - 0.10) < 0.001 or "INVEST" in p.comment.upper()]
        profitable_inv = [p for p in invest_buys if p.profit > 0]
        if not profitable_inv:
            mt5.shutdown()
            return {"status": "noop", "message": "Tidak ada posisi Invest 0.10 yang sedang profit."}

        best_inv = max(profitable_inv, key=lambda p: p.profit)
        ticket = best_inv.ticket
        profit_val = best_inv.profit
        close_price = mt5.symbol_info_tick(symbol).bid

        close_req = {
            "action": mt5.TRADE_ACTION_DEAL,
            "position": ticket,
            "symbol": symbol,
            "volume": best_inv.volume,
            "type": mt5.ORDER_TYPE_SELL,
            "price": close_price,
            "deviation": 25,
            "magic": best_inv.magic,
            "comment": "HERMES_PANEN_INVEST",
            "type_time": mt5.ORDER_TIME_GTC,
            "type_filling": mt5.ORDER_FILLING_IOC,
        }
        res_deal = mt5.order_send(close_req)

        # Pasang Buy Limit reload di support (5 poin di bawah)
        limit_price = round(close_price - 5.0, 2)
        limit_req = {
            "action": mt5.TRADE_ACTION_PENDING,
            "symbol": symbol,
            "volume": 0.10,
            "type": mt5.ORDER_TYPE_BUY_LIMIT,
            "price": limit_price,
            "deviation": 25,
            "magic": 0,
            "comment": "HERMES_RELOAD_INVEST",
            "type_time": mt5.ORDER_TIME_GTC,
            "type_filling": mt5.ORDER_FILLING_IOC,
        }
        res_limit = mt5.order_send(limit_req)

        mt5.shutdown()
        return {
            "status": "success",
            "action": "HARVEST_INVEST",
            "ticket": ticket,
            "profit_realized": profit_val,
            "close_price": close_price,
            "deal_retcode": res_deal.retcode if res_deal else None,
            "limit_price": limit_price,
            "limit_retcode": res_limit.retcode if res_limit else None,
        }

    elif action_type.upper() in ["CUT_SELL", "CUT_EXCEEDED", "CUT_SELL_NYANGKUT"]:
        import sl_guard_manager
        guard_res = sl_guard_manager.run_sl_guard(close_exceeded=True)
        mt5.shutdown()
        return {
            "status": "success",
            "action": "CUT_EXCEEDED_SELL",
            "details": guard_res
        }

    elif action_type.upper() in ["KUNCI", "LOCK_TARGET"]:
        # Disable Algo Trading via Win32 command 33020
        import win32gui
        import win32con
        hwnd = 1575462
        win32gui.SendMessage(hwnd, win32con.WM_COMMAND, 33020, 0)
        mt5.shutdown()
        return {
            "status": "success",
            "action": "LOCK_TARGET",
            "message": "Algo Trading dinonaktifkan (Kunci Target Harian)."
        }

    mt5.shutdown()
    return {"status": "unknown_action", "action": action_type}

if __name__ == "__main__":
    act = sys.argv[1] if len(sys.argv) > 1 else "TRIM"
    print(execute_action(act))
