# frozen_string_literal: true

require 'time'
require_relative 'hard_filter'
require_relative 'scorer'
require_relative 'simulator'
require_relative 'routing_context'

# Роутер: hard-фильтр → взвешенный скоринг → выбор с fallback.
class Router
  FALLBACK = 'spacepayments'

  def initialize(providers, hard_filter: HardFilter.new, scorer: nil, simulator: nil)
    @providers = providers
    @hard_filter = hard_filter
    @scorer = scorer || Scorer.new
    @simulator = simulator || Simulator.new
  end

  # Обработка очереди с накоплением stateful-метрик. Возвращает [decisions, ctx].
  def process(queue)
    ctx = RoutingContext.new
    decisions = queue.map { |op| route(op, ctx) }
    [decisions, ctx]
  end

  # Роутинг одной операции (мутирует состояние провайдеров и ctx).
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
      status = @simulator.result(p, op)
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
      final_status = @simulator.result(fallback, op)
    end

    reason = selected_reason(selected, external.size)
    attempts = build_attempts(results, ranked, selected, reason, rejected, op, ctx)

    apply_state!(selected, op, ctx) if selected && final_status == 'approved'

    {
      'operation_id' => op['operation_id'],
      'selected_provider' => selected&.payment_system,
      'attempts' => attempts,
      'simulated_result' => final_status,
      'latency_sec' => selected ? @simulator.latency(selected) : nil
    }
  end

  private

  def selected_reason(selected, external_count)
    return nil if selected.nil?
    return 'fallback_self_provider' if selected.payment_system == FALLBACK

    external_count == 1 ? 'only_eligible_provider' : 'highest_score'
  end

  # Объяснимость: для каждого рассмотренного провайдера фиксируем причину.
  # hard-отсев → skip_reason; runtime-отказ → rejected/expired;
  # допущен, но не выбран → lower_score (с указанием score).
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

  def selection_details(provider, reason, op, ctx)
    return 'fallback: пул допустимых внешних провайдеров пуст' if provider.payment_system == FALLBACK
    return 'единственный допустимый внешний провайдер' if reason == 'only_eligible_provider'

    @scorer.explain(provider, op, ctx)
  end

  def apply_state!(provider, op, ctx)
    amount = op['amount']
    provider.add_approved_amount(amount)
    provider.reserve_requisite!
    provider.register_request!(parse_time(op['created_at']))
    ctx.record!(provider.payment_system, amount)
  end

  def parse_time(str)
    Time.parse(str.to_s)
  rescue StandardError
    Time.now
  end
end


