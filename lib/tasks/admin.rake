namespace :admin do
  desc "Grant admin to a user: bin/rails admin:grant EMAIL=pastor@example.com"
  task grant: :environment do
    email = ENV["EMAIL"].to_s.strip.downcase
    abort "Usage: bin/rails admin:grant EMAIL=someone@example.com" if email.empty?
    user = User.find_by(email_address: email)
    abort "No user with email #{email}" unless user
    user.update!(admin: true)
    puts "#{email} is now an admin — visit /admin"
  end

  desc "Revoke admin: bin/rails admin:revoke EMAIL=..."
  task revoke: :environment do
    email = ENV["EMAIL"].to_s.strip.downcase
    user = User.find_by(email_address: email)
    abort "No user with email #{email}" unless user
    user.update!(admin: false)
    puts "#{email} is no longer an admin"
  end
end
