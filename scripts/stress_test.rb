# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'json'
require 'time'
require 'loader'
require 'config'
require 'router'
require 'scorer'
require 'simulator'
require 'reporter'

N = 10_000
DAILY_LIMIT_SCALE = 39
REQUISITES_POOL = 50_000

BANKS = %w[sberbank alfa tinkoff vtb gazprombank raiffeisen sberbank alfa tinkoff vtb].freeze

def random_amount(rng)
  roll = rng.rand
  if roll < 0.55
    rng.rand(500..50_000)
  elsif roll < 0.85
    rng.rand(50_001..100_000)
  else
    rng.rand(100_001..200_000)
  end
end

def random_operations(n, rng)
  base = Time.parse('2026-07-30T09:00:00+03:00')
  Array.new(n) do |i|
    {
      'operation_id' => format('op_%05d', i + 1),
      'created_at' => (base + (i * 30)).iso8601,
      'amount' => random_amount(rng),
      'bank' => BANKS[rng.rand(BANKS.size)]
    }
  end
end

def scaled_providers(raw)
  raw.map do |p|
    clean = p.dup
    clean['daily_approved_amount'] = 0
    clean['available_requisites'] = REQUISITES_POOL
    clean['daily_amount_limit'] *= DAILY_LIMIT_SCALE if clean['daily_amount_limit']
    Provider.new(clean)
  end
end

def external_providers(providers)
  providers.reject { |p| p.payment_system == 'spacepayments' }
end

def print_convergence(decisions, providers, queue)
  total = decisions.size
  amounts = queue.each_with_object({}) { |op, a| a[op['operation_id']] = op['amount'].to_f }

  counts = decisions.group_by { |d| d['selected_provider'] }.transform_values(&:size)
  vol = Hash.new(0.0)
  decisions.each { |d| vol[d['selected_provider']] += amounts.fetch(d['operation_id'], 0.0) }
  total_vol = vol.values.sum

  puts
  puts '--- Схождение долей (count) ---'
  puts format('%-12s %9s %9s %9s', 'provider', 'target', 'actual', 'dev')
  external_providers(providers).each do |p|
    name = p.payment_system
    share = total.zero? ? 0.0 : counts.fetch(name, 0) * 100.0 / total
    target = p.traffic_percentage.to_f
    puts format('%-12s %7.0f%% %7.1f%% %+6.1fpp', name, target, share, share - target)
  end

  puts
  puts '--- Схождение долей (volume) ---'
  puts format('%-12s %9s %9s %9s', 'provider', 'target', 'actual', 'dev')
  external_providers(providers).each do |p|
    name = p.payment_system
    vshare = total_vol.zero? ? 0.0 : vol[name] * 100.0 / total_vol
    target = (p.volume_share_pct || 0).to_f
    puts format('%-12s %7.0f%% %7.1f%% %+6.1fpp', name, target, vshare, vshare - target)
  end
end

def print_cascades(decisions)
  runtime = %w[rejected_by_provider expired_by_provider]
  fallbacks = decisions.count { |d| d['selected_provider'] == 'spacepayments' }
  cascades = decisions.count do |d|
    d['selected_provider'] != 'spacepayments' &&
      d['attempts'].any? { |a| a['decision'] == 'skipped' && runtime.include?(a['reason']) }
  end
  runtime_rejections = decisions.sum do |d|
    d['attempts'].count { |a| a['decision'] == 'skipped' && runtime.include?(a['reason']) }
  end

  puts
  puts '--- Каскады и fallback ---'
  puts "успешных каскадов (rejected -> следующий external): #{cascades}"
  puts "переходов на fallback (spacepayments): #{fallbacks}"
  puts "всего runtime-отказов (rejected/expired): #{runtime_rejections}"
end

def main
  seed = ENV['SEED']&.to_i
  rng = seed ? Random.new(seed) : Random.new

  loader = Loader.new
  config = Config.load
  snapshot = loader.snapshot

  providers = scaled_providers(snapshot['providers'])
  config.overrides.each do |name, ov|
    providers.find { |p| p.payment_system == name }&.apply_override!(ov)
  end

  scorer = Scorer.new(weights: config.weights, tie_break: config.tie_break)
  simulator = Simulator.new(seed: seed)
  router = Router.new(providers, scorer: scorer, simulator: simulator)

  queue = random_operations(N, rng)
  decisions, = router.process(queue)

  puts '=' * 64
  puts "Stress test: #{N} случайных операций"
  puts 'simulation: probabilistic (conversion_24h)'
  puts "daily_amount_limit x#{DAILY_LIMIT_SCALE}, available_requisites=#{REQUISITES_POOL}, daily_approved_amount=0"
  puts "seed: #{seed || '(random)'}"
  puts '=' * 64

  print_convergence(decisions, providers, queue)
  print_cascades(decisions)

  puts
  puts '--- Рекомендации ---'
  reporter = Reporter.new(
    period: snapshot['snapshot_at'].to_s[0, 10],
    gateway: snapshot['gateway'],
    merchant: snapshot['merchant'],
    strategy: config.active_strategy
  )
  report = reporter.build(decisions, providers, queue)
  if report['recommendations'].empty?
    puts '  (нет)'
  else
    report['recommendations'].each { |r| puts "  - #{r}" }
  end

  puts
  puts '--- Утилизация daily_amount_limit ---'
  report['projected_daily_utilization'].each do |name, u|
    limit = u['limit'].nil? ? '∞' : u['limit'].to_s
    util = u['utilization_pct'].nil? ? 'n/a' : format('%.1f%%', u['utilization_pct'])
    puts format('  %-12s used=%s / %s  util=%s', name, u['used'], limit, util)
  end
end

main if $PROGRAM_NAME == __FILE__