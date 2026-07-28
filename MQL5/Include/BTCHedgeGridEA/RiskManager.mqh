//+------------------------------------------------------------------+
//|                                                 RiskManager.mqh |
//| Controle de risco: DailyGain/DailyLoss (resetam a cada dia),    |
//| Max Drawdown (kill switch), persistencia via global variables.  |
//+------------------------------------------------------------------+
#property strict

#include <BTCHedgeGridEA/Defines.mqh>

class CHgRiskManager
  {
private:
   string            m_symbol;
   long              m_magic;
   double            m_dailyLossPercent;
   double            m_dailyProfitPercent;
   double            m_maxDrawdownPercent;
   bool              m_useEquityForDaily;   // true = equity, false = balance

   datetime          m_currentDay;          // meia-noite (server time) do dia corrente
   double            m_dailyBaseline;       // saldo/patrimonio no inicio do dia
   double            m_dailyStartEquity;    // igual ao baseline, guardado separado p/ clareza no dashboard
   double            m_equityPeak;          // pico historico de equity (para max DD)
   ENUM_HG_STATE     m_state;

   string GVName(const string suffix)
     {
      return StringFormat("%s%s_%I64d_%s", HGEA_GV_PREFIX, m_symbol, m_magic, suffix);
     }

   datetime DayStart(const datetime t)
     {
      return t - (t % 86400);
     }

public:
   CHgRiskManager(void)
     {
      m_symbol             = _Symbol;
      m_magic              = 0;
      m_dailyLossPercent   = 3.0;
      m_dailyProfitPercent = 0.0;
      m_maxDrawdownPercent = 15.0;
      m_useEquityForDaily  = true;
      m_currentDay         = 0;
      m_dailyBaseline      = 0.0;
      m_dailyStartEquity   = 0.0;
      m_equityPeak         = 0.0;
      m_state              = HG_STATE_TRADING;
     }

   void Configure(const string symbol,const long magic,const double dailyLossPercent,
                  const double dailyProfitPercent,const double maxDrawdownPercent,
                  const bool useEquityForDaily)
     {
      m_symbol             = symbol;
      m_magic              = magic;
      m_dailyLossPercent   = dailyLossPercent;
      m_dailyProfitPercent = dailyProfitPercent;
      m_maxDrawdownPercent = maxDrawdownPercent;
      m_useEquityForDaily  = useEquityForDaily;
     }

   // Carrega estado persistido (global variables sobrevivem a reinicio do terminal,
   // mas nao a uma troca de dia -- isso e o que queremos: retomar o mesmo dia apos restart)
   void Init(void)
     {
      datetime now    = TimeTradeServer();
      datetime today0 = DayStart(now);

      double savedBaseline = 0.0;
      double savedPeak     = 0.0;

      if(GlobalVariableCheck(GVName("day")))
        {
         double savedDay = GlobalVariableGet(GVName("day"));
         if((datetime)savedDay == today0)
           {
            GlobalVariableGet(GVName("baseline"), savedBaseline);
            m_dailyBaseline = savedBaseline;
           }
         else
            m_dailyBaseline = CurrentAccountValue();
        }
      else
         m_dailyBaseline = CurrentAccountValue();

      GlobalVariableSet(GVName("day"), (double)today0);
      GlobalVariableSet(GVName("baseline"), m_dailyBaseline);
      m_dailyStartEquity = m_dailyBaseline;

      if(GlobalVariableCheck(GVName("peak")))
        {
         GlobalVariableGet(GVName("peak"), savedPeak);
         m_equityPeak = MathMax(savedPeak, AccountInfoDouble(ACCOUNT_EQUITY));
        }
      else
         m_equityPeak = AccountInfoDouble(ACCOUNT_EQUITY);

      GlobalVariableSet(GVName("peak"), m_equityPeak);

      m_currentDay = today0;
      m_state      = HG_STATE_TRADING;
     }

   double CurrentAccountValue(void)
     {
      return m_useEquityForDaily ? AccountInfoDouble(ACCOUNT_EQUITY) : AccountInfoDouble(ACCOUNT_BALANCE);
     }

   // Deve ser chamado a cada tick. Retorna true se um novo dia comecou (baseline resetado).
   bool CheckNewDay(void)
     {
      datetime now    = TimeTradeServer();
      datetime today0 = DayStart(now);

      if(today0 != m_currentDay)
        {
         m_currentDay       = today0;
         m_dailyBaseline    = CurrentAccountValue();
         m_dailyStartEquity = m_dailyBaseline;
         m_state            = HG_STATE_TRADING;
         GlobalVariableSet(GVName("day"), (double)today0);
         GlobalVariableSet(GVName("baseline"), m_dailyBaseline);
         return true;
        }
      return false;
     }

   void UpdateEquityPeak(void)
     {
      double eq = AccountInfoDouble(ACCOUNT_EQUITY);
      if(eq > m_equityPeak)
        {
         m_equityPeak = eq;
         GlobalVariableSet(GVName("peak"), m_equityPeak);
        }
     }

   double DailyPnLPercent(void)
     {
      if(m_dailyBaseline <= 0.0)
         return 0.0;
      double current = CurrentAccountValue();
      return (current - m_dailyBaseline) / m_dailyBaseline * 100.0;
     }

   double DailyPnLMoney(void)
     {
      return CurrentAccountValue() - m_dailyBaseline;
     }

   double DrawdownFromPeakPercent(void)
     {
      if(m_equityPeak <= 0.0)
         return 0.0;
      double eq = AccountInfoDouble(ACCOUNT_EQUITY);
      return (m_equityPeak - eq) / m_equityPeak * 100.0;
     }

   bool IsDailyLossHit(void)
     {
      return (m_dailyLossPercent > 0.0 && DailyPnLPercent() <= -MathAbs(m_dailyLossPercent));
     }

   bool IsDailyProfitHit(void)
     {
      return (m_dailyProfitPercent > 0.0 && DailyPnLPercent() >= m_dailyProfitPercent);
     }

   bool IsMaxDrawdownHit(void)
     {
      return (m_maxDrawdownPercent > 0.0 && DrawdownFromPeakPercent() >= m_maxDrawdownPercent);
     }

   ENUM_HG_STATE Evaluate(void)
     {
      UpdateEquityPeak();

      if(IsMaxDrawdownHit())
         m_state = HG_STATE_MAX_DRAWDOWN;
      else if(IsDailyLossHit())
         m_state = HG_STATE_DAILY_LOSS;
      else if(IsDailyProfitHit())
         m_state = HG_STATE_DAILY_PROFIT;
      else
         m_state = HG_STATE_TRADING;

      return m_state;
     }

   ENUM_HG_STATE State(void) const { return m_state; }
   double        DailyBaseline(void) const { return m_dailyBaseline; }
   double        EquityPeak(void) const { return m_equityPeak; }
  };
