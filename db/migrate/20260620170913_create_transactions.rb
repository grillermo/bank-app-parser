class CreateTransactions < ActiveRecord::Migration[8.0]
  def change
    create_table :transactions do |t|
      t.references :batch, null: false, foreign_key: true
      t.date :date, null: false
      t.string :description, null: false
      t.string :bank_name, default: "unknown"
      t.string :merchant, default: "unknown"
      t.string :cardname, default: "unknown"
      t.decimal :amount, precision: 12, scale: 2, null: false
      t.string :category, default: "unknown"
      t.timestamps
    end
  end
end
