# Log de acompanhamento ao vivo — BTC_Scalper_EA

Registro dos resultados reais reportados em conta demo, a configuração
vigente em cada momento, e os ajustes considerados. Objetivo: decidir
mudanças de parâmetro com base em **amostra suficiente** (vários pregões
ou dezenas de trades), não reagindo a 1-2 operações isoladas.

**Regra de decisão:** só reavaliar/ajustar parâmetros depois de acumular
pelo menos ~10-15 trades novos sob a mesma configuração, ou 3+ pregões
completos — o que vier primeiro. Antes disso, qualquer padrão observado é
tratado como ruído, não sinal.

## Configuração vigente (desde 2026-07-29, pós-análise do 2º pregão)

Arquivo: `MQL5/Presets/BTC_Scalper_EA_calibrado_2026-07-29.set`. Substitui
a configuração "mais_operacoes" abaixo depois da análise do resultado de
28-29/07 (ver seção "Pregões" mais abaixo) — reverte parte do
afrouxamento de sinal, encurta o filtro de tendência e aperta os
circuit breakers diários para o tamanho atual da conta.

> **Mudança de conta (2026-07-29, à noite): migrou para conta Cent
> (1:1000).** Depósito de US$10 aparece como 1000 na moeda da conta —
> multiplicador de **100** (1000/10). Isso importa porque
> `InpTargetProfitUSD` e `InpDailyProfitTargetUSD` são calculados usando
> o valor do tick **na moeda da conta** — sem ajuste, um alvo de "US$1"
> viraria só 1 unidade da moeda da conta (≈ US$0,01 reais), fechando o
> trade quase instantaneamente. Adicionado o input
> **`InpCentAccountMultiplier`** (código: `BTC_Scalper_EA.mq5`, funções
> `RealUsdToAccountCurrency`/`AccountCurrencyToRealUsd`) — os dois inputs
> continuam digitados em **dólares reais** (não precisa recalcular nada
> na mão), o EA converte internamente pelo multiplicador. Setado para
> **100.0** no `.set` (padrão de fábrica continua `1.0`, i.e. conta
> normal). **Requer recompilar o `.mq5` no MetaEditor** — é um input
> novo, não só uma mudança de valor. As % (DailyLoss, DailyGain,
> MaxDrawdown, Risco por trade) não precisaram de nenhum ajuste — já são
> relativas à equity, então são automaticamente compatíveis com
> qualquer conta Cent/Micro.

| Parâmetro | Valor novo | Era | Por quê |
|---|---|---|---|
| `InpBBDeviation` | **2.0** | 1.5 | Volta ao valor mais seletivo — o afrouxamento para "mais operações" parece ter aumentado entradas de baixa qualidade, não sinais melhores. |
| `InpRsiOversold` / `InpRsiOverbought` | **25 / 75** | 35 / 65 | Idem — exige extremos reais antes de apostar na reversão. |
| `InpTrendFilterTimeframe` | **M5** | M15 | M15/EMA50 olha ~12,5h para trás — lento demais para pegar quedas de 30-90min, que foram exatamente o que mais doeu (ver análise). |
| `InpTrendFilterPeriod` | **20** | 50 | Em M5, 20 períodos = ~100min de referência — reage a reversões intradiárias sem virar ruído puro. |
| `InpAtrSlMultiplier` | **1.5** | 1.0 | Mitigação parcial para os stops de ~$2 observados (menores que o spread) em momentos de ATR baixo — alarga o stop proporcionalmente. Não é um piso mínimo de verdade (isso exigiria mudança de código, ver nota abaixo). |
| `InpMaxConcurrentPositions` | **2** | 3 | Reduz o tamanho das rajadas de entradas na mesma direção. |
| `InpUseHedgeProtection` | **false** | true (ligado ao vivo) | Nesse tamanho de conta o gatilho (1,5% ≈ R$0,40-0,45) fica colado na distância de stop normal — hedge vira custo extra (comissão/spread dobrado), não proteção real. Desligado até reavaliar com um gatilho bem mais alto. |
| `InpDailyLossPercent` (DL) | **6.0%** | 20% (ao vivo) / 3% (arquivo) | 20% permitia perder mais de $1 num dia numa conta de ~$13-15 — e ele perdeu isso (ou mais) em menos de 1h, três vezes. 6% trava bem antes disso. 3% havia disparado 2x só no primeiro dia (pode ter sido ruído normal) — 6% é o meio-termo até termos mais amostra. |
| `InpDailyProfitTargetUSD` (DG) | **$2.00** | $10.00 | $10 numa conta de ~$13 é ~77% de meta diária — teto irreal. $2 é mais coerente com o tamanho atual da conta. |

