require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # The public hostnames this app answers to. Override with APP_HOSTS
  # (comma-separated, first one is canonical) for staging or a new domain.
  app_hosts = ENV["APP_HOSTS"].to_s.split(",").map(&:strip).reject(&:empty?).presence ||
              %w[ bibliorata.com www.bibliorata.com ]

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Store uploaded files on the local file system (see config/storage.yml for options).
  config.active_storage.service = :local

  # Assume all access to the app is happening through a SSL-terminating reverse proxy.
  config.assume_ssl = true

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  config.force_ssl = true

  # Skip http-to-https redirect for the default health check endpoint.
  config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Change to "debug" to log everything (including potentially personally-identifiable information!).
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # DB-backed cache shared by every Puma worker, so rate limits, the AI spend
  # guards (AiBudget) and cached AI answers hold across processes and restarts.
  # Hatchbox-style deploys only run `db:migrate` for the primary schema, so the
  # solid_cache_entries table lives in the PRIMARY database (see migration
  # CreateSolidCacheEntries) and config/cache.yml names no separate `cache` db.
  config.cache_store = :solid_cache_store

  # Active Job: Solid Queue only when a worker actually runs it — config/puma.rb
  # starts the supervisor in-process when SOLID_QUEUE_IN_PUMA is set, and its
  # tables live in the primary DB (migration CreateSolidQueueTables). Without
  # that env var we stay on the in-process :async adapter rather than enqueue
  # jobs nobody will ever run.
  config.active_job.queue_adapter = ENV["SOLID_QUEUE_IN_PUMA"].present? ? :solid_queue : :async

  # Action Cable powers Go Live and the phone remote. HTTPS origins only.
  config.action_cable.allowed_request_origins = app_hosts.map { |host| "https://#{host}" }

  # Set host to be used by links generated in mailer templates.
  config.action_mailer.default_url_options = { host: app_hosts.first, protocol: "https" }

  # Outgoing mail (password resets) over SMTP, configured from the environment:
  # SMTP_ADDRESS, SMTP_PORT (default 587), SMTP_USERNAME, SMTP_PASSWORD.
  # Without SMTP_ADDRESS no mail is sent and delivery errors aren't raised.
  if ENV["SMTP_ADDRESS"].present?
    config.action_mailer.delivery_method = :smtp
    config.action_mailer.raise_delivery_errors = true
    config.action_mailer.smtp_settings = {
      address: ENV["SMTP_ADDRESS"],
      port: ENV.fetch("SMTP_PORT", 587).to_i,
      user_name: ENV["SMTP_USERNAME"].presence,
      password: ENV["SMTP_PASSWORD"].presence,
      authentication: (ENV["SMTP_USERNAME"].present? ? :plain : nil),
      enable_starttls_auto: true
    }.compact
  else
    config.action_mailer.raise_delivery_errors = false
  end

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # Enable DNS rebinding protection and other `Host` header attacks — only once
  # APP_HOSTS is set on the host, so a deploy can never lock out a hostname
  # (e.g. a Hatchbox/Caddy domain) we didn't know about.
  config.hosts = app_hosts if ENV["APP_HOSTS"].present?

  # Skip DNS rebinding protection for the default health check endpoint.
  config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
end
