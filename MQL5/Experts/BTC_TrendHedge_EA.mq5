//+------------------------------------------------------------------+
//|                                         BTC_TrendHedge_EA.mq5   |
//| Robo de trade BTC para MetaTrader 5 - conta HEDGING.            |
//|                                                                  |
//| Nucleo: trend-following multi-timeframe (EMA + RSI) com entrada |
//| por pullback, protegido por hedge de posicao oposta quando uma  |
//| posicao entra em perda flutuante alem do limiar configurado.    |
//| Gestao de risco: dimensionamento por % de risco, DailyGain/     |
//| DailyLoss (circuit breaker), Max Drawdown (kill switch),        |
//| trailing stop, breakeven, filtro de spread e de sessao.         |
//|                                                                  |
//| ATENCAO: exige conta em modo HEDGING. Compile e faça backtest   |
//| completo (Strategy Tester) antes de qualquer uso em conta real. |
//| Trading envolve risco real de perda de capital.                 |
//+------------------------------------------------------------------+
#property copyright "BTC TrendHedge EA"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <BTCHedgeEA/Defines.mqh>
#include <BTCHedgeEA/RiskManager.mqh>
#include <BTCHedgeEA/TrendSignal.mqh>
#include <BTCHedgeEA/HedgeManager.mqh>
#include <BTCHedgeEA/Dashboard.mqh>

//--- Inputs: identificacao
input long              InpMagicNumber        = 990001;    // Magic number (posicoes de hedge usam Magic+1)

//--- Inputs: timeframes e indicadores de tendencia/entrada
input ENUM_TIMEFRAMES   InpTrendTimeframe     = PERIOD_H4;  // Timeframe da tendencia de fundo
input ENUM_TIMEFRAMES   InpEntryTimeframe     = PERIOD_H1;  // Timeframe de entrada (pullback)
input int                InpEmaFastPeriod      = 20;         // Periodo EMA rapida
input int                InpEmaSlowPeriod      = 50;         // Periodo EMA lenta (tendencia)
input int                InpRsiPeriod          = 14;         // Periodo RSI
input double             InpRsiUpperNeutral    = 55.0;       // RSI: limite superior da zona neutra
input double             InpRsiLowerNeutral    = 45.0;       // RSI: limite inferior da zona neutra
input int                InpAtrPeriod          = 14;         // Periodo ATR
input double             InpMinAtrPoints       = 500;        // Volatilidade minima (pontos) para operar - evita mercado morto

//--- Inputs: gestao de posicao / stops
input double             InpAtrSlMultiplier    = 2.0;        // Stop Loss = ATR * multiplicador
input double             InpRewardRiskRatio    = 1.5;        // Take Profit = SL * ratio (R:R)
input bool                InpUseTrailing        = true;       // Habilita trailing stop
input double             InpTrailingAtrMult    = 1.5;        // Trailing = ATR * multiplicador
input bool                InpUseBreakeven       = true;       // Habilita breakeven
input double             InpBreakevenAtrTrigger= 1.0;        // Aciona breakeven quando lucro >= ATR * este valor
input double             InpBreakevenLockPoints= 50;         // Pontos travados acima/abaixo da entrada no breakeven

//--- Inputs: dimensionamento e limites de posicao
input double             InpRiskPercentPerTrade= 1.0;        // % de risco da equity por trade
input int                InpMaxPositionsPerSide= 1;          // Maximo de posicoes principais por lado (compra/venda)

//--- Inputs: hedge de protecao
input double             InpHedgeTriggerPercent= 1.5;        // % da equity em perda flutuante que aciona o hedge
input double             InpHedgeVolumeRatio   = 1.0;        // Volume do hedge = volume original * ratio
input double             InpHedgeRecoveryRatio = 0.3;        // Fracao do limiar em que a original "recuperou" (fecha hedge)
input double             InpHedgeConvertRatio  = 1.2;        // Fracao da perda original que o hedge deve cobrir p/ cortar a original

//--- Inputs: DailyGain / DailyLoss / Max Drawdown (circuit breakers)
input bool                InpUseEquityForDaily  = true;       // true = usa equity, false = usa balance para calculo diario
input double             InpDailyLossPercent   = 3.0;        // % de perda diaria que bloqueia novas entradas e fecha tudo
input double             InpDailyProfitPercent = 0.0;        // % de ganho diario que bloqueia novas entradas (0 = desabilitado)
input double             InpMaxDrawdownPercent = 12.0;       // % de drawdown do pico de equity que interrompe o EA (kill switch)

