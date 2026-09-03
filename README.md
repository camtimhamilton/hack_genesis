# Умный роутинг выплат · Smart Payout Routing

Кейс **HackGenesis — Задача 2**. Ruby-движок распределения выплат (СБП) между платёжными
провайдерами: жёсткие и мягкие правила, каскадный fallback, объяснимость решений и аналитика.

## Архитектура

```mermaid
flowchart TD
    IN["Input<br/>operations_queue.json<br/>providers.json<br/>config/routing.yml"] --> HF
    HF["HardFilter<br/>9 hard-constraints<br/>status · диапазон суммы · дневной лимит<br/>in-progress · реквизиты · маржа · банк"] -->|"eligible pool"| SC
    SC["Scorer<br/>score = Σ weight × signal<br/>веса из routing.yml"] -->|"ranked"| SM
    SM["Simulator<br/>conversion_24h → approved / rejected"] -->|"rejected → следующий"| SC
    SM -->|"approved"| SU
    SU["StateUpdate<br/>daily_approved_amount · requisites · факт-доли"] --> REP
    REP["Reporter<br/>distribution · рекомендации"] --> OUT["routing_decisions.json<br/>routing_report.json"]
```

## Запуск (одна строка)

```bash
ruby src/main.rb                          # демо → routing_decisions.json + routing_report.json
ruby src/main.rb --deterministic && ruby src/scripts/validate_10.rb routing_decisions.json  # валидация
ruby src/scripts/stress_test.rb           # стресс-тест 10 000 операций
```

## Стресс-тест: 10 000 случайных операций (SEED=42)

| Провайдер | Цель traffic | Факт count | Откл. | Доля по объёму | Утилизация лимита |
| --- | --- | --- | --- | --- | --- |
| vipay | 40% | 36.1% | −3.9 пп | 29.4% | 88.3% |
| payflow | 35% | 19.5% | −15.5 пп | 8.4% | 41.9% |
| quickpay | 25% | 34.4% | +9.4 пп | 48.5% | **91.2%** |

- Успешных каскадов (rejected → следующий): **592**
- Переходов на fallback (`spacepayments`): **994**
- Runtime-отказов (rejected/expired): **1677**

## Структура проекта

```
src/
├── main.rb               # точка входа: очередь → routing_decisions.json + routing_report.json
├── config/
│   └── routing.yml       # веса стратегий, диапазоны сумм, доопределяемые поля
├── lib/
│   ├── loader.rb         # чтение входных данных
│   ├── provider.rb       # модель провайдера + stateful-метрики
│   ├── hard_filter.rb    # hard-constraints → [ok, reason, details]
│   ├── scorer.rb         # взвешенный скоринг
│   ├── strategies/       # 7 стратегий-плагинов (count_share, volume_share, …)
│   ├── router.rb         # оркестрация: выбор + fallback
│   ├── simulator.rb      # вероятностный результат по conversion_24h
│   ├── routing_context.rb# накопление факт-долей count/volume
│   └── reporter.rb       # аналитика + рекомендации
├── data/                 # входные данные кейса
└── scripts/
    ├── validate_10.rb    # валидатор демо-очереди
    ├── test_fallback.rb  # сценарии каскадирования
    └── stress_test.rb    # стресс-тест 10 000 операций
```

## Почему Clean Architecture

- **Разделение ответственности**: фильтрация (`HardFilter`), выбор (`Scorer` + `strategies`),
  исполнение (`Simulator` / `Router`), учёт (`RoutingContext`), отчёт (`Reporter`) — независимые слои.
- **Правила отделены от кода**: веса и параметры — в `config/routing.yml`; новый провайдер или
  стратегия добавляются без изменения ядра.
- **Стратегии как плагины**: единый интерфейс `score(provider, op, ctx)` — новый фактор = новый файл.
- **Тестируемость**: слои проверяются изолированно (`validate_10.rb`, `test_fallback.rb`, `stress_test.rb`).