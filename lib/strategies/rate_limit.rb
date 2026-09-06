# frozen_string_literal: true

require 'time'
require_relative 'base'

# Стратегия 6: интенсивность (rate-limit на провайдера).
# Мягкий сигнал: чем больше загрузка текущей минуты относительно лимита,
# тем ниже приоритет (загрузка влияет на выбор, а не только отсекает).
class RateLimitStrategy < BaseStrategy
  KEY = 'rate_limit'

  def score(provider, op, _ctx)
    limit = provider.requests_per_minute_limit
    return 0.5 if limit.nil? || limit.to_i <= 0

    used = provider.requests_in_minute(parse_time(op['created_at']))
    clamp(1.0 - (used.to_f / limit.to_f))
  end

  private

  def parse_time(str)
    Time.parse(str.to_s)
  rescue StandardError
    Time.now
  end
end