//--- Inputs: filtros operacionais
input double             InpMaxSpreadPoints    = 800;        // Spread maximo (pontos) para permitir novas entradas
input ulong               InpSlippagePoints     = 50;         // Desvio maximo (pontos) nas ordens
input bool                InpUseSessionFilter   = false;       // Habilita filtro de janela de horario (server time)
input int                 InpSessionStartHour   = 0;          // Hora de inicio da sessao permitida (0-23, server time)
input int                 InpSessionEndHour     = 23;         // Hora de fim da sessao permitida (0-23, server time)

//--- Inputs: notificacoes e painel
input bool                InpEnableDashboard    = true;       // Exibe painel no grafico
input bool                InpEnablePushNotify   = false;      // Envia push notification em eventos importantes
input bool                InpEnableEmailNotify  = false;      // Envia e-mail em eventos importantes (requer config no terminal)

//--- Objetos globais do EA
CRiskManager   g_risk;
CTrendSignal   g_signal;
CHedgeManager  g_hedge;
CDashboard     g_dash;
CTrade         g_trade;
CPositionInfo  g_posInfo;

long           g_hedgeMagic;
ENUM_EA_STATE  g_lastState = EA_STATE_TRADING;

//+------------------------------------------------------------------+
void NotifyEvent(const string message)
  {
   Print("BTCHedgeEA: ", message);
   if(InpEnablePushNotify && !MQLInfoInteger(MQL_TESTER))
      SendNotification(StringSubstr(message, 0, 255));
   if(InpEnableEmailNotify && !MQLInfoInteger(MQL_TESTER))
      SendMail("BTCHedgeEA - " + _Symbol, message);
  }

//+------------------------------------------------------------------+
bool InSession(void)
  {
   if(!InpUseSessionFilter)
      return true;

   MqlDateTime dt;
   TimeToStruct(TimeTradeServer(), dt);
   int hour = dt.hour;

   if(InpSessionStartHour <= InpSessionEndHour)
      return (hour >= InpSessionStartHour && hour <= InpSessionEndHour);

   // janela que cruza a meia-noite (ex: 22h as 6h)
   return (hour >= InpSessionStartHour || hour <= InpSessionEndHour);
  }

//+------------------------------------------------------------------+
bool SpreadOk(void)
  {
   long spreadPoints = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   return (InpMaxSpreadPoints <= 0 || spreadPoints <= InpMaxSpreadPoints);
  }

//+------------------------------------------------------------------+
void ManageTrailingAndBreakeven(void)
  {
   if(!InpUseTrailing && !InpUseBreakeven)
      return;

   double atr = g_signal.AtrValue();
   if(atr <= 0.0)
      return;

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!g_posInfo.SelectByIndex(i))
         continue;
      if(g_posInfo.Symbol() != _Symbol)
         continue;
      if(g_posInfo.Magic() != InpMagicNumber && g_posInfo.Magic() != g_hedgeMagic)
         continue;

      ulong  ticket   = g_posInfo.Ticket();
      double openPrice= g_posInfo.PriceOpen();
      double curSl    = g_posInfo.StopLoss();
      double curTp    = g_posInfo.TakeProfit();
      bool   isBuy    = (g_posInfo.PositionType() == POSITION_TYPE_BUY);
      double bid      = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask      = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double price    = isBuy ? bid : ask;

      double newSl = curSl;

      // Breakeven
      if(InpUseBreakeven)
        {
         double trigger = openPrice + (isBuy ? 1 : -1) * atr * InpBreakevenAtrTrigger;
         bool reached = isBuy ? (price >= trigger) : (price <= trigger);
         bool notYetAtBe = isBuy ? (curSl < openPrice) : (curSl > openPrice || curSl == 0.0);
         if(reached && notYetAtBe)
            newSl = openPrice + (isBuy ? 1 : -1) * InpBreakevenLockPoints * point;
        }

      // Trailing stop (so aperta o stop, nunca afrouxa)
      if(InpUseTrailing)
        {
         double trailSl = price - (isBuy ? 1 : -1) * atr * InpTrailingAtrMult;
         if(isBuy && trailSl > newSl)
            newSl = trailSl;
         else if(!isBuy && (newSl == 0.0 || trailSl < newSl))
            newSl = trailSl;
        }

      newSl = NormalizeDouble(newSl, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));

      bool improves = isBuy ? (newSl > curSl) : (curSl == 0.0 || newSl < curSl);
      if(improves && newSl != curSl && newSl != 0.0)
         g_trade.PositionModify(ticket, newSl, curTp);
     }
  }

