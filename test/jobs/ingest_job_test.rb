require "test_helper"

class IngestJobTest < ActiveJob::TestCase
  setup do
    FileUtils.rm_rf(Rails.root.join("tmp/ingest"))
    SolidQueue::Job.delete_all
    Batch.delete_all
  end

  teardown do
    FileUtils.rm_rf(Rails.root.join("tmp/ingest"))
  end

  test "does not process superseded scheduled job" do
    batch = Batch.create!(next_image_index: 1)
    job = IngestJob.new(batch.id)
    solid_job = SolidQueue::Job.create!(
      active_job_id: job.job_id,
      class_name: "IngestJob",
      arguments: "{}",
      queue_name: "default",
      priority: 0,
      scheduled_at: Time.current
    )
    batch.update!(scheduled_job_id: "#{solid_job.active_job_id}-superseded")

    with_singleton_stub(ImagePreprocessor, :process, ->(**) { flunk "superseded job should not preprocess images" }) do
      job.perform_now
    end

    assert_predicate batch.reload, :pending?
  end

  test "does not clobber an already completed batch" do
    batch = Batch.create!(status: :completed, next_image_index: 1)

    with_singleton_stub(ImagePreprocessor, :process, ->(**) { flunk "completed batch should not be processed again" }) do
      IngestJob.perform_now(batch.id)
    end

    assert_predicate batch.reload, :completed?
  end

  private

  def with_singleton_stub(object, method_name, replacement)
    singleton = object.singleton_class
    original = object.method(method_name)
    singleton.define_method(method_name, replacement)
    yield
  ensure
    singleton.define_method(method_name, original)
  end
end
