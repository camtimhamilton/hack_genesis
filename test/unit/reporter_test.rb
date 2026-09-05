# frozen_string_literal: true

require_relative '../test_helper'

class ReporterTest < Minitest::Test
  include TestFixtures

  def setup
    @vipay = fixture_provider('payment_system' => 'vipay', 'traffic_percentage' => 40, 'volume_share_pct' => 50)
    @payflow = fixture_provider('payment_system' => 'payflow', 'traffic_percentage' => 35, 'volume_share_pct' => 30)
    @quickpay = fixture_provider('payment_system' => 'quickpay', 'traffic_percentage' => 25, 'volume_share_pct' => 20)
    @providers = [@vipay, @payflow, @quickpay]
  end

  def test_distribution
    decisions = [
      decision('op1', 'vipay'),
      decision('op2', 'vipay'),
      decision('op3', 'payflow'),
      decision('op4', 'quickpay')
    ]
    queue = decisions.map { |d| { 'operation_id' => d['operation_id'], 'amount' => 100 } }
    report = Reporter.new.build(decisions, @providers, queue)
    assert_equal 4, report['total_operations']
    assert_equal 2, report['distribution']['vipay']['count']
    assert_equal 50.0, report['distribution']['vipay']['share_pct']
    assert_equal 40, report['distribution']['vipay']['target_pct']
    assert_equal 10.0, report['distribution']['vipay']['deviation_pp']
  end

  def test_volume_distribution
    decisions = [decision('op1', 'vipay'), decision('op2', 'payflow')]
    queue = [
      { 'operation_id' => 'op1', 'amount' => 300 },
      { 'operation_id' => 'op2', 'amount' => 100 }
    ]
    report = Reporter.new.build(decisions, @providers, queue)
    assert_equal 300, report['volume_distribution']['vipay']['amount']
    assert_equal 75.0, report['volume_distribution']['vipay']['share_pct']
    assert_equal 50, report['volume_distribution']['vipay']['target_pct']
  end

  def test_skip_reasons
    decisions = [
      decision('op1', 'vipay', attempts: [
                 { 'provider' => 'payflow', 'decision' => 'skipped', 'reason' => 'bank_not_in_list' },
                 { 'provider' => 'quickpay', 'decision' => 'skipped', 'reason' => 'amount_exceeds_limit' }
               ])
    ]
    queue = decisions.map { |d| { 'operation_id' => d['operation_id'], 'amount' => 100 } }
    report = Reporter.new.build(decisions, @providers, queue)
    assert_equal 1, report['skip_reasons']['bank_not_in_list']
    assert_equal 1, report['skip_reasons']['amount_exceeds_limit']
  end

  def test_results
    decisions = [
      decision('op1', 'vipay', simulated_result: 'approved'),
      decision('op2', 'payflow', simulated_result: 'rejected'),
      decision('op3', 'quickpay', simulated_result: 'expired'),
      decision('op4', 'vipay', simulated_result: 'approved')
    ]
    queue = decisions.map { |d| { 'operation_id' => d['operation_id'], 'amount' => 100 } }
    report = Reporter.new.build(decisions, @providers, queue)
    assert_equal 2, report['results']['approved']
    assert_equal 1, report['results']['rejected']
    assert_equal 1, report['results']['expired']
    assert_equal 50.0, report['results']['approval_rate_pct']
  end

  def test_utilization
    p = fixture_provider('payment_system' => 'vipay', 'daily_amount_limit' => 1000, 'daily_approved_amount' => 500)
    decisions = [decision('op1', 'vipay')]
    queue = [{ 'operation_id' => 'op1', 'amount' => 100 }]
    report = Reporter.new.build(decisions, [p], queue)
    util = report['projected_daily_utilization']['vipay']
    assert_equal 500, util['used']
    assert_equal 1000, util['limit']
    assert_equal 50.0, util['utilization_pct']
  end

  def test_recommendation_for_near_limit
    p = fixture_provider('payment_system' => 'payflow', 'traffic_percentage' => 35,
                         'daily_amount_limit' => 1_000_000, 'daily_approved_amount' => 950_000)
    decisions = [decision('op1', 'payflow')]
    queue = [{ 'operation_id' => 'op1', 'amount' => 100 }]
    report = Reporter.new.build(decisions, [p], queue)
    refute_empty report['recommendations']
    assert report['recommendations'].any? { |r| r.include?('daily_amount_limit') }
  end

  def test_recommendation_for_no_requisites
    p = fixture_provider('payment_system' => 'payflow', 'traffic_percentage' => 35, 'available_requisites' => 0)
    decisions = [decision('op1', 'payflow')]
    queue = [{ 'operation_id' => 'op1', 'amount' => 100 }]
    report = Reporter.new.build(decisions, [p], queue)
    assert report['recommendations'].any? { |r| r.include?('available_requisites') }
  end

  def test_unachieved_goals
    payflow = fixture_provider('payment_system' => 'payflow', 'traffic_percentage' => 35, 'banks' => ['sberbank'])
    vipay = fixture_provider('payment_system' => 'vipay')
    decisions = [
      decision('op1', 'vipay', attempts: [
                 { 'provider' => 'payflow', 'decision' => 'skipped', 'reason' => 'bank_not_in_list' }
               ]),
      decision('op2', 'vipay', attempts: [
                 { 'provider' => 'payflow', 'decision' => 'skipped', 'reason' => 'bank_not_in_list' }
               ])
    ]
    queue = decisions.map { |d| { 'operation_id' => d['operation_id'], 'amount' => 100 } }
    report = Reporter.new.build(decisions, [payflow, vipay], queue)
    goals = report['unachieved_goals'].map { |g| g['provider'] }
    assert_includes goals, 'payflow'
  end

  def test_reliability_section
    p = fixture_provider('payment_system' => 'vipay', 'conversion_24h' => 0.9)
    p.seed_reliability!(0.8, source: 'history', observations: 40)
    decisions = [decision('op1', 'vipay')]
    queue = [{ 'operation_id' => 'op1', 'amount' => 100 }]
    report = Reporter.new.build(decisions, [p], queue)
    assert report.key?('reliability')
    sec = report['reliability']['vipay']
    assert_in_delta 0.8, sec['value'], 1e-9
    assert_in_delta 0.8, sec['baseline'], 1e-9
    assert_equal 'history', sec['source']
    assert_equal 40, sec['observations']
  end
end
