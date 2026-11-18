# frozen_string_literal: true

# A gift to BiblioRata through Paystack (GivingController). Amounts are kept
# in the smallest unit Paystack uses: kobo for NGN, cents for USD.
class Donation < ApplicationRecord
  CURRENCIES = {
    "NGN" => { symbol: "₦", presets: [ 2_000, 5_000, 10_000, 25_000 ], min: 500, max: 10_000_000 },
    "USD" => { symbol: "$", presets: [ 5, 10, 25, 50 ], min: 2, max: 10_000 }
  }.freeze

  belongs_to :user, optional: true

  enum :status, { pending: "pending", paid: "paid", failed: "failed" }, default: :pending
  enum :frequency, { one_time: "one_time", monthly: "monthly" }, default: :one_time

  before_validation :assign_reference, on: :create
  before_validation { self.email = email.to_s.strip.downcase.presence }

  validates :currency, inclusion: { in: CURRENCIES.keys }
  validates :email, presence: { message: "is needed for your receipt" },
                    format: { with: URI::MailTo::EMAIL_REGEXP, allow_blank: true, message: "doesn't look right" }
  validates :name, length: { maximum: 120 }
  validates :message, length: { maximum: 500 }
  validates :reference, presence: true, uniqueness: true
  validate :amount_within_limits

  def self.symbol_for(currency) = CURRENCIES.fetch(currency, CURRENCIES["NGN"])[:symbol]

  def self.format_amount(major, currency)
    "#{symbol_for(currency)}#{ActiveSupport::NumberHelper.number_to_delimited(major % 1 == 0 ? major.to_i : format('%.2f', major))}"
  end

  # "5000" or "25.50" in the page's currency -> smallest unit.
  def amount_major=(value)
    major = BigDecimal(value.to_s.delete(",").strip) rescue nil
    self.amount_minor = major && (major * 100).round.to_i
  end

  def amount_major = amount_minor.to_i / 100r
  def display_amount = self.class.format_amount(amount_major, currency)

  # Start the payment: returns the Paystack checkout URL to send the giver to.
  def checkout_url(callback_url:)
    body = {
      email: email, amount: amount_minor, currency: currency, reference: reference, callback_url: callback_url,
      metadata: { app: "BiblioRata", donation_id: id, frequency: frequency,
                  name: (anonymous? ? nil : name), message: message.presence }.compact
    }
    if monthly?
      update!(paystack_plan_code: monthly_plan_code)
      body[:plan] = paystack_plan_code
    end
    Paystack.post("/transaction/initialize", body).fetch("authorization_url")
  rescue KeyError
    raise Paystack::Error, "Paystack didn't return a checkout link"
  end

  # Apply what Paystack says about this payment (from verify or the webhook).
  def settle_from(data)
    return self if paid?
    if data["status"] == "success" && data["amount"].to_i == amount_minor && data["currency"] == currency
      update!(status: :paid, paid_at: (Time.zone.parse(data["paid_at"].to_s) rescue nil) || Time.current)
    elsif data["status"] == "failed"
      update!(status: :failed)
    end
    self
  end

  # charge.success from the webhook. Monthly renewals arrive with a new
  # reference; they are recorded as a new paid gift copying the first one.
  def self.record_payment!(data)
    data = data.to_h
    reference = data["reference"].to_s
    return if reference.blank?
    if (donation = find_by(reference: reference))
      return donation.settle_from(data)
    end
    plan_code = data["plan"].is_a?(Hash) ? data.dig("plan", "plan_code") : data["plan"]
    first = plan_code.present? && where(paystack_plan_code: plan_code, email: data.dig("customer", "email").to_s.downcase).order(:created_at).first
    return unless first
    create!(first.attributes.slice("currency", "frequency", "email", "name", "anonymous", "user_id", "paystack_plan_code")
                 .merge(amount_minor: data["amount"].to_i, reference: reference, status: :paid, paid_at: Time.current))
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    find_by(reference: reference)
  end

  private

  def assign_reference
    self.reference ||= "bibliorata-#{SecureRandom.hex(10)}"
  end

  # One Paystack plan per amount and currency, created on first use.
  def monthly_plan_code
    Donation.monthly.where(currency: currency, amount_minor: amount_minor).where.not(paystack_plan_code: nil).pick(:paystack_plan_code) ||
      Paystack.post("/plan", { name: "BiblioRata monthly gift #{display_amount}", interval: "monthly",
                               amount: amount_minor, currency: currency }).fetch("plan_code")
  end

  def amount_within_limits
    limits = CURRENCIES[currency] or return
    if amount_minor.nil? || amount_minor <= 0
      errors.add(:base, "Choose an amount to give")
    elsif amount_minor < limits[:min] * 100
      errors.add(:base, "The smallest gift is #{self.class.format_amount(limits[:min], currency)}")
    elsif amount_minor > limits[:max] * 100
      errors.add(:base, "For gifts above #{self.class.format_amount(limits[:max], currency)}, please contact us")
    end
  end
end
