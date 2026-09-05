# frozen_string_literal: true

# Общий хелпер тестов: подключает ядро из src/lib и предоставляет фабрики
# провайдеров/операций и тестовые дублёры. Только stdlib (minitest), без gem.
$LOAD_PATH.unshift(File.expand_path('../src/lib', __dir__))

require 'minitest/autorun'
require 'minitest/spec'

require 'provider'
require 'hard_filter'
require 'scorer'
require 'router'
require 'simulator'
require 'routing_context'
require 'reporter'
require 'html_reporter'
require 'loader'
require 'config'

# Фабрики и stub-объекты для изоляции слоёв ядра.
module TestFixtures
  # Провайдер, допустимый «по умолчанию»: активен, без лимитов, с реквизитами.
  # Любое поле можно переопределить, чтобы триггернуть нужный hard-constraint.
  def fixture_provider(overrides = {})
    base = {
      'payment_system' => 'vipay',
      'status' => 'active',
      'traffic_percentage' => 40,
      'priority' => 1,
      'limit_amount_min' => nil,
      'limit_amount_max' => nil,
      'daily_amount_limit' => nil,
      'daily_approved_amount' => 0,
      'in_progress_count_limit' => nil,
      'in_progress_count' => 0,
      'in_progress_amount_limit' => nil,
      'in_progress_amount' => 0,
      'available_requisites' => 10,
      'conversion_24h' => 0.9,
      'avg_latency_sec' => 30,
      'banks' => [],
      'exclude_banks' => false,
      'provider_margin_pct' => 1.0,
      'merchant_margin_pct' => 1.5,
      'allow_negative_agreement' => false
    }
    Provider.new(base.merge(overrides))
  end

  def spacepayments_provider
    fixture_provider(
      'payment_system' => 'spacepayments',
      'traffic_percentage' => 0,
      'priority' => 99,
      'banks' => []
    )
  end

  def fixture_op(overrides = {})
    {
      'operation_id' => 'op_test',
      'created_at' => '2026-07-30T09:00:00+03:00',
      'amount' => 1000,
      'bank' => 'sberbank'
    }.merge(overrides)
  end

  # Готовый decision-hash (для тестов Reporter).
  def decision(operation_id, selected_provider, attempts: [], simulated_result: 'approved')
    {
      'operation_id' => operation_id,
      'selected_provider' => selected_provider,
      'attempts' => attempts,
      'simulated_result' => simulated_result
    }
  end

end

# Симулятор с заданным исходом по провайдеру. Top-level — виден и в unit-классах,
# и в spec-DSL (там лексический скоуп не включает TestFixtures).
# Принимает позиционный hash { payment_system => status }; без аргументов — approved.
class StubSimulator < Simulator
  def initialize(by_provider = {})
    super(always_approve: true)
    @by_provider = by_provider
  end

  def result(provider, _op = nil)
    @by_provider.fetch(provider.payment_system, 'approved')
  end
end

# Скорер с фиксированным порядком (для детерминированных тестов Router).
class StubScorer
  def initialize(order)
    @order = order
  end

  def rank(pool, _op, _ctx)
    @order.filter_map do |name|
      provider = pool.find { |p| p.payment_system == name }
      [provider, 1.0] if provider
    end
  end

  def explain(_provider, _op, _ctx)
    'score=1.000 [test]'
  end
end
