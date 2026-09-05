# Как участвовать (Contributing)

Спасибо за интерес к проекту! Короткие правила, чтобы изменения было легко
ревьюить и мёржить.

## Быстрый старт

```bash
ruby test/run_all.rb                                   # все тесты (офлайн, stdlib)
ruby src/main.rb --deterministic                       # демо-решения
ruby src/scripts/validate_10.rb routing_decisions.json # валидатор (exit 0)
```

## Конвенции

- Ruby, `snake_case`; код ядра — в `src/lib`, стратегии — плагины в
  `src/lib/strategies/`.
- Правила/веса/параметры — в `src/config/routing.yml`; добавление провайдера или
  стратегии не должно менять ядро.
- JSON-вывод — UTF-8; решения — массив.
- Новый код — с тестами (`test/unit` или `test/spec`).

## Что НЕ менять

- `src/scripts/validate_10.rb` — валидатор организаторов.
- `src/data/*` — входные данные кейса.

## Добавление стратегии

1. Создать `src/lib/strategies/<name>.rb`, наследовать `BaseStrategy`,
   определить `KEY` и `score(provider, op, ctx)` (результат `0..1`).
2. Подключить в `Scorer::DEFAULT_STRATEGIES`.
3. Добавить вес в `src/config/routing.yml` (сумма весов = 1.0).
4. Добавить тест в `test/unit/strategies_test.rb`.

## Чек-лист PR

- [ ] `ruby test/run_all.rb` → exit 0 (только stdlib, офлайн)
- [ ] `ruby src/main.rb --deterministic && ruby src/scripts/validate_10.rb routing_decisions.json` → exit 0
- [ ] не затронуты `src/scripts/validate_10.rb` и `src/data/*`
- [ ] документация обновлена при изменении правил/формата
