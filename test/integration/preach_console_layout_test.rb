require "test_helper"

# The operator console (studies/_console) is drawn on the operator's page only,
# around the preach pieces it lays out — never on the projector or stage, which
# render this same page. console.css and console_controller rely on these slots.
class PreachConsoleLayoutTest < ActionDispatch::IntegrationTest
  SLOTS = %w[service preview previewhead livehead screen livetools verses songs words looks].freeze

  setup do
    kjv = Translation.create!(code: "KJV", name: "King James Version")
    john = Book.create!(osis_code: "John", name: "John", testament: :new, position: 43, chapter_count: 21)
    Verse.create!(translation: kjv, book: john, chapter: 3, verse_number: 16, text: "For God so loved the world.")
    sign_in_as users(:one)
    @study = users(:one).studies.create!(name: "Sunday", pane_count: 1)
    @study.panes.first.update!(reference: "John 3", translation: kjv)
  end

  test "the operator page carries the console: regions, slots, tabs, the console controller" do
    get study_path(@study)
    assert_response :success
    assert_includes css_select(".ps-root").sole["data-controller"].split, "console"
    %w[service preview live library].each { |r| assert_select ".cx [data-cx-region='#{r}']", 1 }
    SLOTS.each { |slot| assert_select ".cx [data-cx-slot='#{slot}']", 1, "missing slot #{slot}" }
    %w[scripture songs presentations media words looks].each { |tab| assert_select ".cx-tab[data-tab='#{tab}'][data-console-tab-param='#{tab}']", 1 }
    assert_select ".cx-panel[data-tab='words'] [data-root-words-open='live']" # the root-word card's home
    assert_select ".ps-preach-bar [data-bar-group='show'] [data-root-words-open='live']"
    assert_select ".cx-add [data-action~='console#openAdd'][data-console-kind-param]", 4
    assert_select ".cx [data-tool='templates'][data-action~='setlist#openTool']"
    assert_select ".cx [data-tool='presentation'][data-action~='setlist#openTool']"
    assert_select ".cx [data-tool='seminar'][data-action~='setlist#openTool']"
    assert_select ".cx-library select[data-console-library-target='translation'] option", text: "KJV"
    # The toolbar: Go live, the state pill, Console ⇄ Focus, the tour.
    assert_select ".ps-preach-bar [data-cx-golive][data-action~='preview#goLive']"
    assert_select ".ps-preach-bar [data-cx-state] [data-cx-state-label]"
    assert_select ".ps-preach-bar [data-cx-view-toggle][data-action~='console#toggleView']"
    assert_select ".ps-preach-bar [data-action~='console#tour']"
    assert_select ".ps-preach-bar [data-bar-group='show'] [data-preach-group]", 3
    assert_select ".cx-tour[hidden] template[data-console-tour-target='steps'] [data-region]", 4
  end

  test "the projector and stage windows get none of it" do
    [ "output=1", "stage=1" ].each do |q|
      get "#{study_path(@study)}?#{q}"
      assert_response :success
      assert_select ".cx", 0
      assert_not_includes css_select(".ps-root").sole["data-controller"].split, "console"
    end
  end
end
