# Contracts whose current period of performance ends within the next
# `within_days` days, soonest first, with the incumbent recipient.
class ExpiringContracts
  DEFAULT_WITHIN_DAYS = 180

  Result = Data.define(:awards, :total_count, :matched_agencies)

  def initialize(agency: nil, within_days: nil, min_amount: nil, limit: nil, today: Date.current)
    @agency = AgencyFilter.new(agency)
    @within_days = QueryLimits.days(within_days, default: DEFAULT_WITHIN_DAYS)
    @min_amount = min_amount
    @limit = QueryLimits.limit(limit)
    @today = today
  end

  def call
    scope = Award.where(end_date: @today..(@today + @within_days))
    scope = scope.where(amount: BigDecimal(@min_amount.to_s)..) if @min_amount.present?
    scope = @agency.apply(scope)
    Result.new(
      awards: scope.includes(:recipient, :awarding_agency).order(end_date: :asc, amount: :desc, id: :asc).limit(@limit).to_a,
      total_count: scope.count,
      matched_agencies: @agency.matched_names
    )
  end
end
