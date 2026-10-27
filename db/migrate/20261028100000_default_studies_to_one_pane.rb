# The reader opens on one passage, like a Bible app; comparing translations
# side by side is opt-in (Compare). New studies default to one pane, and
# existing studies whose extra panes were never used (blank references) are
# collapsed to one. Nothing is deleted: hidden panes keep their notes and come
# back when Compare is turned on again.
class DefaultStudiesToOnePane < ActiveRecord::Migration[8.1]
  def up
    change_column_default :studies, :pane_count, from: 4, to: 1

    execute <<~SQL
      UPDATE studies SET pane_count = 1
      WHERE pane_count > 1
        AND NOT EXISTS (
          SELECT 1 FROM panes
          WHERE panes.study_id = studies.id
            AND panes.position BETWEEN 1 AND 3
            AND panes.position < studies.pane_count
            AND (COALESCE(TRIM(panes.reference), '') <> '' OR COALESCE(TRIM(panes.notes), '') <> '')
        )
    SQL
  end

  def down
    change_column_default :studies, :pane_count, from: 1, to: 4
  end
end
