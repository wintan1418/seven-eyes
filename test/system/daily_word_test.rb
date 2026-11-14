require "application_system_test_case"

# Browser smoke of the Word for Today card: Share opens the share-as-image
# modal drawn from this day's word, on the landing and on the signed-in home.
class DailyWordSystemTest < ApplicationSystemTestCase
  setup do
    kjv = Translation.create!(code: "KJV", name: "King James Version")
    DailyWord::REFERENCES.first(2).each_with_index do |ref, i|
      parsed = ReferenceParser.call(ref)
      book = Book.find_by_osis(parsed.osis) ||
             Book.create!(osis_code: parsed.osis, name: parsed.book_name, testament: :new, position: 100 + i, chapter_count: 150)
      Verse.create!(translation: kjv, book:, chapter: parsed.chapter, verse_number: parsed.verse_start, text: "Seeded #{ref}")
    end
    @word = DailyWord.ensure_for(DailyWord.today_date)
    @word.update!(reflection: "Rest in this today.", prayer: "Lord, keep us. Amen.", composed_at: Time.current)
  end

  test "Share on the landing card opens the share modal with today's link" do
    visit root_path
    within(".ld-vod .dw-card") { click_on "Share" }
    assert_selector ".ps-share-host.is-open"
    assert_selector(".ps-share-host.is-open input[data-share-card-target='link']") do |input|
      input.value.end_with?("/today/#{@word.date.iso8601}")
    end
  end

  test "Share on the signed-in home's verse of the day opens the share modal" do
    visit new_session_path
    fill_in "email_address", with: users(:one).email_address
    fill_in "password", with: "password"
    click_on "Sign In"
    assert_selector ".hm-verse"
    within(".hm-verse") { click_on "Share" }
    assert_selector ".ps-share-host.is-open"
  end
end
