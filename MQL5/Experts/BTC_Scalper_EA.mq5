//+------------------------------------------------------------------+
//|                                          BTC_Scalper_EA.mq5     |
//| Robo de scalping BTC para MetaTrader 5 - conta HEDGING.         |
//|                                                                  |
//| Nucleo: reversao a media em timeframe curto (M1/M5 por padrao,  |
//| Bandas de Bollinger + RSI), com alvo de lucro FIXO EM DOLARES   |
//| por trade (pequeno e configuravel), ate N posicoes pequenas     |
//| simultaneas, fechando e reabrindo continuamente ao longo do     |
//| dia. Mesma base de seguranca do BTC_TrendHedge_EA: DailyGain/   |
//| DailyLoss (circuit breaker, com opcao de meta em dolares), Max  |
//| Drawdown (kill switch) e hedge de protecao opcional.            |
//|                                                                  |
//| ATENCAO: mais operacoes = mais custo de spread acumulado. Exige |
//| conta em modo HEDGING. Compile e faca backtest completo antes   |
//| de qualquer uso real. Em contas pequenas, o lote minimo do      |
//| simbolo pode dominar o dimensionamento por risco - confira a    |
//| especificacao do BTCUSD na sua corretora antes de operar.       |
//+------------------------------------------------------------------+
#property copyright "BTC Scalper EA"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <BTCHedgeEA/Defines.mqh>
#include <BTCHedgeEA/RiskManager.mqh>
#include <BTCHedgeEA/ScalpSignal.mqh>
#include <BTCHedgeEA/HedgeManager.mqh>
#include <BTCHedgeEA/Dashboard.mqh>

//--- Inputs: identificacao
input long              InpMagicNumber        = 880001;    // Magic number (posicoes de hedge usam Magic+1)

//--- Inputs: sinal de scalping (reversao a media)
input ENUM_TIMEFRAMES   InpEntryTimeframe     = PERIOD_M1;  // Timeframe de entrada (M1 = mais agil, M5 = menos ruido)
input int                InpBBPeriod           = 20;         // Periodo das Bandas de Bollinger
input double             InpBBDeviation        = 2.0;        // Desvio padrao das Bandas de Bollinger
input int                InpRsiPeriod          = 7;          // Periodo do RSI (mais curto = mais sensivel)
input double             InpRsiOversold        = 25.0;       // RSI abaixo disso = sobrevendido (gatilho de compra)
input double             InpRsiOverbought      = 75.0;       // RSI acima disso = sobrecomprado (gatilho de venda)
input int                InpAtrPeriod          = 14;         // Periodo do ATR (usado so para o stop loss)

//--- Inputs: stop loss e alvo de lucro
input double             InpAtrSlMultiplier    = 1.0;        // Stop Loss = ATR * multiplicador (mantenha apertado)
input double             InpTargetProfitUSD    = 1.0;        // Alvo de lucro FIXO em dolares por trade (ex: 1.0 = tenta fechar em +$1)

//--- Inputs: dimensionamento e concorrencia
input double             InpRiskPercentPerTrade= 2.0;        // % da equity arriscado por trade (define o lote via distancia do SL)
input int                InpMaxConcurrentPositions = 3;      // Maximo de posicoes principais abertas ao mesmo tempo (compra+venda somadas)

//--- Inputs: filtro de spread
input double             InpMaxSpreadPoints    = 500;        // Spread maximo (pontos) para permitir novas entradas

//--- Inputs: hedge de protecao (opcional - trades ja tem stop apertado, hedge normalmente desnecessario aqui)
input bool                InpUseHedgeProtection = false;       // Habilita hedge de protecao (recomendado deixar off no scalper)
input double             InpHedgeTriggerPercent= 1.5;        // % da equity em perda flutuante que aciona o hedge (se habilitado)
input double             InpHedgeVolumeRatio   = 1.0;        // Volume do hedge = volume original * ratio
input double             InpHedgeRecoveryRatio = 0.3;        // Fracao do limiar em que a original "recuperou" (fecha hedge)
input double             InpHedgeConvertRatio  = 1.2;        // Fracao da perda original que o hedge deve cobrir p/ cortar a original
input ulong               InpSlippagePoints     = 30;         // Desvio maximo (pontos) nas ordens

//--- Inputs: DailyGain / DailyLoss / Max Drawdown (circuit breakers)
input bool                InpUseEquityForDaily  = true;       // true = usa equity, false = usa balance para calculo diario
input double             InpDailyLossPercent   = 3.0;        // % de perda diaria que bloqueia novas entradas e fecha tudo (DL)
input double             InpDailyProfitPercent = 0.0;        // % de ganho diario que bloqueia novas entradas (DG em %, 0 = desabilitado)
input double             InpDailyProfitTargetUSD = 10.0;     // Meta de ganho diario em DOLARES (DG em $, 0 = desabilitado) - trava novas entradas ao atingir
input double             InpMaxDrawdownPercent = 12.0;       // % de drawdown do pico de equity que interrompe o EA (kill switch)

