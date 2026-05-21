namespace :bibles do
  desc "Seed the 66-book canon (no network)"
  task books: :environment do
    BibleSeeder.seed_books!
  end

  desc "Seed translations. Usage: bibles:seed[KJV+BSB] or no args for MVP set (KJV ASV BSB WEB). FORCE=1 re-seeds."
  task :seed, [ :codes ] => :environment do |_t, args|
    codes = args[:codes].present? ? args[:codes].split(/[+,\s]/).reject(&:blank?) : BibleSeeder::MVP_CODES
    BibleSeeder.seed!(codes, force: ENV["FORCE"].present?)
  end

  desc "Seed TSK cross-references (votes >= MIN_VOTES, default 0). FORCE=1 re-seeds."
  task seed_refs: :environment do
    CrossReferenceSeeder.seed!(force: ENV["FORCE"].present?, min_votes: ENV.fetch("MIN_VOTES", 0).to_i)
  end

  desc "Seed everything: canon, MVP translations, and cross-references"
  task all: :environment do
    BibleSeeder.seed!
    CrossReferenceSeeder.seed!
  end
end
