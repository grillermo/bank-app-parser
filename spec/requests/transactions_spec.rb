require "rails_helper"

RSpec.describe "GET /transactions", type: :request do
  it "renders the Transactions Inertia component with paginated transactions" do
    batch = Batch.create!
    60.times do |i|
      batch.transactions.create!(date: "2025-10-01", description: "Tx #{i}", merchant: "Store", amount: -10)
    end

    get "/transactions", headers: { "X-Inertia" => "true", "X-Inertia-Version" => ViteRuby.digest }

    expect(response).to have_http_status(:ok)
    json = JSON.parse(response.body)
    expect(json["component"]).to eq("Transactions")
    expect(json["props"]["transactions"].size).to eq(50)
    expect(json["props"]["next_cursor"]).to be_present

    get "/transactions", params: { cursor: json["props"]["next_cursor"] },
      headers: { "X-Inertia" => "true", "X-Inertia-Version" => ViteRuby.digest }

    json = JSON.parse(response.body)
    expect(json["props"]["transactions"].size).to eq(10)
    expect(json["props"]["next_cursor"]).to be_nil
  end
end
