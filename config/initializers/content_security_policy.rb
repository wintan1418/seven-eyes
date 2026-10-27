# Be sure to restart your server when you modify this file.
#
# Content Security Policy. Shipped in REPORT-ONLY mode: browsers log
# violations to the console but block nothing. Set CSP_ENFORCE=true to enforce
# once you've browsed the whole app (studies, preach mode, output/stage
# windows, live follow, remote, share cards, testimonials) with the console
# open and seen no violations.
#
# Known blocker before enforcing: app/views/studies/sermon.html.erb uses an
# inline onclick="window.print()" which an enforced policy will block — move
# it to a Stimulus action first.
#
# What the app actually loads (audited Oct 2026):
#   scripts  — our esbuild bundle + the testimonials widget.js, both same-origin
#              (the widget gets the per-request nonce). No inline <script>s.
#   styles   — same-origin CSS + Google Fonts CSS; many views/JS set inline
#              style attributes, so style-src keeps 'unsafe-inline'.
#   fonts    — fonts.gstatic.com
#   images   — same-origin, data: (AI illustrations, QR codes), blob: (share
#              cards), and https: (setlist pictures on Cloudinary / pasted URLs)
#   media    — Audio Bible mp3s via the same-origin Active Storage proxy
#   connect  — fetch() to our own JSON endpoints + Action Cable websockets
Rails.application.configure do
  ws_hosts = (ENV["APP_HOSTS"].to_s.split(",").map(&:strip).reject(&:empty?).presence ||
              %w[ bibliorata.com www.bibliorata.com ]).map { |host| "wss://#{host}" }

  config.content_security_policy do |policy|
    policy.default_src :self
    policy.base_uri    :self
    policy.form_action :self
    policy.frame_ancestors :self
    policy.object_src  :none
    policy.script_src  :self
    policy.style_src   :self, :unsafe_inline, "https://fonts.googleapis.com"
    policy.font_src    :self, :data, "https://fonts.gstatic.com"
    policy.img_src     :self, :data, :blob, :https
    policy.media_src   :self, :data, :blob
    policy.connect_src :self, *ws_hosts, *(Rails.env.development? ? %w[ ws://localhost:3000 ws://127.0.0.1:3000 ] : [])
    policy.worker_src  :self, :blob
    policy.manifest_src :self
  end

  # A fresh random nonce per request for script-src only (a nonce in style-src
  # would switch off its 'unsafe-inline'). Turbo reads it from csp_meta_tag.
  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[ script-src ]
  config.content_security_policy_nonce_auto = true

  config.content_security_policy_report_only = !ActiveModel::Type::Boolean.new.cast(ENV["CSP_ENFORCE"])
end
