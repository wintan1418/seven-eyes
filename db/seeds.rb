# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Development convenience: the single pastor account. Override via env in production.
if Rails.env.local?
  email = ENV.fetch("PASTOR_EMAIL", "pastor@example.com")
  User.find_or_create_by!(email_address: email) do |u|
    u.password = ENV.fetch("PASTOR_PASSWORD", "password")
  end
end
