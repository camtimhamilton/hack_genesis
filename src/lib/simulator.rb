# frozen_string_literal: true

# Симуляция результата операции и задержки.
class Simulator
  # Доля таймаутов (expired) среди неуспешных исходов (rejected/expired).
  # Позволяет пути таймаута реально проявляться в симуляции и попадать в attempts.
  EXPIRED_RATE = 0.10

  def initialize(seed: nil, always_approve: false)
    @rng = seed ? Random.new(seed) : Random.new
    @always_approve = always_approve
  end

  # Вероятностный результат по conversion_24h (в процентах):
  #   roll <= conversion_24h * 100  => approved
  #   иначе                          => неуспех: в EXPIRED_RATE случаев expired (таймаут),
  #                                     в остальных — rejected (роутер каскадирует дальше)
  def result(provider, _op = nil)
    return 'approved' if @always_approve

    conversion_pct = provider.conversion_24h.to_f * 100.0
    roll = @rng.rand(1..100)
    return 'approved' if roll <= conversion_pct

    @rng.rand < EXPIRED_RATE ? 'expired' : 'rejected'
  end

  def latency(provider)
    provider.avg_latency_sec.to_i
  end
end

