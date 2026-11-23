# A study's queue as a service that happens on a day.
#
# The device tells the server the first time anything from the queue goes live
# on a given day (POST /studies/:id/served, through the offline outbox), which
# sets last_served_at. Once that day has passed on the app's calendar
# (DailyWord::TIME_ZONE — there is no per-user time zone yet), the queue is a
# past service: This Sunday stops presenting it as the coming one, and the
# preach console offers to start fresh.
#
#   keep_for_next_service!  "Keep using it" — the queue counts as current again
#                           until it is served on another day
#   start_fresh!            moves the queue into an archived copy ("Service ·
#                           22 Nov 2026") and empties this one, planned for the
#                           coming Sunday; undo_start_fresh! puts it back
#   copy_service!           a new service with the same order (Reuse)
module Study::Serving
  extend ActiveSupport::Concern

  # A late replay from the outbox may name a time a few weeks back; anything
  # older (or in the future, a wrong device clock) counts as "now".
  OLDEST_PING = 45.days

  included do
    belongs_to :archived_from, class_name: "Study", optional: true
    has_many :service_archives, class_name: "Study", foreign_key: :archived_from_id, inverse_of: :archived_from,
                                dependent: :nullify

    scope :archived, -> { where.not(archived_at: nil) }
    scope :unarchived, -> { where(archived_at: nil) }
    # Services that happened, most recent first (archived copies included).
    scope :served, -> { where.not(last_served_at: nil).where(quick_present: false).order(last_served_at: :desc) }
  end

  class_methods do
    # The app's calendar date of a moment (the same calendar as Word for Today).
    def service_date(time = Time.current)
      time.in_time_zone(DailyWord::TIME_ZONE).to_date
    end

    def service_today = service_date

    # The coming Sunday on the app's calendar (today, when it is Sunday).
    def next_sunday(today = service_today) = today + ((7 - today.wday) % 7)

    def service_name(date) = "Service · #{date.strftime('%-d %b %Y')}"
  end

  def archived? = archived_at.present?

  def served_on = last_served_at && Study.service_date(last_served_at)

  # "Keep using it" was chosen after the last time it was served.
  def kept_for_next_service?
    last_served_at.present? && service_kept_at.present? && service_kept_at >= last_served_at
  end

  # Served on an earlier day and not kept: a past service, not this Sunday's.
  def served_before?(today = Study.service_today)
    served_on.present? && served_on < today && !kept_for_next_service?
  end

  # The queue went live at `at`. Only the first time on each calendar day
  # counts (so a whole service is one write), and an older replay never moves
  # the date back. Returns true when it recorded a new service day.
  def mark_served!(at = Time.current)
    return false if quick_present? || archived?
    now = Time.current
    at = now if at.nil? || at > now + 5.minutes || at < now - OLDEST_PING
    at = [ at, now ].min
    with_lock do
      return false if last_served_at && Study.service_date(last_served_at) >= Study.service_date(at)
      update_columns(last_served_at: at)
    end
    true
  end

  def keep_for_next_service!
    update_columns(service_kept_at: Time.current) if last_served_at
  end

  # Start fresh: the queue moves, items and all, into an archived copy named
  # for the day it was served, and this study's queue is empty and no longer
  # "served". `key` is the device's id for this move: replaying it returns the
  # same copy and moves nothing else. nil when there was nothing to move.
  def start_fresh!(key:, served_on: nil)
    raise ArgumentError, "a start-fresh key is required" if key.blank?
    transaction do
      lock!
      existing = Study.find_by(archive_key: key)
      return existing if existing

      unless setlist_items.exists?
        update_columns(last_served_at: nil, service_kept_at: nil)
        return nil
      end

      date = served_on || self.served_on || Study.service_today
      archive = Study.create!(
        user_id: user_id, name: Study.service_name(date), pane_count: 1,
        archived_at: Time.current, archived_from_id: id, archive_key: key,
        last_served_at: last_served_at || Time.zone.local(date.year, date.month, date.day, 12)
      )
      lead = panes.first
      archive.panes.first&.update_columns(reference: lead.reference, translation_id: lead.translation_id) if lead
      setlist_items.update_all(study_id: archive.id, updated_at: Time.current)
      update_columns(last_served_at: nil, service_kept_at: nil, planned_for: Study.next_sunday, updated_at: Time.current)
      archive
    end
  end

  # Undo a start fresh: the archived items come back to the top of this queue
  # (anything added since stays after them), with the served date, and the
  # copy goes away. Idempotent: an unknown or already undone key does nothing.
  def undo_start_fresh!(key)
    transaction do
      lock!
      archive = service_archives.find_by(archive_key: key.to_s)
      return false unless archive

      moved = archive.setlist_items.count
      setlist_items.update_all([ "position = position + ?", moved ]) if moved.positive?
      archive.setlist_items.update_all(study_id: id, updated_at: Time.current)
      if archive.last_served_at && (last_served_at.nil? || last_served_at < archive.last_served_at)
        update_columns(last_served_at: archive.last_served_at)
      end
      archive.setlist_items.reset
      archive.destroy!
      true
    end
  end

  # A new service with this queue's order (Home's "Reuse last Sunday's
  # order", Past services' "Reuse"). Items that no longer validate are skipped.
  def copy_service!(name: nil, planned_for: Study.next_sunday)
    raise ActiveRecord::RecordNotFound unless user
    transaction do
      copy = user.studies.create!(name: name || Study.service_name(planned_for), pane_count: 1, planned_for: planned_for)
      lead = panes.first
      copy.panes.first&.update(reference: lead.reference, translation_id: lead.translation_id) if lead
      setlist_items.in_order.includes(picture_file_attachment: :blob).each do |item|
        dup = item.dup
        dup.assign_attributes(study: copy, client_id: nil) # position: renumbered on create
        dup.picture_file.attach(item.picture_file.blob) if item.picture_file.attached?
        dup.save
      end
      copy
    end
  end
end
