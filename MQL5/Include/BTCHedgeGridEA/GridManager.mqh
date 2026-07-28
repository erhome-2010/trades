//+------------------------------------------------------------------+
//|                                                 GridManager.mqh |
//| Nucleo do robo de HEDGE GRID:                                   |
//|  - Mantem sempre 1 posicao BUY + 1 posicao SELL abertas.        |
//|  - A cada InpGridStepPoints pontos contra o lado que esta        |
//|    perdendo, abre nova posicao no MESMO lado (media para baixo, |
//|    estilo martingale).                                          |
//|  - A cada InpGridStepPoints pontos a favor do lado que esta      |
//|    ganhando, abre nova posicao a favor e sobe o breakeven das   |
//|    posicoes mais antigas daquele lado (nunca afrouxa o stop).   |
//|  - Volume dobra (ou multiplica por InpVolumeMultiplier) a cada  |
//|    InpLevelsPerTier aberturas, contando por lado.                |
//|  - Cada posicao tem SL/TP fixos em pontos (InpLossPoints /      |
//|    InpGainPoints) a partir da propria entrada - como o volume    |
//|    ja dobra por tier, o resultado em dinheiro desses SL/TP      |
//|    dobra automaticamente junto, sem precisar de logica extra.   |
//|  - Limite de seguranca: InpMaxLevelsPerSide trava novas adicoes |
//|    de martingale por lado (posicoes ja abertas continuam com    |
//|    seu SL/TP normal).                                            |
//+------------------------------------------------------------------+
#property strict

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <BTCHedgeGridEA/Defines.mqh>

