//+------------------------------------------------------------------+
//|                                                   PipUtils.mqh |
//| Conversao "pips" <-> preco, independente do simbolo. Segue a    |
//| convencao padrao do mercado: em simbolos de 3 ou 5 casas        |
//| decimais, 1 pip = 10 pontos; em simbolos de 2 ou 4 casas,       |
//| 1 pip = 1 ponto. Isso deixa os inputs "em pips" funcionando do  |
//| mesmo jeito tanto em BTCUSD (2 casas na maioria das corretoras) |
//| quanto em XAUUSD/forex (4-5 casas).                             |
//+------------------------------------------------------------------+
#property strict

double WrPipSize(const string symbol)
  {
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(digits == 3 || digits == 5)
      return point * 10.0;
   return point;
  }

double WrPipsToPrice(const string symbol,const double pips)
  {
   return pips * WrPipSize(symbol);
  }

double WrPriceToPips(const string symbol,const double priceDistance)
  {
   double pip = WrPipSize(symbol);
   if(pip <= 0.0)
      return 0.0;
   return priceDistance / pip;
  }

// Distancia minima (em preco) exigida pela corretora entre o preco atual e um
// stop/pendente (SYMBOL_TRADE_STOPS_LEVEL/FREEZE_LEVEL + spread atual, com uma
// pequena folga). Usada para nunca enviar uma ordem que o servidor vai rejeitar
// por estar "colada" demais no preco.
double WrMinStopDistance(const string symbol)
  {
   long stopsLevel  = SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long freezeLevel = SymbolInfoInteger(symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   long spread      = SymbolInfoInteger(symbol, SYMBOL_SPREAD);
   long minPoints   = MathMax(stopsLevel, freezeLevel) + spread;
   return minPoints * SymbolInfoDouble(symbol, SYMBOL_POINT);
  }
