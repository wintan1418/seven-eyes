require "test_helper"

class GuideTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
  end

  test "dismiss stamps the user and the welcome stops rendering the panel" do
    post dismiss_guide_path
    assert_redirected_to root_path
    follow_redirect!
    assert users(:one).reload.guide_dismissed_at.present?
    refute_match(/What.s at your desk/, response.body)
  end

  test "restore clears the dismissal so the panel reappears" do
    users(:one).update!(guide_dismissed_at: Time.current)
    delete restore_guide_path
    assert_redirected_to root_path
    follow_redirect!
    assert_nil users(:one).reload.guide_dismissed_at
    assert_match(/What.s at your desk/, response.body)
  end

  test "guests cannot dismiss the guide" do
    delete session_path
    post dismiss_guide_path
    assert_response :unauthorized
  end

  test "guests land on the marketing page, with the field guide a link away" do
    delete session_path
    get root_path
    assert_select ".ps-landing"
    assert_select ".ld-foot-links a[href=?]", guide_path
  end

  test "the illustrated field guide renders for a signed-in user" do
    get guide_path
    assert_response :success
    assert_match(/Everything you can do here/, response.body)
    assert_match(/Ask the AI Rabbi/, response.body)
  end

  test "the field guide is in five parts, with a contents list that jumps to each" do
    get guide_path
    assert_response :success
    {
      "getting-started" => "Getting started", "daily-rhythm" => "Your daily rhythm",
      "reading" => "Reading and studying", "preaching" => "Preaching and the big screen",
      "shortcuts" => "Keyboard shortcuts"
    }.each do |anchor, title|
      assert_select ".ps-tut-toc a[href=?]", "##{anchor}", text: /#{title}/
      assert_select ".ps-tut-part##{anchor} h2", text: title
    end
  end

  test "the field guide covers what shipped recently, with real screenshots" do
    get guide_path
    [ "Five tabs along the bottom", "It works with no data", "Begin today", "Six short steps",
      "The Glossary of the Faith", "From fellow readers", "The Bible reader", "Search the whole Bible",
      "The operator console", "Looks and live buttons", "The song bank",
      "This Sunday, ready ahead of time" ].each do |title|
      assert_select ".ps-tut-copy h3", text: title
    end
    %w[home today faith reader search].each do |shot|
      assert_select ".ps-tut-shot img[src*=?][alt]", "guide/#{shot}"
    end
    assert_select ".ps-tut-keys-card", 2
    assert_select ".ps-tut-foot a[href=?]", whats_new_path
  end

  test "the field guide is saved for offline use" do
    sw = Rails.root.join("app/javascript/service_worker.js").read
    assert_match %r{/\^\\/guide\$/}, sw, "OWN_PAGES keeps it"
    assert_match %r{CORE_PAGES = \[[^\]]*"/guide"}, sw, "warm saves it"
  end

  test "the illustrated field guide is open to guests" do
    delete session_path
    get guide_path
    assert_response :success
    assert_match(/Everything you can do here/, response.body)
  end

  test "the topbar links to the field guide and offers the tour" do
    study = users(:one).studies.create!(name: "Test", pane_count: 1)
    get study_path(study)
    assert_match(guide_path, response.body)
    assert_match(/data-action="tour#start\b/, response.body)
  end
end
