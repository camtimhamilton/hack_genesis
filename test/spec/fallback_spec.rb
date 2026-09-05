# frozen_string_literal: true

require_relative '../test_helper'

describe 'Fallback (spec.md §5.4)' do
  include TestFixtures

  it 'при отказе переходит к следующему допустимому' do
    vipay = fixture_provider('payment_system' => 'vipay', 'priority' => 1)
    payflow = fixture_provider('payment_system' => 'payflow', 'priority' => 2)
    router = Router.new([vipay, payflow], scorer: StubScorer.new(%w[vipay payflow]),
                        simulator: StubSimulator.new('vipay' => 'rejected'))
    d = router.route(fixture_op, RoutingContext.new)
    _(d['selected_provider']).must_equal 'payflow'
    pairs = d['attempts'].map { |a| [a['provider'], a['decision']] }
    _(pairs).must_include ['vipay', 'skipped']
    _(pairs).must_include ['payflow', 'selected']
  end

  it 'при пустом пуле внешних провайдеров выбирает spacepayments' do
    vipay = fixture_provider('payment_system' => 'vipay', 'priority' => 1)
    payflow = fixture_provider('payment_system' => 'payflow', 'priority' => 2)
    space = spacepayments_provider
    router = Router.new([vipay, payflow, space], scorer: StubScorer.new(%w[vipay payflow]),
                        simulator: StubSimulator.new('vipay' => 'rejected', 'payflow' => 'rejected'))
    d = router.route(fixture_op, RoutingContext.new)
    _(d['selected_provider']).must_equal 'spacepayments'
  end

  it 'фиксирует последовательность попыток в attempts' do
    vipay = fixture_provider('payment_system' => 'vipay', 'priority' => 1)
    payflow = fixture_provider('payment_system' => 'payflow', 'priority' => 2)
    router = Router.new([vipay, payflow], scorer: StubScorer.new(%w[vipay payflow]),
                        simulator: StubSimulator.new('vipay' => 'rejected'))
    d = router.route(fixture_op, RoutingContext.new)
    order = d['attempts'].map { |a| a['provider'] }
    _(order.index('vipay')).must_be :<, order.index('payflow')
  end
end
