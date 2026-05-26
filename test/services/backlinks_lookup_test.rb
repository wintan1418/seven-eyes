require "test_helper"

class BacklinksLookupTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @john = Book.create!(osis_code: "John", name: "John", testament: :new,
                         position: 43, chapter_count: 21)
    @rom  = Book.create!(osis_code: "Rom",  name: "Romans", testament: :new,
                         position: 45, chapter_count: 16)
  end

  test "finds a pane whose notes wiki-link to the requested verse" do
    study = @user.studies.create!(name: "Atonement", pane_count: 1)
    study.panes.first.update!(reference: "Rom 5:1", notes: "Echoes of [[John 3:16]] here.")

    matches = BacklinksLookup.for(user: @user, book: @john, chapter: 3, verse: 16)
    assert_equal 1, matches.size
    assert_equal study, matches.first.study
    assert_match(/John 3:16/, matches.first.snippet)
  end

  test "matches abbreviated/alias forms through ReferenceParser" do
    study = @user.studies.create!(name: "Mixed", pane_count: 1)
    study.panes.first.update!(notes: "See [[Jn 3:16]] and [[romans 5:1]].")

    john_matches = BacklinksLookup.for(user: @user, book: @john, chapter: 3, verse: 16)
    rom_matches  = BacklinksLookup.for(user: @user, book: @rom,  chapter: 5, verse: 1)
    assert_equal 1, john_matches.size
    assert_equal 1, rom_matches.size
  end

  test "ignores other users' notes" do
    other = users(:two)
    other.studies.create!(name: "Theirs", pane_count: 1)
         .panes.first.update!(notes: "[[John 3:16]] is mine.")

    matches = BacklinksLookup.for(user: @user, book: @john, chapter: 3, verse: 16)
    assert_empty matches
  end

  test "ignores notes without wiki-link syntax" do
    study = @user.studies.create!(name: "Plain", pane_count: 1)
    study.panes.first.update!(notes: "Just talking about John 3:16 without brackets.")

    matches = BacklinksLookup.for(user: @user, book: @john, chapter: 3, verse: 16)
    assert_empty matches
  end

  test "verse range in a note covers an inner verse" do
    study = @user.studies.create!(name: "Range", pane_count: 1)
    study.panes.first.update!(notes: "Whole gospel: [[John 3:14-18]]")

    matches = BacklinksLookup.for(user: @user, book: @john, chapter: 3, verse: 16)
    assert_equal 1, matches.size
  end

  test "returns nothing when user is nil (guest)" do
    assert_empty BacklinksLookup.for(user: nil, book: @john, chapter: 3, verse: 16)
  end
end
