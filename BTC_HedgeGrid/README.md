# BTC HedgeGrid EA — Robô de hedge grid (martingale) para BTCUSD

Expert Advisor (EA) para MetaTrader 5, em **conta Hedging**, que mantém
sempre duas posições opostas abertas (1 compra + 1 venda) e vai
adicionando posições em grid conforme o preço se move — dobrando o
volume a cada `N` aberturas — com Gain e Loss fixos em pontos por
posição e breakeven progressivo no lado que está ganhando.

Este é um projeto **separado** dos EAs `BTC_TrendHedge_EA` e
`BTC_Scalper_EA` que já existem na raiz `MQL5/` deste repositório — tem
sua própria pasta, seu próprio Include e seu próprio painel, e não
compartilha código com eles (mesmo estilo de codificação, porém
estratégia completamente diferente).

## ⚠️ Isto é uma estratégia tipo martingale/grid — leia antes de usar

Diferente dos outros dois EAs deste repositório (que usam hedge só como
**proteção pontual**), este EA usa hedge bidirecional como **núcleo da
estratégia**: o lado que está perdendo recebe novas posições no mesmo
sentido (média para baixo), aumentando exposição enquanto o preço não
reverte. Isso é, por definição, mais arriscado que uma estratégia
direcional simples:

- Uma tendência forte e prolongada em uma direção pode acumular várias
  aberturas de grid no lado perdedor, com volume dobrando a cada tier.
- `InpMaxLevelsPerSide` limita **quantas aberturas de martingale** são
  permitidas por lado (o EA para de adicionar depois disso), mas as
  posições que já foram abertas continuam correndo com seu próprio
  Stop Loss — ou seja, o limite reduz o pior caso, não o elimina.
- O EA imprime no log (aba **Experts** do MT5) e mostra no painel uma
  estimativa de **"pior caso por lado"** em dólares, assumindo que todas
  as aberturas até `InpMaxLevelsPerSide` acontecem e todas batem o Loss.
  **Confira esse número antes de rodar em conta real** — se ele for
  maior do que você aceita perder, reduza `InpBaseVolume`,
  `InpMaxLevelsPerSide` ou aumente `InpLossPoints`/`InpGridStepPoints`.
- `InpDailyLossPercent` e `InpMaxDrawdownPercent` são a rede de segurança
  final (fecham tudo), mas numa martingale o caminho até lá pode ser bem
  mais brusco do que num EA direcional comum.

**Não existe combinação de parâmetros que elimine o risco de uma
martingale.** Comece com o menor volume possível, valide em backtest e
conta demo por um bom tempo, e só considere conta real depois de
entender exatamente como o EA se comporta em uma tendência forte de
teste (visual mode do Strategy Tester).

## Como funciona o grid de hedge

### O ciclo

1. Sempre que não há nenhuma posição aberta deste EA no símbolo, o EA
   abre um novo ciclo: 1 posição de **compra** + 1 de **venda**,
   simultâneas, ambas com volume `InpBaseVolume` (o "valor de entrada" —
   é a partir dele que tudo mais é calculado).
2. As duas pernas (compra e venda) são geridas **de forma
   independente** a partir daí. Cada perna guarda um contador de quantas
   vezes já abriu (não decresce, mesmo se posições dessa perna forem
   fechadas) e o preço da sua abertura mais recente (âncora).
3. Se uma perna fechar completamente (todas as suas posições encerradas
   por TP ou SL) enquanto a outra ainda tem posições abertas, o EA abre
   imediatamente uma nova posição nessa perna vazia — para manter a
   regra de **"sempre duas posições em direções opostas"**. O contador
   da perna **não é resetado** nesse caso (continua de onde estava); só
   é zerado quando **as duas pernas** ficam vazias ao mesmo tempo
   (ciclo totalmente encerrado, próximo ciclo recomeça do zero).

### A cada `InpGridStepPoints` pontos

A cada tick, cada perna com posições abertas é avaliada:

