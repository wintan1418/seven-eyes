require "test_helper"

# Pastor mode: This Sunday leads Home for preachers, never for lay readers.
class PastorModeTest < ActionDispatch::IntegrationTest
  setup do
    Book.create!(osis_code: "Jer", name: "Jeremiah", testament: :old, position: 24, chapter_count: 52)
    @user = users(:one)
    @study = @user.studies.create!(name: "The Potter's House", pane_count: 1, last_opened_at: 1.hour.ago)
  end

  def queue!
    @study.setlist_items.create!(kind: :scripture, reference: "Jeremiah 18:1-6")
    @study.setlist_items.create!(kind: :song, title: "Be Thou My Vision", body: "Be thou my vision")
  end

  test "a preacher's Home leads with This Sunday: order, readiness, Open / Present / Get ready" do
    queue!
    sign_in_as @user
    get root_path
    assert_select ".hm-root.has-sunday .hm-lead > .hm-sunday:first-child" do
      assert_select ".hm-sunday-title", text: "The Potter's House"
      assert_select ".hm-sunday-item", 2
      assert_select ".hm-sunday-item.is-scripture .hm-sunday-name", text: "Jeremiah 18:1-6"
      assert_select ".hm-sunday-item.is-song .hm-sunday-kind", text: "Song"
      assert_select ".hm-sunday-checks .is-todo", text: /1 song has no order yet/
      assert_select "a[href=?]", study_path(@study, queue: 1), text: /Open service/
      assert_select "a[href=?]", study_path(@study, present: 1), text: /Present/
      assert_select "a[href=?]", study_path(@study, ready: 1), text: /Get ready/
      assert_select "[data-controller=sunday-card][data-sunday-card-url-value=?]", study_path(@study)
    end
  end

  test "lay readers never see it; switching it off hides it; switching it on shows it" do
    sign_in_as @user
    get root_path
    assert_select ".hm-sunday", 0

    queue!
    patch preferences_path, params: { pastor_mode: false }
    assert_redirected_to more_path
    get root_path
    assert_select ".hm-sunday", 0
    assert_select ".hm-root.has-sunday", 0

    patch preferences_path, params: { pastor_mode: true }
    get root_path
    assert_select ".hm-sunday"
  end

  test "pastor mode on but nothing queued: no empty card" do
    @user.update!(pastor_mode: true)
    sign_in_as @user
    get root_path
    assert_select ".hm-sunday", 0
  end

  test "the switch lives in More, as a switch" do
    queue!
    sign_in_as @user
    get more_path
    assert_select "form[action=?] button.ui-switch-row[role=switch][aria-checked=true]", preferences_path
    assert_select "input[name=pastor_mode][value=false]"
    get more_path
  end

  test "guests can't set it" do
    patch preferences_path, params: { pastor_mode: true }
    assert_response :no_content
  end
end
