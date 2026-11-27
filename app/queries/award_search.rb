# Awards signed in the last `days` days matching optional filters, newest first.
class AwardSearch
  DEFAULT_DAYS = 90

  Result = Data.define(:awards, :total_count, :matched_agencies)

  def initialize(keyword: nil, agency: nil, naics_code: nil, state: nil, min_amount: nil,
                 days: nil, limit: nil, today: Date.current)
    @keyword = keyword.to_s.strip
    @agency = AgencyFilter.new(agency)
    @naics_code = naics_code.to_s.strip
    @state = state.to_s.strip.upcase
    @min_amount = min_amount
    @days = QueryLimits.days(days, default: DEFAULT_DAYS)
    @limit = QueryLimits.limit(limit)
    @today = today
  end

  def call
    scope = filtered_scope
    Result.new(
      awards: scope.includes(:recipient, :awarding_agency).order(action_date: :desc, amount: :desc, id: :desc).limit(@limit).to_a,
      total_count: scope.count,
      matched_agencies: @agency.matched_names
    )
  end

  private

  def filtered_scope
    scope = Award.where(action_date: (@today - @days)..@today)
    scope = scope.where("awards.description ILIKE ?", "%#{Award.sanitize_sql_like(@keyword)}%") unless @keyword.empty?
    scope = scope.where(naics_code: @naics_code) unless @naics_code.empty?
    scope = scope.where(place_of_performance_state: @state) unless @state.empty?
    scope = scope.where(amount: BigDecimal(@min_amount.to_s)..) if @min_amount.present?
    @agency.apply(scope)
  end
end
