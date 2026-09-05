# frozen_string_literal: true

require_relative '../test_helper'

# Hard-constraints (spec.md §5.1): каждая из 9 проверок + rate-limit.
class HardFilterTest < Minitest::Test
  include TestFixtures

  def setup
    @filter = HardFilter.new
    @op = fixture_op
  end

  def test_eligible_by_default
    ok, reason, details = @filter.eligible?(@op, fixture_provider)
    assert ok
    assert_nil reason
    assert_nil details
  end

  def test_inactive_status
    ok, reason, = @filter.eligible?(@op, fixture_provider('status' => 'paused'))
    refute ok
    assert_equal 'inactive_provider', reason
  end

  def test_zero_traffic_excludes_external
    ok, reason, = @filter.eligible?(@op, fixture_provider('traffic_percentage' => 0))
    refute ok
    assert_equal 'inactive_provider', reason
  end

  def test_zero_traffic_allowed_for_fallback
    ok, = @filter.eligible?(@op, spacepayments_provider)
    assert ok
  end

  def test_amount_below_minimum
    ok, reason, = @filter.eligible?(@op, fixture_provider('limit_amount_min' => 5000))
    refute ok
    assert_equal 'amount_below_minimum', reason
  end

  def test_amount_exceeds_max
    ok, reason, = @filter.eligible?(@op, fixture_provider('limit_amount_max' => 500))
    refute ok
    assert_equal 'amount_exceeds_limit', reason
  end

  def test_daily_limit_exceeded
    p = fixture_provider('daily_amount_limit' => 1000, 'daily_approved_amount' => 500)
    ok, reason, = @filter.eligible?(@op, p)
    refute ok
    assert_equal 'daily_limit_exceeded', reason
  end

  def test_in_progress_count_exceeded
    p = fixture_provider('in_progress_count_limit' => 1, 'in_progress_count' => 1)
    ok, reason, = @filter.eligible?(@op, p)
    refute ok
    assert_equal 'in_progress_limit_exceeded', reason
  end

  def test_in_progress_amount_exceeded
    p = fixture_provider('in_progress_amount_limit' => 1000, 'in_progress_amount' => 500)
    ok, reason, = @filter.eligible?(@op, p)
    refute ok
    assert_equal 'in_progress_limit_exceeded', reason
  end

  def test_no_available_requisites
    ok, reason, = @filter.eligible?(@op, fixture_provider('available_requisites' => 0))
    refute ok
    assert_equal 'no_available_requisites', reason
  end

  def test_negative_margin
    p = fixture_provider('provider_margin_pct' => 2.0, 'merchant_margin_pct' => 1.5)
    ok, reason, = @filter.eligible?(@op, p)
    refute ok
    assert_equal 'negative_margin', reason
  end

  def test_negative_margin_allowed_when_agreement
    p = fixture_provider('provider_margin_pct' => 2.0, 'merchant_margin_pct' => 1.5, 'allow_negative_agreement' => true)
    ok, = @filter.eligible?(@op, p)
    assert ok
  end

  def test_bank_not_in_list
    p = fixture_provider('banks' => ['sberbank'])
    ok, reason, = @filter.eligible?(fixture_op('bank' => 'alfa'), p)
    refute ok
    assert_equal 'bank_not_in_list', reason
  end

  def test_bank_in_exclude_list
    p = fixture_provider('banks' => ['sberbank'], 'exclude_banks' => true)
    ok, reason, = @filter.eligible?(fixture_op('bank' => 'sberbank'), p)
    refute ok
    assert_equal 'bank_not_in_list', reason
  end

  def test_empty_banks_no_filter
    ok, = @filter.eligible?(fixture_op('bank' => 'gazprombank'), fixture_provider('banks' => []))
    assert ok
  end

  def test_rate_limit_exceeded
    p = fixture_provider('requests_per_minute_limit' => 2)
    time = Time.parse(@op['created_at'])
    2.times { p.register_request!(time) }
    ok, reason, = @filter.eligible?(@op, p)
    refute ok
    assert_equal 'rate_limit_exceeded', reason
  end

  def test_null_limits_mean_unlimited
    ok, = @filter.eligible?(@op, fixture_provider)
    assert ok
  end
end
