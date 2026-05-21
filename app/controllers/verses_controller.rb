class VersesController < ApplicationController
  allow_unauthenticated_access only: %i[ count ]

  # How many verses a chapter has, so the Bible browser can offer a verse grid.
  def count
    book = Book.find_by_osis(params[:osis])
    return render(json: { count: 0 }) unless book

    translation = Translation.find_by(code: params[:translation].presence) || Translation.first
    max = Verse.where(translation: translation, book: book, chapter: params[:chapter].to_i)
               .maximum(:verse_number) || 0
    render json: { count: max }
  end
end
