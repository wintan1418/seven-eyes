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
    assert_match(/\A[#{Regexp.escape(LiveSession::CODE_ALPHABET.join)}]{6}\z/, live.code)
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

  test "legacy four-character codes still resolve" do
    live = @study.live_sessions.create!(code: "AB23")
    assert_equal live, LiveSession.find_active("ab23")
  end

  test "the fallback code (after collisions) also uses the unambiguous alphabet" do
    collide = LiveSession.singleton_class
    collide.alias_method :__real_exists?, :exists?
    collide.define_method(:exists?) { |*| true }
    live = @study.live_sessions.create!
    assert_match(/\A[#{Regexp.escape(LiveSession::CODE_ALPHABET.join)}]{#{LiveSession::FALLBACK_CODE_LENGTH}}\z/, live.code)
  ensure
    collide&.alias_method :exists?, :__real_exists?
    collide&.remove_method :__real_exists?
  end

  test "a session quiet for longer than STALE_AFTER is ended lazily" do
    live = @study.live_sessions.create!
    live.update_column(:updated_at, (LiveSession::STALE_AFTER + 1.minute).ago)
    assert_nil LiveSession.find_active(live.code)
    assert live.reload.ended?
  end

  test "current_for returns the fresh active session and expires a stale one" do
    live = @study.live_sessions.create!
    assert_equal live, LiveSession.current_for(@study)
    live.update_column(:updated_at, (LiveSession::STALE_AFTER + 1.minute).ago)
    assert_nil LiveSession.current_for(@study)
    assert live.reload.ended?
  end

  test "start_for! is idempotent" do
    first = LiveSession.start_for!(@study)
    assert_no_difference -> { LiveSession.count } do
      assert_equal first, LiveSession.start_for!(@study)
    end
  end

  test "the recap stays available for a week after the service" do
    live = @study.live_sessions.create!
    assert live.recap_available?
    live.end!
    assert live.recap_available?
    travel LiveSession::RECAP_TTL + 1.hour do
      refute live.recap_available?
    end
  end

  test "operator tokens resolve their own session only" do
    live = @study.live_sessions.create!
    assert_equal live, LiveSession.find_by_operator_token(live.operator_token)
    assert_nil LiveSession.find_by_operator_token("nope")
  end

  test "ending a session resets the follower count" do
    live = @study.live_sessions.create!
    live.adjust_followers(+3)
    live.end!
    assert_equal 0, live.reload.followers_count
  end
end
