# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('lib', __dir__))

require 'json'
require 'loader'
require 'config'
require 'router'
require 'scorer'
require 'simulator'
require 'reporter'
require 'html_reporter'

# Корень проекта — сюда пишутся выходные артефакты.
ROOT = File.expand_path('..', __dir__)

USAGE = <<~TEXT
  Использование:
    ruby src/main.rb [--deterministic] [decisions_path] [report_path] [queue_filename]

  Флаги:
    --deterministic, --always-approve
        гарантированный approved (для локальной валидации validate_10.rb)

  Аргументы (опционально, по умолчанию — демо-очередь):
    decisions_path  путь к routing_decisions.json   (по умолчанию <корень>/routing_decisions.json)
    report_path     путь к routing_report.json      (по умолчанию <корень>/routing_report.json)
    queue_filename  имя очереди в src/data           (по умолчанию operations_queue_10.json)

  Рядом с JSON-отчётом всегда пишется автономный HTML-отчёт (то же имя, .html),
  полностью офлайн (inline CSS/JS/SVG, без CDN). JSON остаётся обязательным артефактом.

  По умолчанию симулятор вероятностный: approved с вероятностью conversion_24h,
  иначе rejected → каскад на следующего (при пустом пуле — spacepayments).

  Примеры:
    ruby src/main.rb --deterministic
    ruby src/main.rb routing_decisions_test.json routing_report_test.json operations_queue_test.json
TEXT

def main
  print_usage_and_exit if ARGV.include?('--help') || ARGV.include?('-h')

  args, deterministic = parse_args # это аргумент в консоли
  queue_filename = args[2] || 'operations_queue_10.json'
  ensure_queue_exists!(queue_filename)

  loader = Loader.new(queue_filename: queue_filename)
  config = Config.load
  providers = loader.providers
  queue = loader.queue

  apply_overrides!(providers, config)

  scorer = Scorer.new(weights: config.weights, tie_break: config.tie_break)
  simulator = Simulator.new(always_approve: deterministic)
  router = Router.new(providers, scorer: scorer, simulator: simulator)

  decisions, = router.process(queue)

  decisions_path = args[0] ? File.expand_path(args[0], ROOT) : File.join(ROOT, 'routing_decisions.json')
  report_path = args[1] ? File.expand_path(args[1], ROOT) : File.join(ROOT, 'routing_report.json')
  File.write(decisions_path, JSON.pretty_generate(decisions))

  snapshot_at = loader.snapshot['snapshot_at']
  reporter = Reporter.new(
    period: snapshot_at ? snapshot_at.to_s[0, 10] : nil,
    gateway: loader.gateway,
    merchant: loader.merchant,
    strategy: config.active_strategy
  )
  report = reporter.build(decisions, providers, queue)
  File.write(report_path, JSON.pretty_generate(report))

  html_path = report_path.sub(/\.json\z/i, '') + '.html'
  File.write(html_path, HtmlReporter.new.render(report))

  puts "strategy : #{config.active_strategy} (tie-break: #{config.tie_break})"
  puts "simulation: #{deterministic ? 'deterministic (always_approve)' : 'probabilistic (conversion_24h)'}"
  puts "Wrote #{decisions.size} decisions to #{decisions_path}"
  puts "Wrote report to #{report_path}"
  puts "Wrote HTML report to #{html_path}"
  puts
  decisions.each do |d|
    attempts = d['attempts'].map { |a| "#{a['provider']}:#{a['decision']}(#{a['reason']})" }.join(', ')
    puts "  #{d['operation_id']} -> #{d['selected_provider']}  [ #{attempts} ]"
  end

  puts
  print_distribution(decisions, providers)
  puts
  print_report_summary(report)
end

def parse_args
  deterministic = false
  deterministic = true if ARGV.delete('--deterministic')
  deterministic = true if ARGV.delete('--always-approve')
  [ARGV.dup, deterministic]
end

def print_usage_and_exit
  puts USAGE
  exit 0
end

def ensure_queue_exists!(queue_filename)
  path = File.join(Loader::DATA_DIR, queue_filename)
  return if File.exist?(path)

  warn "Файл очереди не найден: #{path}"
  warn 'Укажите существующее имя очереди третьим аргументом (например operations_queue_test.json).'
  exit 1
end

def apply_overrides!(providers, config)
  config.overrides.each do |name, ov|
    p = providers.find { |pr| pr.payment_system == name }
    p.apply_override!(ov) if p
  end
end

def print_distribution(decisions, providers)
  puts 'Distribution (count):'
  total = decisions.size
  counts = decisions.group_by { |d| d['selected_provider'] }.transform_values(&:size)
  providers.reject { |p| p.payment_system == 'spacepayments' }.each do |p|
    name = p.payment_system
    cnt = counts.fetch(name, 0)
    share = total.zero? ? 0.0 : (cnt * 100.0 / total)
    target = p.traffic_percentage.to_f
    puts format('  %-13s count=%d share=%.1f%% target=%.0f%% dev=%+.1fpp', name, cnt, share, target, share - target)
  end
end

def print_report_summary(report)
  puts 'Report summary:'
  report['projected_daily_utilization'].each do |name, u|
    limit = u['limit'].nil? ? '∞' : u['limit'].to_s
    util = u['utilization_pct'].nil? ? 'n/a' : format('%.1f%%', u['utilization_pct'])
    puts format('  %-13s daily_used=%d/%s util=%s', name, u['used'], limit, util)
  end
  puts 'Recommendations:'
  report['recommendations'].each { |r| puts "  - #{r}" }
end

main if $PROGRAM_NAME == __FILE__
