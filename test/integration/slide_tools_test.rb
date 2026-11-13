require "test_helper"

# The phase 2B slide tools on the server: the queue keeps scripture sets,
# presentations and seminar decks (their structured part cleaned to a known
# shape), song collections and service templates upsert by the device's id
# (so the outbox can replay them), and the composer reads verses by Bible code.
class SlideToolsIntegrationTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @study = @user.studies.create!(name: "Sunday", pane_count: 1)
    @kjv = Translation.create!(code: "KJV", name: "King James Version")
    @bsb = Translation.create!(code: "BSB", name: "Berean Standard Bible")
    matt = Book.create!(osis_code: "Matt", name: "Matthew", testament: :new, position: 40, chapter_count: 28)
    (18..20).each do |v|
      Verse.create!(translation: @bsb, book: matt, chapter: 28, verse_number: v, text: "BSB Matthew 28:#{v}")
      Verse.create!(translation: @kjv, book: matt, chapter: 28, verse_number: v, text: "KJV Matthew 28:#{v}")
    end
  end

  test "the composer reads a passage in the Bible it names" do
    get "/verse_passage", params: { q: "Matt 28:19-20", translation: "bsb" }, as: :json
    body = response.parsed_body
    assert body["ok"]
    assert_equal "BSB", body["translation"]
    assert_equal "Matthew 28:19-20", body["label"]
    assert_equal [ [ 28, 19, "BSB Matthew 28:19" ], [ 28, 20, "BSB Matthew 28:20" ] ], body["verses"].map { |v| [ v["c"], v["n"], v["text"] ] }

    get "/verse_passage", params: { q: "Matt 28:19", translation: "AMP" }, as: :json
    assert_equal({ "ok" => false, "error" => "unknown_translation" }, response.parsed_body)
    get "/verse_passage", params: { q: "Hezekiah 1:1" }, as: :json
    assert_equal false, response.parsed_body["ok"]
  end

  test "a scripture set made on the device is kept with its words, idempotently, and comes back in the queue" do
    sign_in_as @user
    data = { refs: [ { reference: "Matt 28:19", translation: "bsb", label: "Matthew 28:19", verses: [ { c: 28, n: 19, text: "BSB Matthew 28:19" } ], junk: "x" } ],
             ref_position: "bottom", verse_numbers: false, split: "nonsense" }
    params = { setlist_item: { kind: "scripture_set", body: "BSB Matthew 28:19\n— Matthew 28:19 (BSB)", data: data, client_id: "tmp-set-1" } }
    2.times { post study_setlist_items_path(@study), params: params, as: :json }
    assert_equal 1, @study.setlist_items.count
    item = @study.setlist_items.sole
    assert item.scripture_set?
    assert_equal({ "ref_position" => "bottom", "verse_numbers" => false, "split" => "auto", "ref_style" => "gold" }, item.data.except("refs"))
    assert_equal %w[ label reference translation verses ], item.data["refs"].first.keys.sort
    assert_equal "BSB", item.data["refs"].first["translation"]
    assert_equal "Matthew 28:19 BSB", item.label

    get study_setlist_items_path(@study), as: :json
    row = response.parsed_body["items"].sole
    assert_equal "scripture_set", row["kind"]
    assert_equal 1, row["stanzas"]
    assert_equal "BSB Matthew 28:19", row.dig("data", "refs", 0, "verses", 0, "text")

    patch study_setlist_item_path(@study, "tmp-set-1"), params: { setlist_item: { title: "The Great Commission", data: data.merge(ref_position: "inline") } }, as: :json
    assert_response :success
    assert_equal "inline", item.reload.data["ref_position"]
    assert_equal "The Great Commission", item.label
  end

  test "a scripture set needs its words; a presentation its pages; a seminar its slides" do
    sign_in_as @user
    post study_setlist_items_path(@study), params: { setlist_item: { kind: "scripture_set", body: "x", data: { refs: [] } } }, as: :json
    assert_response :unprocessable_entity
    post study_setlist_items_path(@study), params: { setlist_item: { kind: "presentation", title: "Deck", data: { deck: "../../etc", pages: 3 } } }, as: :json
    assert_response :unprocessable_entity
    post study_setlist_items_path(@study), params: { setlist_item: { kind: "seminar", title: "Talk", data: { slides: [] } } }, as: :json
    assert_response :unprocessable_entity

    post study_setlist_items_path(@study), params: { setlist_item: { kind: "presentation", title: "Building project", data: { deck: "deck-abc", pages: 12, source: "pdf", file: "building.pdf" } } }, as: :json
    assert_response :created
    deck = @study.setlist_items.presentation.sole
    assert_equal 12, deck.slide_count
    assert_nil deck.media_url # nothing hosted: the pages live on the device

    slides = [ { layout: "bullets", title: "Why", text: "Serve\nModel", notes: "story", image: "https://evil.example/x.png" }, { layout: "weird", title: "End" } ]
    post study_setlist_items_path(@study), params: { setlist_item: { kind: "seminar", title: "Talk", body: "Why", data: { slides: slides, reveal: true } } }, as: :json
    assert_response :created
    seminar = @study.setlist_items.seminar.sole
    assert_equal [ "bullets", "title" ], seminar.data["slides"].map { |s| s["layout"] }
    assert_equal "", seminar.data["slides"].first["image"] # only pictures kept on the device ("local:…")
    assert_equal 2, seminar.slide_count
  end

  test "song collections: accounts only, upserted by the device's id, listed with the song bank" do
    put song_collection_path("col-1"), params: { song_collection: { name: "Communion", titles: [ "x" ] } }, as: :json
    assert_response :unauthorized

    sign_in_as @user
    2.times { put song_collection_path("col-1"), params: { song_collection: { name: " Communion ", titles: [ "When I Survey", "when i survey", "Nothing but the Blood" ] } }, as: :json }
    assert_response :success
    collection = @user.song_collections.sole
    assert_equal "Communion", collection.name
    assert_equal [ "When I Survey", "Nothing but the Blood" ], collection.titles

    get library_study_setlist_items_path(@study), as: :json
    assert_equal [ { "id" => "col-1", "name" => "Communion", "titles" => [ "When I Survey", "Nothing but the Blood" ] } ], response.parsed_body["collections"]

    put song_collection_path("col-1"), params: { song_collection: { name: "" } }, as: :json
    assert_response :unprocessable_entity

    sign_in_as users(:two)
    delete song_collection_path("col-1"), as: :json
    assert_equal 1, SongCollection.count # not theirs
    sign_in_as @user
    delete song_collection_path("col-1"), as: :json
    assert_response :no_content
    assert_equal 0, SongCollection.count
  end

  test "service templates: save the order, list it, start a new service from it" do
    items = [
      { kind: "song", title: "Blessed Assurance", body: "Blessed assurance" },
      { kind: "scripture", reference: "Matt 28:19" },
      { kind: "picture", title: "Notice" }, # pictures belong to their queue
      { kind: "scripture_set", body: "BSB Matthew 28:19", data: { refs: [ { reference: "Matt 28:19", translation: "BSB", verses: [ { c: 28, n: 19, text: "BSB Matthew 28:19" } ] } ] } }
    ]
    put service_template_path("tpl-1"), params: { service_template: { name: "Sunday Service", items: items } }, as: :json
    assert_response :unauthorized

    sign_in_as @user
    put service_template_path("tpl-1"), params: { service_template: { name: "Sunday Service", items: items } }, as: :json
    assert_response :success
    put service_template_path("tpl-1"), params: { service_template: { name: "Sunday Service", items: items } }, as: :json
    template = @user.service_templates.sole
    assert_equal %w[song scripture scripture_set], template.items.map { |i| i["kind"] }

    get service_templates_path, as: :json
    assert_equal [ "Sunday Service" ], response.parsed_body["templates"].map { |t| t["name"] }

    assert_difference -> { @user.studies.count }, 1 do
      post start_service_template_path("tpl-1"), as: :json
    end
    assert_response :created
    study = @user.studies.order(:id).last
    assert_equal study_path(study), response.parsed_body["url"]
    assert_match(/\ASunday Service — /, study.name)
    assert_equal %w[song scripture scripture_set], study.setlist_items.in_order.map(&:kind)
    assert_equal "Matt 28:19", study.panes.first.reference

    sign_in_as users(:two)
    post start_service_template_path("tpl-1"), as: :json
    assert_response :not_found
  end
end
