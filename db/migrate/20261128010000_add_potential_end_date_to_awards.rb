class AddPotentialEndDateToAwards < ActiveRecord::Migration[8.1]
  def change
    # End date if every option is exercised (USAspending award detail only).
    add_column :awards, :potential_end_date, :date
    # When potential_end_date was last fetched; re-fetched when the award changes upstream.
    add_column :awards, :details_checked_at, :datetime
    add_index :awards, :potential_end_date
  end
end
