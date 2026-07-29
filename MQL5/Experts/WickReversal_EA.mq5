//+------------------------------------------------------------------+
//|                                             WickReversal_EA.mq5 |
//| Robo generico (qualquer simbolo/timeframe) para MetaTrader 5 - |
//| conta HEDGING. Inspirado na ESTRUTURA de recursos observada no  |
//| .set de uma EA comercial ("wick rejection" + filtro de media    |
//| movel + confluencia multi-timeframe + entradas em piramide por  |
//| tiers + protecao de equity com reinicio automatico) - a logica  |
//| de deteccao do padrao e uma implementacao propria (pin bar      |
//| classico), nao uma copia do codigo-fonte daquele produto, que   |
//| nao esta disponivel.                                            |
//|                                                                  |
//| Nucleo: detecta velas de rejeicao de pavio (pin bar) no         |
//| timeframe de entrada, filtradas por media movel de tendencia e, |
//| opcionalmente, por confluencia do mesmo padrao em varios outros |
//| timeframes. Ao sinal confirmado, abre um lote de ordens         |
//| PENDENTES stop no rompimento da vela (tier 1). Se o preco       |
//| avancar a favor, piramida com mais 2 tiers (a mercado, nunca    |
//| contra o proprio lado perdedor - nao e martingale). SL/TP fixos |
//| em pips, breakeven e trailing opcionais, protecao de equity     |
//| (meta de lucro / drawdown) com opcao de reiniciar sozinho.       |
//|                                                                  |
//| Todas as distancias sao em "pips" (10 pontos em simbolos de 3/5 |
//| casas, 1 ponto em simbolos de 2/4 casas) - funciona tanto em    |
//| BTCUSD quanto em XAUUSD/forex, ajustando so os valores.          |
//|                                                                  |
//| ATENCAO: compile e faca backtest completo antes de qualquer uso |
//| real. Nenhuma configuracao aqui e garantia de lucro.             |
//+------------------------------------------------------------------+
#property copyright "Wick Reversal EA"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <WickReversalEA/Defines.mqh>
#include <WickReversalEA/PipUtils.mqh>
#include <WickReversalEA/WickSignal.mqh>
#include <WickReversalEA/SetupManager.mqh>
#include <WickReversalEA/PositionManager.mqh>
#include <WickReversalEA/EquityGuard.mqh>
#include <WickReversalEA/Dashboard.mqh>

//--- Inputs: geral
input long   InpMagicNumber            = 550001;      // Magic number

//--- Inputs: direcao
input ENUM_WR_DIRECTION_MODE InpDirectionMode = WR_DIR_BOTH; // Direcao permitida (compra/venda/ambas)
input bool   InpBlockOppositeDirection = true;         // Bloqueia abrir na direcao oposta enquanto houver setup ativo do outro lado
input bool   InpOneSetupAtTime         = false;        // So permite um setup ativo por vez (qualquer direcao) - espera ficar tudo flat

//--- Inputs: horario de negociacao
input bool   InpUseTradingTime = false;   // Habilita filtro de janela de horario (server time)
input int    InpStartHour      = 8;       // Hora de inicio (0-23)
input int    InpStartMinute    = 0;       // Minuto de inicio (0-59)
input int    InpEndHour        = 17;      // Hora de fim (0-23)
input int    InpEndMinute      = 0;       // Minuto de fim (0-59)

//--- Inputs: filtro de media movel (tendencia)
input bool                InpUseMAFilter = true;         // Habilita filtro de tendencia por media movel
input ENUM_TIMEFRAMES     InpMATimeframe = PERIOD_M1;     // Timeframe da media
input int                 InpMAPeriod    = 200;           // Periodo da media
input ENUM_MA_METHOD      InpMAMethod    = MODE_EMA;       // Metodo (SMA/EMA/SMMA/LWMA)
input ENUM_APPLIED_PRICE  InpMAPrice     = PRICE_CLOSE;   // Preco aplicado

