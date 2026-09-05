# frozen_string_literal: true

require_relative '../test_helper'

describe 'Словарь reason (spec.md §6.1)' do
  include TestFixtures

  HARD_REASONS = %w[
    inactive_provider amount_exceeds_limit amount_below_minimum daily_limit_exceeded
    in_progress_limit_exceeded no_available_requisites negative_margin bank_not_in_list
    rate_limit_exceeded
  ].freeze

  SELECT_REASONS = %w[highest_score only_eligible_provider fallback_self_provider].freeze

  RUNTIME_REASONS = %w[rejected_by_provider expired_by_provider].freeze

  it 'использует в attempts только коды из словаря' do
    vipay = fixture_provider('payment_system' => 'vipay')
    payflow = fixture_provider('payment_system' => 'payflow', 'priority' => 2)
    router = Router.new([vipay, payflow], scorer: StubScorer.new(%w[vipay payflow]),
                        simulator: StubSimulator.new('vipay' => 'rejected'))
    d = router.route(fixture_op, RoutingContext.new)
    known = HARD_REASONS + SELECT_REASONS + RUNTIME_REASONS
    d['attempts'].each { |a| assert_includes known, a['reason'] }
  end

  it 'помечает выбранного провайдера reason из SELECT_REASONS' do
    vipay = fixture_provider('payment_system' => 'vipay')
    router = Router.new([vipay], simulator: Simulator.new(always_approve: true))
    d = router.route(fixture_op, RoutingContext.new)
    selected = d['attempts'].find { |a| a['decision'] == 'selected' }
    _(SELECT_REASONS).must_include selected['reason']
  end

  it 'при отказе использует rejected_by_provider, при таймауте — expired_by_provider' do
    vipay = fixture_provider('payment_system' => 'vipay', 'priority' => 1)
    payflow = fixture_provider('payment_system' => 'payflow', 'priority' => 2)

    d_rej = Router.new([vipay, payflow], scorer: StubScorer.new(%w[vipay payflow]),
                       simulator: StubSimulator.new('vipay' => 'rejected')).route(fixture_op, RoutingContext.new)
    _(d_rej['attempts'].map { |a| a['reason'] }).must_include 'rejected_by_provider'

    d_exp = Router.new([vipay, payflow], scorer: StubScorer.new(%w[vipay payflow]),
                       simulator: StubSimulator.new('vipay' => 'expired')).route(fixture_op, RoutingContext.new)
    _(d_exp['attempts'].map { |a| a['reason'] }).must_include 'expired_by_provider'
  end

  it 'при пустом пуле использует fallback_self_provider' do
    vipay = fixture_provider('payment_system' => 'vipay', 'priority' => 1)
    space = spacepayments_provider
    router = Router.new([vipay, space], scorer: StubScorer.new(%w[vipay]),
                        simulator: StubSimulator.new('vipay' => 'rejected'))
    d = router.route(fixture_op, RoutingContext.new)
    _(d['attempts'].map { |a| a['reason'] }).must_include 'fallback_self_provider'
  end
end
