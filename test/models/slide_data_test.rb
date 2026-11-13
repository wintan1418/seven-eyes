require "test_helper"

class SlideDataTest < ActiveSupport::TestCase
  test "a scripture set keeps known fields, uppercases the Bible and drops empty passages" do
    data = SlideData.clean("scripture_set", { "refs" => [
      { "reference" => "Col 2:2", "translation" => "kjv", "verses" => [ { "c" => "2", "n" => "2", "text" => " Words " } ], "evil" => 1 },
      { "reference" => "Col 9:9", "verses" => [] }
    ], "ref_position" => "sideways", "verse_numbers" => "false" })
    assert_equal [ { "reference" => "Col 2:2", "translation" => "KJV", "label" => "Col 2:2", "verses" => [ { "c" => 2, "n" => 2, "text" => "Words" } ] } ], data["refs"]
    assert_equal "top", data["ref_position"]
    assert_equal false, data["verse_numbers"]
  end

  test "caps sizes so one item can't carry a whole Bible" do
    refs = Array.new(30) { { "reference" => "Ps 119", "verses" => Array.new(200) { |i| { "c" => 119, "n" => i + 1, "text" => "x" } } } }
    data = SlideData.clean("scripture_set", { "refs" => refs })
    assert_equal SlideData::MAX_REFS, data["refs"].size
    assert_equal SlideData::MAX_VERSES, data["refs"].first["verses"].size
  end

  test "a presentation keeps only a safe deck key and a page count" do
    assert_equal({ "deck" => "deck-1", "pages" => 3, "source" => "pdf" }, SlideData.clean("presentation", { "deck" => "deck-1", "pages" => "3", "url" => "x" }))
    assert_nil SlideData.clean("presentation", { "deck" => "a/b", "pages" => 1 })["deck"]
    assert_equal SlideData::MAX_PAGES, SlideData.clean("presentation", { "deck" => "d", "pages" => 10_000 })["pages"]
  end

  test "a seminar keeps its layouts and local pictures only; other kinds keep nothing" do
    data = SlideData.clean("seminar", { "slides" => [ { "layout" => "quote", "text" => "Love", "image" => "local:img-1" }, { "image" => "javascript:alert(1)" } ], "reveal" => "1" })
    assert_equal [ "quote", "title" ], data["slides"].map { |s| s["layout"] }
    assert_equal [ "local:img-1", "" ], data["slides"].map { |s| s["image"] }
    assert data["reveal"]
    assert_equal({}, SlideData.clean("song", { "x" => 1 }))
  end

  test "labels" do
    assert_equal "Colossians 2:2 KJV + Matthew 28:19 BSB",
                 SlideData.set_label({ "refs" => [ { "label" => "Colossians 2:2", "translation" => "KJV" }, { "label" => "Matthew 28:19", "translation" => "BSB" } ] })
    assert_equal "Why", SlideData.seminar_label({ "slides" => [ { "title" => "" }, { "title" => "Why" } ] })
  end
end
