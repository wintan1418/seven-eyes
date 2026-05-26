require "test_helper"

class SermonTest < ActionDispatch::IntegrationTest
  setup do
    @kjv = Translation.create!(code: "KJV", name: "King James Version")
    @john = Book.create!(osis_code: "John", name: "John", testament: :new, position: 43, chapter_count: 21)
    @rom = Book.create!(osis_code: "Rom", name: "Romans", testament: :new, position: 45, chapter_count: 16)
    Verse.create!(translation: @kjv, book: @john, chapter: 3, verse_number: 16,
                  text: "For God so loved the world, that he gave his only begotten Son.")
    Verse.create!(translation: @kjv, book: @rom, chapter: 5, verse_number: 1,
                  text: "Therefore being justified by faith, we have peace with God.")

    @user = users(:one)
    sign_in_as @user
    @study = @user.studies.create!(name: "Justification — Sept 14", pane_count: 2)
    @study.panes.order(:position).first.update!(reference: "John 3:16", translation: @kjv)
  end

  test "GET sermon HTML compiles non-empty panes into a manuscript" do
    get sermon_study_path(@study)
    assert_response :success
    assert_select "h1.ms-title", text: "Justification — Sept 14"
    assert_select ".ms-section .ms-ref", text: /John 3:16/
    assert_select ".ms-section", count: 1 # the empty pane is skipped
  end

  test "GET sermon.md returns a markdown attachment" do
    get sermon_study_path(@study, format: :md)
    assert_response :success
    assert_equal "text/markdown", @response.media_type
    assert_match(/^# Justification/, @response.body)
    assert_match(/John 3:16/, @response.body)
    assert_match(/attachment/, @response.headers["Content-Disposition"])
  end

  test "the workspace topbar links to the sermon page" do
    get study_path(@study)
    assert_response :success
    assert_select "a[href=?]", sermon_study_path(@study)
  end

  test "guests can compile a manuscript for their own session study" do
    delete session_path # sign out
    post studies_path, params: { name: "Guest study", pane_count: 1 }
    guest_study = Study.where(user_id: nil).order(:id).last
    guest_study.panes.first.update!(reference: "Rom 5:1", translation: @kjv)

    get sermon_study_path(guest_study)
    assert_response :success
    assert_select ".ms-ref", text: /Romans 5:1/
  end
end
