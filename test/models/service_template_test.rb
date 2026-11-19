require "test_helper"

class ServiceTemplateTest < ActiveSupport::TestCase
  test "keeps the known kinds and fields; a picture only as one of the account's own My Media entries" do
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

  test "pictures are kept by their library entry, never someone else's" do
    mine = library_picture(users(:one), title: "Welcome flyer")
    theirs = library_picture(users(:two))
    t = ServiceTemplate.save_for!(users(:one), "tpl-pic", name: "Sunday", items: [
      { "kind" => "picture", "media_asset_id" => mine.id, "title" => "Welcome", "data" => { "fit" => "fill" }, "image" => "/evil" },
      { "kind" => "picture", "media_asset_id" => theirs.id },
      { "kind" => "picture", "media_asset_id" => "x" },
      { "kind" => "thought", "title" => "Notices" }
    ])
    assert_equal [ { "kind" => "picture", "media_asset_id" => mine.id, "title" => "Welcome", "data" => { "fit" => "fill", "zoom" => 100 } },
                   { "kind" => "thought", "title" => "Notices" } ], t.items

    json = t.as_device_json
    assert_equal mine.media_url, json[:items].first["image"]
    assert json[:items].first["thumb"].present?
  end

  test "start! queues the template's pictures from My Media; one deleted since is skipped" do
    flyer = library_picture(users(:one), title: "Welcome flyer")
    gone = library_picture(users(:one), "giving.jpg")
    t = ServiceTemplate.save_for!(users(:one), "tpl-pics", name: "Sunday", items: [
      { "kind" => "picture", "media_asset_id" => flyer.id, "data" => { "fit" => "fill", "zoom" => 110 } },
      { "kind" => "picture", "media_asset_id" => gone.id },
      { "kind" => "song", "title" => "Hymn", "body" => "Words" }
    ])
    gone.destroy
    assert_equal 2, t.as_device_json[:items].size

    study = t.start!(date: Date.new(2026, 11, 22))
    items = study.setlist_items.in_order.to_a
    assert_equal %w[picture song], items.map(&:kind)
    picture = items.first
    assert_equal flyer, picture.media_asset
    assert_equal "Welcome flyer", picture.title
    assert_equal({ "fit" => "fill", "zoom" => 110 }, picture.data)
    assert_equal flyer.file.blob, picture.picture_file.blob
  end
end
