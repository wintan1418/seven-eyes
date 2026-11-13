require "test_helper"

class FaithTermTest < ActiveSupport::TestCase
  def term(name, **attrs)
    FaithTerm.create!({ name:, short_definition: "#{name} defined." }.merge(attrs))
  end

  test "slug comes from the name, is unique and URL-safe" do
    grace = term("Lord's Supper")
    assert_equal "lord-s-supper", grace.slug
    assert_equal "lord-s-supper", grace.to_param

    dup = FaithTerm.new(name: "Lord's Supper", short_definition: "x")
    assert_not dup.valid?
    assert dup.errors.of_kind?(:slug, :taken)

    bad = FaithTerm.new(name: "Grace", slug: "Grace Bad!", short_definition: "x")
    assert_not bad.valid?
    assert bad.errors[:slug].any?
  end

  test "terms start as drafts" do
    assert term("Grace").draft?
  end

  test "visible_to: the public and ordinary users see reviewed terms only; admins and reviewers see drafts" do
    reviewed = term("Grace", status: :reviewed)
    draft = term("Faith")

    assert_equal [ reviewed ], FaithTerm.visible_to(nil).to_a
    assert_equal [ reviewed ], FaithTerm.visible_to(users(:one)).to_a

    users(:one).update!(admin: true)
    assert_equal [ draft, reviewed ].sort_by(&:id), FaithTerm.visible_to(users(:one)).order(:id).to_a

    users(:two).update!(reviewer: true)
    assert_includes FaithTerm.visible_to(users(:two)), draft
  end

  test "of_the_day: the same term all day, a new one the next day, cycling through every visible term" do
    terms = 3.times.map { |i| term("Term #{i}", position: i, status: :reviewed) }
    day = Date.new(2026, 11, 13)

    assert_equal FaithTerm.of_the_day(day), FaithTerm.of_the_day(day)
    picks = 3.times.map { |i| FaithTerm.of_the_day(day + i) }
    assert_equal terms.sort_by(&:id), picks.sort_by(&:id), "three days walk all three terms"
    assert_equal picks.first, FaithTerm.of_the_day(day + 3), "and then start again"
  end

  test "of_the_day ignores drafts by default and is nil when nothing is reviewed" do
    term("Draft only")
    assert_nil FaithTerm.of_the_day(Date.new(2026, 11, 13))

    reviewed = term("Grace", status: :reviewed)
    assert_equal reviewed, FaithTerm.of_the_day(Date.new(2026, 11, 13))
  end

  test "mark_reviewed! records who and when; send_back_to_draft! clears it" do
    grace = term("Grace")
    grace.mark_reviewed!(by: "  Pastor  Ade ")
    assert grace.reviewed?
    assert_equal "Pastor Ade", grace.reviewed_by
    assert_in_delta Time.current, grace.reviewed_at, 5

    grace.send_back_to_draft!
    assert grace.draft?
    assert_nil grace.reviewed_by
    assert_nil grace.reviewed_at
  end

  test "Strong's numbers and references are tidied and checked" do
    grace = FaithTerm.new(name: "Grace", short_definition: "x", root_strongs: [ " g5485 ", "H2580", "G5485" ],
                          key_references: [ "Eph 2:8-9", " ", "Romans 3:24" ], related_slugs: [ "Mercy", "faith " ])
    assert grace.valid?, grace.errors.full_messages.inspect
    assert_equal %w[ G5485 H2580 ], grace.root_strongs
    assert_equal [ "Eph 2:8-9", "Romans 3:24" ], grace.key_references
    assert_equal %w[ mercy faith ], grace.related_slugs

    grace.root_strongs = [ "grace" ]
    grace.key_references = [ "Hezekiah 4:1", "John 3" ]
    assert_not grace.valid?
    assert grace.errors[:root_strongs].any?
    assert_match "Hezekiah 4:1", grace.errors[:key_references].join
    assert_match "John 3", grace.errors[:key_references].join, "a whole chapter is not a key verse"
  end

  test "root_entries keep the listed order and skip numbers the lexicon lacks" do
    LexiconEntry.create!(strongs: "G5485", language: "greek", lemma: "χάρις", translit: "cháris")
    LexiconEntry.create!(strongs: "H2580", language: "hebrew", lemma: "חֵן", translit: "chên")
    grace = term("Grace", root_strongs: %w[ H2580 G9999 G5485 ])
    assert_equal %w[ H2580 G5485 ], grace.root_entries.map(&:strongs)
  end

  test "related_terms only lists terms the viewer may see, in the order given" do
    mercy = term("Mercy", status: :reviewed)
    term("Faith")
    hope = term("Hope", status: :reviewed)
    grace = term("Grace", related_slugs: %w[ hope faith mercy ])
    assert_equal [ hope, mercy ], grace.related_terms
    assert_equal 3, grace.related_terms(FaithTerm.all).size
  end

  test "search_text covers the name, aliases and definition" do
    born = term("Regeneration", aliases: [ "Born again" ], short_definition: "The new birth.")
    assert_includes born.search_text, "born again"
    assert_includes born.search_text, "new birth"
    assert_equal "R", born.letter
  end
end
