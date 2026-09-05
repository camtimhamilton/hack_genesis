# frozen_string_literal: true

require_relative 'base'

# Стратегия: динамическая надёжность провайдера (reliability, 0..1).
# Инициализируется из operations_history.csv (fallback — conversion_24h),
# затем EWMA-обновляется после каждой операции (approved → ↑, rejected/expired → ↓).
class ReliabilityStrategy < BaseStrategy
  KEY = 'reliability'

  def score(provider, _op, _ctx)
    clamp(provider.reliability.to_f)
  end
end
