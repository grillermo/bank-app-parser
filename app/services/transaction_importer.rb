class TransactionImporter
  PERMITTED = %w[date description bank_name merchant cardname amount category status].freeze
  VALID_STATUSES = %w[pending posted canceled].freeze

  def self.import(batch:, rows:)
    created = 0
    rows.each do |row|
      attrs = row.slice(*PERMITTED)
      next if attrs["date"].blank? || attrs["amount"].nil?
      attrs["status"] = "pending" unless VALID_STATUSES.include?(attrs["status"])
      created += 1 if Transaction.dedup_create!(batch: batch, attrs: attrs)
    end
    Rails.logger.debug("[Import] created #{created} transactions for batch #{batch.id}")
    created
  end
end
