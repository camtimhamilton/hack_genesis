# frozen_string_literal: true

require_relative '../test_helper'
require 'strategies/base'
require 'strategies/count_share'
require 'strategies/volume_share'
require 'strategies/cascade'
require 'strategies/conversion'
require 'strategies/amount_range'
require 'strategies/rate_limit'
require 'strategies/turnover'
require 'strategies/reliability'

class BaseStrategyTest < Minitest::Test
  def test_score_raises_not_implemented
    assert_raises(NotImplementedError) { BaseStrategy.new.score(nil, nil, nil) }
  end
end

class CountShareStrategyTest < Minitest::Test
  include TestFixtures

  def test_key
    assert_equal 'count_share', CountShareStrategy.new.key
  end

  def test_deficit_boosts_score
    ctx = RoutingContext.new
    ctx.record!('payflow', 1000)
    p = fixture_provider('payment_system' => 'vipay', 'traffic_percentage' => 40)
    assert_operator CountShareStrategy.new.score(p, fixture_op, ctx), :>, 0.5
  end

  def test_zero_target_returns_neutral
    p = fixture_provider('traffic_percentage' => 0)
    assert_equal 0.5, CountShareStrategy.new.score(p, fixture_op, RoutingContext.new)
  end
end

class VolumeShareStrategyTest < Minitest::Test
  include TestFixtures

  def test_key
    assert_equal 'volume_share', VolumeShareStrategy.new.key
  end

  def test_deficit_boosts_score
    ctx = RoutingContext.new
    ctx.record!('payflow', 500)
    p = fixture_provider('payment_system' => 'vipay', 'volume_share_pct' => 60)
    assert_operator VolumeShareStrategy.new.score(p, fixture_op, ctx), :>, 0.5
  end

  def test_zero_target_returns_neutral
    p = fixture_provider('volume_share_pct' => 0)
    assert_equal 0.5, VolumeShareStrategy.new.score(p, fixture_op, RoutingContext.new)
  end
end

class CascadeStrategyTest < Minitest::Test
  include TestFixtures

  def test_key
    assert_equal 'cascade', CascadeStrategy.new.key
  end

  def test_inverse_priority
    p = fixture_provider('priority' => 2)
    assert_equal 0.5, CascadeStrategy.new.score(p, fixture_op, RoutingContext.new)
  end

  def test_nonpositive_priority_is_zero
    p = fixture_provider('priority' => 0)
    assert_equal 0.0, CascadeStrategy.new.score(p, fixture_op, RoutingContext.new)
  end
end

class ConversionStrategyTest < Minitest::Test
  include TestFixtures

  def test_key
    assert_equal 'conversion', ConversionStrategy.new.key
  end

  def test_clamps_conversion
    p = fixture_provider('conversion_24h' => 0.87)
    assert_in_delta 0.87, ConversionStrategy.new.score(p, fixture_op, RoutingContext.new), 1e-9
  end

  def test_clamps_above_one
    p = fixture_provider('conversion_24h' => 1.5)
    assert_equal 1.0, ConversionStrategy.new.score(p, fixture_op, RoutingContext.new)
  end
end

class AmountRangeStrategyTest < Minitest::Test
  include TestFixtures

  def test_key
    assert_equal 'amount_range', AmountRangeStrategy.new.key
  end

  def test_in_band
    p = fixture_provider('amount_range_min' => 500, 'amount_range_max' => 5000)
    assert_equal 0.6, AmountRangeStrategy.new.score(p, fixture_op('amount' => 1000), RoutingContext.new)
  end

  def test_out_of_band
    p = fixture_provider('amount_range_min' => 500, 'amount_range_max' => 5000)
    assert_equal 0.4, AmountRangeStrategy.new.score(p, fixture_op('amount' => 10_000), RoutingContext.new)
  end

  def test_no_range_neutral
    assert_equal 0.5, AmountRangeStrategy.new.score(fixture_provider, fixture_op, RoutingContext.new)
  end
end

class RateLimitStrategyTest < Minitest::Test
  include TestFixtures

  def test_key
    assert_equal 'rate_limit', RateLimitStrategy.new.key
  end

  def test_no_limit_neutral
    assert_equal 0.5, RateLimitStrategy.new.score(fixture_provider, fixture_op, RoutingContext.new)
  end

  def test_usage_reduces_score
    p = fixture_provider('requests_per_minute_limit' => 10)
    p.register_request!(Time.parse(fixture_op['created_at']))
    assert_in_delta 0.9, RateLimitStrategy.new.score(p, fixture_op, RoutingContext.new), 1e-9
  end
end

class TurnoverStrategyTest < Minitest::Test
  include TestFixtures

  def test_key
    assert_equal 'turnover', TurnoverStrategy.new.key
  end

  def test_below_min_boosts
    p = fixture_provider('daily_turnover_min' => 1_000_000, 'daily_approved_amount' => 0)
    assert_equal 1.0, TurnoverStrategy.new.score(p, fixture_op, RoutingContext.new)
  end

  def test_at_or_above_max_penalizes
    p = fixture_provider('daily_turnover_max' => 1_000_000, 'daily_approved_amount' => 1_000_000)
    assert_equal 0.0, TurnoverStrategy.new.score(p, fixture_op, RoutingContext.new)
  end

  def test_no_obligation_neutral
    assert_equal 0.5, TurnoverStrategy.new.score(fixture_provider, fixture_op, RoutingContext.new)
  end
end

class ReliabilityStrategyTest < Minitest::Test
  include TestFixtures

  def test_key
    assert_equal 'reliability', ReliabilityStrategy.new.key
  end

  def test_clamps_reliability
    p = fixture_provider('conversion_24h' => 0.83)
    assert_in_delta 0.83, ReliabilityStrategy.new.score(p, fixture_op, RoutingContext.new), 1e-9
  end

  def test_clamps_above_one
    p = fixture_provider('conversion_24h' => 1.5)
    assert_equal 1.0, ReliabilityStrategy.new.score(p, fixture_op, RoutingContext.new)
  end
end
