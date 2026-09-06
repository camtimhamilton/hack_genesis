# frozen_string_literal: true

require_relative 'base'

# Стратегия 7: оборотные обязательства (min/max оборот в сутки).
class TurnoverStrategy < BaseStrategy
  KEY = 'turnover'

  def score(provider, _op, _ctx)
    daily = provider.daily_approved_amount.to_f
    score = 0.5

    min = provider.daily_turnover_min
    max = provider.daily_turnover_max

    score += 0.5 if min && daily < min.to_f
    score -= 0.5 if max && daily >= max.to_f
    clamp(score)
  end
end
