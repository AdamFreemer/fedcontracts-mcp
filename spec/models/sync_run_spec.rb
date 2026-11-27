require "rails_helper"

RSpec.describe SyncRun do
  it "defaults to running" do
    expect(SyncRun.new(started_at: Time.current)).to be_running
  end

  it "rejects unknown statuses" do
    expect(build(:sync_run, status: "bogus")).not_to be_valid
  end

  it "requires started_at" do
    expect(build(:sync_run, started_at: nil)).not_to be_valid
  end

  describe ".data_freshness" do
    it "is nil when no sync has succeeded" do
      create(:sync_run)
      create(:sync_run, :failed)
      expect(SyncRun.data_freshness).to be_nil
    end

    it "returns the latest successful finish time, ignoring failed runs" do
      create(:sync_run, :succeeded, finished_at: 2.days.ago)
      latest = create(:sync_run, :succeeded, finished_at: 1.day.ago)
      create(:sync_run, :failed, finished_at: 1.hour.ago)
      expect(SyncRun.data_freshness).to be_within(1.second).of(latest.finished_at)
    end
  end
end
