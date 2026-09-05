# Формат выходных файлов

Движок пишет два артефакта: решения по роутингу и аналитический отчёт.

## `routing_decisions.json` (и `routing_decisions_test.json`)

Массив решений, по одному на операцию:

```json
[
  {
    "operation_id": "op_103",
    "selected_provider": "quickpay",
    "attempts": [
      { "provider": "vipay",   "decision": "skipped",  "reason": "amount_exceeds_limit", "details": "150000 > limit_amount_max 100000" },
      { "provider": "payflow", "decision": "skipped",  "reason": "amount_exceeds_limit", "details": "150000 > limit_amount_max 50000" },
      { "provider": "quickpay","decision": "selected","reason": "only_eligible_provider" }
    ],
    "simulated_result": "approved",
    "latency_sec": 28
  }
]
```

Обязательные поля элемента: `operation_id`, `selected_provider`, `attempts`
(у каждого — `provider`, `decision` ∈ {`selected`,`skipped`}, `reason`),
`simulated_result`. Рекомендуемые: `latency_sec`, `details`.

## `routing_report.json` (и `routing_report_test.json`)

Аналитика + рекомендации (допускаются доп. поля):

```json
{
  "period": "2026-07-30",
  "gateway": "RUB_SBP_WITHDRAW",
  "merchant": "alpha_market",
  "strategy": "weighted",
  "total_operations": 10,
  "distribution": {
    "vipay":    { "count": 4, "share_pct": 40.0, "target_pct": 40, "deviation_pp": 0.0 },
    "payflow":  { "count": 3, "share_pct": 30.0, "target_pct": 35, "deviation_pp": -5.0 },
    "quickpay": { "count": 3, "share_pct": 30.0, "target_pct": 25, "deviation_pp": 5.0 }
  },
  "volume_distribution": { },
  "skip_reasons": { "bank_not_in_list": 5 },
  "results": { "approved": 10, "rejected": 0, "expired": 0, "approval_rate_pct": 100.0 },
  "projected_daily_utilization": {
    "payflow": { "used": 2988800, "limit": 3000000, "utilization_pct": 99.6 }
  },
  "recommendations": [
    "payflow: дневной лимит почти исчерпан (2988800/3000000 = 99.6%) — увеличить daily_amount_limit или снизить traffic_percentage (35)"
  ],
  "unachieved_goals": []
}
```

`recommendations` содержит конкретное правило/параметр для изменения;
`unachieved_goals` — цели, недостижимые при текущих ограничениях.

## `routing_report.html` (и `routing_report_test.html`)

Визуальный двойник JSON-отчёта, который пишется рядом с ним (то же имя, расширение
`.html`). Генерируется из **того же** report-hash, поэтому данные идентичны JSON.

- **Автономность**: валидный HTML5, только inline `<style>` / `<script>` / `<svg>`.
  0 внешних ресурсов — ни CDN, ни сетевых запросов, ни внешних шрифтов. Открывается
  без сети.
- **Оформление**: тёмная тема, шапка с метаданными (gateway/merchant/period/strategy),
  KPI-карточки (всего операций, approval rate, approved/rejected/expired), SVG-графики
  (доли по количеству и объёму, надёжность, утилизация лимитов), таблицы
  (distribution / volume / skip_reasons / utilization / results), рекомендации и
  недостижимые цели.
- **Обязательный артефакт остаётся JSON** — HTML ничего не заменяет, это
  дополнительный визуальный слой.
