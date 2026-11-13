require "test_helper"

class FaithTermSeederTest < ActiveSupport::TestCase
  setup do
    @dir = Dir.mktmpdir
    @path = File.join(@dir, "terms.yml")
    write_terms("God's undeserved favour.")
  end

  teardown { FileUtils.remove_entry(@dir) }

  def write_terms(grace_short)
    File.write(@path, [
      { "name" => "Grace", "slug" => "grace", "aliases" => [ "favour" ], "short" => grace_short,
        "new_believer" => "It is a gift.", "explanation" => "A longer word.", "roots" => [ "G5485" ],
        "verses" => [ "Ephesians 2:8-9" ], "related" => [ "faith" ] },
      { "name" => "Faith", "slug" => "faith", "short" => "Trusting God.", "roots" => [], "verses" => [ "Hebrews 11:1" ] }
    ].to_yaml)
  end

  test "creates every term as a draft, in file order" do
    assert_equal({ created: 2, updated: 0, kept: 0 }, FaithTermSeeder.call(@path))
    grace = FaithTerm.find_by!(slug: "grace")
    assert grace.draft?
    assert_equal 1, grace.position
    assert_equal [ "G5485" ], grace.root_strongs
    assert_equal [ "Ephesians 2:8-9" ], grace.key_references
    assert_equal 2, FaithTerm.find_by!(slug: "faith").position
  end

  test "is idempotent and refreshes untouched drafts only" do
    FaithTermSeeder.call(@path)
    assert_equal({ created: 0, updated: 0, kept: 2 }, FaithTermSeeder.call(@path))

    write_terms("Freshly worded.")
    assert_equal({ created: 0, updated: 1, kept: 1 }, FaithTermSeeder.call(@path))
    assert_equal "Freshly worded.", FaithTerm.find_by!(slug: "grace").short_definition
  end

  test "never touches a reviewed or site-edited term" do
    FaithTermSeeder.call(@path)
    FaithTerm.find_by!(slug: "grace").mark_reviewed!(by: "Pastor")
    FaithTerm.find_by!(slug: "faith").update!(short_definition: "Pastor's words.", edited_at: Time.current)

    write_terms("Changed in the file.")
    FaithTermSeeder.call(@path)
    assert_equal "God's undeserved favour.", FaithTerm.find_by!(slug: "grace").short_definition
    assert FaithTerm.find_by!(slug: "grace").reviewed?
    assert_equal "Pastor's words.", FaithTerm.find_by!(slug: "faith").short_definition
  end

  test "the shipped glossary loads cleanly and every term is a draft" do
    counts = FaithTermSeeder.call
    assert_operator counts[:created], :>=, 40
    assert FaithTerm.all.all?(&:draft?)
    slugs = FaithTerm.pluck(:slug)
    FaithTerm.find_each do |t|
      assert t.key_references.size.between?(3, 6), "#{t.name}: 3–6 key verses"
      assert_empty t.related_slugs - slugs, "#{t.name}: related terms exist"
    end
  end
end
