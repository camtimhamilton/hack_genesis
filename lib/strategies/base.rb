# frozen_string_literal: true

# Базовый класс стратегии. Каждая стратегия возвращает score в [0, 1]
# (чем больше, тем предпочтительнее провайдер).
class BaseStrategy
  def score(_provider, _op, _ctx)
    raise NotImplementedError, "#{self.class} должен реализовать #score"
  end

  # Ключ для сопоставления с weights в конфиге.
  def key
    self.class::KEY
  end

  private

  def clamp(value, min = 0.0, max = 1.0)
    [[value.to_f, min].max, max].min
  end
end
