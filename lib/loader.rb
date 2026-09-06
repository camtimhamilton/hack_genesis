# frozen_string_literal: true

require 'json'
require 'csv'
require_relative 'provider'

# Загрузчик входных данных из data/.
class Loader
  class DataError < StandardError; end

  DATA_DIR = File.expand_path('../data', __dir__)

  def initialize(data_dir: DATA_DIR, queue_filename: 'operations_queue_10.json')
    @data_dir = data_dir
    @queue_filename = queue_filename
  end

  # --- providers.json ---
  def snapshot
    @snapshot ||= read_json('providers.json')
  end

  def gateway
    snapshot['gateway']
  end

  def merchant
    snapshot['merchant']
  end

  def providers
    @providers ||= begin
      list = snapshot.fetch('providers', []).map { |raw| Provider.new(raw) }
      seed_reliability!(list)
      list
    end
  end

  # --- операции (очередь) ---
  def queue
    @queue ||= read_json(@queue_filename)
  end

  # --- история ---
  def history
    return @history if defined?(@history)

    path = File.join(@data_dir, 'operations_history.csv')
    content = begin
      File.read(path, encoding: 'UTF-8')
    rescue Errno::ENOENT
      raise DataError, "Файл входных данных не найден: #{path}"
    end
    content = content.sub(/\A\uFEFF/, '') # убрать BOM, если есть
    @history = CSV.parse(content, headers: true)
  end

  # --- эталон ---
  def reference
    @reference ||= read_json('reference_decisions.json')
  end

  private

  # Базовая надёжность из operations_history.csv: approved/total по провайдеру.
  # Если у провайдера нет истории — остаётся fallback conversion_24h (в Provider#initialize).
  def seed_reliability!(providers)
    stats = history.each_with_object(Hash.new { |h, k| h[k] = [0, 0] }) do |row, acc|
      ps = row['payment_system']
      next if ps.nil? || ps.empty?

      acc[ps][1] += 1
      acc[ps][0] += 1 if row['status'] == 'approved'
    end

    providers.each do |p|
      approved, total = stats[p.payment_system]
      next if total.nil? || total.zero?

      p.seed_reliability!(approved.to_f / total.to_f, source: 'history', observations: total)
    end
  end

  def read_json(filename)
    path = File.join(@data_dir, filename)
    content = File.read(path, encoding: 'UTF-8')
    JSON.parse(content)
  rescue Errno::ENOENT
    raise DataError, "Файл входных данных не найден: #{path}"
  rescue JSON::ParserError => e
    raise DataError, "Некорректный JSON в файле #{path}: #{e.message}"
  end
end
