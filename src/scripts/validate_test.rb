#!/usr/bin/env ruby
# frozen_string_literal: true

# Валидатор решений для финальной тестовой очереди operations_queue_test.json.
# Аналог validate_10.rb, но параметризован именем очереди и не привязан к
# конкретным operation_id демо-очереди.
#
# Использование:
#   ruby scripts/validate_test.rb path/to/routing_decisions_test.json [queue_filename]
#
# По умолчанию queue_filename = operations_queue_test.json.
#
# Проверяет:
#   1. Структуру JSON
#   2. Покрытие всех заявок из указанной очереди
#   3. Детерминированные кейсы (из reference_decisions.json, если есть)
#   4. Что selected_provider входит в список eligible провайдеров
#   5. skip-reasons из reference (если есть)

require 'json'

DATA_DIR = File.expand_path('../data', __dir__)
DEFAULT_QUEUE_FILENAME = 'operations_queue_test.json'

def load_json(filename)
  JSON.parse(File.read(File.join(DATA_DIR, filename)))
end

# Логика допуска провайдера (hard-constraints) идентична validate_10.rb.
def eligible_providers(operation, providers)
  amount = operation['amount']
  bank = operation['bank']

  providers.select do |p|
    next false if p['status'] != 'active'
    next false if p['traffic_percentage'].to_f.zero? && p['payment_system'] != 'spacepayments'
    next false if p['limit_amount_min'] && amount < p['limit_amount_min']
    next false if p['limit_amount_max'] && amount > p['limit_amount_max']
    next false if p['daily_amount_limit'] && (p['daily_approved_amount'].to_f + amount) > p['daily_amount_limit']
    next false if p['in_progress_count_limit'] && (p['in_progress_count'].to_i + 1) > p['in_progress_count_limit']
    next false if p['in_progress_amount_limit'] && (p['in_progress_amount'].to_f + amount) > p['in_progress_amount_limit']
    next false if p['available_requisites'].to_i.zero?
    next false if p['provider_margin_pct'].to_f > p['merchant_margin_pct'].to_f && !p['allow_negative_agreement']

    banks = p['banks'] || []
    if banks.any?
      if p['exclude_banks']
        next false if banks.include?(bank)
      else
        next false unless banks.include?(bank)
      end
    end

    true
  end.map { |p| p['payment_system'] }
end

def validate_structure(decision)
  errors = []
  %w[operation_id selected_provider attempts].each do |field|
    errors << "отсутствует поле #{field}" unless decision.key?(field)
  end

  if decision['attempts']
    decision['attempts'].each_with_index do |attempt, i|
      %w[provider decision reason].each do |field|
        errors << "attempts[#{i}]: отсутствует #{field}" unless attempt.key?(field)
      end
      unless %w[selected skipped].include?(attempt['decision'])
        errors << "attempts[#{i}]: decision должен быть selected или skipped"
      end
    end
  end

  errors
end

# --- main ---

if ARGV.empty?
  puts "Использование: ruby scripts/validate_test.rb <routing_decisions_test.json> [queue_filename]"
  exit 1
end

decisions_path = ARGV[0]
queue_filename = ARGV[1] || DEFAULT_QUEUE_FILENAME

unless File.exist?(decisions_path)
  puts "❌ Файл не найден: #{decisions_path}"
  exit 1
end

queue_path = File.join(DATA_DIR, queue_filename)
unless File.exist?(queue_path)
  puts "❌ Файл очереди не найден: #{queue_path}"
  exit 1
end

begin
  decisions = JSON.parse(File.read(decisions_path))
rescue JSON::ParserError => e
  puts "❌ Невалидный JSON: #{e.message}"
  exit 1
end

decisions = [decisions] unless decisions.is_a?(Array)

queue = load_json(queue_filename)
providers_data = load_json('providers.json')
providers = providers_data['providers']

reference_path = File.join(DATA_DIR, 'reference_decisions.json')
reference = File.exist?(reference_path) ? JSON.parse(File.read(reference_path)) : nil

