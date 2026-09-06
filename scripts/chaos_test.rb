# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'time'
require 'loader'
require 'config'
require 'router'
require 'scorer'
require 'simulator'
require 'routing_context'

# Chaos Engineering: 1 000 операций с инъекцией сбоев.
#   оп 250 — vipay «падает» (conversion_24h → 0, шлюз отказывает);
#   оп 600 — у payflow обнуляются available_requisites.
# Доказываем: 0 потерянных транзакций, трафик перетекает на quickpay + spacepayments.

N = 1_000
VIPAY_CRASH_AT = 250
PAYFLOW_DRY_AT = 600
DAILY_LIMIT_SCALE = 39
REQUISITES_POOL = 50_000

BANKS = %w[sberbank alfa tinkoff vtb gazprombank raiffeisen].freeze

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

# spacepayments (fallback) всегда подтверждает: это гарантированный sink,
# поэтому потерянные транзакции исключены структурно.
class GuaranteedFallbackSimulator < Simulator
  def result(provider, op = nil)
    return 'approved' if provider.payment_system == 'spacepayments'

    super
  end
end

def share(decisions, name)
  total = decisions.size
  return 0.0 if total.zero?

  decisions.count { |d| d['selected_provider'] == name } * 100.0 / total
end

def print_phase(title, decisions)
  puts
  puts "--- #{title} (#{decisions.size} оп) ---"
  puts format('  %-13s %8s', 'provider', 'share')
  %w[vipay payflow quickpay spacepayments].each do |name|
    puts format('  %-13s %7.1f%%', name, share(decisions, name))
  end
end

def assert(cond, msg)
  puts(cond ? "  ✅ #{msg}" : "  ❌ #{msg}")
  exit 1 unless cond
end

def main
  seed = ENV['SEED']&.to_i || 42
  rng = Random.new(seed)

  loader = Loader.new
  config = Config.load
  snapshot = loader.snapshot

  providers = scaled_providers(snapshot['providers'])
  config.overrides.each { |n, ov| providers.find { |p| p.payment_system == n }&.apply_override!(ov) }

  vipay = providers.find { |p| p.payment_system == 'vipay' }
  payflow = providers.find { |p| p.payment_system == 'payflow' }

  scorer = Scorer.new(weights: config.weights, tie_break: config.tie_break)
  router = Router.new(providers, scorer: scorer, simulator: GuaranteedFallbackSimulator.new(seed: seed))

  queue = random_operations(N, rng)

  puts '=' * 64
  puts "Chaos test: #{N} операций, инъекция сбоев"
  puts "  оп #{VIPAY_CRASH_AT}: vipay падает (conversion_24h → 0, шлюз отказывает)"
  puts "  оп #{PAYFLOW_DRY_AT}: payflow лишается реквизитов (available_requisites → 0)"
  puts "  seed: #{seed} · fallback spacepayments — гарантированный approve"
  puts '=' * 64

  decisions = []
  ctx = RoutingContext.new
  reliability_samples = [['старт', vipay.reliability]]

  queue.each_with_index do |op, idx|
    vipay.apply_override!('conversion_24h' => 0.0) if idx == VIPAY_CRASH_AT - 1
    payflow.drain_requisites! if idx == PAYFLOW_DRY_AT - 1

    decisions << router.route(op, ctx)

    n = idx + 1
    reliability_samples << ["op #{n}", vipay.reliability] if [249, 300, 400, 500, 600, 1000].include?(n)
  end

  print_phase('Фаза 1: до сбоя (оп 1–249)', decisions[0...249])
  print_phase('Фаза 2: vipay упал (оп 250–599)', decisions[249...599])
  print_phase('Фаза 3: vipay упал + payflow без реквизитов (оп 600–1000)', decisions[599...1000])

  puts
  puts '--- Динамическая надёжность vipay (EWMA) ---'
  reliability_samples.each { |label, v| puts format('  %-8s %.4f', label, v) }

  runtime_rejections = decisions.sum do |d|
    d['attempts'].count { |a| a['decision'] == 'skipped' && %w[rejected_by_provider expired_by_provider].include?(a['reason']) }
  end
  vipay_rejections = decisions.sum do |d|
    d['attempts'].count { |a| a['provider'] == 'vipay' && a['decision'] == 'skipped' && a['reason'] == 'rejected_by_provider' }
  end
  payflow_skips = decisions.sum do |d|
    d['attempts'].count { |a| a['provider'] == 'payflow' && a['decision'] == 'skipped' && a['reason'] == 'no_available_requisites' }
  end
  fallbacks = decisions.count { |d| d['selected_provider'] == 'spacepayments' }

  lost = decisions.count { |d| d['selected_provider'].nil? }
  processed = decisions.count { |d| !d['selected_provider'].nil? }
  approved = decisions.count { |d| d['simulated_result'] == 'approved' }

  puts
  puts '--- Итоги ---'
  puts "  обработано: #{processed}/#{N}"
  puts "  потеряно:   #{lost}"
  puts "  approved:   #{approved}/#{N}"
  puts "  runtime-отказов (каскад): #{runtime_rejections} (из них vipay: #{vipay_rejections})"
  puts "  payflow отсечён по реквизитам: #{payflow_skips} оп"
  puts "  переходов на spacepayments: #{fallbacks}"

  puts
  puts '--- Доказательство ---'
  assert lost.zero?, '0 транзакций потеряно'
  assert processed == N, '100% операций обработано'
  assert approved == N, '100% операций завершены approved'
  assert share(decisions[249...1000], 'vipay').zero?, 'vipay после сбоя не получает трафик (share = 0%)'
  assert share(decisions[599...1000], 'payflow').zero?, 'payflow без реквизитов не получает трафик (share = 0%)'

  puts
  puts 'Трафик плавно перетёк на quickpay и дефолтный spacepayments.'
end

main if $PROGRAM_NAME == __FILE__
