require "rails_helper"

RSpec.describe TransactionImporter do
  it "creates deduped transactions and returns count" do
    batch = Batch.create!
    rows = [
      { "date" => "2025-10-12", "description" => "COFFEE", "amount" => -4.5, "merchant" => "SB", "category" => "Food" },
      { "date" => "2025-10-12", "description" => "COFFEE", "amount" => -4.5, "merchant" => "SB", "category" => "Food" }
    ]
    expect(TransactionImporter.import(batch: batch, rows: rows)).to eq(1)
    expect(batch.transactions.count).to eq(1)
  end
end