class CHgGridManager
  {
private:
   string        m_symbol;
   long          m_magic;
   double        m_baseVolume;
   double        m_volumeMultiplier;
   int           m_levelsPerTier;
   int           m_maxLevelsPerSide;
   double        m_gridStepPoints;
   double        m_gainPoints;
   double        m_lossPoints;
   double        m_breakevenLockPoints;
   ulong         m_slippagePoints;

   CTrade        m_trade;
   CPositionInfo m_pos;

   SGridLegState m_leg[2]; // indexado por ENUM_HG_SIDE

   string GVName(const string suffix)
     {
      return StringFormat("%sGrid_%s_%I64d_%s", HGEA_GV_PREFIX, m_symbol, m_magic, suffix);
     }

   void LoadLegState(const ENUM_HG_SIDE side)
     {
      string cSuf = (side == HG_SIDE_BUY) ? "buyCount" : "sellCount";
      string aSuf = (side == HG_SIDE_BUY) ? "buyAnchor" : "sellAnchor";
      double c = 0.0, a = 0.0;
      if(GlobalVariableCheck(GVName(cSuf)))
         c = GlobalVariableGet(GVName(cSuf));
      if(GlobalVariableCheck(GVName(aSuf)))
         a = GlobalVariableGet(GVName(aSuf));
      m_leg[side].count       = (int)c;
      m_leg[side].anchorPrice = a;
     }

   void SaveLegState(const ENUM_HG_SIDE side)
     {
      string cSuf = (side == HG_SIDE_BUY) ? "buyCount" : "sellCount";
      string aSuf = (side == HG_SIDE_BUY) ? "buyAnchor" : "sellAnchor";
      GlobalVariableSet(GVName(cSuf), (double)m_leg[side].count);
      GlobalVariableSet(GVName(aSuf), m_leg[side].anchorPrice);
     }

public:
   CHgGridManager(void)
     {
      m_baseVolume          = 0.01;
      m_volumeMultiplier    = 2.0;
      m_levelsPerTier       = 3;
      m_maxLevelsPerSide    = 9;
      m_gridStepPoints      = 3000;
      m_gainPoints          = 4000;
      m_lossPoints          = 9000;
      m_breakevenLockPoints = 200;
      m_slippagePoints      = 50;
     }

   void Configure(const string symbol,const long magic,const double baseVolume,
                  const double volumeMultiplier,const int levelsPerTier,const int maxLevelsPerSide,
                  const double gridStepPoints,const double gainPoints,const double lossPoints,
                  const double breakevenLockPoints,const ulong slippagePoints)
     {
      m_symbol              = symbol;
      m_magic               = magic;
      m_baseVolume          = baseVolume;
      m_volumeMultiplier    = volumeMultiplier;
      m_levelsPerTier       = MathMax(1, levelsPerTier);
      m_maxLevelsPerSide    = MathMax(1, maxLevelsPerSide);
      m_gridStepPoints      = gridStepPoints;
      m_gainPoints          = gainPoints;
      m_lossPoints          = lossPoints;
      m_breakevenLockPoints = breakevenLockPoints;
      m_slippagePoints      = slippagePoints;

      m_trade.SetDeviationInPoints(m_slippagePoints);
      m_trade.SetMarginMode();
      m_trade.LogLevel(LOG_LEVEL_ERRORS);
     }

   void Init(void)
     {
      LoadLegState(HG_SIDE_BUY);
      LoadLegState(HG_SIDE_SELL);

      if(CountOpenPositions(HG_SIDE_BUY) == 0 && CountOpenPositions(HG_SIDE_SELL) == 0)
        {
         ResetCycle();
         return;
        }

      // Robustez: se o contador persistido esta zerado mas ja existem posicoes abertas
      // (ex.: global variables perdidas), reconstroi a partir das posicoes existentes.
      if(m_leg[HG_SIDE_BUY].count == 0 && CountOpenPositions(HG_SIDE_BUY) > 0)
        {
         m_leg[HG_SIDE_BUY].count       = CountOpenPositions(HG_SIDE_BUY);
         m_leg[HG_SIDE_BUY].anchorPrice = LatestOpenPrice(HG_SIDE_BUY);
         SaveLegState(HG_SIDE_BUY);
        }
      if(m_leg[HG_SIDE_SELL].count == 0 && CountOpenPositions(HG_SIDE_SELL) > 0)
        {
         m_leg[HG_SIDE_SELL].count       = CountOpenPositions(HG_SIDE_SELL);
         m_leg[HG_SIDE_SELL].anchorPrice = LatestOpenPrice(HG_SIDE_SELL);
         SaveLegState(HG_SIDE_SELL);
        }
     }

   void ResetCycle(void)
     {
      m_leg[HG_SIDE_BUY].count        = 0;
      m_leg[HG_SIDE_BUY].anchorPrice  = 0.0;
      m_leg[HG_SIDE_SELL].count       = 0;
      m_leg[HG_SIDE_SELL].anchorPrice = 0.0;
      SaveLegState(HG_SIDE_BUY);
      SaveLegState(HG_SIDE_SELL);
     }

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

   double VolumeForOpening(const int openingIndexZeroBased)
     {
      int tier = openingIndexZeroBased / m_levelsPerTier;
      double vol = m_baseVolume * MathPow(m_volumeMultiplier, tier);
      return NormalizeVolume(vol);
     }

   // Soma de volume necessaria para abrir "n" posicoes seguidas neste lado a partir do zero -
   // usado so para estimar exposicao maxima (informativo, painel/README).
   double SumVolumeForLevels(const int n)
     {
      double total = 0.0;
      for(int i = 0; i < n; i++)
         total += VolumeForOpening(i);
      return total;
     }

   int CountOpenPositions(const ENUM_HG_SIDE side)
     {
      int count = 0;
      ENUM_POSITION_TYPE type = (side == HG_SIDE_BUY) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
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

   double LegFloatingPnL(const ENUM_HG_SIDE side)
     {
      double pnl = 0.0;
      ENUM_POSITION_TYPE type = (side == HG_SIDE_BUY) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         if(!m_pos.SelectByIndex(i))
            continue;
         if(m_pos.Symbol() != m_symbol || m_pos.Magic() != m_magic)
            continue;
         if(m_pos.PositionType() == type)
            pnl += m_pos.Profit() + m_pos.Swap();
        }
      return pnl;
     }

   double LegOpenVolume(const ENUM_HG_SIDE side)
     {
      double vol = 0.0;
      ENUM_POSITION_TYPE type = (side == HG_SIDE_BUY) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         if(!m_pos.SelectByIndex(i))
            continue;
         if(m_pos.Symbol() != m_symbol || m_pos.Magic() != m_magic)
            continue;
         if(m_pos.PositionType() == type)
            vol += m_pos.Volume();
        }
      return vol;
     }

   double LegAvgOpenPrice(const ENUM_HG_SIDE side)
     {
      double sumVolPrice = 0.0, sumVol = 0.0;
      ENUM_POSITION_TYPE type = (side == HG_SIDE_BUY) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         if(!m_pos.SelectByIndex(i))
            continue;
         if(m_pos.Symbol() != m_symbol || m_pos.Magic() != m_magic)
            continue;
         if(m_pos.PositionType() == type)
           {
            sumVolPrice += m_pos.PriceOpen() * m_pos.Volume();
            sumVol      += m_pos.Volume();
           }
        }
      return (sumVol > 0.0) ? sumVolPrice / sumVol : 0.0;
     }

   double LatestOpenPrice(const ENUM_HG_SIDE side)
     {
      datetime latest = 0;
      double   price  = 0.0;
      ENUM_POSITION_TYPE type = (side == HG_SIDE_BUY) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
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

   int    LegOpeningsCount(const ENUM_HG_SIDE side) const { return m_leg[side].count; }
   double LegAnchorPrice(const ENUM_HG_SIDE side)   const { return m_leg[side].anchorPrice; }
   bool   LegCapReached(const ENUM_HG_SIDE side)    const { return m_leg[side].count >= m_maxLevelsPerSide; }
   double LegNextVolume(const ENUM_HG_SIDE side)          { return VolumeForOpening(m_leg[side].count); }

   int    MaxLevelsPerSide(void) const { return m_maxLevelsPerSide; }
   double GridStepPoints(void)   const { return m_gridStepPoints; }
   double GainPoints(void)       const { return m_gainPoints; }
   double LossPoints(void)       const { return m_lossPoints; }
   double BaseVolume(void)       const { return m_baseVolume; }

   // Abre uma posicao no lado indicado, na proxima tier de volume. Retorna o ticket (0 se falhar).
   ulong OpenLegPosition(const ENUM_HG_SIDE side)
     {
      double volume      = VolumeForOpening(m_leg[side].count);
      int    openingIndex = m_leg[side].count + 1; // 1-based, so para comentario/log

      m_trade.SetExpertMagicNumber(m_magic);

      string comment = StringFormat("%s-%s-%d", HGEA_COMMENT_TAG, (side == HG_SIDE_BUY ? "B" : "S"), openingIndex);

      bool sent = (side == HG_SIDE_BUY)
                  ? m_trade.Buy(volume, m_symbol, 0.0, 0.0, 0.0, comment)
                  : m_trade.Sell(volume, m_symbol, 0.0, 0.0, 0.0, comment);

      if(!sent)
        {
         PrintFormat("BTCHedgeGridEA: falha ao abrir %s #%d vol=%.2f - erro %d",
                     (side == HG_SIDE_BUY ? "COMPRA" : "VENDA"), openingIndex, volume, GetLastError());
         return 0;
        }

      ulong dealTicket = m_trade.ResultDeal();
      ulong posTicket  = 0;
      if(HistoryDealSelect(dealTicket))
         posTicket = (ulong)HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);

      if(posTicket == 0 || !PositionSelectByTicket(posTicket))
        {
         PrintFormat("BTCHedgeGridEA: %s #%d enviada mas ticket da posicao nao foi localizado",
                     (side == HG_SIDE_BUY ? "COMPRA" : "VENDA"), openingIndex);
         m_leg[side].count++;
         SaveLegState(side);
         return posTicket;
        }

      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      int    digits     = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
      double point      = SymbolInfoDouble(m_symbol, SYMBOL_POINT);

      double sl = 0.0, tp = 0.0;
      if(side == HG_SIDE_BUY)
        {
         if(m_lossPoints > 0.0) sl = NormalizeDouble(openPrice - m_lossPoints * point, digits);
         if(m_gainPoints > 0.0) tp = NormalizeDouble(openPrice + m_gainPoints * point, digits);
        }
      else
        {
         if(m_lossPoints > 0.0) sl = NormalizeDouble(openPrice + m_lossPoints * point, digits);
         if(m_gainPoints > 0.0) tp = NormalizeDouble(openPrice - m_gainPoints * point, digits);
        }

      if(sl != 0.0 || tp != 0.0)
        {
         if(!m_trade.PositionModify(posTicket, sl, tp))
            PrintFormat("BTCHedgeGridEA: falha ao definir SL/TP da posicao #%I64u - erro %d", posTicket, GetLastError());
        }

      m_leg[side].count++;
      m_leg[side].anchorPrice = openPrice;
      SaveLegState(side);

      PrintFormat("BTCHedgeGridEA: %s aberta #%d ticket=%I64u vol=%.2f preco=%.5f SL=%.5f TP=%.5f",
                  (side == HG_SIDE_BUY ? "COMPRA" : "VENDA"), openingIndex, posTicket, volume, openPrice, sl, tp);

      return posTicket;
     }

   // Sobe o stop das posicoes existentes do lado para o breakeven+trava (nunca afrouxa o stop).
   void RaiseBreakeven(const ENUM_HG_SIDE side)
     {
      double point      = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      int    digits      = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
      long   stopsLevel  = SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL);
      double bid         = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      double ask         = SymbolInfoDouble(m_symbol, SYMBOL_ASK);

      ENUM_POSITION_TYPE type = (side == HG_SIDE_BUY) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;

      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         if(!m_pos.SelectByIndex(i))
            continue;
         if(m_pos.Symbol() != m_symbol || m_pos.Magic() != m_magic)
            continue;
         if(m_pos.PositionType() != type)
            continue;

         double openPrice = m_pos.PriceOpen();
         double curSl      = m_pos.StopLoss();
         double curTp      = m_pos.TakeProfit();
         ulong  ticket      = m_pos.Ticket();

         double candidate = (side == HG_SIDE_BUY) ? openPrice + m_breakevenLockPoints * point
                                                     : openPrice - m_breakevenLockPoints * point;
         candidate = NormalizeDouble(candidate, digits);

         bool improves = (side == HG_SIDE_BUY) ? (candidate > curSl) : (curSl == 0.0 || candidate < curSl);
         if(!improves)
            continue;

         double refPrice    = (side == HG_SIDE_BUY) ? bid : ask;
         double minDistance = stopsLevel * point;
         if(minDistance > 0.0 && MathAbs(refPrice - candidate) < minDistance)
            continue; // muito perto do preco atual, tenta de novo no proximo tick

         if(m_trade.PositionModify(ticket, candidate, curTp))
            PrintFormat("BTCHedgeGridEA: breakeven ajustado #%I64u novo SL=%.5f", ticket, candidate);
        }
     }

   void ManageGridAdditions(const ENUM_HG_SIDE side,const bool spreadOk)
     {
      if(CountOpenPositions(side) == 0)
         return; // acabou de reabrir, aguarda o proximo tick para avaliar movimento
      if(m_leg[side].count >= m_maxLevelsPerSide)
         return; // limite de seguranca atingido para este lado

      double pnl   = LegFloatingPnL(side);
      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      double bid   = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      double ask   = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
      double anchor = m_leg[side].anchorPrice;

      if(anchor <= 0.0 || m_gridStepPoints <= 0.0)
         return;

      double stepPrice = m_gridStepPoints * point;

      if(pnl < 0.0)
        {
         bool triggered = (side == HG_SIDE_BUY) ? (bid <= anchor - stepPrice) : (ask >= anchor + stepPrice);
         if(triggered && spreadOk)
            OpenLegPosition(side); // media para baixo (martingale) no lado perdedor
        }
      else if(pnl > 0.0)
        {
         bool triggered = (side == HG_SIDE_BUY) ? (bid >= anchor + stepPrice) : (ask <= anchor - stepPrice);
         if(triggered)
           {
            if(spreadOk)
               OpenLegPosition(side); // escala a favor no lado ganhador
            RaiseBreakeven(side);     // trava lucro mesmo se o spread bloquear a nova entrada
           }
        }
     }

   // Chamado a cada tick: garante as duas pernas abertas e gerencia adicoes de grid.
   // spreadOk = false apenas adia novas ordens (abertura de perna vazia / adicoes de grid);
   // o breakeven do lado ganhador continua sendo ajustado normalmente.
   void Manage(const bool spreadOk = true)
     {
      if(CountOpenPositions(HG_SIDE_BUY) == 0 && CountOpenPositions(HG_SIDE_SELL) == 0 &&
         (m_leg[HG_SIDE_BUY].count > 0 || m_leg[HG_SIDE_SELL].count > 0))
         ResetCycle();

      if(spreadOk)
        {
         if(CountOpenPositions(HG_SIDE_BUY) == 0)
            OpenLegPosition(HG_SIDE_BUY);
         if(CountOpenPositions(HG_SIDE_SELL) == 0)
            OpenLegPosition(HG_SIDE_SELL);
        }

      ManageGridAdditions(HG_SIDE_BUY, spreadOk);
      ManageGridAdditions(HG_SIDE_SELL, spreadOk);
     }

   // Fecha todas as posicoes deste EA (circuit breaker) e reseta o ciclo.
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
      ResetCycle();
     }
  };
