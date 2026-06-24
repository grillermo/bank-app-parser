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

  it "passes through a valid status" do
    batch = Batch.create!
    rows = [{ "date" => "2025-10-12", "description" => "X", "amount" => -1.0, "status" => "canceled" }]
    TransactionImporter.import(batch: batch, rows: rows)
    expect(batch.transactions.first).to be_canceled
  end

  it "coerces an unknown or blank status to pending" do
    batch = Batch.create!
    rows = [
      { "date" => "2025-10-12", "description" => "Y", "amount" => -1.0, "status" => "weird" },
      { "date" => "2025-10-13", "description" => "Z", "amount" => -2.0 }
    ]
    TransactionImporter.import(batch: batch, rows: rows)
    expect(batch.transactions.pluck(:status).uniq).to eq(["pending"])
  end
end