//--- Inputs: tamanho de lote
input bool   InpUseAutoLot          = true;   // true = piramide de lote por tier; false = lote manual fixo em todas as ordens
input double InpManualLotSize       = 0.01;   // Lote fixo (usado se InpUseAutoLot=false)
input double InpInitialLot          = 0.01;   // Lote da tier 1 (usado se InpUseAutoLot=true)
input double InpProfitStepPips      = 20.0;   // Pips de avanco a favor para liberar a proxima tier (2 ou 3)
input double InpLotIncreasePerStep  = 0.01;   // Quanto o lote cresce por tier (tier N = InitialLot + N*este valor)
input double InpMaximumLot          = 10.0;   // Teto de lote por ordem

//--- Inputs: quantidade de ordens por tier
input int    InpFirstEntryOrders  = 2;   // Quantidade de ordens pendentes na tier 1 (sinal inicial)
input int    InpSecondEntryOrders = 2;   // Quantidade de ordens a mercado na tier 2 (0 = desabilita a tier)
input int    InpThirdEntryOrders  = 2;   // Quantidade de ordens a mercado na tier 3 (0 = desabilita a tier)

//--- Inputs: padrao de vela (wick rejection / pin bar)
input ENUM_TIMEFRAMES InpEntryTimeframe   = PERIOD_M1;  // Timeframe onde o padrao principal e avaliado
input double           InpBodyMaximumPercent = 20.0;      // Corpo da vela <= X% do range total (maxima-minima)
input double           InpWickMinimumPercent = 60.0;      // Pavio de rejeicao >= X% do range total
input double           InpBreakClosePips     = 1.0;       // Pips alem do fechamento da vela de rejeicao para o preco de disparo da ordem pendente

//--- Inputs: stop loss e take profit (pips, fixos por posicao)
input double InpStopLossPips   = 300;   // Stop Loss em pips a partir da propria entrada
input double InpTakeProfitPips = 1000;  // Take Profit em pips a partir da propria entrada

//--- Inputs: breakeven
input bool   InpUseBreakEven     = false;  // Habilita breakeven automatico
input double InpBreakEvenAfterPips = 20;   // Aciona o breakeven quando o lucro atingir X pips
input double InpBreakEvenPlusPips  = 0;    // Pips travados alem da entrada ao acionar o breakeven

//--- Inputs: trailing stop
input bool   InpUseTrailingStop     = true;  // Habilita trailing stop automatico
input double InpTrailingStartPips   = 100;   // So comeca a arrastar o stop apos X pips de lucro
input double InpTrailingDistancePips= 100;   // Distancia do trailing em relacao ao preco atual
input double InpTrailingStepPips    = 1;     // Incremento minimo antes de mover o stop de novo

//--- Inputs: scanner multi-timeframe (confluencia do mesmo padrao em outros timeframes)
input bool InpUseAllTimeframeScanner = true;   // Habilita a exigencia de confluencia
input bool InpScanM1  = false;
input bool InpScanM5  = false;
input bool InpScanM15 = true;
input bool InpScanM30 = true;
input bool InpScanH1  = true;
input bool InpScanH4  = false;
input bool InpScanD1  = false;

//--- Inputs: expiracao de ordens pendentes
input int  InpCancelPendingAfterCandles = 20;  // Cancela a ordem pendente se nao preencher em X velas do timeframe de entrada

//--- Inputs: meta de lucro de equity
input bool   InpUseEquityProfitTarget      = false;  // Habilita a meta de lucro
input double InpEquityProfitTarget         = 100.0;  // % de lucro sobre a equity de referencia que aciona a meta
input bool   InpRestartAfterEquityTarget   = true;   // true = fecha tudo e continua operando (nova referencia); false = fecha tudo e trava ate reiniciar o EA

