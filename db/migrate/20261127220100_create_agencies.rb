class CreateAgencies < ActiveRecord::Migration[8.1]
  def change
    create_table :agencies do |t|
      t.string :toptier_code, null: false
      t.string :name, null: false
      t.string :abbreviation
      t.string :subtier_name

      t.timestamps
    end
    add_index :agencies, :toptier_code, unique: true
  end
end
