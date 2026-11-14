# Pastor mode: "This Sunday" leads Home. nil = decide from what the account
# does (anyone who has lined up a service or gone live gets it); true/false =
# the reader's own choice from More.
class AddPastorModeToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :pastor_mode, :boolean
  end
end
