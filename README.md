# BTC Trading EAs — Robôs de trade BTC para MetaTrader 5

Três Expert Advisors (EA) para negociação automatizada de BTCUSD no
MetaTrader 5, em **conta Hedging**, compartilhando a mesma base de
segurança (DailyGain/DailyLoss, Max Drawdown) mas com estilos de
operação bem diferentes — veja [`docs/strategy-research.md`](docs/strategy-research.md)
para a pesquisa completa e o racional de design dos dois primeiros.

| | `BTC_TrendHedge_EA` | `BTC_Scalper_EA` | `BTC_HedgeGrid_EA` |
|---|---|---|---|
| Estilo | Trend-following (swing) | Reversão à média (scalping) | **Hedge grid / martingale** |
| Timeframes | H4 (tendência) + H1 (entrada) | M1 ou M5 (entrada) | Nenhum indicador — grid por pontos |
| Frequência de operações | Baixa (pode passar horas/dias sem sinal) | Alta (reavalia a cada barra M1/M5) | Contínua — sempre 1 compra + 1 venda abertas |
| Alvo de lucro | ATR × relação risco:retorno | **Valor fixo em dólares** por trade | Gain fixo em **pontos** por posição (dobra em $ com o volume) |
| Posições simultâneas (principais) | 1 por lado (padrão) | Até `InpMaxConcurrentPositions` (padrão 3) | Cresce por lado conforme o grid adiciona (até `InpMaxLevelsPerSide`) |
| Trailing/breakeven | Sim, gerido pelo EA a cada tick | Não — usa SL/TP fixos do servidor | Breakeven progressivo só no lado ganhador |
| Hedge | Proteção pontual, sempre ativo | Proteção pontual, opcional (`InpUseHedgeProtection`) | **Hedge é o núcleo da estratégia** (média no lado perdedor, dobra de volume) |
| Indicado para | Contas maiores, menos ruído, menos custo de spread | Contas que quer giro rápido — **cuidado com spread acumulado em contas pequenas** | Quem entende e aceita o risco de martingale — **é o mais agressivo dos três** |

> ⚠️ Scalping com metas de lucro pequenas ($1-2 por trade) em contas
> pequenas tem uma tensão real: o spread do BTC consome uma fatia
> proporcionalmente maior do alvo. Não existe configuração que garanta um
> valor fixo de ganho por dia — veja a seção do `BTC_Scalper_EA` abaixo
> para o racional completo.

## ⚠️ Aviso importante sobre esta versão

Este código foi escrito e revisado manualmente (sem um compilador MT5
disponível neste ambiente — veja a seção "Por que não foi compilado aqui").
**Antes de qualquer uso, mesmo em conta demo:**

1. Compile no MetaEditor e corrija eventuais erros/warnings de compilação.
2. Rode no Strategy Tester (modo "Every tick based on real ticks") em um
   período longo de histórico de BTCUSD da sua corretora.
3. Rode em conta demo ao vivo por um tempo antes de considerar conta real.
4. **Nunca** rode em conta real sem antes validar backtest + forward test
   em demo. Trading de BTC é volátil e envolve risco real de perda de
   capital — nenhuma configuração aqui é garantia de lucro.

## Estrutura do repositório

```
MQL5/
  Experts/
    BTC_TrendHedge_EA.mq5       # EA de swing trend-following
    BTC_Scalper_EA.mq5          # EA de scalping por reversao a media
    BTC_HedgeGrid_EA.mq5        # EA de hedge grid / martingale
  Include/
    BTCHedgeEA/
      Defines.mqh               # enums e constantes compartilhadas
      RiskManager.mqh           # DailyGain/DailyLoss, Max Drawdown, position sizing (usado por ambos os EAs)
      TrendSignal.mqh           # indicadores e sinal do TrendHedge (EMA/RSI/ATR, multi-timeframe)
      ScalpSignal.mqh           # indicadores e sinal do Scalper (Bandas de Bollinger/RSI, timeframe curto)
      HedgeManager.mqh          # abertura/desfazimento/conversão do hedge de proteção (usado por ambos)
      Dashboard.mqh             # painel visual no gráfico (usado por ambos)
    BTCHedgeGridEA/              # include proprio do HedgeGrid (nao compartilha codigo com o BTCHedgeEA acima)
      Defines.mqh               # enums e estruturas do HedgeGrid
      RiskManager.mqh           # DailyGain/DailyLoss, Max Drawdown (mesma logica, classe separada)
      GridManager.mqh           # nucleo: pernas de compra/venda, grid, volume por tier, gain/loss, breakeven
      TradeLogger.mqh           # exporta CSVs (Common\Files) para o painel web do HedgeGrid
      Dashboard.mqh             # painel no grafico do HedgeGrid
  Presets/
    BTC_Scalper_EA_mais_operacoes.set          # config usada até 29/07 (ver docs/trading-log.md)
    BTC_Scalper_EA_calibrado_2026-07-29.set    # config vigente apos analise do 2o pregao
Dashboard/
  BTC_HedgeGrid.html             # painel web standalone do HedgeGrid (abrir localmente no navegador)
docs/
  strategy-research.md          # pesquisa de estratégias de EAs de mercado
```

