# IP-level throttles in front of the app (Rack::Attack). They complement the
# per-user `rate_limit`s in the controllers: these stop a single address from
# hammering sign-in, sign-up, password reset, study creation and the paid AI
# endpoints regardless of which (or how many) accounts it uses.
#
# Counters live in Rails.cache (Solid Cache in production — shared across Puma
# workers). In test the cache is :null_store, so throttles are inert unless a
# test swaps in a real store (see test/integration/rack_attack_test.rb).
class Rack::Attack
  AI_PATH = %r{\A/studies/\d+/(rabbi|rabbi_diagram|rabbi_illustration|suggest|quick_find|prayer)(\.json)?\z}

  # Normalised email from a form post, for per-account throttles.
  def self.email_param(req)
    req.params["email_address"].to_s.downcase.strip.presence
  end

  # --- sign in --------------------------------------------------------------
  throttle("logins/ip", limit: 20, period: 5.minutes) do |req|
    req.ip if req.post? && req.path == "/session"
  end

  throttle("logins/email", limit: 10, period: 15.minutes) do |req|
    email_param(req) if req.post? && req.path == "/session"
  end

  # --- sign up --------------------------------------------------------------
  throttle("registrations/ip", limit: 10, period: 1.hour) do |req|
    req.ip if req.post? && req.path == "/registration"
  end

  # --- password reset -------------------------------------------------------
  throttle("password_resets/ip", limit: 5, period: 15.minutes) do |req|
    req.ip if req.post? && req.path == "/passwords"
  end

  throttle("password_resets/email", limit: 3, period: 1.hour) do |req|
    email_param(req) if req.post? && req.path == "/passwords"
  end

  # --- creating studies (guests can) ----------------------------------------
  throttle("studies/create/ip", limit: 60, period: 10.minutes) do |req|
    req.ip if req.post? && req.path == "/studies"
  end

  # --- paid AI endpoints ----------------------------------------------------
  # Generous enough for a church on one NAT'd address; the per-user limits and
  # the global AiBudget backstop do the fine-grained work.
  throttle("ai/ip", limit: 40, period: 1.minute) do |req|
    req.ip if AI_PATH.match?(req.path)
  end

  self.throttled_responder = lambda do |req|
    match = req.env["rack.attack.match_data"] || {}
    retry_after = (match[:period] || 60).to_i
    [ 429, { "content-type" => "text/plain", "retry-after" => retry_after.to_s },
      [ "Too many requests. Please wait a moment and try again.\n" ] ]
  end
end
