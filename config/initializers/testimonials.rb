# frozen_string_literal: true

# Self-hosted testimonials (the `testimonials` gem). Collection widget +
# public /testimonials/new page; triage dashboard at /testimonials is
# admin-only. Video/avatars stay off — this app has no Active Storage.
Testimonials.configure do |config|
  config.app_name = "BiblioRata"

  # Resolve the signed-in user from our Rails 8 auth session cookie
  # (Authentication concern stores the Session id in a signed cookie).
  resolve_user = lambda do |request|
    session_id = request.cookie_jar.signed[:session_id]
    Session.active.find_by(id: session_id)&.user if session_id
  end

  config.current_user = resolve_user
  config.authorize_admin = ->(request) { resolve_user.call(request)&.admin? }

  config.user_display = lambda do |user|
    { name: user.email_address.to_s.split("@").first, email: user.email_address }
  end

  config.questions = [
    "How has %{app} served your study — or your pulpit?",
    "What should a fellow pastor or reader know about it?"
  ]

  # No Active Storage in this app — text testimonials only.
  config.video = false
  config.avatars = false

  # Gentle: at most 2 automatic prompts, half a year apart. A user who
  # clicks the "leave a testimonial" link is never throttled.
  config.reprompt_after = 180.days
  config.max_prompts = 2

  # Public collection page stays on (shareable link for reviewers);
  # the read API stays admin-only — the welcome page renders server-side.
  config.public_api = false
  config.rate_limit = { to: 5, within: 1.minute }
end
