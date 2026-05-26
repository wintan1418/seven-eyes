require "test_helper"

class DiffTest < ActionDispatch::IntegrationTest
  setup do
    @kjv = Translation.create!(code: "KJV", name: "King James Version")
    @bsb = Translation.create!(code: "BSB", name: "Berean Standard Bible")
    @john = Book.create!(osis_code: "John", name: "John", testament: :new,
                         position: 43, chapter_count: 21)
    Verse.create!(translation: @kjv, book: @john, chapter: 3, verse_number: 16,
                  text: "For God so loved the world.")
    Verse.create!(translation: @bsb, book: @john, chapter: 3, verse_number: 16,
                  text: "For God so loved the world.")
    @user = users(:one)
    sign_in_as @user
    @study = @user.studies.create!(name: "Compare", pane_count: 2)
    panes = @study.panes.order(:position)
    panes[0].update!(reference: "John 3:16", translation: @kjv)
    panes[1].update!(reference: "John 3:16", translation: @bsb)
  end

  test "verse spans carry osis/chapter/verse_num data attributes the diff JS keys on" do
    get study_path(@study)
    assert_response :success
    assert_select ".ps-verse[data-osis=John][data-chapter='3'][data-verse-num='16']", count: 2
  end

  test "topbar exposes a Diff toggle wired to the diff controller" do
    get study_path(@study)
    assert_select "[data-action=?]", "diff#toggle"
    assert_select "[data-diff-target=?]", "button"
  end
end
