# frozen_string_literal: true

require_relative '../test_helper'

class ScorerTest < Minitest::Test
  include TestFixtures

  def setup
    @ctx = RoutingContext.new
    @op = fixture_op
    @vipay = fixture_provider('payment_system' => 'vipay', 'priority' => 1, 'conversion_24h' => 0.9)
    @payflow = fixture_provider('payment_system' => 'payflow', 'priority' => 2, 'conversion_24h' => 0.5)
  end

  def test_rank_descending_by_score
    scorer = Scorer.new(weights: { 'conversion' => 1.0 })
    ranked = scorer.rank([@payflow, @vipay], @op, @ctx)
    assert_equal 'vipay', ranked.first.first.payment_system
    assert_operator ranked.first.last, :>, ranked.last.last
  end

  def test_tie_break_by_priority
    a = fixture_provider('payment_system' => 'a', 'priority' => 3, 'conversion_24h' => 0.5)
    b = fixture_provider('payment_system' => 'b', 'priority' => 1, 'conversion_24h' => 0.5)
    scorer = Scorer.new(weights: { 'conversion' => 1.0 })
    ranked = scorer.rank([a, b], @op, @ctx)
    assert_equal 'b', ranked.first.first.payment_system
  end

  def test_score_for_is_weighted_sum
    scorer = Scorer.new(weights: { 'conversion' => 0.5, 'cascade' => 0.5 })
    expected = (0.5 * 0.9) + (0.5 * 1.0)
    assert_in_delta expected, scorer.score_for(@vipay, @op, @ctx), 1e-9
  end

  def test_unknown_weight_is_zero
    scorer = Scorer.new(weights: {})
    assert_equal 0.0, scorer.score_for(@vipay, @op, @ctx)
  end

  def test_score_breakdown_structure
    scorer = Scorer.new(weights: { 'conversion' => 0.5 })
    breakdown = scorer.score_breakdown(@vipay, @op, @ctx)
    assert_in_delta 0.45, breakdown['total'], 1e-9
    factor = breakdown['factors']['conversion']
    assert_in_delta 0.9, factor['raw'], 1e-9
    assert_equal 0.5, factor['weight']
    assert_in_delta 0.45, factor['weighted'], 1e-9
  end

  def test_explain_mentions_score
    scorer = Scorer.new(weights: { 'conversion' => 1.0 })
    assert_match(/score=/, scorer.explain(@vipay, @op, @ctx))
  end
end
