require "test_helper"

class MediaBackfillTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @sunday = @user.studies.create!(name: "Sunday")
    @midweek = @user.studies.create!(name: "Midweek")
  end

  # A queue picture as the app made them before My Media: its own blob.
  def legacy_picture(study, name = "welcome_flyer.png", title: "Welcome", data: {})
    blob = ActiveStorage::Blob.create_and_upload!(io: File.open(Rails.root.join("test/fixtures/files", name)), filename: name)
    url = Rails.application.routes.url_helpers.rails_blob_path(blob, only_path: true)
    study.setlist_items.create!(kind: :picture, title: title, media_url: url, picture_file: blob, data: data)
  end

  test "collects signed-in users' pictures into their libraries, one entry per file" do
    a = legacy_picture(@sunday, data: { "fit" => "fill", "zoom" => 120 })
    b = legacy_picture(@midweek, title: "Welcome again") # the same file, uploaded again
    c = legacy_picture(@midweek, "giving.jpg", title: nil)

    stats = MediaBackfill.run
    assert_equal({ linked: 3, created: 2, skipped: 0 }, stats)

    assets = @user.media_assets.order(:id).to_a
    assert_equal 2, assets.size
    flyer = assets.first
    assert_equal "Welcome", flyer.title
    assert_equal({ "fit" => "fill", "zoom" => 120 }, flyer.display)
    assert_equal a.picture_file.blob.checksum, flyer.checksum
    assert_equal a.picture_file.blob, flyer.file.blob, "reuses the queue's blob — nothing re-uploaded"
    assert_equal [ flyer.id, flyer.id ], [ a.reload.media_asset_id, b.reload.media_asset_id ]
    assert_equal "giving", assets.last.title
    assert_equal assets.last.id, c.reload.media_asset_id
  end

  test "is idempotent" do
    legacy_picture(@sunday)
    MediaBackfill.run
    assert_no_difference [ "MediaAsset.count", "ActiveStorage::Blob.count" ] do
      assert_equal({ linked: 0, created: 0, skipped: 0 }, MediaBackfill.run)
    end
  end

  test "Cloudinary pictures are matched by their public id; guests' pictures are left alone" do
    url = "https://res.cloudinary.com/demo/image/upload/v1/q/x.jpg"
    @sunday.setlist_items.create!(kind: :picture, title: "Old", media_url: url, media_public_id: "q/x")
    @midweek.setlist_items.create!(kind: :picture, title: "Old", media_url: url, media_public_id: "q/x")
    guest = Study.create!(name: "Guest")
    guest.setlist_items.create!(kind: :picture, media_url: "https://res.cloudinary.com/demo/g.jpg")

    MediaBackfill.run
    asset = @user.media_assets.sole
    assert_equal url, asset.media_url
    assert_equal "q/x", asset.media_public_id
    assert_not asset.file.attached?
    assert_nil guest.setlist_items.first.media_asset_id
  end

  test "joins a picture already in the library and works in batches" do
    existing = library_picture(@user)
    blob = existing.file.blob
    url = Rails.application.routes.url_helpers.rails_blob_path(blob, only_path: true)
    items = Array.new(3) { @sunday.setlist_items.create!(kind: :picture, media_url: url, picture_file: blob) }

    stub_const(MediaBackfill, :BATCH, 2) { MediaBackfill.run }
    assert_equal [ existing.id ] * 3, items.map { |i| i.reload.media_asset_id }
    assert_equal 1, @user.media_assets.count
  end

  private

  def stub_const(klass, name, value)
    old = klass.const_get(name)
    klass.send(:remove_const, name)
    klass.const_set(name, value)
    yield
  ensure
    klass.send(:remove_const, name)
    klass.const_set(name, old)
  end
end
