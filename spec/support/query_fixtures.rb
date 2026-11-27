# Small, realistic dataset for query specs, modeled on examples.md (DID(IT), VA.gov).
module QueryFixtures
  TODAY = Date.new(2026, 11, 27)

  def build_query_fixtures
    dhs = create(:agency, toptier_code: "070", name: "Department of Homeland Security", abbreviation: "DHS")
    va = create(:agency, toptier_code: "036", name: "Department of Veterans Affairs", abbreviation: "VA")
    doj = create(:agency, toptier_code: "015", name: "Department of Justice", abbreviation: "DOJ")

    excella = create(:recipient, name: "EXCELLA, LLC", uei: "KMKUAFKECJ83", recipient_key: "excella-C")
    oddball = create(:recipient, name: "ODDBALL, INC.", uei: "MHNFNJ1J5RF5", recipient_key: "oddball-C")
    agile_six = create(:recipient, name: "AGILE SIX APPLICATIONS, INC", uei: "AGILESIX0001", recipient_key: "agile-six-C")

    {
      dhs:, va:, doj:, excella:, oddball:, agile_six:,
      didit: create(:award, piid: "70SBUR22F00000004", recipient: excella, awarding_agency: dhs,
                    awarding_sub_agency: "U.S. Citizenship and Immigration Services",
                    description: "DIGITAL INNOVATION AND DEVELOPMENT (DID(IT)) II SUPPORT",
                    amount: 65_538_173.03, action_date: TODAY - 20, start_date: TODAY - 20, end_date: TODAY + 60,
                    naics_code: "541512", place_of_performance_state: "VA"),
      fema_cloud: create(:award, recipient: excella, awarding_agency: dhs,
                         awarding_sub_agency: "Federal Emergency Management Agency",
                         description: "CLOUD HOSTING SERVICES", amount: 2_000_000,
                         action_date: TODAY - 100, end_date: TODAY + 400, naics_code: "518210", place_of_performance_state: "DC"),
      va_platform: create(:award, piid: "36C10B22F0126", recipient: oddball, awarding_agency: va,
                          awarding_sub_agency: "Department of Veterans Affairs",
                          description: "VA.GOV PLATFORM AWARD AND OPTIONAL TASK EXERCISE", amount: 71_525_998,
                          action_date: TODAY - 5, end_date: TODAY + 170, naics_code: "541511", place_of_performance_state: "DC"),
      va_cms: create(:award, recipient: agile_six, awarding_agency: va, awarding_sub_agency: "Department of Veterans Affairs",
                     description: "VETERAN-FACING SERVICES CONTENT MANAGEMENT SYSTEM", amount: 8_333_381,
                     action_date: TODAY - 10, end_date: TODAY + 10, naics_code: "541519"),
      va_old: create(:award, recipient: oddball, awarding_agency: va, awarding_sub_agency: "Department of Veterans Affairs",
                     description: "VA.GOV NOTIFY", amount: 8_798_838,
                     action_date: Date.new(2022, 1, 25), end_date: TODAY - 1, naics_code: "541519"),
      doj_small: create(:award, recipient: agile_six, awarding_agency: doj, awarding_sub_agency: "Federal Bureau of Investigation",
                        description: "SOFTWARE LICENSES", amount: 50_000,
                        action_date: TODAY - 2, end_date: TODAY + 30, naics_code: "541519")
    }
  end
end

RSpec.configure do |config|
  config.include QueryFixtures, type: :query
  config.define_derived_metadata(file_path: %r{/spec/queries/}) { |meta| meta[:type] = :query }
end
