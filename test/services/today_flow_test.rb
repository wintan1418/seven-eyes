require "test_helper"
require_relative "../test_helpers/today_seed"

class TodayFlowTest < ActiveSupport::TestCase
  include TodaySeed

  setup { seed_today! }

  test "six steps from the day's word, with the verses around it marked" do
    flow = TodayFlow.new(@word)
    assert_equal %i[ verse passage reflection word prayer amen ], flow.steps
    numbers = flow.passage.map(&:number)
    assert_includes numbers, 37
    assert numbers.size.between?(5, 10)
    assert_equal [ 37 ], flow.passage.select(&:focus).map(&:number)
    assert_equal "Luke 1:#{numbers.first}–#{numbers.last}", flow.passage_label
    assert_equal 5, flow.minutes
  end

  test "the word of the faith is reviewed-only for readers; reviewers may get drafts" do
    flow = TodayFlow.new(@word)
    assert_equal @grace, flow.term
    assert_equal "χάρις", flow.root.lemma
    assert_equal "grace, favour, thanks", flow.root_meaning

    FaithTerm.where(status: :reviewed).update_all(status: :draft)
    assert_nil TodayFlow.new(@word).term
    assert_not_includes TodayFlow.new(@word).steps, :word

    reviewer = users(:one).tap { |u| u.update!(reviewer: true) }
    assert TodayFlow.new(@word, viewer: reviewer).term.present?
  end

  test "steps with nothing to show are left out" do
    @word.update!(reflection: nil, prayer: nil)
    assert_equal %i[ verse passage word amen ], TodayFlow.new(@word).steps
  end

  test "a long reading keeps the passage to ten verses" do
    @word.update!(verse_start: 33, verse_end: 41, reference: "Luke 1:33-41")
    flow = TodayFlow.new(@word)
    assert_operator flow.passage.size, :<=, TodayFlow::MAX_VERSES
    assert_equal (33..41).to_a, flow.passage.select(&:focus).map(&:number)
  end
end
