# "What's New" — a public, festive tour of the latest features, with animated
# miniature recreations of each one. The topbar badge (whats_new Stimulus
# controller) stops glowing once this page has been seen.
class WhatsNewController < ApplicationController
  allow_unauthenticated_access

  # Bump when a new batch ships — un-dims the topbar badge for everyone.
  VERSION = "2026-06d".freeze

  def show
    @version = VERSION
  end
end
