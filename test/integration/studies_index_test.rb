require "test_helper"

class StudiesIndexTest < ActionDispatch::IntegrationTest
  test "guests can view the open welcome (no forced login)" do
    get root_path
    assert_response :success
    assert_select ".ps-welcome"
  end

  test "renders the Scriptorium welcome when authenticated" do
    sign_in_as users(:one)
    get root_path
    assert_response :success
    assert_select ".ps-welcome"
    assert_select "h1", text: "Welcome back."
  end

  test "the welcome shows the quick-open bar, illumined verse and canon stats" do
    get root_path
    assert_select "form.ps-quick-open input[name=?]", "reference"
    assert_select ".ps-illumined blockquote"
    assert_select ".ps-canon-stats"
  end

  test "recent studies appear as a shelf of cards for the owner" do
    sign_in_as users(:one)
    users(:one).studies.create!(name: "Romans deep dive", pane_count: 2)
    get root_path
    assert_select ".ps-recent-shelf .ps-study-card .nm", text: "Romans deep dive"
  end

  test "quick-open creates a guest study named after the passage with pane I preloaded" do
    assert_difference -> { Study.count }, 1 do
      post studies_path, params: { reference: "John 3:16", pane_count: 2 }
    end
    study = Study.order(:id).last
    assert_redirected_to study_path(study)
    assert_nil study.user_id
    assert_equal "John 3:16", study.name
    assert_equal 2, study.pane_count
    assert_equal "John 3:16", study.panes.first.reference
  end

  test "quick-open with an unparseable reference still opens a study" do
    post studies_path, params: { reference: "zzz 99", pane_count: 2 }
    study = Study.order(:id).last
    assert_equal "Untitled Study", study.name
    assert_equal "zzz 99", study.panes.first.reference
  end
end
