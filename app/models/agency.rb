class Agency < ApplicationRecord
  has_many :awards, foreign_key: :awarding_agency_id, inverse_of: :awarding_agency, dependent: :restrict_with_exception

  validates :toptier_code, presence: true, uniqueness: true
  validates :name, presence: true
end
