require "test_helper"

class LiveSessionTest < ActiveSupport::TestCase
  setup do
    @study = users(:one).studies.create!(name: "Sunday", pane_count: 1)
    @kjv = Translation.create!(code: "KJV", name: "King James Version")
    @john = Book.create!(osis_code: "John", name: "John", testament: :new, position: 43, chapter_count: 21)
    Verse.create!(translation: @kjv, book: @john, chapter: 3, verse_number: 16,
                  text: "For God so loved the world")
  end

  test "assigns a short unambiguous join code on create" do
    live = @study.live_sessions.create!
    assert_match(/\A[#{Regexp.escape(LiveSession::CODE_ALPHABET.join)}]{4}\z/, live.code)
  end

  test "find_active matches case-insensitively and skips ended sessions" do
    live = @study.live_sessions.create!
    assert_equal live, LiveSession.find_active(live.code.downcase)
    live.end!
    assert_nil LiveSession.find_active(live.code)
  end

  test "study.live_session returns the newest active session" do
    old = @study.live_sessions.create!
    old.end!
    fresh = @study.live_sessions.create!
    assert_equal fresh, @study.live_session
  end

  test "verses and reference_label resolve from the stored state" do
    live = @study.live_sessions.create!(osis: "John", chapter: 3, translation_code: "KJV",
                                        verse_start: 16, verse_end: 16)
    assert_equal "John 3", live.reference_label
    assert_equal [ 16 ], live.verses.map(&:verse_number)
  end

  test "adjust_followers never goes below zero" do
    live = @study.live_sessions.create!
    assert_equal 1, live.adjust_followers(+1)
    assert_equal 0, live.adjust_followers(-1)
    assert_equal 0, live.adjust_followers(-1)
  end
end
