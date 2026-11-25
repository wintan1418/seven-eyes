require "test_helper"

# Services that happened (the queue went live) and planning the next one:
# the served ping, Start fresh / Undo / Keep in the preach console, Home's
# "Plan this Sunday" (Start fresh, Reuse, template) and Past services.
class ServicesTest < ActionDispatch::IntegrationTest
  setup do
    Book.create!(osis_code: "Ps", name: "Psalms", testament: :old, position: 19, chapter_count: 150)
    @user = users(:one)
    @study = @user.studies.create!(name: "Psalms 4", pane_count: 1, last_opened_at: Time.utc(2026, 11, 21, 9))
    @study.setlist_items.create!(kind: :scripture, reference: "Psalm 4:1", client_id: "tmp-one")
    @study.setlist_items.create!(kind: :song, title: "Abide with Me", body: "Abide with me", arrangement: "V1")
    sign_in_as @user
  end

  def sunday = Time.utc(2026, 11, 22, 9) # 10:00 in Lagos
  def monday = Time.utc(2026, 11, 23, 9)

  def serve!
    travel_to(sunday) { post study_service_served_path(@study), params: { at: Time.current.iso8601 }, as: :json }
  end

  test "the queue has a New service button for its owner, any time" do
    get study_path(@study)
    assert_select "button[data-action='setlist#newService']", minimum: 1

    sign_out if respond_to?(:sign_out)
    other = users(:two)
    sign_in_as other
    get study_path(@study)
    assert_select "button[data-action='setlist#newService']", 0
  end

  test "starting fresh works on a queue that was never marked as served" do
    assert_nil @study.last_served_at
    post study_service_start_fresh_path(@study), params: { key: "manual-new-1" }, as: :json
    assert_response :success
    assert_equal 0, @study.reload.setlist_items.count
    archive = Study.find_by(archive_key: "manual-new-1")
    assert_equal 2, archive.setlist_items.count
  end

  test "the served ping records the day once" do
    travel_to sunday do
      post study_service_served_path(@study), params: { at: Time.current.iso8601 }, as: :json
      assert_response :success
      assert_equal({ "served_on" => "2026-11-22", "recorded" => true }, response.parsed_body)
      post study_service_served_path(@study), params: { at: 1.hour.from_now.iso8601 }, as: :json
      assert_equal false, response.parsed_body["recorded"]
    end
  end

  test "a ping replayed from the outbox the next day keeps the day it happened" do
    travel_to monday do
      post study_service_served_path(@study), params: { at: "2026-11-22T10:15:00+01:00" }, as: :json
      assert_equal "2026-11-22", response.parsed_body["served_on"]
    end
  end

  test "guests and other accounts can't mark a service" do
    sign_out
    post study_service_served_path(@study), as: :json
    assert_response :unauthorized

    sign_in_as users(:two)
    post study_service_served_path(@study), as: :json
    assert_response :not_found
    assert_nil @study.reload.last_served_at
  end

  test "Home after the service: last Sunday in one line and Plan this Sunday" do
    serve!
    @user.service_templates.create!(client_id: "tpl-sun", name: "Sunday Service", items: [ { kind: "thought", body: "Welcome" } ])
    travel_to monday do
      get root_path
      assert_select ".hm-sunday.is-plan" do
        assert_select ".hm-sunday-eyebrow", text: /This Sunday · 29 November/
        assert_select ".hm-sunday-title", text: "Plan this Sunday"
        assert_select ".hm-sunday-last a[href=?]", study_path(@study) do
          assert_select ".when", text: "Last Sunday, 22 Nov"
          assert_select ".name", text: "Psalms 4"
          assert_select ".count", text: "2 items"
        end
        assert_select "form[action=?] button", services_path, text: /Start fresh/
        assert_select "form[action=?] input[name=from][value=?]", services_path, @study.id.to_s
        assert_select "form[action=?] button", start_service_template_path("tpl-sun"), text: /Sunday Service/
        assert_select "a[href=?]", services_path, text: "Past services"
      end
      assert_select ".hm-sunday-title", text: "Psalms 4", count: 0
    end
  end

  test "on the day itself Home still shows today's service" do
    serve!
    travel_to sunday + 3.hours do
      get root_path
      assert_select ".hm-sunday:not(.is-plan) .hm-sunday-title", text: "Psalms 4"
      assert_select ".hm-sunday-eyebrow", text: /Today/
    end
  end

  test "Start fresh from Home: an empty service for the coming Sunday, which is then This Sunday" do
    serve!
    travel_to monday do
      assert_difference -> { @user.studies.count } do
        post services_path
      end
      fresh = @user.studies.order(:id).last
      assert_redirected_to study_path(fresh, queue: 1)
      assert_equal "Service · 29 Nov 2026", fresh.name
      assert_equal Date.new(2026, 11, 29), fresh.planned_for
      assert_equal 0, fresh.setlist_items.count

      get root_path
      assert_select ".hm-sunday:not(.is-plan) .hm-sunday-title", text: "Service · 29 Nov 2026"
    end
  end

  test "Reuse last Sunday's order: a new service with a copy of the queue" do
    serve!
    travel_to monday do
      post services_path, params: { from: @study.id }
      copy = @user.studies.order(:id).last
      assert_redirected_to study_path(copy, queue: 1)
      assert_equal [ "Psalm 4:1", "Abide with Me" ], copy.setlist_items.in_order.map { |i| i.reference || i.title }
      assert_equal 2, @study.setlist_items.count
      get root_path
      assert_select ".hm-sunday:not(.is-plan) .hm-sunday-title", text: "Service · 29 Nov 2026"
    end
  end

  test "Use a template: the template's order as the coming Sunday's service" do
    serve!
    @user.service_templates.create!(client_id: "tpl-sun", name: "Sunday Service", items: [ { kind: "thought", body: "Welcome" } ])
    travel_to monday do
      post start_service_template_path("tpl-sun")
      started = @user.studies.order(:id).last
      assert_redirected_to study_path(started, queue: 1)
      assert_equal "Sunday Service — 29 Nov 2026", started.name
      assert_equal Date.new(2026, 11, 29), started.planned_for
      get root_path
      assert_select ".hm-sunday:not(.is-plan) .hm-sunday-title", text: "Sunday Service — 29 Nov 2026"
    end
  end

  test "you can't reuse another account's service" do
    other = users(:two).studies.create!(name: "Theirs", pane_count: 1)
    post services_path, params: { from: other.id }
    assert_response :not_found
  end

  test "the console banner gets the served day; Keep using it, Start fresh and Undo" do
    serve!
    travel_to monday do
      get study_path(@study)
      assert_select ".ps-service-reset[hidden][data-controller=service-reset]" \
                    "[data-service-reset-served-on-value='2026-11-22'][data-service-reset-dismissed-for-value='']" do
        assert_select "button[data-action='service-reset#startFresh']", text: "Start fresh"
        assert_select "button[data-action='service-reset#keep']", text: "Keep using it"
      end

      post study_service_keep_path(@study), as: :json
      assert_equal true, response.parsed_body["kept"]
      get study_path(@study)
      assert_select ".ps-service-reset[data-service-reset-dismissed-for-value='2026-11-22']"
      get root_path
      assert_select ".hm-sunday:not(.is-plan) .hm-sunday-title", text: "Psalms 4"
    end
  end

  test "Start fresh archives the queue; a replay is harmless; Undo brings it back" do
    serve!
    travel_to monday do
      post study_service_start_fresh_path(@study), params: { key: "tmp-fresh-abc123", served_on: "2026-11-22" }, as: :json
      assert_response :success
      body = response.parsed_body
      assert_equal "Service · 22 Nov 2026", body["name"]
      archive = Study.find(body["archive_id"])
      assert_equal 2, archive.setlist_items.count
      assert_equal 0, @study.setlist_items.count

      post study_service_start_fresh_path(@study), params: { key: "tmp-fresh-abc123", served_on: "2026-11-22" }, as: :json
      assert_equal archive.id, response.parsed_body["archive_id"]
      assert_equal 1, Study.archived.count

      # The archived copy is a past service — not on Home's lists, not This Sunday.
      get root_path
      assert_select ".hm-study .nm", text: "Service · 22 Nov 2026", count: 0
      assert_select ".ui-study-link .nm", text: "Service · 22 Nov 2026", count: 0
      get services_path
      assert_select ".sv-row .sv-name", text: "Service · 22 Nov 2026"
      # The archived copy itself never offers Start fresh.
      get study_path(archive)
      assert_select ".ps-service-reset", 0

      post study_service_undo_path(@study), params: { key: "tmp-fresh-abc123" }, as: :json
      assert_equal true, response.parsed_body["restored"]
      assert_equal [ "Psalm 4:1", "Abide with Me" ], response.parsed_body["items"].map { |i| i["reference"] || i["title"] }
      assert_equal Date.new(2026, 11, 22), @study.reload.served_on
      assert_not Study.exists?(archive.id)
    end
  end

  test "Start fresh needs a proper key; an archived copy can't be started fresh" do
    post study_service_start_fresh_path(@study), params: { key: "x" }, as: :json
    assert_response :unprocessable_entity
    archive = @study.start_fresh!(key: "tmp-direct-key")
    post study_service_start_fresh_path(archive), params: { key: "tmp-another-key" }, as: :json
    assert_response :not_found
  end

  test "Past services lists services newest first, with Open and Reuse" do
    serve!
    older = @user.studies.create!(name: "Easter", pane_count: 1, last_served_at: Time.utc(2026, 4, 5, 9))
    @user.studies.create!(name: "Never served", pane_count: 1)
    travel_to monday do
      get services_path
      assert_response :success
      assert_select ".sv-row .sv-name", count: 2
      assert_select ".sv-row:first-child .sv-name", text: "Psalms 4"
      assert_select ".sv-row:first-child .sv-meta", text: /Sunday 22 November 2026 · 2 items/
      assert_select ".sv-row:last-child .sv-name", text: "Easter"
      assert_select ".sv-row:first-child a.sv-open[href=?]", study_path(@study, queue: 1)
      assert_select ".sv-row:last-child form[action=?] input[name=from][value=?]", services_path, older.id.to_s
      assert_select ".ui-menu-item[href=?]", services_path
      get more_path # the More tab (and the apps' More)
      assert_select ".ui-menu-item[href=?]", services_path, text: /Past services/
    end
  end

  # An operator checking right after the service looked for it here ("it's
  # not showing what I did today") — today's service is listed, marked Today.
  test "today's service is listed too, marked Today" do
    serve!
    travel_to sunday + 1.hour do
      get services_path
      assert_select ".sv-row", 1
      assert_select ".sv-row[data-study-id=?][data-served-on=?]", @study.id.to_s, "2026-11-22"
      assert_select ".sv-row .sv-name", text: /Psalms 4/
      assert_select ".sv-row .sv-tag", text: "Today"
      assert_select ".sv-empty[hidden]"
    end
    travel_to monday do
      get services_path
      assert_select ".sv-row .sv-tag", 0 # yesterday's is just a past service
    end
  end

  test "with no services the empty note shows" do
    get services_path
    assert_select ".sv-list[hidden]"
    assert_select ".sv-empty:not([hidden])"
  end

  test "the study page tells the queue its name (for a service projected offline)" do
    get study_path(@study)
    assert_select "[data-setlist-study-name-value=?]", "Psalms 4"
  end

  test "Past services needs an account" do
    sign_out
    get services_path
    assert_redirected_to new_session_path
  end
end
