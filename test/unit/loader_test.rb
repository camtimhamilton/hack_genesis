# frozen_string_literal: true

require_relative '../test_helper'

class LoaderTest < Minitest::Test
  def test_loads_providers
    providers = Loader.new.providers
    refute_empty providers
    assert providers.all? { |p| p.is_a?(Provider) }
    names = providers.map(&:payment_system)
    assert_includes names, 'vipay'
    assert_includes names, 'spacepayments'
  end

  def test_loads_queue
    queue = Loader.new.queue
    assert_equal 10, queue.size
    assert queue.all? { |op| op.key?('operation_id') }
  end

  def test_loads_history
    assert_operator Loader.new.history.size, :>, 0
  end

  def test_loads_reference
    assert Loader.new.reference.key?('deterministic_cases')
  end

  def test_missing_file_raises_data_error
    loader = Loader.new(data_dir: File.join(__dir__, 'does_not_exist'))
    assert_raises(Loader::DataError) { loader.providers }
  end

  def test_seeds_reliability_from_history
    providers = Loader.new.providers
    by_name = providers.to_h { |p| [p.payment_system, p] }

    %w[vipay payflow quickpay].each do |name|
      p = by_name[name]
      assert_equal 'history', p.reliability_source
      assert_operator p.reliability, :>=, 0.0
      assert_operator p.reliability, :<=, 1.0
      assert_operator p.reliability_observations, :>, 0
    end

    space = by_name['spacepayments']
    assert_equal 'conversion_24h', space.reliability_source
    assert_in_delta 0.95, space.reliability, 1e-9
  end
end
