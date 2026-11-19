require "test_helper"

# My Media (/media): the account's picture library — page, JSON for the
# console, upload, rename / default display, delete; always the signed-in
# account's own pictures only.
class MediaAssetsTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
  end

  test "guests get a sign-in pitch on the page and 401 everywhere else" do
    get media_assets_path
    assert_response :success
    assert_select "a[href=?]", new_session_path
    assert_select ".mm-grid", count: 0

    get media_assets_path(format: :json)
    assert_response :unauthorized
    post media_assets_path, params: { file: picture_upload }, as: :json
    assert_response :unauthorized
    assert_equal 0, MediaAsset.count
  end

  test "the page lists only my pictures, with storage used" do
    mine = library_picture(@user, title: "Welcome flyer")
    library_picture(users(:two), "giving.jpg", title: "Someone else's")
    sign_in_as @user

    get media_assets_path
    assert_response :success
    assert_select ".mm-card", count: 1
    assert_select "##{ActionView::RecordIdentifier.dom_id(mine)} input[name=title][value=?]", "Welcome flyer"
    assert_select ".mm-storage", text: /of 1 GB used/
    assert_select ".mm-card", text: /Not in a service/
    assert_no_match "Someone else's", response.body
  end

  test "JSON for the console: my pictures with how many services use each" do
    mine = library_picture(@user)
    library_picture(users(:two))
    study = @user.studies.create!(name: "Sunday")
    study.setlist_items.create!(SetlistItem.picture_attrs_from(mine))
    sign_in_as @user

    get media_assets_path(format: :json)
    body = response.parsed_body
    assert_equal [ mine.id ], body["assets"].map { |a| a["id"] }
    asset = body["assets"].first
    assert_equal 1, asset["services"]
    assert_equal mine.media_url, asset["url"]
    assert_equal({ "fit" => "fit", "zoom" => 100 }, asset["display"])
    assert_equal MediaAsset::QUOTA_BYTES, body["quota_bytes"]
    assert_equal mine.byte_size, body["used_bytes"]
  end

  test "upload (JSON): created once, the same file again is the same entry" do
    sign_in_as @user
    post media_assets_path, params: { file: picture_upload, width: 640, height: 360 }, headers: { "Accept" => "application/json" }
    assert_response :created
    first = response.parsed_body
    assert first["created"]
    assert_equal 640, first.dig("asset", "width")

    assert_no_difference [ "MediaAsset.count", "ActiveStorage::Blob.count" ] do
      post media_assets_path, params: { file: picture_upload }, headers: { "Accept" => "application/json" }
    end
    assert_response :ok
    assert_not response.parsed_body["created"]
    assert_equal first.dig("asset", "id"), response.parsed_body.dig("asset", "id")
  end

  test "upload (Turbo Stream, the page): the card arrives and storage updates" do
    sign_in_as @user
    post media_assets_path, params: { file: picture_upload("giving.jpg") }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_equal "1", response.headers["X-Media-Created"]
    assert_match(/turbo-stream action="prepend" target="media-grid"/, response.body)
    assert_match(/turbo-stream action="update" target="media-storage"/, response.body)
  end

  test "refused uploads say why" do
    sign_in_as @user
    post media_assets_path, params: { file: bytes_upload("hi", type: "text/plain", name: "a.txt") }, headers: { "Accept" => "application/json" }
    assert_response :unprocessable_entity
    assert_match(/isn't a picture/, response.parsed_body["error"])

    post media_assets_path, params: { file: bytes_upload("hi", type: "text/plain", name: "a.txt") }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :unprocessable_entity
    assert_match(/target="media-status"/, response.body)
  end

  test "rename and set the default display" do
    asset = library_picture(@user)
    sign_in_as @user
    patch media_asset_path(asset), params: { title: "Welcome — new", fit: "fill", zoom: "150" }, headers: { "Accept" => "application/json" }
    assert_response :success
    asset.reload
    assert_equal "Welcome — new", asset.title
    assert_equal({ "fit" => "fill", "zoom" => 150 }, asset.display)

    patch media_asset_path(asset), params: { fit: "stretch" }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_match(/turbo-stream action="replace"/, response.body)
    assert_equal({ "fit" => "stretch", "zoom" => 150 }, asset.reload.display)

    patch media_asset_path(asset), params: { title: " " }, headers: { "Accept" => "application/json" }
    assert_response :unprocessable_entity
  end

  test "another account's picture is a 404 for every action" do
    theirs = library_picture(users(:two))
    sign_in_as @user
    patch media_asset_path(theirs), params: { title: "Mine now" }, headers: { "Accept" => "application/json" }
    assert_response :not_found
    delete media_asset_path(theirs), headers: { "Accept" => "application/json" }
    assert_response :not_found
    assert_equal "welcome flyer", theirs.reload.title
  end

  test "deleting a picture a service uses: the service keeps it" do
    asset = library_picture(@user)
    study = @user.studies.create!(name: "Sunday")
    item = study.setlist_items.create!(SetlistItem.picture_attrs_from(asset))
    sign_in_as @user

    get media_assets_path
    assert_select ".mm-del[data-turbo-confirm*=?]", "Those services keep showing it"

    delete media_asset_path(asset), headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_match(/turbo-stream action="remove"/, response.body)
    assert_not MediaAsset.exists?(asset.id)
    item.reload
    assert item.picture?
    assert item.picture_file.attached?
    assert_equal asset.media_url, item.media_url

    get study_path(study)
    assert_response :success
    assert_select ".ps-setlist-item.kind-picture img.thumb[src=?]", asset.media_url
  end

  test "the same file from two accounts is two private entries" do
    sign_in_as users(:two)
    post media_assets_path, params: { file: picture_upload }, headers: { "Accept" => "application/json" }
    theirs = response.parsed_body.dig("asset", "id")
    sign_out
    sign_in_as @user
    post media_assets_path, params: { file: picture_upload }, headers: { "Accept" => "application/json" }
    assert_response :created
    assert_not_equal theirs, response.parsed_body.dig("asset", "id")
    get media_assets_path(format: :json)
    assert_equal 1, response.parsed_body["assets"].size
  end

  test "thumbnails load lazily on the page" do
    library_picture(@user)
    sign_in_as @user
    get media_assets_path
    assert_select ".mm-card img[loading=lazy][decoding=async][data-full]"
  end
end
