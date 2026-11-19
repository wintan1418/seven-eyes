# Runs one AiRequest (Quick Find, the Rabbi, an illustration) off the web
# server. In production this goes to Solid Queue — the separate
# biblio-compass-solid_queue service (bin/jobs) works it — so a 20–40 s model
# call never holds one of Puma's few threads. The rest of the app still uses the
# in-process :async adapter (see config/environments/production.rb).
#
# Never retried: every attempt is a paid call, and the page offers Retry.
class AiRequestJob < ApplicationJob
  queue_as :ai
  # AI_JOB_ADAPTER=solid_queue runs it the production way locally (with bin/jobs).
  adapter = ENV["AI_JOB_ADAPTER"].presence || ("solid_queue" if Rails.env.production?)
  self.queue_adapter = adapter.to_sym if adapter

  discard_on ActiveJob::DeserializationError

  def perform(ai_request_id)
    AiRequest.find_by(id: ai_request_id)&.perform!
  end
end
