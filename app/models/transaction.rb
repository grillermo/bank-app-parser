class Transaction < ApplicationRecord
  belongs_to :batch
  validates :date, :description, :amount, presence: true

  def self.dedup_create!(batch:, attrs:)
    attrs = attrs.symbolize_keys
    bank_name = attrs[:bank_name] || column_defaults["bank_name"]
    return nil if batch.transactions.exists?(
      description: attrs[:description], bank_name: bank_name,
      date: attrs[:date], amount: attrs[:amount]
    )
    batch.transactions.create!(attrs)
  end
end
