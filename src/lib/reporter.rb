# frozen_string_literal: true

# Аналитика по результатам роутинга: доли (count/volume), причины skip,
# успешность/отказы, использование лимитов и рекомендации по изменению правил.
class Reporter
  HARD_SKIP_REASONS = %w[
    inactive_provider amount_exceeds_limit amount_below_minimum daily_limit_exceeded
    in_progress_limit_exceeded no_available_requisites negative_margin bank_not_in_list
    rate_limit_exceeded
  ].freeze

  def initialize(period: nil, gateway: nil, merchant: nil, strategy: nil)
    @period = period
    @gateway = gateway
    @merchant = merchant
    @strategy = strategy
  end

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

  def external_providers(providers)
    providers.reject { |p| p.payment_system == 'spacepayments' }
  end

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

  def skip_reasons(decisions)
    decisions.each_with_object(Hash.new(0)) do |d, acc|
      d['attempts'].each do |a|
        acc[a['reason']] += 1 if a['decision'] == 'skipped'
      end
    end
  end

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

      # 1) дневной лимит почти исчерпан
      limit = p.daily_amount_limit
      util = limit.to_f.positive? ? (p.daily_approved_amount.to_f * 100.0 / limit) : nil
      if util && util >= 90.0
        recs << format('%s: дневной лимит почти исчерпан (%d/%d = %.1f%%) — увеличить daily_amount_limit или снизить traffic_percentage (%d)',
                       name, p.daily_approved_amount, limit, util, p.traffic_percentage)
      end

      # 2) концентрация объёма
      vshare = pct(vol[name], total_vol)
      vdev = vshare - (p.volume_share_pct || 0).to_f
      if vdev >= 20.0
        recs << format('%s: доля по объёму %.1f%% сильно выше целевой %.0f%% — пересмотреть amount_range_min/max или volume_share_pct',
                       name, vshare, (p.volume_share_pct || 0).to_f)
      end

      # 3) отклонение count-доли
      if dev <= -10.0 && (util.nil? || util < 90.0)
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