//--- Inputs: painel e notificacoes
input bool                InpEnableDashboard    = true;       // Exibe painel no grafico
input bool                InpEnablePushNotify   = false;      // Envia push notification em eventos importantes
input bool                InpEnableEmailNotify  = false;      // Envia e-mail em eventos importantes

//--- Objetos globais do EA
CRiskManager   g_risk;
CScalpSignal   g_scalp;
CHedgeManager  g_hedge;
CDashboard     g_dash;
CTrade         g_trade;
CPositionInfo  g_posInfo;

long           g_hedgeMagic;
ENUM_EA_STATE  g_lastState  = EA_STATE_TRADING;
int            g_tradesToday = 0;
datetime       g_tradesDay   = 0;

//+------------------------------------------------------------------+
void NotifyEvent(const string message)
  {
   Print("BTCScalperEA: ", message);
   if(InpEnablePushNotify && !MQLInfoInteger(MQL_TESTER))
      SendNotification(StringSubstr(message, 0, 255));
   if(InpEnableEmailNotify && !MQLInfoInteger(MQL_TESTER))
      SendMail("BTCScalperEA - " + _Symbol, message);
  }

//+------------------------------------------------------------------+
bool SpreadOk(void)
  {
   long spreadPoints = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   return (InpMaxSpreadPoints <= 0 || spreadPoints <= InpMaxSpreadPoints);
  }

//+------------------------------------------------------------------+
double MinStopDistance(void)
  {
   long stopsLevel  = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long freezeLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   long spread      = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   long minPoints   = MathMax(stopsLevel, freezeLevel) + spread;
   return minPoints * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
  }

//+------------------------------------------------------------------+
// Distancia de preco necessaria para que 'lots' renda 'targetUSD' de lucro
double ComputeTpDistanceForProfit(const double lots,const double targetUSD)
  {
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickValue <= 0.0 || tickSize <= 0.0 || lots <= 0.0)
      return 0.0;

   double valuePerPriceUnit = (tickValue / tickSize) * lots;
   if(valuePerPriceUnit <= 0.0)
      return 0.0;

   return targetUSD / valuePerPriceUnit;
  }

//+------------------------------------------------------------------+
int CountAllMainPositions(void)
  {
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!g_posInfo.SelectByIndex(i))
         continue;
      if(g_posInfo.Symbol() == _Symbol && g_posInfo.Magic() == InpMagicNumber)
         count++;
     }
   return count;
  }

//+------------------------------------------------------------------+
void TryOpenNewPosition(void)
  {
   if(!SpreadOk())
      return;

   if(CountAllMainPositions() >= InpMaxConcurrentPositions)
      return;

   int signal = g_scalp.GetEntrySignal();
   if(signal == 0)
      return;

   double atr = g_scalp.AtrValue();
   if(atr <= 0.0)
      return;

   double minStop    = MinStopDistance();
   double slDistance = MathMax(atr * InpAtrSlMultiplier, minStop);

   double lots = g_risk.CalcLotByRisk(slDistance);

   double tpDistance = ComputeTpDistanceForProfit(lots, InpTargetProfitUSD);
   if(tpDistance < minStop)
      tpDistance = minStop;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   g_trade.SetExpertMagicNumber(InpMagicNumber);

   if(signal > 0)
     {
      double sl = NormalizeDouble(ask - slDistance, digits);
      double tp = NormalizeDouble(ask + tpDistance, digits);
      if(g_trade.Buy(lots, _Symbol, ask, sl, tp, "BTCScalperEA"))
         NotifyEvent(StringFormat("Scalp compra @%.2f SL=%.2f TP=%.2f (alvo $%.2f) vol=%.2f", ask, sl, tp, InpTargetProfitUSD, lots));
     }
   else
     {
      double sl = NormalizeDouble(bid + slDistance, digits);
      double tp = NormalizeDouble(bid - tpDistance, digits);
      if(g_trade.Sell(lots, _Symbol, bid, sl, tp, "BTCScalperEA"))
         NotifyEvent(StringFormat("Scalp venda @%.2f SL=%.2f TP=%.2f (alvo $%.2f) vol=%.2f", bid, sl, tp, InpTargetProfitUSD, lots));
     }
  }

//+------------------------------------------------------------------+
void UpdateDashboard(const ENUM_EA_STATE state)
  {
   if(!InpEnableDashboard)
      return;

   int buyCount = 0, sellCount = 0, hedgeCount = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!g_posInfo.SelectByIndex(i))
         continue;
      if(g_posInfo.Symbol() != _Symbol)
         continue;
      if(g_posInfo.Magic() == InpMagicNumber)
        {
         if(g_posInfo.PositionType() == POSITION_TYPE_BUY)
            buyCount++;
         else
            sellCount++;
        }
      else if(g_posInfo.Magic() == g_hedgeMagic)
         hedgeCount++;
     }

   double dailyProfitUSD = AccountInfoDouble(ACCOUNT_EQUITY) - g_risk.DailyBaseline();
   string extra = StringFormat("Trades hoje: %d   Meta DG: $%.2f (atual $%.2f)", g_tradesToday, InpDailyProfitTargetUSD, dailyProfitUSD);

   g_dash.Update("BTC Scalper EA", state, g_risk.DailyPnLPercent(), g_risk.DrawdownFromPeakPercent(),
                 AccountInfoDouble(ACCOUNT_EQUITY), AccountInfoDouble(ACCOUNT_BALANCE),
                 buyCount, sellCount, hedgeCount, extra);
  }

