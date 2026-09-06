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

# Взвешенный скоринг: объединяет soft-стратегии в единый числовой score.
#
# Итоговый score — взвешенная сумма нормализованных сигналов всех стратегий:
# `score = Σ weight_i · signal_i`, где веса задаются в config/routing.yml.
# При равенстве score используется tie-break (по умолчанию — меньший `priority`).
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

  # @param weights [Hash{String => Numeric}] веса стратегий (ключ — KEY стратегии).
  # @param strategies [Array<Strategy>] набор soft-стратегий (по умолчанию все 8).
  # @param tie_break [String] правило ничьих (`priority` — меньший приоритет).
  # @return [Scorer]
  def initialize(weights: {}, strategies: DEFAULT_STRATEGIES, tie_break: 'priority')
    @weights = weights
    @strategies = strategies
    @tie_break = tie_break
  end

  # Ранжирует пул допустимых провайдеров по убыванию score.
  #
  # @param pool [Array<Provider>] пул допустимых провайдеров.
  # @param op [Hash] операция из очереди.
  # @param ctx [RoutingContext] контекст накопленных факт-долей.
  # @return [Array<Array(Provider, Float)>] пары [provider, score], отсортированные
  #   по убыванию score (при равенстве — по tie-break).
  def rank(pool, op, ctx)
    pool.map { |p| [p, score_for(p, op, ctx)] }
        .sort_by { |p, s| [-s, tie_value(p)] }
  end

  # Считает взвешенный score одного провайдера.
  #
  # @param provider [Provider] провайдер.
  # @param op [Hash] операция.
  # @param ctx [RoutingContext] контекст факт-долей.
  # @return [Float] взвешенная сумма сигналов стратегий.
  def score_for(provider, op, ctx)
    @strategies.sum { |s| weight_for(s.key) * s.score(provider, op, ctx) }
  end

  # Детализированный разбор score по факторам для объяснимости решений.
  #
  # @param provider [Provider] провайдер.
  # @param op [Hash] операция.
  # @param ctx [RoutingContext] контекст.
  # @return [Hash] `{ 'total' => Float, 'factors' => { key => {raw, weight, weighted} } }`.
  def score_breakdown(provider, op, ctx)
    factors = @strategies.each_with_object({}) do |s, acc|
      w = weight_for(s.key)
      raw = s.score(provider, op, ctx)
      acc[s.key] = { 'raw' => round3(raw), 'weight' => w, 'weighted' => round3(w * raw) }
    end
    { 'total' => round3(factors.values.sum { |f| f['weighted'] }), 'factors' => factors }
  end

  # Компактное текстовое объяснение выбора (для `attempts[].details`).
  #
  # @param provider [Provider] выбранный провайдер.
  # @param op [Hash] операция.
  # @param ctx [RoutingContext] контекст.
  # @return [String] строка вида `score=0.123 [key=0.100, ...]`.
  def explain(provider, op, ctx)
    breakdown = score_breakdown(provider, op, ctx)
    parts = breakdown['factors'].reject { |_k, f| f['weighted'].zero? }
                                .map { |k, f| "#{k}=#{format('%.3f', f['weighted'])}" }
    "score=#{format('%.3f', breakdown['total'])} [#{parts.join(', ')}]"
  end

  private

  # Вес стратегии по ключу (0.0 при отсутствии в конфиге).
  #
  # @param key [String] ключ стратегии.
  # @return [Float] вес из конфига.
  def weight_for(key)
    @weights.fetch(key, 0.0).to_f
  end

  # Значение для разрешения ничьих (приоритет при tie_break == 'priority').
  #
  # @param provider [Provider] провайдер.
  # @return [Integer] значение tie-break.
  def tie_value(provider)
    @tie_break == 'priority' ? provider.priority.to_i : 0
  end

  # Округление до трёх знаков после запятой.
  #
  # @param value [Numeric] число.
  # @return [Float] округлённое значение.
  def round3(value)
    (value.to_f * 1000).round / 1000.0
  end
end
