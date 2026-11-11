# Composes a Word for Today's reflection and prayer off the request path.
#
#   DailyWordJob.perform_later(word.id) — enqueued by DailyWord#request_composition,
#     which has already claimed the word, so this just composes.
#   DailyWordJob.perform_later — no id: the early-morning recurring run
#     (config/recurring.yml). It creates today's word and composes it, so the
#     first reader of the day already sees the reflection.
class DailyWordJob < ApplicationJob
  queue_as :default

  def perform(daily_word_id = nil)
    if daily_word_id
      DailyWord.find_by(id: daily_word_id)&.compose!
    else
      word = DailyWord.ensure_for(DailyWord.today_date)
      word.compose! if word&.claim_composition
    end
  end
end
