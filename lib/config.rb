# frozen_string_literal: true

require 'yaml'

# Загрузчик конфигурации правил (config/routing.yml).
class Config
  def self.load(path = File.expand_path('../config/routing.yml', __dir__))
    new(path)
  end

  def initialize(path)
    @path = path
    @data = YAML.load_file(path)
  end

  attr_reader :data

  def active_strategy
    @data['active_strategy']
  end

  def tie_break
    @data['tie_break']
  end

  def weights
    @data['weights'] || {}
  end

  def overrides
    @data['overrides'] || {}
  end
end
