require "rails_helper"

RSpec.describe "GET /", type: :request do
  it "renders the Dashboard Inertia component with stats props" do
    batch = Batch.create!
    batch.transactions.create!(date: "2025-10-01", description: "A", merchant: "Store1", amount: -100, category: "Food")

    get "/", headers: { "X-Inertia" => "true", "X-Inertia-Version" => ViteRuby.digest }

    expect(response).to have_http_status(:ok)
    json = JSON.parse(response.body)
    expect(json["component"]).to eq("Dashboard")
    expect(json["props"]).to have_key("top_categories")
    expect(json["props"]).to have_key("category_timeseries")
  end
end
