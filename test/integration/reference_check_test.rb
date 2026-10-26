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

  test "a parseable book we have not seeded is refused" do
    get reference_check_path(q: "gen 1") # valid in the canon, absent from Books
    refute JSON.parse(response.body)["ok"]
  end
end
