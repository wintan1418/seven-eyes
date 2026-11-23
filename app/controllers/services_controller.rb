# Services: a study's queue as something that happened on a day (Study::Serving).
#
#   GET  /services                          Past services — reopen or reuse one
#   POST /services                          plan the coming Sunday: an empty service,
#                                           or a copy of an old one's order (from:)
#   POST /studies/:study_id/service/served  the queue went live (the device sends
#                                           this once a day, through the outbox)
#   POST /studies/:study_id/service/keep    "Keep using it"
#   POST /studies/:study_id/service/start_fresh  archive the served queue, empty it
#   POST /studies/:study_id/service/undo    undo that start fresh
#
# Accounts only: a guest's queue has no Sundays to plan (401 for JSON).
class ServicesController < ApplicationController
  allow_unauthenticated_access only: %i[ served keep start_fresh undo ]
  before_action :require_account, only: %i[ served keep start_fresh undo ]
  before_action :set_study, only: %i[ served keep start_fresh undo ]

  PAST_LIMIT = 60

  def index
    today = Study.service_today
    @services = current_user.studies.served.where(last_served_at: ...service_day_start(today))
                            .limit(PAST_LIMIT).to_a
    @counts = SetlistItem.where(study_id: @services.map(&:id)).group(:study_id).count
    @studies = current_user.studies.shelf.recent.limit(30)
  end

  def create
    planned_for = Study.next_sunday
    study =
      if params[:from].present?
        current_user.studies.find(params[:from]).copy_service!(planned_for:)
      else
        current_user.studies.create!(name: Study.service_name(planned_for), pane_count: 1, planned_for:)
      end
    redirect_to study_path(study, queue: 1)
  end

  # {at: ISO time it first went live} → {served_on, recorded}
  def served
    at = Time.zone.parse(params[:at].to_s) rescue nil
    recorded = @study.mark_served!(at || Time.current)
    render json: { served_on: @study.served_on&.iso8601, recorded: recorded }
  end

  def keep
    @study.keep_for_next_service!
    render json: { kept: @study.kept_for_next_service? }
  end

  # {key: the device's id for this move, served_on: "2026-11-22"}
  def start_fresh
    key = params[:key].to_s
    return render(json: { error: "key required" }, status: :unprocessable_entity) unless key.match?(/\A[\w-]{8,64}\z/)
    served_on = Date.iso8601(params[:served_on].to_s) rescue nil
    archive = @study.start_fresh!(key:, served_on:)
    render json: { archive_id: archive&.id, archive_url: archive && study_path(archive), name: archive&.name,
                   server_time: (Time.current.to_f * 1000).to_i }
  end

  def undo
    restored = @study.undo_start_fresh!(params[:key].to_s)
    render json: { restored: restored, items: @study.setlist_items.in_order.map(&:as_queue_json),
                   server_time: (Time.current.to_f * 1000).to_i }
  end

  private

  def set_study
    @study = current_user.studies.unarchived.find(params[:study_id])
  end

  def require_account
    head :unauthorized unless authenticated?
  end

  def service_day_start(day) = day.in_time_zone(DailyWord::TIME_ZONE).beginning_of_day
end
