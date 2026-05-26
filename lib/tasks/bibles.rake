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

  desc "Seed every public-domain / permissively-licensed translation we know. FORCE=1 re-seeds."
  task seed_all: :environment do
    BibleSeeder.seed!(BibleSeeder::ALL_CODES, force: ENV["FORCE"].present?)
  end

  desc "Seed TSK cross-references (votes >= MIN_VOTES, default 0). FORCE=1 re-seeds."
  task seed_refs: :environment do
    CrossReferenceSeeder.seed!(force: ENV["FORCE"].present?, min_votes: ENV.fetch("MIN_VOTES", 0).to_i)
  end

  desc "Seed commentary. Usage: bibles:seed_commentary[matthew-henry+john-gill] or no args for Matthew Henry. FORCE=1 re-seeds."
  task :seed_commentary, [ :sources ] => :environment do |_t, args|
    sources = args[:sources].present? ? args[:sources].split(/[+,\s]/).reject(&:blank?) : CommentarySeeder::DEFAULT
    CommentarySeeder.seed!(sources, force: ENV["FORCE"].present?)
  end

  desc "Seed Strong's Greek + Hebrew lexicon entries. FORCE=1 re-seeds."
  task seed_lexicon: :environment do
    LexiconSeeder.seed!(force: ENV["FORCE"].present?)
  end

  desc "Tag KJV verses with Strong's numbers (needs KJV seeded first). FORCE=1 re-seeds."
  task seed_tokens: :environment do
    VerseTokenSeeder.seed!(force: ENV["FORCE"].present?)
  end

  desc "Seed the full word-study stack: lexicon + KJV Strong's tagging."
  task seed_strongs: :environment do
    LexiconSeeder.seed!(force: ENV["FORCE"].present?)
    VerseTokenSeeder.seed!(force: ENV["FORCE"].present?)
  end

  desc "Seed everything: canon, MVP translations, and cross-references"
  task all: :environment do
    BibleSeeder.seed!
    CrossReferenceSeeder.seed!
  end
end