## Instalação no MetaEditor / MT5

1. Localize a pasta de dados do seu terminal MT5: no terminal, menu
   **Arquivo → Abrir pasta de dados**.
2. Copie o conteúdo de `MQL5/Include/BTCHedgeEA/` para
   `<pasta de dados>/MQL5/Include/BTCHedgeEA/`.
3. Copie `MQL5/Experts/BTC_TrendHedge_EA.mq5` e/ou `MQL5/Experts/BTC_Scalper_EA.mq5`
   (os dois usam a mesma pasta `Include/BTCHedgeEA/`) para
   `<pasta de dados>/MQL5/Experts/`.
4. Abra o MetaEditor, localize o(s) arquivo(s) em **Experts**, e compile
   (F7). Corrija qualquer erro reportado (ver seção de limitações abaixo).
5. No MT5, arraste o EA para um gráfico de **BTCUSD** (ou o símbolo BTC da
   sua corretora) com conta em modo **Hedging**. Os EAs podem rodar
   juntos no mesmo gráfico (magic numbers diferentes: `990001`/`990002`
   para o TrendHedge, `880001`/`880002` para o Scalper, `770001` para o
   HedgeGrid), mas se mais de um estiver ativo ao mesmo tempo, cada um
   aplica seu próprio circuit breaker DailyGain/DailyLoss de forma
   independente — o P/L de um não é descontado do limite do outro.

### Instalando o `BTC_HedgeGrid_EA`

O `BTC_HedgeGrid_EA` usa sua própria pasta de include
(`BTCHedgeGridEA/`, sem relação com `BTCHedgeEA/` dos outros dois EAs) e
tem um painel web próprio:

1. Copie `MQL5/Include/BTCHedgeGridEA/` para
   `<pasta de dados>/MQL5/Include/BTCHedgeGridEA/`.
2. Copie `MQL5/Experts/BTC_HedgeGrid_EA.mq5` para
   `<pasta de dados>/MQL5/Experts/`.
3. Compile e arraste para o gráfico, como nos passos acima.
4. Abra `Dashboard/BTC_HedgeGrid.html` direto no navegador (funciona
   local, sem servidor) para acompanhar o robô com gráficos diários,
   semanais e mensais — veja a seção "Painel web do HedgeGrid" mais
   abaixo para os detalhes.

## `BTC_TrendHedge_EA` — Parâmetros completos (inputs)

Todos os parâmetros abaixo aparecem na aba **Inputs** do EA no MT5, com o
valor padrão (de fábrica) já configurado no código. Nenhum é obrigatório
alterar para rodar, mas todos podem ser ajustados por gráfico/símbolo.

### Identificação

| Parâmetro | Padrão | O que é |
|---|---|---|
| `InpMagicNumber` | `990001` | Número que identifica as ordens abertas por este EA (evita conflito com outros EAs/manual no mesmo gráfico). As posições de **hedge** usam automaticamente `InpMagicNumber + 1` (ou seja, `990002`), para o EA distinguir "posição principal" de "posição de proteção". |

### Tendência e entrada (indicadores)

| Parâmetro | Padrão | O que é |
|---|---|---|
| `InpTrendTimeframe` | `H4` | Timeframe usado para definir a tendência de fundo (EMA rápida vs. EMA lenta). Só entra a favor dessa tendência. |
| `InpEntryTimeframe` | `H1` | Timeframe usado para o gatilho de entrada (pullback), mais curto que o de tendência. |
| `InpEmaFastPeriod` | `20` | Período da média móvel exponencial (EMA) rápida, usada tanto na tendência quanto na entrada. |
| `InpEmaSlowPeriod` | `50` | Período da EMA lenta, usada só no timeframe de tendência (referência de "fundo" do movimento). |
| `InpRsiPeriod` | `14` | Período do RSI, usado para confirmar retomada de impulso na entrada. |
| `InpRsiUpperNeutral` | `55.0` | Limite superior da "zona neutra" do RSI. Em tendência de baixa, a entrada de venda exige que o RSI tenha estado ≥ 55 e esteja caindo (perdendo força de alta). |
| `InpRsiLowerNeutral` | `45.0` | Limite inferior da zona neutra do RSI. Em tendência de alta, a entrada de compra exige que o RSI tenha estado ≤ 45 e esteja subindo (saindo da correção). |
| `InpAtrPeriod` | `14` | Período do ATR (Average True Range), usado para medir volatilidade e calcular stop loss, take profit, trailing e breakeven. |
| `InpMinAtrPoints` | `500` | Volatilidade mínima exigida (em pontos de ATR) para permitir qualquer entrada nova. Evita operar em mercado "morto"/sem volatilidade suficiente para cobrir spread e stops. Ajuste conforme a escala de pontos do símbolo BTC da sua corretora. |

### Stops, trailing e breakeven

