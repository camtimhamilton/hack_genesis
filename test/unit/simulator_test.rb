# frozen_string_literal: true

require_relative '../test_helper'

class SimulatorTest < Minitest::Test
  include TestFixtures

  def test_always_approve
    assert_equal 'approved', Simulator.new(always_approve: true).result(fixture_provider)
  end

  def test_seeded_deterministic
    a = Simulator.new(seed: 42)
    b = Simulator.new(seed: 42)
    provider = fixture_provider('conversion_24h' => 0.5)
    20.times do
      assert_equal a.result(provider), b.result(provider)
    end
  end

  def test_latency
    assert_equal 30, Simulator.new.latency(fixture_provider('avg_latency_sec' => 30))
  end
end