- **Se a perna está perdendo** (P/L flutuante negativo) e o preço andou
  `InpGridStepPoints` pontos **contra** ela desde a última abertura
  daquela perna → abre **mais uma posição no mesmo sentido** (média para
  baixo, estilo martingale).
- **Se a perna está ganhando** (P/L flutuante positivo) e o preço andou
  `InpGridStepPoints` pontos **a favor** dela desde a última abertura →
  abre **mais uma posição no mesmo sentido** (escala a favor da
  tendência) **e** sobe o Stop Loss de todas as posições mais antigas
  daquela perna para o breakeven + `InpBreakevenLockPoints` (nunca
  afrouxa um stop, só aperta).

Isso continua até `InpMaxLevelsPerSide` aberturas naquela perna (limite
de segurança) ou até a perna fechar totalmente (TP/SL de cada posição
individual).

### Volume (dobra a cada `InpLevelsPerTier` aberturas)

O volume de cada nova posição depende de **quantas vezes aquela perna já
abriu**, contando desde o início do ciclo (perda ou ganho, tanto faz —
o contador é só "quantas aberturas"):

| Abertura nº (na perna) | Tier | Volume (com `InpBaseVolume=0.01`, `InpVolumeMultiplier=2.0`, `InpLevelsPerTier=3`) |
|---|---|---|
| 1, 2, 3 | 0 | 0,01 |
| 4, 5, 6 | 1 | 0,02 |
| 7, 8, 9 | 2 | 0,04 |
| 10, 11, 12 | 3 | 0,08 (só se `InpMaxLevelsPerSide` > 9) |

### Gain e Loss (em pontos, por posição)

Cada posição individual recebe, no momento em que é aberta:

- **Take Profit** = preço de entrada ± `InpGainPoints` pontos.
- **Stop Loss** = preço de entrada ± `InpLossPoints` pontos.

