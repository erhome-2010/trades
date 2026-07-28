# Log de acompanhamento ao vivo — BTC_Scalper_EA

Registro dos resultados reais reportados em conta demo, a configuração
vigente em cada momento, e os ajustes considerados. Objetivo: decidir
mudanças de parâmetro com base em **amostra suficiente** (vários pregões
ou dezenas de trades), não reagindo a 1-2 operações isoladas.

**Regra de decisão:** só reavaliar/ajustar parâmetros depois de acumular
pelo menos ~10-15 trades novos sob a mesma configuração, ou 3+ pregões
completos — o que vier primeiro. Antes disso, qualquer padrão observado é
tratado como ruído, não sinal.

## Configuração vigente (desde 2026-07-27, ~15h39)

Arquivo: `MQL5/Presets/BTC_Scalper_EA_mais_operacoes.set` (com filtro de
tendência adicionado nesta versão).

| Parâmetro | Valor |
|---|---|
| `InpEntryTimeframe` | M1 |
| `InpBBPeriod` / `InpBBDeviation` | 20 / 1.5 |
| `InpRsiPeriod` | 7 |
| `InpRsiOversold` / `InpRsiOverbought` | 35 / 65 |
| `InpUseTrendFilter` | true (M15, EMA 50) |
| `InpAtrSlMultiplier` | 1.0 |
| `InpTargetProfitUSD` | 1.0 |
| `InpRiskPercentPerTrade` | 2.0% |
| `InpMaxConcurrentPositions` | 3 |
| `InpMaxSpreadPoints` | 3000 (ajustado manualmente em 27/07, padrão de fábrica no código é 500) |
| `InpDailyLossPercent` (DL) | **20.0%** (ajustado manualmente em 27/07, subiu de 3%→10%→20% no mesmo dia; padrão de fábrica no código é 3.0%) |
| `InpDailyProfitTargetUSD` (DG) | $10.00 |
| `InpMaxDrawdownPercent` | 12.0% |
| `InpUseHedgeProtection` | **true** (ligado manualmente em 27/07 à noite; padrão de fábrica no código é `false`) |
| `InpHedgeTriggerPercent` / `InpHedgeVolumeRatio` | 1.5% / 1.0 (valores padrão, não alterados) |
| `InpHedgeRecoveryRatio` / `InpHedgeConvertRatio` | 0.3 / 1.2 (valores padrão, não alterados) |

> Nota: `InpMaxSpreadPoints`, `InpDailyLossPercent` e `InpUseHedgeProtection`
> foram alterados ao vivo pelos Inputs do MT5 e ainda não foram levados
> para o `.set` versionado — atualizar o arquivo quando estabilizarmos os
> valores.
>
> **Atenção ao DL em 20%:** numa conta de ~$28, isso permite até ~$5.6 de
> perda num único dia antes de travar — bem mais espaço que o inicial de
> 3%. É um teste deliberado do usuário para observar mais pregões sem
> interrupção precoce, não um valor recomendado para conta real.
>
> **Hedge com esta equity:** o gatilho de 1.5% equivale a ~$0.40-0.45 de
> perda flutuante — muito próximo da distância de stop loss já usada nas
> operações (que variou de $0.17 a $1.03 nos trades do dia 1). Na prática
> isso deve fazer o hedge disparar em praticamente toda operação
> perdedora, quase imediatamente após abrir, não só em perdas grandes.
> Efeito esperado, a acompanhar nos próximos pregões.

## Pregões

### 2026-07-27 (primeiro dia ao vivo)

Duas fases nesse dia, com configurações diferentes:

**Fase 1 — config inicial (BB 2.0, RSI 25/75, sem filtro de tendência, DL 3%)**
- 3 compras: -0.64, -0.48, -1.03 (a última encerrada pelo circuit breaker em movimento rápido, preço além do SL nominal)
- 1 compra: +0.98 (fechou no TP)
- Circuit breaker de DailyLoss (3%) acionado 2x nessa fase; usuário elevou DL para 10% para continuar testando no mesmo dia.

**Fase 2 — config atual (BB 1.5, RSI 35/65, filtro de tendência M15/EMA50, DL 10%)**
- 4 vendas, 4 perdas: -0.59, -0.71, -0.17, -0.28 (total -1.75)
- Circuit breaker de DailyLoss (10%) acionado ao final, fechando o dia em **-10.21%** (equity 31.15 → 27.97)
- Contexto de mercado: sessão com reversões bruscas e sucessivas (queda forte, disparada de volta, nova queda) — regime difícil para reversão à média mesmo com filtro de tendência.

**Resumo do dia:** 8 trades, 7 perdas + 1 ganho, circuit breaker de DailyLoss acionado 3 vezes no total (2x em 3%, 1x em 10%). Amostra pequena demais para concluir se a config atual (Fase 2) tem edge — precisa de mais pregões.

**Ajustes considerados, NÃO aplicados ainda (aguardando mais amostra):**
- Filtro de tendência mais rígido (usar inclinação da EMA, não só posição relativa) — para reduzir entradas em dias de reversão violenta como este.
- Considerar `InpMaxConcurrentPositions` menor ou intervalo mínimo entre trades — 4 perdas em ~45 minutos sugere possível overtrading em mercado de chicote.
- Revisar se `InpRiskPercentPerTrade` (2%) está adequado dado o tamanho da conta (lotes caindo para 0.01 conforme a equity encolhe).
- Alternativa a considerar mais adiante: rodar backtest no Strategy Tester (não feito ainda) para validar a estratégia com amostra muito maior antes de continuar só com dados ao vivo.

### 2026-07-28 (segundo dia — 3 vendas simultâneas + bug de código encontrado)

- Novo dia resetou o `P/L Diário` corretamente (0.00%), mas o EA ficou
  **bloqueado por `MAX DRAWDOWN`** logo de manhã — mecanismo diferente do
  DailyLoss: mede queda desde o **pico histórico de equity** ($31.15) e
  não reseta por dia. Usuário elevou `InpMaxDrawdownPercent` para
  continuar testando (valor a confirmar/registrar aqui quando informado).
- Log do dia mostrou 3 vendas simultâneas abertas em barras M1
  consecutivas (07:19-07:21) — comportamento esperado de
  `InpMaxConcurrentPositions=3`, não bug. Ponto de atenção: as 3 eram na
  **mesma direção** (o filtro de tendência só liberava venda nesse
  trecho), ou seja, risco concentrado/triplicado no mesmo movimento, não
  diversificado.
- **Bug de código encontrado e corrigido** (`HedgeManager.mqh`,
  `CleanupOrphanHedges`): ao fechar um hedge órfão (posição original já
  encerrada), o ticket era lido *depois* de uma troca de contexto de
  seleção de posição, sempre resultando em `0` — o fechamento falhava
  silenciosamente e o mesmo hedge órfão era redetectado e retentado **em
  loop infinito** (centenas de tentativas/seg no log). Como o hedge é
  aberto sem SL/TP próprio, ele ficou exposto sem proteção até um circuit
  breaker de emergência varrer tudo. Corrigido no commit `f7c0169`
  (capturar o ticket antes da troca de contexto) — corrigido também um
  bug relacionado de leitura de posição desatualizada em
  `OpenHedgesWhereNeeded`. **Isso significa que os resultados do hedge
  no dia 27/07 e início do dia 28/07 podem ter sido afetados por esse
  bug** (hedge órfão sem proteção por um período) — considerar isso ao
  analisar os números da semana na segunda-feira, e dar mais peso aos
  resultados a partir da correção (commit `f7c0169`) em diante.
