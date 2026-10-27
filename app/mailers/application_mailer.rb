class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("MAIL_FROM", "BiblioRata <no-reply@bibliorata.com>")
  layout "mailer"
end
