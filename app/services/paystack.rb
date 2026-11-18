# frozen_string_literal: true

require "net/http"

# A small Paystack API client (https://paystack.com/docs/api). Giving is
# switched on by setting PAYSTACK_SECRET_KEY; without it the Give page shows
# "Giving opens soon" and nothing is sent.
module Paystack
  API = "https://api.paystack.co"

  class Error < StandardError; end

  module_function

  def secret = ENV["PAYSTACK_SECRET_KEY"].presence
  def configured? = secret.present?

  def post(path, body) = request(Net::HTTP::Post, path, body)
  def get(path) = request(Net::HTTP::Get, path)

  # Paystack signs each webhook: HMAC-SHA512 of the raw body with the secret key.
  def valid_signature?(raw_body, signature)
    return false unless configured? && signature.present?
    ActiveSupport::SecurityUtils.secure_compare(OpenSSL::HMAC.hexdigest("SHA512", secret, raw_body.to_s), signature.to_s)
  end

  def request(klass, path, body = nil)
    raise Error, "Paystack is not set up" unless configured?
    uri = URI.join(API, path)
    req = klass.new(uri)
    req["Authorization"] = "Bearer #{secret}"
    req["Content-Type"] = "application/json"
    req.body = body.to_json if body
    res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 15) { |http| http.request(req) }
    json = JSON.parse(res.body.to_s) rescue {}
    raise Error, (json["message"].presence || "Paystack answered #{res.code}") unless res.is_a?(Net::HTTPSuccess) && json["status"]
    json["data"] || {}
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED, OpenSSL::SSL::SSLError => e
    raise Error, "Couldn't reach Paystack (#{e.class.name.demodulize})"
  end
end
