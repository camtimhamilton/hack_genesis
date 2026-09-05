# frozen_string_literal: true

require_relative '../test_helper'

describe 'Динамическая надёжность провайдера (этап 6)' do
  include TestFixtures

  it 'инициализирует надёжность из conversion_24h как fallback' do
    p = fixture_provider('conversion_24h' => 0.87)
    _(p.reliability).must_equal 0.87
    _(p.reliability_source).must_equal 'conversion_24h'
  end

  it 'калибрует надёжность из истории (approved/total)' do
    p = fixture_provider
    p.seed_reliability!(0.8, source: 'history', observations: 40)
    _(p.reliability).must_equal 0.8
    _(p.reliability_source).must_equal 'history'
    _(p.reliability_observations).must_equal 40
  end

  it 'увеличивает надёжность после approved (EWMA)' do
    p = fixture_provider('conversion_24h' => 0.5)
    p.update_reliability!('approved')
    _(p.reliability).must_be :>, 0.5
  end

  it 'уменьшает надёжность после rejected/expired (EWMA)' do
    p = fixture_provider('conversion_24h' => 0.5)
    p.update_reliability!('rejected')
    _(p.reliability).must_be :<, 0.5

    q = fixture_provider('conversion_24h' => 0.5)
    q.update_reliability!('expired')
    _(q.reliability).must_be :<, 0.5
  end

  it 'обновляет надёжность после каждой операции в роутере' do
    vipay = fixture_provider('payment_system' => 'vipay', 'conversion_24h' => 0.5)
    router = Router.new([vipay], simulator: Simulator.new(always_approve: true))
    router.route(fixture_op, RoutingContext.new)
    _(vipay.reliability).must_be :>, 0.5
  end

  it 'сохраняет обязательную структуру отчёта при добавлении секции reliability' do
    p = fixture_provider('payment_system' => 'vipay', 'traffic_percentage' => 40)
    decisions = [decision('op1', 'vipay')]
    queue = [{ 'operation_id' => 'op1', 'amount' => 100 }]
    report = Reporter.new.build(decisions, [p], queue)

    %w[distribution volume_distribution skip_reasons results projected_daily_utilization recommendations].each do |k|
      _(report.keys).must_include k
    end
    _(report.keys).must_include 'reliability'
  end
end
