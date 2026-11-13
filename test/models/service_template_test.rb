require "test_helper"

class ServiceTemplateTest < ActiveSupport::TestCase
  test "keeps the known kinds and fields, never pictures" do
    t = ServiceTemplate.save_for!(users(:one), "tpl-1", name: "Midweek", items: [
      { "kind" => "thought", "title" => "Welcome", "evil" => 1 },
      { "kind" => "picture", "title" => "Flyer" },
      { "kind" => "presentation", "title" => "Deck", "data" => { "deck" => "deck-1", "pages" => 4 } },
      { "kind" => "nope" }
    ])
    assert_equal [ { "kind" => "thought", "title" => "Welcome" }, { "kind" => "presentation", "title" => "Deck", "data" => { "deck" => "deck-1", "pages" => 4, "source" => "pdf" } } ], t.items
  end

  test "start! makes a dated study with the order queued, skipping what no longer validates" do
    t = ServiceTemplate.save_for!(users(:one), "tpl-2", name: "Midweek", items: [ { "kind" => "song", "title" => "Hymn", "body" => "Words" }, { "kind" => "scripture", "reference" => "Nowhere 99:1" } ])
    study = t.start!(date: Date.new(2026, 11, 18))
    assert_equal "Midweek — 18 Nov 2026", study.name
    assert_equal [ "Hymn" ], study.setlist_items.map(&:title)
  end
end
