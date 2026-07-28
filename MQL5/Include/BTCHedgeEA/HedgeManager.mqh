//+------------------------------------------------------------------+
//|                                                 HedgeManager.mqh |
//| Hedge de proteção: abre posição oposta quando uma posição       |
//| principal atinge perda flutuante acima do limiar configurado,   |
//| e desfaz o hedge quando a posição original se recupera, quando   |
//| ela é encerrada (órfão), ou converte a posição quando o hedge   |
//| supera a perda original (corta o perdedor, deixa o hedge correr).|
//+------------------------------------------------------------------+
#property strict

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <BTCHedgeEA/Defines.mqh>

#define BTCEA_HEDGE_TAG "HDG"

class CHedgeManager
  {
private:
   string        m_symbol;
   long          m_mainMagic;
   long          m_hedgeMagic;
   double        m_triggerLossPercent;   // % da equity que dispara o hedge
   double        m_hedgeRatio;           // volume do hedge = volume original * ratio
   double        m_recoveryBufferRatio;  // fração do limiar em que a original "se recuperou" o suficiente
   double        m_convertRatio;         // fração da perda original que o hedge precisa cobrir p/ cortar a original
   ulong         m_slippagePoints;

   CTrade        m_trade;
   CPositionInfo m_pos;

   string HedgeComment(const ulong originalTicket)
     {
      return StringFormat("%s%I64u", BTCEA_HEDGE_TAG, originalTicket);
     }

   ulong ParseHedgedTicket(const string comment)
     {
      int tagLen = StringLen(BTCEA_HEDGE_TAG);
      if(StringSubstr(comment, 0, tagLen) != BTCEA_HEDGE_TAG)
         return 0;
      return (ulong)StringToInteger(StringSubstr(comment, tagLen));
     }

   double TriggerLossMoney(void)
     {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      return equity * (m_triggerLossPercent / 100.0);
     }

   bool FindHedgeForOriginal(const ulong originalTicket,ulong &hedgeTicket)
     {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         if(!m_pos.SelectByIndex(i))
            continue;
         if(m_pos.Symbol() != m_symbol || m_pos.Magic() != m_hedgeMagic)
            continue;
         if(ParseHedgedTicket(m_pos.Comment()) == originalTicket)
           {
            hedgeTicket = m_pos.Ticket();
            return true;
           }
        }
      return false;
     }

