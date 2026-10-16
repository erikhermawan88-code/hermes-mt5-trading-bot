//+------------------------------------------------------------------+
//|                                    XAUUSD_GridScalp_v6_EA.mq5     |
//|                                                                  |
//|  GRID SCALP v6 = v5 (grid bebas) + RECOVERY BATCH lihat S/R.      |
//|   - Grid utama: BUY & SELL bebas (kayak v5), TANPA filter S/R.    |
//|     Grid jarak InpGridPoints, maks InpMaxPerSide (10-20) / arah.  |
//|     Tiap posisi ditutup sendiri saat profit >= TP efektif.       |
//|   - RECOVERY: kalau 1 arah kena >= InpRecoveryTrigger (20) DAN    |
//|     harga di area S/R (support utk recovery BUY, resist utk SELL) |
//|     -> buka s/d InpRecoveryMax (10) posisi SEARAH basket yg       |
//|     nyangkut, lot tetap, jarak InpRecoverySpacing.               |
//|   - TIDAK ADA basket SL (permintaan user).                       |
//|   - Kill-switch equity <= InpKillEquityPct% peak (default 30 =    |
//|     -70%). InpKillReset: tutup semua -> reset peak -> mulai lagi. |
//|                                                                  |
//|  !!! RISIKO SANGAT TINGGI. Recovery = nambah martingale layer.   |
//|  UJI di DEMO / Strategy Tester every-tick dulu.                  |
//+------------------------------------------------------------------+
#property copyright "Custom EA - penggunaan pribadi"
#property version   "6.20"
#property description "Grid scalp v6.2 - entry S/R + recovery + 15s TP delay + 2x 0.10 Invest HODL runner"

#include <Trade\Trade.mqh>
#include <Canvas\Canvas.mqh>
#include <DigitalnusaLicense.mqh>

input group "=== Grid utama ==="
input double InpLot          = 0.03;   // Lot tetap tiap posisi (default 0.03)
input int    InpGridPoints   = 1500;   // Jarak tambah posisi (1500 pt = $1.50)
input int    InpTPPoints     = 500;    // Target profit per posisi (points). Min; naik ke spread+buffer
input int    InpTPBufferPts  = 100;    // Buffer di atas spread untuk TP efektif
input int    InpEntryDelayAfterTPSec = 25; // Jeda (detik) sebelum entry baru pasca-TP (Anti langsung nyangkut)
input int    InpMaxBuy       = 10;     // Batas posisi grid BUY (10)
input int    InpMaxSell      = 5;      // Batas posisi grid SELL (KUNCI KETAT: MAX 5 POSISI)
input int    InpTotalMaxSell = 7;      // Batas MAKSIMAL TOTAL Posisi SELL (5 s/d 7 Posisi)
input double InpMaxLossCent  = 30.0;   // Stop Loss ketat per posisi (30 cent / 30.0 USC)
input int    InpMaxPositions = 25;     // Batas TOTAL posisi (25)
input bool   InpBothSides    = true;   // Grid BUY & SELL sekaligus

input group "=== Filter Lembah & Anti-Nyangkut SELL ==="
input bool   InpUseRSIFilter         = true;       // Aktifkan Filter RSI Lembah
input ENUM_TIMEFRAMES InpRSI_TF      = PERIOD_M15; // Timeframe RSI
input int    InpRSIPeriod            = 14;         // Periode RSI
input double InpRSIOversoldLimit     = 32.0;       // Batas Oversold: Kalau RSI <= ini, DILARANG BUKA SELL BARU!


input group "=== Zona entry RECOVERY (S/R + OB + FVG) ==="
input ENUM_TIMEFRAMES InpSRTimeframe = PERIOD_M5;  // TF swing high/low (S/R sederhana)
input int    InpSRLookback    = 20;    // Jumlah candle swing high/low
input int    InpSRTolerancePts= 1500;  // Toleransi "dekat" S/R (points)
input int    InpRecoveryZone  = 3;     // 0=S/R swing | 1=FVG | 2=OB | 3=salah satu (FVG/OB/S-R)
input ENUM_TIMEFRAMES InpZoneTF = PERIOD_H1;  // TF deteksi Order Block & FVG
input int    InpZoneLookback  = 60;    // Bar dicek buat cari OB/FVG
input int    InpZoneTolPts    = 2000;  // Toleransi "di / dekat" zona OB/FVG (points; 2000 = $2)

input group "=== RECOVERY BATCH (Tingkat 2 - Jeda 10.000 s/d 20.000 pt) ==="
input bool   InpRecoveryOn       = true;   // Aktifkan recovery batch
input int    InpRecoveryMaxBuy   = 3;      // Maks posisi recovery kelipatan BUY (3 posisi)
input int    InpRecoveryMaxSell  = 2;      // Maks posisi recovery kelipatan SELL (2 posisi, total 5+2=7)
input double InpRecoveryLot      = 0.03;   // Lot tetap recovery (0.03 lot)
input int    InpRecoveryFirstGap = 15000;  // Jarak recovery PERTAMA (15.000 pt = $15.00 Gold / rentang 10k-20k)
input int    InpRecoverySpacing  = 15000;  // Jarak antar layer recovery kelipatan (15.000 pt = $15.00)
input bool   InpRecoveryNeedSR   = false;  // false = jarak murni kelipatan (tanpa nunggu zona S/R)

input group "=== RECOVERY: Take Profit ==="
input int    InpRecTPMode        = 0;      // 0=per posisi | 1=ke area nyangkut (avg grid utama) | 2=basket breakeven
input int    InpRecTPBufferPts   = 3000;   // Mode 1: tutup recovery SEBELUM avg grid utama, sebanyak ini (pts; $3)
input double InpBasketTargetUSD  = 0.0;    // Mode 2: tutup SEMUA (utama+recovery) kalau total floating >= $ ini

input group "=== INVEST HODL / Macro Runner (v6.2) ==="
input bool   InpInvestOn          = true;    // Aktifkan tabungan invest HODL
input double InpInvestLot         = 0.10;    // Lot posisi invest HODL (0.10 cent)
input int    InpInvestMaxPos      = 1;       // Maksimal posisi invest (1 posisi tunggal HODL)
input int    InpInvestStepPoints  = 5000;    // Jarak tambah posisi invest (pts; 5000-10000 = $5-$10)
input int    InpInvestTPPoints    = 0;       // Target TP posisi invest (0 = TANPA TP, Pure HODL Abadi)
input bool   InpInvestTrailBEP    = false;   // false = TANPA SL/BEP (Murni Buy & Hold Jangka Panjang)
input int    InpInvestBEPTrigger  = 10000;   // Trigger kunci BEP (pts; 10000 = $10 profit)
input int    InpInvestBEPBuffer   = 1000;    // Buffer kunci profit BEP (pts; 1000 = $1 profit)
input string InpInvestComment     = "GINVEST62"; // Comment posisi invest

input group "=== Proteksi ==="
input double InpKillEquityPct= 30.0;   // Kill kalau equity <= ini % dari peak (30 = rugi 70%)
input bool   InpKillReset    = true;   // Setelah kill: tutup semua -> reset -> mulai lagi (bukan stop)
input int    InpKillCooldownMin = 15;  // Jeda (menit) setelah kill sebelum entry lagi
input int    InpMaxSpreadPts = 600;    // Skip buka posisi kalau spread > ini

input group "=== Umum ==="
input long   InpMagic        = 27270062;
input int    InpSlippage     = 30;
input string InpComment      = "GSCALP62";

