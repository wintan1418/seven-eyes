require "test_helper"

# "Paste your own" verses (NKJV, NIV, AMP… from the pastor's own Bible app):
# kept only inside that service's queue item — a scripture_set whose ref is
# marked `own` — never in a Translation, and only the service's owner can add,
# read or change it. Templates leave them out.
class PasteVersesTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @study = @user.studies.create!(name: "Sunday", pane_count: 1)
  end

  def own_data(verses: nil, version: "nkjv")
    verses ||= [ { c: 3, n: 16, text: "For God so loved the world…" }, { c: 3, n: 17, text: "For God did not send His Son…" } ]
    { refs: [ { reference: "John 3:16-17", label: "John 3:16-17", translation: version, own: true, verses: verses } ], per_slide: 1 }
  end

  def create_params(data = own_data, client_id: "tmp-own-1")
    { setlist_item: { kind: "scripture_set", body: "John 3:16-17 (NKJV)\n16 For God so loved the world…", data: data, client_id: client_id } }
  end

  test "a pasted passage is kept in the owner's queue with its version label and nothing else" do
    sign_in_as @user
    assert_no_difference -> { Translation.count } do
      assert_no_difference -> { Verse.count } do
        post study_setlist_items_path(@study), params: create_params, as: :json
      end
    end
    assert_response :created
    item = @study.setlist_items.sole
    ref = item.data["refs"].sole
    assert_equal true, ref["own"]
    assert_equal "NKJV", ref["translation"]
    assert_equal [ 16, 17 ], ref["verses"].map { |v| v["n"] }
    assert_equal 1, item.data["per_slide"]
    assert_equal "John 3:16-17 NKJV", item.label

    get study_setlist_items_path(@study), as: :json
    assert_equal true, response.parsed_body["items"].sole.dig("data", "refs", 0, "own")
  end

  test "someone else's service can't be added to, read or changed" do
    sign_in_as @user
    post study_setlist_items_path(@study), params: create_params, as: :json
    assert_response :created

    sign_in_as users(:two)
    post study_setlist_items_path(@study), params: create_params(client_id: "tmp-own-2"), as: :json
    assert_response :not_found
    get study_setlist_items_path(@study), as: :json
    assert_response :not_found
    patch study_setlist_item_path(@study, "tmp-own-1"), params: { setlist_item: { data: own_data(version: "NIV") } }, as: :json
    assert_response :not_found
    assert_equal 1, @study.setlist_items.count
    assert_equal "NKJV", @study.setlist_items.sole.data.dig("refs", 0, "translation")
  end

  test "a guest can't reach a signed-in pastor's service either" do
    post study_setlist_items_path(@study), params: create_params, as: :json
    assert_response :not_found
    assert_equal 0, @study.setlist_items.count
  end

  test "up to 200 verses are kept; a paste over 40 KB is refused kindly" do
    sign_in_as @user
    many = (1..250).map { |n| { c: 119, n: n % 177, text: "Verse #{n}." } }
    post study_setlist_items_path(@study), params: create_params(own_data(verses: many)), as: :json
    assert_response :created
    assert_equal SlideData::MAX_OWN_VERSES, @study.setlist_items.sole.data.dig("refs", 0, "verses").size

    huge = (1..30).map { |n| { c: 1, n: n, text: "x" * 1_900 } } # ~57 KB
    post study_setlist_items_path(@study), params: create_params(own_data(verses: huge), client_id: "tmp-own-big"), as: :json
    assert_response :unprocessable_entity
    assert_match(/too long/, response.parsed_body["error"].to_s + response.body)
  end

  test "a public-domain scripture set still stops at 80 verses a reference" do
    data = { refs: [ { reference: "Ps 119", translation: "KJV", verses: (1..120).map { |n| { c: 119, n: n, text: "v#{n}" } } } ] }
    assert_equal SlideData::MAX_VERSES, SlideData.clean("scripture_set", data)["refs"].sole["verses"].size
    assert_not SlideData.own?(SlideData.clean("scripture_set", data))
  end

  test "templates leave pasted passages out" do
    sign_in_as @user
    items = [
      { kind: "song", title: "Blessed Assurance", body: "Blessed assurance" },
      { kind: "scripture_set", body: "John 3:16", data: own_data }
    ]
    put service_template_path("tpl-own"), params: { service_template: { name: "Sunday Service", items: items } }, as: :json
    assert_response :success
    assert_equal %w[song], @user.service_templates.sole.items.map { |i| i["kind"] }
  end
end
