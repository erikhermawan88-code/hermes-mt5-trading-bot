---
name: hermes-mt5-copilot
description: Use when controlling or automating MetaTrader 5 (MT5).
---

# Hermes MT5 Copilot & Terminal Automation Bridge

Authoritative procedural guide and Python engine for enabling Hermes Agent to seamlessly inspect, control, trade, and manage risk on any MetaTrader 5 (MT5) terminal across Windows environments.

---

## 1. WHY MT5 CONNECTION FAILS ON NEW COMPUTERS (THE 5 CRITICAL CHECKPOINTS)

If Hermes Agent on another computer cannot connect to MT5 (`mt5.initialize()` returns `False` or raises errors), it is ALWAYS caused by one of these 5 root causes:

### 🔴 Checkpoint 1: Python Architecture & Version Mismatch (Most Common)
- **Rule:** The official `MetaTrader5` Python package **ONLY works on 64-bit Windows Python (AMD64)** and supports Python **3.8 through 3.12**.
- **Failure:** 
  - 32-bit Python throws `ImportError: DLL load failed` or `No matching distribution found`.
  - Python 3.13+ may not have pre-built binary wheels on PyPI.
- **Fix:** Install Windows 64-bit Python 3.11 or 3.12 (`python-3.11.x-amd64.exe`).

### 🔴 Checkpoint 2: Package Not Installed in Hermes's Active Environment
- **Rule:** When Hermes runs commands via terminal, it often uses its own virtualenv (e.g. `C:\Users\<user>\AppData\Local\hermes\hermes-agent\venv\Scripts\python.exe`) or the system Python.
- **Failure:** `ModuleNotFoundError: No module named 'MetaTrader5'`.
- **Fix:** Run pip install targeting the exact python executable Hermes uses:
  ```bash
  python -m pip install MetaTrader5 psutil numpy
  # If inside Hermes virtualenv:
  "C:/Users/<user>/AppData/Local/hermes/hermes-agent/venv/Scripts/python.exe" -m pip install MetaTrader5 psutil numpy
  ```

