require "test_helper"

class PaneTest < ActiveSupport::TestCase
  setup do
    @kjv = Translation.create!(code: "KJV", name: "King James Version")
    @john = Book.create!(osis_code: "John", name: "John", testament: :new, position: 43, chapter_count: 21)
    Verse.create!(translation: @kjv, book: @john, chapter: 3, verse_number: 16, text: "For God so loved the world...")
    study = users(:one).studies.create!(name: "Test", pane_count: 1)
    @pane = study.panes.first
  end

  test "empty pane reports :empty" do
    assert @pane.empty?
    assert_equal :empty, @pane.content.error
    refute @pane.content.ok?
  end

  test "unparseable reference reports :unparseable" do
    @pane.update!(reference: "blah blah")
    assert_equal :unparseable, @pane.content.error
  end

  test "valid reference loads verses" do
    @pane.update!(reference: "John 3:16", translation: @kjv)
    content = @pane.content
    assert content.ok?
    assert_equal 1, content.verses.size
    assert_equal 16, content.verses.first.verse_number
    assert_equal @john, content.book
  end

  test "reference with no rows in this translation reports :not_found" do
    @pane.update!(reference: "John 3:17", translation: @kjv) # verse 17 not seeded
    assert_equal :not_found, @pane.content.error
  end

  test "effective_translation falls back to KJV when none set" do
    assert_equal @kjv, @pane.effective_translation
  end
end
