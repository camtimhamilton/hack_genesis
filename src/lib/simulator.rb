# frozen_string_literal: true

# Симуляция результата операции и задержки.
class Simulator
  def initialize(seed: nil, always_approve: false)
    @rng = seed ? Random.new(seed) : Random.new
    @always_approve = always_approve
  end

  # Вероятностный результат по conversion_24h (в процентах):
  #   rand(1..100) > conversion_24h * 100  => rejected (роутер каскадирует дальше)
  #   иначе                               => approved
  def result(provider, _op = nil)
    return 'approved' if @always_approve

    conversion_pct = provider.conversion_24h.to_f * 100.0
    roll = @rng.rand(1..100)
    roll > conversion_pct ? 'rejected' : 'approved'
  end

  def latency(provider)
    provider.avg_latency_sec.to_i
  end
end

