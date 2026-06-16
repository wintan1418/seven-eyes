require "test_helper"

class LiveSessionsTest < ActionDispatch::IntegrationTest
  include ActionCable::TestHelper

  setup do
    @kjv = Translation.create!(code: "KJV", name: "King James Version")
    @john = Book.create!(osis_code: "John", name: "John", testament: :new, position: 43, chapter_count: 21)
    Verse.create!(translation: @kjv, book: @john, chapter: 3, verse_number: 16,
                  text: "For God so loved the world, that he gave his only begotten Son")
    Verse.create!(translation: @kjv, book: @john, chapter: 3, verse_number: 17,
                  text: "For God sent not his Son into the world to condemn the world")
  end

  def owner_study
    sign_in_as users(:one)
    users(:one).studies.create!(name: "Sunday", pane_count: 1)
  end

  test "the owner can go live and gets a join code and QR" do
    study = owner_study
    post study_live_path(study), params: { reference: "John 3", translation_id: @kjv.id,
                                           verse_start: 16, verse_end: 16 }, as: :json
    assert_response :success
    data = JSON.parse(response.body)
    assert_match(/\A[A-Z2-9]{4}\z/, data["code"])
    assert_includes data["url"], "/live/#{data["code"]}"
    assert_includes data["qr_svg"], "<svg"

    live = study.live_session
    assert_equal "John", live.osis
    assert_equal 3, live.chapter
    assert_equal 16, live.verse_start
    assert_equal "KJV", live.translation_code
  end

  test "going live twice reuses the active session" do
    study = owner_study
    post study_live_path(study), as: :json
    first_code = JSON.parse(response.body)["code"]
    assert_no_difference -> { LiveSession.count } do
      post study_live_path(study), as: :json
    end
    assert_equal first_code, JSON.parse(response.body)["code"]
  end

  test "a guest can go live with their session study" do
    post studies_path # creates the guest's session-scoped study
    study = Study.last
    assert_nil study.user_id
    post study_live_path(study), as: :json
    assert_response :success
    assert study.live_session.present?
  end

  test "state pushes update the session and broadcast to followers" do
    study = owner_study
    post study_live_path(study), as: :json
    live = study.live_session

    assert_broadcasts(LiveSessionChannel.broadcasting_for(live), 1) do
      patch study_live_path(study), params: { reference: "John 3", translation_id: @kjv.id,
                                              verse_start: 17, verse_end: 17 }, as: :json
    end
    assert_response :success
    live.reload
    assert_equal 17, live.verse_start
    assert_equal "John 3", live.reference_label
  end

  test "an emphasis push is stored and carried in the broadcast state" do
    study = owner_study
    post study_live_path(study), params: { reference: "John 3", translation_id: @kjv.id,
                                           verse_start: 16, verse_end: 16 }, as: :json
    live = study.live_session

    patch study_live_path(study), params: { reference: "John 3", translation_id: @kjv.id,
                                            verse_start: 16, verse_end: 16,
                                            emphasis: { "16" => [ 3, 4 ] } }, as: :json
    assert_response :success
    assert_equal({ "16" => [ 3, 4 ] }, live.reload.emphasis)
    assert_equal({ "16" => [ 3, 4 ] }, live.live_state[:emphasis])
  end

  test "a garbled reference push is rejected without blanking the state" do
    study = owner_study
    post study_live_path(study), params: { reference: "John 3", translation_id: @kjv.id }, as: :json
    patch study_live_path(study), params: { reference: "blorbity 99" }, as: :json
    assert_response :unprocessable_entity
    assert_equal "John", study.live_session.reload.osis
  end

  test "ending the session broadcasts and marks it ended" do
    study = owner_study
    post study_live_path(study), as: :json
    live = study.live_session
    assert_broadcasts(LiveSessionChannel.broadcasting_for(live), 1) do
      delete study_live_path(study)
    end
    assert live.reload.ended?
  end

  test "anyone can open the follower page and sees the emphasised verse" do
    study = users(:one).studies.create!(name: "Sunday", pane_count: 1)
    live = study.live_sessions.create!(osis: "John", chapter: 3, translation_code: "KJV",
                                       verse_start: 16, verse_end: 16)
    get live_session_path(live.code)
    assert_response :success
    assert_includes response.body, "only begotten Son"
    assert_select ".ps-live-verse.is-now[data-num='16']"
    assert_select ".ps-live-ended[hidden]"
  end

  test "the passage endpoint serves the current chapter HTML" do
    study = users(:one).studies.create!(name: "Sunday", pane_count: 1)
    live = study.live_sessions.create!(osis: "John", chapter: 3, translation_code: "KJV")
    get live_session_passage_path(live.code)
    assert_response :success
    assert_includes response.body, "condemn the world"
  end

  test "an ended session renders the farewell with a keep-reading link" do
    study = users(:one).studies.create!(name: "Sunday", pane_count: 1)
    live = study.live_sessions.create!(osis: "John", chapter: 3, translation_code: "KJV")
    live.end!
    get live_session_path(live.code)
    assert_response :success
    assert_includes response.body, "The service has ended"
    assert_select ".ps-live-ended[hidden]", count: 0
    assert_select "a.cta[href=?]", open_passage_path("john-3")
  end

  test "an unknown code renders not-found" do
    get live_session_path("ZZZZ")
    assert_response :not_found
    assert_includes response.body, "No such live session"
  end

  test "a slide push swaps the pews to the song and back to scripture" do
    study = owner_study
    post study_live_path(study), params: { reference: "John 3", translation_id: @kjv.id }, as: :json
    live = study.live_session

    patch study_live_path(study), params: { kind: "slide", slide_title: "Amazing Grace",
                                            slide_body: "v one\n\nv two", slide_index: 1 }, as: :json
    assert_response :success
    live.reload
    assert live.slide?
    assert_equal [ "v one", "v two" ], live.slide_stanzas

    get live_session_passage_path(live.code)
    assert_select ".ps-live-slide .ps-live-stanza.is-now[data-idx='1']", text: "v two"

    patch study_live_path(study), params: { reference: "John 3", verse_start: 16, verse_end: 16 }, as: :json
    assert_equal "scripture", live.reload.kind
  end

  test "a picture slide reaches the pews" do
    study = owner_study
    post study_live_path(study), as: :json
    patch study_live_path(study), params: { kind: "slide", slide_title: "Harvest Sunday",
                                            slide_image_url: "https://res.cloudinary.com/demo/x.jpg" }, as: :json
    assert_response :success
    live = study.live_session.reload
    assert_equal "https://res.cloudinary.com/demo/x.jpg", live.slide_image_url

    get live_session_passage_path(live.code)
    assert_select ".ps-live-slide img.ps-live-picture[src='https://res.cloudinary.com/demo/x.jpg']"
  end

  test "an empty slide push is rejected" do
    study = owner_study
    post study_live_path(study), as: :json
    patch study_live_path(study), params: { kind: "slide", slide_title: "", slide_body: "" }, as: :json
    assert_response :unprocessable_entity
  end

  test "each chapter preached is logged once for the recap" do
    study = owner_study
    post study_live_path(study), params: { reference: "John 3", translation_id: @kjv.id }, as: :json
    patch study_live_path(study), params: { reference: "John 3", verse_start: 17 }, as: :json
    patch study_live_path(study), params: { reference: "John 4" }, as: :json
    live = study.live_session.reload
    assert_equal [ "John 3", "John 4" ], live.passages.map { |p| p["label"] }

    get live_session_recap_path(live.code)
    assert_response :success
    assert_select ".ps-live-recap li a[href=?]", open_passage_path("john-4"), text: "John 4"
  end

  test "an ended session's farewell lists tonight's scriptures" do
    study = users(:one).studies.create!(name: "Sunday", pane_count: 1)
    live = study.live_sessions.create!(osis: "John", chapter: 3, translation_code: "KJV")
    live.log_passage!
    live.end!
    get live_session_path(live.code)
    assert_response :success
    assert_select ".ps-live-ended .ps-live-recap li", text: "John 3"
  end
end
