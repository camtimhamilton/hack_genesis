# frozen_string_literal: true

# Симулирует исход операции (approved/rejected/expired) и задержку провайдера.
#
# Результат по умолчанию вероятностный — по `conversion_24h` провайдера; при
# флаге `always_approve` всегда `approved` (для детерминированной валидации).
class Simulator
  # Доля таймаутов (expired) среди неуспешных исходов (rejected/expired).
  # Позволяет пути таймаута реально проявляться в симуляции и попадать в attempts.
  EXPIRED_RATE = 0.10

  # @param seed [Integer, nil] зерно ГСЧ для воспроизводимости (nil — случайный).
  # @param always_approve [Boolean] если true — всегда возвращать `approved`.
  # @return [Simulator]
  def initialize(seed: nil, always_approve: false)
    @rng = seed ? Random.new(seed) : Random.new
    @always_approve = always_approve
  end

  # Возвращает исход операции для провайдера.
  #
  # При `always_approve` — всегда `approved`. Иначе бросается случайный roll
  # (1..100) и сравнивается с `conversion_24h * 100`; при неуспехе с
  # вероятностью EXPIRED_RATE возвращается `expired` (таймаут), иначе —
  # `rejected` (роутер каскадирует на следующего провайдера).
  #
  # @param provider [Provider] провайдер, чей `conversion_24h` используется.
  # @param _op [Hash, nil] операция (зарезервировано, не используется).
  # @return [String] `approved` | `rejected` | `expired`.
  def result(provider, _op = nil)
    return 'approved' if @always_approve

    conversion_pct = provider.conversion_24h.to_f * 100.0
    roll = @rng.rand(1..100)
    return 'approved' if roll <= conversion_pct

    @rng.rand < EXPIRED_RATE ? 'expired' : 'rejected'
  end

  # Задержка провайдера (сек), используемая для `latency_sec` в решении.
  #
  # @param provider [Provider] провайдер.
  # @return [Integer] средняя задержка в секундах (целое).
  def latency(provider)
    provider.avg_latency_sec.to_i
  end
end

