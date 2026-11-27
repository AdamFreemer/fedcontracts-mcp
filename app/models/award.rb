class Award < ApplicationRecord
  belongs_to :recipient
  belongs_to :awarding_agency, class_name: "Agency", inverse_of: :awards

  validates :generated_internal_id, presence: true, uniqueness: true

  def usaspending_url
    "https://www.usaspending.gov/award/#{generated_internal_id}"
  end
end
