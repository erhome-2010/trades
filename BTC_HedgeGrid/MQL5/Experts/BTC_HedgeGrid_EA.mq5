//+------------------------------------------------------------------+
//|                                            BTC_HedgeGrid_EA.mq5 |
//| Robo de HEDGE GRID para BTCUSD no MetaTrader 5 - conta HEDGING. |
//|                                                                  |
//| Mantem sempre 1 posicao de COMPRA e 1 de VENDA abertas ao mesmo |
//| tempo. A cada InpGridStepPoints pontos contra o lado que esta   |
//| perdendo, abre nova posicao no mesmo lado (media para baixo,    |
//| estilo martingale). A cada InpGridStepPoints pontos a favor do  |
//| lado que esta ganhando, abre nova posicao a favor e sobe o     |
//| breakeven das posicoes mais antigas daquele lado. O volume      |
//| dobra a cada InpLevelsPerTier aberturas (contando por lado).    |
//| Cada posicao tem Gain (TP) e Loss (SL) fixos em pontos a partir |
//| da propria entrada - como o volume ja dobra por tier, o        |
//| resultado em dinheiro desses TP/SL dobra automaticamente.       |
//|                                                                  |
//| ATENCAO - ISTO E UMA ESTRATEGIA TIPO MARTINGALE/GRID:            |
//| o lado perdedor acumula posicoes e aumenta volume enquanto o    |
//| preco nao reverte. InpMaxLevelsPerSide limita quantas aberturas |
//| de martingale sao permitidas por lado antes de o EA parar de    |
//| adicionar (as posicoes ja abertas continuam com seu SL normal), |
//| mas isso NAO elimina o risco - uma tendencia forte e prolongada |
//| pode gerar perdas grandes. Use InpDailyLossPercent e             |
//| InpMaxDrawdownPercent como redes de seguranca finais, calibre   |
//| todos os pontos ao seu simbolo/corretora, e SEMPRE valide em    |
//| backtest + conta demo antes de conta real.                      |
//|                                                                  |
//| Exige conta em modo HEDGING. Compile e faca backtest completo   |
//| (Strategy Tester) antes de qualquer uso em conta real.          |
//+------------------------------------------------------------------+
#property copyright "BTC HedgeGrid EA"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <BTCHedgeGridEA/Defines.mqh>
#include <BTCHedgeGridEA/RiskManager.mqh>
#include <BTCHedgeGridEA/GridManager.mqh>
#include <BTCHedgeGridEA/TradeLogger.mqh>
#include <BTCHedgeGridEA/Dashboard.mqh>

//--- Inputs: identificacao
input long   InpMagicNumber          = 770001;  // Magic number (compra e venda usam o mesmo, diferenciados pelo tipo)

//--- Inputs: valor de entrada e progressao de volume (martingale)
input double InpBaseVolume           = 0.01;    // Volume da entrada inicial (a "quantidade de entrada" - tudo mais escala a partir dela)
input double InpVolumeMultiplier     = 2.0;     // Multiplicador de volume a cada tier (2.0 = dobra)
input int    InpLevelsPerTier        = 3;       // Quantas aberturas no mesmo volume antes de multiplicar (3 = abre 3x, dobra, abre 3x, dobra...)
input int    InpMaxLevelsPerSide     = 9;       // Limite de seguranca: maximo de aberturas de grid por lado (9 = 3 tiers: 0,01/0,02/0,04)

//--- Inputs: grid (pontos)
input double InpGridStepPoints       = 3000;    // Pontos de movimento (a favor OU contra) para abrir a proxima posicao do grid - CALIBRE para o seu simbolo (veja o log de sugestao no OnInit)
input double InpGainPoints           = 4000;    // Gain (Take Profit) de cada posicao, em pontos, a partir da propria entrada
input double InpLossPoints           = 9000;    // Loss (Stop Loss) de cada posicao, em pontos, a partir da propria entrada - o valor em dinheiro dobra sozinho a cada tier de volume
input double InpBreakevenLockPoints  = 200;     // Pontos travados acima/abaixo da entrada quando o breakeven do lado ganhador e ajustado

//--- Inputs: filtros operacionais
input double InpMaxSpreadPoints      = 800;     // Spread maximo (pontos) para permitir novas aberturas (breakeven continua sendo ajustado mesmo com spread alto)
input ulong  InpSlippagePoints       = 50;      // Desvio maximo (pontos) tolerado nas ordens

//--- Inputs: DailyGain / DailyLoss / Max Drawdown (circuit breakers, resetam todo dia)
input bool   InpUseEquityForDaily    = true;    // true = usa equity, false = usa balance para o calculo diario
input double InpDailyLossPercent     = 5.0;     // % de perda diaria (DailyLoss) que fecha tudo e bloqueia novas entradas ate o proximo dia
input double InpDailyProfitPercent   = 0.0;     // % de ganho diario (DailyGain) que bloqueia novas entradas (0 = desabilitado); posicoes abertas continuam sendo geridas
input double InpMaxDrawdownPercent   = 20.0;    // % de drawdown do pico de equity que interrompe o EA (kill switch, nao reseta por dia)

