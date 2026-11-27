class AddTrigramIndexToRecipientNames < ActiveRecord::Migration[8.1]
  def change
    add_index :recipients, :name, using: :gin, opclass: :gin_trgm_ops, name: "index_recipients_on_name_trgm"
  end
end
