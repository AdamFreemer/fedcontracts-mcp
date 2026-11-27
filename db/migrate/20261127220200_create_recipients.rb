class CreateRecipients < ActiveRecord::Migration[8.1]
  def change
    create_table :recipients do |t|
      # Upsert key: USAspending recipient ID when present, else normalized name.
      t.string :recipient_key, null: false
      t.string :usaspending_recipient_id
      t.string :name, null: false
      t.string :uei
      t.string :parent_name
      t.string :city
      t.string :state
      t.string :country

      t.timestamps
    end
    add_index :recipients, :recipient_key, unique: true
    add_index :recipients, :usaspending_recipient_id
    add_index :recipients, :uei
  end
end
