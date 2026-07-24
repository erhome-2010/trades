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

## Parâmetros principais (inputs)

| Grupo | Parâmetro | Descrição |
|---|---|---|
| Identificação | `InpMagicNumber` | Magic number das posições principais (hedge usa Magic+1) |
| Tendência/Entrada | `InpTrendTimeframe`, `InpEntryTimeframe` | Timeframes da tendência de fundo e da entrada por pullback |
| Tendência/Entrada | `InpEmaFastPeriod`, `InpEmaSlowPeriod`, `InpRsiPeriod` | Períodos dos indicadores |
| Tendência/Entrada | `InpMinAtrPoints` | Volatilidade mínima (pontos de ATR) para permitir operar |
| Stops | `InpAtrSlMultiplier`, `InpRewardRiskRatio` | Stop loss por ATR e relação risco:retorno do take profit |
| Stops | `InpUseTrailing`, `InpUseBreakeven` | Trailing stop e breakeven automáticos |
| Risco | `InpRiskPercentPerTrade` | % da equity arriscado por trade (dimensiona o lote) |
| Hedge | `InpHedgeTriggerPercent` | % da equity em perda flutuante que aciona o hedge de proteção |
| Hedge | `InpHedgeVolumeRatio`, `InpHedgeRecoveryRatio`, `InpHedgeConvertRatio` | Proporção de volume do hedge e regras de desfazimento/conversão |
| Circuit breaker | `InpDailyLossPercent` | % de perda diária que fecha tudo e bloqueia o dia |
| Circuit breaker | `InpDailyProfitPercent` | % de ganho diário que bloqueia novas entradas (0 = desabilitado) |
| Circuit breaker | `InpMaxDrawdownPercent` | % de drawdown do pico de equity que interrompe o EA (kill switch) |
| Filtros | `InpMaxSpreadPoints`, `InpUseSessionFilter` | Filtro de spread máximo e de janela de horário |
| Painel/Notificações | `InpEnableDashboard`, `InpEnablePushNotify`, `InpEnableEmailNotify` | Painel no gráfico, push notification e e-mail (configurar em Ferramentas → Opções → Notificações/E-mail no terminal) |

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
