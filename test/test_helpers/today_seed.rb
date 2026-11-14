# A tiny Bible and today's Word for the Today flow / Home tests: Luke 1:33-41
# in the KJV, today's word at Luke 1:37 with a reflection and prayer, and
# (optionally) glossary words — one reviewed, one draft.
module TodaySeed
  def seed_today!(terms: true)
    @kjv = Translation.find_by(code: "KJV") || Translation.create!(code: "KJV", name: "King James Version")
    @luke = Book.find_by(osis_code: "Luke") ||
            Book.create!(osis_code: "Luke", name: "Luke", testament: :new, position: 42, chapter_count: 24)
    (30..45).each do |n|
      Verse.create!(translation: @kjv, book: @luke, chapter: 1, verse_number: n,
                    text: n == 37 ? "For with God nothing shall be impossible." : "Luke one verse #{n}.")
    end
    @word = DailyWord.create!(
      date: DailyWord.today_date, reference: "Luke 1:37", osis_code: "Luke", chapter: 1, verse_start: 37, verse_end: 37,
      translation_code: "KJV", verse_text: "For with God nothing shall be impossible.",
      reflection: "Nothing you face today is beyond him.", prayer: "Lord, I trust you with today. Amen.", composed_at: Time.current
    )
    return @word unless terms

    LexiconEntry.create!(strongs: "G5485", language: "greek", lemma: "χάρις", translit: "cháris", kjv_def: "grace, favour, thanks")
    @grace = FaithTerm.create!(name: "Grace", short_definition: "God's undeserved favour.", position: 0, status: :reviewed,
                               root_strongs: [ "G5485" ], key_references: [ "Luke 1:30" ])
    @draft = FaithTerm.create!(name: "Election", short_definition: "A draft nobody may see yet.", position: 1)
    @word
  end
end
