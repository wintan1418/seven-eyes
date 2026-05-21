module Bible
  # The Protestant canon: OSIS codes (used internally everywhere), display names,
  # chapter counts, and the distinctive abbreviation aliases per book.
  #
  # Numeric prefixes ("1", "2", "3") are normalized by ReferenceParser before lookup,
  # so aliases here only need the *word* portion ("cor", "kgs"); the parser tries both
  # "1cor" and bare forms. Full name and OSIS code are always accepted automatically.
  module Canon
    BOOKS = [
      # OSIS,     Name,                    Testament, Chapters, Aliases
      [ "Gen",     "Genesis",               :old, 50,  %w[ge gen gn] ],
      [ "Exod",    "Exodus",                :old, 40,  %w[ex exo exod] ],
      [ "Lev",     "Leviticus",             :old, 27,  %w[le lev lv] ],
      [ "Num",     "Numbers",               :old, 36,  %w[nu num nm nb] ],
      [ "Deut",    "Deuteronomy",           :old, 34,  %w[dt deut deu de] ],
      [ "Josh",    "Joshua",                :old, 24,  %w[js jos josh] ],
      [ "Judg",    "Judges",                :old, 21,  %w[jdg judg jgs jg] ],
      [ "Ruth",    "Ruth",                  :old, 4,   %w[ru ruth rth] ],
      [ "1Sam",    "1 Samuel",              :old, 31,  %w[1sam 1sa 1sm sam1 1samuel] ],
      [ "2Sam",    "2 Samuel",              :old, 24,  %w[2sam 2sa 2sm sam2 2samuel] ],
      [ "1Kgs",    "1 Kings",               :old, 22,  %w[1kgs 1ki 1kg 1kings kings1] ],
      [ "2Kgs",    "2 Kings",               :old, 25,  %w[2kgs 2ki 2kg 2kings kings2] ],
      [ "1Chr",    "1 Chronicles",          :old, 29,  %w[1chr 1ch 1chron 1chronicles] ],
      [ "2Chr",    "2 Chronicles",          :old, 36,  %w[2chr 2ch 2chron 2chronicles] ],
      [ "Ezra",    "Ezra",                  :old, 10,  %w[ezr ezra] ],
      [ "Neh",     "Nehemiah",              :old, 13,  %w[ne neh] ],
      [ "Esth",    "Esther",                :old, 10,  %w[es est esth] ],
      [ "Job",     "Job",                   :old, 42,  %w[jb job] ],
      [ "Ps",      "Psalms",                :old, 150, %w[ps psa psalm psalms pss] ],
      [ "Prov",    "Proverbs",              :old, 31,  %w[pr prov prv pro] ],
      [ "Eccl",    "Ecclesiastes",          :old, 12,  %w[ec ecc eccl eccles qoh] ],
      [ "Song",    "Song of Solomon",       :old, 8,   %w[song sos ss songofsolomon songofsongs canticles cant] ],
      [ "Isa",     "Isaiah",                :old, 66,  %w[is isa isaiah] ],
      [ "Jer",     "Jeremiah",              :old, 52,  %w[je jer jeremiah] ],
      [ "Lam",     "Lamentations",          :old, 5,   %w[la lam lament] ],
      [ "Ezek",    "Ezekiel",               :old, 48,  %w[ez eze ezek ezk] ],
      [ "Dan",     "Daniel",                :old, 12,  %w[da dan dn] ],
      [ "Hos",     "Hosea",                 :old, 14,  %w[ho hos] ],
      [ "Joel",    "Joel",                  :old, 3,   %w[joe joel jl] ],
      [ "Amos",    "Amos",                  :old, 9,   %w[am amo amos] ],
      [ "Obad",    "Obadiah",               :old, 1,   %w[ob oba obad obd] ],
      [ "Jonah",   "Jonah",                 :old, 4,   %w[jon jnh jonah] ],
      [ "Mic",     "Micah",                 :old, 7,   %w[mic mi micah] ],
      [ "Nah",     "Nahum",                 :old, 3,   %w[na nah nahum] ],
      [ "Hab",     "Habakkuk",              :old, 3,   %w[hab hb habakkuk] ],
      [ "Zeph",    "Zephaniah",             :old, 3,   %w[zep zeph zphn] ],
      [ "Hag",     "Haggai",                :old, 2,   %w[hag hg haggai] ],
      [ "Zech",    "Zechariah",             :old, 14,  %w[zec zech zc zechariah] ],
      [ "Mal",     "Malachi",               :old, 4,   %w[mal ml malachi] ],
      [ "Matt",    "Matthew",               :new, 28,  %w[mt mat matt matthew] ],
      [ "Mark",    "Mark",                  :new, 16,  %w[mk mar mrk mark] ],
      [ "Luke",    "Luke",                  :new, 24,  %w[lk luk luke] ],
      [ "John",    "John",                  :new, 21,  %w[jn joh jhn john] ],
      [ "Acts",    "Acts",                  :new, 28,  %w[ac act acts] ],
      [ "Rom",     "Romans",                :new, 16,  %w[ro rom rm romans] ],
      [ "1Cor",    "1 Corinthians",         :new, 16,  %w[1cor 1co 1corinthians cor1] ],
      [ "2Cor",    "2 Corinthians",         :new, 13,  %w[2cor 2co 2corinthians cor2] ],
      [ "Gal",     "Galatians",             :new, 6,   %w[ga gal galatians] ],
      [ "Eph",     "Ephesians",             :new, 6,   %w[eph ephes ephesians] ],
      [ "Phil",    "Philippians",           :new, 4,   %w[php phil philippians] ],
      [ "Col",     "Colossians",            :new, 4,   %w[col colossians] ],
      [ "1Thess",  "1 Thessalonians",       :new, 5,   %w[1thess 1th 1thes 1thessalonians] ],
      [ "2Thess",  "2 Thessalonians",       :new, 3,   %w[2thess 2th 2thes 2thessalonians] ],
      [ "1Tim",    "1 Timothy",             :new, 6,   %w[1tim 1ti 1timothy] ],
      [ "2Tim",    "2 Timothy",             :new, 4,   %w[2tim 2ti 2timothy] ],
      [ "Titus",   "Titus",                 :new, 3,   %w[tit ti titus] ],
      [ "Phlm",    "Philemon",              :new, 1,   %w[phm phlm philem philemon] ],
      [ "Heb",     "Hebrews",               :new, 13,  %w[heb hebrews] ],
      [ "Jas",     "James",                 :new, 5,   %w[jas jam jms james] ],
      [ "1Pet",    "1 Peter",               :new, 5,   %w[1pet 1pe 1pt 1peter] ],
      [ "2Pet",    "2 Peter",               :new, 3,   %w[2pet 2pe 2pt 2peter] ],
      [ "1John",   "1 John",                :new, 5,   %w[1john 1jn 1jo 1jhn] ],
      [ "2John",   "2 John",                :new, 1,   %w[2john 2jn 2jo 2jhn] ],
      [ "3John",   "3 John",                :new, 1,   %w[3john 3jn 3jo 3jhn] ],
      [ "Jude",    "Jude",                  :new, 1,   %w[jud jude jd] ],
      [ "Rev",     "Revelation",            :new, 22,  %w[rev re rv revelation apocalypse] ]
    ].freeze

    Entry = Struct.new(:osis, :name, :testament, :chapter_count, :aliases, :position)

    class << self
      def all
        @all ||= BOOKS.each_with_index.map do |(osis, name, testament, chapters, aliases), i|
          Entry.new(osis, name, testament, chapters, aliases, i + 1)
        end.freeze
      end

      def find(osis)
        index[osis]
      end

      def index
        @index ||= all.index_by(&:osis).freeze
      end

      # Map every normalized alias/name/osis token to its OSIS code.
      def alias_map
        @alias_map ||= begin
          map = {}
          all.each do |b|
            keys = [ b.osis, b.name, *b.aliases ]
            keys.each { |k| map[normalize_key(k)] = b.osis }
          end
          map.freeze
        end
      end

      # Lowercase, drop spaces and periods so "1 Cor.", "1cor", "I Corinthians"
      # all collapse to the same key. (Ordinal words/romans are converted to
      # digits by ReferenceParser before this is called.)
      def normalize_key(str)
        str.to_s.downcase.gsub(/[\s.]/, "")
      end
    end
  end
end