//--- Inputs: painel, exportacao e notificacoes
input bool   InpEnableDashboard      = true;    // Exibe painel no grafico
input bool   InpEnableCsvExport      = true;    // Exporta CSVs (Common\Files) para o painel web (Dashboard/index.html)
input int    InpExportIntervalSeconds= 15;      // Intervalo minimo (segundos) entre gravacoes do snapshot de status
input bool   InpEnablePushNotify     = false;   // Envia push notification em eventos importantes
input bool   InpEnableEmailNotify    = false;   // Envia e-mail em eventos importantes (requer config no terminal)

//--- Objetos globais do EA
CHgRiskManager  g_risk;
CHgGridManager  g_grid;
CHgTradeLogger  g_logger;
CHgDashboard    g_dash;

ENUM_HG_STATE   g_lastState = HG_STATE_TRADING;
datetime        g_lastExport = 0;

//+------------------------------------------------------------------+
void NotifyEvent(const string message)
  {
   Print("BTCHedgeGridEA: ", message);
   if(InpEnablePushNotify && !MQLInfoInteger(MQL_TESTER))
      SendNotification(StringSubstr(message, 0, 255));
   if(InpEnableEmailNotify && !MQLInfoInteger(MQL_TESTER))
      SendMail("BTCHedgeGridEA - " + _Symbol, message);
  }

//+------------------------------------------------------------------+
bool SpreadOk(void)
  {
   long spreadPoints = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   return (InpMaxSpreadPoints <= 0 || spreadPoints <= InpMaxSpreadPoints);
  }

//+------------------------------------------------------------------+
// Coleta os tickets de todas as posicoes abertas deste EA neste simbolo.
void CollectOpenTickets(ulong &out[])
  {
   ArrayResize(out, 0);
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;
      int n = ArraySize(out);
      ArrayResize(out, n + 1);
      out[n] = ticket;
     }
  }

//+------------------------------------------------------------------+
bool TicketInArray(const ulong ticket,const ulong &arr[])
  {
   for(int i = 0; i < ArraySize(arr); i++)
      if(arr[i] == ticket)
         return true;
   return false;
  }

//+------------------------------------------------------------------+
// Registra no CSV de historico qualquer posicao que estava aberta no inicio do
// tick e nao esta mais (fechada por SL, TP, breakeven-stopout ou circuit breaker).
void LogClosedTickets(const ulong &before[],const ulong &after[])
  {
   if(!InpEnableCsvExport)
      return;
   for(int i = 0; i < ArraySize(before); i++)
     {
      if(!TicketInArray(before[i], after))
         g_logger.LogClosedPosition(before[i]);
     }
  }

//+------------------------------------------------------------------+
// Estimativa do pior caso (em USD) se todas as posicoes de um lado, ate o
// limite InpMaxLevelsPerSide, forem encerradas no Loss individual. Puramente
// informativo (painel/log) - nao altera o comportamento do EA.
double EstimateWorstCaseUsdPerSide(void)
  {
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double point     = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(tickSize <= 0.0 || tickValue <= 0.0)
      return 0.0;

   double lossPerLot = (InpLossPoints * point / tickSize) * tickValue;
   double sumVolume  = g_grid.SumVolumeForLevels(InpMaxLevelsPerSide);
   return sumVolume * lossPerLot;
  }

//+------------------------------------------------------------------+
// Sugestao (apenas informativa) de InpGridStepPoints/InpGainPoints/InpLossPoints
// com base na volatilidade recente (ATR H1), para ajudar a calibrar um valor
// "saudavel" para o simbolo/corretora atual - nao aplica nada automaticamente.
void PrintCalibrationSuggestion(void)
  {
   int atrHandle = iATR(_Symbol, PERIOD_H1, 14);
   if(atrHandle == INVALID_HANDLE)
      return;

   double atrBuf[];
   ArraySetAsSeries(atrBuf, true);
   if(CopyBuffer(atrHandle, 0, 1, 1, atrBuf) > 0)
     {
      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      if(point > 0.0)
        {
         double atrPoints = atrBuf[0] / point;
         PrintFormat("BTCHedgeGridEA: ATR(H1,14) atual = %.1f pontos. Sugestao de referencia (ajuste ao seu apetite de risco): "
                     "GridStepPoints ~ %.0f (0.5x ATR), GainPoints ~ %.0f (1x ATR), LossPoints ~ %.0f (2x ATR). "
                     "Valores atuais configurados: Grid=%.0f Gain=%.0f Loss=%.0f",
                     atrPoints, atrPoints * 0.5, atrPoints * 1.0, atrPoints * 2.0,
                     InpGridStepPoints, InpGainPoints, InpLossPoints);
        }
     }
   IndicatorRelease(atrHandle);
  }

