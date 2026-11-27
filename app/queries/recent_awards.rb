# Newest awards by signed date, plus a per-recipient summary of everything in the
# window: who just won work and may be staffing up.
class RecentAwards
  DEFAULT_DAYS = 30

  Result = Data.define(:awards, :recipients, :total_count, :matched_agencies)
  RecipientSummary = Data.define(:recipient, :award_count, :total_amount)

  def initialize(agency: nil, days: nil, limit: nil, today: Date.current)
    @agency = AgencyFilter.new(agency)
    @days = QueryLimits.days(days, default: DEFAULT_DAYS)
    @limit = QueryLimits.limit(limit)
    @today = today
  end

  def call
    scope = @agency.apply(Award.where(action_date: (@today - @days)..@today))
    Result.new(
      awards: scope.includes(:recipient, :awarding_agency).order(action_date: :desc, amount: :desc, id: :desc).limit(@limit).to_a,
      recipients: recipient_summaries(scope),
      total_count: scope.count,
      matched_agencies: @agency.matched_names
    )
  end

  private

  def recipient_summaries(scope)
    rows = scope.group(:recipient_id)
                .order(Arel.sql("SUM(amount) DESC NULLS LAST"))
                .limit(@limit)
                .pluck(:recipient_id, Arel.sql("COUNT(*)"), Arel.sql("COALESCE(SUM(amount), 0)"))
    recipients = Recipient.where(id: rows.map(&:first)).index_by(&:id)
    rows.map { |id, count, total| RecipientSummary.new(recipient: recipients.fetch(id), award_count: count, total_amount: total) }
  end
end
