# frozen_string_literal: true

require 'time'
require_relative 'hard_filter'
require_relative 'scorer'
require_relative 'simulator'
require_relative 'routing_context'

# Оркестрирует роутинг одной операции и всей очереди.
#
# Конвейер на операцию: HardFilter (допуск) → Scorer (ранжирование) →
# Simulator (попытка) с каскадом при отказе и fallback на spacepayments при
# пустом пуле; затем — stateful-обновление и сбор attempts для объяснимости.
class Router
  # Платёжная система-фолбэк, на которую уходит трафик при пустом пуле.
  FALLBACK = 'spacepayments'

  # @param providers [Array<Provider>] пул провайдеров.
  # @param hard_filter [HardFilter] фильтр допуска.
  # @param scorer [Scorer, nil] скоринг (nil — Scorer.new по умолчанию).
  # @param simulator [Simulator, nil] симулятор исходов (nil — Simulator.new).
  # @return [Router]
  def initialize(providers, hard_filter: HardFilter.new, scorer: nil, simulator: nil)
    @providers = providers
    @hard_filter = hard_filter
    @scorer = scorer || Scorer.new
    @simulator = simulator || Simulator.new
  end

  # Обрабатывает всю очередь с накоплением stateful-метрик.
  #
  # @param queue [Array<Hash>] операции из очереди.
  # @return [Array(Array<Hash>, RoutingContext)] решения и итоговый контекст.
  def process(queue)
    ctx = RoutingContext.new
    decisions = queue.map { |op| route(op, ctx) }
    [decisions, ctx]
  end

  # Роутит одну операцию: допуск → ранжирование → попытка с каскадом → fallback.
  #
  # Мутирует состояние провайдеров и ctx (stateful-метрики, надёжность).
  #
  # @param op [Hash] операция.
  # @param ctx [RoutingContext] контекст факт-долей.
  # @return [Hash] decision-hash (operation_id, selected_provider, attempts, ...).
  def route(op, ctx)
    ordered = @providers.sort_by { |p| p.priority.to_i }
    results = ordered.map { |p| [p, *@hard_filter.eligible?(op, p)] }

    external = results.select { |(p, ok, _r, _d)| ok && p.payment_system != FALLBACK }.map(&:first)
    fallback = results.find { |(p, ok, _r, _d)| ok && p.payment_system == FALLBACK }&.first

    ranked = @scorer.rank(external, op, ctx)

    selected = nil
    final_status = 'rejected'
    rejected = {}

    ranked.each do |p, _score|
      status = try_provider(p, op)
      if status == 'approved'
        selected = p
        final_status = status
        break
      else
        rejected[p] = status
      end
    end

    if selected.nil? && fallback
      selected = fallback
      final_status = try_provider(fallback, op)
    end

    reason = selected_reason(selected, external.size)
    attempts = build_attempts(results, ranked, selected, reason, rejected, op, ctx)

    apply_state!(selected, op, ctx) if selected && final_status == 'approved'
    apply_reliability!(selected, final_status, rejected)

    {
      'operation_id' => op['operation_id'],
      'selected_provider' => selected&.payment_system,
      'reason' => reason,
      'attempts' => attempts,
      'simulated_result' => final_status,
      'latency_sec' => selected ? @simulator.latency(selected) : nil
    }
  end

  private

  # Пытается провести операцию через провайдера: резервирует in-progress на
  # время симуляции и освобождает после исхода (spec.md §5.5), даже при ошибке.
  #
  # @param provider [Provider] провайдер.
  # @param op [Hash] операция.
  # @return [String] исход симуляции (`approved` | `rejected` | `expired`).
  def try_provider(provider, op)
    provider.reserve_in_progress!(op['amount'])
    @simulator.result(provider, op)
  ensure
    provider.release_in_progress!(op['amount'])
  end

  # Определяет reason-код выбора по итогам роутинга.
  #
  # @param selected [Provider, nil] выбранный провайдер (nil — пустой пул).
  # @param external_count [Integer] количество допустимых внешних провайдеров.
  # @return [String] reason-код из словаря (no_eligible_provider,
  #   fallback_self_provider, only_eligible_provider, highest_score).
  def selected_reason(selected, external_count)
    return 'no_eligible_provider' if selected.nil?
    return 'fallback_self_provider' if selected.payment_system == FALLBACK

    external_count == 1 ? 'only_eligible_provider' : 'highest_score'
  end

  # Объяснимость: для каждого рассмотренного провайдера фиксируем причину.
  # hard-отсев → skip_reason; runtime-отказ → rejected/expired;
  # допущен, но не выбран → lower_score (с указанием score).
  #
  # @param results [Array<Array>] кортежи [provider, ok, skip_reason, details].
  # @param ranked [Array<Array(Provider, Float)>] ранжированный пул.
  # @param selected [Provider, nil] выбранный провайдер.
  # @param reason [String] reason-код выбора.
  # @param rejected [Hash{Provider => String}] провайдеры, отказавшие на попытке.
  # @param op [Hash] операция.
  # @param ctx [RoutingContext] контекст.
  # @return [Array<Hash>] список attempts (selected/skipped с причинами).
  def build_attempts(results, ranked, selected, reason, rejected, op, ctx)
    scores = ranked.to_h { |p, s| [p.payment_system, s] }

    results.each_with_object([]) do |(p, ok, skip_reason, details), acc|
      if p == selected
        entry = { 'provider' => p.payment_system, 'decision' => 'selected', 'reason' => reason }
        entry['details'] = selection_details(p, reason, op, ctx)
        acc << entry
      elsif !ok
        entry = { 'provider' => p.payment_system, 'decision' => 'skipped', 'reason' => skip_reason }
        entry['details'] = details if details
        acc << entry
      elsif rejected.key?(p)
        status = rejected[p]
        acc << { 'provider' => p.payment_system, 'decision' => 'skipped',
                 'reason' => status == 'expired' ? 'expired_by_provider' : 'rejected_by_provider' }
      elsif p.payment_system != FALLBACK
        acc << { 'provider' => p.payment_system, 'decision' => 'skipped', 'reason' => 'lower_score',
                 'details' => "score=#{format('%.3f', scores.fetch(p.payment_system, 0.0))} ниже выбранного" }
      end
      # spacepayments (fallback) не выбран → не попадает в attempts
    end
  end

  # Детализация выбора для attempts выбранного провайдера.
  #
  # @param provider [Provider] выбранный провайдер.
  # @param reason [String] reason-код выбора.
  # @param op [Hash] операция.
  # @param ctx [RoutingContext] контекст.
  # @return [String] пояснение выбора (fallback / единственный / разбор score).
  def selection_details(provider, reason, op, ctx)
    return 'fallback: пул допустимых внешних провайдеров пуст' if provider.payment_system == FALLBACK
    return 'единственный допустимый внешний провайдер' if reason == 'only_eligible_provider'

    @scorer.explain(provider, op, ctx)
  end

  # Фиксирует stateful-обновление после успешной операции у выбранного провайдера.
  #
  # @param provider [Provider] выбранный провайдер.
  # @param op [Hash] операция.
  # @param ctx [RoutingContext] контекст факт-долей.
  # @return [void]
  def apply_state!(provider, op, ctx)
    amount = op['amount']
    provider.add_approved_amount(amount)
    provider.reserve_requisite!
    provider.register_request!(parse_time(op['created_at']))
    ctx.record!(provider.payment_system, amount)
  end

  # Обновление динамической надёжности по исходам: approved → ↑, rejected/expired → ↓.
  # Учитываются и выбранный провайдер, и те, кто отказал/таймаутнул при попытке.
  #
  # @param selected [Provider, nil] выбранный провайдер.
  # @param final_status [String] итоговый исход операции.
  # @param rejected [Hash{Provider => String}] провайдеры, отказавшие на попытке.
  # @return [void]
  def apply_reliability!(selected, final_status, rejected)
    rejected.each { |p, status| p.update_reliability!(status) }
    selected.update_reliability!(final_status) if selected
  end

  # Парсит временную метку операции; при невалидном вводе — текущее время.
  #
  # @param str [String] ISO8601-строка времени.
  # @return [Time] распарсенное время (Time.now при ошибке парсинга).
  def parse_time(str)
    Time.parse(str.to_s)
  rescue StandardError
    Time.now
  end
end


