//+------------------------------------------------------------------+
//|                                                 WickSignal.mqh |
//| Deteccao do padrao de rejeicao de pavio ("wick rejection" / pin |
//| bar): corpo pequeno (<= BodyMaximumPercent do range da vela) e  |
//| pavio grande do lado contrario a direcao do sinal (>=           |
//| WickMinimumPercent do range). Bullish = pavio inferior grande   |
//| (rejeitou queda) -> sinal de compra. Bearish = pavio superior   |
//| grande (rejeitou alta) -> sinal de venda.                       |
//|                                                                  |
//| Filtros adicionais: media movel de tendencia (so compra acima   |
//| da media, so vende abaixo) e "scanner" multi-timeframe (exige   |
//| que o mesmo padrao, na mesma direcao, tambem apareca na ultima  |
//| vela fechada de cada timeframe habilitado).                     |
//+------------------------------------------------------------------+
#property strict

class CWickSignal
  {
private:
   string          m_symbol;
   ENUM_TIMEFRAMES m_entryTimeframe;
   double          m_bodyMaxPercent;
   double          m_wickMinPercent;

   bool            m_useMaFilter;
   ENUM_TIMEFRAMES m_maTimeframe;
   int             m_maPeriod;
   ENUM_MA_METHOD  m_maMethod;
   ENUM_APPLIED_PRICE m_maPrice;
   int             m_maHandle;

   bool            m_useScanner;
   bool            m_scanEnabled[7];
   ENUM_TIMEFRAMES m_scanTf[7];

   datetime        m_lastEntryBarTime;
   bool            m_evaluatedThisCall;

   // Retorna +1 (padrao de alta / bullish), -1 (padrao de baixa / bearish) ou 0 (nenhum)
   // avaliado na ultima vela FECHADA (shift=1) do timeframe informado.
   int PatternOnTimeframe(const ENUM_TIMEFRAMES tf)
     {
      if(iBars(m_symbol, tf) < 3)
         return 0;

      double open  = iOpen(m_symbol, tf, 1);
      double high  = iHigh(m_symbol, tf, 1);
      double low   = iLow(m_symbol, tf, 1);
      double close = iClose(m_symbol, tf, 1);

      double range = high - low;
      if(range <= 0.0)
         return 0;

      double body = MathAbs(close - open);
      double bodyPct = body / range * 100.0;
      if(bodyPct > m_bodyMaxPercent)
         return 0;

      double lowerWick = MathMin(open, close) - low;
      double upperWick = high - MathMax(open, close);
      double lowerWickPct = lowerWick / range * 100.0;
      double upperWickPct = upperWick / range * 100.0;

      if(lowerWickPct >= m_wickMinPercent)
         return 1;
      if(upperWickPct >= m_wickMinPercent)
         return -1;
      return 0;
     }

public:
   CWickSignal(void)
     {
      m_maHandle          = INVALID_HANDLE;
      m_lastEntryBarTime  = 0;
      m_evaluatedThisCall = false;
      m_useScanner        = false;
      m_scanTf[0] = PERIOD_M1;  m_scanTf[1] = PERIOD_M5;  m_scanTf[2] = PERIOD_M15;
      m_scanTf[3] = PERIOD_M30; m_scanTf[4] = PERIOD_H1;  m_scanTf[5] = PERIOD_H4;
      m_scanTf[6] = PERIOD_D1;
      for(int i = 0; i < 7; i++)
         m_scanEnabled[i] = false;
     }

   bool Init(const string symbol,const ENUM_TIMEFRAMES entryTimeframe,
             const double bodyMaxPercent,const double wickMinPercent,
             const bool useMaFilter,const ENUM_TIMEFRAMES maTimeframe,const int maPeriod,
             const ENUM_MA_METHOD maMethod,const ENUM_APPLIED_PRICE maPrice,
             const bool useScanner,const bool scanM1,const bool scanM5,const bool scanM15,
             const bool scanM30,const bool scanH1,const bool scanH4,const bool scanD1)
     {
      m_symbol         = symbol;
      m_entryTimeframe = entryTimeframe;
      m_bodyMaxPercent = bodyMaxPercent;
      m_wickMinPercent = wickMinPercent;

      m_useMaFilter = useMaFilter;
      m_maTimeframe = maTimeframe;
      m_maPeriod    = maPeriod;
      m_maMethod    = maMethod;
      m_maPrice     = maPrice;

      m_useScanner = useScanner;
      m_scanEnabled[0] = scanM1;  m_scanEnabled[1] = scanM5;  m_scanEnabled[2] = scanM15;
      m_scanEnabled[3] = scanM30; m_scanEnabled[4] = scanH1;  m_scanEnabled[5] = scanH4;
      m_scanEnabled[6] = scanD1;

      if(m_useMaFilter)
        {
         m_maHandle = iMA(m_symbol, m_maTimeframe, m_maPeriod, 0, m_maMethod, m_maPrice);
         if(m_maHandle == INVALID_HANDLE)
           {
            PrintFormat("WickReversalEA: falha ao criar indicador de media movel - erro %d", GetLastError());
            return false;
           }
        }
      return true;
     }

   void Release(void)
     {
      if(m_maHandle != INVALID_HANDLE)
         IndicatorRelease(m_maHandle);
      m_maHandle = INVALID_HANDLE;
     }

   bool WasEvaluatedThisCall(void) const { return m_evaluatedThisCall; }

   bool TrendFilterAllows(const int direction)
     {
      if(!m_useMaFilter)
         return true;
      if(m_maHandle == INVALID_HANDLE)
         return true;

      double buf[];
      ArraySetAsSeries(buf, true);
      if(CopyBuffer(m_maHandle, 0, 1, 1, buf) <= 0)
         return false;

      double maValue = buf[0];
      double refPrice = iClose(m_symbol, m_entryTimeframe, 1);

      if(direction > 0)
         return refPrice > maValue;
      return refPrice < maValue;
     }

   double MaValue(void)
     {
      if(m_maHandle == INVALID_HANDLE)
         return 0.0;
      double buf[];
      ArraySetAsSeries(buf, true);
      if(CopyBuffer(m_maHandle, 0, 1, 1, buf) <= 0)
         return 0.0;
      return buf[0];
     }

   // Preco de fechamento da vela de rejeicao (ultima fechada no timeframe de entrada) -
   // usado como referencia para o preco de disparo da ordem pendente (break + BreakClosePips).
   double EntryPatternClose(void)
     {
      return iClose(m_symbol, m_entryTimeframe, 1);
     }

   datetime EntryBarTime(void)
     {
      return iTime(m_symbol, m_entryTimeframe, 0);
     }

   // Chamado a cada tick. So reavalia quando uma nova vela do timeframe de entrada fecha.
   // Retorna +1 (sinal de compra), -1 (sinal de venda) ou 0 (nenhum sinal novo).
   int GetEntrySignal(void)
     {
      m_evaluatedThisCall = false;

      datetime curBar = EntryBarTime();
      if(curBar == m_lastEntryBarTime)
         return 0;
      m_lastEntryBarTime  = curBar;
      m_evaluatedThisCall = true;

      int pattern = PatternOnTimeframe(m_entryTimeframe);
      if(pattern == 0)
         return 0;

      if(!TrendFilterAllows(pattern))
         return 0;

      if(m_useScanner)
        {
         for(int i = 0; i < 7; i++)
           {
            if(!m_scanEnabled[i])
               continue;
            int scanPattern = PatternOnTimeframe(m_scanTf[i]);
            if(scanPattern != pattern)
               return 0; // exige confluencia - qualquer timeframe habilitado que discordar cancela o sinal
           }
        }

      return pattern;
     }
  };
