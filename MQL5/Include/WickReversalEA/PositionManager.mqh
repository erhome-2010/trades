//+------------------------------------------------------------------+
//|                                             PositionManager.mqh |
//| Breakeven e trailing stop, aplicados por posicao (independente  |
//| de tier/lado) a todas as posicoes abertas deste EA.             |
//+------------------------------------------------------------------+
#property strict

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <WickReversalEA/PipUtils.mqh>

class CPositionManager
  {
private:
   string        m_symbol;
   long          m_magic;

   bool          m_useBreakEven;
   double        m_breakEvenAfterPips;
   double        m_breakEvenPlusPips;

   bool          m_useTrailing;
   double        m_trailingStartPips;
   double        m_trailingDistancePips;
   double        m_trailingStepPips;

   CTrade        m_trade;
   CPositionInfo m_pos;

public:
   void Configure(const string symbol,const long magic,
                  const bool useBreakEven,const double breakEvenAfterPips,const double breakEvenPlusPips,
                  const bool useTrailing,const double trailingStartPips,const double trailingDistancePips,
                  const double trailingStepPips,const ulong slippagePoints)
     {
      m_symbol = symbol;
      m_magic  = magic;

      m_useBreakEven       = useBreakEven;
      m_breakEvenAfterPips = breakEvenAfterPips;
      m_breakEvenPlusPips  = breakEvenPlusPips;

      m_useTrailing          = useTrailing;
      m_trailingStartPips    = trailingStartPips;
      m_trailingDistancePips = trailingDistancePips;
      m_trailingStepPips     = trailingStepPips;

      m_trade.SetDeviationInPoints(slippagePoints);
      m_trade.SetMarginMode();
      m_trade.LogLevel(LOG_LEVEL_ERRORS);
     }

   void Manage(void)
     {
      if(!m_useBreakEven && !m_useTrailing)
         return;

      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      int    digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
      long   stopsLevel = SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL);
      double minDistance = stopsLevel * point;

      double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);

      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         if(!m_pos.SelectByIndex(i))
            continue;
         if(m_pos.Symbol() != m_symbol || m_pos.Magic() != m_magic)
            continue;

         bool   isBuy     = (m_pos.PositionType() == POSITION_TYPE_BUY);
         double openPrice = m_pos.PriceOpen();
         double curSl      = m_pos.StopLoss();
         double curTp      = m_pos.TakeProfit();
         double price      = isBuy ? bid : ask;
         ulong  ticket      = m_pos.Ticket();

         double profitPips = WrPriceToPips(m_symbol, isBuy ? (price - openPrice) : (openPrice - price));
         double newSl = curSl;

         if(m_useBreakEven && profitPips >= m_breakEvenAfterPips)
           {
            double beSl = isBuy ? openPrice + WrPipsToPrice(m_symbol, m_breakEvenPlusPips)
                                  : openPrice - WrPipsToPrice(m_symbol, m_breakEvenPlusPips);
            bool improves = isBuy ? (beSl > newSl) : (newSl == 0.0 || beSl < newSl);
            if(improves)
               newSl = beSl;
           }

         if(m_useTrailing && profitPips >= m_trailingStartPips)
           {
            double trailSl = isBuy ? price - WrPipsToPrice(m_symbol, m_trailingDistancePips)
                                     : price + WrPipsToPrice(m_symbol, m_trailingDistancePips);
            double stepDist = WrPipsToPrice(m_symbol, m_trailingStepPips);
            bool improves = isBuy ? (trailSl > newSl + stepDist) : (newSl == 0.0 || trailSl < newSl - stepDist);
            if(improves)
               newSl = trailSl;
           }

         newSl = NormalizeDouble(newSl, digits);
         bool changed = (newSl != curSl && newSl != 0.0);
         bool onCorrectSide = isBuy ? (newSl < price) : (newSl > price);
         bool respectsMinDistance = (minDistance <= 0.0) || (MathAbs(price - newSl) >= minDistance);

         if(changed && onCorrectSide && respectsMinDistance)
            m_trade.PositionModify(ticket, newSl, curTp);
        }
     }
  };