//--- Inputs: protecao de equity (drawdown)
input bool   InpUseEquityProtection        = false;  // Habilita a protecao de drawdown
input double InpMaxEquityDrawdownPercent   = 10.0;   // % de queda sobre a equity de referencia que aciona a protecao
input bool   InpRestartAfterEquityProtection = false; // true = fecha tudo e continua operando (nova referencia); false = fecha tudo e trava ate reiniciar o EA

//--- Inputs: execucao
input ulong  InpSlippagePoints = 30;   // Desvio maximo (pontos) tolerado nas ordens

//--- Inputs: painel e notificacoes
input bool InpEnableDashboard   = true;   // Exibe painel no grafico
input bool InpEnablePushNotify  = false;  // Envia push notification em eventos importantes
input bool InpEnableEmailNotify = false;  // Envia e-mail em eventos importantes

//--- Inputs: diagnostico
input bool InpVerboseLogging = true;   // Loga no Diario/Experts o motivo de cada vela nao gerar sinal (corpo/pavio, filtro MA, scanner) - util para depurar por que nao esta operando

//--- Objetos globais do EA
CWickSignal     g_signal;
CSetupManager   g_setup;
CPositionManager g_posMgr;
CEquityGuard    g_equity;
CWrDashboard    g_dash;

ENUM_WR_STATE   g_lastState = WR_STATE_TRADING;

//+------------------------------------------------------------------+
void NotifyEvent(const string message)
  {
   Print("WickReversalEA: ", message);
   if(InpEnablePushNotify && !MQLInfoInteger(MQL_TESTER))
      SendNotification(StringSubstr(message, 0, 255));
   if(InpEnableEmailNotify && !MQLInfoInteger(MQL_TESTER))
      SendMail("WickReversalEA - " + _Symbol, message);
  }

//+------------------------------------------------------------------+
bool InSession(void)
  {
   if(!InpUseTradingTime)
      return true;

   MqlDateTime dt;
   TimeToStruct(TimeTradeServer(), dt);
   int nowMinutes   = dt.hour * 60 + dt.min;
   int startMinutes = InpStartHour * 60 + InpStartMinute;
   int endMinutes    = InpEndHour * 60 + InpEndMinute;

   if(startMinutes <= endMinutes)
      return (nowMinutes >= startMinutes && nowMinutes <= endMinutes);

   // janela que cruza a meia-noite
   return (nowMinutes >= startMinutes || nowMinutes <= endMinutes);
  }

//+------------------------------------------------------------------+
int MaxTierTotal(void)
  {
   return InpFirstEntryOrders + InpSecondEntryOrders + InpThirdEntryOrders;
  }

//+------------------------------------------------------------------+
void UpdateDashboard(const ENUM_WR_STATE state)
  {
   if(!InpEnableDashboard)
      return;

   int buyOpen  = g_setup.CountOpenPositions(WR_SIDE_BUY);
   int sellOpen = g_setup.CountOpenPositions(WR_SIDE_SELL);
   bool buyPending  = g_setup.HasPendingOrder(WR_SIDE_BUY);
   bool sellPending = g_setup.HasPendingOrder(WR_SIDE_SELL);

   g_dash.Update(state, g_equity.ProfitPercent(), AccountInfoDouble(ACCOUNT_EQUITY), AccountInfoDouble(ACCOUNT_BALANCE),
                 buyOpen, buyPending, MaxTierTotal(), sellOpen, sellPending, MaxTierTotal(), MaxTierTotal());
  }

