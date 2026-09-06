# Тестирование

Тесты полностью офлайн и используют только stdlib `minitest` (без gem).

## Запуск

```bash
ruby test/run_all.rb
```

Одна команда запускает все unit- и spec-тесты и возвращает код `0` при успехе.

Можно запускать и отдельные файлы:

```bash
ruby test/unit/hard_filter_test.rb
ruby test/spec/fallback_spec.rb
```

## Структура

```
test/
├── run_all.rb              # единый раннер (minitest/autorun + glob)
├── test_helper.rb          # LOAD_PATH, фабрики Provider/операции, stub'ы
├── unit/                   # Minitest::Test (assert-стиль)
│   ├── hard_filter_test.rb # 9 hard-constraints + rate-limit
│   ├── scorer_test.rb      # взвешенный скоринг, tie-break, breakdown
│   ├── strategies_test.rb  # 8 стратегий + BaseStrategy
│   ├── provider_test.rb    # статические поля + stateful-метрики
│   ├── router_test.rb      # выбор, fallback, attempts, stateful
│   ├── reporter_test.rb    # distribution / skip / utilization / рекомендации
│   ├── html_reporter_test.rb # HTML5, офлайн (0 внешних ресурсов), экранирование
│   ├── loader_test.rb      # чтение входных данных
│   ├── config_test.rb      # routing.yml
│   ├── simulator_test.rb   # детерминированность, latency
│   └── routing_context_test.rb
└── spec/                   # Minitest::Spec DSL (describe/it)
    ├── hard_constraints_spec.rb  # spec.md §5.1
    ├── reason_dictionary_spec.rb # spec.md §6.1
    ├── fallback_spec.rb          # spec.md §5.4
    └── stateful_spec.rb          # spec.md §5.5
```

## Матрица покрытия

| Слой | Unit | Spec |
| --- | --- | --- |
| HardFilter | ✅ | ✅ |
| Scorer | ✅ | — |
| Стратегии (7) | ✅ | — |
| Provider | ✅ | ✅ |
| Router | ✅ | ✅ (fallback/reason) |
| Reporter | ✅ | — |
| HtmlReporter | ✅ | — |
| Loader / Config / Simulator / RoutingContext | ✅ | — |

## Изоляция слоёв

- `StubSimulator` — фиксированный исход (`approved`/`rejected`/`expired`) по
  провайдеру, без случайности.
- `StubScorer` — фиксированный порядок ранжирования для детерминированных
  сценариев Router.
- `TestFixtures` — фабрики `fixture_provider` / `fixture_op` с дефолтами как в
  `providers.json`.

## CI

GitHub Actions (`.github/workflows/ci.yml`) прогоняет `test/run_all.rb` и
валидатор демо-очереди на каждый push/PR:

```bash
ruby test/run_all.rb
ruby main.rb --deterministic
ruby scripts/validate_10.rb routing_decisions.json
```
