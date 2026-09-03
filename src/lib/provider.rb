# frozen_string_literal: true

# Модель провайдера: статические данные из providers.json + изменяемое состояние
# (stateful-метрики), которое обновляется по ходу обработки очереди.
class Provider
  attr_reader :data

  def initialize(raw)
    @data = raw.transform_keys(&:to_sym)
    @state = {
      daily_approved_amount: @data[:daily_approved_amount],
      in_progress_count: @data[:in_progress_count],
      in_progress_amount: @data[:in_progress_amount],
      available_requisites: @data[:available_requisites]
    }
    # "YYYY-MM-DD HH:MM" => число заявок (для rate-limit, этап 2)
    @request_buckets = Hash.new(0)
  end

  # --- статические поля (snapshot) ---
  def payment_system
    @data[:payment_system]
  end

  def status
    @data[:status]
  end

  def traffic_percentage
    @data[:traffic_percentage]
  end

  def priority
    @data[:priority]
  end

  def limit_amount_min
    @data[:limit_amount_min]
  end

  def limit_amount_max
    @data[:limit_amount_max]
  end

  def daily_amount_limit
    @data[:daily_amount_limit]
  end

  def in_progress_count_limit
    @data[:in_progress_count_limit]
  end

  def in_progress_amount_limit
    @data[:in_progress_amount_limit]
  end

  def conversion_24h
    @data[:conversion_24h]
  end

  def avg_latency_sec
    @data[:avg_latency_sec]
  end

  def banks
    @data[:banks] || []
  end

  def exclude_banks
    @data[:exclude_banks]
  end

  def provider_margin_pct
    @data[:provider_margin_pct]
  end

  def merchant_margin_pct
    @data[:merchant_margin_pct]
  end

  def allow_negative_agreement
    @data[:allow_negative_agreement]
  end

  def note
    @data[:note]
  end

  # --- доопределяемые поля (из конфига, могут отсутствовать) ---
  def volume_share_pct
    @data[:volume_share_pct]
  end

  def requests_per_minute_limit
    @data[:requests_per_minute_limit]
  end

  def daily_turnover_min
    @data[:daily_turnover_min]
  end

  def daily_turnover_max
    @data[:daily_turnover_max]
  end

  def amount_range_min
    @data[:amount_range_min]
  end

  def amount_range_max
    @data[:amount_range_max]
  end

  def [](key)
    @data[key.to_sym]
  end

  # Слияние доопределяемых полей из конфига.
  def apply_override!(hash)
    hash.each { |k, v| @data[k.to_sym] = v }
    self
  end

  # --- stateful-метрики (изменяются по ходу обработки) ---
  def daily_approved_amount
    @state[:daily_approved_amount]
  end

  def in_progress_count
    @state[:in_progress_count]
  end

  def in_progress_amount
    @state[:in_progress_amount]
  end

  def available_requisites
    @state[:available_requisites]
  end

  # --- операции над stateful-метриками (используются с этапа 2) ---
  def add_approved_amount(amount)
    @state[:daily_approved_amount] = (@state[:daily_approved_amount] || 0) + amount
  end

  def reserve_requisite!
    current = @state[:available_requisites] || 0
    @state[:available_requisites] = current - 1 if current.positive?
  end

  def register_request!(time)
    @request_buckets[time.strftime('%Y-%m-%d %H:%M')] += 1
  end

  def requests_in_minute(time)
    @request_buckets[time.strftime('%Y-%m-%d %H:%M')]
  end
end
