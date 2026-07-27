//+------------------------------------------------------------------+
//|                                                  ScalpSignal.mqh |
//| Sinal de scalping por reversao a media (Bandas de Bollinger +   |
//| RSI), avaliado uma vez por barra fechada do timeframe de        |
//| entrada (M1/M5 por padrao) - gera sinais com muito mais         |
//| frequencia que o TrendSignal (que so reavalia por hora em H1).  |
//+------------------------------------------------------------------+
#property strict

#include <BTCHedgeEA/Defines.mqh>

class CScalpSignal
  {
private:
   string          m_symbol;
   ENUM_TIMEFRAMES m_tf;
   int             m_bbPeriod;
   double          m_bbDeviation;
   int             m_rsiPeriod;
   double          m_rsiOversold;
   double          m_rsiOverbought;
   int             m_atrPeriod;

   bool            m_useTrendFilter;
   ENUM_TIMEFRAMES m_trendFilterTF;
   int             m_trendFilterPeriod;

   int             m_hBands;
   int             m_hRsi;
   int             m_hAtr;
   int             m_hTrendFilter;

   datetime        m_lastEvalBarTime;
   bool            m_evaluatedThisCall;
   double          m_lastClose;
   double          m_lastUpper;
   double          m_lastLower;
   double          m_lastRsi;
   double          m_lastTrendFilterMa;

   double GetBuffer(const int handle,const int bufferIndex,const int shift)
     {
      double buf[];
      ArraySetAsSeries(buf, true);
      if(CopyBuffer(handle, bufferIndex, shift, 1, buf) <= 0)
         return EMPTY_VALUE;
      return buf[0];
     }

public:
   CScalpSignal(void)
     {
      m_hBands       = INVALID_HANDLE;
      m_hRsi         = INVALID_HANDLE;
      m_hAtr         = INVALID_HANDLE;
      m_hTrendFilter = INVALID_HANDLE;
      m_lastEvalBarTime = 0;
      m_evaluatedThisCall = false;
      m_lastClose = 0.0;
      m_lastUpper = 0.0;
      m_lastLower = 0.0;
      m_lastRsi   = 0.0;
      m_lastTrendFilterMa = 0.0;
     }

   ~CScalpSignal(void)
     {
      Release();
     }

   bool Init(const string symbol,const ENUM_TIMEFRAMES tf,const int bbPeriod,const double bbDeviation,
             const int rsiPeriod,const double rsiOversold,const double rsiOverbought,const int atrPeriod,
             const bool useTrendFilter,const ENUM_TIMEFRAMES trendFilterTF,const int trendFilterPeriod)
     {
      m_symbol        = symbol;
      m_tf            = tf;
      m_bbPeriod      = bbPeriod;
      m_bbDeviation   = bbDeviation;
      m_rsiPeriod     = rsiPeriod;
      m_rsiOversold   = rsiOversold;
      m_rsiOverbought = rsiOverbought;
      m_atrPeriod     = atrPeriod;
      m_useTrendFilter    = useTrendFilter;
      m_trendFilterTF     = trendFilterTF;
      m_trendFilterPeriod = trendFilterPeriod;

      m_hBands = iBands(m_symbol, m_tf, m_bbPeriod, 0, m_bbDeviation, PRICE_CLOSE);
      m_hRsi   = iRSI(m_symbol, m_tf, m_rsiPeriod, PRICE_CLOSE);
      m_hAtr   = iATR(m_symbol, m_tf, m_atrPeriod);

      if(m_hBands == INVALID_HANDLE || m_hRsi == INVALID_HANDLE || m_hAtr == INVALID_HANDLE)
        {
         Print("BTCScalperEA: falha ao criar handles de indicadores");
         return false;
        }

      if(m_useTrendFilter)
        {
         m_hTrendFilter = iMA(m_symbol, m_trendFilterTF, m_trendFilterPeriod, 0, MODE_EMA, PRICE_CLOSE);
         if(m_hTrendFilter == INVALID_HANDLE)
           {
            Print("BTCScalperEA: falha ao criar handle do filtro de tendencia");
            return false;
           }
        }
      return true;
     }

   void Release(void)
     {
      if(m_hBands       != INVALID_HANDLE) IndicatorRelease(m_hBands);
      if(m_hRsi         != INVALID_HANDLE) IndicatorRelease(m_hRsi);
      if(m_hAtr         != INVALID_HANDLE) IndicatorRelease(m_hAtr);
      if(m_hTrendFilter != INVALID_HANDLE) IndicatorRelease(m_hTrendFilter);
     }

   bool IsReady(void)
     {
      bool baseReady = BarsCalculated(m_hBands) > m_bbPeriod && BarsCalculated(m_hRsi) > 2 && BarsCalculated(m_hAtr) > 2;
      if(!m_useTrendFilter)
         return baseReady;
      return baseReady && BarsCalculated(m_hTrendFilter) > m_trendFilterPeriod;
     }

   double AtrValue(void)
     {
      double atr = GetBuffer(m_hAtr, 0, 1);
      return (atr == EMPTY_VALUE) ? 0.0 : atr;
     }

   // true somente na chamada em que uma barra nova foi de fato avaliada
   // (util para logging de diagnostico sem duplicar por tick)
   bool WasEvaluatedThisCall(void) const { return m_evaluatedThisCall; }
   double LastClose(void) const { return m_lastClose; }
   double LastUpper(void) const { return m_lastUpper; }
   double LastLower(void) const { return m_lastLower; }
   double LastRsi(void)   const { return m_lastRsi; }
   double LastTrendFilterMa(void) const { return m_lastTrendFilterMa; }

   // Reversao a media: fecha fora da banda + RSI em extremo -> aposta na volta ao centro.
   // So avalia uma vez por barra fechada do timeframe de entrada (evita reabrir o mesmo
   // sinal a cada tick dentro da mesma barra).
   int GetEntrySignal(void)
     {
      m_evaluatedThisCall = false;

      if(!IsReady())
         return 0;

      datetime barTime = iTime(m_symbol, m_tf, 0);
      if(barTime == m_lastEvalBarTime)
         return 0;
      m_lastEvalBarTime = barTime;

      double close1 = iClose(m_symbol, m_tf, 1);
      double upper1 = GetBuffer(m_hBands, 1, 1); // UPPER_BAND
      double lower1 = GetBuffer(m_hBands, 2, 1); // LOWER_BAND
      double rsi1   = GetBuffer(m_hRsi, 0, 1);

      if(upper1 == EMPTY_VALUE || lower1 == EMPTY_VALUE || rsi1 == EMPTY_VALUE)
         return 0;

      double trendMa = 0.0;
      if(m_useTrendFilter)
        {
         trendMa = GetBuffer(m_hTrendFilter, 0, 0); // valor mais recente (barra atual em formacao) do TF maior
         if(trendMa == EMPTY_VALUE)
            return 0;
        }

      m_evaluatedThisCall = true;
      m_lastClose = close1;
      m_lastUpper = upper1;
      m_lastLower = lower1;
      m_lastRsi   = rsi1;
      m_lastTrendFilterMa = trendMa;

      // Filtro de tendencia: nao compra "faca caindo" numa tendencia de baixa confirmada
      // (preco abaixo da media do timeframe maior), nem vende contra uma tendencia de alta confirmada.
      bool blockBuy  = m_useTrendFilter && (close1 < trendMa);
      bool blockSell = m_useTrendFilter && (close1 > trendMa);

      if(close1 <= lower1 && rsi1 <= m_rsiOversold && !blockBuy)
         return 1;  // compra - espera reversao para cima

      if(close1 >= upper1 && rsi1 >= m_rsiOverbought && !blockSell)
         return -1; // venda - espera reversao para baixo

      return 0;
     }
  };
