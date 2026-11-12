# Quick Present: every signed-in user has one always-ready study the device
# keeps offline (lib/offline/ready.js), so "New study" / "Present offline"
# with no internet opens straight into preach mode instead of a dead end.
#
#   QuickPresent.ensure!(user) # => the user's Quick Present study (created once)
#
# Idempotent: one per user (partial unique index on studies.user_id where
# quick_present), safe against two tabs asking at once. An existing study is
# left as the presenter last used it — only a missing translation is filled in.
class QuickPresent
  NAME = "Quick Present".freeze
  REFERENCE = "John 3".freeze

  def self.ensure!(user) = new(user).ensure!

  def initialize(user)
    @user = user
  end

  def ensure!
    study = @user.studies.find_by(quick_present: true) || create!
    pane = study.panes.first
    pane.update!(translation: default_translation) if pane && pane.translation_id.nil? && default_translation
    study
  end

  # The translation the user reads in most: their latest study's first pane,
  # else the site default (KJV).
  def default_translation
    @default_translation ||= begin
      latest = @user.studies.where(quick_present: false).recent.first
      chosen = latest&.panes&.first&.translation
      chosen&.available? ? chosen : Translation.default
    end
  end

  private

  def create!
    Study.transaction(requires_new: true) do
      @user.studies.create!(name: NAME, pane_count: 1, quick_present: true).tap do |study|
        study.panes.first&.update!(reference: REFERENCE, translation: default_translation)
      end
    end
  rescue ActiveRecord::RecordNotUnique
    @user.studies.find_by!(quick_present: true)
  end
end
