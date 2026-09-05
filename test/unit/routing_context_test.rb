# frozen_string_literal: true

require_relative '../test_helper'

class RoutingContextTest < Minitest::Test
  def test_record_and_shares
    ctx = RoutingContext.new
    ctx.record!('vipay', 300)
    ctx.record!('payflow', 100)
    assert_equal 2, ctx.total_count
    assert_equal 400.0, ctx.total_volume
    assert_equal 0.5, ctx.count_share('vipay')
    assert_in_delta 0.75, ctx.volume_share('vipay'), 1e-9
  end

  def test_zero_division_guards
    ctx = RoutingContext.new
    assert_equal 0.0, ctx.count_share('vipay')
    assert_equal 0.0, ctx.volume_share('vipay')
  end
end
