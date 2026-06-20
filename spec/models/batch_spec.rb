require "rails_helper"

RSpec.describe Batch do
  it "defaults to pending status" do
    expect(Batch.create!.status).to eq("pending")
  end

  it "supports the full status lifecycle" do
    batch = Batch.create!
    batch.processing!
    batch.completed!
    expect(batch.completed?).to be(true)
  end
end
