# Profile of one company's federal contract work. Finds the company by UEI or by
# name. Recipient rows are grouped by normalized name (big companies have several
# UEIs under one name). Several distinct names, or only fuzzy (trigram) matches,
# return candidates for the client to pick instead of guessing.
class CompanyProfile
  CANDIDATE_LIMIT = 10
  SIMILARITY_THRESHOLD = 0.3
  TOP_N = 5
  TREND_QUARTERS = 8

  Candidate = Data.define(:name, :ueis, :award_count, :total_amount)
  Profile = Data.define(:name, :ueis, :recipient_count, :total_amount, :award_count,
                        :top_agencies, :top_naics, :quarterly_trend, :recent_awards, :expiring_awards)
  Result = Data.define(:status, :profile, :candidates) do
    def found? = status == :found
    def ambiguous? = status == :ambiguous
    def not_found? = status == :not_found
  end

  def initialize(name: nil, uei: nil, today: Date.current)
    @name = name.to_s.strip
    @uei = uei.to_s.strip.upcase
    @today = today
  end

  def call
    raise ArgumentError, "name or uei is required" if @name.empty? && @uei.empty?

    recipients, fuzzy = matching_recipients
    return Result.new(status: :not_found, profile: nil, candidates: []) if recipients.empty?

    groups = recipients.group_by { |r| Usaspending::AwardMapper.normalize_name(r.name) }
    if fuzzy || groups.size > 1
      return Result.new(status: :ambiguous, profile: nil, candidates: candidates(groups))
    end

    Result.new(status: :found, profile: build_profile(groups.values.first), candidates: [])
  end

  private

  # Returns [recipients, fuzzy?]. Exact UEI wins; then exact (case-insensitive)
  # name; then substring; then trigram similarity, which is only ever a suggestion.
  def matching_recipients
    return [ Recipient.where(uei: @uei).to_a, false ] unless @uei.empty?

    exact = Recipient.where("LOWER(name) = ?", @name.downcase).to_a
    return [ exact, false ] if exact.any?

    substring = Recipient.where("name ILIKE ?", "%#{Recipient.sanitize_sql_like(@name)}%").to_a
    return [ substring, false ] if substring.any?

    similar = Recipient.where("similarity(name, ?) >= ?", @name, SIMILARITY_THRESHOLD)
                       .order(Arel.sql(Recipient.sanitize_sql_array([ "similarity(name, ?) DESC", @name ])))
                       .limit(CANDIDATE_LIMIT * 3).to_a
    [ similar, true ]
  end

  def candidates(groups)
    totals = Award.where(recipient_id: groups.values.flatten.map(&:id))
                  .group(:recipient_id).pluck(:recipient_id, Arel.sql("COUNT(*)"), Arel.sql("COALESCE(SUM(amount), 0)"))
                  .to_h { |id, count, total| [ id, [ count, total ] ] }
    groups.values.map do |recipients|
      count, total = recipients.map { |r| totals.fetch(r.id, [ 0, 0 ]) }.transpose.map(&:sum)
      Candidate.new(name: recipients.first.name, ueis: recipients.filter_map(&:uei).uniq, award_count: count, total_amount: total)
    end.sort_by { |c| -c.total_amount }.first(CANDIDATE_LIMIT)
  end

  def build_profile(recipients)
    awards = Award.where(recipient_id: recipients.map(&:id))
    Profile.new(
      name: recipients.first.name,
      ueis: recipients.filter_map(&:uei).uniq,
      recipient_count: recipients.size,
      total_amount: awards.sum(:amount),
      award_count: awards.count,
      top_agencies: top_agencies(awards),
      top_naics: top_naics(awards),
      quarterly_trend: quarterly_trend(awards),
      recent_awards: awards.includes(:awarding_agency).order(action_date: :desc, id: :desc).limit(TOP_N).to_a,
      expiring_awards: awards.includes(:awarding_agency).where(end_date: @today..).order(end_date: :asc, id: :asc).limit(TOP_N).to_a
    )
  end

  def top_agencies(awards)
    awards.joins(:awarding_agency).group("agencies.name", "agencies.abbreviation")
          .order(Arel.sql("SUM(awards.amount) DESC NULLS LAST")).limit(TOP_N)
          .pluck("agencies.name", "agencies.abbreviation", Arel.sql("COUNT(*)"), Arel.sql("COALESCE(SUM(awards.amount), 0)"))
          .map { |name, abbr, count, total| { name:, abbreviation: abbr, award_count: count, total_amount: total } }
  end

  def top_naics(awards)
    awards.where.not(naics_code: nil).group(:naics_code, :naics_description)
          .order(Arel.sql("SUM(amount) DESC NULLS LAST")).limit(TOP_N)
          .pluck(:naics_code, :naics_description, Arel.sql("COUNT(*)"), Arel.sql("COALESCE(SUM(amount), 0)"))
          .map { |code, desc, count, total| { code:, description: desc, award_count: count, total_amount: total } }
  end

  # Awards signed per calendar quarter for the last TREND_QUARTERS quarters (zero-filled).
  def quarterly_trend(awards)
    first_quarter = (@today.beginning_of_quarter << (3 * (TREND_QUARTERS - 1)))
    rows = awards.where(action_date: first_quarter..@today)
                 .group(Arel.sql("DATE_TRUNC('quarter', action_date)::date"))
                 .pluck(Arel.sql("DATE_TRUNC('quarter', action_date)::date"), Arel.sql("COUNT(*)"), Arel.sql("COALESCE(SUM(amount), 0)"))
                 .to_h { |q, count, total| [ q, [ count, total ] ] }
    Array.new(TREND_QUARTERS) do |i|
      quarter = first_quarter >> (3 * i)
      count, total = rows.fetch(quarter, [ 0, 0 ])
      { quarter: "#{quarter.year}-Q#{(quarter.month - 1) / 3 + 1}", award_count: count, total_amount: total }
    end
  end
end
