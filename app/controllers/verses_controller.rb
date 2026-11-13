class VersesController < ApplicationController
  allow_unauthenticated_access only: %i[ count check chapter passage ]

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

  # The whole chapter a typed reference sits in, as JSON — the preach queue's
  # Preview and EasyWorship-style verse list when the translation isn't
  # downloaded to the device (they read the downloaded Bible first).
  def chapter
    parsed = ReferenceParser.call(params[:q].to_s)
    book = parsed.valid? && Book.find_by_osis(parsed.osis)
    return render(json: { ok: false }) unless book

    translation = Translation.available.find_by(id: params[:translation].presence) || Translation.default
    verses = Verse.where(translation:, book:, chapter: parsed.chapter).ordered.pluck(:chapter, :verse_number, :text)
    render json: {
      ok: true, osis: parsed.osis, chapter: parsed.chapter, label: parsed.label,
      chapter_reference: "#{parsed.book_name} #{parsed.chapter}",
      verse_start: parsed.verse_start, verse_end: parsed.verse_end,
      translation: translation&.code,
      verses: verses.map { |c, n, t| { chapter: c, num: n, text: t } }
    }
  end

  # The words of a reference in one translation (by code), as JSON — the
  # scripture slide composer when that Bible isn't downloaded to the device.
  # Capped so a careless "Psalm 1-150" can't pull a whole book.
  PASSAGE_MAX_VERSES = 80

  def passage
    parsed = ReferenceParser.call(params[:q].to_s)
    book = parsed.valid? && Book.find_by_osis(parsed.osis)
    return render(json: { ok: false, error: "unknown_reference" }) unless book

    code = params[:translation].to_s
    translation = code.present? ? Translation.available.find_by("LOWER(translations.code) = ?", code.downcase) : Translation.default
    return render(json: { ok: false, error: "unknown_translation" }) unless translation

    verses = Verse.passage(translation:, book:, **parsed.passage_args).limit(PASSAGE_MAX_VERSES).pluck(:chapter, :verse_number, :text)
    render json: {
      ok: true, label: parsed.label, osis: parsed.osis, translation: translation.code,
      verses: verses.map { |c, n, t| { c: c, n: n, text: t } }
    }
  end

  # How many verses a chapter has, so the Bible browser can offer a verse grid.
  def count
    book = Book.find_by_osis(params[:osis])
    return render(json: { count: 0 }) unless book

    translation = Translation.available.find_by(code: params[:translation].presence) || Translation.default
    max = Verse.where(translation: translation, book: book, chapter: params[:chapter].to_i)
               .maximum(:verse_number) || 0
    render json: { count: max }
  end
end
