# Shared input clamps for query objects. Tools validate inputs too (M8); these
# keep queries safe on their own.
module QueryLimits
  DEFAULT_LIMIT = 25
  MAX_LIMIT = 50
  MAX_DAYS = 3650

  module_function

  def limit(value)
    Integer(value || DEFAULT_LIMIT).clamp(1, MAX_LIMIT)
  end

  def days(value, default:)
    Integer(value || default).clamp(1, MAX_DAYS)
  end
end
