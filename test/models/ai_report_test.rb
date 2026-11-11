require "test_helper"

class AiReportTest < ActiveSupport::TestCase
  test "kind must be a known AI surface" do
    assert AiReport.new(kind: "rabbi").valid?
    assert_not AiReport.new(kind: "notes").valid?
  end

  test "context and excerpt are trimmed to their limits" do
    report = AiReport.new(kind: "rabbi", context: "  a  b  " + "c" * 500, excerpt: "x" * 5000)
    assert report.context.start_with?("a b c")
    assert_operator report.context.length, :<=, AiReport::CONTEXT_LIMIT
    assert_equal AiReport::EXCERPT_LIMIT, report.excerpt.length
  end

  test "recent lists newest first" do
    old = AiReport.create!(kind: "rabbi", created_at: 2.days.ago)
    new = AiReport.create!(kind: "prayer")
    assert_equal [ new, old ], AiReport.recent.where(id: [ old.id, new.id ]).to_a
  end
end
