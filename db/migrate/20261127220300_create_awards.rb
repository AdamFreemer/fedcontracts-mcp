class CreateAwards < ActiveRecord::Migration[8.1]
  def change
    create_table :awards do |t|
      t.string :generated_internal_id, null: false
      t.string :piid
      t.references :recipient, null: false, foreign_key: true
      t.references :awarding_agency, null: false, foreign_key: { to_table: :agencies }
      t.string :awarding_sub_agency
      t.text :description
      t.decimal :amount, precision: 15, scale: 2
      t.date :start_date
      t.date :end_date
      t.date :action_date
      t.string :naics_code
      t.string :naics_description
      t.string :psc_code
      t.string :place_of_performance_state
      t.jsonb :raw, null: false, default: {}

      t.timestamps
    end
    add_index :awards, :generated_internal_id, unique: true
    add_index :awards, :end_date
    add_index :awards, :start_date
    add_index :awards, :action_date
    add_index :awards, :naics_code
    add_index :awards, :description, using: :gin, opclass: :gin_trgm_ops
  end
end
