class CreateNotificationHistories < ActiveRecord::Migration[8.0]
  def change
    create_table :notification_histories, id: :uuid do |t|
      t.string :notification_type, null: false
      t.string :title, null: false
      t.text :message, null: false
      t.integer :priority, default: 5, null: false
      t.string :status, default: 'pending', null: false
      t.integer :gotify_message_id
      t.jsonb :metadata, default: {}
      t.text :error_message
      t.datetime :sent_at

      t.timestamps
    end

    add_index :notification_histories, :notification_type
    add_index :notification_histories, :status
    add_index :notification_histories, :sent_at
    add_index :notification_histories, :created_at
  end
end
