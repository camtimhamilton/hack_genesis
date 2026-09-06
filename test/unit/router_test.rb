# frozen_string_literal: true

require_relative '../test_helper'

class RouterTest < Minitest::Test
  include TestFixtures

  def test_selects_sole_eligible_provider
    vipay = fixture_provider('payment_system' => 'vipay')
    payflow = fixture_provider('payment_system' => 'payflow', 'banks' => ['sberbank'])
    router = Router.new([vipay, payflow], scorer: StubScorer.new(%w[vipay payflow]),
                        simulator: StubSimulator.new)
    d = router.route(fixture_op('bank' => 'alfa'), RoutingContext.new)
    assert_equal 'vipay', d['selected_provider']
    selected = d['attempts'].find { |a| a['provider'] == 'vipay' }
    assert_equal 'only_eligible_provider', selected['reason']
  end

  def test_selects_highest_score
    vipay = fixture_provider('payment_system' => 'vipay', 'priority' => 1)
    payflow = fixture_provider('payment_system' => 'payflow', 'priority' => 2)
    router = Router.new([vipay, payflow], scorer: StubScorer.new(%w[payflow vipay]),
                        simulator: StubSimulator.new)
    d = router.route(fixture_op, RoutingContext.new)
    assert_equal 'payflow', d['selected_provider']
    selected = d['attempts'].find { |a| a['provider'] == 'payflow' }
    assert_equal 'highest_score', selected['reason']
  end

  def test_fallback_to_next_on_rejected
    vipay = fixture_provider('payment_system' => 'vipay', 'priority' => 1)
    payflow = fixture_provider('payment_system' => 'payflow', 'priority' => 2)
    router = Router.new([vipay, payflow], scorer: StubScorer.new(%w[vipay payflow]),
                        simulator: StubSimulator.new('vipay' => 'rejected'))
    d = router.route(fixture_op, RoutingContext.new)
    assert_equal 'payflow', d['selected_provider']
    assert d['attempts'].any? { |a| a['provider'] == 'vipay' && a['decision'] == 'skipped' && a['reason'] == 'rejected_by_provider' }
  end

  def test_fallback_to_next_on_expired
    vipay = fixture_provider('payment_system' => 'vipay', 'priority' => 1)
    payflow = fixture_provider('payment_system' => 'payflow', 'priority' => 2)
    router = Router.new([vipay, payflow], scorer: StubScorer.new(%w[vipay payflow]),
                        simulator: StubSimulator.new('vipay' => 'expired'))
    d = router.route(fixture_op, RoutingContext.new)
    assert_equal 'payflow', d['selected_provider']
    assert d['attempts'].any? { |a| a['provider'] == 'vipay' && a['reason'] == 'expired_by_provider' }
  end

  def test_fallback_to_spacepayments_when_pool_empty
    vipay = fixture_provider('payment_system' => 'vipay', 'priority' => 1)
    payflow = fixture_provider('payment_system' => 'payflow', 'priority' => 2)
    space = spacepayments_provider
    router = Router.new([vipay, payflow, space], scorer: StubScorer.new(%w[vipay payflow]),
                        simulator: StubSimulator.new('vipay' => 'rejected', 'payflow' => 'rejected'))
    d = router.route(fixture_op, RoutingContext.new)
    assert_equal 'spacepayments', d['selected_provider']
    selected = d['attempts'].find { |a| a['provider'] == 'spacepayments' }
    assert_equal 'fallback_self_provider', selected['reason']
  end

  def test_stateful_update_after_approved
    vipay = fixture_provider('payment_system' => 'vipay', 'available_requisites' => 10, 'daily_approved_amount' => 0)
    router = Router.new([vipay], simulator: Simulator.new(always_approve: true))
    ctx = RoutingContext.new
    router.route(fixture_op('amount' => 1000), ctx)
    assert_equal 1000, vipay.daily_approved_amount
    assert_equal 9, vipay.available_requisites
    assert_equal 1, ctx.counts['vipay']
    assert_equal 1000.0, ctx.volumes['vipay']
  end

  def test_no_state_update_when_rejected
    vipay = fixture_provider('payment_system' => 'vipay', 'available_requisites' => 10, 'daily_approved_amount' => 0)
    router = Router.new([vipay], scorer: StubScorer.new(%w[vipay]),
                        simulator: StubSimulator.new('vipay' => 'rejected'))
    ctx = RoutingContext.new
    d = router.route(fixture_op('amount' => 1000), ctx)
    assert_nil d['selected_provider']
    assert_equal 0, vipay.daily_approved_amount
    assert_equal 10, vipay.available_requisites
    assert_equal 0, ctx.total_count
  end

  def test_attempts_contain_skip_reason
    vipay = fixture_provider('payment_system' => 'vipay', 'banks' => ['sberbank'])
    payflow = fixture_provider('payment_system' => 'payflow', 'priority' => 2)
    router = Router.new([vipay, payflow], scorer: StubScorer.new(%w[vipay payflow]),
                        simulator: StubSimulator.new)
    d = router.route(fixture_op('bank' => 'alfa'), RoutingContext.new)
    skipped = d['attempts'].find { |a| a['provider'] == 'vipay' && a['decision'] == 'skipped' }
    assert_equal 'bank_not_in_list', skipped['reason']
  end

  def test_reliability_increases_after_approved
    vipay = fixture_provider('payment_system' => 'vipay', 'conversion_24h' => 0.5)
    router = Router.new([vipay], simulator: Simulator.new(always_approve: true))
    router.route(fixture_op, RoutingContext.new)
    assert_operator vipay.reliability, :>, 0.5
  end

  def test_reliability_decreases_after_rejected_attempt
    vipay = fixture_provider('payment_system' => 'vipay', 'conversion_24h' => 0.5)
    payflow = fixture_provider('payment_system' => 'payflow', 'priority' => 2, 'conversion_24h' => 0.5)
    router = Router.new([vipay, payflow], scorer: StubScorer.new(%w[vipay payflow]),
                        simulator: StubSimulator.new('vipay' => 'rejected'))
    router.route(fixture_op, RoutingContext.new)
    assert_operator vipay.reliability, :<, 0.5
    assert_operator payflow.reliability, :>, 0.5
  end

  def test_empty_pool_marks_no_eligible_provider
    vipay = fixture_provider('payment_system' => 'vipay', 'banks' => ['sberbank'])
    space = spacepayments_provider.apply_override!('status' => 'inactive')
    router = Router.new([vipay, space], scorer: StubScorer.new(%w[vipay]),
                        simulator: StubSimulator.new)
    d = router.route(fixture_op('bank' => 'alfa'), RoutingContext.new)
    assert_nil d['selected_provider']
    assert_equal 'no_eligible_provider', d['reason']
  end

  def test_in_progress_reserved_during_attempt
    p = fixture_provider('payment_system' => 'vipay', 'in_progress_count' => 2, 'in_progress_amount' => 100)
    observed = []
    sim = Object.new
    sim.define_singleton_method(:result) do |provider, _op = nil|
      observed << [provider.in_progress_count, provider.in_progress_amount]
      'approved'
    end
    sim.define_singleton_method(:latency) { |_p| 0 }
    router = Router.new([p], simulator: sim)
    router.route(fixture_op('amount' => 500), RoutingContext.new)
    assert_equal [[3, 600]], observed
    assert_equal 2, p.in_progress_count
    assert_equal 100, p.in_progress_amount
  end
end
