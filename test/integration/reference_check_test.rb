require "test_helper"

class ReferenceCheckTest < ActionDispatch::IntegrationTest
  setup do
    @rom = Book.create!(osis_code: "Rom", name: "Romans", testament: :new, position: 45, chapter_count: 16)
  end

  test "parses a called reference into a canonical chapter + landing verse" do
    get reference_check_path(q: "rom 8:28")
    assert_response :success
    data = JSON.parse(response.body)
    assert data["ok"]
    assert_equal "Rom", data["osis"]
    assert_equal 8, data["chapter"]
    assert_equal 28, data["verse_start"]
    assert_equal "Romans 8", data["chapter_reference"]
  end

  test "a whole-chapter call has no landing verse" do
    get reference_check_path(q: "romans 8")
    data = JSON.parse(response.body)
    assert data["ok"]
    assert_nil data["verse_start"]
  end

  test "a misspelled or bare book name is still understood" do
    get reference_check_path(q: "romams 8:28") # one letter off
    data = JSON.parse(response.body)
    assert data["ok"]
    assert_equal "Rom", data["osis"]

    get reference_check_path(q: "Romans")
    data = JSON.parse(response.body)
    assert data["ok"]
    assert_equal 1, data["chapter"]
  end

  test "an unreadable reference is refused" do
    get reference_check_path(q: "blorbity 99")
    refute JSON.parse(response.body)["ok"]
  end

  test "verse_chapter returns the whole chapter of a reference for the queue's preview" do
    kjv = Translation.create!(code: "KJV", name: "King James Version")
    (27..29).each { |v| Verse.create!(translation: kjv, book: @rom, chapter: 8, verse_number: v, text: "Rom 8:#{v}") }
    get verse_chapter_path(q: "rom 8:28", translation: kjv.id)
    data = JSON.parse(response.body)
    assert data["ok"]
    assert_equal "Romans 8:28", data["label"]
    assert_equal 28, data["verse_start"]
    assert_equal "KJV", data["translation"]
    assert_equal [ 27, 28, 29 ], data["verses"].map { |v| v["num"] }
    assert_equal "Rom 8:28", data["verses"][1]["text"]

    get verse_chapter_path(q: "blorbity 9")
    refute JSON.parse(response.body)["ok"]
  end

  test "a parseable book we have not seeded is refused" do
    get reference_check_path(q: "gen 1") # valid in the canon, absent from Books
    refute JSON.parse(response.body)["ok"]
  end
end