| Parâmetro | Padrão | O que é |
|---|---|---|
| `InpAtrSlMultiplier` | `2.0` | Distância do Stop Loss = ATR atual × este multiplicador. Quanto maior, mais "largo" o stop (menos chance de ser estopado por ruído, mas perda maior se acionado). |
| `InpRewardRiskRatio` | `1.5` | Distância do Take Profit = distância do SL × este valor. Com o padrão, o TP fica a 1.5x a distância do SL (relação risco:retorno de 1:1.5). |
| `InpUseTrailing` | `true` | Liga/desliga o trailing stop automático. |
| `InpTrailingAtrMult` | `1.5` | Distância do trailing stop em relação ao preço atual = ATR × este multiplicador. Só aperta o stop a favor do trade, nunca afrouxa. |
| `InpUseBreakeven` | `true` | Liga/desliga o movimento automático do stop para o ponto de entrada (breakeven) quando o trade avança a favor. |
| `InpBreakevenAtrTrigger` | `1.0` | O breakeven é acionado quando o lucro flutuante atinge ATR × este valor (com o padrão, quando o lucro em preço iguala 1x o ATR). |
| `InpBreakevenLockPoints` | `50` | Quantos pontos além do preço de entrada o stop trava ao acionar o breakeven (garante um pequeno lucro mínimo, em vez de travar exatamente no zero a zero). |

### Dimensionamento de posição (lotes)

| Parâmetro | Padrão | O que é |
|---|---|---|
| `InpRiskPercentPerTrade` | `1.0` (1% da equity) | **Não existe um input de "quantidade de lotes" fixa** — o EA calcula o volume de cada entrada dinamicamente: `lotes = (equity × InpRiskPercentPerTrade / 100) ÷ (perda em dinheiro de 1 lote na distância do Stop Loss calculado)`. Ou seja, o tamanho da posição se ajusta automaticamente à volatilidade do momento (ATR) e ao tamanho da conta, sempre arriscando a mesma fração da equity por trade. O resultado é normalizado para o volume mínimo/máximo/step do símbolo (`SYMBOL_VOLUME_MIN/MAX/STEP`) antes de enviar a ordem. |
| `InpMaxPositionsPerSide` | `1` | Número máximo de posições **principais** simultâneas por lado (ex: no máximo 1 compra e 1 venda principais abertas ao mesmo tempo). Não conta as posições de hedge, que são geridas à parte. |

### Hedge de proteção

| Parâmetro | Padrão | O que é |
|---|---|---|
| `InpHedgeTriggerPercent` | `1.5` (1.5% da equity) | Quando uma posição principal acumula perda flutuante ≥ 1.5% da equity da conta, o EA abre automaticamente uma posição oposta (hedge) para travar o prejuízo naquele ponto. |
| `InpHedgeVolumeRatio` | `1.0` | Volume do hedge = volume da posição original × este valor. `1.0` = hedge do mesmo tamanho (trava 100% do risco adicional a partir daquele ponto); valores menores (ex: `0.5`) fazem um hedge parcial. |
| `InpHedgeRecoveryRatio` | `0.3` | Fração do limiar de hedge (`InpHedgeTriggerPercent`) até a qual a posição original precisa "se recuperar" para o hedge ser desfeito. Com o padrão, se a perda da original encolher para dentro de 0.3 × 1.5% = 0.45% da equity, o hedge é fechado e a original volta a correr sozinha. |
| `InpHedgeConvertRatio` | `1.2` | Se o hedge acumular lucro ≥ 1.2× o valor absoluto da perda da posição original, o EA fecha a posição original (realizando a perda, já limitada) e deixa o hedge correndo sozinho como a posição ativa — na prática, "vira" a operação para o lado que a tendência de fato seguiu. |

### DailyGain / DailyLoss / Max Drawdown (circuit breakers)

| Parâmetro | Padrão | O que é |
|---|---|---|
| `InpUseEquityForDaily` | `true` | Define se o cálculo diário (DG/DL) usa **equity** (saldo + flutuante, `true`) ou **balance** (só saldo fechado, `false`) como referência. |
| `InpDailyLossPercent` **(DL — DailyLoss)** | `3.0` (3% ao dia) | Limite de **perda diária**. Se o P/L do dia cair para -3% ou pior (em relação ao saldo/equity do início do dia, hora do servidor), o EA **fecha todas as posições imediatamente** e bloqueia novas entradas até o próximo dia (rollover do servidor). É o "freio de mão" do robô — não é meta, é limite de segurança. |
| `InpDailyProfitPercent` **(DG — DailyGain)** | `0.0` (desabilitado) | Meta de **ganho diário**. Se > 0 e o P/L do dia atingir esse percentual, o EA **bloqueia novas entradas** pelo resto do dia (protege o lucro já feito), mas **não fecha** as posições abertas — elas continuam sendo geridas (trailing/breakeven/hedge) normalmente. Deixe em `0.0` para não ter meta diária e deixar o EA operar o dia todo. |
| `InpMaxDrawdownPercent` | `12.0` (12%) | **Kill switch** de drawdown total: se a equity cair 12% ou mais em relação ao **pico histórico** de equity já atingido pela conta (não é o dia, é desde sempre), o EA fecha tudo e para de abrir novas posições, igual ao DailyLoss, mas medido contra o pico geral e não o dia. Protege contra uma sequência ruim que se estenda por vários dias. |

