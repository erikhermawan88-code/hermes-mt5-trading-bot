#!/usr/bin/env python3
"""
Automated Installer for Hermes MT5 Trading Bot v6.2 Suite
Installs EA, presets, Python risk watchdog, and Hermes copilot skill automatically.
"""

import os
import sys
import shutil
import glob
import subprocess

def print_step(msg):
    print(f"\n[+] {msg}")

def main():
    print("=" * 65)
    print("🤖 HERMES MT5 TRADING BOT v6.2 - AUTOMATED INSTALLER")
    print("=" * 65)

    base_dir = os.path.dirname(os.path.abspath(__file__))
    mql5_src = os.path.join(base_dir, "mql5_ea")
    presets_src = os.path.join(base_dir, "presets")
    skill_src = os.path.join(base_dir, "skill", "SKILL.md")

    # 1. Install python dependencies
    print_step("Installing Python requirements (MetaTrader5, psutil, numpy)...")
    try:
        subprocess.run([sys.executable, "-m", "pip", "install", "MetaTrader5", "psutil", "numpy"], check=False)
    except Exception as e:
        print(f"[-] Pip install warning: {e}")

    # 2. Locate MT5 data directory
    print_step("Detecting MetaTrader 5 directories...")
    mt5_dirs = []
    
    # Check AppData MetaQuotes
    appdata_mt5 = os.path.expandvars(r"%APPDATA%\MetaQuotes\Terminal")
    if os.path.exists(appdata_mt5):
        for item in os.listdir(appdata_mt5):
            candidate = os.path.join(appdata_mt5, item, "MQL5")
            if os.path.exists(candidate):
                mt5_dirs.append(candidate)

    # Check common drives for portable installs
    for drive in ["C", "D", "E"]:
        patterns = [
            f"{drive}:/MT5*/MQL5",
            f"{drive}:/Program Files/MetaTrader 5/MQL5",
            f"{drive}:/Program Files (x86)/MetaTrader 5/MQL5"
        ]
        for pat in patterns:
            for match in glob.glob(pat):
                if os.path.exists(match) and match not in mt5_dirs:
                    mt5_dirs.append(match)

    target_mql5 = None
    if mt5_dirs:
        print(f"Found {len(mt5_dirs)} MT5 MQL5 directory(s):")
        for idx, d in enumerate(mt5_dirs):
            print(f"  [{idx+1}] {d}")
        target_mql5 = mt5_dirs[0]
        print(f"Target selected: {target_mql5}")
    else:
        print("[-] No standard MT5 MQL5 directory auto-detected.")
        custom = input("Please enter your MT5 MQL5 directory path (or press Enter to skip): ").strip()
        if custom and os.path.exists(custom):
            target_mql5 = custom

    # 3. Copy EA & Presets
    if target_mql5:
        experts_dir = os.path.join(target_mql5, "Experts")
        presets_dir = os.path.join(target_mql5, "Presets")
        os.makedirs(experts_dir, exist_ok=True)
        os.makedirs(presets_dir, exist_ok=True)

        for f in os.listdir(mql5_src):
            s = os.path.join(mql5_src, f)
            d = os.path.join(experts_dir, f)
            shutil.copy2(s, d)
            print(f"  Copied EA: {f} -> {experts_dir}")

        for f in os.listdir(presets_src):
            s = os.path.join(presets_src, f)
            d = os.path.join(presets_dir, f)
            shutil.copy2(s, d)
            print(f"  Copied Preset: {f} -> {presets_dir}")
        print_step("MQL5 files installed successfully!")
    else:
        print("[-] Skipping MQL5 file copy (target directory not specified).")

    # 4. Install Hermes Skill
    print_step("Installing Hermes Copilot Skill...")
    hermes_skill_paths = [
        os.path.expandvars(r"%LOCALAPPDATA%\hermes\skills\finance\hermes-mt5-copilot\SKILL.md"),
        os.path.expanduser("~/.hermes/skills/finance/hermes-mt5-copilot/SKILL.md")
    ]
    for sp in hermes_skill_paths:
        try:
            os.makedirs(os.path.dirname(sp), exist_ok=True)
            shutil.copy2(skill_src, sp)
            print(f"  Skill installed to: {sp}")
        except Exception as e:
            pass

    print("\n" + "=" * 65)
    print("✅ INSTALLATION COMPLETED!")
    print("=" * 65)
    print("Next steps:")
    print("1. Open MetaTrader 5.")
    print("2. Ensure 'Algo Trading' is ON (Green button).")
    print("3. Attach 'XAUUSD_GridScalp_v6.2_EA' to XAUUSD M1/M5 chart.")
    print("4. Load preset 'sistemv62.set'.")
    print("5. Run watchdog: python python_watchdog/sl_guard_manager.py")
    print("=" * 65)

if __name__ == "__main__":
    main()
