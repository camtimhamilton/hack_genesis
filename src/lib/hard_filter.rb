# frozen_string_literal: true

require 'time'

# Hard-constraints: определяет, может ли провайдер обработать операцию.
# Возвращает [ok, reason, details]. Логика соответствует eligible_providers
# из src/scripts/validate_10.rb.
class HardFilter
  FALLBACK = 'spacepayments'

  def eligible?(op, provider)
    amount = op['amount']
    bank = op['bank']

    return [false, 'inactive_provider', "status=#{provider.status}"] unless provider.status == 'active'

    if provider.traffic_percentage.to_f.zero? && provider.payment_system != FALLBACK
      return [false, 'inactive_provider', 'traffic_percentage=0']
    end

    if provider.limit_amount_min && amount < provider.limit_amount_min
      return [false, 'amount_below_minimum', "#{amount} < limit_amount_min #{provider.limit_amount_min}"]
    end

    if provider.limit_amount_max && amount > provider.limit_amount_max
      return [false, 'amount_exceeds_limit', "#{amount} > limit_amount_max #{provider.limit_amount_max}"]
    end

    if provider.daily_amount_limit && (provider.daily_approved_amount.to_f + amount) > provider.daily_amount_limit
      return [false, 'daily_limit_exceeded',
              "#{provider.daily_approved_amount} + #{amount} > #{provider.daily_amount_limit}"]
    end

    if provider.in_progress_count_limit && (provider.in_progress_count.to_i + 1) > provider.in_progress_count_limit
      return [false, 'in_progress_limit_exceeded',
              "in_progress_count #{provider.in_progress_count} + 1 > #{provider.in_progress_count_limit}"]
    end

    if provider.in_progress_amount_limit && (provider.in_progress_amount.to_f + amount) > provider.in_progress_amount_limit
      return [false, 'in_progress_limit_exceeded',
              "#{provider.in_progress_amount} + #{amount} > #{provider.in_progress_amount_limit}"]
    end

    if provider.available_requisites.to_i.zero?
      return [false, 'no_available_requisites', 'available_requisites=0']
    end

    if provider.provider_margin_pct.to_f > provider.merchant_margin_pct.to_f && !provider.allow_negative_agreement
      return [false, 'negative_margin',
              "provider_margin #{provider.provider_margin_pct} > merchant_margin #{provider.merchant_margin_pct}"]
    end

    banks = provider.banks
    if banks.any?
      if provider.exclude_banks
        return [false, 'bank_not_in_list', "bank #{bank} в исключениях"] if banks.include?(bank)
      else
        return [false, 'bank_not_in_list', "bank #{bank} не в banks"] unless banks.include?(bank)
      end
    end

    limit = provider.requests_per_minute_limit
    if limit && provider.requests_in_minute(parse_time(op['created_at'])).to_i >= limit.to_i
      return [false, 'rate_limit_exceeded',
              "requests_per_minute #{provider.requests_in_minute(parse_time(op['created_at']))} >= #{limit}"]
    end

    [true, nil, nil]
  end

  private

  def parse_time(str)
    Time.parse(str.to_s)
  rescue StandardError
    Time.now
  end
end
