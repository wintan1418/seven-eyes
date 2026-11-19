require "test_helper"

# My Media's JSON (the console's My Media view): the signed-in account's own
# pictures only; upload into the library, deduped.
class MediaAssetsTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
  end

  def json_headers = { "Accept" => "application/json" }

  test "guests get a 401 and nothing is stored" do
    get media_assets_path, headers: json_headers
    assert_response :unauthorized
    post media_assets_path, params: { file: picture_upload }, headers: json_headers
    assert_response :unauthorized
    assert_equal 0, MediaAsset.count
  end

  test "lists only my pictures, with how many of my services use each" do
    mine = library_picture(@user)
    library_picture(users(:two), "giving.jpg", title: "Someone else's")
    study = @user.studies.create!(name: "Sunday")
    study.setlist_items.create!(SetlistItem.picture_attrs_from(mine))
    sign_in_as @user

    get media_assets_path, headers: json_headers
    assert_response :success
    body = response.parsed_body
    assert_equal [ mine.id ], body["assets"].map { |a| a["id"] }
    asset = body["assets"].first
    assert_equal 1, asset["services"]
    assert_equal mine.media_url, asset["url"]
    assert_match %r{/rails/active_storage/representations/}, asset["thumb"]
    assert_equal({ "fit" => "fit", "zoom" => 100 }, asset["display"])
    assert_equal MediaAsset::QUOTA_BYTES, body["quota_bytes"]
    assert_equal mine.byte_size, body["used_bytes"]
    assert_no_match "Someone else's", response.body
  end

  test "upload: created once, the same file again is the same entry" do
    sign_in_as @user
    post media_assets_path, params: { file: picture_upload, width: 640, height: 360 }, headers: json_headers
    assert_response :created
    first = response.parsed_body
    assert first["created"]
    assert_equal 640, first.dig("asset", "width")
    assert_equal "welcome flyer", first.dig("asset", "title")

    assert_no_difference [ "MediaAsset.count", "ActiveStorage::Blob.count" ] do
      post media_assets_path, params: { file: picture_upload }, headers: json_headers
    end
    assert_response :ok
    assert_not response.parsed_body["created"]
    assert_equal first.dig("asset", "id"), response.parsed_body.dig("asset", "id")
  end

  test "the same file from two accounts is two private entries" do
    sign_in_as users(:two)
    post media_assets_path, params: { file: picture_upload }, headers: json_headers
    theirs = response.parsed_body.dig("asset", "id")
    sign_out
    sign_in_as @user
    post media_assets_path, params: { file: picture_upload }, headers: json_headers
    assert_response :created
    assert_not_equal theirs, response.parsed_body.dig("asset", "id")
    get media_assets_path, headers: json_headers
    assert_equal 1, response.parsed_body["assets"].size
  end

  test "refused uploads say why" do
    sign_in_as @user
    post media_assets_path, params: { file: bytes_upload("hi", type: "text/plain", name: "a.txt") }, headers: json_headers
    assert_response :unprocessable_entity
    assert_match(/isn't a picture/, response.parsed_body["error"])
    post media_assets_path, params: { file: bytes_upload("0" * (PictureUpload::MAX_BYTES + 1)) }, headers: json_headers
    assert_match(/over 5 MB/, response.parsed_body["error"])
  end
end
