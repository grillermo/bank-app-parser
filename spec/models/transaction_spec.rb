require "rails_helper"

RSpec.describe Transaction do
  let(:batch) { Batch.create! }
  let(:attrs) do
    { date: "2025-10-12", description: "COFFEE", amount: -4.5,
      bank_name: "unknown", merchant: "Starbucks", cardname: "unknown", category: "Food" }
  end

  it "requires date, description, amount" do
    t = Transaction.new(batch: batch)
    expect(t).not_to be_valid
    expect(t.errors.attribute_names).to include(:date, :description, :amount)
  end

  it "creates a transaction via dedup_create!" do
    expect { Transaction.dedup_create!(batch: batch, attrs: attrs) }
      .to change(Transaction, :count).by(1)
  end

  it "skips duplicates within the same batch" do
    Transaction.dedup_create!(batch: batch, attrs: attrs)
    result = Transaction.dedup_create!(batch: batch, attrs: attrs)
    expect(result).to be_nil
    expect(Transaction.count).to eq(1)
  end

  it "does not treat same description+date+amount as duplicate when bank_name differs" do
    Transaction.dedup_create!(batch: batch, attrs: attrs)
    result = Transaction.dedup_create!(batch: batch, attrs: attrs.merge(bank_name: "chase"))
    expect(result).not_to be_nil
    expect(Transaction.count).to eq(2)
  end

  describe "status enum" do
    it "defaults new records to pending" do
      t = batch.transactions.create!(attrs)
      expect(t).to be_pending
    end

    it "exposes posted and canceled scopes" do
      batch.transactions.create!(attrs.merge(status: :posted, description: "P"))
      batch.transactions.create!(attrs.merge(status: :canceled, description: "C"))
      expect(Transaction.posted.pluck(:description)).to eq(["P"])
      expect(Transaction.canceled.pluck(:description)).to eq(["C"])
    end
  end
end
