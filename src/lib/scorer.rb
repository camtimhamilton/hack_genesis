# frozen_string_literal: true

require_relative 'strategies/base'
require_relative 'strategies/count_share'
require_relative 'strategies/volume_share'
require_relative 'strategies/cascade'
require_relative 'strategies/conversion'
require_relative 'strategies/amount_range'
require_relative 'strategies/rate_limit'
require_relative 'strategies/turnover'
require_relative 'strategies/reliability'

# Взвешенный скоринг: объединяет soft-стратегии в единый score.
class Scorer
  DEFAULT_STRATEGIES = [
    CountShareStrategy.new,
    VolumeShareStrategy.new,
    CascadeStrategy.new,
    ConversionStrategy.new,
    AmountRangeStrategy.new,
    RateLimitStrategy.new,
    TurnoverStrategy.new,
    ReliabilityStrategy.new
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

  # Детализированный разбор score для объяснимости решений.
  def score_breakdown(provider, op, ctx)
    factors = @strategies.each_with_object({}) do |s, acc|
      w = weight_for(s.key)
      raw = s.score(provider, op, ctx)
      acc[s.key] = { 'raw' => round3(raw), 'weight' => w, 'weighted' => round3(w * raw) }
    end
    { 'total' => round3(factors.values.sum { |f| f['weighted'] }), 'factors' => factors }
  end

  # Компактное текстовое объяснение выбора (для attempts[].details).
  def explain(provider, op, ctx)
    breakdown = score_breakdown(provider, op, ctx)
    parts = breakdown['factors'].reject { |_k, f| f['weighted'].zero? }
                                .map { |k, f| "#{k}=#{format('%.3f', f['weighted'])}" }
    "score=#{format('%.3f', breakdown['total'])} [#{parts.join(', ')}]"
  end

  private

  def weight_for(key)
    @weights.fetch(key, 0.0).to_f
  end

  def tie_value(provider)
    @tie_break == 'priority' ? provider.priority.to_i : 0
  end

  def round3(value)
    (value.to_f * 1000).round / 1000.0
  end
end