//+------------------------------------------------------------------+
bool DailyProfitTargetUSDHit(void)
  {
   if(InpDailyProfitTargetUSD <= 0.0)
      return false;
   double dailyProfitUSD = AccountInfoDouble(ACCOUNT_EQUITY) - g_risk.DailyBaseline();
   return dailyProfitUSD >= InpDailyProfitTargetUSD;
  }

//+------------------------------------------------------------------+
int OnInit(void)
  {
   if((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
     {
      Print("BTCScalperEA: esta EA requer conta em modo HEDGING. Abortando.");
      return(INIT_FAILED);
     }

   g_hedgeMagic = InpMagicNumber + BTCEA_HEDGE_MAGIC_OFFSET;

   g_risk.Configure(_Symbol, InpMagicNumber, InpRiskPercentPerTrade, InpDailyLossPercent,
                     InpDailyProfitPercent, InpMaxDrawdownPercent, InpUseEquityForDaily);
   g_risk.Init();

   if(!g_scalp.Init(_Symbol, InpEntryTimeframe, InpBBPeriod, InpBBDeviation, InpRsiPeriod,
                     InpRsiOversold, InpRsiOverbought, InpAtrPeriod))
      return(INIT_FAILED);

   g_hedge.Configure(_Symbol, InpMagicNumber, g_hedgeMagic, InpHedgeTriggerPercent, InpHedgeVolumeRatio,
                      InpHedgeRecoveryRatio, InpHedgeConvertRatio, InpSlippagePoints);

   g_trade.SetDeviationInPoints(InpSlippagePoints);
   g_trade.SetMarginMode();
   g_trade.LogLevel(LOG_LEVEL_ERRORS);

   if(InpEnableDashboard)
      g_dash.Init(ChartID(), IntegerToString(InpMagicNumber));

   g_lastState   = EA_STATE_TRADING;
   g_tradesToday = 0;
   g_tradesDay   = 0;

   PrintFormat("BTCScalperEA inicializado. Magic=%I64d HedgeMagic=%I64d Symbol=%s TF=%s Alvo=$%.2f",
               InpMagicNumber, g_hedgeMagic, _Symbol, EnumToString(InpEntryTimeframe), InpTargetProfitUSD);
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(InpEnableDashboard)
      g_dash.Remove();
   g_scalp.Release();
  }

//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &request,const MqlTradeResult &result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;
   if(!HistoryDealSelect(trans.deal))
      return;

   long magic = (long)HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
   if(magic != InpMagicNumber && magic != g_hedgeMagic)
      return;

   ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(entry == DEAL_ENTRY_IN)
      g_tradesToday++;
  }

//+------------------------------------------------------------------+
void OnTick(void)
  {
   datetime today0 = TimeTradeServer() - (TimeTradeServer() % 86400);
   if(today0 != g_tradesDay)
     {
      g_tradesDay   = today0;
      g_tradesToday = 0;
     }

   if(g_risk.CheckNewDay())
      NotifyEvent("Novo dia de negociacao - baseline diario resetado.");

   ENUM_EA_STATE state = g_risk.Evaluate();
   if(state == EA_STATE_TRADING && DailyProfitTargetUSDHit())
      state = EA_STATE_DAILY_PROFIT;

   if(state == EA_STATE_DAILY_LOSS || state == EA_STATE_MAX_DRAWDOWN)
     {
      if(g_lastState != state)
        {
         g_hedge.CloseAll();
         NotifyEvent(StringFormat("Circuit breaker acionado (%s). Todas as posicoes encerradas. P/L diario=%.2f%% DD=%.2f%%",
                     EnumToString(state), g_risk.DailyPnLPercent(), g_risk.DrawdownFromPeakPercent()));
        }
      g_lastState = state;
      UpdateDashboard(state);
      return;
     }

   if(state == EA_STATE_DAILY_PROFIT)
     {
      if(g_lastState != state)
         NotifyEvent(StringFormat("Meta diaria atingida (P/L=%.2f%%, $%.2f). Bloqueando novas entradas ate o proximo dia.",
                     g_risk.DailyPnLPercent(), AccountInfoDouble(ACCOUNT_EQUITY) - g_risk.DailyBaseline()));
      g_lastState = state;
      if(InpUseHedgeProtection)
         g_hedge.Manage();
      UpdateDashboard(state);
      return;
     }

   g_lastState = state;

   if(InpUseHedgeProtection)
      g_hedge.Manage();

   TryOpenNewPosition();
   UpdateDashboard(state);
  }
//+------------------------------------------------------------------+
