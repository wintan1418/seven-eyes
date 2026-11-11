require "test_helper"

class AiReportsTest < ActionDispatch::IntegrationTest
  test "a member reports an AI answer and sees thanks in the same frame" do
    sign_in_as users(:one)

    assert_difference -> { AiReport.count }, 1 do
      post ai_reports_path, params: { kind: "rabbi", frame: "ai_report_rabbi_12",
                                      context: "John 3:16 — God so loved", excerpt: "The plain love of God." }
    end

    assert_response :success
    assert_select "turbo-frame#ai_report_rabbi_12", text: /reported/
    report = AiReport.last
    assert_equal users(:one), report.user
    assert_equal "rabbi", report.kind
    assert_equal "The plain love of God.", report.excerpt
  end

  test "a guest can report a prayer on a public passage page" do
    assert_difference -> { AiReport.where(user: nil).count }, 1 do
      post ai_reports_path, params: { kind: "prayer", frame: "ai_report_prayer", context: "John 3", excerpt: "Father…" }
    end
    assert_response :success
  end

  test "unknown kinds are refused and odd frame ids are not echoed" do
    assert_no_difference -> { AiReport.count } do
      post ai_reports_path, params: { kind: "nonsense", excerpt: "x" }
    end
    assert_response :unprocessable_entity

    post ai_reports_path, params: { kind: "rabbi", frame: "x\"><script>" }
    assert_select "turbo-frame#ai_report"
    assert_not_includes response.body, "<script>"
  end

  test "an admin sees reports on the overview" do
    AiReport.create!(kind: "illustration", context: "John 3", excerpt: "A shepherd at dusk")
    users(:one).update!(admin: true)
    sign_in_as users(:one)
    get admin_path
    assert_includes response.body, "A shepherd at dusk"
  end

  test "deleting an account deletes its reports" do
    report = AiReport.create!(user: users(:one), kind: "rabbi", excerpt: "x")
    AccountDeletion.call(users(:one))
    assert_not AiReport.exists?(report.id)
  end
end