queue_ids = queue.map { |op| op['operation_id'] }
decision_ids = decisions.map { |d| d['operation_id'] }

passed = 0
failed = 0
warnings = 0

puts "=== Проверка #{File.basename(decisions_path)} ==="
puts "Очередь:  #{queue_filename} (#{queue_ids.size} заявок)"
puts "Решений в файле: #{decision_ids.size}"
puts

# 1. Покрытие
missing = queue_ids - decision_ids
extra = decision_ids - queue_ids

if missing.any?
  puts "❌ Отсутствуют решения для: #{missing.join(', ')}"
  failed += missing.size
else
  puts "✅ Все заявки из очереди покрыты"
  passed += 1
end

if extra.any?
  puts "⚠️  Лишние operation_id: #{extra.join(', ')}"
  warnings += 1
end

# 2. Структура
structure_errors = []
decisions.each do |d|
  structure_errors.concat(validate_structure(d).map { |e| "#{d['operation_id']}: #{e}" })
end

if structure_errors.any?
  puts "❌ Ошибки структуры:"
  structure_errors.each { |e| puts "   #{e}" }
  failed += structure_errors.size
else
  puts "✅ Структура JSON корректна"
  passed += 1
end

# 3. Детерминированные кейсы (если есть reference)
if reference && reference['deterministic_cases'].is_a?(Array)
  deterministic = reference['deterministic_cases'].select { |case_| queue_ids.include?(case_['operation_id']) }
  if deterministic.empty?
    puts "ℹ️  Нет deterministic-кейсов reference для этой очереди"
  else
    deterministic.each do |case_|
      op_id = case_['operation_id']
      required = case_['required_provider']
      decision = decisions.find { |d| d['operation_id'] == op_id }

      unless decision
        puts "❌ #{op_id}: нет решения (ожидался #{required})"
        failed += 1
        next
      end

      if decision['selected_provider'] == required
        puts "✅ #{op_id}: корректно выбран #{required}"
        passed += 1
      else
        puts "❌ #{op_id}: выбран #{decision['selected_provider']}, ожидался #{required}"
        puts "   Причина: #{case_['reason']}"
        failed += 1
      end
    end
  end
end

# 4. Eligible providers
queue.each do |operation|
  op_id = operation['operation_id']
  decision = decisions.find { |d| d['operation_id'] == op_id }
  next unless decision

  eligible = eligible_providers(operation, providers)
  selected = decision['selected_provider']

  if eligible.include?(selected)
    puts "✅ #{op_id}: #{selected} в списке допустимых [#{eligible.join(', ')}]"
    passed += 1
  else
    puts "❌ #{op_id}: #{selected} НЕ допустим. Допустимые: [#{eligible.join(', ')}]"
    failed += 1
  end
end

# 5. Проверка skip reasons (если есть reference)
if reference && reference['skip_reasons_expected'].is_a?(Hash)
  reference['skip_reasons_expected'].each do |op_id, skips|
    next unless queue_ids.include?(op_id)

    decision = decisions.find { |d| d['operation_id'] == op_id }
    next unless decision

    skips.each do |provider, expected_reason|
      attempt = decision['attempts']&.find { |a| a['provider'] == provider }
      if attempt.nil?
        puts "⚠️  #{op_id}: нет attempt для #{provider} (ожидался skip: #{expected_reason})"
        warnings += 1
      elsif attempt['decision'] != 'skipped'
        puts "⚠️  #{op_id}: #{provider} не skipped (ожидался skip: #{expected_reason})"
        warnings += 1
      else
        puts "✅ #{op_id}: #{provider} корректно skipped (#{attempt['reason']})"
        passed += 1
      end
    end
  end
end

puts
puts "=== Итого ==="
puts "✅ Пройдено: #{passed}"
puts "❌ Ошибок:   #{failed}"
puts "⚠️  Предупр.: #{warnings}"

exit(failed.zero? ? 0 : 1)