input group "=== Dashboard ==="
input bool   InpShowDashboard = true;
input int    InpDashX         = 14;
input int    InpDashY         = 26;
input int    InpDashFont      = 9;
input string InpDashFontName  = "Consolas";
input color  InpColBg         = C'20,24,32';
input color  InpColText       = clrGainsboro;
input color  InpColHeader     = clrDeepSkyBlue;
input color  InpColProfit     = C'0,220,120';
input color  InpColLoss       = C'255,80,80';
input color  InpColWarn       = clrGold;

//==================================================================
CTrade   trade;
CCanvas  g_canvas;
bool     g_canvasOK = false;
double   g_point;
int      g_digits;
double   g_peakEquity = 0.0;
double   g_dayStartEquity = 0.0;
datetime g_curDay = 0;
bool     g_dead = false;
datetime g_killUntil = 0;      // cooldown pasca kill-reset
int      g_killCount = 0;
string   g_state = "mulai";
datetime g_lastTPBuyTime  = 0;   // Timestamp TP terakhir arah BUY (delay anti-nyangkut)
datetime g_lastTPSellTime = 0;   // Timestamp TP terakhir arah SELL (delay anti-nyangkut)
string   RCOM;                 // komentar posisi recovery
string   ICOM;                 // komentar posisi invest HODL
int      g_rsiHandle = INVALID_HANDLE;         // Handle indikator RSI

string   PREFIX;
const int NLINES  = 62;
const int PANEL_W = 300;
const int CHART_H = 116;
int      g_x0, g_y0, g_lineH, g_ln;

struct Stats { int trades,wins,losses; double grossProfit,grossLoss,best,worst; int streak; };
Stats    g_all, g_today;
double   g_curveVal[];
datetime g_curveTime[];
#define  MAX_CURVE 600

//==================================================================
int OnInit()
{
   if(!ValidateDigitalnusaLicense("Raja_Emas_v6.2"))
   {
      ExpertRemove();
      return(INIT_FAILED);
   }

   PREFIX = "GSCP6_" + IntegerToString((int)ChartID()) + "_";
   RCOM   = InpComment + "R";
   ICOM   = InpInvestComment;
   if(InpUseRSIFilter)
   {
      g_rsiHandle = iRSI(_Symbol, InpRSI_TF, InpRSIPeriod, PRICE_CLOSE);
   }
   g_point  = _Point;
   g_digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   trade.SetExpertMagicNumber((ulong)InpMagic);
   trade.SetDeviationInPoints(InpSlippage);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.LogLevel(LOG_LEVEL_ERRORS);

   g_peakEquity     = AccountInfoDouble(ACCOUNT_EQUITY);
   g_curDay         = DayStart(TimeCurrent());
   RebuildStats();
   g_dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY) - (g_today.grossProfit + g_today.grossLoss);
   if(g_dayStartEquity <= 0.0) g_dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);

   g_lineH = InpDashFont + 7;
   g_x0 = InpDashX; g_y0 = InpDashY;
   if(DashboardVisible()) { CreateDashboard(); EventSetTimer(1); UpdateDashboard(); }

   PrintFormat("=== GridScalp v6.2 (Invest HODL + Scalper) START === %s grid=%d Buy=%d Sell=%d | RECOVERY MaxBuy=%d MaxSell=%d gap1=%d space=%d | needZone=%s",
               _Symbol, InpGridPoints, InpMaxBuy, InpMaxSell,
               InpRecoveryMaxBuy, InpRecoveryMaxSell, InpRecoveryFirstGap, InpRecoverySpacing,
               (InpRecoveryNeedSR ? "YA" : "TIDAK"));
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   if(g_rsiHandle != INVALID_HANDLE)
   {
      IndicatorRelease(g_rsiHandle);
      g_rsiHandle = INVALID_HANDLE;
   }
   g_canvas.Destroy();
   ObjectsDeleteAll(0, PREFIX);
   Comment("");
}

void OnTimer() { UpdateDashboard(); }

void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
{
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD) { RebuildStats(); UpdateDashboard(); }
}

//==================================================================
int CountSide(int type)
{
   int c = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(PositionSelectByTicket(tk) &&
         PositionGetInteger(POSITION_MAGIC) == InpMagic &&
         PositionGetString(POSITION_SYMBOL) == _Symbol &&
         (int)PositionGetInteger(POSITION_TYPE) == type)
         c++;
   }
   return c;
}
int CountAll() { return CountSide(POSITION_TYPE_BUY) + CountSide(POSITION_TYPE_SELL); }

// hitung posisi per arah, filter recovery / bukan
int CountTag(int type, int tagMode) // 0=main scalp, 1=recovery, 2=invest
{
   int c = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(!PositionSelectByTicket(tk)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((int)PositionGetInteger(POSITION_TYPE) != type) continue;
      string com = PositionGetString(POSITION_COMMENT);
      bool isR = (StringFind(com, RCOM) >= 0);
      bool isI = (StringFind(com, ICOM) >= 0);
      if(tagMode == 0 && !isR && !isI) c++;
      else if(tagMode == 1 && isR) c++;
      else if(tagMode == 2 && isI) c++;
   }
   return c;
}
int CountRec(int type)    { return CountTag(type, 1); }
int CountMain(int type)   { return CountTag(type, 0); }
int CountInvest()         { return CountTag(POSITION_TYPE_BUY, 2); }

double InvestLowestEntry()
{
   double lowest = DBL_MAX;
   bool found = false;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(!PositionSelectByTicket(tk)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(StringFind(PositionGetString(POSITION_COMMENT), ICOM) < 0) continue;
      double op = PositionGetDouble(POSITION_PRICE_OPEN);
      if(op < lowest) lowest = op;
      found = true;
   }
   return found ? lowest : 0.0;
}

double InvestFloating()
{
   double f = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(!PositionSelectByTicket(tk)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(StringFind(PositionGetString(POSITION_COMMENT), ICOM) < 0) continue;
      f += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   }
   return f;
}

// entry recovery paling ekstrem: BUY = terendah, SELL = tertinggi
double RecEdge(int type)
{
   double edge = (type == POSITION_TYPE_BUY) ? DBL_MAX : 0.0;
   bool found = false;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(!PositionSelectByTicket(tk)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((int)PositionGetInteger(POSITION_TYPE) != type) continue;
      if(StringFind(PositionGetString(POSITION_COMMENT), RCOM) < 0) continue;
      double op = PositionGetDouble(POSITION_PRICE_OPEN);
      if(type == POSITION_TYPE_BUY) { if(op < edge) edge = op; }
      else                          { if(op > edge) edge = op; }
      found = true;
   }
   return found ? edge : 0.0;
}

double EdgeEntry(int type)
{
   double edge = (type == POSITION_TYPE_BUY) ? DBL_MAX : 0.0;
   bool found = false;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(PositionSelectByTicket(tk) &&
         PositionGetInteger(POSITION_MAGIC) == InpMagic &&
         PositionGetString(POSITION_SYMBOL) == _Symbol &&
         (int)PositionGetInteger(POSITION_TYPE) == type)
      {
         string com = PositionGetString(POSITION_COMMENT);
         if(StringFind(com, RCOM) >= 0 || StringFind(com, ICOM) >= 0) continue; // hanya grid utama
         double op = PositionGetDouble(POSITION_PRICE_OPEN);
         if(type == POSITION_TYPE_BUY)  { if(op < edge) edge = op; }
         else                           { if(op > edge) edge = op; }
         found = true;
      }
   }
   return found ? edge : 0.0;
}

