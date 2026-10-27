# Error monitoring. Entirely inert unless SENTRY_DSN is set in the environment.
if ENV["SENTRY_DSN"].present?
  Sentry.init do |config|
    config.dsn = ENV["SENTRY_DSN"]
    config.environment = ENV.fetch("SENTRY_ENVIRONMENT", Rails.env)
    config.breadcrumbs_logger = %i[ active_support_logger http_logger ]
    # Errors only by default; opt in to performance tracing with a sample rate.
    config.traces_sample_rate = ENV.fetch("SENTRY_TRACES_SAMPLE_RATE", 0).to_f
    # Never ship user emails, IPs, cookies or request bodies (study notes, AI
    # prompts) to a third party.
    config.send_default_pii = false
  end
end
