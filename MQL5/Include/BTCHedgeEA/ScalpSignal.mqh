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

   int             m_hBands;
   int             m_hRsi;
   int             m_hAtr;

   datetime        m_lastEvalBarTime;

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
      m_hBands = INVALID_HANDLE;
      m_hRsi   = INVALID_HANDLE;
      m_hAtr   = INVALID_HANDLE;
      m_lastEvalBarTime = 0;
     }

   ~CScalpSignal(void)
     {
      Release();
     }

   bool Init(const string symbol,const ENUM_TIMEFRAMES tf,const int bbPeriod,const double bbDeviation,
             const int rsiPeriod,const double rsiOversold,const double rsiOverbought,const int atrPeriod)
     {
      m_symbol        = symbol;
      m_tf            = tf;
      m_bbPeriod      = bbPeriod;
      m_bbDeviation   = bbDeviation;
      m_rsiPeriod     = rsiPeriod;
      m_rsiOversold   = rsiOversold;
      m_rsiOverbought = rsiOverbought;
      m_atrPeriod     = atrPeriod;

      m_hBands = iBands(m_symbol, m_tf, m_bbPeriod, 0, m_bbDeviation, PRICE_CLOSE);
      m_hRsi   = iRSI(m_symbol, m_tf, m_rsiPeriod, PRICE_CLOSE);
      m_hAtr   = iATR(m_symbol, m_tf, m_atrPeriod);

      if(m_hBands == INVALID_HANDLE || m_hRsi == INVALID_HANDLE || m_hAtr == INVALID_HANDLE)
        {
         Print("BTCScalperEA: falha ao criar handles de indicadores");
         return false;
        }
      return true;
     }

   void Release(void)
     {
      if(m_hBands != INVALID_HANDLE) IndicatorRelease(m_hBands);
      if(m_hRsi   != INVALID_HANDLE) IndicatorRelease(m_hRsi);
      if(m_hAtr   != INVALID_HANDLE) IndicatorRelease(m_hAtr);
     }

   bool IsReady(void)
     {
      return BarsCalculated(m_hBands) > m_bbPeriod && BarsCalculated(m_hRsi) > 2 && BarsCalculated(m_hAtr) > 2;
     }

   double AtrValue(void)
     {
      double atr = GetBuffer(m_hAtr, 0, 1);
      return (atr == EMPTY_VALUE) ? 0.0 : atr;
     }

   // Reversao a media: fecha fora da banda + RSI em extremo -> aposta na volta ao centro.
   // So avalia uma vez por barra fechada do timeframe de entrada (evita reabrir o mesmo
   // sinal a cada tick dentro da mesma barra).
   int GetEntrySignal(void)
     {
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

      if(close1 <= lower1 && rsi1 <= m_rsiOversold)
         return 1;  // compra - espera reversao para cima

      if(close1 >= upper1 && rsi1 >= m_rsiOverbought)
         return -1; // venda - espera reversao para baixo

      return 0;
     }
  };
