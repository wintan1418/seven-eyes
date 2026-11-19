require "test_helper"

class SetlistItemsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    Book.create!(osis_code: "Rom", name: "Romans", testament: :new, position: 45, chapter_count: 16)
  end

  def owner_study
    sign_in_as users(:one)
    users(:one).studies.create!(name: "Sunday", pane_count: 1)
  end

  test "the owner can queue a scripture and gets the re-rendered frame" do
    study = owner_study
    post study_setlist_items_path(study), params: { setlist_item: { kind: "scripture", reference: "rom 8:28" } }
    assert_response :success
    assert_select "turbo-frame#setlist .ps-setlist-item[data-kind='scripture'][data-reference='rom 8:28']"
    assert_equal "Romans 8:28", study.setlist_items.in_order.last.label
  end

  test "a song with stanzas is queued as a slide item" do
    study = owner_study
    post study_setlist_items_path(study),
         params: { setlist_item: { kind: "song", title: "Amazing Grace", body: "v one\n\nv two" } }
    assert_response :success
    assert_select ".ps-setlist-item[data-kind='slide']"
    assert_select ".ps-setlist-item .meta", text: "2 slides"
  end

  test "several comma-separated scriptures are queued in one submit" do
    study = owner_study
    Book.create!(osis_code: "John", name: "John", testament: :new, position: 43, chapter_count: 21)
    Book.create!(osis_code: "Ps", name: "Psalms", testament: :old, position: 19, chapter_count: 150)
    assert_difference -> { SetlistItem.count }, 3 do
      post study_setlist_items_path(study),
           params: { setlist_item: { kind: "scripture", reference: "rom 8:28, John 3:16, Ps 23" } }
    end
    assert_response :success
    assert_equal [ "rom 8:28", "John 3:16", "Ps 23" ], study.setlist_items.in_order.map(&:reference)
  end

  test "a batch adds the readable scriptures and reports the unreadable ones" do
    study = owner_study
    assert_difference -> { SetlistItem.count }, 1 do
      post study_setlist_items_path(study),
           params: { setlist_item: { kind: "scripture", reference: "rom 8:28, blorbity 9" } }
    end
    assert_response :success
    assert_equal [ "rom 8:28" ], study.setlist_items.in_order.map(&:reference)
    assert_select ".ps-setlist-form .err", text: /blorbity 9/
  end

  test "an unreadable reference re-renders the form with the error and keeps the text" do
    study = owner_study
    assert_no_difference -> { SetlistItem.count } do
      post study_setlist_items_path(study), params: { setlist_item: { kind: "scripture", reference: "blorbity 9" } }
    end
    assert_response :success
    assert_select ".ps-setlist-form .err"
    assert_select "input.ref-field[value='blorbity 9']"
  end

  test "move and destroy reorder the queue" do
    study = owner_study
    a = study.setlist_items.create!(kind: :song, title: "A")
    b = study.setlist_items.create!(kind: :song, title: "B")

    post move_study_setlist_item_path(study, b, direction: :up)
    assert_response :success
    assert_equal %w[B A], study.setlist_items.in_order.map(&:title)

    delete study_setlist_item_path(study, a)
    assert_response :success
    assert_equal %w[B], study.setlist_items.in_order.map(&:title)
  end

  test "a picture uploads to our own server when no picture host is configured" do
    study = owner_study
    file = Rack::Test::UploadedFile.new(StringIO.new("fake png"), "image/png", original_filename: "slide.png")
    assert_difference -> { SetlistItem.count }, 1 do
      post study_setlist_items_path(study), params: { setlist_item: { kind: "picture", title: "Harvest", image: file } }
    end
    assert_response :success
    item = study.setlist_items.picture.last
    assert item.picture_file.attached?
    assert_match %r{\A/rails/active_storage/blobs/}, item.media_url
    assert_select ".ps-setlist-item img.thumb[src=?]", item.media_url
  end

  test "when the picture host refuses (account disabled) the picture is kept on our server" do
    study = owner_study
    file = Rack::Test::UploadedFile.new(StringIO.new("fake png"), "image/png", original_filename: "slide.png")
    configured = PictureUpload.method(:configured?)
    uploader = Cloudinary::Uploader.method(:upload)
    PictureUpload.define_singleton_method(:configured?) { true }
    Cloudinary::Uploader.define_singleton_method(:upload) { |*| raise CloudinaryException, "cloud_name is disabled" }
    begin
      post study_setlist_items_path(study), params: { setlist_item: { kind: "picture", title: "PRAYER", image: file } }
    ensure
      PictureUpload.define_singleton_method(:configured?, configured)
      Cloudinary::Uploader.define_singleton_method(:upload, uploader)
    end
    item = study.setlist_items.picture.last
    assert_equal "PRAYER", item.title
    assert item.picture_file.attached?
  end

  test "a non-image file is still refused with a friendly message" do
    study = owner_study
    file = Rack::Test::UploadedFile.new(StringIO.new("hello"), "text/plain", original_filename: "notes.txt")
    assert_no_difference -> { SetlistItem.count } do
      post study_setlist_items_path(study), params: { setlist_item: { kind: "picture", title: "Notes", image: file } }
    end
    assert_select ".ps-setlist-form .err", text: /isn't a picture/
  end

  test "a stored picture renders with its thumbnail and slide data" do
    study = owner_study
    study.setlist_items.create!(kind: :picture, title: "Harvest Sunday",
                                media_url: "https://res.cloudinary.com/demo/x.jpg",
                                media_public_id: "demo/x")
    get study_path(study)
    assert_select ".ps-setlist-item[data-kind='slide'][data-image='https://res.cloudinary.com/demo/x.jpg']"
    assert_select ".ps-setlist-item img.thumb[src='https://res.cloudinary.com/demo/x.jpg']"
  end

  test "the library endpoint returns the hymnal plus the owner's past songs" do
    study = owner_study
    study.setlist_items.create!(kind: :song, title: "Our Anthem", body: "verse one")
    get library_study_setlist_items_path(study), headers: { "Accept" => "application/json" }
    assert_response :success
    titles = JSON.parse(response.body)["songs"].map { |s| s["title"] }
    assert_includes titles, "Our Anthem"
    assert_includes titles, "Amazing Grace"
  end

  test "a guest can build a queue on their session study" do
    post studies_path # creates the guest's session-scoped study
    study = Study.last
    post study_setlist_items_path(study), params: { setlist_item: { kind: "thought", body: "Welcome" } }
    assert_response :success
    assert_equal 1, study.setlist_items.count
  end

  test "someone else's study is not reachable" do
    study = users(:two).studies.create!(name: "Private", pane_count: 1)
    sign_in_as users(:one)
    post study_setlist_items_path(study), params: { setlist_item: { kind: "thought", body: "x" } }
    assert_response :not_found
  end

  test "an unknown kind is a 422 with the form re-rendered, not a 500" do
    study = owner_study
    assert_no_difference -> { SetlistItem.count } do
      post study_setlist_items_path(study), params: { setlist_item: { kind: "sermon", body: "x" } }
    end
    assert_response :unprocessable_entity
    assert_select ".ps-setlist-form .err", text: /kind/

    item = study.setlist_items.create!(kind: :song, title: "A")
    patch study_setlist_item_path(study, item), params: { setlist_item: { kind: "bogus" } }
    assert_response :unprocessable_entity
    assert item.reload.song?
  end

  test "guests can't upload pictures" do
    post studies_path
    study = Study.last
    file = Rack::Test::UploadedFile.new(StringIO.new("fake"), "image/png", original_filename: "slide.png")
    assert_no_difference -> { SetlistItem.count } do
      post study_setlist_items_path(study), params: { setlist_item: { kind: "picture", image: file } }
    end
    assert_select ".ps-setlist-form .err", text: /Sign in/
  end

  test "pictures are capped per study before any upload" do
    study = owner_study
    SetlistItem::PICTURE_LIMIT.times do |i|
      study.setlist_items.create!(kind: :picture, media_url: "https://res.cloudinary.com/demo/#{i}.jpg")
    end
    file = Rack::Test::UploadedFile.new(StringIO.new("fake"), "image/png", original_filename: "slide.png")
    assert_no_difference -> { SetlistItem.count } do
      post study_setlist_items_path(study), params: { setlist_item: { kind: "picture", image: file } }
    end
    assert_select ".ps-setlist-form .err", text: /already holds #{SetlistItem::PICTURE_LIMIT} pictures/
  end

  test "changing a picture into another kind drops its hosted media" do
    study = owner_study
    item = study.setlist_items.create!(kind: :picture, title: "Harvest",
                                       media_url: "https://res.cloudinary.com/demo/x.jpg", media_public_id: "demo/x")
    patch study_setlist_item_path(study, item), params: { setlist_item: { kind: "thought" } }
    assert_response :success
    item.reload
    assert item.thought?
    assert_nil item.media_url
    assert_nil item.media_public_id
  end

  # ---- the local-first queue (JSON, replayed through the offline outbox) ----

  def json_post(study, attrs)
    post study_setlist_items_path(study), params: { setlist_item: attrs }, as: :json
  end

  test "a device-made scripture is created once per client_id, however often it is replayed" do
    study = owner_study
    assert_difference -> { SetlistItem.count }, 1 do
      json_post(study, kind: "scripture", reference: "rom 8:28", client_id: "tmp-abc-1")
      assert_response :created
      json_post(study, kind: "scripture", reference: "rom 8:28", client_id: "tmp-abc-1")
      assert_response :success
    end
    body = response.parsed_body
    assert_equal "tmp-abc-1", body["client_id"]
    assert_equal "Romans 8:28", body["label"]
    assert body["server_time"].positive?
  end

  test "an explicit position inserts the item there and keeps positions dense" do
    study = owner_study
    study.setlist_items.create!(kind: :song, title: "A")
    study.setlist_items.create!(kind: :song, title: "B")
    json_post(study, kind: "thought", title: "Mid", client_id: "tmp-mid", position: 1)
    assert_response :created
    assert_equal %w[A Mid B], study.setlist_items.in_order.map(&:title)
    assert_equal [ 0, 1, 2 ], study.setlist_items.in_order.map(&:position)
    assert_equal 1, response.parsed_body["position"]
  end

  test "an unreadable reference is a JSON 422 with the reason" do
    study = owner_study
    assert_no_difference -> { SetlistItem.count } do
      json_post(study, kind: "scripture", reference: "blorbity 9", client_id: "tmp-bad")
    end
    assert_response :unprocessable_entity
    assert_match(/couldn't be read/, response.parsed_body["error"])
  end

  test "update, destroy and order accept the device's client id" do
    study = owner_study
    json_post(study, kind: "thought", title: "One", client_id: "tmp-one")
    json_post(study, kind: "thought", title: "Two", client_id: "tmp-two")
    json_post(study, kind: "thought", title: "Three", client_id: "tmp-three")

    patch study_setlist_item_path(study, "tmp-two"), params: { setlist_item: { title: "Second" } }, as: :json
    assert_response :success
    assert_equal "Second", response.parsed_body["title"]

    three = study.setlist_items.find_by!(client_id: "tmp-three")
    patch order_study_setlist_items_path(study), params: { order: [ three.id.to_s, "tmp-one", "tmp-two" ] }, as: :json
    assert_response :success
    assert_equal %w[Three One Second], response.parsed_body["items"].map { |i| i["title"] }
    assert_equal %w[Three One Second], study.setlist_items.in_order.map(&:title)

    delete study_setlist_item_path(study, "tmp-one"), as: :json
    assert_response :success
    assert_equal %w[Three Second], study.setlist_items.in_order.map(&:title)

    # A replayed delete of something already gone is a 404 (the outbox settles it).
    delete study_setlist_item_path(study, "tmp-one"), as: :json
    assert_response :not_found
  end

  test "an order naming unknown or missing items keeps the rest after it" do
    study = owner_study
    a = study.setlist_items.create!(kind: :song, title: "A")
    b = study.setlist_items.create!(kind: :song, title: "B")
    c = study.setlist_items.create!(kind: :song, title: "C")
    patch order_study_setlist_items_path(study), params: { order: [ c.id.to_s, "tmp-gone" ] }, as: :json
    assert_response :success
    assert_equal [ c, a, b ], study.setlist_items.in_order.to_a
  end

  test "the queue index returns items in order" do
    study = owner_study
    study.setlist_items.create!(kind: :scripture, reference: "rom 8:28")
    get study_setlist_items_path(study), as: :json
    assert_response :success
    assert_equal [ "Romans 8:28" ], response.parsed_body["items"].map { |i| i["label"] }
  end

  test "a guest's device-made items land on their session study" do
    post studies_path
    study = Study.last
    json_post(study, kind: "scripture", reference: "rom 8:28", client_id: "tmp-guest")
    assert_response :created
    assert_equal [ "tmp-guest" ], study.setlist_items.pluck(:client_id)
  end

  test "JSON writes to someone else's study are not found" do
    study = users(:two).studies.create!(name: "Private", pane_count: 1)
    item = study.setlist_items.create!(kind: :thought, title: "x", client_id: "tmp-x")
    sign_in_as users(:one)
    json_post(study, kind: "thought", title: "y", client_id: "tmp-y")
    assert_response :not_found
    patch order_study_setlist_items_path(study), params: { order: [ item.id.to_s ] }, as: :json
    assert_response :not_found
    delete study_setlist_item_path(study, "tmp-x"), as: :json
    assert_response :not_found
    assert SetlistItem.exists?(item.id)
  end

  test "pictures still need the form (and an account)" do
    study = owner_study
    json_post(study, kind: "picture", title: "x", client_id: "tmp-pic")
    assert_response :unprocessable_entity
  end

  test "the Picture Bank saves how a picture fills the screen (and only that)" do
    study = owner_study
    item = study.setlist_items.create!(kind: :picture, title: "First timer", media_url: "https://res.cloudinary.com/demo/x.jpg")
    patch study_setlist_item_path(study, item), params: { setlist_item: { kind: "picture", data: { fit: "fill", zoom: 130 } } }, as: :json
    assert_response :success
    assert_equal({ "fit" => "fill", "zoom" => 130 }, JSON.parse(response.body)["data"])
    item.reload
    assert_equal({ "fit" => "fill", "zoom" => 130 }, item.data)
    assert_equal "https://res.cloudinary.com/demo/x.jpg", item.media_url

    # Zoom alone keeps the fit; nonsense is cleaned.
    patch study_setlist_item_path(study, item), params: { setlist_item: { data: { zoom: 999 } } }, as: :json
    assert_equal({ "fit" => "fill", "zoom" => 200 }, item.reload.data)

    # It still can't be turned into another kind from the device.
    patch study_setlist_item_path(study, item), params: { setlist_item: { kind: "thought", body: "x" } }, as: :json
    assert_response :unprocessable_entity
    assert item.reload.picture?
  end

  test "a picture's setting is in the queue the page hands the device" do
    study = owner_study
    study.setlist_items.create!(kind: :picture, title: "Flyer", media_url: "https://res.cloudinary.com/demo/x.jpg", data: { fit: "stretch" })
    get study_path(study)
    items = JSON.parse(css_select("[data-items]").first["data-items"])
    assert_equal({ "fit" => "stretch", "zoom" => 100 }, items.find { |i| i["kind"] == "picture" }["data"])
  end

  # ---- My Media: every picture added to a service is kept in the library ----

  test "a picture uploaded to the queue lands in My Media and the item uses that file" do
    study = owner_study
    assert_difference [ "MediaAsset.count", "ActiveStorage::Blob.count" ], 1 do
      post study_setlist_items_path(study), params: { setlist_item: { kind: "picture", title: "Welcome", image: picture_upload } }
    end
    item = study.setlist_items.picture.sole
    asset = users(:one).media_assets.sole
    assert_equal asset, item.media_asset
    assert_equal "Welcome", asset.title
    assert_equal asset.file.blob, item.picture_file.blob
    assert_equal asset.media_url, item.media_url
  end

  test "the same picture in a second service reuses the library file — no second upload" do
    study = owner_study
    other = users(:one).studies.create!(name: "Midweek", pane_count: 1)
    post study_setlist_items_path(study), params: { setlist_item: { kind: "picture", image: picture_upload } }
    assert_no_difference [ "MediaAsset.count", "ActiveStorage::Blob.count" ] do
      post study_setlist_items_path(other), params: { setlist_item: { kind: "picture", image: picture_upload } }
    end
    a = study.setlist_items.picture.sole
    b = other.setlist_items.picture.sole
    assert_equal a.media_asset_id, b.media_asset_id
    assert_equal a.picture_file.blob, b.picture_file.blob
    assert_equal "welcome flyer", b.title
  end

  test "a picture from My Media is queued by its library id (JSON / outbox), once per client_id" do
    study = owner_study
    asset = library_picture(users(:one))
    asset.update!(display: { fit: "fill", zoom: 120 })
    assert_difference -> { study.setlist_items.count }, 1 do
      json_post(study, kind: "picture", media_asset_id: asset.id, client_id: "tmp-pic-1")
      assert_response :created
      json_post(study, kind: "picture", media_asset_id: asset.id, client_id: "tmp-pic-1")
    end
    body = response.parsed_body
    assert_equal asset.id, body["media_asset_id"]
    assert_equal asset.media_url, body["image"]
    assert_equal({ "fit" => "fill", "zoom" => 120 }, body["data"], "starts from the library's default display")
    item = study.setlist_items.picture.sole
    assert_equal asset.file.blob, item.picture_file.blob
    assert asset.reload.last_used_at.present?

    json_post(study, kind: "picture", media_asset_id: asset.id, client_id: "tmp-pic-2", data: { fit: "stretch" })
    assert_equal({ "fit" => "stretch", "zoom" => 100 }, response.parsed_body["data"], "or the device's own choice")
  end

  test "someone else's library picture can't be queued" do
    study = owner_study
    theirs = library_picture(users(:two))
    assert_no_difference -> { SetlistItem.count } do
      json_post(study, kind: "picture", media_asset_id: theirs.id, client_id: "tmp-pic")
    end
    assert_response :unprocessable_entity
  end

  test "removing a picture from a service leaves it in My Media" do
    study = owner_study
    asset = library_picture(users(:one))
    item = study.setlist_items.create!(SetlistItem.picture_attrs_from(asset))
    perform_enqueued_jobs do
      delete study_setlist_item_path(study, item), as: :json
    end
    assert_response :success
    assert asset.reload.file.attached?
    assert ActiveStorage::Blob.exists?(asset.file.blob.id)
  end
end