### 🔴 Checkpoint 3: Terminal Path Not Explicitly Passed (Portable vs Installed)
- **Rule:** A bare `mt5.initialize()` only searches standard Windows Registry keys (`C:\Program Files\MetaTrader 5\terminal64.exe`). If MT5 is installed on another drive (e.g. `D:\MT5-Akun2\`), inside a broker custom folder, or run in portable mode (`/portable`), `initialize()` **fails silently**.
- **Fix:** Always provide the full absolute path and `portable=True` if applicable:
  ```python
  mt5.initialize(path=r"D:\MT5-Akun2\terminal64.exe", portable=True)
  ```

### 🔴 Checkpoint 4: MT5 Algo Trading & API Permissions Disabled in GUI
- **Rule:** MT5 blocks all order execution and DLL inter-process communication unless permissions are enabled in terminal options.
- **Fix in MT5 GUI:**
  1. Open MT5 $\rightarrow$ Menu **Tools** $\rightarrow$ **Options** (or press **Ctrl + O**).
  2. Select tab **Expert Advisors**.
  3. Check: **"Allow algorithmic trading"**.
  4. Check: **"Allow DLL imports"**.
  5. Check: **"Allow WebRequest for listed URL"**.
  6. In the main MT5 toolbar, ensure the **"Algo Trading"** button is **ON (Green icon)**.

### 🔴 Checkpoint 5: Windows User Privilege & UAC Elevation Mismatch
- **Rule:** If MT5 is launched with "Run as Administrator", but Hermes or the Python script is launched under a standard user token (or vice versa), Windows User Account Control (UAC) integrity levels block the local Windows IPC named pipe.
- **Fix:** Run both MT5 and Hermes under the same standard user session (do NOT run MT5 as Administrator unless required).

---

## 2. UNIVERSAL MT5 CONNECTION TEMPLATE (AUTO-LOCATING ENGINE)

Use this robust helper to auto-detect any running or installed MT5 terminal on the system:

```python
import os, psutil
import MetaTrader5 as mt5

def get_mt5_terminal_path():
    # 1. Check currently running processes first
    for p in psutil.process_iter(['name', 'exe']):
        try:
            if p.info['name'] and 'terminal64' in p.info['name'].lower():
                return p.info['exe']
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            pass

    # 2. Check standard candidate directories
    candidates = [
        r"C:\Program Files\MetaTrader 5\terminal64.exe",
        r"C:\Program Files (x86)\MetaTrader 5\terminal64.exe",
        r"D:\MT5-Akun2\terminal64.exe",
        r"C:\MT5\terminal64.exe",
        r"D:\MetaTrader 5\terminal64.exe"
    ]
    for c in candidates:
        if os.path.isfile(c):
            return c
    return None

def connect_mt5():
    exe_path = get_mt5_terminal_path()
    if exe_path:
        is_portable = os.path.exists(os.path.join(os.path.dirname(exe_path), 'portable')) or 'Akun' in exe_path
        if mt5.initialize(path=exe_path, portable=is_portable):
            return True, f"Connected to {exe_path}"
    
    # Fallback to default registry lookup
    if mt5.initialize():
        return True, "Connected via default registry MT5"
        
    return False, f"Init failed: {mt5.last_error()}"
```

---

## 3. CORE TRADING & ACCOUNT CONTROL PROCEDURES

### A. Inspect Account & Live Balance
```python
acc = mt5.account_info()
# acc.balance, acc.equity, acc.margin_level, acc.margin_free, acc.server, acc.login
```

### B. Read Open Positions (With Magic Number Filter)
```python
positions = mt5.positions_get(symbol="XAUUSDc") or []
buys = [p for p in positions if p.type == 0]
sells = [p for p in positions if p.type == 1]
```

### C. Set Hard Stop Loss (TRADE_ACTION_SLTP)
```python
# Set SL on ticket
req = {
    "action": mt5.TRADE_ACTION_SLTP,
    "position": ticket,
    "symbol": symbol,
    "sl": target_sl_price,
    "tp": current_tp_price,
}
res = mt5.order_send(req)
# res.retcode == mt5.TRADE_RETCODE_DONE (10009) means SUCCESS
```

### D. Close Position by Ticket (Market Deal)
```python
p = mt5.positions_get(ticket=ticket)[0]
close_type = mt5.ORDER_TYPE_SELL if p.type == 0 else mt5.ORDER_TYPE_BUY
close_price = mt5.symbol_info_tick(symbol).bid if p.type == 0 else mt5.symbol_info_tick(symbol).ask

req = {
    "action": mt5.TRADE_ACTION_DEAL,
    "position": p.ticket,
    "symbol": p.symbol,
    "volume": p.volume,
    "type": close_type,
    "price": close_price,
    "deviation": 25,
    "magic": p.magic,
    "comment": "HERMES_CLOSE",
    "type_time": mt5.ORDER_TIME_GTC,
    "type_filling": mt5.ORDER_FILLING_IOC,
}
res = mt5.order_send(req)
```

---

## 4. STANDALONE RISK MANAGEMENT RULE: SL GUARD & GRID TRIMMING

### A. Stop Loss Cap Rule for Scalpers (0.03 lot)
- **Calculation for Gold Cent (`XAUUSDc`):** Contract size = 1.0, 1 USD price delta = 3.0 USC.
- **Target Cap:** Max loss per 0.03 scalping layer = **-40.0 USC** ($\approx 13.333$ price points).
  - For SELL: `sl_price = price_open + 13.33`
  - For BUY:  `sl_price = price_open - 13.33`
- **Dual-Layer Guard:**
  1. Register hard SL directly on the broker server via `TRADE_ACTION_SLTP` as soon as order fills so network disconnects cannot cause blowout.
  2. Maintain a background watchdog / manager (`sl_guard_manager.py`) to auto-close positions if floating P/L drops to $\le -40.0$ USC due to slippage or weekend gap.

### B. Selective Grid Trimming Protocol (Counter-Trend Accumulation)
When the EA accumulates 5+ counter-trend grid layers during a strong directional impulse:
1. **Never let infinite grid layers stack:** Identify the 2 worst outlier tickets (the layers furthest from market price).
2. **Selective Pruning:** Cut the 2 deepest negative layers immediately to release margin and arrest drawdown progression.
3. **Subsidized Payoff:** If a trend-following runner position (e.g. BUY 0.10) is floating in substantial profit, use runner profit to fund the closure of outlier grid debt, keeping net account balance neutral or positive.