### Filtros operacionais

| Parâmetro | Padrão | O que é |
|---|---|---|
| `InpMaxSpreadPoints` | `800` | Spread máximo (em pontos) permitido para abrir uma nova posição. Se o spread do momento estiver acima disso, o EA simplesmente não entra (mas continua gerindo posições já abertas). Ajuste conforme o spread típico do BTC na sua corretora — 800 pontos é só um valor de partida, **confira o spread real do seu símbolo antes de usar**. |
| `InpSlippagePoints` | `50` | Desvio máximo de preço (em pontos) tolerado ao enviar ordens (proteção contra slippage excessivo em momentos de volatilidade). |
| `InpUseSessionFilter` | `false` | Liga/desliga um filtro de janela de horário para novas entradas (BTC opera 24/7, então por padrão vem desligado). |
| `InpSessionStartHour` | `0` | Hora de início da janela permitida (0-23, hora do servidor da corretora). Só é usado se `InpUseSessionFilter = true`. |
| `InpSessionEndHour` | `23` | Hora de fim da janela permitida. Com os padrões (`0` a `23`), a janela cobre o dia todo mesmo se o filtro for ligado. |

### Painel e notificações

| Parâmetro | Padrão | O que é |
|---|---|---|
| `InpEnableDashboard` | `true` | Mostra um painel no canto superior esquerdo do gráfico com: estado do EA (operando/bloqueado e por quê), P/L do dia, drawdown do pico, equity, balance e contagem de posições (compra/venda/hedge). |
| `InpEnablePushNotify` | `false` | Envia notificação push para o app MetaTrader no celular a cada evento importante (novo trade, hedge aberto/fechado, circuit breaker acionado). Exige configurar o MetaQuotes ID em Ferramentas → Opções → Notificações no terminal. |
| `InpEnableEmailNotify` | `false` | Envia e-mail nos mesmos eventos. Exige configurar SMTP em Ferramentas → Opções → E-mail no terminal. |

> **Resumo rápido DG/DL:** `InpDailyLossPercent` é o **DL (DailyLoss)** — limite de perda diária, fecha tudo. `InpDailyProfitPercent` é o **DG (DailyGain)** — meta de ganho diário, só trava novas entradas (não fecha o que já está aberto). Ambos são medidos em % sobre `InpUseEquityForDaily` (equity ou balance) desde a virada do dia no horário do servidor.

## `BTC_Scalper_EA` — Parâmetros completos (inputs)

EA de giro rápido: reavalia sinal a cada barra fechada do timeframe de
entrada (M1 por padrão) em vez de esperar horas como o TrendHedge.
Estratégia de **reversão à média** (Bandas de Bollinger + RSI): quando o
preço fecha fora da banda e o RSI está em extremo, aposta na volta ao
centro, com alvo de lucro **fixo em dólares** por trade.

### Identificação

| Parâmetro | Padrão | O que é |
|---|---|---|
| `InpMagicNumber` | `880001` | Identifica as ordens deste EA. Hedge (se habilitado) usa `880002`. Diferente do magic do TrendHedge (`990001`), então os dois podem rodar juntos sem conflito. |

### Sinal de scalping (reversão à média)

| Parâmetro | Padrão | O que é |
|---|---|---|
| `InpEntryTimeframe` | `M1` | Timeframe do sinal. `M1` = máxima agilidade (mais sinais, mais ruído e mais custo de spread proporcional). `M5` = ainda ágil, porém mais seletivo. |
| `InpBBPeriod` | `20` | Período das Bandas de Bollinger (média móvel central). |
| `InpBBDeviation` | `2.0` | Desvio padrão das bandas — quanto maior, mais raro o preço tocar a banda (menos sinais, porém mais "extremos" quando ocorre). |
| `InpRsiPeriod` | `7` | Período do RSI usado como filtro de confirmação — mais curto que o padrão (14) para reagir mais rápido, coerente com o estilo scalping. |
| `InpRsiOversold` | `25.0` | RSI abaixo deste valor + fechamento na banda inferior = sinal de **compra** (aposta na reversão para cima). |
| `InpRsiOverbought` | `75.0` | RSI acima deste valor + fechamento na banda superior = sinal de **venda** (aposta na reversão para baixo). |
| `InpAtrPeriod` | `14` | Período do ATR, usado só para calcular a distância do Stop Loss. |

### Filtro de tendência (evita comprar "faca caindo")

Adicionado depois de observar ao vivo o EA comprar duas vezes seguidas
durante uma queda forte e contínua do BTC — a reversão à média pura não
tem noção de tendência maior, então ela aposta contra movimentos fortes
sem nenhuma proteção. Este filtro resolve isso.

