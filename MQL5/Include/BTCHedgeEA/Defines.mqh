//+------------------------------------------------------------------+
//|                                                     Defines.mqh |
//|                     Constantes e enums compartilhados do BTC EA |
//+------------------------------------------------------------------+
#property strict

#define BTCEA_GV_PREFIX "BTCHedgeEA_"

enum ENUM_TREND_STATE
  {
   TREND_NONE = 0,
   TREND_UP   = 1,
   TREND_DOWN = -1
  };

enum ENUM_EA_STATE
  {
   EA_STATE_TRADING       = 0, // Operando normalmente
   EA_STATE_DAILY_LOSS    = 1, // Bloqueado: DailyLoss atingido
   EA_STATE_DAILY_PROFIT  = 2, // Bloqueado: DailyGain atingido
   EA_STATE_MAX_DRAWDOWN  = 3, // Bloqueado: Max Drawdown atingido (kill switch)
   EA_STATE_OUT_OF_SESSION= 4  // Fora da janela de sessão permitida
  };

// Faixa de magic numbers: magic base = posições principais, magic base+1 = posições de hedge
#define BTCEA_HEDGE_MAGIC_OFFSET 1
