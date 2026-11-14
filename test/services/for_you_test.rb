require "test_helper"
require_relative "../test_helpers/today_seed"

class ForYouTest < ActiveSupport::TestCase
  include TodaySeed

  setup do
    seed_today!
    @user = users(:one)
    @study = @user.studies.create!(name: "Luke", pane_count: 1)
    @study.panes.first.update!(reference: "Luke 1")
  end

  def cards(plan: nil, terms: FaithTerm.reviewed.in_order.to_a)
    ForYou.call(studies: @user.studies.includes(:panes).to_a, terms:, active_plan: plan)
  end

  test "a glossary word tied to the book being read" do
    card = cards.find { |c| c.kind == :term }
    assert_equal "Grace", card.title
    assert_equal "You’ve been reading Luke", card.eyebrow
    assert_equal "/faith/grace", card.href
  end

  test "no matching word, no card — and drafts never count" do
    assert_nil cards(terms: []).find { |c| c.kind == :term }
    @grace.update!(key_references: [ "John 3:16" ])
    assert_nil cards.find { |c| c.kind == :term }
  end

  test "cross-references out of the last chapter, only when there are some" do
    assert_nil cards.find { |c| c.kind == :xrefs }
    3.times do |n|
      CrossReference.create!(from_book: @luke, from_chapter: 1, from_verse: 30 + n, to_book: @luke, to_chapter_start: 2, to_verse_start: n + 1, votes: 5)
    end
    card = cards.find { |c| c.kind == :xrefs }
    assert_equal "Luke 1 is linked to 3 passages", card.title
  end

  test "a plan through the book being read, only without a plan" do
    card = cards.find { |c| c.kind == :plan }
    assert_equal({ name: "Luke in 24 days", template: "book", book: "Luke", chapters_per_day: 1 }, card.plan_params)
    plan = @user.reading_plans.create!(name: "Mine", start_date: Date.current)
    assert_nil cards(plan:).find { |c| c.kind == :plan }
  end

  test "nothing read: no term or cross-reference card" do
    @study.panes.first.update!(reference: "")
    assert_equal [], cards.map(&:kind) - [ :plan ]
  end
end
