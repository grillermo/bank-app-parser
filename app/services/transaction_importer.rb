class TransactionImporter
  PERMITTED = %w[date description bank_name merchant cardname amount category].freeze

  def self.import(batch:, rows:)
    created = 0
    rows.each do |row|
      attrs = row.slice(*PERMITTED)
      next if attrs["date"].blank? || attrs["amount"].nil?
      created += 1 if Transaction.dedup_create!(batch: batch, attrs: attrs)
    end
    Rails.logger.debug("[Import] created #{created} transactions for batch #{batch.id}")
    created
  end
end
