# frozen_string_literal: true

require 'json'
require 'csv'
require_relative 'provider'

# Загрузчик входных данных из src/data.
class Loader
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
    @providers ||= snapshot.fetch('providers', []).map { |raw| Provider.new(raw) }
  end

  # --- операции (очередь) ---
  def queue
    @queue ||= read_json(@queue_filename)
  end

  # --- история ---
  def history
    return @history if defined?(@history)

    content = File.read(File.join(@data_dir, 'operations_history.csv'), encoding: 'UTF-8')
    content = content.sub(/\A\uFEFF/, '') # убрать BOM, если есть
    @history = CSV.parse(content, headers: true)
  end

  # --- эталон ---
  def reference
    @reference ||= read_json('reference_decisions.json')
  end

  private

  def read_json(filename)
    path = File.join(@data_dir, filename)
    JSON.parse(File.read(path, encoding: 'UTF-8'))
  end
end
