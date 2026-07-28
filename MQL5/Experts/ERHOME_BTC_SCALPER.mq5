//+------------------------------------------------------------------+
//|                                       ERHOME_BTC_SCALPER.mq5     |
//| Robo de scalping BTC para MetaTrader 5 - conta HEDGING.         |
//|                                                                  |
//| LINHAGEM: BTC_Scalper_EA (mesma logica de trade, sem alteracao) |
//| -> ERHOME_BTC_SCALPER (renomeado + painel redesenhado no estilo |
//| ERHOME_BOVESPA_V1). Nenhuma mudanca de estrategia/gestao de     |
//| risco nesta versao - apenas nome e painel visual.               |
//|                                                                  |
//| Nucleo: reversao a media em timeframe curto (M1/M5 por padrao,  |
//| Bandas de Bollinger + RSI), com alvo de lucro FIXO EM DOLARES   |
//| por trade (pequeno e configuravel), ate N posicoes pequenas     |
//| simultaneas, fechando e reabrindo continuamente ao longo do     |
//| dia. DailyGain/DailyLoss (circuit breaker, com opcao de meta em |
//| dolares), Max Drawdown (kill switch) e hedge de protecao        |
//| opcional (com o fix do bug de hedge orfao ja aplicado).         |
//|                                                                  |
//| ATENCAO: mais operacoes = mais custo de spread acumulado. Exige |
//| conta em modo HEDGING. Compile e faca backtest completo antes   |
//| de qualquer uso real. Em contas pequenas, o lote minimo do      |
//| simbolo pode dominar o dimensionamento por risco - confira a    |
//| especificacao do simbolo na sua corretora antes de operar.      |
//+------------------------------------------------------------------+
#property copyright "ERHOME"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <BTCHedgeEA/Defines.mqh>
#include <BTCHedgeEA/RiskManager.mqh>
#include <BTCHedgeEA/ScalpSignal.mqh>
#include <BTCHedgeEA/HedgeManager.mqh>

#define EA_TAG "ERHOME_BTC_SCALPER"

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

//--- Inputs: filtro de tendencia (evita comprar/vender contra uma tendencia forte)
input bool                InpUseTrendFilter     = true;       // Habilita filtro de tendencia (recomendado)
input ENUM_TIMEFRAMES   InpTrendFilterTimeframe = PERIOD_M15; // Timeframe da media usada como filtro de tendencia
input int                InpTrendFilterPeriod  = 50;          // Periodo da media (EMA) usada como filtro de tendencia

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

//--- Inputs: diagnostico
input bool                InpVerboseLogging     = true;       // Loga no Diario/Experts os valores de Bandas/RSI a cada barra fechada (util para depurar por que nao esta operando)

//--- Objetos globais do EA
CRiskManager   g_risk;
CScalpSignal   g_scalp;
CHedgeManager  g_hedge;
CTrade         g_trade;
CPositionInfo  g_posInfo;

long           g_hedgeMagic;
ENUM_EA_STATE  g_lastState  = EA_STATE_TRADING;
int            g_tradesToday = 0;
datetime       g_tradesDay   = 0;
bool           g_notReadyWarned = false;

//+------------------------------------------------------------------+
void NotifyEvent(const string message)
  {
   Print(EA_TAG, ": ", message);
   if(InpEnablePushNotify && !MQLInfoInteger(MQL_TESTER))
      SendNotification(StringSubstr(message, 0, 255));
   if(InpEnableEmailNotify && !MQLInfoInteger(MQL_TESTER))
      SendMail(EA_TAG + " - " + _Symbol, message);
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
   if(InpVerboseLogging && !g_scalp.IsReady())
     {
      if(!g_notReadyWarned)
        {
         PrintFormat("%s [debug] aguardando historico suficiente do indicador (BB periodo=%d) em %s %s",
                     EA_TAG, InpBBPeriod, _Symbol, EnumToString(InpEntryTimeframe));
         g_notReadyWarned = true;
        }
     }
   else
      g_notReadyWarned = false;

   int signal = g_scalp.GetEntrySignal();

   if(InpVerboseLogging && g_scalp.WasEvaluatedThisCall())
      PrintFormat("%s [debug] barra fechada -> close=%.2f upper=%.2f lower=%.2f rsi=%.2f (oversold<=%.1f overbought>=%.1f) filtroTendencia(%s)=%.2f sinal=%d spread=%d",
                  EA_TAG, g_scalp.LastClose(), g_scalp.LastUpper(), g_scalp.LastLower(), g_scalp.LastRsi(),
                  InpRsiOversold, InpRsiOverbought, (InpUseTrendFilter ? EnumToString(InpTrendFilterTimeframe) : "off"),
                  g_scalp.LastTrendFilterMa(), signal, (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD));

   if(signal == 0)
      return;

   if(!SpreadOk())
     {
      if(InpVerboseLogging)
         PrintFormat("%s [debug] sinal=%d encontrado mas bloqueado por spread: atual=%d pontos, maximo=%.0f",
                     EA_TAG, signal, (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD), InpMaxSpreadPoints);
      return;
     }

   if(CountAllMainPositions() >= InpMaxConcurrentPositions)
     {
      if(InpVerboseLogging)
         PrintFormat("%s [debug] sinal encontrado mas numero maximo de posicoes concorrentes atingido", EA_TAG);
      return;
     }

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
      if(g_trade.Buy(lots, _Symbol, ask, sl, tp, EA_TAG))
         NotifyEvent(StringFormat("Scalp compra @%.2f SL=%.2f TP=%.2f (alvo $%.2f) vol=%.2f", ask, sl, tp, InpTargetProfitUSD, lots));
     }
   else
     {
      double sl = NormalizeDouble(bid + slDistance, digits);
      double tp = NormalizeDouble(bid - tpDistance, digits);
      if(g_trade.Sell(lots, _Symbol, bid, sl, tp, EA_TAG))
         NotifyEvent(StringFormat("Scalp venda @%.2f SL=%.2f TP=%.2f (alvo $%.2f) vol=%.2f", bid, sl, tp, InpTargetProfitUSD, lots));
     }
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
//|  PAINEL - estilo ERHOME (fundo escuro, titulo, secoes, tabela)   |
//+------------------------------------------------------------------+
#define PX  8
#define PY  6
#define RH  18
#define PW  300
#define C1  8
#define C2  145

