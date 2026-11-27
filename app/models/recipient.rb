class Recipient < ApplicationRecord
  has_many :awards, dependent: :restrict_with_exception

  validates :recipient_key, presence: true, uniqueness: true
  validates :name, presence: true
end
