# frozen_string_literal: true

# Накопленные факт-доли (count/volume) по ходу обработки очереди.
class RoutingContext
  attr_reader :counts, :volumes, :total_count, :total_volume

  def initialize
    @counts = Hash.new(0)
    @volumes = Hash.new(0.0)
    @total_count = 0
    @total_volume = 0.0
  end

  def record!(provider_name, amount)
    @counts[provider_name] += 1
    @volumes[provider_name] += amount.to_f
    @total_count += 1
    @total_volume += amount.to_f
  end

  def count_share(name)
    return 0.0 if @total_count.zero?

    @counts[name].to_f / @total_count
  end

  def volume_share(name)
    return 0.0 if @total_volume.zero?

    @volumes[name].to_f / @total_volume
  end
end
