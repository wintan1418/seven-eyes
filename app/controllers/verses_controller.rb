class VersesController < ApplicationController
  allow_unauthenticated_access only: %i[ count check ]

  # Parse a typed reference (preach-mode quick chase). The operator validates
  # what the preacher called out BEFORE the projected pane is touched, so a
  # misheard reference can never put an error page on the big screen.
  def check
    parsed = ReferenceParser.call(params[:q].to_s)
    return render(json: { ok: false }) unless parsed.valid? && Book.find_by_osis(parsed.osis)

    render json: {
      ok: true,
      osis: parsed.osis,
      chapter: parsed.chapter,
      verse_start: parsed.verse_start,
      chapter_reference: "#{parsed.book_name} #{parsed.chapter}",
      label: parsed.label
    }
  end

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
