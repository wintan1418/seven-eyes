namespace :bibles do
  desc "Seed the 66-book canon (no network)"
  task books: :environment do
    BibleSeeder.seed_books!
  end

  desc "Seed translations. Usage: bibles:seed[KJV+BSB] or no args for MVP set (KJV ASV BSB WEB). " \
       "FORCE=1 re-seeds (upsert — ids and highlights survive). Incomplete translations re-seed automatically."
  task :seed, [ :codes ] => :environment do |_t, args|
    codes = args[:codes].present? ? args[:codes].split(/[+,\s]/).reject(&:blank?) : BibleSeeder::MVP_CODES
    BibleSeeder.seed!(codes, force: ENV["FORCE"].present?)
  end

  desc "Seed every public-domain / permissively-licensed translation we know (licence-restricted NET excluded). FORCE=1 re-seeds."
  task seed_all: :environment do
    BibleSeeder.seed!(BibleSeeder::ALL_CODES, force: ENV["FORCE"].present?)
  end

  desc "Report, per translation: verse count, books present, and chapters missing vs the canon"
  task verify: :environment do
    rows = BibleSeeder.verify
    puts "No translations seeded." if rows.empty?
    rows.each do |r|
      status = r.complete? ? "OK" : "INCOMPLETE"
      status += " (restricted — hidden from readers)" if r.restricted
      puts format("%-4s %-30s %6d verses  %2d/66 books  %s", r.code, r.name.truncate(30), r.verse_count, r.books, status)
      puts "     missing books: #{r.missing_books.join(', ')}" if r.missing_books.any?
      if r.missing_chapters.any?
        puts "     missing chapters (#{r.missing_chapters.size}): #{r.missing_chapters.first(40).join(', ')}" \
             "#{' …' if r.missing_chapters.size > 40}"
      end
    end
    incomplete = rows.reject { |r| r.complete? || r.restricted }.map(&:code)
    puts "\nRe-seed incomplete ones with: bin/rails \"bibles:seed[#{incomplete.join('+')}]\"" if incomplete.any?
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

  # NOTE (Oct 2026): the tokenizer now drops KJV marginal notes (<sup>…</sup>)
  # and refuses tokens whose text doesn't match the verse. Production tokens
  # seeded before that fix still carry the notes — re-run once after deploy:
  #   bin/rails bibles:seed_tokens FORCE=1
  desc "Tag KJV verses with Strong's numbers (needs KJV seeded first). FORCE=1 re-seeds (required once after the Oct 2026 tokenizer fix)."
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
