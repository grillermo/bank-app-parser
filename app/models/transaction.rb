class Transaction < ApplicationRecord
  belongs_to :batch
  validates :date, :description, :amount, presence: true
  enum :status, { pending: 0, posted: 1, canceled: 2 }

  def self.dedup_create!(batch:, attrs:)
    attrs = attrs.symbolize_keys
    bank_name = attrs[:bank_name] || column_defaults["bank_name"]
    existing = batch.transactions.find_by(
      description: attrs[:description], bank_name: bank_name,
      date: attrs[:date], amount: attrs[:amount]
    )
    if existing
      promote_status!(existing, attrs[:status])
      return nil
    end
    batch.transactions.create!(attrs)
  end

  def self.promote_status!(record, incoming)
    return if incoming.blank?
    incoming = incoming.to_s
    return unless statuses.key?(incoming)
    record.update!(status: incoming) if statuses[incoming] > statuses[record.status]
  end
end
