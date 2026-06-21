require "test_helper"

class IngestControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = "test-token"
    ENV["INGEST_TOKEN"] = @token

    FileUtils.rm_rf(Rails.root.join("tmp/ingest"))
    SolidQueue::Job.delete_all
    Batch.delete_all
  end

  teardown do
    FileUtils.rm_rf(Rails.root.join("tmp/ingest"))
  end

  test "single image upload opens a pending batch and schedules ingestion after inactivity" do
    post "/ingest", params: { image: uploaded_image("first") }, headers: authorization_header

    assert_response :accepted
    batch = Batch.find(response.parsed_body.fetch("batch_id"))
    solid_job = SolidQueue::Job.find_by!(active_job_id: batch.scheduled_job_id)

    assert_predicate batch, :pending?
    assert_equal 1, batch.next_image_index
    assert_in_delta 15.minutes.from_now.to_f, solid_job.scheduled_at.to_f, 2
    assert_path_exists IngestController.batch_dir(batch.id).join("000.png")
  end

  test "subsequent single image appends to pending batch and replaces scheduled ingestion" do
    post "/ingest", params: { image: uploaded_image("first") }, headers: authorization_header
    batch = Batch.find(response.parsed_body.fetch("batch_id"))
    previous_scheduled_job_id = batch.scheduled_job_id

    post "/ingest", params: { image: uploaded_image("second") }, headers: authorization_header

    assert_response :accepted
    batch.reload
    assert_equal batch.id, response.parsed_body.fetch("batch_id")
    assert_equal 2, batch.next_image_index
    assert_not_equal previous_scheduled_job_id, batch.scheduled_job_id
    assert_nil SolidQueue::Job.find_by(active_job_id: previous_scheduled_job_id)
    assert_path_exists IngestController.batch_dir(batch.id).join("001.png")
  end

  test "upload rejects a missing single image" do
    post "/ingest", params: {}, headers: authorization_header
    assert_response :unprocessable_entity

    post "/ingest", params: { image: [ uploaded_image("first"), uploaded_image("second") ] }, headers: authorization_header
    assert_response :unprocessable_entity
  end

  private

  def authorization_header
    { "Authorization" => "Bearer #{@token}" }
  end

  def uploaded_image(name)
    file = Tempfile.new([ name, ".png" ])
    file.binmode
    file.write("png-#{name}")
    file.rewind

    Rack::Test::UploadedFile.new(file.path, "image/png", true)
  end
end
