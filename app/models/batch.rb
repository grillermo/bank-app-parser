class Batch < ApplicationRecord
  enum :status, { pending: 0, processing: 1, completed: 2, failed: 3 }

  INGEST_DELAY = 15.minutes
  MAX_IMAGES = 15

  has_many :transactions, dependent: :destroy

  def self.open_for_ingest
    pending.first_or_create!
  rescue ActiveRecord::RecordNotUnique
    pending.first!
  end

  def append_image!(bytes)
    with_lock do
      raise FullBatchError if next_image_index >= MAX_IMAGES

      dir = IngestController.batch_dir(id)
      FileUtils.mkdir_p(dir)
      File.binwrite(dir.join(format("%03d.png", next_image_index)), bytes)

      increment!(:next_image_index)
      reschedule_ingest!
    end
  end

  def fail!(message)
    update!(status: :failed, error_message: message)
  end

  private

  def reschedule_ingest!
    return unless discard_scheduled_ingest

    job = IngestJob.set(wait: INGEST_DELAY).perform_later(id)

    update!(scheduled_job_id: job.job_id)
  end

  def discard_scheduled_ingest
    SolidQueue::Job.find_by(active_job_id: scheduled_job_id)&.discard
    true
  rescue SolidQueue::Execution::UndiscardableError
    false
  end

  class FullBatchError < StandardError; end
end
