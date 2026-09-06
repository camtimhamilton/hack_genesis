# frozen_string_literal: true

require_relative 'base'

# Стратегия 3: каскад по priority (меньше — выше).
class CascadeStrategy < BaseStrategy
  KEY = 'cascade'

  def score(provider, _op, _ctx)
    priority = provider.priority.to_i
    priority.positive? ? (1.0 / priority) : 0.0
  end
end
