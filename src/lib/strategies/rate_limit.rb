# frozen_string_literal: true

require 'time'
require_relative 'base'

# Стратегия 6: интенсивность (rate-limit на провайдера).
class RateLimitStrategy < BaseStrategy
  KEY = 'rate_limit'

  def score(provider, op, _ctx)
    limit = provider.requests_per_minute_limit
    return 0.5 if limit.nil? || limit.to_i <= 0

    used = provider.requests_in_minute(parse_time(op['created_at']))
    used.to_i >= limit.to_i ? 0.0 : 1.0
  end

  private

  def parse_time(str)
    Time.parse(str.to_s)
  rescue StandardError
    Time.now
  end
end