public:
   CHedgeManager(void)
     {
      m_triggerLossPercent  = 1.5;
      m_hedgeRatio          = 1.0;
      m_recoveryBufferRatio = 0.3;
      m_convertRatio        = 1.2;
      m_slippagePoints      = 30;
     }

   void Configure(const string symbol,const long mainMagic,const long hedgeMagic,
                  const double triggerLossPercent,const double hedgeRatio,
                  const double recoveryBufferRatio,const double convertRatio,
                  const ulong slippagePoints)
     {
      m_symbol              = symbol;
      m_mainMagic           = mainMagic;
      m_hedgeMagic          = hedgeMagic;
      m_triggerLossPercent  = triggerLossPercent;
      m_hedgeRatio          = hedgeRatio;
      m_recoveryBufferRatio = recoveryBufferRatio;
      m_convertRatio        = convertRatio;
      m_slippagePoints      = slippagePoints;

      m_trade.SetDeviationInPoints(m_slippagePoints);
      m_trade.SetMarginMode();
      m_trade.LogLevel(LOG_LEVEL_ERRORS);
     }

   // Deve ser chamado a cada tick, depois da gestão de trailing/breakeven das posições.
   void Manage(void)
     {
      CleanupOrphanHedges();
      CheckRecoveryAndConvert();
      OpenHedgesWhereNeeded();
     }

   // Fecha hedges cuja posição original já não existe mais (fechada por SL/TP/trailing/manual)
   void CleanupOrphanHedges(void)
     {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         if(!m_pos.SelectByIndex(i))
            continue;
         if(m_pos.Symbol() != m_symbol || m_pos.Magic() != m_hedgeMagic)
            continue;

         ulong originalTicket = ParseHedgedTicket(m_pos.Comment());
         if(originalTicket == 0)
            continue;

         ulong hedgeTicket = m_pos.Ticket(); // capturar ANTES de trocar a selecao global abaixo

         if(!PositionSelectByTicket(originalTicket))
           {
            if(m_trade.PositionClose(hedgeTicket))
               PrintFormat("BTCHedgeEA: hedge #%I64u orfao (original #%I64u fechada) - encerrado", hedgeTicket, originalTicket);
            else
               PrintFormat("BTCHedgeEA: hedge #%I64u orfao (original #%I64u fechada) - FALHA ao encerrar, erro %d", hedgeTicket, originalTicket, GetLastError());
           }
        }
     }

   // Se a posição original se recuperou o suficiente, encerra o hedge.
   // Se o hedge já cobre a perda original com folga, corta a posição original (converte).
   void CheckRecoveryAndConvert(void)
     {
      double triggerMoney = TriggerLossMoney();

      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         if(!m_pos.SelectByIndex(i))
            continue;
         if(m_pos.Symbol() != m_symbol || m_pos.Magic() != m_hedgeMagic)
            continue;

         ulong originalTicket = ParseHedgedTicket(m_pos.Comment());
         if(originalTicket == 0)
            continue;

         double hedgeProfit = m_pos.Profit() + m_pos.Swap();
         ulong  hedgeTicket = m_pos.Ticket();

         if(!PositionSelectByTicket(originalTicket))
            continue; // tratado em CleanupOrphanHedges no próximo Manage()

         double originalProfit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);

         // Recuperação: a perda original encolheu para dentro do buffer de recuperação -> não precisa mais de hedge
         if(originalProfit >= -(triggerMoney * m_recoveryBufferRatio))
           {
            m_trade.PositionClose(hedgeTicket);
            PrintFormat("BTCHedgeEA: original #%I64u recuperou (P/L=%.2f) - hedge #%I64u encerrado",
                        originalTicket, originalProfit, hedgeTicket);
            continue;
           }

         // Conversão: o hedge já cobre a perda original com folga -> corta a original, deixa o hedge correr
         if(hedgeProfit >= MathAbs(originalProfit) * m_convertRatio && hedgeProfit > 0.0)
           {
            m_trade.PositionClose(originalTicket);
            PrintFormat("BTCHedgeEA: hedge #%I64u cobriu a perda da original #%I64u (hedgeP/L=%.2f, origP/L=%.2f) - original cortada",
                        hedgeTicket, originalTicket, hedgeProfit, originalProfit);
           }
        }
     }

   // Abre hedge de proteção para posições principais cuja perda flutuante excedeu o limiar
   void OpenHedgesWhereNeeded(void)
     {
      double triggerMoney = TriggerLossMoney();
      if(triggerMoney <= 0.0)
         return;

      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         if(!m_pos.SelectByIndex(i))
            continue;
         if(m_pos.Symbol() != m_symbol || m_pos.Magic() != m_mainMagic)
            continue;

         double profit = m_pos.Profit() + m_pos.Swap();
         if(profit > -triggerMoney)
            continue; // ainda dentro do limite tolerado

         ulong originalTicket = m_pos.Ticket();
         // Capturar volume/tipo AGORA: FindHedgeForOriginal() reutiliza o mesmo objeto
         // m_pos internamente (seu proprio loop de SelectByIndex) e sobrescreveria a
         // selecao atual se lidos depois da chamada.
         double hedgeVolume = NormalizeHedgeVolume(m_pos.Volume() * m_hedgeRatio);
         ENUM_POSITION_TYPE originalType = m_pos.PositionType();

         ulong existingHedge;
         if(FindHedgeForOriginal(originalTicket, existingHedge))
            continue; // já tem hedge

         m_trade.SetExpertMagicNumber(m_hedgeMagic);
         bool sent;
         if(originalType == POSITION_TYPE_BUY)
            sent = m_trade.Sell(hedgeVolume, m_symbol, 0.0, 0.0, 0.0, HedgeComment(originalTicket));
         else
            sent = m_trade.Buy(hedgeVolume, m_symbol, 0.0, 0.0, 0.0, HedgeComment(originalTicket));

         if(sent)
            PrintFormat("BTCHedgeEA: hedge aberto para #%I64u (perda=%.2f, limiar=%.2f, vol=%.2f)",
                        originalTicket, profit, triggerMoney, hedgeVolume);
         else
            PrintFormat("BTCHedgeEA: falha ao abrir hedge para #%I64u - erro %d", originalTicket, GetLastError());
        }
     }

   double NormalizeHedgeVolume(const double volume)
     {
      double minVol = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
      double maxVol = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MAX);
      double step   = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);

      double vol = volume;
      if(step > 0.0)
         vol = MathRound(vol / step) * step;
      if(vol < minVol)
         vol = minVol;
      if(maxVol > 0.0 && vol > maxVol)
         vol = maxVol;

      int digits = (step >= 1.0) ? 0 : (step >= 0.1 ? 1 : 2);
      return NormalizeDouble(vol, digits);
     }

   // Fecha todas as posições (principais e hedge) deste símbolo/EA - usado pelo circuit breaker
   void CloseAll(void)
     {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         if(!m_pos.SelectByIndex(i))
            continue;
         if(m_pos.Symbol() != m_symbol)
            continue;
         if(m_pos.Magic() != m_mainMagic && m_pos.Magic() != m_hedgeMagic)
            continue;
         m_trade.PositionClose(m_pos.Ticket());
        }
     }

   int CountMainPositions(const ENUM_POSITION_TYPE type)
     {
      int count = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         if(!m_pos.SelectByIndex(i))
            continue;
         if(m_pos.Symbol() != m_symbol || m_pos.Magic() != m_mainMagic)
            continue;
         if(m_pos.PositionType() == type)
            count++;
        }
      return count;
     }
  };
