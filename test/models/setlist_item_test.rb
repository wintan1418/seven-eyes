require "test_helper"

class SetlistItemTest < ActiveSupport::TestCase
  setup do
    Book.create!(osis_code: "Rom", name: "Romans", testament: :new, position: 45, chapter_count: 16)
    @study = users(:one).studies.create!(name: "Sunday", pane_count: 1)
  end

  test "scripture items must carry a parseable, seeded reference" do
    assert @study.setlist_items.create(kind: :scripture, reference: "rom 8:28").persisted?
    refute @study.setlist_items.create(kind: :scripture, reference: "blorbity 9").persisted?
    refute @study.setlist_items.create(kind: :scripture, reference: "gen 1").persisted? # canon-valid, not seeded
    refute @study.setlist_items.create(kind: :scripture).persisted?
  end

  test "songs and thoughts need a title or words" do
    assert @study.setlist_items.create(kind: :song, title: "Amazing Grace").persisted?
    assert @study.setlist_items.create(kind: :thought, body: "Welcome to the service").persisted?
    refute @study.setlist_items.create(kind: :song).persisted?
  end

  test "positions are assigned in sequence and label resolves per kind" do
    a = @study.setlist_items.create!(kind: :scripture, reference: "rom 8:28")
    b = @study.setlist_items.create!(kind: :song, title: "Amazing Grace", body: "v1\n\nv2")
    c = @study.setlist_items.create!(kind: :thought, body: "Remember the building fund\nthis week")
    assert_equal [ 0, 1, 2 ], [ a, b, c ].map(&:position)
    assert_equal "Romans 8:28", a.label
    assert_equal "Amazing Grace", b.label
    assert_equal "Remember the building fund", c.label
  end

  test "stanzas split on blank lines" do
    item = @study.setlist_items.create!(kind: :song, title: "Hymn",
      body: "Amazing grace how sweet\nthe sound\n\nThrough many dangers\n\n\nWhen we've been there")
    assert_equal 3, item.stanzas.size
    assert_equal "Amazing grace how sweet\nthe sound", item.stanzas.first
  end

  test "a song's sections and arrangement decide its slides; plain songs are unchanged" do
    body = "[Verse 1]\nBlessed assurance\n\n[Chorus]\nThis is my story\n\n[Verse 2]\nPerfect submission\n\n[Bridge]\nOh yes"
    song = @study.setlist_items.create!(kind: :song, title: "Assurance", body: body)
    assert_equal [ "Blessed assurance", "This is my story", "Perfect submission", "Oh yes" ], song.stanzas

    song.update!(arrangement: "V1 C V2 C B C")
    assert_equal [ "Blessed assurance", "This is my story", "Perfect submission", "This is my story", "Oh yes", "This is my story" ],
                 song.stanzas
    assert_equal 6, song.as_queue_json[:stanzas]
    assert_equal "V1 C V2 C B C", song.as_queue_json[:arrangement]

    hymn = @study.setlist_items.create!(kind: :song, title: "Hymn", body: "[Verse 1]\na\n\n[Refrain]\nr\n\n[Verse 2]\nb")
    assert_equal %w[a r b r], hymn.stanzas # the refrain follows every verse

    refute @study.setlist_items.create(kind: :song, title: "Long", body: "x", arrangement: "V1 " * 100).persisted?
  end

  test "the song library offers saved songs, then past songs, then the hymnal — deduped" do
    @study.setlist_items.create!(kind: :song, title: "Jajaj", body: "past words")
    users(:one).songs.create!(title: "jajaj", body: "Matthew 28:20 AMP\nteaching them\n\nMark 1:1 BSB\nThe beginning", arrangement: "")
    library = SetlistItem.song_library_for(@study)
    jajaj = library.select { |s| s[:title].casecmp?("jajaj") }
    assert_equal 1, jajaj.size
    assert jajaj.first[:saved]
    assert_match(/Mark 1:1 BSB/, jajaj.first[:body])
    hymn = library.find { |s| s[:title] == "Holy, Holy, Holy" }
    assert_equal "Public domain", hymn[:copyright]
    assert hymn[:author].present?
  end

  test "the song library offers the hymnal plus the account's own songs, deduped" do
    @study.setlist_items.create!(kind: :song, title: "Our Anthem", body: "verse one")
    # A second study under the same owner contributes too.
    other = users(:one).studies.create!(name: "Midweek", pane_count: 1)
    other.setlist_items.create!(kind: :song, title: "Amazing Grace", body: "our edited words")

    library = SetlistItem.song_library_for(@study)
    titles = library.map { |s| s[:title] }
    assert_includes titles, "Our Anthem"
    assert_includes titles, "Holy, Holy, Holy" # straight from the hymnal

    # The owner's own "Amazing Grace" wins over the hymnal default (deduped).
    grace = library.find { |s| s[:title] == "Amazing Grace" }
    assert_equal "our edited words", grace[:body]
    assert_equal "yours", grace[:source]
    assert_equal 1, titles.count("Amazing Grace")
  end

  test "a guest's song library is scoped to their own session study" do
    guest = Study.create!(name: "Guest", pane_count: 1) # user_id nil
    users(:one).studies.create!(name: "Someone else", pane_count: 1)
            .setlist_items.create!(kind: :song, title: "Private Song", body: "x")

    titles = SetlistItem.song_library_for(guest).map { |s| s[:title] }
    refute_includes titles, "Private Song"
    assert_includes titles, "Amazing Grace" # the hymnal is still offered
  end

  test "a study holds at most PICTURE_LIMIT pictures" do
    SetlistItem::PICTURE_LIMIT.times do |i|
      @study.setlist_items.create!(kind: :picture, media_url: "https://res.cloudinary.com/demo/#{i}.jpg")
    end
    extra = @study.setlist_items.create(kind: :picture, media_url: "https://res.cloudinary.com/demo/x.jpg")
    refute extra.persisted?
    assert_match(/at most #{SetlistItem::PICTURE_LIMIT} pictures/, extra.errors.full_messages.to_sentence)
  end

  test "move! swaps neighbours and clamps at the edges" do
    a = @study.setlist_items.create!(kind: :song, title: "A")
    b = @study.setlist_items.create!(kind: :song, title: "B")
    c = @study.setlist_items.create!(kind: :song, title: "C")

    b.move!(:up)
    assert_equal %w[B A C], @study.setlist_items.in_order.map(&:title)

    b.move!(:up) # already first — no-op
    assert_equal %w[B A C], @study.setlist_items.in_order.map(&:title)

    a.move!(:down)
    assert_equal %w[B C A], @study.setlist_items.in_order.map(&:title)
  end
end
