# Pesquisa de estratégias — EAs/robôs de trade líderes de mercado

Pesquisa feita para fundamentar o design do `BTC_TrendHedge_EA`. Resume as
abordagens mais usadas por vendors comerciais (MQL5 Market, Forex Store,
EATested, etc.) e por robôs institucionais, e explica por que o núcleo do
EA foi definido como **trend-following + hedge de proteção** em vez de
grid/martingale puro.

## 1. Famílias de estratégia mais usadas

### Grid / Martingale
Abre ordens em intervalos de preço fixos (grid) e aumenta o volume a cada
perda (martingale) na expectativa de reversão à média. Populares em pares
"range-bound" (AUDCAD, EURCHF, EURGBP). **Risco real**: uma tendência forte
e sustentada estoura a conta — o padrão clássico é "lucro pequeno e
constante por meses, seguido de um blow-up". A maioria das prop firms
**desqualifica** EAs de grid/martingale/HFT nos desafios de avaliação por
esse motivo.

### Trend-following
Entra a favor da tendência de fundo (médias móveis, ATR, RSI, rompimentos
com retest), com stop loss fixo e position sizing por % de risco. É o
padrão mais usado por EAs "sérios"/institucionais e o único compatível com
regras de prop firm (perda por trade limitada e conhecida de antemão).

### Hedge de proteção (não é grid)
Diferente do hedge usado em EAs de grid (que abre grid nos dois lados como
mecanismo de entrada), aqui o hedge é definido como **mecanismo de defesa**:
uma posição perdedora, ao ultrapassar um limiar de perda flutuante, é
parcialmente protegida por uma posição oposta, evitando que o prejuízo
cresça sem controle enquanto se aguarda reversão ou confirmação de stop.
Esse padrão aparece em ferramentas como "Coverage Account / Auto Hedging"
(YourBourse) usadas por mesas de risco de corretoras, e em EAs comerciais
do tipo "Hedge Martingale EA" — mas aqui aplicado de forma disciplinada
(sem aumento de volume por martingale), como salvaguarda e não como
estratégia primária de entrada.

### Scalping / notícias
Operações rápidas em janelas de alta volatilidade (abertura de sessão,
eventos macro). Menor tempo de exposição, mas exige execução de baixa
latência e é mais sensível a spread/slippage — motivo pelo qual BTC
(disponível 24/7, spread variável) se encaixa melhor em trend-following
com filtro de volatilidade do que em scalping puro de notícias.

## 2. O que os robôs comerciais/institucionais têm em comum (funções replicadas no EA)

| Função | Onde aparece no BTC_TrendHedge_EA |
|---|---|
| Position sizing por % de risco | `RiskManager.CalcLotByRisk()` |
| Daily Loss circuit breaker | `RiskManager.IsDailyLossHit()` → fecha tudo e bloqueia o dia |
| Daily Gain lock-in | `RiskManager.IsDailyProfitHit()` → bloqueia novas entradas |
| Max Drawdown kill switch (estilo prop firm) | `RiskManager.IsMaxDrawdownHit()` |
| Hedge de proteção (não-martingale) | `HedgeManager` (abre, desfaz por recuperação, converte) |
| Trailing stop / breakeven | `ManageTrailingAndBreakeven()` no EA principal |
| Filtro de spread | `SpreadOk()` |
| Filtro de sessão/horário | `InSession()` |
| Filtro de volatilidade mínima (evita mercado morto) | `TrendSignal.VolatilityOk()` |
| Painel visual no gráfico (dashboard) | `Dashboard.mqh` |
| Notificações (push/e-mail) | `NotifyEvent()` |
| Persistência de estado entre reinícios do terminal | Global Variables em `RiskManager` |
| Magic number segregando posições principais x hedge | `Defines.mqh` (`BTCEA_HEDGE_MAGIC_OFFSET`) |

## 3. Por que trend-following + hedge, e não grid/martingale

