require "rails_helper"

RSpec.describe DashboardStats do
  let(:batch) { Batch.create! }
  before do
    batch.transactions.create!(date: "2025-10-01", description: "A", merchant: "Store1", amount: -100, category: "Food")
    batch.transactions.create!(date: "2025-10-02", description: "B", merchant: "Store2", amount: -300, category: "Shopping")
    batch.transactions.create!(date: "2025-11-01", description: "C", merchant: "Store1", amount: -100, category: "Food")
    batch.transactions.create!(date: "2025-11-02", description: "D", merchant: "Boss",   amount:  500, category: "Income")
  end

  let(:stats) { DashboardStats.new.to_h }

  it "computes top categories with percentages of total spend" do
    cats = stats[:top_categories]
    shopping = cats.find { |c| c[:category] == "Shopping" }
    expect(shopping[:total]).to eq(300.0)
    expect(shopping[:percentage]).to eq(60.0) # 300 of 500 total spend
  end

  it "computes top merchants by spend" do
    expect(stats[:top_merchants].first).to eq({ merchant: "Store2", total: 300.0 })
  end

  it "lists largest single purchases most-negative first" do
    expect(stats[:largest_purchases].first[:amount]).to eq(-300.0)
  end

  it "builds a category timeseries by month" do
    expect(stats[:category_timeseries][:months]).to eq(["2025-10", "2025-11"])
    food = stats[:category_timeseries][:series].find { |s| s[:category] == "Food" }
    expect(food[:data]).to eq([100.0, 100.0])
  end
end
