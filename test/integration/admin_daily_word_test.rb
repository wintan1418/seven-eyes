require "test_helper"

class AdminDailyWordTest < ActionDispatch::IntegrationTest
  setup do
    kjv = Translation.create!(code: "KJV", name: "King James Version")
    john = Book.create!(osis_code: "John", name: "John", testament: :new, position: 43, chapter_count: 21)
    Verse.create!(translation: kjv, book: john, chapter: 3, verse_number: 16, text: "For God so loved the world")
    @original = DailyWordComposer.method(:call)
  end

  teardown { DailyWordComposer.define_singleton_method(:call, @original) }

  def stub_composer(result)
    DailyWordComposer.define_singleton_method(:call) { |_word| result }
  end

  test "guests and ordinary accounts cannot regenerate" do
    post admin_regenerate_daily_word_path
    assert_redirected_to new_session_path

    sign_in_as users(:one)
    post admin_regenerate_daily_word_path
    assert_redirected_to root_path
    assert_nil DailyWord.first&.reflection
  end

  test "an admin sees today's word and can have it rewritten" do
    users(:one).update!(admin: true)
    sign_in_as users(:one)
    word = DailyWord.ensure_for(DailyWord.today_date)
    word.update!(reflection: "Old reflection.", prayer: "Old. Amen.", composed_at: 1.hour.ago)

    get admin_path
    assert_select ".dw-admin", text: /Old reflection\./
    assert_select ".dw-admin form[action=?]", admin_regenerate_daily_word_path

    stub_composer(DailyWordComposer::Result.new(ok: true, reflection: "New reflection.", prayer: "New. Amen."))
    post admin_regenerate_daily_word_path
    assert_redirected_to admin_path
    assert_equal "New reflection.", word.reload.reflection
    follow_redirect!
    assert_select ".dw-admin-flash", text: /rewritten/
  end

  test "a failed regeneration keeps the old text" do
    users(:one).update!(admin: true)
    sign_in_as users(:one)
    word = DailyWord.ensure_for(DailyWord.today_date)
    word.update!(reflection: "Old reflection.", prayer: "Old. Amen.")

    stub_composer(DailyWordComposer::Result.new(ok: false, error: :no_key))
    post admin_regenerate_daily_word_path
    assert_redirected_to admin_path
    assert_equal "Old reflection.", word.reload.reflection
  end
end
