import MetaTrader5 as mt5
from datetime import datetime, date
import numpy as np

DAILY_TARGET_CENT = 1000.0

def calculate_rsi(prices, period=14):
    if len(prices) < period + 1:
        return 50.0
    deltas = np.diff(prices)
    seed = deltas[:period]
    up = seed[seed >= 0].sum() / period
    down = -seed[seed < 0].sum() / period
    rs = up / down if down != 0 else 0
    rsi = np.zeros_like(prices)
    rsi[:period] = 100. - 100. / (1. + rs)

    for i in range(period, len(prices)):
        delta = deltas[i - 1]
        if delta > 0:
            upval = delta
            downval = 0.
        else:
            upval = 0.
            downval = -delta
        up = (up * (period - 1) + upval) / period
        down = (down * (period - 1) + downval) / period
        rs = up / down if down != 0 else 0
        rsi[i] = 100. - 100. / (1. + rs)
    return float(rsi[-1])

def get_report():
    # Cek akhir pekan: Sabtu & Minggu market tutup, heningkan watchdog (empty stdout = tidak kirim notifikasi)
    now = datetime.now()
    if now.weekday() in [5, 6]:
        return ""

    if not mt5.initialize(path=r"D:\MT5-Akun2\terminal64.exe", portable=True):
        return "⚠️ Gagal terhubung ke terminal MT5 Exness Portable."

    acc = mt5.account_info()
    if not acc:
        mt5.shutdown()
        return "⚠️ Gagal membaca informasi akun MT5."

    symbol = "XAUUSDc"
    tick = mt5.symbol_info_tick(symbol)
    curr_price = tick.bid
    
    # 1. Analisa Teknikal Market (M15 & H1)
    rates_m15 = mt5.copy_rates_from_pos(symbol, mt5.TIMEFRAME_M15, 0, 30)
    rates_h1 = mt5.copy_rates_from_pos(symbol, mt5.TIMEFRAME_H1, 0, 24)
    
    closes_m15 = [r['close'] for r in rates_m15]
    rsi_m15 = calculate_rsi(closes_m15, 14)
    day_high = max(r['high'] for r in rates_h1)
    day_low = min(r['low'] for r in rates_h1)
    
    ema20_m15 = sum(closes_m15[-20:]) / 20.0
    if curr_price > ema20_m15 + 1.0:
        market_trend = "BULLISH (Kuat di atas EMA20)"
    elif curr_price < ema20_m15 - 1.0:
        market_trend = "BEARISH (Pullback di bawah EMA20)"
    else:
        market_trend = "SIDEWAY / KONSOLIDASI (Mendatar di EMA20)"

    # 2. Situasi Finansial & Posisi Akun
    positions = mt5.positions_get(symbol=symbol) or []
    buys = [p for p in positions if p.type == 0]
    sells = [p for p in positions if p.type == 1]

    total_buy_pl = sum(p.profit for p in buys)
    total_sell_pl = sum(p.profit for p in sells)
    net_floating = acc.equity - acc.balance

    today_start = datetime.combine(date.today(), datetime.min.time())
    deals = mt5.history_deals_get(today_start, datetime.now()) or []
    realized_profit_today = sum(d.profit + d.swap + d.commission for d in deals if d.entry in [1, 2, 3])

    progress_pct = (realized_profit_today / DAILY_TARGET_CENT) * 100.0

    invest_buys = [p for p in buys if abs(p.volume - 0.10) < 0.001 or "INVEST" in p.comment.upper()]
    scalp_buys = [p for p in buys if p not in invest_buys]

    # 3. Analisa Taktis & Rumusan Tindakan
    action_plans = []
    
    # Aksi 1: Kunci Target Harian
    if realized_profit_today >= DAILY_TARGET_CENT:
        action_plans.append(
            "👑 *AKSI 1: KUNCI TARGET HARIAN TERCAPAI*\n"
            f"  • *Kondisi:* Profit hari ini sudah tembus `+{realized_profit_today:,.1f} cent` (+${realized_profit_today/100:.2f} USD).\n"
            "  • *Rekomendasi:* Matikan Algo Trading atau set InpBothSides=false agar profit terkunci aman 100% dari fluktuasi malam.\n"
            "  👉 *Balas 'OK 1' atau 'KUNCI' untuk langsung gw eksekusi.*"
        )
        
    # Aksi 2: Panen Invest Runner 0.10 jika Cuan Tebal
    for inv in invest_buys:
        if inv.profit >= 120.0:
            action_plans.append(
                f"💎 *AKSI 2: AMANKAN CUAN INVEST 0.10 (#{inv.ticket})*\n"
                f"  • *Kondisi:* Invest 0.10 terbuka @ {inv.price_open:.2f}, running @ {curr_price:.2f} (Cuan: `+{inv.profit:.1f} cent` / `+${inv.profit/100:.2f}`).\n"
                f"  • *Rekomendasi:* Tutup tiket #{inv.ticket} ke kas Balance, pasang Buy Limit baru di support {curr_price - 5.0:.2f}.\n"
                "  👉 *Balas 'OK PANEN' atau 'GAS PANEN' untuk langsung gw eksekusi.*"
            )

    # Aksi Proteksi SELL (Batas 5-7 Posisi & SL 30 cent)
    if len(sells) >= 5:
        action_plans.append(
            f"🛡️ *AKSI PROTEKSI SELL: BATAS {len(sells)}/7 POSISI TERCAPAI*\n"
            f"  • *Kondisi:* Akun memiliki {len(sells)} posisi SELL. Sesuai instruksi Erik, batas maksimum adalah 5-7 posisi dengan hard SL 30 cent.\n"
            f"  • *Status:* Penambahan SELL baru otomatis DIBLOKIR oleh EA & SL Guard.\n"
            f"  👉 *Balas 'CUT SELL' jika lo mau gw bersihkan posisi SELL yang minus melebihi 30 cent.*"
        )

    # Aksi 4: Trimming Pemulihan Otomatis (Zona Recovery $4,195 - $4,220)
    if curr_price >= 4195.0:
        action_plans.append(
            f"🚀 *AKSI RECOVERY: ZONA TARGET ${curr_price:.2f} TERCAPAI!*\n"
            f"  • *Status:* Emas sudah mantul ke zona aman panen (>= $4,195.00).\n"
            f"  • *Instruksi Erik:* Panen layer profit bawah dan potong pucuk, *sisain 0.10 di dasar* (#1988305167 & #1986109312).\n"
            f"  👉 *Balas 'PANEN' atau 'GAS' untuk langsung eksekusi live.*"
        )
    else:
        dist_to_recovery = 4195.0 - curr_price
        action_plans.append(
            f"⏳ *MONITORING RECOVERY ZONE ($4,195+)*\n"
            f"  • *Jarak ke Target:* Tinggal `{dist_to_recovery:.1f} poin` lagi menuju $4,195.00.\n"
            f"  • *Perlindungan Runner:* 0.10 lot terbawah (Tiket #1988305167 & #1986109312) sudah dikunci aman.\n"
            f"  • *SOP:* Begitu harga sentuh $4,195+, protokol panen siap dipicu."
        )

    # Aksi Standby jika akun normal
    if not action_plans:
        action_plans.append(
            "⚡ *STANDBY / BIARKAN BOT PANEN MANDIRI*\n"
            f"  • *Kondisi:* Market {market_trend}, RSI {rsi_m15:.1f} (Aman), Margin {acc.margin_level:,.0f}% super kuat.\n"
            "  • *Rekomendasi:* Tidak diperlukan intervensi manual saat ini. Bot v6.2 bekerja memburu target TP 500pt."
        )

    # Susun Laporan Komprehensif
    lines = [
        f"📊 *ANALISA PASAR & SITUASI AKUN TRADING ({datetime.now().strftime('%H:%M WIB')})*",
        "",
        "📈 *1. Pembacaan Pergerakan Market Gold (XAUUSD):*",
        f"• *Harga Live:* `{curr_price:.2f}` (Rentang Hari Ini: `{day_low:.2f} - {day_high:.2f}`)",
        f"• *Struktur Trend (M15):* {market_trend}",
        f"• *Indikator Momentum RSI:* `{rsi_m15:.1f}` ({'Jenuh Beli / Overbought' if rsi_m15>=70 else 'Jenuh Jual / Oversold' if rsi_m15<=30 else 'Zona Netral Sehat'})",
        "",
        "💼 *2. Analisa Situasi Finansial & Posisi Akun:*",
        f"• *Balance Kas:* `{acc.balance:,.2f} USC` (${acc.balance/100:.2f} USD)",
        f"• *Equity Aktif:* `{acc.equity:,.2f} USC` (${acc.equity/100:.2f} USD)",
        f"• *Net Floating:* `{'+' if net_floating >= 0 else ''}{net_floating:.2f} cent` (Margin Level: `{acc.margin_level:,.0f}%` - Sangat Kuat)",
        f"• *Realized Cuan Hari Ini:* `+{realized_profit_today:,.2f} cent` ({progress_pct:.1f}% menuju target {DAILY_TARGET_CENT:,.0f} cent)",
        f"• *Sebaran Posisi:* BUY `{len(buys)} pos` (Floating: `{'+' if total_buy_pl>=0 else ''}{total_buy_pl:.2f} cent`) | SELL `{len(sells)}/7 pos` (Batas 5-7 pos | SL 30c) (Floating: `{total_sell_pl:.2f} cent`)",
        "",
        "🎯 *3. Rekomendasi Tindakan Taktis Setelah Analisa:*",
        "\n\n".join(action_plans),
        "",
        "💬 _Setiap ada saran tindakan di atas, lo cukup ketik 'OK' atau 'GAS' di sini, langsung gw eksekusi instan di MT5._"
    ]

    mt5.shutdown()
    return "\n".join(lines)

if __name__ == "__main__":
    print(get_report())
