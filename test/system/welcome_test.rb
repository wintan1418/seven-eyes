require "application_system_test_case"

# Browser smoke of the landing page: the hero renders,
# and the quick-open bar carries a guest straight into a study.
class WelcomeTest < ApplicationSystemTestCase
  test "the landing renders and quick-open lands in a fresh study" do
    visit root_path

    assert_selector "h1", text: "The Word, laid open."
    assert_selector ".ld-vod blockquote"
    assert_selector ".ps-canon-stats"

    fill_in "reference", with: "John 3:16"
    click_on "Read"

    assert_selector ".ui-appbar [data-reader-header-target='reference']", text: "John 3:16"
    assert_selector "input[name='pane[reference]'][value='John 3:16']", visible: :all
  end
end
