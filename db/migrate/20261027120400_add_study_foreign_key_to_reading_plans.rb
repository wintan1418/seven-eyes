# reading_plans.study_id had no foreign key, so deleting a study left plans
# pointing at a missing row. Clear the dangling ids, index the column, and let
# the database null it out whenever the study is deleted.
class AddStudyForeignKeyToReadingPlans < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      UPDATE reading_plans SET study_id = NULL
       WHERE study_id IS NOT NULL
         AND NOT EXISTS (SELECT 1 FROM studies WHERE studies.id = reading_plans.study_id)
    SQL
    add_index :reading_plans, :study_id unless index_exists?(:reading_plans, :study_id)
    add_foreign_key :reading_plans, :studies, on_delete: :nullify
  end

  def down
    remove_foreign_key :reading_plans, :studies
    remove_index :reading_plans, :study_id if index_exists?(:reading_plans, :study_id)
  end
end
