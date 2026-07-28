require "application_system_test_case"

# Browser smoke of the Scriptorium welcome: the page renders its hero,
# and the quick-open bar carries a guest straight into a study.
class WelcomeTest < ApplicationSystemTestCase
  test "the welcome renders and quick-open lands in a fresh study" do
    visit root_path

    assert_selector "h1", text: "Parallel Scripture"
    assert_selector ".ps-illumined blockquote"
    assert_selector ".ps-canon-stats"

    fill_in "reference", with: "John 3:16"
    click_on "Read"

    assert_selector ".ps-topbar"
    assert_field with: "John 3:16"
  end
end
