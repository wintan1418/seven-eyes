require "test_helper"

class WhatsNewTest < ActionDispatch::IntegrationTest
  test "the what's-new tour is public and shows every new feature" do
    get whats_new_path
    assert_response :success
    assert_includes response.body, "What&rsquo;s new in BiblioRata"
    [ "The Preach Queue", "Songs &amp; thoughts, projected", "Ask anything, mid-sermon",
      "Your phone is the clicker", "The stage display", "Dress the projection",
      "One press back", "Pictures on the screen",
      "Blank the screen in a tap", "Songs you don&rsquo;t retype",
      "Go Live &mdash; now with a takeaway" ].each do |title|
      assert_includes response.body, title
    end
    assert_select ".ps-news[data-whats-new-version-value=?]", WhatsNewController::VERSION
  end
end
