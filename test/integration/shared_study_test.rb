require "test_helper"

class SharedStudyTest < ActionDispatch::IntegrationTest
  setup do
    @kjv = Translation.create!(code: "KJV", name: "King James Version")
    @john = Book.create!(osis_code: "John", name: "John", testament: :new,
                         position: 43, chapter_count: 21)
    Verse.create!(translation: @kjv, book: @john, chapter: 3, verse_number: 16,
                  text: "For God so loved the world, that he gave his only begotten Son.")

    @owner = users(:one)
    @study = @owner.studies.create!(name: "Atonement", pane_count: 1)
    @study.panes.first.update!(reference: "John 3:16", translation: @kjv)
  end

  test "owner can mint and re-use a share token" do
    sign_in_as @owner
    post share_study_path(@study), as: :json
    assert_response :success
    body = JSON.parse(@response.body)
    token = @study.reload.share_token
    assert token.present?
    assert_includes body["url"], "/s/#{token}"

    # Idempotent — calling again returns the same token.
    post share_study_path(@study), as: :json
    assert_equal token, @study.reload.share_token
  end

  test "non-owner cannot mint a share link (study is scoped to owner)" do
    sign_in_as users(:two)
    post share_study_path(@study), as: :json
    assert_response :not_found
    assert_nil @study.reload.share_token
  end

  test "guests get bounced to sign in when trying to share" do
    post share_study_path(@study), as: :json
    assert_response :redirect
    assert_match(/session/, @response.location)
    assert_nil @study.reload.share_token
  end

  test "anyone with the token can view the shared study without auth" do
    @study.ensure_share_token!
    get shared_study_path(@study.share_token)
    assert_response :success
    assert_select ".ps-study-name", text: /Atonement/
    assert_select ".ps-verses", text: /so loved the world/
    # No editable inputs leak through.
    assert_select "input.ps-search", count: 0
    assert_select "textarea.ps-notes-area", count: 0
  end

  test "viewers get no links into the owner's xref or lexicon drawers" do
    Verse.find_by(verse_number: 16).update!(tokens: [ { "w" => "For " }, { "w" => "God", "s" => "G2316" },
                                                      { "w" => " so loved the world, that he gave his only begotten Son." } ])
    @study.panes.first.update!(notes: "See [[John 3:16]] again")
    @study.ensure_share_token!
    get shared_study_path(@study.share_token)
    assert_response :success
    assert_select ".ps-vnum", text: "16"
    assert_select "a.ps-vnum", count: 0
    assert_select "[data-turbo-frame='xref_drawer']", count: 0
    assert_select "[data-href*='lexicon']", count: 0
    assert_no_match %r{/studies/#{@study.id}/}, response.body
    assert_select ".ps-notes-body", text: /See \[\[John 3:16\]\] again/
  end

  test "hidden panes stay private on the shared page" do
    @study.update!(pane_count: 2)
    @study.sync_panes!
    @study.panes.last.update!(notes: "Private thought")
    @study.update!(pane_count: 1)
    @study.ensure_share_token!
    get shared_study_path(@study.share_token)
    assert_no_match(/Private thought/, response.body)
  end

  test "invalid token renders 404" do
    get shared_study_path("notarealtoken")
    assert_response :not_found
    assert_select "h1", text: /Not found/
  end

  test "topbar Share button is present for owner only" do
    sign_in_as @owner
    get study_path(@study)
    assert_select "[data-share-url-value=?]", share_study_path(@study)

    sign_in_as users(:two)
    other_study = users(:two).studies.create!(name: "Other", pane_count: 1)
    get study_path(other_study)
    # The button is rendered for the owner of *this* study — confirm path matches.
    assert_select "[data-share-url-value=?]", share_study_path(other_study)
    # And not for the original owner's study.
    assert_select "[data-share-url-value=?]", share_study_path(@study), count: 0
  end
end
