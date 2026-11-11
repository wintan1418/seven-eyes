# Public Terms of Service, Privacy Policy and account-deletion pages. The
# deletion page is the "delete account" URL given to Google Play and the App
# Store, so it must stay public (no sign-in needed to read it).
class LegalController < ApplicationController
  allow_unauthenticated_access

  PRIVACY_UPDATED_ON = Date.new(2026, 11, 11)
  TERMS_UPDATED_ON = Date.new(2026, 11, 11)

  # Shown on both pages. Set CONTACT_EMAIL in production.
  def self.contact_email = ENV.fetch("CONTACT_EMAIL", "support@bibliorata.com")

  def terms
  end

  def privacy
  end

  def delete_account
  end
end