string PanelPrefix() { return "ERH_" + IntegerToString(InpMagicNumber) + "_"; }

void PL(string id,int x,int y,string txt,color c,int sz=9,bool bold=false)
  {
   string nm = PanelPrefix() + id;
   if(ObjectFind(0, nm) < 0)
      ObjectCreate(0, nm, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, nm, OBJPROP_CORNER,    CORNER_LEFT_UPPER);
   ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, nm, OBJPROP_COLOR,     c);
   ObjectSetInteger(0, nm, OBJPROP_FONTSIZE,  sz);
   ObjectSetString (0, nm, OBJPROP_FONT,      bold ? "Arial Bold" : "Arial");
   ObjectSetString (0, nm, OBJPROP_TEXT,      txt);
   ObjectSetInteger(0, nm, OBJPROP_BACK,      false);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE,false);
  }

void PSep(string id,int y)
  {
   PL(id, PX, y, "- - - - - - - - - - - - - - - - - - - - - - - -", (color)0x3A3A3A, 7);
  }

void DeletePanel(void)
  {
   string prefix = PanelPrefix();
   for(int i = ObjectsTotal(0, 0, -1) - 1; i >= 0; i--)
     {
      string nm = ObjectName(0, i, 0, -1);
      if(StringFind(nm, prefix) == 0)
         ObjectDelete(0, nm);
     }
   ChartRedraw(0);
  }

datetime DayStart(void)   { return TimeTradeServer() - (TimeTradeServer() % 86400); }
datetime WeekStart(void)  { MqlDateTime t; TimeToStruct(TimeTradeServer(), t); return DayStart() - (t.day_of_week * 86400); }
datetime MonthStart(void) { MqlDateTime t; TimeToStruct(TimeTradeServer(), t); t.day = 1; t.hour = 0; t.min = 0; t.sec = 0; return StructToTime(t); }

// Estatisticas realizadas (deals de saida) desde 'from', deste EA (principal + hedge)
void GetPeriodStats(datetime from,int &tot,int &wins,double &sum)
  {
   tot = 0; wins = 0; sum = 0.0;
   HistorySelect(from, TimeTradeServer());
   int n = HistoryDealsTotal();
   for(int i = 0; i < n; i++)
     {
      ulong t = HistoryDealGetTicket(i);
      if(HistoryDealGetString(t, DEAL_SYMBOL) != _Symbol)
         continue;
      long magic = (long)HistoryDealGetInteger(t, DEAL_MAGIC);
      if(magic != InpMagicNumber && magic != g_hedgeMagic)
         continue;
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(t, DEAL_ENTRY) != DEAL_ENTRY_OUT)
         continue;
      double p = HistoryDealGetDouble(t, DEAL_PROFIT) + HistoryDealGetDouble(t, DEAL_SWAP);
      tot++;
      sum += p;
      if(p > 0)
         wins++;
     }
  }

double GetOpenProfit(void)
  {
   double s = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!g_posInfo.SelectByIndex(i))
         continue;
      if(g_posInfo.Symbol() != _Symbol)
         continue;
      if(g_posInfo.Magic() != InpMagicNumber && g_posInfo.Magic() != g_hedgeMagic)
         continue;
      s += g_posInfo.Profit() + g_posInfo.Swap();
     }
   return s;
  }

