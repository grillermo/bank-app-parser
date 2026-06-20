class Transaction < ApplicationRecord
  belongs_to :batch
  validates :date, :description, :amount, presence: true

  def self.dedup_create!(batch:, attrs:)
    attrs = attrs.symbolize_keys
    return nil if batch.transactions.exists?(
      date: attrs[:date], description: attrs[:description], amount: attrs[:amount]
    )
    batch.transactions.create!(attrs)
  end
end