//+------------------------------------------------------------------+
void TryOpenNewPosition(void)
  {
   if(!InSession() || !SpreadOk())
      return;

   int signal = g_signal.GetEntrySignal();
   if(signal == 0)
      return;

   double atr = g_signal.AtrValue();
   if(atr <= 0.0)
      return;

   double slDistance = atr * InpAtrSlMultiplier;
   double tpDistance = slDistance * InpRewardRiskRatio;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   double lots = g_risk.CalcLotByRisk(slDistance);

   g_trade.SetExpertMagicNumber(InpMagicNumber);

   if(signal > 0 && g_hedge.CountMainPositions(POSITION_TYPE_BUY) < InpMaxPositionsPerSide)
     {
      double sl = NormalizeDouble(ask - slDistance, digits);
      double tp = NormalizeDouble(ask + tpDistance, digits);
      if(g_trade.Buy(lots, _Symbol, ask, sl, tp, "BTCHedgeEA-trend"))
         NotifyEvent(StringFormat("Compra aberta @%.2f SL=%.2f TP=%.2f vol=%.2f", ask, sl, tp, lots));
     }
   else if(signal < 0 && g_hedge.CountMainPositions(POSITION_TYPE_SELL) < InpMaxPositionsPerSide)
     {
      double sl = NormalizeDouble(bid + slDistance, digits);
      double tp = NormalizeDouble(bid - tpDistance, digits);
      if(g_trade.Sell(lots, _Symbol, bid, sl, tp, "BTCHedgeEA-trend"))
         NotifyEvent(StringFormat("Venda aberta @%.2f SL=%.2f TP=%.2f vol=%.2f", bid, sl, tp, lots));
     }
  }

//+------------------------------------------------------------------+
void UpdateDashboard(const ENUM_EA_STATE state)
  {
   if(!InpEnableDashboard)
      return;

   int buyCount   = g_hedge.CountMainPositions(POSITION_TYPE_BUY);
   int sellCount  = g_hedge.CountMainPositions(POSITION_TYPE_SELL);

   int hedgeCount = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!g_posInfo.SelectByIndex(i))
         continue;
      if(g_posInfo.Symbol() == _Symbol && g_posInfo.Magic() == g_hedgeMagic)
         hedgeCount++;
     }

   g_dash.Update("BTC TrendHedge EA", state, g_risk.DailyPnLPercent(), g_risk.DrawdownFromPeakPercent(),
                 AccountInfoDouble(ACCOUNT_EQUITY), AccountInfoDouble(ACCOUNT_BALANCE),
                 buyCount, sellCount, hedgeCount);
  }

//+------------------------------------------------------------------+
int OnInit(void)
  {
   if((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
     {
      Print("BTCHedgeEA: esta EA requer conta em modo HEDGING. Abortando.");
      return(INIT_FAILED);
     }

   g_hedgeMagic = InpMagicNumber + BTCEA_HEDGE_MAGIC_OFFSET;

   g_risk.Configure(_Symbol, InpMagicNumber, InpRiskPercentPerTrade, InpDailyLossPercent,
                     InpDailyProfitPercent, InpMaxDrawdownPercent, InpUseEquityForDaily);
   g_risk.Init();

   if(!g_signal.Init(_Symbol, InpTrendTimeframe, InpEntryTimeframe, InpEmaFastPeriod, InpEmaSlowPeriod,
                      InpRsiPeriod, InpRsiUpperNeutral, InpRsiLowerNeutral, InpAtrPeriod, InpMinAtrPoints))
      return(INIT_FAILED);

   g_hedge.Configure(_Symbol, InpMagicNumber, g_hedgeMagic, InpHedgeTriggerPercent, InpHedgeVolumeRatio,
                      InpHedgeRecoveryRatio, InpHedgeConvertRatio, InpSlippagePoints);

   g_trade.SetDeviationInPoints(InpSlippagePoints);
   g_trade.SetMarginMode();
   g_trade.LogLevel(LOG_LEVEL_ERRORS);

   if(InpEnableDashboard)
      g_dash.Init(ChartID(), IntegerToString(InpMagicNumber));

   g_lastState = EA_STATE_TRADING;

   PrintFormat("BTCHedgeEA inicializado. Magic=%I64d HedgeMagic=%I64d Symbol=%s", InpMagicNumber, g_hedgeMagic, _Symbol);
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
   if(g_risk.CheckNewDay())
      NotifyEvent("Novo dia de negociacao - baseline diario resetado.");

   ENUM_EA_STATE state = g_risk.Evaluate();

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
         NotifyEvent(StringFormat("Meta de DailyGain atingida (%.2f%%). Bloqueando novas entradas ate o proximo dia.",
                     g_risk.DailyPnLPercent()));
      g_lastState = state;
      // Ainda gerencia posicoes abertas (trailing/hedge), so bloqueia novas entradas
      ManageTrailingAndBreakeven();
      g_hedge.Manage();
      UpdateDashboard(state);
      return;
     }

   g_lastState = state;

   ManageTrailingAndBreakeven();
   g_hedge.Manage();

   if(!InSession())
     {
      UpdateDashboard(EA_STATE_OUT_OF_SESSION);
      return;
     }

   TryOpenNewPosition();
   UpdateDashboard(state);
  }
//+------------------------------------------------------------------+
