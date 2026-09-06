# Архитектура — Умный роутинг выплат

Движок выбирает платёжного провайдера для каждой выплаты: сначала жёсткая
фильтрация (hard-constraints), затем взвешенный скоринг среди допустимых
(soft-goals), каскадный fallback при отказе и объяснимая аналитика.

## Принципы

- **Разделение hard/soft.** Жёсткие ограничения только допускают/исключают
  провайдера; мягкие цели ранжируют уже допущенных.
- **Стратегии как плагины.** Единый интерфейс `score(provider, op, ctx)` — новый
  фактор = новый файл в `lib/strategies/`.
- **Правила в конфиге.** Веса и параметры — в `config/routing.yml`, без
  правки кода.
- **Объяснимость.** Каждый шаг (hard-отсев, скоринг, fallback) фиксируется в
  `attempts`.

## Поток обработки одной операции

1. `Loader` читает `providers.json`, очередь, `operations_history.csv`,
   `reference_decisions.json`.
2. `HardFilter#eligible?(op, provider)` по каждому провайдеру → пул допустимых
   + причины `skip`.
3. `Scorer` ранжирует пул по взвешенной сумме сигналов → кандидат.
4. `Simulator` выдаёт `approved` / `rejected` / `expired` (по `conversion_24h`).
5. При `rejected`/`expired` — исключить кандидата и повторить шаги 3–4.
6. Если пул внешних провайдеров пуст — fallback на `spacepayments`.
7. Обновить stateful-метрики выбранного провайдера.
8. Записать `attempts` + `selected_provider`.

## Компоненты

| Модуль | Файл | Ответственность |
| --- | --- | --- |
| Loader | `lib/loader.rb` | чтение входных данных |
| Provider | `lib/provider.rb` | модель провайдера, stateful-метрики |
| HardFilter | `lib/hard_filter.rb` | hard-constraints → `[ok, reason]` |
| Scorer | `lib/scorer.rb` | взвешенный скоринг, согласование факторов |
| Strategies | `lib/strategies/*.rb` | по одной стратегии на файл |
| Router | `lib/router.rb` | оркестрация: выбор + fallback + attempts |
| Simulator | `lib/simulator.rb` | `approved`/`rejected`/`expired`, latency |
| RoutingContext | `lib/routing_context.rb` | накопленные факт-доли count/volume |
| Reporter | `lib/reporter.rb` | аналитика + рекомендации |
| Config | `lib/config.rb` | загрузка `config/routing.yml` |
| CLI | `main.rb` | вход → `routing_decisions*.json` + `routing_report*.json` |

## Скоринг

```
score(p) = Σ weight_i · norm(signal_i)
```

Выбор — провайдер с максимальным `score`; при равенстве — меньший `priority`
(детерминированность). Детали — в `docs/routing-rules.md`.

## Интерфейсы

```ruby
HardFilter#eligible?(op, provider) -> [true/false, reason]
Strategy#score(provider, op, ctx)  -> Float (0..1)
Scorer#rank(pool, op, ctx)         -> [[provider, score], ...]
Router#route(op, ctx)              -> decision_hash
Simulator#result(provider)         -> "approved" | "rejected" | "expired"
Reporter#build(decisions, providers, queue) -> report_hash
```
