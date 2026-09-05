# frozen_string_literal: true

require 'json'

# HTML-отчёт: превращает тот же report-hash, что и JSON-отчёт, в автономный
# HTML5-документ с тёмной темой. Полностью офлайн: только inline CSS/JS/SVG,
# без CDN и сетевых запросов. JSON-отчёт остаётся обязательным артефактом.
class HtmlReporter
  # Возвращает HTML-строку для заданного report-hash (структура Reporter#build).
  def render(report)
    <<~HTML
      <!DOCTYPE html>
      <html lang="ru">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>#{h(report['gateway'])} · Routing Report · #{h(report['period'])}</title>
        #{inline_style}
      </head>
      <body>
        #{header(report)}
        <main>
          #{kpi_cards(report)}
          #{distribution_section(report)}
          #{volume_section(report)}
          #{reliability_section(report)}
          #{skip_reasons_section(report)}
          #{utilization_section(report)}
          #{results_section(report)}
          #{recommendations_section(report)}
          #{unachieved_goals_section(report)}
        </main>
        #{footer(report)}
        #{inline_script}
      </body>
      </html>
    HTML
  end

  private

  # --- каркас страницы ---

  def header(report)
    <<~HTML
      <header class="hero">
        <div>
          <p class="eyebrow">Smart Payout Routing</p>
          <h1>Routing Report</h1>
          <p class="subtitle">Автономный аналитический отчёт по маршрутизации выплат</p>
        </div>
        <dl class="meta">
          <div><dt>Gateway</dt><dd>#{h(report['gateway'])}</dd></div>
          <div><dt>Merchant</dt><dd>#{h(report['merchant'])}</dd></div>
          <div><dt>Период</dt><dd>#{h(report['period'])}</dd></div>
          <div><dt>Стратегия</dt><dd>#{h(report['strategy'])}</dd></div>
        </dl>
      </header>
    HTML
  end

  def footer(report)
    <<~HTML
      <footer>
        <p>Сформировано движком роутинга · стратегия #{h(report['strategy'])} ·
        #{h(report['total_operations'])} операций(и). Отчёт автономен: 0 внешних ресурсов.</p>
      </footer>
    HTML
  end

  # --- KPI ---

  def kpi_cards(report)
    results = report['results'] || {}
    approved = results['approved'].to_i
    rejected = results['rejected'].to_i
    expired = results['expired'].to_i
    providers = (report['distribution'] || {}).size
    <<~HTML
      <section>
        <h2 class="section-title">Ключевые показатели</h2>
        <div class="kpi-grid">
          #{kpi_card('Всего операций', report['total_operations'], 'заявки очереди')}
          #{kpi_card('Approval rate', fmt_pct(results['approval_rate_pct']), 'доля approved')}
          #{kpi_card('Approved', approved, 'успешно завершено')}
          #{kpi_card('Rejected', rejected, 'отказы провайдеров')}
          #{kpi_card('Expired', expired, 'таймауты')}
          #{kpi_card('Провайдеры', providers, 'в распределении')}
        </div>
      </section>
    HTML
  end

  def kpi_card(label, value, hint)
    <<~HTML
      <article class="kpi-card">
        <p class="kpi-label">#{h(label)}</p>
        <p class="kpi-value">#{h(value)}</p>
        <p class="kpi-hint">#{h(hint)}</p>
      </article>
    HTML
  end

  # --- распределение по количеству ---

  def distribution_section(report)
    dist = report['distribution'] || {}
    return '' if dist.empty?

    rows = dist.map do |name, d|
      <<~HTML
        <tr>
          <td class="mono">#{h(name)}</td>
          <td>#{h(d['count'])}</td>
          <td>#{fmt_pct(d['share_pct'])}</td>
          <td>#{fmt_pct(d['target_pct'])}</td>
          <td class="#{dev_class(d['deviation_pp'])}">#{fmt_dev(d['deviation_pp'])}</td>
        </tr>
      HTML
    end.join("\n")

    <<~HTML
      <section>
        <h2 class="section-title">Распределение по количеству операций</h2>
        #{bar_chart(dist, value_key: 'share_pct', target_key: 'target_pct', caption: 'share_pct против target_pct')}
        <div class="table-wrap">
          <table>
            <thead>
              <tr><th>Провайдер</th><th>Count</th><th>Share</th><th>Target</th><th>Отклонение</th></tr>
            </thead>
            <tbody>#{rows}</tbody>
          </table>
        </div>
      </section>
    HTML
  end

  # --- распределение по объёму ---

  def volume_section(report)
    dist = report['volume_distribution'] || {}
    return '' if dist.empty?

    rows = dist.map do |name, d|
      <<~HTML
        <tr>
          <td class="mono">#{h(name)}</td>
          <td>#{fmt_money(d['amount'])}</td>
          <td>#{fmt_pct(d['share_pct'])}</td>
          <td>#{fmt_pct(d['target_pct'])}</td>
          <td class="#{dev_class(d['deviation_pp'])}">#{fmt_dev(d['deviation_pp'])}</td>
        </tr>
      HTML
    end.join("\n")

    <<~HTML
      <section>
        <h2 class="section-title">Распределение по объёму</h2>
        #{bar_chart(dist, value_key: 'share_pct', target_key: 'target_pct', caption: 'share_pct против target_pct (объём)')}
        <div class="table-wrap">
          <table>
            <thead>
              <tr><th>Провайдер</th><th>Сумма</th><th>Share</th><th>Target</th><th>Отклонение</th></tr>
            </thead>
            <tbody>#{rows}</tbody>
          </table>
        </div>
      </section>
    HTML
  end

  # --- надёжность ---

  def reliability_section(report)
    rel = report['reliability'] || {}
    return '' if rel.empty?

    rows = rel.map do |name, r|
      obs = r['observations'].nil? ? '—' : h(r['observations'])
      <<~HTML
        <tr>
          <td class="mono">#{h(name)}</td>
          <td>#{fmt_ratio(r['value'])}</td>
          <td>#{fmt_ratio(r['baseline'])}</td>
          <td>#{h(r['source'])}</td>
          <td>#{obs}</td>
        </tr>
      HTML
    end.join("\n")

    <<~HTML
      <section>
        <h2 class="section-title">Динамическая надёжность провайдеров</h2>
        #{reliability_chart(rel)}
        <div class="table-wrap">
          <table>
            <thead>
              <tr><th>Провайдер</th><th>Значение</th><th>Baseline</th><th>Источник</th><th>Наблюдения</th></tr>
            </thead>
            <tbody>#{rows}</tbody>
          </table>
        </div>
      </section>
    HTML
  end

  # --- причины skip ---

  def skip_reasons_section(report)
    reasons = report['skip_reasons'] || {}
    return '' if reasons.empty?

    total = reasons.values.sum
    rows = reasons.sort_by { |_, v| -v }.map do |reason, count|
      share = total.zero? ? 0.0 : count * 100.0 / total
      <<~HTML
        <tr>
          <td class="mono">#{h(reason)}</td>
          <td>#{h(count)}</td>
          <td>#{fmt_pct(share)}</td>
        </tr>
      HTML
    end.join("\n")

    <<~HTML
      <section>
        <h2 class="section-title">Причины пропуска (skip_reasons)</h2>
        <div class="table-wrap">
          <table>
            <thead>
              <tr><th>Reason</th><th>Количество</th><th>Доля</th></tr>
            </thead>
            <tbody>#{rows}</tbody>
          </table>
        </div>
      </section>
    HTML
  end

  # --- утилизация лимитов ---

  def utilization_section(report)
    util = report['projected_daily_utilization'] || {}
    return '' if util.empty?

    rows = util.map do |name, u|
      util_pct = u['utilization_pct'].nil? ? '∞' : fmt_pct(u['utilization_pct'])
      limit = u['limit'].nil? ? '∞' : fmt_money(u['limit'])
      <<~HTML
        <tr>
          <td class="mono">#{h(name)}</td>
          <td>#{fmt_money(u['used'])}</td>
          <td>#{limit}</td>
          <td class="#{util_class(u['utilization_pct'])}">#{util_pct}</td>
          <td>#{h(u['in_progress_count'])} / #{h(u['in_progress_count_limit'])}</td>
          <td>#{fmt_money(u['in_progress_amount'])} / #{fmt_money(u['in_progress_amount_limit'])}</td>
          <td>#{h(u['available_requisites'])}</td>
        </tr>
      HTML
    end.join("\n")

    <<~HTML
      <section>
        <h2 class="section-title">Использование дневных лимитов</h2>
        #{utilization_chart(util)}
        <div class="table-wrap">
          <table>
            <thead>
              <tr><th>Провайдер</th><th>Used</th><th>Limit</th><th>Util</th><th>In-progress (count)</th><th>In-progress (amount)</th><th>Реквизиты</th></tr>
            </thead>
            <tbody>#{rows}</tbody>
          </table>
        </div>
      </section>
    HTML
  end

  # --- результаты ---

  def results_section(report)
    results = report['results'] || {}
    by_provider = results['by_provider'] || {}
    return '' if by_provider.empty?

    rows = by_provider.map do |name, statuses|
      approved = statuses['approved'].to_i
      rejected = statuses['rejected'].to_i
      expired = statuses['expired'].to_i
      <<~HTML
        <tr>
          <td class="mono">#{h(name)}</td>
          <td>#{approved}</td>
          <td>#{rejected}</td>
          <td>#{expired}</td>
        </tr>
      HTML
    end.join("\n")

    <<~HTML
      <section>
        <h2 class="section-title">Результаты по провайдерам</h2>
        <div class="table-wrap">
          <table>
            <thead>
              <tr><th>Провайдер</th><th>Approved</th><th>Rejected</th><th>Expired</th></tr>
            </thead>
            <tbody>#{rows}</tbody>
          </table>
        </div>
      </section>
    HTML
  end

  # --- рекомендации ---

  def recommendations_section(report)
    recs = report['recommendations'] || []
    return '' if recs.empty?

    items = recs.map { |r| "<li>#{h(r)}</li>" }.join("\n")
    <<~HTML
      <section>
        <h2 class="section-title">Рекомендации</h2>
        <ul class="recommendations">#{items}</ul>
      </section>
    HTML
  end

  # --- недостижимые цели ---

  def unachieved_goals_section(report)
    goals = report['unachieved_goals'] || []
    return '' if goals.empty?

    items = goals.map do |g|
      reasons = (g['skip_reasons'] || {}).map { |r, c| "#{h(r)} ×#{c}" }.join(', ')
      reasons = reasons.empty? ? '—' : reasons
      <<~HTML
        <li>
          <span class="mono">#{h(g['provider'])}</span> — цель #{fmt_pct(g['target_pct'])},
          достижимо #{fmt_pct(g['achievable_share_pct'])}
          (#{h(g['eligible_operations'])}/#{h(g['total_operations'])} операций доступно).
          Причины hard-skip: #{reasons}.
        </li>
      HTML
    end.join("\n")

    <<~HTML
      <section>
        <h2 class="section-title">Недостижимые цели</h2>
        <ul class="recommendations">#{items}</ul>
      </section>
    HTML
  end

  # --- SVG-графики ---

  # Горизонтальный bar-chart: фактическая доля и целевая (маркер-линия).
  def bar_chart(data, value_key:, target_key:, caption:)
    entries = data.to_a
    return '' if entries.empty?

    max_value = entries.map { |_, d| [d[value_key].to_f, d[target_key].to_f].max }.max.to_f
    max_value = 1.0 if max_value.zero?

    n = entries.size
    width = 720
    height = [n * 56 + 40, 120].max
    label_w = 120
    track_x = label_w + 10
    track_w = width - track_x - 90

    bars = []
    entries.each_with_index do |(name, d), i|
      y = i * (height - 40) / n + 12
      value_w = track_w * [d[value_key].to_f, 0.0].max / max_value
      target_w = track_w * [d[target_key].to_f, 0.0].max / max_value
      target_x = track_x + target_w
      bars << %(<text x="#{label_w - 8}" y="#{y + 15}" text-anchor="end" class="svglabel">#{h(name)}</text>)
      bars << %(<rect x="#{track_x}" y="#{y}" width="#{track_w}" height="18" rx="3" class="track"></rect>)
      bars << %(<rect x="#{track_x}" y="#{y}" width="#{value_w.round(1)}" height="18" rx="3" class="bar"></rect>)
      bars << %(<line x1="#{target_x.round(1)}" y1="#{y - 4}" x2="#{target_x.round(1)}" y2="#{y + 22}" class="target"></line>)
      bars << %(<text x="#{track_x + value_w.round(1) + 6}" y="#{y + 14}" class="svglabel">#{fmt_pct(d[value_key])}</text>)
    end

    <<~SVG
      <svg viewBox="0 0 #{width} #{height}" role="img" aria-label="#{h(caption)}" class="chart">
        #{bars.join("\n        ")}
      </svg>
      <p class="legend">Столбец — фактическая доля · вертикальная линия — целевая доля · единицы: %</p>
    SVG
  end

  # Bar-chart надёжности: value против baseline (шкала 0..1).
  def reliability_chart(data)
    entries = data.to_a
    return '' if entries.empty?

    n = entries.size
    width = 720
    height = [n * 56 + 40, 120].max
    label_w = 120
    track_x = label_w + 10
    track_w = width - track_x - 90

    bars = []
    entries.each_with_index do |(name, r), i|
      y = i * (height - 40) / n + 12
      value = [[r['value'].to_f, 0.0].max, 1.0].min
      baseline = [[r['baseline'].to_f, 0.0].max, 1.0].min
      value_w = track_w * value
      base_w = track_w * baseline
      bars << %(<text x="#{label_w - 8}" y="#{y + 15}" text-anchor="end" class="svglabel">#{h(name)}</text>)
      bars << %(<rect x="#{track_x}" y="#{y}" width="#{track_w}" height="18" rx="3" class="track"></rect>)
      bars << %(<rect x="#{track_x}" y="#{y}" width="#{base_w.round(1)}" height="18" rx="3" class="bar-dim"></rect>)
      bars << %(<rect x="#{track_x}" y="#{y}" width="#{value_w.round(1)}" height="18" rx="3" class="bar"></rect>)
      bars << %(<text x="#{track_x + value_w.round(1) + 6}" y="#{y + 14}" class="svglabel">#{fmt_ratio(r['value'])}</text>)
    end

    <<~SVG
      <svg viewBox="0 0 #{width} #{height}" role="img" aria-label="reliability value vs baseline" class="chart">
        #{bars.join("\n        ")}
      </svg>
      <p class="legend">Яркий столбец — текущая надёжность · тусклый — baseline · шкала 0..1</p>
    SVG
  end

  # Bar-chart утилизации дневного лимита (0..100%).
  def utilization_chart(data)
    entries = data.to_a
    return '' if entries.empty?

    n = entries.size
    width = 720
    height = [n * 56 + 40, 120].max
    label_w = 120
    track_x = label_w + 10
    track_w = width - track_x - 90

    bars = []
    entries.each_with_index do |(name, u), i|
      y = i * (height - 40) / n + 12
      util = u['utilization_pct']
      w = util.nil? ? 0.0 : track_w * [[util.to_f, 0.0].max, 100.0].min / 100.0
      label = util.nil? ? '∞' : fmt_pct(util)
      bars << %(<text x="#{label_w - 8}" y="#{y + 15}" text-anchor="end" class="svglabel">#{h(name)}</text>)
      bars << %(<rect x="#{track_x}" y="#{y}" width="#{track_w}" height="18" rx="3" class="track"></rect>)
      bars << %(<rect x="#{track_x}" y="#{y}" width="#{w.round(1)}" height="18" rx="3" class="bar-warn"></rect>)
      bars << %(<text x="#{track_x + w.round(1) + 6}" y="#{y + 14}" class="svglabel">#{label}</text>)
    end

    <<~SVG
      <svg viewBox="0 0 #{width} #{height}" role="img" aria-label="daily limit utilization" class="chart">
        #{bars.join("\n        ")}
      </svg>
      <p class="legend">Доля использованного дневного лимита (0..100%; ∞ = без лимита)</p>
    SVG
  end

  # --- форматирование ---

  def fmt_pct(value)
    return '—' if value.nil?

    format('%.1f%%', value.to_f)
  end

  def fmt_dev(value)
    return '—' if value.nil?

    v = value.to_f
    v.positive? ? format('+%.1f п.п.', v) : format('%.1f п.п.', v)
  end

  def fmt_money(value)
    return '—' if value.nil?

    value.to_f.round.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1 ').reverse
  end

  def fmt_ratio(value)
    return '—' if value.nil?

    format('%.3f', value.to_f)
  end

  def dev_class(value)
    v = value.to_f
    return 'pos' if v >= 0.1
    return 'neg' if v <= -0.1

    'ok'
  end

  def util_class(value)
    return 'warn' if !value.nil? && value.to_f >= 90.0

    'ok'
  end

  # HTML-экранирование динамических строк.
  def h(value)
    value.to_s
         .gsub('&', '&amp;')
         .gsub('<', '&lt;')
         .gsub('>', '&gt;')
         .gsub('"', '&quot;')
         .gsub("'", '&#39;')
  end

  # --- inline CSS (тёмная тема) ---

  def inline_style
    <<~CSS
      <style>
        :root {
          --bg: #0d1117;
          --panel: #161b22;
          --panel-2: #1c2128;
          --border: #30363d;
          --text: #e6edf3;
          --muted: #8b949e;
          --accent: #58a6ff;
          --green: #3fb950;
          --red: #f85149;
          --amber: #d29922;
        }
        * { box-sizing: border-box; }
        body {
          margin: 0;
          background: var(--bg);
          color: var(--text);
          font: 15px/1.55 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
        }
        .hero {
          padding: 40px 48px 32px;
          background: linear-gradient(180deg, #1b2a41 0%, var(--bg) 100%);
          border-bottom: 1px solid var(--border);
          display: flex;
          justify-content: space-between;
          gap: 32px;
          flex-wrap: wrap;
        }
        .eyebrow { margin: 0; color: var(--accent); text-transform: uppercase; letter-spacing: .12em; font-size: 12px; }
        h1 { margin: 8px 0 4px; font-size: 30px; }
        .subtitle { margin: 0; color: var(--muted); }
        .meta { display: grid; grid-template-columns: repeat(2, minmax(160px, auto)); gap: 12px 28px; margin: 0; }
        .meta dt { color: var(--muted); font-size: 12px; text-transform: uppercase; letter-spacing: .08em; }
        .meta dd { margin: 2px 0 0; font-weight: 600; }
        main { max-width: 1100px; margin: 0 auto; padding: 32px 24px 64px; }
        section { margin-bottom: 44px; }
        .section-title {
          font-size: 20px;
          margin: 0 0 18px;
          padding-left: 12px;
          border-left: 4px solid var(--accent);
        }
        .kpi-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(150px, 1fr)); gap: 14px; }
        .kpi-card {
          background: var(--panel);
          border: 1px solid var(--border);
          border-radius: 10px;
          padding: 18px 16px;
        }
        .kpi-label { margin: 0; color: var(--muted); font-size: 12px; text-transform: uppercase; letter-spacing: .08em; }
        .kpi-value { margin: 6px 0 2px; font-size: 30px; font-weight: 700; color: var(--text); }
        .kpi-hint { margin: 0; color: var(--muted); font-size: 12px; }
        .table-wrap { overflow-x: auto; border: 1px solid var(--border); border-radius: 10px; background: var(--panel); }
        table { border-collapse: collapse; width: 100%; min-width: 560px; }
        th, td { padding: 10px 14px; text-align: left; border-bottom: 1px solid var(--border); }
        th { color: var(--muted); font-size: 12px; text-transform: uppercase; letter-spacing: .06em; background: var(--panel-2); }
        tbody tr:last-child td { border-bottom: none; }
        tbody tr:hover { background: var(--panel-2); }
        .mono { font-family: "SFMono-Regular", Consolas, "Liberation Mono", Menlo, monospace; }
        .pos { color: var(--green); }
        .neg { color: var(--red); }
        .ok { color: var(--muted); }
        .warn { color: var(--amber); font-weight: 700; }
        .chart { width: 100%; height: auto; display: block; background: var(--panel); border: 1px solid var(--border); border-radius: 10px; padding: 8px; }
        .svglabel { fill: var(--muted); font-size: 12px; }
        .track { fill: #21262d; }
        .bar { fill: var(--accent); }
        .bar-dim { fill: #37475a; }
        .bar-warn { fill: var(--amber); }
        .target { stroke: var(--green); stroke-width: 2; stroke-dasharray: 4 3; }
        .legend { color: var(--muted); font-size: 12px; margin: 8px 2px 14px; }
        ul.recommendations { list-style: none; padding: 0; margin: 0; }
        ul.recommendations li {
          background: var(--panel);
          border: 1px solid var(--border);
          border-left: 4px solid var(--amber);
          border-radius: 8px;
          padding: 12px 16px;
          margin-bottom: 10px;
        }
        footer { border-top: 1px solid var(--border); color: var(--muted); text-align: center; padding: 24px; font-size: 13px; }
        section.collapsed > *:not(.section-title) { display: none; }
        button.toggle {
          background: none; border: none; cursor: pointer;
          color: var(--accent); font-size: 13px; padding: 0; margin-left: 10px;
        }
        button.toggle:hover { text-decoration: underline; }
        @media (max-width: 720px) {
          .hero { padding: 28px 20px 24px; }
          .meta { grid-template-columns: 1fr; }
          main { padding: 20px 14px 48px; }
        }
      </style>
    CSS
  end

  # --- inline JS (аккордеон-переключение секций, без сети) ---

  def inline_script
    <<~JS
      <script>
        (function () {
          var titles = document.querySelectorAll('.section-title');
          titles.forEach(function (title) {
            var btn = document.createElement('button');
            btn.type = 'button';
            btn.className = 'toggle';
            btn.textContent = 'свернуть';
            btn.addEventListener('click', function () {
              var section = title.closest('section');
              var collapsed = section.classList.toggle('collapsed');
              btn.textContent = collapsed ? 'развернуть' : 'свернуть';
            });
            title.appendChild(btn);
          });
        })();
      </script>
    JS
  end
end