double CurrentFloating()
{
   double f = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(PositionSelectByTicket(tk) &&
         PositionGetInteger(POSITION_MAGIC) == InpMagic &&
         PositionGetString(POSITION_SYMBOL) == _Symbol)
         f += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   }
   return f;
}
double MyLots()
{
   double v = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(PositionSelectByTicket(tk) &&
         PositionGetInteger(POSITION_MAGIC) == InpMagic &&
         PositionGetString(POSITION_SYMBOL) == _Symbol)
         v += PositionGetDouble(POSITION_VOLUME);
   }
   return v;
}

void CloseWinners()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double tp  = EffTP() * g_point;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(!PositionSelectByTicket(tk)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      string _com = PositionGetString(POSITION_COMMENT);
      if(StringFind(_com, ICOM) >= 0) continue;  // posisi INVEST HODL TIDAK BOLEH ditutup scalp TP!
      bool isR = (StringFind(_com, RCOM) >= 0);
      if(isR && InpRecTPMode != 0) continue;    // recovery pakai TP mode sendiri
      int    type = (int)PositionGetInteger(POSITION_TYPE);
      double op   = PositionGetDouble(POSITION_PRICE_OPEN);
      double prof = (type == POSITION_TYPE_BUY) ? (bid - op) : (op - ask);
      if(prof >= tp)
      {
         if(trade.PositionClose(tk))
         {
            if(type == POSITION_TYPE_BUY)
            {
               g_lastTPBuyTime = TimeCurrent();
               PrintFormat("✅ [v6.2 TP GRID] BUY #%I64u ditutup TP (+%.1f pt). Jeda entry baru %d detik.", tk, prof/g_point, InpEntryDelayAfterTPSec);
            }
            else
            {
               g_lastTPSellTime = TimeCurrent();
               PrintFormat("✅ [v6.2 TP GRID] SELL #%I64u ditutup TP (+%.1f pt). Jeda entry baru %d detik.", tk, prof/g_point, InpEntryDelayAfterTPSec);
            }
         }
      }
   }
}

void CloseAll()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(PositionSelectByTicket(tk) &&
         PositionGetInteger(POSITION_MAGIC) == InpMagic &&
         PositionGetString(POSITION_SYMBOL) == _Symbol)
         trade.PositionClose(tk);
   }
}

// tutup semua posisi recovery satu arah
void CloseRec(int type)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(!PositionSelectByTicket(tk)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((int)PositionGetInteger(POSITION_TYPE) != type) continue;
      if(StringFind(PositionGetString(POSITION_COMMENT), RCOM) < 0) continue;
      trade.PositionClose(tk);
   }
}

// harga rata-rata (volume-weighted) posisi GRID UTAMA satu arah
double MainAvgEntry(int type)
{
   double vsum = 0.0, wsum = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(!PositionSelectByTicket(tk)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((int)PositionGetInteger(POSITION_TYPE) != type) continue;
      if(StringFind(PositionGetString(POSITION_COMMENT), RCOM) >= 0) continue;   // hanya utama
      double v = PositionGetDouble(POSITION_VOLUME);
      vsum += PositionGetDouble(POSITION_PRICE_OPEN) * v;
      wsum += v;
   }
   return (wsum > 0.0) ? vsum / wsum : 0.0;
}

// TP untuk batch recovery (dipanggil tiap tick)
void RecoveryTP()
{
   if(InpRecTPMode == 0) return;   // per-posisi -> ditangani CloseWinners

   int rBuy = CountRec(POSITION_TYPE_BUY), rSell = CountRec(POSITION_TYPE_SELL);
   if(rBuy == 0 && rSell == 0) return;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   if(InpRecTPMode == 2)
   {
      // basket breakeven: total floating (utama + recovery) >= target -> tutup SEMUA
      if(CurrentFloating() >= InpBasketTargetUSD && (rBuy > 0 || rSell > 0))
      {
         PrintFormat("### RECOVERY TP mode2: floating %.2f >= %.2f -> tutup SEMUA ###", CurrentFloating(), InpBasketTargetUSD);
         CloseAll();
      }
      return;
   }

   // mode 1: tutup semua recovery pas harga balik ke deket avg grid utama
   double buf = InpRecTPBufferPts * g_point;
   if(rBuy > 0)
   {
      double avg = MainAvgEntry(POSITION_TYPE_BUY);
      if(avg > 0.0 && bid >= avg - buf)
      { PrintFormat("### RECOVERY BUY TP: bid %.3f >= avg %.3f - buf -> tutup %d recovery ###", bid, avg, rBuy); CloseRec(POSITION_TYPE_BUY); }
   }
   if(rSell > 0)
   {
      double avg = MainAvgEntry(POSITION_TYPE_SELL);
      if(avg > 0.0 && ask <= avg + buf)
      { PrintFormat("### RECOVERY SELL TP: ask %.3f <= avg %.3f + buf -> tutup %d recovery ###", ask, avg, rSell); CloseRec(POSITION_TYPE_SELL); }
   }
}

//==================================================================
//  STOP LOSS ENFORCER (30 CENT KETAT - SL GUARD)
//==================================================================
void EnforceStopLoss()
{
   if(InpMaxLossCent <= 0.0) return;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(!PositionSelectByTicket(tk)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      long magic = PositionGetInteger(POSITION_MAGIC);
      if(magic != InpMagic && magic != 0) continue;

      string com = PositionGetString(POSITION_COMMENT);
      if(StringFind(com, ICOM) >= 0) continue; // Pure Invest 0.10 runner tidak di-cut scalp SL

      int type = (int)PositionGetInteger(POSITION_TYPE);
      double vol = PositionGetDouble(POSITION_VOLUME);
      double op = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      double pl = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);

      double deltaPts = (vol > 0.0) ? (InpMaxLossCent / (vol * 100.0)) : 10.0;

      if(type == POSITION_TYPE_SELL)
      {
         double idealSL = NormalizeDouble(op + deltaPts, _Digits);
         if((sl == 0.0 || MathAbs(sl - idealSL) > 0.05) && ask < idealSL)
         {
            trade.PositionModify(tk, idealSL, tp);
         }
         if(pl <= -InpMaxLossCent)
         {
            trade.PositionClose(tk);
         }
      }
      else if(type == POSITION_TYPE_BUY)
      {
         if(op > 4250.0) continue;
         double idealSL = NormalizeDouble(op - deltaPts, _Digits);
         if((sl == 0.0 || MathAbs(sl - idealSL) > 0.05) && bid > idealSL)
         {
            trade.PositionModify(tk, idealSL, tp);
         }
         if(pl <= -InpMaxLossCent)
         {
            trade.PositionClose(tk);
         }
      }
   }
}

bool SpreadOK()
{
   double sp = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / g_point;
   return (InpMaxSpreadPts <= 0 || sp <= InpMaxSpreadPts);
}
datetime DayStart(datetime t) { return (t - (t % 86400)); }

// TP efektif: minimal (spread + buffer) biar menang > biaya
double EffTP()
{
   double sp = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / g_point;
   return MathMax((double)InpTPPoints, sp + InpTPBufferPts);
}