| Parâmetro | Padrão | O que é |
|---|---|---|
| `InpUseTrendFilter` | `true` | Liga/desliga o filtro. Com ele ligado, só permite **compra** se o preço estiver acima da média de tendência (não compra contra uma queda confirmada), e só permite **venda** se o preço estiver abaixo dela (não vende contra uma alta confirmada). Reduz o número de sinais, mas evita o cenário exato que causou a perda observada. |
| `InpTrendFilterTimeframe` | `M15` | Timeframe da média usada como referência de tendência maior (deve ser mais alto que `InpEntryTimeframe`). |
| `InpTrendFilterPeriod` | `50` | Período da EMA usada como referência. |

### Stop loss e alvo de lucro

| Parâmetro | Padrão | O que é |
|---|---|---|
| `InpAtrSlMultiplier` | `1.0` | Stop Loss = ATR × este multiplicador (mantido apertado, coerente com trades rápidos). É automaticamente alargado se ficar menor que a distância mínima permitida pela corretora (`SYMBOL_TRADE_STOPS_LEVEL`/`FREEZE_LEVEL` + spread atual). |
| `InpTargetProfitUSD` | `1.0` | **Alvo de lucro fixo em dólares por trade.** O EA calcula a distância de preço necessária para que o lote calculado (via risco %) renda exatamente esse valor, e usa isso como Take Profit. Ex: com lote 0.01 e BTC valendo ~$64.000, cada $1 de movimento de preço = $0.01 de lucro nesse lote — então $1.00 de alvo exige ~$100 de movimento a favor. **Em contas pequenas o lote fica preso no mínimo do símbolo, então o alvo em dólares pode exigir um movimento de preço maior do que parece — confira a matemática com a especificação do seu símbolo antes de ajustar expectativas.** |

### Dimensionamento e concorrência

| Parâmetro | Padrão | O que é |
|---|---|---|
| `InpRiskPercentPerTrade` | `2.0` (2% da equity) | Mesma lógica do TrendHedge: define o lote a partir da distância do Stop Loss, arriscando essa fração da equity por trade. Em contas muito pequenas, o lote mínimo do símbolo tende a dominar o cálculo (ver aviso no topo do README). |
| `InpMaxConcurrentPositions` | `3` | Máximo de posições principais abertas ao mesmo tempo (compra + venda somadas). Cada uma fecha sozinha ao bater o TP/SL fixo, liberando espaço para a próxima — é isso que gera o efeito de "abre, fecha, abre outra" pedido. |

### Filtro de spread

| Parâmetro | Padrão | O que é |
|---|---|---|
| `InpMaxSpreadPoints` | `500` | Spread máximo (pontos) para permitir nova entrada. **Este é o parâmetro mais crítico do scalper** — como os alvos são pequenos em dólares, um spread alto consome uma fatia desproporcional do lucro-alvo. Ajuste para o spread real do BTC na sua corretora antes de operar. |

### Hedge de proteção (opcional)

| Parâmetro | Padrão | O que é |
|---|---|---|
| `InpUseHedgeProtection` | `false` | Liga/desliga o hedge de proteção (mesmo mecanismo do TrendHedge — ver seção abaixo). Vem desligado por padrão porque os trades do scalper já têm stop apertado e giro rápido; hedge normalmente é redundante aqui, mas pode ser útil se você aumentar `InpAtrSlMultiplier` ou operar em mercado mais errático. |
| `InpHedgeTriggerPercent` | `1.5` | Só usado se `InpUseHedgeProtection = true`. Ver explicação no TrendHedge. |
| `InpHedgeVolumeRatio` | `1.0` | Idem. |
| `InpHedgeRecoveryRatio` | `0.3` | Idem. |
| `InpHedgeConvertRatio` | `1.2` | Idem. |
| `InpSlippagePoints` | `30` | Desvio máximo (pontos) tolerado nas ordens. |

### DailyGain / DailyLoss / Max Drawdown (circuit breakers)

| Parâmetro | Padrão | O que é |
|---|---|---|
| `InpUseEquityForDaily` | `true` | Usa equity (`true`) ou balance (`false`) como referência para os cálculos diários. |
| `InpDailyLossPercent` **(DL)** | `3.0` (3%) | Limite de perda diária em %. Ao atingir, fecha tudo e bloqueia o dia — igual ao TrendHedge. |
| `InpDailyProfitPercent` **(DG em %)** | `0.0` (desabilitado) | Meta de ganho diário em %, se preferir usar percentual em vez de dólares. |
| `InpDailyProfitTargetUSD` **(DG em $)** | `10.0` | **Meta de ganho diário em dólares** — a forma mais direta de expressar "quero fechar o dia com pelo menos $X" (o que você pediu). Ao atingir, o EA trava novas entradas até o próximo dia, mas não fecha as posições abertas. Ajuste para `30`, `100` etc. conforme a meta do dia — lembrando que isso é um **teto/trava de lucro**, não uma garantia: em dias ruins o EA pode fechar no zero ou negativo (respeitando o `InpDailyLossPercent`), não existe forma de garantir o valor mínimo. Coloque `0` para desabilitar. |
| `InpMaxDrawdownPercent` | `12.0` (12%) | Kill switch de drawdown desde o pico histórico de equity — igual ao TrendHedge. |

