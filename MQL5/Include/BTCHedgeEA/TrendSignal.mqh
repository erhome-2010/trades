//+------------------------------------------------------------------+
//|                                                 TrendSignal.mqh |
//| Filtro de tendência multi-timeframe (EMA + RSI) e gatilho de    |
//| entrada por pullback, com filtro de volatilidade via ATR.       |
//+------------------------------------------------------------------+
#property strict

#include <BTCHedgeEA/Defines.mqh>

class CTrendSignal
  {
private:
   string   m_symbol;
   ENUM_TIMEFRAMES m_trendTF;
   ENUM_TIMEFRAMES m_entryTF;

   int      m_emaFastPeriod;
   int      m_emaSlowPeriod;
   int      m_rsiPeriod;
   double   m_rsiUpperNeutral;
   double   m_rsiLowerNeutral;
   int      m_atrPeriod;
   double   m_minAtrPoints;      // filtro de volatilidade mínima (em pontos) para evitar mercado morto

   int      m_hEmaFastTrend;
   int      m_hEmaSlowTrend;
   int      m_hEmaFastEntry;
   int      m_hRsiEntry;
   int      m_hAtrEntry;

   double GetBuffer(const int handle,const int shift)
     {
      double buf[];
      ArraySetAsSeries(buf, true);
      if(CopyBuffer(handle, 0, shift, 1, buf) <= 0)
         return EMPTY_VALUE;
      return buf[0];
     }

public:
   CTrendSignal(void)
     {
      m_hEmaFastTrend = INVALID_HANDLE;
      m_hEmaSlowTrend = INVALID_HANDLE;
      m_hEmaFastEntry = INVALID_HANDLE;
      m_hRsiEntry     = INVALID_HANDLE;
      m_hAtrEntry     = INVALID_HANDLE;
     }

   ~CTrendSignal(void)
     {
      Release();
     }

   bool Init(const string symbol,const ENUM_TIMEFRAMES trendTF,const ENUM_TIMEFRAMES entryTF,
             const int emaFastPeriod,const int emaSlowPeriod,const int rsiPeriod,
             const double rsiUpperNeutral,const double rsiLowerNeutral,
             const int atrPeriod,const double minAtrPoints)
     {
      m_symbol          = symbol;
      m_trendTF         = trendTF;
      m_entryTF         = entryTF;
      m_emaFastPeriod   = emaFastPeriod;
      m_emaSlowPeriod   = emaSlowPeriod;
      m_rsiPeriod       = rsiPeriod;
      m_rsiUpperNeutral = rsiUpperNeutral;
      m_rsiLowerNeutral = rsiLowerNeutral;
      m_atrPeriod       = atrPeriod;
      m_minAtrPoints    = minAtrPoints;

      m_hEmaFastTrend = iMA(m_symbol, m_trendTF, m_emaFastPeriod, 0, MODE_EMA, PRICE_CLOSE);
      m_hEmaSlowTrend = iMA(m_symbol, m_trendTF, m_emaSlowPeriod, 0, MODE_EMA, PRICE_CLOSE);
      m_hEmaFastEntry = iMA(m_symbol, m_entryTF, m_emaFastPeriod, 0, MODE_EMA, PRICE_CLOSE);
      m_hRsiEntry     = iRSI(m_symbol, m_entryTF, m_rsiPeriod, PRICE_CLOSE);
      m_hAtrEntry     = iATR(m_symbol, m_entryTF, m_atrPeriod);

      if(m_hEmaFastTrend == INVALID_HANDLE || m_hEmaSlowTrend == INVALID_HANDLE ||
         m_hEmaFastEntry == INVALID_HANDLE || m_hRsiEntry == INVALID_HANDLE ||
         m_hAtrEntry == INVALID_HANDLE)
        {
         Print("BTCHedgeEA: falha ao criar handles de indicadores");
         return false;
        }
      return true;
     }

   void Release(void)
     {
      if(m_hEmaFastTrend != INVALID_HANDLE) IndicatorRelease(m_hEmaFastTrend);
      if(m_hEmaSlowTrend != INVALID_HANDLE) IndicatorRelease(m_hEmaSlowTrend);
      if(m_hEmaFastEntry != INVALID_HANDLE) IndicatorRelease(m_hEmaFastEntry);
      if(m_hRsiEntry     != INVALID_HANDLE) IndicatorRelease(m_hRsiEntry);
      if(m_hAtrEntry      != INVALID_HANDLE) IndicatorRelease(m_hAtrEntry);
     }

   bool IsReady(void)
     {
      return BarsCalculated(m_hEmaFastTrend) > 2 && BarsCalculated(m_hEmaSlowTrend) > 2 &&
             BarsCalculated(m_hEmaFastEntry) > 2 && BarsCalculated(m_hRsiEntry) > 2 &&
             BarsCalculated(m_hAtrEntry) > 2;
     }

   // Tendência de fundo, calculada no timeframe maior (trendTF)
   ENUM_TREND_STATE GetTrend(void)
     {
      double fast = GetBuffer(m_hEmaFastTrend, 1);
      double slow = GetBuffer(m_hEmaSlowTrend, 1);
      if(fast == EMPTY_VALUE || slow == EMPTY_VALUE)
         return TREND_NONE;

      double diffPoints = (fast - slow) / SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      double minSeparation = 2.0; // pontos mínimos de separação para considerar tendência válida

      if(diffPoints > minSeparation)
         return TREND_UP;
      if(diffPoints < -minSeparation)
         return TREND_DOWN;
      return TREND_NONE;
     }

   double AtrPoints(void)
     {
      double atr = GetBuffer(m_hAtrEntry, 1);
      if(atr == EMPTY_VALUE)
         return 0.0;
      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      return (point > 0.0) ? atr / point : 0.0;
     }

   double AtrValue(void)
     {
      double atr = GetBuffer(m_hAtrEntry, 1);
      return (atr == EMPTY_VALUE) ? 0.0 : atr;
     }

   bool VolatilityOk(void)
     {
      if(m_minAtrPoints <= 0.0)
         return true;
      return AtrPoints() >= m_minAtrPoints;
     }

   // Entrada por pullback: no timeframe de entrada, preço cruza de volta a favor da
   // tendência dominante após afastar-se da EMA rápida, com RSI saindo da zona neutra
   // na direção do movimento (confirma retomada do impulso).
   int GetEntrySignal(void)
     {
      if(!IsReady() || !VolatilityOk())
         return 0;

      ENUM_TREND_STATE trend = GetTrend();
      if(trend == TREND_NONE)
         return 0;

      double emaEntry1 = GetBuffer(m_hEmaFastEntry, 1);
      double emaEntry2 = GetBuffer(m_hEmaFastEntry, 2);
      double rsi1       = GetBuffer(m_hRsiEntry, 1);
      double rsi2       = GetBuffer(m_hRsiEntry, 2);

      double close1 = iClose(m_symbol, m_entryTF, 1);
      double close2 = iClose(m_symbol, m_entryTF, 2);

      if(emaEntry1 == EMPTY_VALUE || rsi1 == EMPTY_VALUE || rsi2 == EMPTY_VALUE)
         return 0;

      if(trend == TREND_UP)
        {
         bool priceReclaimedEma = (close2 <= emaEntry2) && (close1 > emaEntry1);
         bool rsiTurningUp      = (rsi2 <= m_rsiLowerNeutral) && (rsi1 > rsi2);
         if(priceReclaimedEma && rsiTurningUp)
            return 1;
        }
      else if(trend == TREND_DOWN)
        {
         bool priceLostEma  = (close2 >= emaEntry2) && (close1 < emaEntry1);
         bool rsiTurningDown = (rsi2 >= m_rsiUpperNeutral) && (rsi1 < rsi2);
         if(priceLostEma && rsiTurningDown)
            return -1;
        }

      return 0;
     }
  };
