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

RSpec.describe "GET /pending", type: :request do
  it "renders the Pending component with only pending transactions" do
    batch = Batch.create!
    batch.transactions.create!(date: "2025-10-01", description: "pend", amount: -10, status: :pending)
    batch.transactions.create!(date: "2025-10-02", description: "post", amount: -10, status: :posted)

    get "/pending", headers: { "X-Inertia" => "true", "X-Inertia-Version" => ViteRuby.digest }

    expect(response).to have_http_status(:ok)
    json = JSON.parse(response.body)
    expect(json["component"]).to eq("Pending")
    descs = json["props"]["transactions"].map { |t| t["description"] }
    expect(descs).to eq([ "pend" ])
    expect(json["props"]["transactions"].first["status"]).to eq("pending")
  end
end

RSpec.describe "PATCH /transactions/:id", type: :request do
  it "updates a pending transaction to posted" do
    batch = Batch.create!
    t = batch.transactions.create!(date: "2025-10-01", description: "x", amount: -10, status: :pending)

    patch "/transactions/#{t.id}", params: { status: "canceled" }

    expect(response).to have_http_status(:redirect)
    expect(t.reload).to be_canceled
  end

  it "rejects a non-whitelisted status" do
    batch = Batch.create!
    t = batch.transactions.create!(date: "2025-10-01", description: "x", amount: -10, status: :pending)

    patch "/transactions/#{t.id}", params: { status: "pending" }

    expect(response).to have_http_status(:unprocessable_content)
    expect(t.reload).to be_pending
  end
end
