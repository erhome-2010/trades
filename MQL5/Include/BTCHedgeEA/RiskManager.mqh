//+------------------------------------------------------------------+
//|                                                 RiskManager.mqh |
//| Controle de risco: DailyGain/DailyLoss, Max Drawdown, dimensiona-|
//| mento de posição por % de risco, persistência entre reinícios.  |
//+------------------------------------------------------------------+
#property strict

#include <BTCHedgeEA/Defines.mqh>

class CRiskManager
  {
private:
   string            m_symbol;
   long              m_magic;
   double            m_riskPercent;
   double            m_dailyLossPercent;
   double            m_dailyProfitPercent;
   double            m_maxDrawdownPercent;
   bool              m_useEquityForDaily;   // true = equity, false = balance

   datetime          m_currentDay;          // meia-noite (server time) do dia corrente
   double            m_dailyBaseline;       // saldo/patrimônio no início do dia
   double            m_equityPeak;          // pico histórico de equity (para max DD)
   ENUM_EA_STATE     m_state;

   string GVName(const string suffix)
     {
      return StringFormat("%s%s_%I64d_%s", BTCEA_GV_PREFIX, m_symbol, m_magic, suffix);
     }

   datetime DayStart(const datetime t)
     {
      return t - (t % 86400);
     }

public:
   CRiskManager(void)
     {
      m_symbol             = _Symbol;
      m_magic              = 0;
      m_riskPercent        = 1.0;
      m_dailyLossPercent   = 3.0;
      m_dailyProfitPercent = 0.0;   // 0 = desabilitado
      m_maxDrawdownPercent = 10.0;
      m_useEquityForDaily  = true;
      m_currentDay         = 0;
      m_dailyBaseline      = 0.0;
      m_equityPeak         = 0.0;
      m_state              = EA_STATE_TRADING;
     }

   void Configure(const string symbol,const long magic,const double riskPercent,
                  const double dailyLossPercent,const double dailyProfitPercent,
                  const double maxDrawdownPercent,const bool useEquityForDaily)
     {
      m_symbol             = symbol;
      m_magic              = magic;
      m_riskPercent        = riskPercent;
      m_dailyLossPercent   = dailyLossPercent;
      m_dailyProfitPercent = dailyProfitPercent;
      m_maxDrawdownPercent = maxDrawdownPercent;
      m_useEquityForDaily  = useEquityForDaily;
     }

   // Carrega estado persistido (global variables sobrevivem a reinício do terminal,
   // mas não a uma troca de dia -- isso é o que queremos: retomar o mesmo dia após um restart)
   void Init(void)
     {
      datetime now     = TimeTradeServer();
      datetime today0  = DayStart(now);

      double savedDay      = GlobalVariableGet(GVName("day"));
      double savedBaseline = 0.0;
      double savedPeak      = 0.0;

      if(GlobalVariableCheck(GVName("day")) && (datetime)savedDay == today0)
        {
         GlobalVariableGet(GVName("baseline"), savedBaseline);
         m_dailyBaseline = savedBaseline;
        }
      else
        {
         m_dailyBaseline = CurrentAccountValue();
         GlobalVariableSet(GVName("day"), (double)today0);
         GlobalVariableSet(GVName("baseline"), m_dailyBaseline);
        }

      if(GlobalVariableCheck(GVName("peak")))
        {
         GlobalVariableGet(GVName("peak"), savedPeak);
         m_equityPeak = MathMax(savedPeak, AccountInfoDouble(ACCOUNT_EQUITY));
        }
      else
         m_equityPeak = AccountInfoDouble(ACCOUNT_EQUITY);

      GlobalVariableSet(GVName("peak"), m_equityPeak);

      m_currentDay = today0;
      m_state      = EA_STATE_TRADING;
     }

   double CurrentAccountValue(void)
     {
      return m_useEquityForDaily ? AccountInfoDouble(ACCOUNT_EQUITY) : AccountInfoDouble(ACCOUNT_BALANCE);
     }

   // Deve ser chamado a cada tick. Retorna true se um novo dia começou (baseline resetado).
   bool CheckNewDay(void)
     {
      datetime now    = TimeTradeServer();
      datetime today0 = DayStart(now);

      if(today0 != m_currentDay)
        {
         m_currentDay    = today0;
         m_dailyBaseline = CurrentAccountValue();
         m_state         = EA_STATE_TRADING;
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

   ENUM_EA_STATE Evaluate(void)
     {
      UpdateEquityPeak();

      if(IsMaxDrawdownHit())
         m_state = EA_STATE_MAX_DRAWDOWN;
      else if(IsDailyLossHit())
         m_state = EA_STATE_DAILY_LOSS;
      else if(IsDailyProfitHit())
         m_state = EA_STATE_DAILY_PROFIT;
      else
         m_state = EA_STATE_TRADING;

      return m_state;
     }

   ENUM_EA_STATE State(void) const { return m_state; }
   double        DailyBaseline(void) const { return m_dailyBaseline; }
   double        EquityPeak(void) const { return m_equityPeak; }

   // Dimensiona volume por % de risco da conta dado a distância do stop em pontos (price units)
   double CalcLotByRisk(const double slDistancePrice)
     {
      if(slDistancePrice <= 0.0)
         return SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);

      double equity    = AccountInfoDouble(ACCOUNT_EQUITY);
      double riskMoney = equity * (m_riskPercent / 100.0);

      double tickValue = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize  = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
      if(tickSize <= 0.0 || tickValue <= 0.0)
         return SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);

      double lossPerLot = (slDistancePrice / tickSize) * tickValue;
      if(lossPerLot <= 0.0)
         return SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);

      double lots = riskMoney / lossPerLot;
      return NormalizeVolume(lots);
     }

   double NormalizeVolume(const double volume)
     {
      double minVol  = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
      double maxVol  = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MAX);
      double step    = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);

      double vol = volume;
      if(step > 0.0)
         vol = MathFloor(vol / step) * step;

      if(vol < minVol)
         vol = minVol;
      if(maxVol > 0.0 && vol > maxVol)
         vol = maxVol;

      int digits = 2;
      if(step >= 0.1)
         digits = 1;
      if(step >= 1.0)
         digits = 0;

      return NormalizeDouble(vol, digits);
     }
  };
