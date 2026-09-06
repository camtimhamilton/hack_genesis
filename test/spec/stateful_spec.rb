# frozen_string_literal: true

require_relative '../test_helper'

describe 'Stateful-обновление (spec.md §5.5)' do
  include TestFixtures

  it 'увеличивает daily_approved_amount после approved' do
    p = fixture_provider('payment_system' => 'vipay', 'daily_approved_amount' => 0)
    router = Router.new([p], simulator: Simulator.new(always_approve: true))
    router.route(fixture_op('amount' => 1500), RoutingContext.new)
    _(p.daily_approved_amount).must_equal 1500
  end

  it 'не изменяет available_requisites после approved (пул освобождается сразу)' do
    p = fixture_provider('payment_system' => 'vipay', 'available_requisites' => 5)
    router = Router.new([p], simulator: Simulator.new(always_approve: true))
    router.route(fixture_op, RoutingContext.new)
    _(p.available_requisites).must_equal 5
  end

  it 'ведёт счётчик интенсивности (requests_per_minute)' do
    p = fixture_provider('payment_system' => 'vipay')
    router = Router.new([p], simulator: Simulator.new(always_approve: true))
    op = fixture_op
    router.route(op, RoutingContext.new)
    _(p.requests_in_minute(Time.parse(op['created_at']))).must_equal 1
  end

  it 'накапливает факт-доли count/volume' do
    p = fixture_provider('payment_system' => 'vipay')
    router = Router.new([p], simulator: Simulator.new(always_approve: true))
    ctx = RoutingContext.new
    router.route(fixture_op('amount' => 2000), ctx)
    _(ctx.count_share('vipay')).must_equal 1.0
    _(ctx.volume_share('vipay')).must_equal 1.0
    _(ctx.total_count).must_equal 1
    _(ctx.total_volume).must_equal 2000.0
  end

  it 'не обновляет метрики при rejected' do
    p = fixture_provider('payment_system' => 'vipay', 'daily_approved_amount' => 0, 'available_requisites' => 5)
    router = Router.new([p], scorer: StubScorer.new(%w[vipay]),
                        simulator: StubSimulator.new('vipay' => 'rejected'))
    ctx = RoutingContext.new
    router.route(fixture_op('amount' => 2000), ctx)
    _(p.daily_approved_amount).must_equal 0
    _(p.available_requisites).must_equal 5
    _(ctx.total_count).must_equal 0
  end
end
