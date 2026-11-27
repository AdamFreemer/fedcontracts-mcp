class SyncRun < ApplicationRecord
  KINDS = %w[awards end_dates].freeze

  enum :status, { running: "running", succeeded: "succeeded", failed: "failed" }, validate: true

  validates :started_at, presence: true
  validates :kind, inclusion: { in: KINDS }

  scope :awards, -> { where(kind: "awards") }
  scope :end_dates, -> { where(kind: "end_dates") }

  # Finish time of the most recent successful award sync, or nil if none has succeeded.
  def self.data_freshness
    awards.succeeded.maximum(:finished_at)
  end
end
