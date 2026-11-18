# frozen_string_literal: true

# /give: support BiblioRata through Paystack. Only admins can see the page
# until DONATIONS_PUBLIC=1 is set; payments start once PAYSTACK_SECRET_KEY is set.
class GivingController < ApplicationController
  allow_unauthenticated_access
  skip_forgery_protection only: :webhook
  before_action :require_giving_visible, except: :webhook
  # The offline cache fetches several pages at once on a first visit, which can
  # replace the session's form token; show the form again rather than an error.
  rescue_from ActionController::InvalidAuthenticityToken, with: :ask_to_give_again

  def self.public? = ENV["DONATIONS_PUBLIC"] == "1"

  def show
    @donation = Donation.new(currency: "NGN", frequency: :one_time, email: viewer&.email_address)
    @donation.amount_major = 5_000
  end

  def create
    unless Paystack.configured?
      redirect_to give_path, notice: "Giving opens soon. Thank you for wanting to help."
      return
    end

    @donation = Donation.new(donation_params.merge(user: viewer))
    @donation.email = viewer.email_address if @donation.email.blank? && viewer
    unless @donation.save
      render :show, status: :unprocessable_entity
      return
    end

    redirect_to @donation.checkout_url(callback_url: give_thanks_url), allow_other_host: true
  rescue Paystack::Error => e
    Rails.logger.warn("[Giving] checkout failed for #{@donation&.reference}: #{e.message}")
    @donation.update_column(:status, "failed") if @donation&.persisted?
    flash.now[:alert] = "We couldn't reach the payment service just now. Please try again in a moment."
    render :show, status: :unprocessable_entity
  end

  # Paystack sends the giver back here with ?reference=…
  def thanks
    @donation = Donation.find_by(reference: params[:reference].to_s.presence || params[:trxref].to_s)
    if @donation&.pending? && Paystack.configured?
      @donation.settle_from(Paystack.get("/transaction/verify/#{ERB::Util.url_encode(@donation.reference)}"))
    end
  rescue Paystack::Error => e
    Rails.logger.warn("[Giving] verify failed for #{@donation&.reference}: #{e.message}")
  end

  # Paystack's server tells us about payments, including monthly renewals.
  def webhook
    raw = request.raw_post
    return head(:unauthorized) unless Paystack.valid_signature?(raw, request.headers["X-Paystack-Signature"])

    event = JSON.parse(raw) rescue {}
    Donation.record_payment!(event["data"]) if event["event"] == "charge.success" && event["data"].is_a?(Hash)
    head :ok
  end

  private

  def viewer = authenticated? ? current_user : nil

  def require_giving_visible
    return if self.class.public?
    return if viewer&.admin?
    redirect_to root_path, alert: "That page isn't available."
  end

  def ask_to_give_again
    return require_giving_visible unless self.class.public? || viewer&.admin?
    @donation = Donation.new(donation_params) rescue Donation.new(currency: "NGN")
    @donation.email ||= viewer&.email_address
    flash.now[:alert] = "Please check your gift and press Give again."
    render :show, status: :unprocessable_entity
  end

  def donation_params
    p = params.require(:donation).permit(:currency, :frequency, :amount_ngn, :amount_usd, :amount_custom, :name, :email, :anonymous, :message)
    currency = Donation::CURRENCIES.key?(p[:currency]) ? p[:currency] : "NGN"
    preset = currency == "USD" ? p[:amount_usd] : p[:amount_ngn]
    {
      currency: currency,
      frequency: p[:frequency] == "monthly" ? :monthly : :one_time,
      amount_major: p[:amount_custom].presence || preset,
      name: p[:name].to_s.strip.presence,
      email: p[:email],
      anonymous: ActiveModel::Type::Boolean.new.cast(p[:anonymous]) || false,
      message: p[:message].to_s.strip.presence
    }
  end
end
