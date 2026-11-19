require "test_helper"

class MediaLibraryTest < ActiveSupport::TestCase
  setup { @user = users(:one) }

  test "adds a picture once: the same file again is found, not uploaded" do
    first = MediaLibrary.add(@user, picture_upload, width: "640", height: "360")
    assert first.ok?
    assert first.created
    assert_equal [ 640, 360 ], [ first.asset.width, first.asset.height ]
    assert_equal "welcome flyer", first.asset.title
    assert_equal File.size(Rails.root.join("test/fixtures/files/welcome_flyer.png")), first.asset.byte_size

    assert_no_difference [ "ActiveStorage::Blob.count", "MediaAsset.count" ] do
      again = MediaLibrary.add(@user, picture_upload)
      assert again.ok?
      assert_not again.created
      assert_equal first.asset, again.asset
    end
  end

  test "each account keeps its own library" do
    mine = MediaLibrary.add(@user, picture_upload).asset
    theirs = MediaLibrary.add(users(:two), picture_upload).asset
    assert_not_equal mine, theirs
    assert_equal users(:two), theirs.user
  end

  test "a given title wins; nonsense dimensions are ignored" do
    asset = MediaLibrary.add(@user, picture_upload("giving.jpg"), title: "Offering", width: "abc", height: "-3").asset
    assert_equal "Offering", asset.title
    assert_nil asset.width
    assert_nil asset.height
    assert_equal "image/jpeg", asset.content_type
  end

  test "refuses what isn't a picture, too large, or missing — before storing anything" do
    assert_no_difference [ "ActiveStorage::Blob.count", "MediaAsset.count" ] do
      assert_equal :not_image, MediaLibrary.add(@user, bytes_upload("hello", type: "text/plain", name: "a.txt")).error
      assert_equal :too_large, MediaLibrary.add(@user, bytes_upload("0" * (PictureUpload::MAX_BYTES + 1))).error
      assert_equal :missing, MediaLibrary.add(@user, nil).error
    end
  end

  test "a full library says so" do
    @user.media_assets.create!(title: "Big", media_url: "/x", byte_size: MediaAsset::QUOTA_BYTES)
    result = MediaLibrary.add(@user, picture_upload)
    assert_equal :full, result.error
    assert_match(/library is full/, result.message)
  end
end
