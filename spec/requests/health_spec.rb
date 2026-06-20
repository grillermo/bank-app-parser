require "rails_helper"

RSpec.describe "GET /health", type: :request do
  before { allow(ENV).to receive(:[]).and_call_original }

  it "returns 200 when all dependencies are healthy" do
    allow(ENV).to receive(:[]).with("OPENAI_API_KEY").and_return("sk-x")
    get "/health"
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)["status"]).to eq("ok")
  end

  it "returns 503 when OPENAI_API_KEY is missing" do
    allow(ENV).to receive(:[]).with("OPENAI_API_KEY").and_return(nil)
    get "/health"
    expect(response).to have_http_status(:service_unavailable)
    expect(JSON.parse(response.body)["checks"]["openai_key"]).to eq(false)
  end
end
