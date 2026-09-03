# frozen_string_literal: true

require_relative 'base'

# Стратегия 2: целевая доля по объёму (volume_share_pct).
class VolumeShareStrategy < BaseStrategy
  KEY = 'volume_share'

  def score(provider, _op, ctx)
    target = provider.volume_share_pct.to_f / 100.0
    return 0.5 if target <= 0

    clamp(0.5 + (target - ctx.volume_share(provider.payment_system)))
  end
end
