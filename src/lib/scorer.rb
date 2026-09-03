# frozen_string_literal: true

require_relative 'strategies/base'
require_relative 'strategies/count_share'
require_relative 'strategies/volume_share'
require_relative 'strategies/cascade'
require_relative 'strategies/conversion'
require_relative 'strategies/amount_range'
require_relative 'strategies/rate_limit'
require_relative 'strategies/turnover'

# Взвешенный скоринг: объединяет soft-стратегии в единый score.
class Scorer
  DEFAULT_STRATEGIES = [
    CountShareStrategy.new,
    VolumeShareStrategy.new,
    CascadeStrategy.new,
    ConversionStrategy.new,
    AmountRangeStrategy.new,
    RateLimitStrategy.new,
    TurnoverStrategy.new
  ].freeze

  def initialize(weights: {}, strategies: DEFAULT_STRATEGIES, tie_break: 'priority')
    @weights = weights
    @strategies = strategies
    @tie_break = tie_break
  end

  # Ранжирует пул по убыванию score. Возвращает массив пар [provider, score].
  def rank(pool, op, ctx)
    pool.map { |p| [p, score_for(p, op, ctx)] }
        .sort_by { |p, s| [-s, tie_value(p)] }
  end

  def score_for(provider, op, ctx)
    @strategies.sum { |s| weight_for(s.key) * s.score(provider, op, ctx) }
  end

  private

  def weight_for(key)
    @weights.fetch(key, 0.0).to_f
  end

  def tie_value(provider)
    @tie_break == 'priority' ? provider.priority.to_i : 0
  end
end
