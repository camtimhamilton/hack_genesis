# frozen_string_literal: true

require_relative '../test_helper'

class ConfigTest < Minitest::Test
  def test_load_default
    config = Config.load
    assert_equal 'weighted', config.active_strategy
    assert_equal 'priority', config.tie_break
    refute_empty config.weights
    assert config.overrides.key?('vipay')
  end

  def test_weights_sum_to_one
    config = Config.load
    assert_in_delta 1.0, config.weights.values.sum, 0.001
  end
end