//------- Support / Resistance (dari candle TF rendah) -------
double SRResistance()
{
   int i = iHighest(_Symbol, InpSRTimeframe, MODE_HIGH, InpSRLookback, 1);
   return (i < 0) ? 0.0 : iHigh(_Symbol, InpSRTimeframe, i);
}
double SRSupport()
{
   int i = iLowest(_Symbol, InpSRTimeframe, MODE_LOW, InpSRLookback, 1);
   return (i < 0) ? 0.0 : iLow(_Symbol, InpSRTimeframe, i);
}
double DistRes() { double r = SRResistance(); double b = SymbolInfoDouble(_Symbol, SYMBOL_BID); return (r <= 0) ? 1e9 : (r - b) / g_point; }
double DistSup() { double s = SRSupport();    double b = SymbolInfoDouble(_Symbol, SYMBOL_BID); return (s <= 0) ? 1e9 : (b - s) / g_point; }
bool NearRes() { double d = DistRes(); return (d <= InpSRTolerancePts && d >= -InpSRTolerancePts); }
bool NearSup() { double d = DistSup(); return (d <= InpSRTolerancePts && d >= -InpSRTolerancePts); }

//------- FAIR VALUE GAP (imbalance 3-candle) di InpZoneTF -------
// FVG bull: low[i] > high[i+2]  -> zona [high[i+2] .. low[i]]. Belum ke-fill = harga blm turun ke bawah zona.
bool NearFvgBull()
{
   double tol = InpZoneTolPts * g_point;
   double px  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   for(int i = 1; i <= InpZoneLookback - 2; i++)
   {
      double loI  = iLow(_Symbol, InpZoneTF, i);
      double hiI2 = iHigh(_Symbol, InpZoneTF, i + 2);
      if(loI <= hiI2) continue;
      double zBot = hiI2, zTop = loI;
      bool filled = false;
      for(int k = 1; k < i; k++) if(iLow(_Symbol, InpZoneTF, k) < zBot) { filled = true; break; }
      if(filled) continue;
      if(px <= zTop + tol && px >= zBot - tol) return true;
   }
   return false;
}
// FVG bear: high[i] < low[i+2] -> zona [high[i] .. low[i+2]]
bool NearFvgBear()
{
   double tol = InpZoneTolPts * g_point;
   double px  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   for(int i = 1; i <= InpZoneLookback - 2; i++)
   {
      double hiI  = iHigh(_Symbol, InpZoneTF, i);
      double loI2 = iLow(_Symbol, InpZoneTF, i + 2);
      if(hiI >= loI2) continue;
      double zBot = hiI, zTop = loI2;
      bool filled = false;
      for(int k = 1; k < i; k++) if(iHigh(_Symbol, InpZoneTF, k) > zTop) { filled = true; break; }
      if(filled) continue;
      if(px <= zTop + tol && px >= zBot - tol) return true;
   }
   return false;
}

//------- ORDER BLOCK (sederhana) di InpZoneTF -------
// OB bull: candle bearish, lalu candle berikutnya bullish & close > high candle bearish.
//          zona = low..high candle bearish. Belum di-mitigasi = harga blm turun ke bawah low-nya.
bool NearObBull()
{
   double tol = InpZoneTolPts * g_point;
   double px  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   for(int i = 2; i <= InpZoneLookback; i++)
   {
      double o = iOpen(_Symbol, InpZoneTF, i), c = iClose(_Symbol, InpZoneTF, i);
      if(c >= o) continue;
      double h = iHigh(_Symbol, InpZoneTF, i), l = iLow(_Symbol, InpZoneTF, i);
      double o1 = iOpen(_Symbol, InpZoneTF, i - 1), c1 = iClose(_Symbol, InpZoneTF, i - 1);
      if(!(c1 > o1 && c1 > h)) continue;
      bool mit = false;
      for(int k = 1; k < i - 1; k++) if(iLow(_Symbol, InpZoneTF, k) < l) { mit = true; break; }
      if(mit) continue;
      if(px <= h + tol && px >= l - tol) return true;
   }
   return false;
}
bool NearObBear()
{
   double tol = InpZoneTolPts * g_point;
   double px  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   for(int i = 2; i <= InpZoneLookback; i++)
   {
      double o = iOpen(_Symbol, InpZoneTF, i), c = iClose(_Symbol, InpZoneTF, i);
      if(c <= o) continue;
      double h = iHigh(_Symbol, InpZoneTF, i), l = iLow(_Symbol, InpZoneTF, i);
      double o1 = iOpen(_Symbol, InpZoneTF, i - 1), c1 = iClose(_Symbol, InpZoneTF, i - 1);
      if(!(c1 < o1 && c1 < l)) continue;
      bool mit = false;
      for(int k = 1; k < i - 1; k++) if(iHigh(_Symbol, InpZoneTF, k) > h) { mit = true; break; }
      if(mit) continue;
      if(px <= h + tol && px >= l - tol) return true;
   }
   return false;
}

// gabungan: harga di zona buat recovery BUY / SELL ?
bool ZoneBull()
{
   if(!InpRecoveryNeedSR) return true;
   bool sr = NearSup(), fvg = NearFvgBull(), ob = NearObBull();
   if(InpRecoveryZone == 0) return sr;
   if(InpRecoveryZone == 1) return fvg;
   if(InpRecoveryZone == 2) return ob;
   return (sr || fvg || ob);
}
bool ZoneBear()
{
   if(!InpRecoveryNeedSR) return true;
   bool sr = NearRes(), fvg = NearFvgBear(), ob = NearObBear();
   if(InpRecoveryZone == 0) return sr;
   if(InpRecoveryZone == 1) return fvg;
   if(InpRecoveryZone == 2) return ob;
   return (sr || fvg || ob);
}
string ZoneText(int dir)
{
   if(!InpRecoveryNeedSR) return "off (jarak doang)";
   string s = "";
   if(dir > 0) { if(NearSup()) s += "S/R "; if(NearFvgBull()) s += "FVG "; if(NearObBull()) s += "OB "; }
   else        { if(NearRes()) s += "S/R "; if(NearFvgBear()) s += "FVG "; if(NearObBear()) s += "OB "; }
   return (s == "" ? "belum di zona" : "DI ZONA: " + s);
}

//==================================================================

//==================================================================
// MANAJEMEN INVEST HODL (v6.2)
//==================================================================

double GetCurrentRSI()
{
   if(!InpUseRSIFilter) return 50.0;
   if(g_rsiHandle == INVALID_HANDLE)
      g_rsiHandle = iRSI(_Symbol, InpRSI_TF, InpRSIPeriod, PRICE_CLOSE);
   if(g_rsiHandle == INVALID_HANDLE) return 50.0;
   double rsiVal[];
   ArraySetAsSeries(rsiVal, true);
   if(CopyBuffer(g_rsiHandle, 0, 0, 1, rsiVal) <= 0) return 50.0;
   return rsiVal[0];
}



