# BTC TrendHedge EA — Robô de trade BTC para MetaTrader 5

Expert Advisor (EA) para negociação automatizada de BTCUSD no MetaTrader 5,
em **conta Hedging**. Núcleo trend-following multi-timeframe (EMA + RSI +
ATR) com hedge de proteção, DailyGain/DailyLoss (circuit breaker) e Max
Drawdown (kill switch), inspirado nas funções mais comuns de EAs
comerciais/institucionais — veja [`docs/strategy-research.md`](docs/strategy-research.md)
para a pesquisa completa e o racional de design.

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
    BTC_TrendHedge_EA.mq5       # EA principal (OnInit/OnTick/OnDeinit)
  Include/
    BTCHedgeEA/
      Defines.mqh               # enums e constantes compartilhadas
      RiskManager.mqh           # DailyGain/DailyLoss, Max Drawdown, position sizing
      TrendSignal.mqh           # indicadores e lógica de sinal (EMA/RSI/ATR)
      HedgeManager.mqh          # abertura/desfazimento/conversão do hedge de proteção
      Dashboard.mqh             # painel visual no gráfico
docs/
  strategy-research.md          # pesquisa de estratégias de EAs de mercado
```

## Instalação no MetaEditor / MT5

1. Localize a pasta de dados do seu terminal MT5: no terminal, menu
   **Arquivo → Abrir pasta de dados**.
2. Copie o conteúdo de `MQL5/Include/BTCHedgeEA/` para
   `<pasta de dados>/MQL5/Include/BTCHedgeEA/`.
3. Copie `MQL5/Experts/BTC_TrendHedge_EA.mq5` para
   `<pasta de dados>/MQL5/Experts/`.
4. Abra o MetaEditor, localize o arquivo em **Experts**, e compile
   (F7). Corrija qualquer erro reportado (ver seção de limitações abaixo).
5. No MT5, arraste o EA para um gráfico de **BTCUSD** (ou o símbolo BTC da
   sua corretora) com conta em modo **Hedging**.

## Parâmetros completos (inputs)

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

## Como funciona o hedge de proteção

Não é grid nem martingale (não aumenta volume progressivamente). Quando
uma posição principal atinge perda flutuante ≥ `InpHedgeTriggerPercent`
da equity:

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
MetaEditor/MT5.

## Próximos passos sugeridos

1. Compilar e rodar backtest completo (idealmente 2+ anos de histórico
   BTCUSD, modo "Every tick based on real ticks") variando
   `InpRiskPercentPerTrade`, `InpHedgeTriggerPercent` e os períodos de
   EMA/RSI/ATR para otimizar.
2. Validar o comportamento do circuit breaker (`InpDailyLossPercent`)
   simulando perdas no Strategy Tester (visual mode) para confirmar que
   todas as posições são fechadas corretamente.
3. Forward test em conta demo por pelo menos algumas semanas antes de
   considerar conta real.
4. Considerar adicionar: filtro de notícias/calendário econômico,
   correlação com outros ativos (ex: ETHUSD, DXY) e otimização walk-forward.
