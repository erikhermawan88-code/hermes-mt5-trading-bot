# 🤖 Hermes MT5 Quant Trading Bot & Risk Copilot (v6.2 Suite)

Sistem trading kuantitatif terintegrasi MetaTrader 5 (MT5) yang menggabungkan Expert Advisor MQL5 otomatis dengan engine pengawas risiko (Risk Watchdog) berbasis Python dan instruksi otonom untuk Hermes Agent.

---

## 🏗️ 1. Arsitektur Sistem

Sistem ini terbagi menjadi 3 komponen utama:

1. **Core MQL5 EA (`/mql5_ea`)**:
   - `XAUUSD_GridScalp_v6.2_EA.mq5` & terkompilasi `.ex5`.
   - **Dual-Engine Architecture:**
     - Scalper grid buy/sell lot 0.03 dengan TP 500 point.
     - Macro Invest BUY lot 0.10 (HODL trend runner).
   - **Benteng Pertahanan:**
     - Maksimal posisi SELL dibatasi keras **5 sampai 7 posisi** (`InpMaxSell = 5`, `InpTotalMaxSell = 7`).
     - Hard Stop Loss otomatis terpasang **30 cent (-30.0 USC)** untuk mencegah floating loss membengkak.
     - Filter RSI M15 < 32 untuk proteksi posisi Buy.

2. **Python Risk Watchdog & Automation Bridge (`/python_watchdog`)**:
   - `sl_guard_manager.py`: Memantau floating loss posisi secara real-time via MetaTrader5 Python API dan melakukan auto cut-loss jika melebihi ambang batas 30 cent (-30.0 USC).
   - `trading_watchdog_cron.py`: Memeriksa portofolio secara berkala (cron per jam), menganalisis equity/margin, dan menyusun laporan aksi taktis (panen/cut loss).
   - `execute_trading_action.py`: Eksekutor interaktif untuk menutup posisi (close buy/sell, harvest runner, selective trimming) secara instan.

3. **Hermes Agent Copilot Skill (`/skill`)**:
   - `SKILL.md`: Standard Operating Procedure (SOP) agar Hermes Agent lain mampu mendeteksi terminal MT5, mengatasi kendala koneksi IPC Windows, dan mengendalikan akun secara mandiri.

---

## 🚀 2. Cara Hermes Agent Lain Mengakses & Menggunakan Bot Ini

Bagi Hermes Agent lain yang ingin menggunakan bot ini:

### Langkah A: Setup Environment di Komputer Target
MT5 Python API mewajibkan **Python 64-bit (Windows)** versi 3.8 s/d 3.12:
```bash
pip install MetaTrader5 psutil numpy
```

### Langkah B: Pasang Skill di Hermes Target
Salin folder `skill/` ke direktori skills Hermes Agent target:
```bash
# Path skill di Hermes:
# ~/.hermes/skills/finance/hermes-mt5-copilot/SKILL.md
# atau di Windows:
# %LOCALAPPDATA%\hermes\skills\finance\hermes-mt5-copilot\SKILL.md
```

### Langkah C: Auto-Install Cepat (Recommended)
Cukup jalankan script installer otomatis yang sudah kami sediakan:
```bash
python auto_install.py
```
Script ini akan:
1. Menginstall dependencies Python (`MetaTrader5`, `psutil`, `numpy`).
2. Mendeteksi direktori MT5 secara otomatis dan menyalin file EA (`.ex5`/`.mq5`) ke folder `MQL5/Experts/` serta file presets ke `MQL5/Presets/`.
3. Memasang skill `hermes-mt5-copilot` langsung ke direktori skills Hermes Agent target.

Atau jika ingin pasang manual:
1. Pindahkan file dari `mql5_ea/` ke:
   `<MT5_DATA_FOLDER>\MQL5\Experts\`
2. Pindahkan file dari `presets/` ke:
   `<MT5_DATA_FOLDER>\MQL5\Presets\`
3. Buka MT5, pastikan:
   - **Tools -> Options -> Expert Advisors** -> Centang **"Allow algorithmic trading"** dan **"Allow DLL imports"**.
   - Tombol **"Algo Trading"** di toolbar atas dalam status **HIJAU (ON)**.
4. Pasang EA ke chart `XAUUSD` (Timeframe M1 atau M5) dan load preset `sistemv62.set`.

### Langkah D: Jalankan Watchdog Proteksi Python
Jalankan pengawas risiko di latar belakang:
```bash
python python_watchdog/sl_guard_manager.py
```

---

## ⚙️ 3. Spesifikasi Akun Rekomendasi
- **Tipe Akun:** Exness Standard Cent (Akun Cent)
- **Simbol:** `XAUUSDc` (Contract Size: 1.0)
- **Minimum Modal:** $100 - $200 USD (setara 10,000 - 20,000 USC)
- **Lot Rekomendasi:** Scalper `0.03` / Macro Runner `0.10`
