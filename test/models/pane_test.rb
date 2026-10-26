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

  test "a verse past the end of a seeded chapter reports :verse_not_found with the chapter's length" do
    @pane.update!(reference: "John 3:17", translation: @kjv) # chapter 3 has only v16 seeded
    content = @pane.content
    assert_equal :verse_not_found, content.error
    assert_equal 16, content.max_verse
    assert_equal @john, content.book
  end

  test "a chapter this translation has no text for reports :not_found" do
    @pane.update!(reference: "John 4", translation: @kjv) # nothing seeded in chapter 4
    content = @pane.content
    assert_equal :not_found, content.error
    assert_nil content.max_verse
  end

  test "a bare book name opens chapter 1" do
    Verse.create!(translation: @kjv, book: @john, chapter: 1, verse_number: 1, text: "In the beginning was the Word")
    @pane.update!(reference: "John", translation: @kjv)
    content = @pane.content
    assert content.ok?
    assert_equal 1, content.parsed.chapter
    assert content.parsed.whole_chapter?
  end

  test "a chapter beyond the book reports :unparseable with the parser's reason" do
    @pane.update!(reference: "John 99", translation: @kjv)
    content = @pane.content
    assert_equal :unparseable, content.error
    assert_equal :bad_chapter, content.parsed.error
    assert_equal 21, content.parsed.chapter_count
  end

  test "effective_translation falls back to KJV when none set" do
    assert_equal @kjv, @pane.effective_translation
  end
end
