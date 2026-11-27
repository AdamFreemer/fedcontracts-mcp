# Contracts with an end date in the next `within_days` days, with the incumbent.
#
# Two end dates matter: `end_date` (current period of performance) and
# `potential_end_date` (if every option is exercised, fetched by EndDateEnricher).
# Each result is labeled:
#   final_period       - the contract's last possible end falls in the window: likely recompete
#   options_remaining  - the current period ends in the window but options can extend it: likely renewal
#   unknown            - option status not checked (awards under EndDateEnricher::MIN_AMOUNT)
class ExpiringContracts
  DEFAULT_WITHIN_DAYS = 180
  STATUSES = %w[final_period options_remaining unknown].freeze

  Item = Data.define(:award, :status, :final_end_date)
  # unchecked_count: contracts in the window (before recompete_only) whose option status is unknown.
  Result = Data.define(:items, :total_count, :unchecked_count, :matched_agencies) do
    def awards = items.map(&:award)
  end

  # Date of the event that puts the award in the window: the current end if it's
  # still ahead, otherwise the potential end (current period already lapsed).
  EVENT_DATE_SQL = "CASE WHEN awards.end_date >= :today THEN awards.end_date ELSE awards.potential_end_date END".freeze
  FINAL_END_SQL = "GREATEST(awards.end_date, COALESCE(awards.potential_end_date, awards.end_date))".freeze

  def initialize(agency: nil, within_days: nil, min_amount: nil, recompete_only: false, limit: nil, today: Date.current)
    @agency = AgencyFilter.new(agency)
    @within_days = QueryLimits.days(within_days, default: DEFAULT_WITHIN_DAYS)
    @min_amount = min_amount
    @recompete_only = recompete_only
    @limit = QueryLimits.limit(limit)
    @today = today
  end

  def call
    base = base_scope
    scope = @recompete_only ? recompete_filter(base) : base
    awards = scope.includes(:recipient, :awarding_agency)
                  .order(Arel.sql(Award.sanitize_sql_array([ "#{EVENT_DATE_SQL} ASC", { today: @today } ])), amount: :desc, id: :asc)
                  .limit(@limit).to_a
    Result.new(items: awards.map { |a| item(a) }, total_count: scope.count,
               unchecked_count: base.where(details_checked_at: nil).count, matched_agencies: @agency.matched_names)
  end

  private

  def window
    @today..(@today + @within_days)
  end

  def base_scope
    scope = Award.where(end_date: window)
                 .or(Award.where(potential_end_date: window).where("awards.potential_end_date >= awards.end_date"))
    scope = scope.where(amount: BigDecimal(@min_amount.to_s)..) if @min_amount.present?
    @agency.apply(scope)
  end

  def recompete_filter(scope)
    scope.where.not(details_checked_at: nil).where("#{FINAL_END_SQL} BETWEEN ? AND ?", window.begin, window.end)
  end

  def item(award)
    final_end = [ award.end_date, award.potential_end_date ].compact.max
    status =
      if award.details_checked_at.nil? then "unknown"
      elsif final_end <= window.end then "final_period"
      else "options_remaining"
      end
    Item.new(award:, status:, final_end_date: final_end)
  end
end
