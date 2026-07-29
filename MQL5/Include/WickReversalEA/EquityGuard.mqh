//+------------------------------------------------------------------+
//|                                                 EquityGuard.mqh |
//| Meta de lucro e protecao de drawdown medidas contra uma equity  |
//| de referencia (definida ao iniciar o EA). Cada uma pode         |
//| "reiniciar" (fecha tudo, redefine a referencia para a equity     |
//| atual e continua operando) ou travar permanentemente ate o      |
//| usuario reiniciar o EA manualmente.                              |
//+------------------------------------------------------------------+
#property strict

#include <WickReversalEA/Defines.mqh>

class CEquityGuard
  {
private:
   bool          m_useProfitTarget;
   double        m_profitTargetPercent;
   bool          m_restartAfterProfitTarget;

   bool          m_useProtection;
   double        m_maxDrawdownPercent;
   bool          m_restartAfterProtection;

   double        m_baseline;
   ENUM_WR_STATE m_state;
   bool          m_pendingCloseAll;

public:
   CEquityGuard(void)
     {
      m_useProfitTarget          = false;
      m_profitTargetPercent      = 100.0;
      m_restartAfterProfitTarget = true;
      m_useProtection            = false;
      m_maxDrawdownPercent       = 10.0;
      m_restartAfterProtection   = false;
      m_baseline                 = 0.0;
      m_state                    = WR_STATE_TRADING;
      m_pendingCloseAll          = false;
     }

   void Configure(const bool useProfitTarget,const double profitTargetPercent,const bool restartAfterProfitTarget,
                  const bool useProtection,const double maxDrawdownPercent,const bool restartAfterProtection)
     {
      m_useProfitTarget          = useProfitTarget;
      m_profitTargetPercent      = profitTargetPercent;
      m_restartAfterProfitTarget = restartAfterProfitTarget;
      m_useProtection            = useProtection;
      m_maxDrawdownPercent       = maxDrawdownPercent;
      m_restartAfterProtection   = restartAfterProtection;
     }

   void Init(void)
     {
      m_baseline = AccountInfoDouble(ACCOUNT_EQUITY);
      m_state    = WR_STATE_TRADING;
      m_pendingCloseAll = false;
     }

   void ResetBaseline(void)
     {
      m_baseline = AccountInfoDouble(ACCOUNT_EQUITY);
     }

   double Baseline(void) const { return m_baseline; }

   double ProfitPercent(void)
     {
      if(m_baseline <= 0.0)
         return 0.0;
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      return (equity - m_baseline) / m_baseline * 100.0;
     }

   ENUM_WR_STATE State(void) const { return m_state; }

   // Deve ser chamado a cada tick. Se retornar diferente de WR_STATE_TRADING de forma
   // permanente (sem restart), o EA que chama deve bloquear novas entradas.
   ENUM_WR_STATE Evaluate(void)
     {
      if(m_state != WR_STATE_TRADING)
         return m_state; // travado (sem restart) ate o proximo Init() do EA

      double pct = ProfitPercent();

      if(m_useProfitTarget && m_profitTargetPercent > 0.0 && pct >= m_profitTargetPercent)
        {
         m_pendingCloseAll = true;
         if(m_restartAfterProfitTarget)
           {
            ResetBaseline();
            m_state = WR_STATE_TRADING;
           }
         else
            m_state = WR_STATE_PROFIT_TARGET_HIT;
         return m_state;
        }

      if(m_useProtection && m_maxDrawdownPercent > 0.0 && pct <= -m_maxDrawdownPercent)
        {
         m_pendingCloseAll = true;
         if(m_restartAfterProtection)
           {
            ResetBaseline();
            m_state = WR_STATE_TRADING;
           }
         else
            m_state = WR_STATE_PROTECTION_HIT;
         return m_state;
        }

      return WR_STATE_TRADING;
     }

   // Consome (e reseta) o evento "precisa fechar tudo agora" - o EA chamador e
   // responsavel por efetivamente fechar as posicoes (via CSetupManager::CloseAll).
   bool ConsumePendingCloseAll(void)
     {
      bool v = m_pendingCloseAll;
      m_pendingCloseAll = false;
      return v;
     }
  };
