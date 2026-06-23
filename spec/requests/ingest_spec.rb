require "rails_helper"

RSpec.describe "POST /ingest", type: :request do
  include ActiveJob::TestHelper

  around do |example|
    original_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    example.run
  ensure
    ActiveJob::Base.queue_adapter = original_adapter
  end

  let(:token) { "dev-local-token" }
  before { allow(ENV).to receive(:[]).and_call_original }
  before { allow(ENV).to receive(:[]).with("INGEST_TOKEN").and_return(token) }

  def image
    Rack::Test::UploadedFile.new(StringIO.new("fakebytes"), "image/png", original_filename: "shot.png")
  end

  it "rejects requests without the bearer token" do
    post "/ingest", params: { images: [image] }
    expect(response).to have_http_status(:unauthorized)
  end

  it "accepts an image, creates a batch, enqueues the job, saves the file" do
    expect {
      post "/ingest", params: { image: image },
           headers: { "Authorization" => "Bearer #{token}" }
    }.to have_enqueued_job(IngestJob).and change(Batch, :count).by(1)

    expect(response).to have_http_status(:accepted)
    body = JSON.parse(response.body)
    batch_id = body["batch_id"]
    dir = IngestController.batch_dir(batch_id)
    expect(Dir.glob(dir.join("*.png")).sort).to eq([dir.join("000.png").to_s])
  ensure
    FileUtils.rm_rf(IngestController.batch_dir(body["batch_id"])) if defined?(body) && body
  end
end