void ManageInvestPositions()
{
   if(!InpInvestOn) return;

   int nInv = CountInvest();
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // 1. Eksekusi Entry Invest Baru (HARD SAFETY CLAMP: HANYA 1 POSISI TUNGGAL HODL)
   if(nInv < 1 && SpreadOK())
   {
      if(nInv == 0)
      {
         // Buka Invest BUY #1 pertama (HANYA 1 POSISI TUNGGAL YANG DIIZINKAN)
         if(trade.Buy(InpInvestLot, _Symbol, 0.0, 0.0, 0.0, ICOM))
         {
            PrintFormat("💎 [v6.2 INVEST] Sukses buka Invest BUY #1 lot %.2f @ %.3f (HODL Jangka Panjang)", InpInvestLot, ask);
         }
      }
   }

   // 2. Monitoring Take Profit Raksasa & Trailing BEP Lock
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(!PositionSelectByTicket(tk)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(StringFind(PositionGetString(POSITION_COMMENT), ICOM) < 0) continue;

      double op = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);

      // Take Profit Makro (jika diset > 0)
      if(InpInvestTPPoints > 0 && bid >= op + InpInvestTPPoints * g_point)
      {
         trade.PositionClose(tk);
         PrintFormat("💎🏆 [v6.2 INVEST TP] Posisi Invest #%I64u panen TP raksasa @ %.3f (+%d pt)!", tk, bid, InpInvestTPPoints);
         continue;
      }

      // Kunci BEP + Trailing jika profit >= InpInvestBEPTrigger
      if(InpInvestTrailBEP && bid >= op + InpInvestBEPTrigger * g_point)
      {
         double newSL = op + InpInvestBEPBuffer * g_point;
         double minStopLevel = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * g_point;
         if(minStopLevel < 100 * g_point) minStopLevel = 100 * g_point;

         // Pastikan newSL strictly valid di bawah bid (SL BUY harus < bid - stop_level)
         if(newSL > bid - minStopLevel) newSL = bid - minStopLevel;

         if(newSL > op && sl < newSL)
         {
            if(trade.PositionModify(tk, newSL, 0.0))
            {
               PrintFormat("🛡️ [v6.2 INVEST BEP] Kunci BEP Posisi Invest #%I64u ke %.3f (Bebas Risiko)!", tk, newSL);
            }
         }
      }
   }
}

void OnTick()
{
   // ---- PERIODIC CLOUD LICENSE CHECK ----
   if(TimeCurrent() - g_lastCheckTime > 3600)
   {
      if(!ValidateDigitalnusaLicense("Raja_Emas_v6.2"))
      {
         ExpertRemove();
         return;
      }
   }

   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq > g_peakEquity) g_peakEquity = eq;

   datetime d = DayStart(TimeCurrent());
   if(d != g_curDay) { g_curDay = d; g_dayStartEquity = eq; RebuildStats(); }

   if(g_dead) { g_state = "EA OFF (kill-switch, reset OFF)"; UpdateDashboard(); return; }

   // ---- KILL-SWITCH ----
   if(g_peakEquity > 0.0 && eq <= g_peakEquity * InpKillEquityPct / 100.0)
   {
      g_killCount++;
      CloseAll();
      if(InpKillReset)
      {
         g_peakEquity = AccountInfoDouble(ACCOUNT_EQUITY);
         g_killUntil  = TimeCurrent() + InpKillCooldownMin * 60;
         g_state = StringFormat("KILL #%d -> reset, cooldown %d mnt", g_killCount, InpKillCooldownMin);
         PrintFormat("### KILL-SWITCH #%d: eq %.2f <= %.0f%% peak -> tutup semua, RESET, mulai lagi ###",
                     g_killCount, eq, InpKillEquityPct);
      }
      else
      {
         g_dead = true;
         g_state = StringFormat("KILL-SWITCH eq %.2f <= %.0f%% peak -> STOP", eq, InpKillEquityPct);
         PrintFormat("### %s ###", g_state);
      }
      UpdateDashboard();
      return;
   }

   CloseWinners();
   ManageInvestPositions();
   RecoveryTP();
   EnforceStopLoss();

   if(TimeCurrent() < g_killUntil)
   { g_state = StringFormat("cooldown pasca-kill (%d dtk)", (int)(g_killUntil - TimeCurrent())); UpdateDashboard(); return; }
   if(!SpreadOK()) { g_state = "spread lebar - tunggu"; UpdateDashboard(); return; }

   int totAll = CountAll();
   if(InpMaxPositions > 0 && totAll >= InpMaxPositions)
   { g_state = StringFormat("maks posisi (%d) - tunggu TP", InpMaxPositions); UpdateDashboard(); return; }

   double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double grid = InpGridPoints * g_point;
   int  capTot = (InpMaxPositions > 0 ? InpMaxPositions : 99999);

   int mBuy  = CountMain(POSITION_TYPE_BUY);
   int mSell = CountMain(POSITION_TYPE_SELL);

   // ================= GRID UTAMA (v5-style: TANPA filter S/R) =================
   g_state = StringFormat("grid: B%d/%d S%d/%d", mBuy, InpMaxBuy, mSell, InpMaxSell);

   // BUY grid (Batas InpMaxBuy = 10)
   if(mBuy < InpMaxBuy && CountAll() < capTot)
   {
      bool delayBuyOK = (InpEntryDelayAfterTPSec <= 0) || (g_lastTPBuyTime == 0) || ((TimeCurrent() - g_lastTPBuyTime) >= InpEntryDelayAfterTPSec);
      if(!delayBuyOK)
      {
         int remainBuy = (int)(InpEntryDelayAfterTPSec - (TimeCurrent() - g_lastTPBuyTime));
         g_state = StringFormat("Jeda Anti-Nyangkut BUY: %ds pasca-TP", remainBuy);
      }
      else
      {
         double tpBuyVal = NormalizeDouble(ask + EffTP() * g_point, _Digits);
         if(mBuy == 0)
         { if(trade.Buy(InpLot, _Symbol, 0.0, 0.0, tpBuyVal, InpComment)) g_state = "buka BUY #1"; }
         else
         {
            double lowEntry = EdgeEntry(POSITION_TYPE_BUY);
            if(lowEntry > 0.0 && ask <= lowEntry - grid)
               if(trade.Buy(InpLot, _Symbol, 0.0, 0.0, tpBuyVal, InpComment)) g_state = StringFormat("tambah BUY #%d", mBuy + 1);
         }
      }
   }

   // SELL grid (KUNCI KETAT: MAX 5 POSISI & TOTAL MAX 7 POSISI & FILTER RSI & SL 30 CENT)
   int totSellNow = mSell + CountRec(POSITION_TYPE_SELL);
   if(InpBothSides && mSell < InpMaxSell && totSellNow < InpTotalMaxSell && CountAll() < capTot)
   {
      double curRSI = GetCurrentRSI();
      bool rsiSellOK = (!InpUseRSIFilter) || (curRSI > InpRSIOversoldLimit);

      if(!rsiSellOK)
      {
         g_state = StringFormat("RSI M15 %.1f <= %.0f (Oversold Lembah) - Dilarang Buka SELL", curRSI, InpRSIOversoldLimit);
      }
      else
      {
         bool delaySellOK = (InpEntryDelayAfterTPSec <= 0) || (g_lastTPSellTime == 0) || ((TimeCurrent() - g_lastTPSellTime) >= InpEntryDelayAfterTPSec);
         if(!delaySellOK)
         {
            int remainSell = (int)(InpEntryDelayAfterTPSec - (TimeCurrent() - g_lastTPSellTime));
            g_state = StringFormat("Jeda Anti-Nyangkut SELL: %ds pasca-TP", remainSell);
         }
         else
         {
            double tpSellVal = NormalizeDouble(bid - EffTP() * g_point, _Digits);
            double slSellDist = (InpLot > 0.0 && InpMaxLossCent > 0.0) ? (InpMaxLossCent / (InpLot * 100.0)) : 0.0;
            double slSellVal = (slSellDist > 0.0) ? NormalizeDouble(ask + slSellDist, _Digits) : 0.0;
            if(mSell == 0)
            { if(trade.Sell(InpLot, _Symbol, 0.0, slSellVal, tpSellVal, InpComment)) g_state = "buka SELL #1 (SL 30c)"; }
            else
            {
               double highEntry = EdgeEntry(POSITION_TYPE_SELL);
               if(highEntry > 0.0 && bid >= highEntry + grid)
                  if(trade.Sell(InpLot, _Symbol, 0.0, slSellVal, tpSellVal, InpComment)) g_state = StringFormat("tambah SELL #%d (SL 30c)", mSell + 1);
            }
         }
      }
   }

   // ================= RECOVERY BATCH (Tingkat 2) =================
   if(InpRecoveryOn)
   {
      // 1. RECOVERY BUY: Aktif jika BUY Utama penuh (mBuy >= InpMaxBuy) dan harga anjlok sejauh InpRecoveryFirstGap (10k-20k pt)
      if(mBuy >= InpMaxBuy)
      {
         int nRecBuy = CountRec(POSITION_TYPE_BUY);
         if(nRecBuy < InpRecoveryMaxBuy && (InpMaxPositions <= 0 || CountAll() < InpMaxPositions))
         {
            double mEdge = EdgeEntry(POSITION_TYPE_BUY);
            double firstGap = InpRecoveryFirstGap * g_point;
            double rspace   = InpRecoverySpacing  * g_point;
            bool go = false;
            if(nRecBuy == 0)
               go = (ask <= mEdge - firstGap);
            else
            {
               double rEdge = RecEdge(POSITION_TYPE_BUY);
               go = (ask <= rEdge - rspace);
            }
            bool delayBuyOK = (InpEntryDelayAfterTPSec <= 0) || (g_lastTPBuyTime == 0) || ((TimeCurrent() - g_lastTPBuyTime) >= InpEntryDelayAfterTPSec);
            if(go && delayBuyOK && (!InpRecoveryNeedSR || ZoneBull()))
            {
               double tpBuy = NormalizeDouble(ask + EffTP() * g_point, _Digits);
               if(trade.Buy(InpRecoveryLot, _Symbol, 0.0, 0.0, tpBuy, RCOM))
                  g_state = StringFormat("RECOVERY BUY #%d", nRecBuy + 1);
            }
         }
      }

      // 2. RECOVERY SELL: Aktif jika SELL Utama penuh (mSell >= InpMaxSell) dan harga melesat sejauh InpRecoveryFirstGap (10k-20k pt)
      if(mSell >= InpMaxSell)
      {
         int nRecSell = CountRec(POSITION_TYPE_SELL);
         int totSellAll = mSell + nRecSell;
         if(nRecSell < InpRecoveryMaxSell && totSellAll < InpTotalMaxSell && (InpMaxPositions <= 0 || CountAll() < InpMaxPositions))
         {
            double mEdge = EdgeEntry(POSITION_TYPE_SELL);
            double firstGap = InpRecoveryFirstGap * g_point;
            double rspace   = InpRecoverySpacing  * g_point;
            bool go = false;
            if(nRecSell == 0)
               go = (bid >= mEdge + firstGap);
            else
            {
               double rEdge = RecEdge(POSITION_TYPE_SELL);
               go = (bid >= rEdge + rspace);
            }
            bool delaySellOK = (InpEntryDelayAfterTPSec <= 0) || (g_lastTPSellTime == 0) || ((TimeCurrent() - g_lastTPSellTime) >= InpEntryDelayAfterTPSec);
            if(go && delaySellOK && (!InpRecoveryNeedSR || ZoneBear()))
            {
               double tpSell = NormalizeDouble(bid - EffTP() * g_point, _Digits);
               double slRecSellDist = (InpRecoveryLot > 0.0 && InpMaxLossCent > 0.0) ? (InpMaxLossCent / (InpRecoveryLot * 100.0)) : 0.0;
               double slRecSellVal = (slRecSellDist > 0.0) ? NormalizeDouble(ask + slRecSellDist, _Digits) : 0.0;
               if(trade.Sell(InpRecoveryLot, _Symbol, 0.0, slRecSellVal, tpSell, RCOM))
                  g_state = StringFormat("RECOVERY SELL #%d (SL 30c)", nRecSell + 1);
            }
         }
      }
   }

   UpdateDashboard();
}

