# frozen_string_literal: true

require_relative '../test_helper'

class HtmlReporterTest < Minitest::Test
  def sample_report(overrides = {})
    {
      'period' => '2026-07-30',
      'gateway' => 'RUB_SBP_WITHDRAW',
      'merchant' => 'alpha_market',
      'strategy' => 'weighted',
      'total_operations' => 4,
      'distribution' => {
        'vipay' => { 'count' => 2, 'share_pct' => 50.0, 'target_pct' => 40.0, 'deviation_pp' => 10.0 },
        'payflow' => { 'count' => 2, 'share_pct' => 50.0, 'target_pct' => 35.0, 'deviation_pp' => 15.0 }
      },
      'volume_distribution' => {
        'vipay' => { 'amount' => 300.0, 'share_pct' => 75.0, 'target_pct' => 40.0, 'deviation_pp' => 35.0 },
        'payflow' => { 'amount' => 100.0, 'share_pct' => 25.0, 'target_pct' => 35.0, 'deviation_pp' => -10.0 }
      },
      'skip_reasons' => { 'bank_not_in_list' => 3, 'amount_exceeds_limit' => 1 },
      'results' => {
        'approved' => 4, 'rejected' => 0, 'expired' => 0, 'approval_rate_pct' => 100.0,
        'by_provider' => { 'vipay' => { 'approved' => 2 }, 'payflow' => { 'approved' => 2 } }
      },
      'reliability' => {
        'vipay' => { 'value' => 0.91, 'baseline' => 0.78, 'source' => 'history', 'observations' => 41 }
      },
      'projected_daily_utilization' => {
        'vipay' => {
          'used' => 500, 'limit' => 1000, 'utilization_pct' => 50.0,
          'in_progress_count' => 2, 'in_progress_count_limit' => 10,
          'in_progress_amount' => 100, 'in_progress_amount_limit' => 500,
          'available_requisites' => 8
        }
      },
      'recommendations' => ['vipay: дневной лимит почти исчерпан — увеличить daily_amount_limit'],
      'unachieved_goals' => []
    }.merge(overrides)
  end

  def render(report = sample_report)
    HtmlReporter.new.render(report)
  end

  def test_render_produces_valid_html5_skeleton
    html = render
    assert_match(/<!DOCTYPE html>/, html)
    assert_match(/<html lang="ru">/, html)
    assert_match(%r{</html>}, html)
    assert_match(/<head>/, html)
    assert_match(/<title>/, html)
    assert_match(/<body>/, html)
    assert_match(/<style>/, html)
    assert_match(/<svg /, html)
    assert_match(/<table>/, html)
    assert_match(/<script>/, html)
  end

  def test_no_external_resources
    html = render
    refute_match(%r{https?://}, html)
    refute_match(%r{//cdn}, html)
    refute_match(/<script[^>]+src=/, html)
    refute_match(/<link[^>]+stylesheet/, html)
    refute_match(/@import\s+url\(/, html)
  end

  def test_includes_kpi_and_content
    html = render
    assert_match(/Ключевые показатели/, html)
    assert_match(/vipay/, html)
    assert_match(/payflow/, html)
    assert_match(/bank_not_in_list/, html)
    assert_match(/Рекомендации/, html)
    assert_match(/daily_amount_limit/, html)
  end

  def test_escapes_hostile_content
    report = sample_report('recommendations' => ['<script>alert(1)</script>'])
    html = render(report)
    refute_match(/<script>alert\(1\)<\/script>/, html)
    assert_match(/&lt;script&gt;alert\(1\)&lt;\/script&gt;/, html)
  end

  def test_escapes_ampersand
    report = sample_report('merchant' => 'a & b <corp>')
    html = render(report)
    assert_match(/a &amp; b &lt;corp&gt;/, html)
  end

  def test_handles_empty_sections
    report = sample_report(
      'distribution' => {},
      'volume_distribution' => {},
      'skip_reasons' => {},
      'reliability' => {},
      'projected_daily_utilization' => {},
      'results' => { 'approved' => 0, 'rejected' => 0, 'expired' => 0, 'approval_rate_pct' => 0.0 },
      'recommendations' => [],
      'unachieved_goals' => []
    )
    html = render(report)
    assert_match(/<!DOCTYPE html>/, html)
    refute_match(/<table>/, html)
  end

  def test_renders_unachieved_goals
    report = sample_report('unachieved_goals' => [
                             { 'provider' => 'payflow', 'target_pct' => 35.0, 'eligible_operations' => 1,
                               'total_operations' => 4, 'achievable_share_pct' => 25.0,
                               'skip_reasons' => { 'bank_not_in_list' => 3 } }
                           ])
    html = render(report)
    assert_match(/Недостижимые цели/, html)
    assert_match(/bank_not_in_list/, html)
  end
end