- Grid/martingale tem lucro esperado positivo apenas enquanto o mercado
  permanece em range; BTC tem histórico de tendências fortes e prolongadas
  (halving cycles, notícias regulatórias) que historicamente destroem
  contas de martingale.
- Prop firms e a maioria das corretoras sérias tratam martingale/grid como
  sinal de risco de conta — não é compatível com "todas as funções dos
  maiores robôs" se o objetivo inclui rodar em conta financiada/fundeada.
- Hedge como **proteção** (não como técnica de recuperação por aumento de
  volume) mantém o perfil de risco conhecido por trade, e ainda assim
  entrega a funcionalidade de "hedge" pedida.

## 4. Especificidades de BTCUSD no MT5 relevantes ao EA

- Contrato: normalmente 1 lote = 1 BTC (varia por corretora — **conferir na
  aba "Especificação" do símbolo antes de operar**: volume mínimo, step,
  tick value/size).
- Spread e liquidez variam bastante por corretora/horário — por isso o EA
  tem filtro de spread máximo (`InpMaxSpreadPoints`) e de volatilidade
  mínima via ATR.
- Requer **conta em modo Hedging** (`ACCOUNT_MARGIN_MODE_RETAIL_HEDGING`)
  para permitir posições compradas e vendidas simultâneas no mesmo símbolo
  — o EA verifica isso em `OnInit()` e recusa rodar em conta Netting.
- Daily loss/drawdown calculado sobre equity (ou balance, configurável) —
  os cortes de dia usam `TimeTradeServer()` (hora do servidor da
  corretora), não hora local.

## Fontes consultadas

- [Grid Trading Forex: Complete Strategy Guide for 2026](https://newyorkcityservers.com/blog/grid-trading-forex)
- [Best Free Martingale EAs – ForexCracked](https://www.forexcracked.com/tag/martingale/)
- [Best MT5 Expert Advisors (EAs) for Funded Accounts | For Traders](https://fortraders.com/blog/best-mt5-expert-advisors-eas-for-funded-accounts)
- [RobotFX Fluid expert advisor MT4/MT5](https://www.robotfx.org/p/fluid-expert-advisor-mt4-mt5.html)
- [Grid EA MT4/MT5 – Forex Grid Trading & Hedging Expert Advisor | RobotFX](https://www.robotfx.org/p/grid-expert-advisor-mt4.html)
- [Best Forex Robots & EAs (2026) — ForexTester](https://forextester.com/blog/best-forex-ea-and-forex-robots/)
- [TOP 15 Best Forex Robots & EA's Reviews in 2026 — Forex Store](https://forexstore.com/best-forex-robots)
- [Best Forex Grid EAs 2026 — AlgoTradingSpace](https://algotradingspace.com/best-forex-grid-eas)
- [Quantum Bitcoin EA — MQL5 Market](https://www.mql5.com/en/market/product/127013)
- [BTC usd — MQL5 Market](https://www.mql5.com/en/market/product/138031)
- [Daily Drawdown Limit EA Prop Firm trading MT5 — MQL5 Market](https://www.mql5.com/en/market/product/85087)
- [The Autopsy of a Funded Account: How to Structure an EA to Survive Prop Firms — MQL5 Blogs](https://www.mql5.com/en/blogs/post/767611)
- [Stop trading after reaching daily Profit/Loss — MQL5 Forum](https://www.mql5.com/en/forum/342190)
- [MT5 Prop Firm EA Rules: Daily Loss, News, Lots (2026) — AlfaTactix](https://alfatactix.com/academy/mql5-ea/ea-prop-firm-rules-mt5)
- [How to Calculate Lot Size for BTCUSD (Bitcoin) — TIOmarkets](https://tiomarkets.com/en/article/how-to-calculate-lot-size-for-btcusd)
- [Coverage Account - Bucketing and Auto Hedging Plugin for MT5 — YourBourse](https://www.yourbourse.com/coverage-account-bucketing-and-auto-hedging-plugin-for-mt5)