//==================================================================
//  STATISTIK
//==================================================================
void ResetStats(Stats &s) { s.trades=0;s.wins=0;s.losses=0;s.grossProfit=0;s.grossLoss=0;s.best=0;s.worst=0;s.streak=0; }
void AccStat(Stats &s, double pl)
{
   s.trades++;
   if(pl >= 0.0) { s.wins++;   s.grossProfit += pl; s.streak = (s.streak >= 0) ? s.streak + 1 : 1; }
   else          { s.losses++; s.grossLoss   += pl; s.streak = (s.streak <= 0) ? s.streak - 1 : -1; }
   if(pl > s.best)  s.best  = pl;
   if(pl < s.worst) s.worst = pl;
}
void PushCurve(datetime t, double v)
{
   int n = ArraySize(g_curveVal);
   if(n >= MAX_CURVE) { ArrayRemove(g_curveVal, 0, 1); ArrayRemove(g_curveTime, 0, 1); n--; }
   ArrayResize(g_curveVal, n + 1); ArrayResize(g_curveTime, n + 1);
   g_curveVal[n] = v; g_curveTime[n] = t;
}
void RebuildStats()
{
   ResetStats(g_all); ResetStats(g_today);
   ArrayResize(g_curveVal, 0); ArrayResize(g_curveTime, 0);
   datetime todayStart = DayStart(TimeCurrent());
   if(!HistorySelect(0, TimeCurrent() + 86400)) return;
   double cum = 0.0;
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong tk = HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(tk, DEAL_MAGIC) != InpMagic) continue;
      if(HistoryDealGetString(tk, DEAL_SYMBOL) != _Symbol) continue;
      long entry = HistoryDealGetInteger(tk, DEAL_ENTRY);
      double pl = HistoryDealGetDouble(tk, DEAL_PROFIT) + HistoryDealGetDouble(tk, DEAL_SWAP) + HistoryDealGetDouble(tk, DEAL_COMMISSION);
      datetime dt = (datetime)HistoryDealGetInteger(tk, DEAL_TIME);
      cum += pl;
      if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT)
      {
         PushCurve(dt, cum);
         AccStat(g_all, pl);
         if(dt >= todayStart) AccStat(g_today, pl);
      }
   }
}
double NetAll()   { return g_all.grossProfit + g_all.grossLoss; }
double NetToday() { return g_today.grossProfit + g_today.grossLoss; }
double PF(const Stats &s) { if(s.grossLoss == 0.0) return (s.grossProfit > 0.0) ? 999.0 : 0.0; return s.grossProfit / MathAbs(s.grossLoss); }

//==================================================================
//  DASHBOARD
//==================================================================
string FmtMoney(double v)
{
   string sign = (v < -0.005) ? "-" : "+";
   double a = MathAbs(v);
   long ip = (long)MathFloor(a + 1e-7);
   int dec = (int)MathRound((a - (double)ip) * 100.0);
   if(dec >= 100) { ip++; dec -= 100; }
   string is = IntegerToString(ip), g = ""; int c = 0;
   for(int i = StringLen(is) - 1; i >= 0; i--)
   { g = StringSubstr(is, i, 1) + g; c++; if(c % 3 == 0 && i > 0) g = "," + g; }
   return sign + g + "." + (dec < 10 ? "0" : "") + IntegerToString(dec);
}
string Pct(double v) { return DoubleToString(v, 2) + "%"; }

void SetLabel(string name, int x, int y, string text, color clr)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetString(0, name, OBJPROP_FONT, InpDashFontName);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, InpDashFont);
   }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
}

