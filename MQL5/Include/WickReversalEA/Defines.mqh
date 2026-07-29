//+------------------------------------------------------------------+
//|                                                     Defines.mqh |
//|      Enums e constantes compartilhados do WickReversal_EA.      |
//+------------------------------------------------------------------+
#property strict

#define WREA_GV_PREFIX "WickReversalEA_"
#define WREA_COMMENT_TAG "WR"

enum ENUM_WR_DIRECTION_MODE
  {
   WR_DIR_BOTH      = 0, // Compra e venda
   WR_DIR_BUY_ONLY  = 1, // Somente compra
   WR_DIR_SELL_ONLY = 2  // Somente venda
  };

enum ENUM_WR_SIDE
  {
   WR_SIDE_BUY  = 0,
   WR_SIDE_SELL = 1
  };

enum ENUM_WR_STATE
  {
   WR_STATE_TRADING           = 0, // Operando normalmente
   WR_STATE_PROFIT_TARGET_HIT = 1, // Bloqueado: meta de lucro de equity atingida (sem restart)
   WR_STATE_PROTECTION_HIT    = 2, // Bloqueado: protecao de drawdown de equity atingida (sem restart)
   WR_STATE_OUT_OF_SESSION    = 3  // Fora da janela de horario permitida
  };
