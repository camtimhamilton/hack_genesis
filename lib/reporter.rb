# frozen_string_literal: true

# Строит аналитический отчёт по результатам роутинга.
#
# Агрегирует доли по количеству и объёму, причины hard-отсевов, успешность/
# отказы, утилизацию лимитов, динамическую надёжность и формирует рекомендации
# по изменению правил (конкретные числа, O(1) по времени).
class Reporter
  HARD_SKIP_REASONS = %w[
    inactive_provider amount_exceeds_limit amount_below_minimum daily_limit_exceeded
    in_progress_limit_exceeded no_available_requisites negative_margin bank_not_in_list
    rate_limit_exceeded
  ].freeze

  # Порог утилизации дневного лимита, после которого генерируется рекомендация.
  NEAR_LIMIT_THRESHOLD_PCT = 90.0
  # Запас ёмкости (headroom), закладываемый в рекомендуемый лимит.
  LIMIT_HEADROOM = 0.30

  # @param period [String, nil] период отчёта (дата снимка, `YYYY-MM-DD`).
  # @param gateway [String, nil] шлюз.
  # @param merchant [String, nil] мерчант.
  # @param strategy [String, nil] активная стратегия скоринга.
  # @return [Reporter]
  def initialize(period: nil, gateway: nil, merchant: nil, strategy: nil)
    @period = period
    @gateway = gateway
    @merchant = merchant
    @strategy = strategy
  end

  # Собирает полный report-hash (обязательный JSON-артефакт).
  #
  # @param decisions [Array<Hash>] решения роутера.
  # @param providers [Array<Provider>] пул провайдеров.
  # @param queue [Array<Hash>] операции из очереди.
  # @return [Hash] отчёт: period, gateway, merchant, strategy, total_operations,
  #   distribution, volume_distribution, skip_reasons, results, reliability,
  #   projected_daily_utilization, recommendations, unachieved_goals.
  def build(decisions, providers, queue)
    {
      'period' => @period,
      'gateway' => @gateway,
      'merchant' => @merchant,
      'strategy' => @strategy,
      'total_operations' => decisions.size,
      'distribution' => count_distribution(decisions, providers),
      'volume_distribution' => volume_distribution(decisions, providers, queue),
      'skip_reasons' => skip_reasons(decisions),
      'results' => results(decisions),
      'reliability' => reliability_section(providers),
      'projected_daily_utilization' => utilization(providers),
      'recommendations' => recommendations(decisions, providers, queue),
      'unachieved_goals' => unachieved_goals(decisions, providers)
    }
  end

  private

  # Внешние провайдеры (без self-provider fallback spacepayments).
  #
  # @param providers [Array<Provider>] пул провайдеров.
  # @return [Array<Provider>] провайдеры без spacepayments.
  def external_providers(providers)
    providers.reject { |p| p.payment_system == 'spacepayments' }
  end

  # Распределение решений по количеству (count) с отклонением от целевой доли.
  #
  # @param decisions [Array<Hash>] решения.
  # @param providers [Array<Provider>] пул провайдеров.
  # @return [Hash{String => Hash}] по провайдеру: count, share_pct, target_pct,
  #   deviation_pp.
  def count_distribution(decisions, providers)
    total = decisions.size
    counts = decisions.group_by { |d| d['selected_provider'] }.transform_values(&:size)
    external_providers(providers).each_with_object({}) do |p, acc|
      name = p.payment_system
      share = pct(counts.fetch(name, 0), total)
      target = p.traffic_percentage.to_f
      acc[name] = {
        'count' => counts.fetch(name, 0),
        'share_pct' => round1(share),
        'target_pct' => target,
        'deviation_pp' => round1(share - target)
      }
    end
  end

  # Распределение решений по объёму (суммам) с отклонением от целевой доли.
  #
  # @param decisions [Array<Hash>] решения.
  # @param providers [Array<Provider>] пул провайдеров.
  # @param queue [Array<Hash>] операции (для суммы по operation_id).
  # @return [Hash{String => Hash}] по провайдеру: amount, share_pct, target_pct,
  #   deviation_pp.
  def volume_distribution(decisions, providers, queue)
    amounts = queue.each_with_object({}) { |op, acc| acc[op['operation_id']] = op['amount'].to_f }
    vol = Hash.new(0.0)
    decisions.each { |d| vol[d['selected_provider']] += amounts.fetch(d['operation_id'], 0.0) }
    total_vol = vol.values.sum

    external_providers(providers).each_with_object({}) do |p, acc|
      name = p.payment_system
      share = pct(vol[name], total_vol)
      target = (p.volume_share_pct || 0).to_f
      acc[name] = {
        'amount' => vol[name],
        'share_pct' => round1(share),
        'target_pct' => target,
        'deviation_pp' => round1(share - target)
      }
    end
  end

  # Агрегирует частоты причин skip по всем attempts.
  #
  # @param decisions [Array<Hash>] решения.
  # @return [Hash{String => Integer}] reason → количество skipped.
  def skip_reasons(decisions)
    decisions.each_with_object(Hash.new(0)) do |d, acc|
      d['attempts'].each do |a|
        acc[a['reason']] += 1 if a['decision'] == 'skipped'
      end
    end
  end

  # Итоги симуляции: счётчики approved/rejected/expired и approval-rate.
  #
  # @param decisions [Array<Hash>] решения.
  # @return [Hash] approved, rejected, expired, approval_rate_pct, by_provider.
  def results(decisions)
    totals = Hash.new(0)
    by_provider = Hash.new { |h, k| h[k] = Hash.new(0) }
    decisions.each do |d|
      status = d['simulated_result'] || 'unknown'
      totals[status] += 1
      by_provider[d['selected_provider']][status] += 1 if d['selected_provider']
    end

    {
      'approved' => totals['approved'],
      'rejected' => totals['rejected'],
      'expired' => totals['expired'],
      'approval_rate_pct' => round1(pct(totals['approved'], decisions.size)),
      'by_provider' => by_provider
    }
  end

  # Динамическая надёжность провайдеров (доп. секция отчёта, этап 6).
  #
  # @param providers [Array<Provider>] пул провайдеров.
  # @return [Hash{String => Hash}] по провайдеру: value, baseline, source,
  #   observations.
  def reliability_section(providers)
    providers.each_with_object({}) do |p, acc|
      acc[p.payment_system] = {
        'value' => round3(p.reliability),
        'baseline' => round3(p.reliability_baseline),
        'source' => p.reliability_source,
        'observations' => p.reliability_observations
      }
    end
  end

  # Проекция дневной утилизации лимитов по внешним провайдерам.
  #
  # @param providers [Array<Provider>] пул провайдеров.
  # @return [Hash{String => Hash}] по провайдеру: used, limit, utilization_pct,
  #   in-progress-метрики, available_requisites.
  def utilization(providers)
    external_providers(providers).each_with_object({}) do |p, acc|
      limit = p.daily_amount_limit
      used = p.daily_approved_amount.to_f
      acc[p.payment_system] = {
        'used' => p.daily_approved_amount,
        'limit' => limit,
        'utilization_pct' => limit.to_f.positive? ? round1(used * 100.0 / limit) : nil,
        'in_progress_count' => p.in_progress_count,
        'in_progress_count_limit' => p.in_progress_count_limit,
        'in_progress_amount' => p.in_progress_amount,
        'in_progress_amount_limit' => p.in_progress_amount_limit,
        'available_requisites' => p.available_requisites
      }
    end
  end

  # Формирует список рекомендаций по изменению правил (лимиты, доли, реквизиты).
  #
  # @param decisions [Array<Hash>] решения.
  # @param providers [Array<Provider>] пул провайдеров.
  # @param queue [Array<Hash>] операции.
  # @return [Array<String>] текстовые рекомендации.
  def recommendations(decisions, providers, queue)
    recs = []
    counts = decisions.group_by { |d| d['selected_provider'] }.transform_values(&:size)
    total = decisions.size
    amounts = queue.each_with_object({}) { |op, acc| acc[op['operation_id']] = op['amount'].to_f }
    vol = Hash.new(0.0)
    decisions.each { |d| vol[d['selected_provider']] += amounts.fetch(d['operation_id'], 0.0) }
    total_vol = vol.values.sum

    external_providers(providers).each do |p|
      name = p.payment_system
      share = pct(counts.fetch(name, 0), total)
      dev = share - p.traffic_percentage.to_f
      limit = p.daily_amount_limit
      util = limit.to_f.positive? ? (p.daily_approved_amount.to_f * 100.0 / limit) : nil

      # 1) дневной лимит почти исчерпан → конкретный дефицит и целевой лимит
      rec = limit_recommendation(name, p, decisions, total)
      recs << rec if rec

      # 2) концентрация объёма
      vshare = pct(vol[name], total_vol)
      vdev = vshare - (p.volume_share_pct || 0).to_f
      if vdev >= 20.0
        recs << format('%s: доля по объёму %.1f%% сильно выше целевой %.0f%% — пересмотреть amount_range_min/max или volume_share_pct',
                       name, vshare, (p.volume_share_pct || 0).to_f)
      end

      # 3) отклонение count-доли
      if dev <= -10.0 && (util.nil? || util < NEAR_LIMIT_THRESHOLD_PCT)
        recs << format('%s: недобор доли (share %.1f%% < target %.0f%%) — увеличить traffic_percentage или снизить priority',
                       name, share, p.traffic_percentage.to_f)
      elsif dev >= 10.0
        recs << format('%s: факт-доля %.1f%% выше цели %.0f%% — пересмотреть target_pct',
                       name, share, p.traffic_percentage.to_f)
      end

      # 4) реквизиты
      recs << format('%s: закончились реквизиты — пополнить available_requisites', name) if (p.available_requisites || 0) <= 0
    end

    # 5) цели, которые невозможно выполнить при текущих ограничениях
    unachieved_goals(decisions, providers).each do |ug|
      recs << format('%s: цель %.0f%% недостижима при текущих ограничениях (доступен в %d/%d = %.1f%%) — пересмотреть лимиты/banks или снизить traffic_percentage',
                     ug['provider'], ug['target_pct'], ug['eligible_operations'], ug['total_operations'], ug['achievable_share_pct'])
    end

    recs
  end

  # Цели, которые невозможно выполнить: у провайдера положительная целевая доля,
  # но он исключался hard-ограничениями, поэтому даже 100% доступных операций
  # не дотянут до целевой доли.
  #
  # @param decisions [Array<Hash>] решения.
  # @param providers [Array<Provider>] пул провайдеров.
  # @return [Array<Hash>] по недостижимой цели: provider, target_pct,
  #   eligible_operations, total_operations, achievable_share_pct, skip_reasons.
  def unachieved_goals(decisions, providers)
    total = decisions.size
    external_providers(providers).filter_map do |p|
      name = p.payment_system
      target = p.traffic_percentage.to_f
      next unless target.positive?

      hard_skips = 0
      reasons = Hash.new(0)
      decisions.each do |d|
        d['attempts'].each do |a|
          next unless a['provider'] == name && a['decision'] == 'skipped'
          next unless HARD_SKIP_REASONS.include?(a['reason'])

          hard_skips += 1
          reasons[a['reason']] += 1
        end
      end

      eligible = total - hard_skips
      next if eligible.to_f / total >= target / 100.0

      {
        'provider' => name,
        'target_pct' => target,
        'eligible_operations' => eligible,
        'total_operations' => total,
        'achievable_share_pct' => round1(eligible.to_f * 100.0 / total),
        'skip_reasons' => reasons
      }
    end
  end

  # Рекомендация по дневному лимиту с конкретными числами (O(1) по времени):
  # дефицит экстраполируется из текущей утилизации, целевой лимит считается
  # как объём с запасом LIMIT_HEADROOM, доля ухода в каскад — по attempts.
  #
  # @param name [String] имя провайдера.
  # @param provider [Provider] провайдер.
  # @param decisions [Array<Hash>] решения.
  # @param total [Integer] общее число операций.
  # @return [String, nil] рекомендация или nil, если лимит не близок к исчерпанию.
  def limit_recommendation(name, provider, decisions, total)
    limit = provider.daily_amount_limit
    return nil unless limit.to_f.positive?

    used = provider.daily_approved_amount.to_f
    util = used * 100.0 / limit
    return nil if util < NEAR_LIMIT_THRESHOLD_PCT

    cascade_count = limit_cascade_count(decisions, name)
    cascade_pct = pct(cascade_count, total)

    recommended = ceil_significant(used / (1.0 - LIMIT_HEADROOM))
    recommended = ceil_significant(limit * (1.0 + LIMIT_HEADROOM)) if recommended <= limit
    increase_pct = (recommended.to_f / limit - 1.0) * 100.0

    tail = if cascade_count.positive?
             "чтобы предотвратить уход #{cascade_pct.round}% операций в каскад"
           else
             'чтобы сохранить запас по дневному лимиту'
           end

    format('%s: лимит исчерпан на %.1f%% (%s/%s ₽) — рекомендуется увеличить daily_amount_limit до %s ₽ (+%d%%), %s',
           name, round1(util), money(used), money(limit), money(recommended), increase_pct.round, tail)
  end

  # Количество операций, где провайдер был отсечён именно исчерпанием дневного лимита.
  #
  # @param decisions [Array<Hash>] решения.
  # @param name [String] имя провайдера.
  # @return [Integer] число отсечений по daily_limit_exceeded.
  def limit_cascade_count(decisions, name)
    decisions.count do |d|
      d['attempts'].any? do |a|
        a['provider'] == name && a['decision'] == 'skipped' && a['reason'] == 'daily_limit_exceeded'
      end
    end
  end

  # Компактный денежный формат: 2 988 800 → "2.99M", 950 000 → "950k".
  def money(value)
    v = value.to_f
    if v >= 1_000_000
      "#{trim2(v / 1_000_000)}M"
    elsif v >= 1_000
      "#{trim2(v / 1_000)}k"
    else
      v.round.to_s
    end
  end

  def trim2(x)
    format('%.2f', x).sub(/0\z/, '').sub(/\.\z/, '')
  end

  # Округление вверх до двух значащих цифр (4 269 714 → 4 300 000).
  def ceil_significant(value)
    v = value.to_f
    return v if v <= 0

    factor = 10**(Math.log10(v).floor - 1)
    (v / factor).ceil * factor
  end

  def pct(part, whole)
    return 0.0 if whole.to_f.zero?

    part.to_f * 100.0 / whole.to_f
  end

  def round1(value)
    (value.to_f * 10).round / 10.0
  end

  def round3(value)
    (value.to_f * 1000).round / 1000.0
  end
end
