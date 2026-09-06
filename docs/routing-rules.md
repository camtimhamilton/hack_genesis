# Правила роутинга

Правила делятся на **hard-constraints** (допуск) и **soft-goals** (ранжирование).
Параметры задаются в `config/routing.yml` и в `data/providers.json`.

## Hard-constraints

Жёсткие условия допуска провайдера (при невыполнении любого — провайдер
исключается). Порядок проверок соответствует `HardFilter#eligible?`.

| # | Проверка | Провайдер недоступен, если |
| --- | --- | --- |
| 1 | Статус | `status != "active"` |
| 2 | Нулевой трафик | `traffic_percentage == 0` (кроме `spacepayments` — fallback) |
| 3 | Диапазон суммы | `amount < limit_amount_min` или `amount > limit_amount_max` |
| 4 | Дневной оборот | `daily_approved_amount + amount > daily_amount_limit` |
| 5 | In-progress count | `in_progress_count + 1 > in_progress_count_limit` |
| 6 | In-progress amount | `in_progress_amount + amount > in_progress_amount_limit` |
| 7 | Реквизиты | `available_requisites == 0` |
| 8 | Маржа | `provider_margin_pct > merchant_margin_pct` без `allow_negative_agreement` |
| 9 | Банковский фильтр | банк не в `banks` (или в исключениях при `exclude_banks`) |
| + | Интенсивность | `requests_per_minute >= requests_per_minute_limit` |

`null`-лимиты трактуются как «без ограничения»; `banks: []` — без банковского
фильтра.

## Soft-goals (стратегии)

| # | Стратегия | Критерий |
| --- | --- | --- |
| 1 | Доля по количеству | `traffic_percentage` |
| 2 | Доля по объёму | `volume_share_pct` |
| 3 | Каскад | `priority` (меньше = выше) |
| 4 | Диапазон суммы | `amount_range_min/max` |
| 5 | Конверсия | `conversion_24h` |
| 6 | Интенсивность | `requests_per_minute_limit` |
| 7 | Оборотные обязательства | `daily_turnover_min/max` |
| 8 | Надёжность | `reliability` (0..1, EWMA по исходам) |

Каждая стратегия возвращает `score` в `[0, 1]`. Итоговый выбор — взвешенная сумма
с весами из `config/routing.yml` (сумма весов = 1.0).

## Словарь reason

| reason | Смысл |
| --- | --- |
| `inactive_provider` | статус не `active` (или нулевой трафик у внешнего) |
| `amount_exceeds_limit` | сумма больше `limit_amount_max` |
| `amount_below_minimum` | сумма меньше `limit_amount_min` |
| `daily_limit_exceeded` | превышен дневной оборот |
| `in_progress_limit_exceeded` | превышен лимит in-progress (count/amount) |
| `no_available_requisites` | нет свободных реквизитов |
| `negative_margin` | provider_margin > merchant_margin |
| `bank_not_in_list` | банк не в `banks` / в исключениях |
| `rate_limit_exceeded` | превышена интенсивность |
| `highest_score` | наибольший взвешенный score среди допустимых |
| `only_eligible_provider` | единственный допустимый провайдер |
| `fallback_self_provider` | выбран fallback `spacepayments` |
| `rejected_by_provider` | провайдер отклонил (→ следующий) |
| `expired_by_provider` | таймаут провайдера (→ следующий) |
| `no_eligible_provider` | пул пуст даже после fallback (`selected_provider = null`) |
| `lower_score` | допущен, но не выбран (score ниже выбранного) |

## Fallback

При `rejected`/`expired` выбранный провайдер исключается из пула и выбирается
следующий по рангу; при пустом пуле внешних провайдеров — `spacepayments`.
Последовательность попыток фиксируется в `attempts`.

## Stateful-обновление

После каждой `approved` операции у выбранного провайдера обновляются:
`daily_approved_amount`, счётчики `requests_per_minute`
и накопленные факт-доли count/volume (`RoutingContext`).

После каждой операции обновляется динамическая надёжность `reliability` (0..1)
по EWMA: `approved` → ↑, `rejected`/`expired` → ↓. Базовая надёжность калибруется
из `operations_history.csv` (approved/total по провайдеру); при отсутствии истории —
fallback `conversion_24h`.
