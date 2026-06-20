class CreateBatches < ActiveRecord::Migration[8.0]
  def change
    create_table :batches do |t|
      t.integer :status, null: false, default: 0
      t.text :error_message
      t.timestamps
    end
  end
end
