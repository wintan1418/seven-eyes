# Collects the pictures already in signed-in users' services into their
# My Media libraries (MediaBackfill: idempotent, batched, no file is read or
# uploaded again — the library entry reuses the queue item's blob or URL).
# Safe to re-run any time: `bin/rails media:backfill`.
class BackfillMediaAssets < ActiveRecord::Migration[8.1]
  disable_ddl_transaction! # each batch commits by itself

  def up
    SetlistItem.reset_column_information
    MediaAsset.reset_column_information
    stats = MediaBackfill.run
    say "My Media backfill: #{stats.inspect}"
  end

  def down
    # Nothing to undo: rolling back CreateMediaAssets drops the libraries.
  end
end
