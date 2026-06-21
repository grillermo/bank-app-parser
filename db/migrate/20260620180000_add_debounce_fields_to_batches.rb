class AddDebounceFieldsToBatches < ActiveRecord::Migration[8.0]
  def change
    add_column :batches, :next_image_index, :integer, null: false, default: 0
    add_column :batches, :scheduled_job_id, :string

    add_index :batches, :scheduled_job_id
    add_index :batches, :status, unique: true, where: "status = 0", name: "index_batches_on_pending_status"
  end
end
