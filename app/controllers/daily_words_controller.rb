# Public "Word for Today" pages: /today, /today/YYYY-MM-DD for past days, and
# the JSON the share-as-image modal reads (card + prayer). Never shows a date
# after today (Africa/Lagos), and never creates a word for any day but today.
class DailyWordsController < ApplicationController
  allow_unauthenticated_access

  before_action :set_word, only: %i[ card prayer ]

  def show
    @word = params[:date] ? published_word(params[:date]) : DailyWord.today
    return render(:not_found, status: :not_found) if params[:date] && @word.nil?

    @archive = DailyWord.published.newest_first.where.not(id: @word&.id).limit(DailyWord::ARCHIVE_SIZE)
  end

  # Same shape as StudiesController#share_card, so the share modal draws it.
  def card
    render json: {
      reference: @word.reference, translation: translation_name, translation_code: @word.translation_code,
      osis: @word.osis_code, chapter: @word.chapter, text: @word.verse_text, slug: @word.slug,
      url: daily_word_url(@word)
    }
  end

  # The share modal's "Prayer" tab shows this day's prayer.
  def prayer
    render json: {
      ok: @word.prayer.present?, reference: @word.reference, prayer: @word.prayer,
      error: (@word.prayer.present? ? nil : "unavailable"), url: daily_word_url(@word)
    }
  end

  private

  def published_word(value)
    date = Date.iso8601(value.to_s)
    DailyWord.published.find_by(date:)
  rescue Date::Error
    nil
  end

  def set_word
    @word = published_word(params[:date])
    head :not_found unless @word
  end

  def translation_name
    Translation.find_by(code: @word.translation_code)&.name || @word.translation_code
  end
end
