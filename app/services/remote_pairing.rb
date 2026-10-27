# Signed, expiring pairing tokens for the phone remote. RemotesController#create
# mints a code and two tokens bound to that code AND the study: one for the
# console, one for the pad (embedded in the QR link). RemoteChannel verifies the
# token on subscribe and uses its role to decide who may send what.
#
#   RemotePairing.issue(code:, study:, role: RemotePairing::PAD) # => token
#   RemotePairing.verify(token, code:)  # => { role:, study_id: } or nil
module RemotePairing
  CONSOLE = "console"
  PAD = "pad"
  ROLES = [ CONSOLE, PAD ].freeze
  TTL = 12.hours

  module_function

  def issue(code:, study:, role:)
    raise ArgumentError, "unknown role #{role.inspect}" unless ROLES.include?(role)
    verifier.generate({ "s" => study.id, "r" => role }, expires_in: TTL, purpose: purpose_for(code))
  end

  def verify(token, code:)
    return nil if token.blank?
    data = verifier.verified(token.to_s, purpose: purpose_for(code))
    return nil unless data.is_a?(Hash) && ROLES.include?(data["r"])
    { role: data["r"], study_id: data["s"] }
  rescue ActiveSupport::MessageVerifier::InvalidSignature, ArgumentError
    nil
  end

  def purpose_for(code)
    "remote_pairing:#{code.to_s.upcase}"
  end

  def verifier
    @verifier ||= ActiveSupport::MessageVerifier.new(
      Rails.application.key_generator.generate_key("remote_pairing"),
      digest: "SHA256", serializer: JSON, url_safe: true
    )
  end
end