Os dois ficam **fixos em pontos** (não mudam por tier). Como o volume
já dobra sozinho a cada `InpLevelsPerTier` aberturas, o resultado **em
dinheiro** desses mesmos pontos dobra automaticamente junto — é assim
que se chega ao comportamento pedido ("abriu a 0,01 com loss de $10, a
próxima tier de 0,02 já sai com loss de $20 automaticamente") sem
precisar de nenhuma tabela extra de valores em dólar por tier.

O Stop Loss de cada posição é o que garante que **nada fica aberto para
sempre** — mesmo que o grid nunca mais adicione posições (limite
atingido), cada posição individual tem seu próprio teto de perda.

### Breakeven do lado ganhador

Toda vez que o lado que está ganhando abre uma nova posição a favor
(ver acima), o EA sobe o Stop Loss de **todas** as posições já abertas
daquela perna para `preço de entrada de cada uma ± InpBreakevenLockPoints`
— sempre apertando o stop, nunca afrouxando. Isso trava lucro
progressivamente conforme o movimento continua a favor.

## Estrutura do projeto

```
BTC_HedgeGrid/
  README.md                          # este arquivo
  MQL5/
    Experts/
      BTC_HedgeGrid_EA.mq5            # o Expert Advisor
    Include/
      BTCHedgeGridEA/
        Defines.mqh                  # enums e estruturas compartilhadas
        RiskManager.mqh              # DailyGain/DailyLoss (resetam por dia), Max Drawdown
        GridManager.mqh              # nucleo: pernas, grid, volume por tier, gain/loss, breakeven
        TradeLogger.mqh              # exporta CSVs (Common\Files) para o painel web
        Dashboard.mqh                # painel no grafico do MT5
  Dashboard/
    index.html                       # painel web (abrir localmente no navegador)
```

## Instalação no MetaEditor / MT5

1. Localize a pasta de dados do seu terminal MT5: menu **Arquivo → Abrir
   pasta de dados**.
2. Copie `BTC_HedgeGrid/MQL5/Include/BTCHedgeGridEA/` para
   `<pasta de dados>/MQL5/Include/BTCHedgeGridEA/`.
3. Copie `BTC_HedgeGrid/MQL5/Experts/BTC_HedgeGrid_EA.mq5` para
   `<pasta de dados>/MQL5/Experts/`.
4. Abra o MetaEditor, localize o arquivo em **Experts**, compile (F7) e
   corrija qualquer erro/warning reportado (ver aviso sobre compilação
   no fim deste documento).
5. No MT5, arraste o EA para um gráfico de **BTCUSD** (ou o símbolo BTC
   da sua corretora) com a conta em modo **Hedging**.

## Parâmetros completos (inputs)

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
| `InpMaxLevelsPerSide` | `9` | **Limite de segurança**: número máximo de aberturas de grid por lado (9 = 3 tiers completos: 0,01 / 0,02 / 0,04 com os padrões). Depois disso o EA para de adicionar posições naquele lado — as que já existem continuam com seu SL/TP normal. |

### Grid (pontos) — "me ajude a pensar nesses valores"

| Parâmetro | Padrão | O que é |
|---|---|---|
| `InpGridStepPoints` | `3000` | Quantos pontos o preço precisa andar (a favor OU contra) desde a última abertura da perna para abrir a próxima posição do grid. **Este é o valor que você disse não saber ainda** — o EA imprime, no log do OnInit, uma sugestão calculada a partir do ATR(H1,14) atual do símbolo (grid ≈ 0.5× ATR, gain ≈ 1× ATR, loss ≈ 2× ATR) para te dar um ponto de partida "saudável" — mas ajuste conforme a volatilidade real do BTC na sua corretora e o quanto de espaço você quer entre as aberturas do grid. |
| `InpGainPoints` | `4000` | Take Profit de cada posição, em pontos, a partir da própria entrada. |
| `InpLossPoints` | `9000` | Stop Loss de cada posição, em pontos, a partir da própria entrada. O valor em dinheiro deste Loss dobra sozinho a cada tier de volume (ver seção acima). |
| `InpBreakevenLockPoints` | `200` | Pontos travados além da entrada quando o breakeven do lado ganhador é ajustado. |

> **Como calibrar:** rode o EA uma vez em qualquer gráfico (mesmo sem
> operar de verdade — pode remover depois) e olhe a aba **Experts** do
> MT5: o log do `OnInit` mostra o ATR(H1) atual em pontos e uma sugestão
> de `GridStepPoints`/`GainPoints`/`LossPoints` a partir dele. Ajuste
> esses três inputs e o painel também mostra, a cada início, a
> estimativa de "pior caso por lado" em dólares — use isso para decidir
> se o risco está do tamanho que você aceita.

### Filtros operacionais

| Parâmetro | Padrão | O que é |
|---|---|---|
| `InpMaxSpreadPoints` | `800` | Spread máximo (pontos) para permitir **novas** aberturas (tanto reabertura de perna vazia quanto adição de grid). O ajuste do breakeven do lado ganhador continua acontecendo mesmo com spread acima do limite (não depende de enviar ordem nova). |
| `InpSlippagePoints` | `50` | Desvio máximo (pontos) tolerado nas ordens. |

### DailyGain / DailyLoss / Max Drawdown (circuit breakers, resetam por dia)

| Parâmetro | Padrão | O que é |
|---|---|---|
| `InpUseEquityForDaily` | `true` | Usa equity (`true`) ou balance (`false`) como referência para os cálculos diários. |
| `InpDailyLossPercent` **(DL)** | `5.0` | Limite de perda diária. Ao ser atingido, o EA fecha **todas** as posições imediatamente e bloqueia novas entradas até o próximo dia (vira o dia no horário do servidor). |
| `InpDailyProfitPercent` **(DG)** | `0.0` (desabilitado) | Meta de ganho diário. Se > 0 e atingida, o EA bloqueia novas entradas pelo resto do dia (protege o lucro), mas **não fecha** as posições abertas — elas continuam sendo geridas (grid/breakeven) normalmente. |
| `InpMaxDrawdownPercent` | `20.0` | Kill switch: se a equity cair esse percentual desde o pico histórico (não é o dia, é desde sempre), fecha tudo e para — igual ao DailyLoss, mas contra o pico geral. |

> Ambos os limites diários resetam sozinhos todo dia (baseline
> recalculado na virada do dia, horário do servidor) e o estado é
> persistido via *global variables* do terminal — sobrevive a um
> reinício do MT5 no mesmo dia.

### Painel, exportação e notificações

| Parâmetro | Padrão | O que é |
|---|---|---|
| `InpEnableDashboard` | `true` | Mostra o painel no gráfico do MT5 (estado, P/L do dia, drawdown, detalhe de cada perna, estimativa de pior caso). |
| `InpEnableCsvExport` | `true` | Exporta os CSVs consumidos pelo painel web (`Dashboard/index.html`) para a pasta `Common\Files` do terminal. |
| `InpExportIntervalSeconds` | `15` | Intervalo mínimo entre gravações do snapshot de status (o histórico de trades é gravado imediatamente a cada fechamento, sem esperar esse intervalo). |
| `InpEnablePushNotify` | `false` | Push notification em eventos importantes (abertura de grid, circuit breaker). |
| `InpEnableEmailNotify` | `false` | E-mail nos mesmos eventos (requer SMTP configurado no terminal). |

## Painel web (`Dashboard/index.html`)

Um painel completo, com tema claro/escuro, que roda **inteiramente no
seu navegador** (nenhum dado sai da sua máquina) e lê os CSVs que o EA
exporta:

- `BTCHedgeGrid_<magic>_status.csv` — snapshot do estado atual (equity,
  balance, P/L do dia, drawdown, posições e P/L de cada perna).
- `BTCHedgeGrid_<magic>_trades.csv` — histórico de todos os trades já
  encerrados (para os gráficos diário/semanal/mensal e a tabela).

**Onde encontrar os arquivos:** no terminal MT5, menu **Arquivo → Abrir
pasta de dados**, depois vá para `../Common/Files/` (a pasta "Common" é
compartilhada entre todos os terminais MT5 instalados na máquina, então
o caminho não depende de qual terminal/conta você está usando).

**Como usar:**

1. Abra `BTC_HedgeGrid/Dashboard/index.html` diretamente no navegador
   (duplo clique no arquivo, ou arraste para uma aba).
2. Clique em **Carregar CSVs** e selecione os dois arquivos juntos
   (`..._status.csv` e `..._trades.csv`).
3. Em navegadores baseados em Chromium (Chrome, Edge, Brave...), o
   painel oferece **atualização automática** (relê os arquivos a cada
   10 segundos, sem precisar reabrir o seletor) — clique no botão que
   aparece após carregar pela primeira vez. Em outros navegadores,
   repita o passo 2 quando quiser atualizar.

O painel mostra: estado do robô, equity/balance, P/L do dia e drawdown,
detalhe de cada perna (posições abertas, tier atual, próximo volume,
preço médio, P/L flutuante), gráfico de resultado acumulado, P/L
diário/semanal/mensal, taxa de acerto, ganho/perda médios e a tabela
dos trades mais recentes com o motivo do fechamento (TP, SL, etc.).

## Por que não foi compilado/testado nesta sessão

Assim como os outros dois EAs deste repositório, este código foi escrito
e revisado manualmente, sem um MetaEditor/MT5 disponível neste ambiente
de nuvem isolado (sem GUI e com allowlist de rede que bloqueia o
instalador do MT5). **Antes de qualquer uso, mesmo em conta demo:**

1. Compile no MetaEditor e corrija eventuais erros/warnings.
2. Rode no Strategy Tester (modo "Every tick based on real ticks") em um
   período longo de histórico de BTCUSD, incluindo trechos de tendência
   forte e prolongada — é exatamente aí que uma martingale sofre mais.
3. Confira a estimativa de "pior caso por lado" impressa no log/painel
   contra o tamanho da sua conta antes de ajustar `InpBaseVolume` para
   cima.
4. Rode em conta demo ao vivo por um bom tempo antes de considerar conta
   real.

O painel web (`Dashboard/index.html`) foi testado neste ambiente
(Chromium headless, com CSVs de exemplo) e renderiza corretamente nos
temas claro e escuro, sem erros de console.
