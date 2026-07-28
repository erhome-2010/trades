//+------------------------------------------------------------------+
//|                                                 TradeLogger.mqh |
//| Exporta CSVs para a pasta "Common\Files" do terminal (compar-   |
//| tilhada entre todos os terminais MT5 da maquina), consumidos    |
//| pelo painel web (Dashboard/index.html):                         |
//|   BTCHedgeGrid_<magic>_trades.csv  - historico de trades (append)|
//|   BTCHedgeGrid_<magic>_status.csv  - snapshot do estado atual    |
//+------------------------------------------------------------------+
#property strict

#include <BTCHedgeGridEA/Defines.mqh>

class CHgTradeLogger
  {
private:
   long   m_magic;
   bool   m_enabled;
   string m_tradesFile;
   string m_statusFile;

   string SideName(const ENUM_HG_SIDE side)
     {
      return (side == HG_SIDE_BUY) ? "BUY" : "SELL";
     }

   string ReasonName(const long reason)
     {
      switch(reason)
        {
         case DEAL_REASON_SL:     return "SL";
         case DEAL_REASON_TP:     return "TP";
         case DEAL_REASON_SO:     return "STOPOUT";
         case DEAL_REASON_EXPERT: return "EA";
         case DEAL_REASON_CLIENT:
         case DEAL_REASON_MOBILE:
         case DEAL_REASON_WEB:    return "MANUAL";
         default:                 return "OUTRO";
        }
     }

public:
   CHgTradeLogger(void)
     {
      m_magic   = 0;
      m_enabled = true;
     }

   void Configure(const long magic,const bool enabled)
     {
      m_magic      = magic;
      m_enabled    = enabled;
      m_tradesFile = StringFormat("BTCHedgeGrid_%I64d_trades.csv", magic);
      m_statusFile = StringFormat("BTCHedgeGrid_%I64d_status.csv", magic);
     }

   void EnsureTradesHeader(void)
     {
      if(!m_enabled)
         return;
      if(FileIsExist(m_tradesFile, FILE_COMMON))
         return;

      int h = FileOpen(m_tradesFile, FILE_WRITE | FILE_CSV | FILE_COMMON | FILE_ANSI, ',');
      if(h == INVALID_HANDLE)
        {
         PrintFormat("BTCHedgeGridEA: falha ao criar %s - erro %d", m_tradesFile, GetLastError());
         return;
        }
      FileWrite(h, "close_time", "side", "ticket", "comment", "volume", "open_price", "close_price", "profit", "reason");
      FileClose(h);
     }

   // Registra uma posicao ja encerrada (busca os deals de abertura/fechamento no historico)
   void LogClosedPosition(const ulong positionId)
     {
      if(!m_enabled)
         return;
      if(!HistorySelectByPosition((long)positionId))
         return;

      bool   haveOpen = false, haveClose = false;
      double openPrice = 0.0, closePrice = 0.0, volume = 0.0, profit = 0.0;
      datetime closeTime = 0;
      long   reason = -1;
      string comment = "";
      ENUM_HG_SIDE side = HG_SIDE_BUY;

      int total = HistoryDealsTotal();
      for(int i = 0; i < total; i++)
        {
         ulong dealTicket = HistoryDealGetTicket(i);
         if(dealTicket == 0)
            continue;

         long entry = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
         if(entry == DEAL_ENTRY_IN)
           {
            openPrice = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
            volume    = HistoryDealGetDouble(dealTicket, DEAL_VOLUME);
            comment   = HistoryDealGetString(dealTicket, DEAL_COMMENT);
            long dtype = HistoryDealGetInteger(dealTicket, DEAL_TYPE);
            side      = (dtype == DEAL_TYPE_BUY) ? HG_SIDE_BUY : HG_SIDE_SELL;
            haveOpen  = true;
           }
         else if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY)
           {
            closePrice = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
            closeTime  = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);
            profit    += HistoryDealGetDouble(dealTicket, DEAL_PROFIT)
                       + HistoryDealGetDouble(dealTicket, DEAL_SWAP)
                       + HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
            reason     = HistoryDealGetInteger(dealTicket, DEAL_REASON);
            haveClose  = true;
           }
        }

      if(!haveOpen || !haveClose)
         return;

      EnsureTradesHeader();

      int h = FileOpen(m_tradesFile, FILE_READ | FILE_WRITE | FILE_CSV | FILE_COMMON | FILE_ANSI, ',');
      if(h == INVALID_HANDLE)
        {
         PrintFormat("BTCHedgeGridEA: falha ao abrir %s para gravar trade - erro %d", m_tradesFile, GetLastError());
         return;
        }
      FileSeek(h, 0, SEEK_END);
      FileWrite(h, TimeToString(closeTime, TIME_DATE | TIME_MINUTES), SideName(side), (long)positionId,
                comment, DoubleToString(volume, 2), DoubleToString(openPrice, 2), DoubleToString(closePrice, 2),
                DoubleToString(profit, 2), ReasonName(reason));
      FileClose(h);
     }

   void WriteStatusSnapshot(const string eaName,const ENUM_HG_STATE state,const double equity,const double balance,
                             const double dailyPnlPct,const double dailyPnlUsd,const double ddPct,
                             const int buyOpen,const int buyTier,const double buyNextVol,const double buyAvg,const double buyPnl,
                             const int sellOpen,const int sellTier,const double sellNextVol,const double sellAvg,const double sellPnl)
     {
      if(!m_enabled)
         return;

      int h = FileOpen(m_statusFile, FILE_WRITE | FILE_CSV | FILE_COMMON | FILE_ANSI, ',');
      if(h == INVALID_HANDLE)
        {
         PrintFormat("BTCHedgeGridEA: falha ao gravar %s - erro %d", m_statusFile, GetLastError());
         return;
        }

      FileWrite(h, "field", "value");
      FileWrite(h, "updated_at", TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS));
      FileWrite(h, "ea_name", eaName);
      FileWrite(h, "state", EnumToString(state));
      FileWrite(h, "equity", DoubleToString(equity, 2));
      FileWrite(h, "balance", DoubleToString(balance, 2));
      FileWrite(h, "daily_pnl_pct", DoubleToString(dailyPnlPct, 2));
      FileWrite(h, "daily_pnl_usd", DoubleToString(dailyPnlUsd, 2));
      FileWrite(h, "drawdown_pct", DoubleToString(ddPct, 2));
      FileWrite(h, "buy_open", (long)buyOpen);
      FileWrite(h, "buy_tier", (long)buyTier);
      FileWrite(h, "buy_next_volume", DoubleToString(buyNextVol, 2));
      FileWrite(h, "buy_avg_price", DoubleToString(buyAvg, 2));
      FileWrite(h, "buy_floating_pnl", DoubleToString(buyPnl, 2));
      FileWrite(h, "sell_open", (long)sellOpen);
      FileWrite(h, "sell_tier", (long)sellTier);
      FileWrite(h, "sell_next_volume", DoubleToString(sellNextVol, 2));
      FileWrite(h, "sell_avg_price", DoubleToString(sellAvg, 2));
      FileWrite(h, "sell_floating_pnl", DoubleToString(sellPnl, 2));
      FileClose(h);
     }
  };
