# frozen_string_literal: true

require_relative 'base'

# Стратегия 1: целевая доля по количеству заявок (traffic_percentage).
class CountShareStrategy < BaseStrategy
  KEY = 'count_share'

  def score(provider, _op, ctx)
    target = provider.traffic_percentage.to_f / 100.0
    return 0.5 if target <= 0

    clamp(0.5 + (target - ctx.count_share(provider.payment_system)))
  end
end