### Painel e notificações

| Parâmetro | Padrão | O que é |
|---|---|---|
| `InpEnableDashboard` | `true` | Painel no gráfico, igual ao TrendHedge, com uma linha extra: `Trades hoje` (contagem de entradas do dia) e o progresso da meta `DG` em dólares (atual vs. alvo). |
| `InpEnablePushNotify` | `false` | Push notification a cada evento importante. |
| `InpEnableEmailNotify` | `false` | E-mail a cada evento importante. |

> **Realidade sobre a meta diária em dólares:** com uma conta de ~$31,
> $10/dia já é ~32% de retorno diário e $100/dia é mais de 300% — não é
> uma meta sustentável, é um teto otimista em dias muito favoráveis. O
> parâmetro existe para você travar o lucro quando ele aparecer, não para
> forçá-lo a acontecer. O tamanho realista da meta cresce junto com a
> conta (e com o volume que o lote mínimo permite operar).

## `BTC_HedgeGrid_EA` — Parâmetros completos (inputs)

EA completamente diferente dos dois acima: aqui o hedge bidirecional
**é o núcleo da estratégia**, não uma proteção pontual. Não usa
indicadores — a lógica é toda baseada em pontos e no P/L de cada lado.

> ⚠️ **Isto é uma estratégia tipo martingale/grid.** O lado que está
> perdendo recebe novas posições no mesmo sentido (média para baixo),
> aumentando exposição enquanto o preço não reverte. `InpMaxLevelsPerSide`
> limita quantas aberturas de martingale são permitidas por lado (o EA
> para de adicionar depois disso), mas as posições que já foram abertas
> continuam com seu próprio Stop Loss — o limite reduz o pior caso, não
> o elimina. O EA imprime no log do `OnInit` e mostra no painel uma
> estimativa de **"pior caso por lado"** em dólares (todas as aberturas
> até `InpMaxLevelsPerSide` batendo o Loss) — confira esse número contra
> o tamanho da sua conta antes de rodar em conta real. `InpDailyLossPercent`
> e `InpMaxDrawdownPercent` são a rede de segurança final, mas numa
> martingale o caminho até lá pode ser bem mais brusco que num EA
> direcional comum. Comece com o menor volume possível e valide bastante
> em backtest + demo antes de considerar conta real.

### Como funciona o grid