void CreateDashboard()
{
   int panelH = NLINES * g_lineH + CHART_H + 22;
   string bg = PREFIX + "bg";
   if(ObjectFind(0, bg) < 0) ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, bg, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, bg, OBJPROP_XDISTANCE, g_x0 - 8);
   ObjectSetInteger(0, bg, OBJPROP_YDISTANCE, g_y0 - 8);
   ObjectSetInteger(0, bg, OBJPROP_XSIZE, PANEL_W);
   ObjectSetInteger(0, bg, OBJPROP_YSIZE, panelH);
   ObjectSetInteger(0, bg, OBJPROP_BGCOLOR, InpColBg);
   ObjectSetInteger(0, bg, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, bg, OBJPROP_COLOR, C'70,80,95');
   ObjectSetInteger(0, bg, OBJPROP_BACK, false);
   ObjectSetInteger(0, bg, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, bg, OBJPROP_HIDDEN, true);

   int cw = PANEL_W - 16, cx = g_x0, cy = g_y0 + NLINES * g_lineH + 6;
   ObjectDelete(0, PREFIX + "canvas");
   if(g_canvas.CreateBitmapLabel(PREFIX + "canvas", cx, cy, cw, CHART_H, COLOR_FORMAT_ARGB_NORMALIZE))
   { g_canvasOK = true; g_canvas.Erase(ColorToARGB(InpColBg, 255)); g_canvas.Update(); }
}

void PL(string txt, color c)
{
   if(g_ln >= NLINES) return;
   SetLabel(PREFIX + "L" + IntegerToString(g_ln), g_x0, g_y0 + g_ln * g_lineH, txt, c);
   g_ln++;
}
string Row(string k, string v) { return StringFormat("%-12s %s", k, v); }

bool DashboardVisible()
{
   if(!InpShowDashboard) return false;
   if(MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE)) return false;
   return true;
}

void UpdateDashboard()
{
   if(!DashboardVisible()) { DashboardComment(); return; }
   if(ObjectFind(0, PREFIX + "bg") < 0) CreateDashboard();

   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
   double fl  = CurrentFloating();
   double ml  = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   double ddP = (g_peakEquity > 0.0) ? (g_peakEquity - eq) / g_peakEquity * 100.0 : 0.0;
   double dEq = g_dayStartEquity > 0.0 ? g_dayStartEquity : eq;
   double dayTot = eq - dEq;
   double killPct = 100.0 - InpKillEquityPct;

   color cFl  = (fl >= 0.0) ? InpColProfit : InpColLoss;
   color cDay = (dayTot >= 0.0) ? InpColProfit : InpColLoss;
   color cAll = (NetAll() >= 0.0) ? InpColProfit : InpColLoss;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double sp  = (ask - bid) / g_point;
   int nBuy = CountSide(POSITION_TYPE_BUY);
   int nSell = CountSide(POSITION_TYPE_SELL);

   g_ln = 0;
   PL("  XAUUSD GRIDSCALP  v6.2  (INVEST HODL + SCALPER)", InpColHeader);
   PL(StringFormat("  %s  %s  %s", _Symbol, StringSubstr(EnumToString((ENUM_TIMEFRAMES)_Period), 7),
                   TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS)), InpColText);
   PL("------------------------------------", InpColText);

   PL("AKUN", InpColHeader);
   PL(Row("Balance",  FmtMoney(bal)), InpColText);
   PL(Row("Equity",   FmtMoney(eq)),  InpColText);
   PL(Row("Floating", FmtMoney(fl)),  cFl);
   PL(Row("Margin Lv", (ml > 0.0 ? DoubleToString(ml, 0) + "%" : "-")),
      (ml > 0.0 && ml < 200.0 ? InpColLoss : ml > 0.0 && ml < 500.0 ? InpColWarn : InpColText));
   PL(Row("Drawdown", Pct(ddP) + "  / kill " + Pct(killPct)),
      (ddP >= killPct * 0.6 ? InpColWarn : InpColText));
   PL("------------------------------------", InpColText);

   PL("HARI INI  " + TimeToString(g_curDay, TIME_DATE), InpColHeader);
   PL(Row("Realized", FmtMoney(NetToday())), (NetToday() >= 0.0 ? InpColProfit : InpColLoss));
   PL(Row("Total P/L", FmtMoney(dayTot)), cDay);
   PL(Row("Trades", StringFormat("%d   W:%d  L:%d", g_today.trades, g_today.wins, g_today.losses)), InpColText);
   PL(Row("Status", (g_dead ? "EA OFF" : "AKTIF")), (g_dead ? InpColLoss : InpColProfit));
   PL("------------------------------------", InpColText);

   PL("KESELURUHAN (sejak trade pertama)", InpColHeader);
   PL(Row("Net Profit", FmtMoney(NetAll())), cAll);
   PL(Row("Trades", StringFormat("%d   W:%d  L:%d", g_all.trades, g_all.wins, g_all.losses)), InpColText);
   PL(Row("Win rate", (g_all.trades > 0 ? Pct(100.0 * g_all.wins / g_all.trades) : "-")), InpColText);
   PL(Row("Profit Fac", (g_all.trades > 0 ? DoubleToString(PF(g_all), 2) : "-")),
      (g_all.trades > 0 && PF(g_all) < 1.0 ? InpColLoss : InpColText));
   PL(Row("Best/Worst", FmtMoney(g_all.best) + " / " + FmtMoney(g_all.worst)), InpColText);
   PL("------------------------------------", InpColText);

   int mB = CountMain(POSITION_TYPE_BUY),  mS = CountMain(POSITION_TYPE_SELL);
   int rB = CountRec(POSITION_TYPE_BUY),   rS = CountRec(POSITION_TYPE_SELL);

   PL("POSISI GRID UTAMA", InpColHeader);
   PL(Row("BUY", StringFormat("%d / %d", mB, InpMaxBuy)), (mB > 0 ? InpColProfit : InpColText));
   PL(Row("SELL (Kunci)", StringFormat("%d / %d", mS, InpMaxSell)), (mS > 0 ? InpColLoss : InpColText));
   if(InpUseRSIFilter)
   {
      double _r = GetCurrentRSI();
      string _rTxt = StringFormat("%.1f %s", _r, (_r <= InpRSIOversoldLimit ? "(Oversold Block)" : "Normal"));
      PL(Row("RSI M15", _rTxt), (_r <= InpRSIOversoldLimit ? InpColWarn : InpColText));
   }
   PL(Row("Total", StringFormat("%d / %s   (%.2f lot)", nBuy + nSell,
          (InpMaxPositions > 0 ? IntegerToString(InpMaxPositions) : "~"), MyLots())),
      (InpMaxPositions > 0 && nBuy + nSell >= InpMaxPositions ? InpColWarn : InpColText));
   PL("------------------------------------", InpColText);

      PL("------------------------------------", InpColText);
   PL("INVEST HODL (MACRO RUNNER)", InpColHeader);
   if(!InpInvestOn)
   {
      PL(Row("Status", "OFF"), InpColText);
   }
   else
   {
      int _nI = CountInvest();
      double _iLow = InvestLowestEntry();
      double _iFl = InvestFloating();
      color _cI = (_iFl >= 0.0) ? InpColProfit : InpColLoss;
      PL(Row("Posisi", StringFormat("%d / %d  (%.2f lot)", _nI, InpInvestMaxPos, _nI * InpInvestLot)), (_nI > 0 ? InpColProfit : InpColText));
      PL(Row("Floating", FmtMoney(_iFl)), _cI);
      if(_nI == 1 && _iLow > 0.0)
      {
         double _nxt = _iLow - InpInvestStepPoints * g_point;
         PL(Row("Next Buy #2", StringFormat("<= %.*f (-%d pt)", g_digits, _nxt, InpInvestStepPoints)), InpColWarn);
      }
      else if(_nI >= InpInvestMaxPos)
      {
         PL(Row("Alokasi", "PENUH (1/1) HODL!"), InpColProfit);
      }
      else
      {
         PL(Row("Status", "Standby / Buka Buy #1"), InpColText);
      }
      if(InpInvestTPPoints > 0)
         PL(Row("Target TP", StringFormat("+%d pt ($%.0f)", InpInvestTPPoints, InpInvestTPPoints*g_point)), InpColText);
   }
   PL("------------------------------------", InpColText);
   PL("RECOVERY BATCH (TINGKAT 2)", InpColHeader);
   {
      string rBuyStat = (mB >= InpMaxBuy) ? StringFormat("B%d/%d (Aktif)", rB, InpRecoveryMaxBuy) : "Standby (tunggu 10 BUY)";
      string rSellStat = (mS >= InpMaxSell) ? StringFormat("S%d/%d (Aktif)", rS, InpRecoveryMaxSell) : "Standby (tunggu 3 SELL)";
      PL(Row("Recovery BUY", rBuyStat), (mB >= InpMaxBuy ? InpColWarn : InpColText));
      PL(Row("Recovery SELL", rSellStat), (mS >= InpMaxSell ? InpColWarn : InpColText));
      PL(Row("Jeda Gap-1", StringFormat("%d pt ($%.1f)", InpRecoveryFirstGap, InpRecoveryFirstGap * g_point)), InpColText);
      PL(Row("Spacing", StringFormat("%d pt ($%.1f)", InpRecoverySpacing, InpRecoverySpacing * g_point)), InpColText);
      PL(Row("TP Tiap Posisi", StringFormat("+%d pt ($%.2f)", EffTP(), EffTP() * g_point)), InpColProfit);
   }
   PL("------------------------------------", InpColText);

   PL("S/R + ZONA", InpColHeader);
   {
      double _r = SRResistance(), _s = SRSupport();
      PL(Row("Resistance", StringFormat("%.*f  (%+.0f pt)%s", g_digits, _r, DistRes(), NearRes()?"  <<":"")),
         (NearRes() ? InpColLoss : InpColText));
      PL(Row("Support", StringFormat("%.*f  (%+.0f pt)%s", g_digits, _s, DistSup(), NearSup()?"  <<":"")),
         (NearSup() ? InpColProfit : InpColText));
      PL(Row("FVG "+StringSubstr(EnumToString(InpZoneTF),7),
             StringFormat("bull:%s  bear:%s", (NearFvgBull()?"YA":"-"), (NearFvgBear()?"YA":"-"))),
         ((NearFvgBull()||NearFvgBear()) ? InpColWarn : InpColText));
      PL(Row("OB "+StringSubstr(EnumToString(InpZoneTF),7),
             StringFormat("bull:%s  bear:%s", (NearObBull()?"YA":"-"), (NearObBear()?"YA":"-"))),
         ((NearObBull()||NearObBear()) ? InpColWarn : InpColText));
   }
   PL(Row("Spread", StringFormat("%.0f pt  %s", sp, (SpreadOK() ? "OK" : "TOLAK"))),
      (SpreadOK() ? InpColText : InpColWarn));
   PL(Row("TP efektif", StringFormat("%.0f pt = %.*f", EffTP(), g_digits, EffTP()*g_point)), InpColText);
   if(InpEntryDelayAfterTPSec > 0)
   {
      int remB = (g_lastTPBuyTime > 0) ? (int)MathMax(0, InpEntryDelayAfterTPSec - (TimeCurrent() - g_lastTPBuyTime)) : 0;
      int remS = (g_lastTPSellTime > 0) ? (int)MathMax(0, InpEntryDelayAfterTPSec - (TimeCurrent() - g_lastTPSellTime)) : 0;
      string dlyInfo = StringFormat("%ds | B:%ds S:%ds", InpEntryDelayAfterTPSec, remB, remS);
      PL(Row("Entry Delay", dlyInfo), (remB > 0 || remS > 0 ? InpColWarn : InpColText));
   }
   PL(Row("Kill", StringFormat("eq<=%.0f%% peak  reset:%s  x%d", InpKillEquityPct, (InpKillReset?"YA":"-"), g_killCount)),
      (g_killCount > 0 ? InpColWarn : InpColText));
   PL(Row("Status", g_state), InpColWarn);

   DrawEquityChart();
   ChartRedraw();
}