//+------------------------------------------------------------------+
int OnInit(void)
  {
   if((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
     {
      Print("WickReversalEA: esta EA requer conta em modo HEDGING. Abortando.");
      return(INIT_FAILED);
     }

   if(!g_signal.Init(_Symbol, InpEntryTimeframe, InpBodyMaximumPercent, InpWickMinimumPercent,
                      InpUseMAFilter, InpMATimeframe, InpMAPeriod, InpMAMethod, InpMAPrice,
                      InpUseAllTimeframeScanner, InpScanM1, InpScanM5, InpScanM15, InpScanM30,
                      InpScanH1, InpScanH4, InpScanD1, InpVerboseLogging))
      return(INIT_FAILED);

   g_setup.Configure(_Symbol, InpMagicNumber, InpEntryTimeframe,
                      InpDirectionMode, InpBlockOppositeDirection, InpOneSetupAtTime,
                      InpUseAutoLot, InpManualLotSize, InpInitialLot, InpProfitStepPips,
                      InpLotIncreasePerStep, InpMaximumLot,
                      InpFirstEntryOrders, InpSecondEntryOrders, InpThirdEntryOrders,
                      InpStopLossPips, InpTakeProfitPips, InpBreakClosePips,
                      InpCancelPendingAfterCandles, InpSlippagePoints);

   g_posMgr.Configure(_Symbol, InpMagicNumber,
                       InpUseBreakEven, InpBreakEvenAfterPips, InpBreakEvenPlusPips,
                       InpUseTrailingStop, InpTrailingStartPips, InpTrailingDistancePips,
                       InpTrailingStepPips, InpSlippagePoints);

   g_equity.Configure(InpUseEquityProfitTarget, InpEquityProfitTarget, InpRestartAfterEquityTarget,
                       InpUseEquityProtection, InpMaxEquityDrawdownPercent, InpRestartAfterEquityProtection);
   g_equity.Init();

   if(InpEnableDashboard)
      g_dash.Init(ChartID(), IntegerToString(InpMagicNumber));

   g_lastState = WR_STATE_TRADING;

   PrintFormat("WickReversalEA inicializado. Magic=%I64d Symbol=%s EntryTF=%s PipSize=%.5f EquityReferencia=%.2f",
               InpMagicNumber, _Symbol, EnumToString(InpEntryTimeframe), WrPipSize(_Symbol), g_equity.Baseline());
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(InpEnableDashboard)
      g_dash.Remove();
   g_signal.Release();
  }

//+------------------------------------------------------------------+
void OnTick(void)
  {
   ENUM_WR_STATE state = g_equity.Evaluate();

   if(g_equity.ConsumePendingCloseAll())
     {
      g_setup.CloseAll();
      NotifyEvent(StringFormat("Guarda de equity acionada (%s). Todas as posicoes/pendentes encerradas. Equity vs referencia=%.2f%%",
                  EnumToString(state), g_equity.ProfitPercent()));
     }

   if(g_lastState != state)
     {
      if(state == WR_STATE_PROFIT_TARGET_HIT)
         NotifyEvent("Meta de lucro de equity atingida - travado ate reiniciar o EA.");
      else if(state == WR_STATE_PROTECTION_HIT)
         NotifyEvent("Protecao de drawdown de equity acionada - travado ate reiniciar o EA.");
     }
   g_lastState = state;

   bool allowNewEntries = (state == WR_STATE_TRADING) && InSession();

   if(allowNewEntries)
     {
      int signal = g_signal.GetEntrySignal();
      if(signal != 0)
        {
         g_setup.PlaceInitialSetup(signal, g_signal.EntryPatternClose());
         if(signal > 0)
            NotifyEvent("Sinal de compra (pin bar) confirmado - ordens pendentes enviadas.");
         else
            NotifyEvent("Sinal de venda (pin bar) confirmado - ordens pendentes enviadas.");
        }
     }

   g_setup.CancelExpiredPendingOrders();
   g_setup.ManageTierProgression(WR_SIDE_BUY);
   g_setup.ManageTierProgression(WR_SIDE_SELL);
   g_posMgr.Manage();

   ENUM_WR_STATE displayState = (state == WR_STATE_TRADING && !InSession()) ? WR_STATE_OUT_OF_SESSION : state;
   UpdateDashboard(displayState);
  }
//+------------------------------------------------------------------+
