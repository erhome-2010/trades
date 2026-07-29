//+------------------------------------------------------------------+
//|                                                SetupManager.mqh |
//| Nucleo do robo: ao surgir um sinal novo, abre um lote de ordens |
//| PENDENTES (stop) na direcao do sinal, no rompimento do          |
//| fechamento da vela de rejeicao + BreakClosePips - a primeira    |
//| "tier" (FirstEntryOrders ordens). Ordens pendentes nao           |
//| confirmadas em ate CancelPendingAfterCandles velas sao           |
//| canceladas. Uma vez preenchida a tier 1, se o preco avancar     |
//| ProfitStepPips a favor, abre a tier 2 (SecondEntryOrders, a     |
//| mercado, lote maior); se avancar de novo, abre a tier 3          |
//| (ThirdEntryOrders). So adiciona a favor (nunca faz media no     |
//| lado perdedor - e um piramide de tendencia, nao martingale).    |
//+------------------------------------------------------------------+
#property strict

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/OrderInfo.mqh>
#include <WickReversalEA/Defines.mqh>
#include <WickReversalEA/PipUtils.mqh>

class CSetupManager
  {
private:
   string          m_symbol;
   long            m_magic;

   ENUM_WR_DIRECTION_MODE m_directionMode;
   bool            m_blockOppositeDirection;
   bool            m_oneSetupAtTime;

   bool            m_useAutoLot;
   double          m_manualLot;
   double          m_initialLot;
   double          m_profitStepPips;
   double          m_lotIncreasePerStep;
   double          m_maxLot;

   int             m_firstOrders;
   int             m_secondOrders;
   int             m_thirdOrders;

   double          m_slPips;
   double          m_tpPips;
   double          m_breakClosePips;
   int             m_cancelPendingAfterCandles;
   ENUM_TIMEFRAMES m_entryTimeframe;

   ulong           m_slippagePoints;

   CTrade          m_trade;
   CPositionInfo   m_pos;
   COrderInfo      m_ord;

   double NormalizeVolume(const double volume)
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

   int TierBoundary(const int tierIdx)
     {
      if(tierIdx <= 0)
         return m_firstOrders;
      if(tierIdx == 1)
         return m_firstOrders + m_secondOrders;
      return m_firstOrders + m_secondOrders + m_thirdOrders;
     }

   int OrdersForTier(const int tierIdx)
     {
      if(tierIdx <= 0)
         return m_firstOrders;
      if(tierIdx == 1)
         return m_secondOrders;
      return m_thirdOrders;
     }

   double LotForTier(const int tierIdx)
     {
      if(!m_useAutoLot)
         return NormalizeVolume(m_manualLot);
      double lot = m_initialLot + m_lotIncreasePerStep * tierIdx;
      if(m_maxLot > 0.0)
         lot = MathMin(lot, m_maxLot);
      return NormalizeVolume(lot);
     }

public:
   CSetupManager(void)
     {
      m_directionMode              = WR_DIR_BOTH;
      m_blockOppositeDirection     = true;
      m_oneSetupAtTime             = false;
      m_useAutoLot                 = true;
      m_manualLot                  = 0.01;
      m_initialLot                 = 0.01;
      m_profitStepPips             = 20.0;
      m_lotIncreasePerStep         = 0.01;
      m_maxLot                     = 10.0;
      m_firstOrders                = 2;
      m_secondOrders               = 2;
      m_thirdOrders                = 2;
      m_slPips                     = 300.0;
      m_tpPips                     = 1000.0;
      m_breakClosePips             = 1.0;
      m_cancelPendingAfterCandles  = 20;
      m_entryTimeframe             = PERIOD_M1;
      m_slippagePoints             = 30;
     }

   void Configure(const string symbol,const long magic,const ENUM_TIMEFRAMES entryTimeframe,
                  const ENUM_WR_DIRECTION_MODE directionMode,const bool blockOppositeDirection,const bool oneSetupAtTime,
                  const bool useAutoLot,const double manualLot,const double initialLot,const double profitStepPips,
                  const double lotIncreasePerStep,const double maxLot,
                  const int firstOrders,const int secondOrders,const int thirdOrders,
                  const double slPips,const double tpPips,const double breakClosePips,
                  const int cancelPendingAfterCandles,const ulong slippagePoints)
     {
      m_symbol         = symbol;
      m_magic          = magic;
      m_entryTimeframe = entryTimeframe;

      m_directionMode          = directionMode;
      m_blockOppositeDirection = blockOppositeDirection;
      m_oneSetupAtTime         = oneSetupAtTime;

      m_useAutoLot         = useAutoLot;
      m_manualLot          = manualLot;
      m_initialLot         = initialLot;
      m_profitStepPips     = profitStepPips;
      m_lotIncreasePerStep = lotIncreasePerStep;
      m_maxLot             = maxLot;

      m_firstOrders  = MathMax(1, firstOrders);
      m_secondOrders = MathMax(0, secondOrders);
      m_thirdOrders  = MathMax(0, thirdOrders);

      m_slPips = slPips;
      m_tpPips = tpPips;
      m_breakClosePips            = breakClosePips;
      m_cancelPendingAfterCandles = MathMax(1, cancelPendingAfterCandles);
      m_slippagePoints            = slippagePoints;

      m_trade.SetDeviationInPoints(m_slippagePoints);
      m_trade.SetMarginMode();
      m_trade.LogLevel(LOG_LEVEL_ERRORS);
     }

   int CountOpenPositions(const ENUM_WR_SIDE side)
     {
      int count = 0;
      ENUM_POSITION_TYPE type = (side == WR_SIDE_BUY) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         if(!m_pos.SelectByIndex(i))
            continue;
         if(m_pos.Symbol() != m_symbol || m_pos.Magic() != m_magic)
            continue;
         if(m_pos.PositionType() == type)
            count++;
        }
      return count;
     }

   double LatestOpenPrice(const ENUM_WR_SIDE side)
     {
      datetime latest = 0;
      double   price  = 0.0;
      ENUM_POSITION_TYPE type = (side == WR_SIDE_BUY) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         if(!m_pos.SelectByIndex(i))
            continue;
         if(m_pos.Symbol() != m_symbol || m_pos.Magic() != m_magic)
            continue;
         if(m_pos.PositionType() != type)
            continue;
         if(m_pos.Time() >= latest)
           {
            latest = m_pos.Time();
            price  = m_pos.PriceOpen();
           }
        }
      return price;
     }

   bool HasPendingOrder(const ENUM_WR_SIDE side)
     {
      ENUM_ORDER_TYPE type = (side == WR_SIDE_BUY) ? ORDER_TYPE_BUY_STOP : ORDER_TYPE_SELL_STOP;
      for(int i = OrdersTotal() - 1; i >= 0; i--)
        {
         if(!m_ord.SelectByIndex(i))
            continue;
         if(m_ord.Symbol() != m_symbol || m_ord.Magic() != m_magic)
            continue;
         if(m_ord.OrderType() == type)
            return true;
        }
      return false;
     }

   bool HasActiveSetup(const ENUM_WR_SIDE side)
     {
      return (CountOpenPositions(side) > 0 || HasPendingOrder(side));
     }

   bool CanStartNewSetup(const int direction)
     {
      if(m_directionMode == WR_DIR_BUY_ONLY && direction < 0)
         return false;
      if(m_directionMode == WR_DIR_SELL_ONLY && direction > 0)
         return false;

      bool activeBuy  = HasActiveSetup(WR_SIDE_BUY);
      bool activeSell = HasActiveSetup(WR_SIDE_SELL);

      if(m_oneSetupAtTime && (activeBuy || activeSell))
         return false;

      if(m_blockOppositeDirection)
        {
         if(direction > 0 && activeSell)
            return false;
         if(direction < 0 && activeBuy)
            return false;
        }

      // Nao inicia um novo "setup" na mesma direcao se ja ha um ativo -
      // a progressao de tiers (ManageTierProgression) cuida disso, nao um novo sinal.
      if(direction > 0 && activeBuy)
         return false;
      if(direction < 0 && activeSell)
         return false;

      return true;
     }

   // Abre a tier 1 (FirstEntryOrders ordens pendentes stop) no rompimento
   // do fechamento da vela de rejeicao + BreakClosePips.
   void PlaceInitialSetup(const int direction,const double patternClosePrice)
     {
      if(!CanStartNewSetup(direction))
         return;

      int    digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
      double breakDist = WrPipsToPrice(m_symbol, m_breakClosePips);
      double slDist  = WrPipsToPrice(m_symbol, m_slPips);
      double tpDist  = WrPipsToPrice(m_symbol, m_tpPips);
      double lot     = LotForTier(0);
      double minDist = WrMinStopDistance(m_symbol);
      double ask     = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
      double bid     = SymbolInfoDouble(m_symbol, SYMBOL_BID);

      slDist = MathMax(slDist, minDist);
      tpDist = MathMax(tpDist, minDist);

      m_trade.SetExpertMagicNumber(m_magic);

      int ordersToPlace = OrdersForTier(0);
      for(int i = 0; i < ordersToPlace; i++)
        {
         string comment = StringFormat("%s-%s0-%d", WREA_COMMENT_TAG, (direction > 0 ? "B" : "S"), i + 1);
         bool sent;
         if(direction > 0)
           {
            double entryPrice = MathMax(patternClosePrice + breakDist, ask + minDist);
            entryPrice = NormalizeDouble(entryPrice, digits);
            double sl = NormalizeDouble(entryPrice - slDist, digits);
            double tp = NormalizeDouble(entryPrice + tpDist, digits);
            sent = m_trade.BuyStop(lot, entryPrice, m_symbol, sl, tp, ORDER_TIME_GTC, 0, comment);
           }
         else
           {
            double entryPrice = MathMin(patternClosePrice - breakDist, bid - minDist);
            entryPrice = NormalizeDouble(entryPrice, digits);
            double sl = NormalizeDouble(entryPrice + slDist, digits);
            double tp = NormalizeDouble(entryPrice - tpDist, digits);
            sent = m_trade.SellStop(lot, entryPrice, m_symbol, sl, tp, ORDER_TIME_GTC, 0, comment);
           }

         if(sent)
            PrintFormat("WickReversalEA: ordem pendente #%d aberta (%s) vol=%.2f", i + 1, (direction > 0 ? "BUY STOP" : "SELL STOP"), lot);
         else
            PrintFormat("WickReversalEA: falha ao abrir ordem pendente %s - erro %d", (direction > 0 ? "BUY STOP" : "SELL STOP"), GetLastError());
        }
     }

   // Cancela ordens pendentes deste EA que ja passaram de CancelPendingAfterCandles
   // velas do timeframe de entrada sem serem preenchidas.
   void CancelExpiredPendingOrders(void)
     {
      for(int i = OrdersTotal() - 1; i >= 0; i--)
        {
         if(!m_ord.SelectByIndex(i))
            continue;
         if(m_ord.Symbol() != m_symbol || m_ord.Magic() != m_magic)
            continue;
         if(m_ord.OrderType() != ORDER_TYPE_BUY_STOP && m_ord.OrderType() != ORDER_TYPE_SELL_STOP)
            continue;

         datetime setupTime = (datetime)OrderGetInteger(ORDER_TIME_SETUP);
         int barsSince = iBarShift(m_symbol, m_entryTimeframe, setupTime, false);
         if(barsSince >= m_cancelPendingAfterCandles)
           {
            ulong ticket = m_ord.Ticket();
            if(m_trade.OrderDelete(ticket))
               PrintFormat("WickReversalEA: ordem pendente #%I64u expirou (%d velas) - cancelada", ticket, barsSince);
           }
        }
     }

   // Abre uma posicao a mercado (usado nas tiers 2/3, sempre a favor do movimento ja confirmado).
   void OpenMarketTierPosition(const ENUM_WR_SIDE side,const int tierIdx)
     {
      double lot = LotForTier(tierIdx);
      m_trade.SetExpertMagicNumber(m_magic);

      string comment = StringFormat("%s-%s%d", WREA_COMMENT_TAG, (side == WR_SIDE_BUY ? "B" : "S"), tierIdx);

      bool sent = (side == WR_SIDE_BUY)
                  ? m_trade.Buy(lot, m_symbol, 0.0, 0.0, 0.0, comment)
                  : m_trade.Sell(lot, m_symbol, 0.0, 0.0, 0.0, comment);

      if(!sent)
        {
         PrintFormat("WickReversalEA: falha ao abrir tier %d (%s) - erro %d", tierIdx, (side == WR_SIDE_BUY ? "BUY" : "SELL"), GetLastError());
         return;
        }

      ulong dealTicket = m_trade.ResultDeal();
      ulong posTicket  = 0;
      if(HistoryDealSelect(dealTicket))
         posTicket = (ulong)HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);

      if(posTicket == 0 || !PositionSelectByTicket(posTicket))
         return;

      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      int    digits     = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
      double minDist     = WrMinStopDistance(m_symbol);
      double slDist      = MathMax(WrPipsToPrice(m_symbol, m_slPips), minDist);
      double tpDist      = MathMax(WrPipsToPrice(m_symbol, m_tpPips), minDist);

      double sl = (side == WR_SIDE_BUY) ? NormalizeDouble(openPrice - slDist, digits) : NormalizeDouble(openPrice + slDist, digits);
      double tp = (side == WR_SIDE_BUY) ? NormalizeDouble(openPrice + tpDist, digits) : NormalizeDouble(openPrice - tpDist, digits);

      m_trade.PositionModify(posTicket, sl, tp);

      PrintFormat("WickReversalEA: tier %d aberta a mercado (%s) ticket=%I64u vol=%.2f preco=%.5f",
                  tierIdx, (side == WR_SIDE_BUY ? "BUY" : "SELL"), posTicket, lot, openPrice);
     }

   // Verifica se o setup ativo de um lado avancou o suficiente (ProfitStepPips) para
   // liberar a proxima tier (2 ou 3), e abre as ordens dessa tier a mercado.
   void ManageTierProgression(const ENUM_WR_SIDE side)
     {
      int openCount = CountOpenPositions(side);
      if(openCount == 0 || openCount < TierBoundary(0))
         return; // sem setup ativo, ou tier 1 ainda nao preencheu totalmente

      int nextTierIdx;
      if(openCount < TierBoundary(1))
         nextTierIdx = 1;
      else if(openCount < TierBoundary(2))
         nextTierIdx = 2;
      else
         return; // todas as tiers ja abertas

      if(OrdersForTier(nextTierIdx) <= 0)
         return; // essa tier esta configurada com 0 ordens - pula

      double anchor = LatestOpenPrice(side);
      if(anchor <= 0.0)
         return;

      double stepDist = WrPipsToPrice(m_symbol, m_profitStepPips);
      double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);

      bool movedFavorable = (side == WR_SIDE_BUY) ? (bid - anchor >= stepDist) : (anchor - ask >= stepDist);
      if(!movedFavorable)
         return;

      int ordersToOpen = OrdersForTier(nextTierIdx);
      for(int i = 0; i < ordersToOpen; i++)
         OpenMarketTierPosition(side, nextTierIdx);
     }

   // Fecha todas as posicoes e cancela todas as ordens pendentes deste EA (circuit breaker).
   void CloseAll(void)
     {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         if(!m_pos.SelectByIndex(i))
            continue;
         if(m_pos.Symbol() != m_symbol || m_pos.Magic() != m_magic)
            continue;
         m_trade.PositionClose(m_pos.Ticket());
        }
      for(int i = OrdersTotal() - 1; i >= 0; i--)
        {
         if(!m_ord.SelectByIndex(i))
            continue;
         if(m_ord.Symbol() != m_symbol || m_ord.Magic() != m_magic)
            continue;
         m_trade.OrderDelete(m_ord.Ticket());
        }
     }
  };
