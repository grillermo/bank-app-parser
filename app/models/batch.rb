class Batch < ApplicationRecord
  enum :status, { pending: 0, processing: 1, completed: 2, failed: 3 }
  has_many :transactions, dependent: :destroy

  def fail!(message)
    update!(status: :failed, error_message: message)
  end
end
