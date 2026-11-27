# Resolves a free-text agency ("DHS", "USCIS", "homeland", "Veterans Affairs") to
# awards. Acronym matches win: toptier abbreviations, plus acronyms derived from
# sub-agency names (USAspending stores those by full name only, e.g.
# "U.S. Citizenship and Immigration Services" -> USCIS). Only if no acronym matches
# does a name fragment of MIN_NAME_FRAGMENT+ characters match agency names, so
# "ICE" doesn't match "Department of Justice".
class AgencyFilter
  STOP_WORDS = %w[and of the for on in to].freeze
  # Sub-agencies whose common acronym doesn't follow from their name.
  ACRONYM_ALIASES = {
    "CMS" => "Centers for Medicare and Medicaid Services",
    "CDC" => "Centers for Disease Control and Prevention"
  }.freeze

  MIN_NAME_FRAGMENT = 4

  def self.acronyms(name)
    letters = name.gsub(/[^A-Za-z ]/, " ").split.reject { |w| STOP_WORDS.include?(w.downcase) }.map { |w| w[0].upcase }
    full = letters.join
    [ full, full.delete_prefix("US") ].uniq
  end

  def initialize(query)
    @query = query.to_s.strip
  end

  def blank?
    @query.empty?
  end

  def apply(scope)
    return scope if blank?
    return scope.none if agency_ids.empty? && sub_agency_names.empty?

    scope.where(awarding_agency_id: agency_ids).or(scope.where(awarding_sub_agency: sub_agency_names))
  end

  # Human-readable names of what matched, so the client can see how "DHS" was read.
  def matched_names
    return [] if blank?

    (Agency.where(id: agency_ids).order(:name).pluck(:name) + sub_agency_names.sort).uniq
  end

  private

  def agency_ids
    resolve unless defined?(@agency_ids)
    @agency_ids
  end

  def sub_agency_names
    resolve unless defined?(@sub_agency_names)
    @sub_agency_names
  end

  def resolve
    upper = @query.upcase
    all_sub_names = Award.distinct.where.not(awarding_sub_agency: nil).pluck(:awarding_sub_agency)

    @agency_ids = Agency.where("UPPER(abbreviation) = ?", upper).pluck(:id)
    @sub_agency_names = all_sub_names.select { |n| n == ACRONYM_ALIASES[upper] || self.class.acronyms(n).include?(upper) }
    return if @agency_ids.any? || @sub_agency_names.any? || @query.length < MIN_NAME_FRAGMENT

    @agency_ids = Agency.where("name ILIKE ?", like_pattern).pluck(:id)
    @sub_agency_names = all_sub_names.select { |n| n.downcase.include?(@query.downcase) }
  end

  def like_pattern
    "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%"
  end
end
