require "test_helper"

class DailyWordsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  ANDROID_APP = { "User-Agent" => "Mozilla/5.0 (Linux; Android 16) Chrome/140 BiblioRata/1.0.3; Hotwire Native Android; Turbo Native Android" }.freeze

  setup do
    @kjv = Translation.create!(code: "KJV", name: "King James Version")
    DailyWord::REFERENCES.first(3).each_with_index do |ref, i|
      parsed = ReferenceParser.call(ref)
      book = Book.find_by_osis(parsed.osis) ||
             Book.create!(osis_code: parsed.osis, name: parsed.book_name, testament: :new, position: 100 + i, chapter_count: 150)
      Verse.create!(translation: @kjv, book:, chapter: parsed.chapter, verse_number: parsed.verse_start, text: "Seeded #{ref}")
    end
    @today = DailyWord.today_date
  end

  def composed_word(date = @today)
    DailyWord.ensure_for(date).tap do |w|
      w.update!(reflection: "Rest in this promise today.", prayer: "Lord, keep us. Amen.", composed_at: Time.current)
    end
  end

  # -- /today ------------------------------------------------------------------

  test "/today creates today's word lazily and shows the verse with a fallback line until the reflection is written" do
    assert_enqueued_jobs 1, only: DailyWordJob do
      get today_path
    end
    assert_response :success
    word = DailyWord.find_by!(date: @today)
    assert_select ".dw-verse", text: word.verse_text
    assert_select ".dw-reflection.is-fallback", text: DailyWord::FALLBACK_LINE
    assert_select ".dw-prayer", count: 0
    assert_select "title", text: /Word for Today: #{Regexp.escape(word.reference)}/
  end

  test "/today shows the reflection and prayer, SEO and Open Graph tags" do
    word = composed_word
    get today_path
    assert_response :success
    assert_select ".dw-reflection", text: "Rest in this promise today."
    assert_select ".dw-prayer[open] p", text: "Lord, keep us. Amen."
    assert_select "meta[name=description][content*=?]", word.verse_text
    assert_select "meta[property='og:title'][content*=?]", word.reference
    assert_select "meta[property='og:url'][content=?]", daily_word_url(word)
    assert_select "meta[property='og:image'][content$='/og-image.jpg']"
    assert_select "link[rel=canonical][href=?]", daily_word_url(word)
    assert_select ".dw-actions form[action=?]", studies_path
    assert_select ".dw-actions button", text: /Share/
    assert_select ".dw-actions button", text: /Copy text/
    assert_select ".ps-share-host[data-share-card-card-url-value=?]", daily_word_card_path(word)
  end

  test "an AI failure never breaks the page" do
    get today_path
    word = DailyWord.find_by!(date: @today)
    refute word.compose!(composer: ->(_w) { DailyWordComposer::Result.new(ok: false, error: :budget) })
    get today_path
    assert_response :success
    assert_select ".dw-reflection.is-fallback"
  end

  test "/today still renders when no Bible is seeded" do
    Verse.delete_all
    Translation.delete_all
    get today_path
    assert_response :success
    assert_select ".dw-verse", text: /Open thou mine eyes/
  end

  # -- Dated pages & archive ------------------------------------------------------

  test "a past day's page and the archive" do
    past = composed_word(@today - 1)
    composed_word
    get daily_word_path(past)
    assert_response :success
    assert_select "h1", text: /Word for #{past.date.strftime('%A')}/
    assert_select ".dw-verse", text: past.verse_text
    assert_select ".dw-archive a[href=?]", daily_word_path(@today.iso8601)
    assert_select "a[href=?]", today_path, text: /Read today's word/
  end

  test "future dates are never shown, even when a word exists" do
    future = DailyWord.ensure_for(@today + 1)
    get daily_word_path(future)
    assert_response :not_found
    get daily_word_card_path(future)
    assert_response :not_found
    get today_path
    assert_select ".dw-archive a[href=?]", daily_word_path(future), count: 0
  end

  test "a day without a word is a 404, and visiting it creates nothing" do
    assert_no_difference -> { DailyWord.count } do
      get daily_word_path((@today - 30).iso8601)
    end
    assert_response :not_found
    get "/today/2026-02-31"
    assert_response :not_found
  end

  # -- Share JSON ----------------------------------------------------------------

  test "card JSON feeds the share-as-image modal" do
    word = composed_word
    get daily_word_card_path(word)
    assert_response :success
    body = response.parsed_body
    assert_equal word.reference, body["reference"]
    assert_equal word.verse_text, body["text"]
    assert_equal "King James Version", body["translation"]
    assert_equal daily_word_url(word), body["url"]
    assert_equal word.osis_code, body["osis"]
  end

  test "prayer JSON returns the day's prayer, or a soft failure" do
    word = DailyWord.ensure_for(@today)
    get daily_word_prayer_path(word)
    refute response.parsed_body["ok"]

    composed_word
    get daily_word_prayer_path(word)
    assert response.parsed_body["ok"]
    assert_equal "Lord, keep us. Amen.", response.parsed_body["prayer"]
  end

  # -- Home placement -----------------------------------------------------------

  test "the landing page shows today's word" do
    word = composed_word
    get root_path
    assert_response :success
    assert_select ".ld-vod .dw-card .dw-verse", text: word.verse_text
    assert_select ".ld-vod .dw-reflection", text: "Rest in this promise today."
    assert_select ".ld-vod details.dw-prayer:not([open])"
  end

  test "the signed-in home shows today's word over a painting, with Read the chapter, Share, Copy and the prayer folded" do
    word = composed_word
    sign_in_as users(:one)
    get root_path
    assert_response :success
    assert_select ".hm-verse .hm-verse-art picture img[loading=eager]"
    assert_select ".hm-verse .hm-verse-text", text: word.verse_text
    assert_select ".hm-verse a.hm-verse-read[href=?]", read_path(ref: word.reference, t: word.translation_code)
    assert_select ".hm-verse [data-action='daily-word#share']"
    assert_select ".hm-verse [data-action='daily-word#copy']"
    assert_select ".hm-verse[data-daily-word-text-value*=?]", "Lord, keep us. Amen."
    assert_select ".hm-verse details.hm-reflect:not([open])" do
      assert_select ".hm-reflect-prayer", text: "Lord, keep us. Amen."
      assert_select "a[href=?]", today_path
    end
    # The share modal sits outside the scroller so it covers the app bar.
    assert_select ".hm-root > .ps-share-host[data-share-card-card-url-value=?]", daily_word_card_path(word)
    assert_select ".hm-main .ps-share-host", count: 0
  end

  # -- Android app -----------------------------------------------------------------

  test "inside the Android app /today drops the web title suffix and hides the web app bar" do
    word = composed_word
    get today_path, headers: ANDROID_APP
    assert_response :success
    assert_select "body.hotwire-native"
    assert_select "title", text: "Word for Today: #{word.reference}"
    # The web app bar carries no chip, so native.css hides it (the app draws its own).
    assert_select ".pub-appbar .ui-chip", count: 0
  end
end
