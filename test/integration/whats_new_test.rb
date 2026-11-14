require "test_helper"

class WhatsNewTest < ActionDispatch::IntegrationTest
  test "the what's-new tour is public and shows every new feature" do
    get whats_new_path
    assert_response :success
    assert_includes response.body, "What&rsquo;s new in BiblioRata"
    [ "A calmer, modern reader", "The Preach Queue", "Songs &amp; thoughts, projected", "Ask anything, mid-sermon",
      "Your phone is the clicker", "The stage display", "Dress the projection",
      "One press back", "Pictures on the screen",
      "Blank the screen in a tap", "Songs you don&rsquo;t retype",
      "It survives a hiccup", "The passage, named on screen",
      "Make the key word glow", "One key back to your text",
      "Queue a stack in one go",
      "Go Live &mdash; now with a takeaway" ].each do |title|
      assert_includes response.body, title
    end
    assert_select ".ps-news[data-whats-new-version-value=?]", WhatsNewController::VERSION
  end

  test "November 2026 comes first, newest at the top, above the earlier cards" do
    get whats_new_path
    titles = [ "Begin today &mdash; five quiet minutes", "The Glossary of the Faith",
               "A Bible reader like the book", "Five tabs in the app",
               "Works offline from the first launch", "Pastor mode &mdash; This Sunday",
               "From fellow readers", "Sliders that break like glass" ]
    titles.each { |t| assert_includes response.body, t }
    assert_select ".news-release", text: "November 2026"
    latest = response.body.index("news-grid--latest")
    assert latest < response.body.index("A calmer, modern reader"), "the new cards sit above the older ones"
    assert_select ".news-grid--latest .news-card", 8
  end
end
