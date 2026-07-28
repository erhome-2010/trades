//+------------------------------------------------------------------+
//|                                                     Defines.mqh |
//|         Constantes, enums e estruturas do BTC HedgeGrid EA.     |
//+------------------------------------------------------------------+
#property strict

#define HGEA_GV_PREFIX "BTCHedgeGridEA_"
#define HGEA_COMMENT_TAG "HG"

enum ENUM_HG_SIDE
  {
   HG_SIDE_BUY  = 0,
   HG_SIDE_SELL = 1
  };

enum ENUM_HG_STATE
  {
   HG_STATE_TRADING       = 0, // Operando normalmente
   HG_STATE_DAILY_LOSS    = 1, // Bloqueado: DailyLoss atingido
   HG_STATE_DAILY_PROFIT  = 2, // Bloqueado: DailyGain atingido
   HG_STATE_MAX_DRAWDOWN  = 3  // Bloqueado: Max Drawdown atingido (kill switch)
  };

// Estado persistido de uma perna (lado) do grid de hedge
struct SGridLegState
  {
   int               count;        // quantas posicoes ja foram abertas neste lado (nao decresce)
   double            anchorPrice;  // preco de abertura da posicao mais recente deste lado
  };