void DrawPanel(const ENUM_EA_STATE state)
  {
   if(!InpEnableDashboard)
      return;

   string bg = PanelPrefix() + "BG";
   if(ObjectFind(0, bg) < 0)
     {
      ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, bg, OBJPROP_CORNER,      CORNER_LEFT_UPPER);
      ObjectSetInteger(0, bg, OBJPROP_XDISTANCE,   2);
      ObjectSetInteger(0, bg, OBJPROP_YDISTANCE,   2);
      ObjectSetInteger(0, bg, OBJPROP_XSIZE,       PW);
      ObjectSetInteger(0, bg, OBJPROP_YSIZE,       340);
      ObjectSetInteger(0, bg, OBJPROP_BGCOLOR,     (color)0x0D1117);
      ObjectSetInteger(0, bg, OBJPROP_BORDER_COLOR,(color)0x2A5A8A);
      ObjectSetInteger(0, bg, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, bg, OBJPROP_BACK,        false);
      ObjectSetInteger(0, bg, OBJPROP_SELECTABLE,  false);
     }

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

   double price          = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double openP          = GetOpenProfit();
   double dailyProfitUSD = AccountInfoDouble(ACCOUNT_EQUITY) - g_risk.DailyBaseline();
   double dailyPct       = g_risk.DailyPnLPercent();
   double ddPct          = g_risk.DrawdownFromPeakPercent();
   long   spread         = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);

   int dT,dW,wT,wW,mT,mW; double dS,wS,mS;
   GetPeriodStats(DayStart(),   dT, dW, dS);
   GetPeriodStats(WeekStart(),  wT, wW, wS);
   GetPeriodStats(MonthStart(), mT, mW, mS);

   string stTxt; color stClr;
   if(state == EA_STATE_DAILY_LOSS)        { stTxt = "PERDA MAX DIA";     stClr = (color)0xFF4444; }
   else if(state == EA_STATE_MAX_DRAWDOWN) { stTxt = "MAX DRAWDOWN";      stClr = (color)0xFF4444; }
   else if(state == EA_STATE_DAILY_PROFIT) { stTxt = "META DIARIA";       stClr = clrGold; }
   else if(state == EA_STATE_OUT_OF_SESSION){ stTxt = "Fora horario";     stClr = (color)0x888888; }
   else if(buyCount + sellCount > 0)       { stTxt = "EM POSICAO";        stClr = clrAqua; }
   else                                    { stTxt = "Operando";          stClr = clrLime; }

   string posTxt = "- NENHUMA";
   color  posClr = clrGray;
   if(buyCount > 0 && sellCount == 0) { posTxt = "COMPRA x" + IntegerToString(buyCount); posClr = clrLime; }
   else if(sellCount > 0 && buyCount == 0) { posTxt = "VENDA x" + IntegerToString(sellCount); posClr = (color)0xFF4444; }
   else if(buyCount > 0 && sellCount > 0) { posTxt = "COMPRA x" + IntegerToString(buyCount) + " / VENDA x" + IntegerToString(sellCount); posClr = clrYellow; }

   int y = PY + 5;

   PL("T0", PX, y, EA_TAG + "  |  " + _Symbol, clrWhite, 11, true);
   y += 22;
   PSep("S0", y); y += 9;

   PL("L1a", PX+C1, y, "Status:", (color)0x8899AA);
   PL("L1b", PX+C2, y, stTxt, stClr, 9, true);
   y += RH;

   PL("L2a", PX+C1, y, "Preco:", (color)0x8899AA);
   PL("L2b", PX+C2, y, DoubleToString(price, (int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS)), clrWhite);
   y += RH;

   PL("L3a", PX+C1, y, "Spread:", (color)0x8899AA);
   PL("L3b", PX+C2, y, IntegerToString((int)spread) + " pts", (color)0xBBCCDD);
   y += RH;

   PL("L4a", PX+C1, y, "Posicoes:", (color)0x8899AA);
   PL("L4b", PX+C2, y, posTxt, posClr, 9, true);
   y += RH;

   PL("L5a", PX+C1, y, "Hedge ativo:", (color)0x8899AA);
   PL("L5b", PX+C2, y, (hedgeCount > 0 ? "x" + IntegerToString(hedgeCount) : "-"), (hedgeCount > 0 ? clrOrange : clrGray));
   y += RH;

   PL("L6a", PX+C1, y, "Flutuante:", (color)0x8899AA);
   PL("L6b", PX+C2, y, "$ " + DoubleToString(openP, 2), openP >= 0 ? clrLime : (color)0xFF4444);
   y += RH;

   PSep("S1", y); y += 9;

   PL("R0", PX+C1, y, "Risco/trade: " + DoubleToString(InpRiskPercentPerTrade,1) + "%   Alvo: $" + DoubleToString(InpTargetProfitUSD,2), clrAqua, 8);
   y += RH;

   PSep("S2", y); y += 9;

   PL("D1a", PX+C1, y, "Resultado hoje:", (color)0x8899AA);
   PL("D1b", PX+C2, y, "$ " + DoubleToString(dailyProfitUSD,2) + "  (" + DoubleToString(dailyPct,2) + "%)",
      dailyProfitUSD >= 0 ? clrLime : (color)0xFF4444, 10, true);
   y += RH;

   PL("D2a", PX+C1, y, "Meta / Limite:", (color)0x8899AA);
   PL("D2b", PX+C2, y, "$" + DoubleToString(InpDailyProfitTargetUSD,0) + "  /  -" + DoubleToString(InpDailyLossPercent,1) + "%", clrGold, 8);
   y += RH;

   PL("D3a", PX+C1, y, "Drawdown (pico):", (color)0x8899AA);
   PL("D3b", PX+C2, y, DoubleToString(ddPct,2) + "%  (limite " + DoubleToString(InpMaxDrawdownPercent,1) + "%)", (color)0x998855, 8);
   y += RH;

   PSep("S3", y); y += 9;

   PL("H0a", PX+C1, y, "Periodo", (color)0x667788, 8);
   PL("H0b", PX+C2, y, "Trades/Win", (color)0x667788, 8);
   y += RH;

   PL("H1a", PX+C1, y, "Hoje:", (color)0x8899AA);
   PL("H1b", PX+C2, y, IntegerToString(dT) + "/" + IntegerToString(dW) + "  $" + DoubleToString(dS,2), dS >= 0 ? clrLime : (color)0xFF4444);
   y += RH;

   PL("H2a", PX+C1, y, "Semana:", (color)0x8899AA);
   PL("H2b", PX+C2, y, IntegerToString(wT) + "/" + IntegerToString(wW) + "  $" + DoubleToString(wS,2), wS >= 0 ? clrLime : (color)0xFF4444);
   y += RH;

   PL("H3a", PX+C1, y, "Mes:", (color)0x8899AA);
   PL("H3b", PX+C2, y, IntegerToString(mT) + "/" + IntegerToString(mW) + "  $" + DoubleToString(mS,2), mS >= 0 ? clrLime : (color)0xFF4444);
   y += RH + 4;

   PSep("S4", y); y += 9;
   PL("FT", PX+C1, y, EA_TAG + "  |  Reversao a Media + Hedge opcional", (color)0x334455, 8);
   y += 16;

   ObjectSetInteger(0, bg, OBJPROP_YSIZE, y);
   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
