# Public Terms of Service and Privacy Policy pages.
class LegalController < ApplicationController
  allow_unauthenticated_access

  # Shown on both pages. Set CONTACT_EMAIL in production.
  def self.contact_email = ENV.fetch("CONTACT_EMAIL", "support@bibliorata.com")

  def terms
  end

  def privacy
  end
end
