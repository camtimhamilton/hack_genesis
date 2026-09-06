# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'loader'
require 'config'
require 'router'
require 'simulator'
require 'routing_context'

# Симулятор, который отклоняет указанных провайдеров, остальных одобряет.
class RejectingSimulator < Simulator
  def initialize(reject: [])
    super(always_approve: true)
    @reject = reject
  end

  def result(provider, _op = nil)
    @reject.include?(provider.payment_system) ? 'rejected' : 'approved'
  end
end

def assert(cond, msg)
  puts(cond ? "  ✅ #{msg}" : "  ❌ #{msg}")
  exit 1 unless cond
end

def build_router(reject)
  loader = Loader.new
  config = Config.load
  providers = loader.providers
  config.overrides.each { |n, ov| providers.find { |p| p.payment_system == n }&.apply_override!(ov) }
  Router.new(providers, simulator: RejectingSimulator.new(reject: reject))
end

op = Loader.new.queue.find { |o| o['operation_id'] == 'op_101' }

puts 'Scenario 1 (reject vipay):'
d = build_router(['vipay']).route(op, RoutingContext.new)
puts "  selected=#{d['selected_provider']}"
assert d['selected_provider'] != 'vipay', 'выбран следующий провайдер вместо vipay'
assert d['attempts'].any? { |a| a['provider'] == 'vipay' && a['decision'] == 'skipped' },
       'vipay помечен skipped (rejected_by_provider)'

puts 'Scenario 2 (reject all external):'
d2 = build_router(%w[vipay payflow quickpay]).route(op, RoutingContext.new)
puts "  selected=#{d2['selected_provider']}"
assert d2['selected_provider'] == 'spacepayments', 'fallback на spacepayments'
assert d2['attempts'].any? { |a| a['provider'] == 'spacepayments' && a['decision'] == 'selected' },
       'spacepayments помечен selected'

puts 'All fallback scenarios passed.'
