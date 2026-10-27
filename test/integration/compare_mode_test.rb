require "test_helper"

# The reader opens on one passage; Compare (pane_count > 1) is opt-in and
# fills new panes with the same passage in other translations.
class CompareModeTest < ActionDispatch::IntegrationTest
  setup do
    @kjv = Translation.create!(code: "KJV", name: "King James Version")
    @bsb = Translation.create!(code: "BSB", name: "Berean Standard Bible")
    @web = Translation.create!(code: "WEB", name: "World English Bible")
    john = Book.create!(osis_code: "John", name: "John", testament: :new, position: 43, chapter_count: 21)
    [ @kjv, @bsb, @web ].each do |t|
      Verse.create!(translation: t, book: john, chapter: 3, verse_number: 16, text: "#{t.code} 3:16")
    end
    sign_in_as users(:one)
  end

  test "a new study opens with one pane" do
    post studies_path, params: { reference: "John 3" }
    study = Study.last
    assert_equal 1, study.pane_count
    assert_equal 1, Study.new.pane_count, "the column default is one pane"
    follow_redirect!
    assert_select ".ps-workspace .ps-pane", 1
    assert_select ".ui-comparebar", 0
    assert_select ".ps-root.is-compare", 0
  end

  test "turning Compare on fills the new pane with the same passage in another translation" do
    study = users(:one).studies.create!(name: "S")
    study.panes.first.update!(reference: "John 3:16", translation: @kjv)
    patch study_path(study), params: { study: { pane_count: 2 } }
    second = study.reload.panes.second
    assert_equal "John 3:16", second.reference
    assert_equal "BSB", second.translation.code

    patch study_path(study), params: { study: { pane_count: 3 } }
    assert_equal "WEB", study.reload.panes.third.translation.code

    follow_redirect!
    assert_select ".ps-root.is-compare"
    assert_select ".ui-comparebar"
    assert_select ".ps-pane .rd-pane-head", 3
  end

  test "closing Compare keeps the hidden panes and their notes; reopening brings them back as they were" do
    study = users(:one).studies.create!(name: "S", pane_count: 2)
    study.panes.first.update!(reference: "John 3:16", translation: @kjv)
    study.panes.second.update!(reference: "Romans 8", translation: @web, notes: "keep me")
    patch study_path(study), params: { study: { pane_count: 1 } }
    assert_equal 2, study.reload.all_panes.count
    patch study_path(study), params: { study: { pane_count: 2 } }
    second = study.reload.panes.second
    assert_equal [ "Romans 8", "WEB", "keep me" ], [ second.reference, second.translation.code, second.notes ]
  end

  test "an empty primary pane leaves compare panes empty" do
    study = users(:one).studies.create!(name: "S")
    patch study_path(study), params: { study: { pane_count: 2 } }
    assert_nil study.reload.panes.second.reference
  end
end
