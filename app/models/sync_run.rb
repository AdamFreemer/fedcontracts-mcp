class SyncRun < ApplicationRecord
  enum :status, { running: "running", succeeded: "succeeded", failed: "failed" }, validate: true

  validates :started_at, presence: true

  # Finish time of the most recent successful sync, or nil if none has succeeded.
  def self.data_freshness
    succeeded.maximum(:finished_at)
  end
end