> **Ainda NÃO aplicado (precisa de mudança de código, não só do `.set`):**
> um piso mínimo de distância de stop (equivalente ao `InpMinAtrPoints`
> que o `BTC_TrendHedge_EA` já tem), para nunca operar com SL menor que
> ~2-3x o spread típico do símbolo. `InpAtrSlMultiplier=1.5` ajuda, mas
> não impede um SL de poucos pontos se o ATR do momento estiver muito
> baixo. Também não aplicado: um intervalo mínimo entre entradas
> consecutivas do mesmo lado (cooldown) — hoje o único freio a rajadas é
> `InpMaxConcurrentPositions`. Ambos ficam como próximo passo de código,
> não de calibragem.

### Configuração anterior (2026-07-27 ~15h39 até 2026-07-29 ~13h51)

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

### 2026-07-28 13:19 → 2026-07-29 13:51 (segundo dia — hedge protection ligado)

Análise feita em cima do relatório de histórico exportado do MT5 (96
trades fechados). Config vigente durante todo o período: a "Fase 2"
acima, com `InpUseHedgeProtection=true` e `InpDailyLossPercent=20%`
(ambos ajustados ao vivo, não no `.set`).

**Resultado consolidado:**
- 96 trades, líquido **-$12.99** (bruto -$10.84, comissão -$2.15)
- Taxa de acerto geral: **32.3%** (31 ganhos / 65 perdas)
- Saldo: ~$26 → **$13.33** (rebaixamento máximo de **57.3%** no período)
- Maior sequência de perdas: **18 trades seguidos, -$6.10**, todos de compra

**Assimetria compra/venda** — quase todo o prejuízo veio de um lado só:

| | Trades | Acerto | Líquido |
|---|---|---|---|
| Compra | 57 | 19.3% | -$14.64 |
| Venda | 39 | ~46-51% | +$1.65 |

**Três episódios concentraram a perda**, todos com o mesmo padrão —
rajada de entradas na mesma direção (quase sempre compra) durante um
movimento de preço sustentado, cada uma stopada rapidamente:

| Janela (hora do servidor) | Trades | Líquido | Acerto |
|---|---|---|---|
| 28/07 ~20:09-20:37 | 12 | -$5.21 | 0% |
| 29/07 ~01:00-01:53 | 20 | -$5.31 | 5% |
| 29/07 ~13:23-13:51 | 27 | -$4.79 | 48% (perdas maiores por posições simultâneas — chegou a 7 ao mesmo tempo) |

O episódio das 01:00-01:53 foi isolado trade a trade: são 20 COMPRAS
seguidas, uma por fechamento de barra M1, com o preço caindo de forma
sustentada (~200 pontos em 53min) e **nenhuma venda simultânea** — ou
seja, esse prejuízo específico não veio do hedge disparando, veio do
próprio sinal de reversão à média do Scalper insistindo em comprar
contra uma queda real, sem o filtro de tendência (M15/EMA50, ~12.5h de
lookback) reagir a tempo.

**Achados técnicos:**
1. Filtro de tendência (M15/EMA50) é lento demais para bloquear quedas
   de 30-90min, que foram exatamente o que mais doeu.
2. Distância de stop variou de $2 a $90 (mediana ~$36) — o mínimo de $2
   é menor que o spread+ruído normal do BTC. 13 dos 96 trades fecharam
   em ≤10 segundos, ou seja, o stop já nasce colado à entrada em
   momentos de ATR baixo (`InpAtrSlMultiplier=1.0` sem piso mínimo).
3. Hedge parece estar empilhando posições (até 7 simultâneas, acima do
   `InpMaxConcurrentPositions=3` — hedge não conta nesse limite) mas não
   é a causa raiz do prejuízo grande; funciona mais como custo extra
   (comissão/exposição dobrada) do que proteção, porque o gatilho de
   1.5% (~$0.40-0.45) fica colado na distância de stop normal — exatamente
   o que já estava previsto na nota de 27/07 acima.

**Ajustes aplicados** (ver `MQL5/Presets/BTC_Scalper_EA_calibrado_2026-07-29.set`
e a seção "Configuração vigente" no topo deste arquivo): reverter
BB/RSI para valores mais seletivos, encurtar o filtro de tendência para
M5/EMA20, subir `InpAtrSlMultiplier` para 1.5, reduzir
`InpMaxConcurrentPositions` para 2, desligar o hedge, e apertar
DL para 6% e DG para $2.

**Ainda NÃO aplicado (precisa de mudança de código):**
- Piso mínimo de distância de stop (equivalente ao `InpMinAtrPoints` do
  `BTC_TrendHedge_EA`) — para nunca operar com SL menor que ~2-3x o
  spread típico do símbolo.
- Intervalo mínimo entre entradas consecutivas do mesmo lado (cooldown)
  — hoje só `InpMaxConcurrentPositions` freia rajadas.
- Rodar backtest no Strategy Tester cobrindo janelas como essas 3 antes
  de continuar só com dados ao vivo (ainda não feito).
