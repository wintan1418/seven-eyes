# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc,
  # Personal study content and AI prompts stay out of the logs.
  # (`q` is anchored: a bare :q would partially match every key containing a "q".)
  :notes, :note, /\Aq\z/, :body, :reflection, :selection
]