//+------------------------------------------------------------------+
void UpdateDashboardAndExport(const ENUM_HG_STATE state)
  {
   int buyOpen   = g_grid.CountOpenPositions(HG_SIDE_BUY);
   int sellOpen  = g_grid.CountOpenPositions(HG_SIDE_SELL);
   int buyTier   = g_grid.LegOpeningsCount(HG_SIDE_BUY);
   int sellTier  = g_grid.LegOpeningsCount(HG_SIDE_SELL);
   double buyNextVol  = g_grid.LegNextVolume(HG_SIDE_BUY);
   double sellNextVol = g_grid.LegNextVolume(HG_SIDE_SELL);
   double buyPnl  = g_grid.LegFloatingPnL(HG_SIDE_BUY);
   double sellPnl = g_grid.LegFloatingPnL(HG_SIDE_SELL);

   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double dailyPct = g_risk.DailyPnLPercent();
   double dailyUsd = g_risk.DailyPnLMoney();
   double ddPct    = g_risk.DrawdownFromPeakPercent();

   if(InpEnableDashboard)
      g_dash.Update(state, dailyPct, dailyUsd, ddPct, equity, balance,
                    buyOpen, buyTier, InpMaxLevelsPerSide, buyNextVol, buyPnl,
                    sellOpen, sellTier, InpMaxLevelsPerSide, sellNextVol, sellPnl,
                    EstimateWorstCaseUsdPerSide());

   if(InpEnableCsvExport && (TimeCurrent() - g_lastExport >= InpExportIntervalSeconds))
     {
      g_logger.WriteStatusSnapshot("BTC HedgeGrid EA", state, equity, balance, dailyPct, dailyUsd, ddPct,
                                    buyOpen, buyTier, buyNextVol, g_grid.LegAvgOpenPrice(HG_SIDE_BUY), buyPnl,
                                    sellOpen, sellTier, sellNextVol, g_grid.LegAvgOpenPrice(HG_SIDE_SELL), sellPnl);
      g_lastExport = TimeCurrent();
     }
  }

//+------------------------------------------------------------------+
int OnInit(void)
  {
   if((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
     {
      Print("BTCHedgeGridEA: esta EA requer conta em modo HEDGING. Abortando.");
      return(INIT_FAILED);
     }

   g_risk.Configure(_Symbol, InpMagicNumber, InpDailyLossPercent, InpDailyProfitPercent,
                     InpMaxDrawdownPercent, InpUseEquityForDaily);
   g_risk.Init();

   g_grid.Configure(_Symbol, InpMagicNumber, InpBaseVolume, InpVolumeMultiplier, InpLevelsPerTier,
                     InpMaxLevelsPerSide, InpGridStepPoints, InpGainPoints, InpLossPoints,
                     InpBreakevenLockPoints, InpSlippagePoints);
   g_grid.Init();

   g_logger.Configure(InpMagicNumber, InpEnableCsvExport);
   g_logger.EnsureTradesHeader();

   if(InpEnableDashboard)
      g_dash.Init(ChartID(), IntegerToString(InpMagicNumber));

   g_lastState  = HG_STATE_TRADING;
   g_lastExport = 0;

   PrintCalibrationSuggestion();
   PrintFormat("BTCHedgeGridEA inicializado. Magic=%I64d Symbol=%s BaseVolume=%.2f MaxLevelsPerSide=%d "
               "Pior caso estimado por lado ~%.2f USD (se todos os niveis abrirem e baterem o Loss)",
               InpMagicNumber, _Symbol, InpBaseVolume, InpMaxLevelsPerSide, EstimateWorstCaseUsdPerSide());

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(InpEnableDashboard)
      g_dash.Remove();
  }

//+------------------------------------------------------------------+
void OnTick(void)
  {
   ulong before[];
   CollectOpenTickets(before);

   if(g_risk.CheckNewDay())
      NotifyEvent("Novo dia de negociacao - baseline diario resetado.");

   ENUM_HG_STATE state = g_risk.Evaluate();

   if(state == HG_STATE_DAILY_LOSS || state == HG_STATE_MAX_DRAWDOWN)
     {
      if(g_lastState != state)
        {
         g_grid.CloseAll();
         NotifyEvent(StringFormat("Circuit breaker acionado (%s). Todas as posicoes encerradas. P/L diario=%.2f%% DD=%.2f%%",
                     EnumToString(state), g_risk.DailyPnLPercent(), g_risk.DrawdownFromPeakPercent()));
        }
      g_lastState = state;

      ulong after1[];
      CollectOpenTickets(after1);
      LogClosedTickets(before, after1);

      UpdateDashboardAndExport(state);
      return;
     }

   bool allowNewEntries = SpreadOk() && (state != HG_STATE_DAILY_PROFIT);

   if(state == HG_STATE_DAILY_PROFIT && g_lastState != state)
      NotifyEvent(StringFormat("Meta de DailyGain atingida (%.2f%%). Bloqueando novas entradas ate o proximo dia.",
                  g_risk.DailyPnLPercent()));

   g_lastState = state;

   g_grid.Manage(allowNewEntries);

   ulong after[];
   CollectOpenTickets(after);
   LogClosedTickets(before, after);

   UpdateDashboardAndExport(state);
  }
//+------------------------------------------------------------------+
