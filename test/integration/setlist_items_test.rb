require "test_helper"

class SetlistItemsTest < ActionDispatch::IntegrationTest
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
    assert_select ".ps-setlist-item .meta", text: "2 stanzas"
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

  test "a picture upload without hosting configured shows the friendly error" do
    study = owner_study
    file = Rack::Test::UploadedFile.new(StringIO.new("fake"), "image/png", original_filename: "slide.png")
    assert_no_difference -> { SetlistItem.count } do
      post study_setlist_items_path(study), params: { setlist_item: { kind: "picture", title: "Harvest", image: file } }
    end
    assert_response :success
    assert_select ".ps-setlist-form .err", text: /hosting isn't configured/
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
end