int OnInit(void)
  {
   if((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
     {
      PrintFormat("%s: esta EA requer conta em modo HEDGING. Abortando.", EA_TAG);
      return(INIT_FAILED);
     }

   g_hedgeMagic = InpMagicNumber + BTCEA_HEDGE_MAGIC_OFFSET;

   g_risk.Configure(_Symbol, InpMagicNumber, InpRiskPercentPerTrade, InpDailyLossPercent,
                     InpDailyProfitPercent, InpMaxDrawdownPercent, InpUseEquityForDaily);
   g_risk.Init();

   if(!g_scalp.Init(_Symbol, InpEntryTimeframe, InpBBPeriod, InpBBDeviation, InpRsiPeriod,
                     InpRsiOversold, InpRsiOverbought, InpAtrPeriod,
                     InpUseTrendFilter, InpTrendFilterTimeframe, InpTrendFilterPeriod))
      return(INIT_FAILED);

   g_hedge.Configure(_Symbol, InpMagicNumber, g_hedgeMagic, InpHedgeTriggerPercent, InpHedgeVolumeRatio,
                      InpHedgeRecoveryRatio, InpHedgeConvertRatio, InpSlippagePoints);

   g_trade.SetDeviationInPoints(InpSlippagePoints);
   g_trade.SetMarginMode();
   g_trade.LogLevel(LOG_LEVEL_ERRORS);

   g_lastState   = EA_STATE_TRADING;
   g_tradesToday = 0;
   g_tradesDay   = 0;

   DrawPanel(EA_STATE_TRADING);

   PrintFormat("%s inicializado. Magic=%I64d HedgeMagic=%I64d Symbol=%s TF=%s Alvo=$%.2f",
               EA_TAG, InpMagicNumber, g_hedgeMagic, _Symbol, EnumToString(InpEntryTimeframe), InpTargetProfitUSD);
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   DeletePanel();
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
      DrawPanel(state);
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
      DrawPanel(state);
      return;
     }

   g_lastState = state;

   if(InpUseHedgeProtection)
      g_hedge.Manage();

   TryOpenNewPosition();
   DrawPanel(state);
  }
//+------------------------------------------------------------------+
