class IngestJob < ApplicationJob
  queue_as :default

  def perform(batch_id)
    # Implemented in Task 9.
  end
end
