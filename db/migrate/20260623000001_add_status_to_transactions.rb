class AddStatusToTransactions < ActiveRecord::Migration[8.1]
  def up
    add_column :transactions, :status, :integer, null: false, default: 0
    # existing rows were all charges -> posted (1)
    execute "UPDATE transactions SET status = 1"
    add_index :transactions, :status
  end

  def down
    remove_column :transactions, :status
  end
end