void DashboardComment()
{
   Comment(StringFormat("GridScalp v6 | Eq %s | Float %s | Net %s | Pos %d (B%d/S%d) | %s",
      FmtMoney(AccountInfoDouble(ACCOUNT_EQUITY)), FmtMoney(CurrentFloating()),
      FmtMoney(NetAll()), CountAll(), CountSide(POSITION_TYPE_BUY), CountSide(POSITION_TYPE_SELL),
      (g_dead ? "EA OFF" : g_state)));
}

int MapY(double v, double mn, double mx, int H, int pt, int pb)
{
   double f = (v - mn) / (mx - mn);
   return (int)MathRound((double)(H - pb) - f * (double)(H - pt - pb));
}

void DrawEquityChart()
{
   if(!g_canvasOK) return;
   int W = g_canvas.Width(), H = g_canvas.Height();
   g_canvas.Erase(ColorToARGB(InpColBg, 255));
   g_canvas.Rectangle(0, 0, W - 1, H - 1, ColorToARGB(C'70,80,95', 255));

   int n = ArraySize(g_curveVal);
   double live = NetAll() + CurrentFloating();
   int m = n + 2;
   double ys[]; ArrayResize(ys, m);
   ys[0] = 0.0;
   for(int i = 0; i < n; i++) ys[i + 1] = g_curveVal[i];
   ys[m - 1] = live;

   double mn = 0.0, mx = 0.0;
   for(int i = 0; i < m; i++) { mn = MathMin(mn, ys[i]); mx = MathMax(mx, ys[i]); }
   if(mx - mn < 1.0) { mx += 1.0; mn -= 1.0; }
   double pad = (mx - mn) * 0.12; mn -= pad; mx += pad;
   int padL = 3, padR = 3, padT = 16, padB = 4;

   int yz = MapY(0.0, mn, mx, H, padT, padB);
   g_canvas.LineHorizontal(padL, W - padR, yz, ColorToARGB(clrGray, 90));

   color lc = (live >= 0.0) ? InpColProfit : InpColLoss;
   for(int i = 0; i < m - 1; i++)
   {
      int x1 = padL + (int)((double)i / (m - 1) * (W - padL - padR));
      int x2 = padL + (int)((double)(i + 1) / (m - 1) * (W - padL - padR));
      int y1 = MapY(ys[i], mn, mx, H, padT, padB);
      int y2 = MapY(ys[i + 1], mn, mx, H, padT, padB);
      g_canvas.Line(x1, y1, x2, y2, ColorToARGB(lc, 255));
      g_canvas.Line(x1, y1 + 1, x2, y2 + 1, ColorToARGB(lc, 110));
   }
   int lx = padL + (W - padL - padR);
   int ly = MapY(live, mn, mx, H, padT, padB);
   g_canvas.FillCircle(lx - 2, ly, 3, ColorToARGB(lc, 255));

   g_canvas.FontSet(InpDashFontName, -InpDashFont * 10);
   g_canvas.TextOut(4, 3, "Kurva P/L (realized+floating):  " + FmtMoney(live), ColorToARGB(InpColText, 255));
   g_canvas.Update();
}
//+------------------------------------------------------------------+
