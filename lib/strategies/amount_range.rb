# frozen_string_literal: true

require_relative 'base'

# Стратегия 4: маршрут по диапазону суммы чека.
# Диапазоны задаются в конфиге и мержатся в провайдера как
# amount_range_min / amount_range_max.
class AmountRangeStrategy < BaseStrategy
  KEY = 'amount_range'

  def score(provider, op, _ctx)
    min = provider.amount_range_min
    max = provider.amount_range_max
    return 0.5 if min.nil? && max.nil?

    amount = op['amount'].to_f
    in_band = (min.nil? || amount >= min.to_f) && (max.nil? || amount <= max.to_f)
    # Мягкое влияние: 0.6 в диапазоне, 0.4 вне — чтобы не перебивать балансировку долей.
    in_band ? 0.6 : 0.4
  end
end
