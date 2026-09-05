# frozen_string_literal: true

require_relative '../test_helper'

class ProviderTest < Minitest::Test
  include TestFixtures

  def test_static_readers
    p = fixture_provider('payment_system' => 'vipay', 'traffic_percentage' => 40, 'priority' => 1)
    assert_equal 'vipay', p.payment_system
    assert_equal 'active', p.status
    assert_equal 40, p.traffic_percentage
    assert_equal 1, p.priority
  end

  def test_banks_default_empty
    assert_equal [], fixture_provider.banks
  end

  def test_index_access
    p = fixture_provider('conversion_24h' => 0.87)
    assert_equal 0.87, p[:conversion_24h]
  end

  def test_apply_override
    p = fixture_provider
    p.apply_override!('volume_share_pct' => 40, 'requests_per_minute_limit' => 15)
    assert_equal 40, p.volume_share_pct
    assert_equal 15, p.requests_per_minute_limit
  end

  def test_add_approved_amount
    p = fixture_provider('daily_approved_amount' => 100)
    p.add_approved_amount(50)
    assert_equal 150, p.daily_approved_amount
  end

  def test_reserve_requisite
    p = fixture_provider('available_requisites' => 3)
    p.reserve_requisite!
    assert_equal 2, p.available_requisites
    2.times { p.reserve_requisite! }
    assert_equal 0, p.available_requisites
    p.reserve_requisite! # не уходит в минус
    assert_equal 0, p.available_requisites
  end

  def test_register_request_buckets_by_minute
    p = fixture_provider
    t1 = Time.parse('2026-07-30T09:00:10+03:00')
    t2 = Time.parse('2026-07-30T09:00:50+03:00')
    t3 = Time.parse('2026-07-30T09:01:00+03:00')
    p.register_request!(t1)
    p.register_request!(t2)
    assert_equal 2, p.requests_in_minute(t1)
    assert_equal 0, p.requests_in_minute(t3)
  end

  def test_reliability_defaults_to_conversion_24h
    p = fixture_provider('conversion_24h' => 0.91)
    assert_in_delta 0.91, p.reliability, 1e-9
    assert_equal 'conversion_24h', p.reliability_source
  end

  def test_seed_reliability_from_history
    p = fixture_provider
    p.seed_reliability!(0.75, source: 'history', observations: 40)
    assert_in_delta 0.75, p.reliability, 1e-9
    assert_in_delta 0.75, p.reliability_baseline, 1e-9
    assert_equal 'history', p.reliability_source
    assert_equal 40, p.reliability_observations
  end

  def test_seed_reliability_clamps_to_range
    p = fixture_provider
    p.seed_reliability!(1.5)
    assert_equal 1.0, p.reliability
    p.seed_reliability!(-0.2)
    assert_equal 0.0, p.reliability
  end

  def test_update_reliability_ewma_approved
    p = fixture_provider('conversion_24h' => 0.5)
    p.update_reliability!('approved')
    assert_in_delta 0.6, p.reliability, 1e-9
  end

  def test_update_reliability_ewma_rejected
    p = fixture_provider('conversion_24h' => 0.5)
    p.update_reliability!('rejected')
    assert_in_delta 0.4, p.reliability, 1e-9
  end

  def test_update_reliability_ewma_expired
    p = fixture_provider('conversion_24h' => 0.5)
    p.update_reliability!('expired')
    assert_in_delta 0.4, p.reliability, 1e-9
  end
end
