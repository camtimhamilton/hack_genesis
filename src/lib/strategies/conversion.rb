# frozen_string_literal: true

require_relative 'base'

# Стратегия 5: приоритизация по конверсии (conversion_24h).
class ConversionStrategy < BaseStrategy
  KEY = 'conversion'

  def score(provider, _op, _ctx)
    clamp(provider.conversion_24h.to_f)
  end
end