1. **Ciclo**: sempre que não há nenhuma posição aberta deste EA no
   símbolo, abre um novo ciclo — 1 posição de **compra** + 1 de
   **venda**, simultâneas, ambas com volume `InpBaseVolume` (o "valor de
   entrada" — é a partir dele que tudo mais é calculado). As duas pernas
   são geridas de forma independente dali em diante; se uma perna fechar
   totalmente enquanto a outra ainda tem posições, o EA reabre
   imediatamente uma posição nela, para manter sempre as duas pernas
   abertas (o contador de tier daquela perna não é resetado nesse caso —
   só é zerado quando as duas pernas ficam vazias ao mesmo tempo).
2. **A cada `InpGridStepPoints` pontos**: se a perna está **perdendo** e
   o preço andou esses pontos contra ela desde a última abertura, abre
   mais uma posição no mesmo sentido (média para baixo). Se a perna está
   **ganhando** e o preço andou esses pontos a favor, abre mais uma
   posição a favor **e** sobe o Stop Loss das posições mais antigas
   daquela perna para o breakeven + `InpBreakevenLockPoints` (nunca
   afrouxa o stop, só aperta). Isso continua até `InpMaxLevelsPerSide`
   aberturas naquela perna.
3. **Volume**: dobra (ou multiplica por `InpVolumeMultiplier`) a cada
   `InpLevelsPerTier` aberturas, contando por perna — ex: com os
   padrões, abre 3x a 0,01, depois 3x a 0,02, depois 3x a 0,04.
4. **Gain e Loss em pontos**: cada posição individual recebe, ao ser
   aberta, Take Profit = entrada ± `InpGainPoints` e Stop Loss = entrada
   ± `InpLossPoints` — valores **fixos em pontos**, que não mudam por
   tier. Como o volume já dobra sozinho, o resultado **em dinheiro**
   desses mesmos pontos dobra automaticamente junto (ex: Loss de $10 na
   tier de 0,01 vira $20 sozinho na tier de 0,02) — sem precisar de
   nenhuma tabela extra de valores em dólar por tier. O Stop Loss de
   cada posição é o que garante que nada fica aberto para sempre.

### Identificação

| Parâmetro | Padrão | O que é |
|---|---|---|
| `InpMagicNumber` | `770001` | Identifica as posições deste EA (compra e venda usam o mesmo magic — são diferenciadas pelo tipo da posição, não pelo magic). |

### Valor de entrada e progressão de volume

| Parâmetro | Padrão | O que é |
|---|---|---|
| `InpBaseVolume` | `0.01` | Volume da primeira abertura de cada perna — **este é o "valor de entrada"**: todo o resto (tiers de volume, Gain/Loss em dinheiro) escala a partir dele. |
| `InpVolumeMultiplier` | `2.0` | Multiplicador de volume aplicado a cada novo tier (2.0 = dobra). |
| `InpLevelsPerTier` | `3` | Quantas aberturas no mesmo volume antes de multiplicar (padrão: abre 3x, dobra, abre 3x, dobra...). |
| `InpMaxLevelsPerSide` | `9` | **Limite de segurança**: máximo de aberturas de grid por lado (9 = 3 tiers completos: 0,01 / 0,02 / 0,04 com os padrões). Depois disso o EA para de adicionar posições naquele lado. |

### Grid (pontos) — como calibrar o valor que você ainda não sabe

| Parâmetro | Padrão | O que é |
|---|---|---|
| `InpGridStepPoints` | `3000` | Pontos que o preço precisa andar (a favor OU contra) desde a última abertura da perna para abrir a próxima posição do grid. **Este é o valor "saudável" que você pediu ajuda para pensar** — o EA imprime, no log do `OnInit` (aba Experts do MT5), uma sugestão calculada a partir do ATR(H1,14) atual do símbolo (grid ≈ 0.5× ATR, gain ≈ 1× ATR, loss ≈ 2× ATR). Ajuste conforme a volatilidade real do BTC na sua corretora. |
| `InpGainPoints` | `4000` | Take Profit de cada posição, em pontos, a partir da própria entrada. |
| `InpLossPoints` | `9000` | Stop Loss de cada posição, em pontos, a partir da própria entrada. O valor em dinheiro dobra sozinho a cada tier de volume. |
| `InpBreakevenLockPoints` | `200` | Pontos travados além da entrada quando o breakeven do lado ganhador é ajustado. |

> **Como calibrar:** rode o EA uma vez em qualquer gráfico (mesmo sem
> operar de verdade) e olhe a aba **Experts**: o log do `OnInit` mostra o
> ATR(H1) atual em pontos e a sugestão de `GridStepPoints`/`GainPoints`/`LossPoints`
> a partir dele, além da estimativa de "pior caso por lado" em dólares —
> use isso para decidir se o risco está do tamanho que você aceita.

### Filtros operacionais

| Parâmetro | Padrão | O que é |
|---|---|---|
| `InpMaxSpreadPoints` | `800` | Spread máximo (pontos) para permitir **novas** aberturas (reabertura de perna vazia ou adição de grid). O ajuste do breakeven do lado ganhador continua acontecendo mesmo com spread acima do limite. |
| `InpSlippagePoints` | `50` | Desvio máximo (pontos) tolerado nas ordens. |

### DailyGain / DailyLoss / Max Drawdown (circuit breakers)

| Parâmetro | Padrão | O que é |
|---|---|---|
| `InpUseEquityForDaily` | `true` | Usa equity (`true`) ou balance (`false`) como referência para os cálculos diários. |
| `InpDailyLossPercent` **(DL)** | `5.0` | Limite de perda diária. Ao ser atingido, fecha **todas** as posições imediatamente e bloqueia novas entradas até o próximo dia. |
| `InpDailyProfitPercent` **(DG)** | `0.0` (desabilitado) | Meta de ganho diário. Se > 0 e atingida, bloqueia novas entradas pelo resto do dia, mas não fecha as posições abertas — elas continuam sendo geridas (grid/breakeven) normalmente. |
| `InpMaxDrawdownPercent` | `20.0` | Kill switch: se a equity cair esse percentual desde o pico histórico, fecha tudo e para. |

> Os dois limites diários resetam sozinhos todo dia (baseline
> recalculado na virada do dia, horário do servidor) e o estado é
> persistido via *global variables* do terminal — sobrevive a um
> reinício do MT5 no mesmo dia.

### Painel, exportação e notificações

| Parâmetro | Padrão | O que é |
|---|---|---|
| `InpEnableDashboard` | `true` | Painel no gráfico do MT5 (estado, P/L do dia, drawdown, detalhe de cada perna, estimativa de pior caso). |
| `InpEnableCsvExport` | `true` | Exporta os CSVs consumidos pelo painel web (`Dashboard/BTC_HedgeGrid.html`) para a pasta `Common\Files` do terminal. |
| `InpExportIntervalSeconds` | `15` | Intervalo mínimo entre gravações do snapshot de status (o histórico de trades é gravado imediatamente a cada fechamento). |
| `InpEnablePushNotify` | `false` | Push notification em eventos importantes. |
| `InpEnableEmailNotify` | `false` | E-mail nos mesmos eventos. |

### Painel web do HedgeGrid (`Dashboard/BTC_HedgeGrid.html`)

Um painel completo, com tema claro/escuro, que roda **inteiramente no
seu navegador** (nenhum dado sai da sua máquina) e lê os CSVs que o EA
exporta:

- `BTCHedgeGrid_<magic>_status.csv` — snapshot do estado atual (equity,
  balance, P/L do dia, drawdown, posições e P/L de cada perna).
- `BTCHedgeGrid_<magic>_trades.csv` — histórico de todos os trades já
  encerrados (para os gráficos diário/semanal/mensal e a tabela).

**Onde encontrar os arquivos:** no terminal MT5, menu **Arquivo → Abrir
pasta de dados**, depois vá para `../Common/Files/` (a pasta "Common" é
compartilhada entre todos os terminais MT5 instalados na máquina).

**Como usar:**

1. Abra `Dashboard/BTC_HedgeGrid.html` direto no navegador (duplo clique
   no arquivo, ou arraste para uma aba).
2. Clique em **Carregar CSVs** e selecione os dois arquivos juntos
   (`..._status.csv` e `..._trades.csv`).
3. Em navegadores baseados em Chromium (Chrome, Edge, Brave...), o
   painel oferece **atualização automática** (relê os arquivos a cada
   10 segundos) — clique no botão que aparece após carregar pela
   primeira vez. Em outros navegadores, repita o passo 2 quando quiser
   atualizar.

O painel mostra: estado do robô, equity/balance, P/L do dia e drawdown,
detalhe de cada perna (posições abertas, tier atual, próximo volume,
preço médio, P/L flutuante), gráfico de resultado acumulado, P/L
diário/semanal/mensal, taxa de acerto, ganho/perda médios e a tabela
dos trades mais recentes com o motivo do fechamento (TP, SL, etc.).

## Como funciona o hedge de proteção (`BTC_TrendHedge_EA` / `BTC_Scalper_EA`)

Não é grid nem martingale (não aumenta volume progressivamente) — essa
seção é sobre os dois EAs acima; o `BTC_HedgeGrid_EA` descrito
imediatamente acima tem sua própria lógica (grid/martingale de fato).
Quando uma posição principal atinge perda flutuante ≥
`InpHedgeTriggerPercent` da equity:

1. Abre-se uma posição oposta ("hedge") com volume = volume original ×
   `InpHedgeVolumeRatio`, marcada com magic `InpMagicNumber+1` e comentário
   referenciando o ticket original.
2. Se a posição original se recuperar (perda encolher para dentro do
   buffer `InpHedgeRecoveryRatio`), o hedge é fechado.
3. Se o hedge crescer o suficiente para cobrir a perda da original
   (`InpHedgeConvertRatio`), a original é encerrada (perda realizada e
   limitada) e o hedge continua correndo como a posição ativa.
4. Se a original for fechada por qualquer motivo (SL/TP/trailing/manual),
   o hedge órfão é encerrado automaticamente.

## Por que não foi compilado/testado nesta sessão

Esta sessão roda em um ambiente de nuvem isolado, sem GUI/RDP e com uma
allowlist de rede que bloqueia o domínio de download do MetaTrader
(`download.mql5.com`) e a porta SSH (22) para servidores externos — não
foi possível baixar o instalador do MT5 nem conectar ao servidor do
usuário para compilar/testar remotamente. Por decisão do usuário, o
trabalho desta sessão ficou restrito a código + pesquisa de estratégias;
a compilação e os backtestes ficam por conta do usuário, no seu próprio
MetaEditor/MT5. Isso vale para os três EAs, incluindo o
`BTC_HedgeGrid_EA`. O painel web `Dashboard/BTC_HedgeGrid.html` foi
testado neste ambiente (Chromium headless, com CSVs de exemplo) e
renderiza corretamente nos temas claro e escuro, sem erros de console —
mas o EA em si (`.mq5`/`.mqh`) segue sem compilação real.

## Próximos passos sugeridos

1. Compilar e rodar backtest completo (idealmente 2+ anos de histórico
   BTCUSD, modo "Every tick based on real ticks") variando
   `InpRiskPercentPerTrade`, `InpHedgeTriggerPercent` e os períodos de
   EMA/RSI/ATR para otimizar (TrendHedge/Scalper).
2. Validar o comportamento do circuit breaker (`InpDailyLossPercent`)
   simulando perdas no Strategy Tester (visual mode) para confirmar que
   todas as posições são fechadas corretamente (nos três EAs).
3. Forward test em conta demo por pelo menos algumas semanas antes de
   considerar conta real.
4. Considerar adicionar: filtro de notícias/calendário econômico,
   correlação com outros ativos (ex: ETHUSD, DXY) e otimização walk-forward
   (TrendHedge/Scalper).
5. Para o `BTC_HedgeGrid_EA`: rodar o Strategy Tester cobrindo trechos de
   tendência forte e prolongada do histórico do BTC — é exatamente aí
   que uma martingale sofre mais — e conferir a estimativa de "pior caso
   por lado" contra o tamanho real da conta antes de aumentar
   `InpBaseVolume`.
