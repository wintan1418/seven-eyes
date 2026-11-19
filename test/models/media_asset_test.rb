require "test_helper"

class MediaAssetTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = users(:one)
  end

  test "keeps a tidy title, a clean default display and its file" do
    asset = library_picture(@user, title: "  Welcome   flyer ")
    assert_equal "Welcome flyer", asset.title
    assert_equal({ "fit" => "fit", "zoom" => 100 }, asset.display_settings)
    assert asset.file.attached?
    assert_equal asset.file.blob.checksum, asset.checksum
    assert_match %r{\A/rails/active_storage/blobs/}, asset.media_url

    asset.update!(display: { "fit" => "nonsense", "zoom" => 900 })
    assert_equal({ "fit" => "fit", "zoom" => 200 }, asset.reload.display)
  end

  test "needs a title and a picture URL" do
    asset = @user.media_assets.new(title: " ", media_url: "")
    assert_not asset.valid?
    assert asset.errors[:title].any?
    assert asset.errors[:media_url].any?
  end

  test "titles come from the file name" do
    assert_equal "Sunday flyer final", MediaAsset.title_from_filename("Sunday_flyer final.JPG")
    assert_equal "Picture", MediaAsset.title_from_filename("")
    assert_equal "Picture", MediaAsset.title_from_filename(nil)
  end

  test "recent_first: last used first, then newest" do
    old = @user.media_assets.create!(title: "Old", media_url: "/a", created_at: 3.days.ago)
    used = @user.media_assets.create!(title: "Used", media_url: "/b", created_at: 5.days.ago, last_used_at: 1.hour.ago)
    fresh = @user.media_assets.create!(title: "Fresh", media_url: "/c", created_at: 1.day.ago)
    assert_equal [ used, fresh, old ], @user.media_assets.recent_first.to_a
  end

  test "bytes_used and service_counts are per account" do
    a = @user.media_assets.create!(title: "A", media_url: "/a", byte_size: 100)
    users(:two).media_assets.create!(title: "B", media_url: "/b", byte_size: 999)
    assert_equal 100, MediaAsset.bytes_used(@user)

    s1 = @user.studies.create!(name: "One")
    s2 = @user.studies.create!(name: "Two")
    2.times { s1.setlist_items.create!(kind: :picture, media_url: "/a", media_asset: a) }
    s2.setlist_items.create!(kind: :picture, media_url: "/a", media_asset: a)
    assert_equal({ a.id => 2 }, MediaAsset.service_counts([ a ]))
  end

  test "without libvips (production) the grid uses the picture itself; Cloudinary still resizes by URL" do
    asset = library_picture(@user)
    cloud = @user.media_assets.new(title: "C", media_url: "https://res.cloudinary.com/demo/image/upload/v1/q/x.jpg")
    MediaAsset.thumbnails = false
    assert_equal asset.media_url, asset.thumb_url
    assert_match %r{/upload/c_limit,w_480,h_270/}, cloud.thumb_url
  ensure
    MediaAsset.remove_instance_variable(:@thumbnails) if MediaAsset.instance_variable_defined?(:@thumbnails)
  end

  test "a Cloudinary picture's thumbnail is a resized URL" do
    asset = @user.media_assets.new(title: "C", media_url: "https://res.cloudinary.com/demo/image/upload/v1/q/x.jpg")
    assert_equal "https://res.cloudinary.com/demo/image/upload/c_limit,w_480,h_270/v1/q/x.jpg", asset.thumb_url
    assert_match %r{/rails/active_storage/representations/}, library_picture(@user).thumb_url
  end

  test "deleting it from the library keeps it in every service that uses it" do
    asset = library_picture(@user)
    study = @user.studies.create!(name: "Sunday")
    item = study.setlist_items.create!(SetlistItem.picture_attrs_from(asset))
    blob = asset.file.blob

    perform_enqueued_jobs { asset.destroy }

    item.reload
    assert_nil item.media_asset_id
    assert item.picture_file.attached?, "the service keeps its own attachment"
    assert ActiveStorage::Blob.exists?(blob.id), "the file stays while a service uses it"
    assert_equal blob.id, item.picture_file.blob.id
  end

  test "the file goes once nothing uses it" do
    asset = library_picture(@user)
    blob = asset.file.blob
    perform_enqueued_jobs { asset.destroy }
    assert_not ActiveStorage::Blob.exists?(blob.id)
  end

  test "a shared Cloudinary copy is only destroyed when nothing names it" do
    url = "https://res.cloudinary.com/demo/image/upload/v1/q/x.jpg"
    asset = @user.media_assets.create!(title: "C", media_url: url, media_public_id: "q/x")
    study = @user.studies.create!(name: "Sunday")
    item = study.setlist_items.create!(kind: :picture, media_url: url, media_public_id: "q/x", media_asset: asset)
    purged = []
    original = PictureUpload.method(:purge)
    PictureUpload.define_singleton_method(:purge) { |id| purged << id }
    begin
      asset.destroy
      assert_empty purged, "a service still uses it"
      item.destroy
      PictureUpload.purge_unused("q/x")
    ensure
      PictureUpload.define_singleton_method(:purge, original)
    end
    assert_equal [ "q/x" ], purged
  end

  test "a queue item can't point at someone else's picture" do
    theirs = library_picture(users(:two))
    study = @user.studies.create!(name: "Mine")
    item = study.setlist_items.new(kind: :picture, media_url: theirs.media_url, media_asset: theirs)
    assert_not item.valid?
    assert_includes item.errors.full_messages.to_sentence, "isn't in your library"
  end
end
