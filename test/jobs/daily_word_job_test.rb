require "test_helper"

class DailyWordJobTest < ActiveJob::TestCase
  setup do
    kjv = Translation.create!(code: "KJV", name: "King James Version")
    DailyWord::REFERENCES.first(3).each_with_index do |ref, i|
      parsed = ReferenceParser.call(ref)
      book = Book.find_by_osis(parsed.osis) ||
             Book.create!(osis_code: parsed.osis, name: parsed.book_name, testament: :new, position: 100 + i, chapter_count: 150)
      Verse.create!(translation: kjv, book:, chapter: parsed.chapter, verse_number: parsed.verse_start, text: "Text #{ref}")
    end
    @original = DailyWordComposer.method(:call)
    DailyWordComposer.define_singleton_method(:call) do |_word|
      DailyWordJobTest.calls += 1
      DailyWordComposer::Result.new(ok: true, reflection: "A reflection.", prayer: "A prayer. Amen.")
    end
    self.class.calls = 0
  end

  teardown { DailyWordComposer.define_singleton_method(:call, @original) }

  class << self
    attr_accessor :calls
  end

  test "the morning run creates and composes today's word once" do
    DailyWordJob.perform_now
    DailyWordJob.perform_now
    word = DailyWord.find_by(date: DailyWord.today_date)
    assert word.composed?
    assert_equal 1, self.class.calls
  end

  test "an enqueued word is composed" do
    word = DailyWord.ensure_for(DailyWord.today_date)
    DailyWordJob.perform_now(word.id)
    assert_equal "A reflection.", word.reload.reflection
  end
end
